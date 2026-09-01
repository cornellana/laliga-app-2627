const http2  = require('node:http2');
const jwt    = require('jsonwebtoken');
const fs     = require('fs');

const BUNDLE_ID = process.env.APNS_BUNDLE_ID;
const KEY_ID    = process.env.APNS_KEY_ID;
const TEAM_ID   = process.env.APNS_TEAM_ID;

// Acepta la clave .p8 en tres formatos (en orden de precedencia):
//  1. APNS_KEY_PATH  → ruta al archivo .p8 montado en el contenedor
//  2. APNS_KEY_B64   → contenido del .p8 en base64 (sin problemas de multilínea en .env)
//  3. APNS_KEY       → contenido del .p8 con \n literales
function loadKey() {
  if (process.env.APNS_KEY_PATH) {
    return fs.readFileSync(process.env.APNS_KEY_PATH, 'utf8');
  }
  if (process.env.APNS_KEY_B64) {
    return Buffer.from(process.env.APNS_KEY_B64, 'base64').toString('utf8');
  }
  if (process.env.APNS_KEY) {
    return process.env.APNS_KEY.replace(/\\n/g, '\n');
  }
  throw new Error('APNs key not configured (set APNS_KEY_PATH, APNS_KEY_B64 or APNS_KEY)');
}

let APNS_KEY;
try { APNS_KEY = loadKey(); } catch (e) { console.warn('[apns]', e.message); }

// Cache del JWT (válido ~50 min; APNs lo acepta hasta ~60 min)
let jwtCache = { token: null, issuedAt: 0 };

function getJWT() {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && (now - jwtCache.issuedAt) < 2900) return jwtCache.token;
  const token = jwt.sign({ iss: TEAM_ID }, APNS_KEY, {
    algorithm: 'ES256',
    keyid:     KEY_ID,
  });
  jwtCache = { token, issuedAt: now };
  return token;
}

// Pool de conexiones HTTP/2 por entorno
const clients = {};

function getClient(environment) {
  const host = environment === 'production'
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';

  if (!clients[environment] || clients[environment].destroyed) {
    clients[environment] = http2.connect(host);
    clients[environment].on('error', err => {
      console.error(`[apns] HTTP/2 session error (${environment}):`, err.message);
      clients[environment] = null;
    });
  }
  return clients[environment];
}

function sendPush(deviceToken, environment, title, body) {
  return new Promise((resolve, reject) => {
    if (!APNS_KEY) return reject(new Error('APNs key not loaded'));

    const client  = getClient(environment);
    const payload = JSON.stringify({ aps: { alert: { title, body }, sound: 'default' } });

    const req = client.request({
      ':method':       'POST',
      ':path':         `/3/device/${deviceToken}`,
      'authorization': `bearer ${getJWT()}`,
      'apns-topic':    BUNDLE_ID,
      'apns-push-type':'alert',
      'apns-priority': '10',
      'content-type':  'application/json',
      'content-length': Buffer.byteLength(payload),
    });

    req.write(payload);
    req.end();

    // Resuelve DENTRO del handler :response para garantizar que
    // statusCode esté disponible antes de que llegue el 'end' del body
    req.on('response', headers => {
      const statusCode = headers[':status'];
      let body_data = '';
      req.on('data', d => { body_data += d; });
      req.on('end', () => {
        if (statusCode === 200) {
          resolve({ success: true });
        } else {
          let reason = '';
          try { reason = JSON.parse(body_data).reason; } catch {}
          resolve({ success: false, statusCode, reason });
        }
      });
    });
    req.on('error', reject);
    // Timeout de seguridad si APNs no responde en absoluto
    const timer = setTimeout(() => {
      req.destroy();
      resolve({ success: false, statusCode: 0, reason: 'timeout' });
    }, 10000);
    req.on('response', () => clearTimeout(timer));
  });
}

module.exports = { sendPush };
