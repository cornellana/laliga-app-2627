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

// Datos servidos en directo, para que las apps no dependan de la CDN de
// GitHub, que cachea unos cinco minutos. Aquí llegan segundos después de que
// los contenedores actualizadores los generen.
//
// La lista de ficheros es CERRADA a propósito: nada de rutas libres ni de
// servir un directorio entero. Cada entrada dice de qué carpeta sale, porque
// cada competición tiene su propio actualizador y su propio volumen.
const FICHEROS = {
  'laliga2627.json':    process.env.DATOS_DIR ?? '/app/publico',
  'champions2627.json': process.env.DATOS_CHAMPIONS_DIR ?? '/app/publico-champions',
};

// Si un actualizador lleva más de esto sin reescribir su fichero, algo le pasa.
// Reescriben en cada ciclo (60 s con partido, 10 min en reposo) aunque el
// contenido no cambie, así que la fecha del fichero es una señal de vida.
const DATOS_CADUCAN_MS = parseInt(process.env.DATOS_CADUCAN_MS ?? '1200000', 10);

app.get('/datos/:nombre', (req, res) => {
  const carpeta = FICHEROS[req.params.nombre];
  if (!carpeta) {
    return res.status(404).json({ error: 'fichero desconocido' });
  }

  const fichero = path.join(carpeta, req.params.nombre);
  fs.stat(fichero, (errStat, info) => {
    // Servir datos congelados sería peor que no servir nada: la app los
    // preferiría a los de GitHub, que en ese escenario sí estarían al día.
    // Con un 503 se va sola a la fuente de siempre.
    if (errStat) {
      console.error(`[datos] ${req.params.nombre} no disponible:`, errStat.message);
      return res.status(503).json({ error: 'datos no disponibles' });
    }
    const antiguedad = Date.now() - info.mtimeMs;
    if (antiguedad > DATOS_CADUCAN_MS) {
      console.error(`[datos] ${req.params.nombre} caducado: `
        + `${Math.round(antiguedad / 60000)} min sin refrescarse`);
      return res.status(503).json({ error: 'datos caducados', minutos: Math.round(antiguedad / 60000) });
    }
    fs.readFile(fichero, (err, contenido) => {
      if (err) {
        console.error(`[datos] ${req.params.nombre} no se pudo leer:`, err.message);
        return res.status(503).json({ error: 'datos no disponibles' });
      }
      res.set('Cache-Control', 'no-cache, must-revalidate');
      res.type('application/json').send(contenido);
    });
  });
});

// Alta y baja de avisos. Cada app llama a su ruta y queda apuntada con su
// competición; el sondeador solo le manda los partidos de esa. Las rutas de La
// Liga son las de siempre, sin el prefijo, para no tocar la app que ya está
// repartida.
function registrar(competition) {
  return (req, res) => {
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
    }, competition);

    console.log(`[register] ${competition} ...${deviceToken.slice(-8)} env=${environment} teams=[${teams.join(', ')}]`);
    res.json({ ok: true });
  };
}

function desregistrar(req, res) {
  const { deviceToken } = req.body ?? {};
  if (!TOKEN_RE.test(deviceToken))
    return res.status(400).json({ error: 'invalid deviceToken' });
  store.deleteSubscription(deviceToken);
  console.log(`[unregister] ...${deviceToken.slice(-8)}`);
  res.json({ ok: true });
}

app.post('/register',             registrar('esp.1'));
app.post('/unregister',           desregistrar);
app.post('/champions/register',   registrar('uefa.champions'));
app.post('/champions/unregister', desregistrar);

// Captura errores no manejados — devuelve JSON en vez de traza completa
app.use((err, _req, res, _next) => {
  console.error('[server] unhandled error:', err.message);
  res.status(500).json({ error: 'internal server error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[server] escuchando en :${PORT}`);
  startPoller();
});
