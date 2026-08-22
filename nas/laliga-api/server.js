const express = require('express');
const fs      = require('fs');
const path    = require('path');
const store   = require('./store');
const { start: startPoller } = require('./poller');

const PORT = parseInt(process.env.PORT ?? '8090', 10);
const app   = express();
app.use(express.json());

// deviceToken válido: hex de 64 caracteres
const TOKEN_RE = /^[0-9a-f]{64}$/i;

app.get('/health', (_req, res) => {
  try {
    store.checkDb();
    res.json({ status: 'ok', ts: Date.now() });
  } catch (err) {
    console.error('[health] DB error:', err.message);
    res.status(503).json({ status: 'error', reason: err.message });
  }
});

// Datos de La Liga servidos en directo, para que la app no dependa de la CDN
// de GitHub, que cachea unos cinco minutos. Aquí llegan segundos después de que
// el contenedor laliga-updater los genere. Es solo lectura de un único fichero
// conocido: nada de rutas libres ni de servir el directorio entero.
const DATOS_DIR = process.env.DATOS_DIR ?? '/app/publico';

// Si el actualizador lleva más de esto sin reescribir el fichero, algo le pasa.
// Reescribe en cada ciclo (60 s con partido, 10 min en reposo) aunque el
// contenido no cambie, así que la fecha del fichero es una señal de vida fiable.
const DATOS_CADUCAN_MS = parseInt(process.env.DATOS_CADUCAN_MS ?? '1200000', 10);

app.get('/datos/laliga2627.json', (_req, res) => {
  const fichero = path.join(DATOS_DIR, 'laliga2627.json');
  fs.stat(fichero, (errStat, info) => {
    // Servir datos congelados sería peor que no servir nada: la app los
    // preferiría a los de GitHub, que en ese escenario sí estarían al día.
    // Con un 503 se va sola a la fuente de siempre.
    if (errStat) {
      console.error('[datos] no disponible:', errStat.message);
      return res.status(503).json({ error: 'datos no disponibles' });
    }
    const antiguedad = Date.now() - info.mtimeMs;
    if (antiguedad > DATOS_CADUCAN_MS) {
      console.error(`[datos] caducados: ${Math.round(antiguedad / 60000)} min sin refrescarse`);
      return res.status(503).json({ error: 'datos caducados', minutos: Math.round(antiguedad / 60000) });
    }
    fs.readFile(fichero, (err, contenido) => {
      if (err) {
        console.error('[datos] no se pudo leer:', err.message);
        return res.status(503).json({ error: 'datos no disponibles' });
      }
      res.set('Cache-Control', 'no-cache, must-revalidate');
      res.type('application/json').send(contenido);
    });
  });
});

app.post('/register', (req, res) => {
  const { deviceToken, environment, teams, prefs } = req.body ?? {};

  if (!TOKEN_RE.test(deviceToken))
    return res.status(400).json({ error: 'invalid deviceToken' });
  if (!['sandbox', 'production'].includes(environment))
    return res.status(400).json({ error: 'invalid environment' });
  if (!Array.isArray(teams) || teams.length === 0 || teams.some(t => typeof t !== 'string'))
    return res.status(400).json({ error: 'teams must be non-empty string[]' });
  if (!prefs || typeof prefs !== 'object')
    return res.status(400).json({ error: 'invalid prefs' });

  store.upsertSubscription(deviceToken, environment, teams, {
    enabled:   !!prefs.enabled,
    goals:     prefs.goals     !== false,
    penalties: prefs.penalties !== false,
    redCards:  prefs.redCards  !== false,
    startEnd:  prefs.startEnd  !== false,
  });

  console.log(`[register] ...${deviceToken.slice(-8)} env=${environment} teams=[${teams.join(', ')}]`);
  res.json({ ok: true });
});

app.post('/unregister', (req, res) => {
  const { deviceToken } = req.body ?? {};
  if (!TOKEN_RE.test(deviceToken))
    return res.status(400).json({ error: 'invalid deviceToken' });
  store.deleteSubscription(deviceToken);
  console.log(`[unregister] ...${deviceToken.slice(-8)}`);
  res.json({ ok: true });
});

// Captura errores no manejados — devuelve JSON en vez de traza completa
app.use((err, _req, res, _next) => {
  console.error('[server] unhandled error:', err.message);
  res.status(500).json({ error: 'internal server error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[server] escuchando en :${PORT}`);
  startPoller();
});
