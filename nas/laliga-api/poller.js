const store = require('./store');
const { sendPush } = require('./apns');
const { teamMatches } = require('./teamMatches');
const { championsTeamMatches } = require('./championsTeams');

// ESPN sustituye a SofaScore, que desde agosto de 2026 devuelve 403 a IPs
// residenciales (verificado desde el propio contenedor).
//
// Cada competición lleva su endpoint, el bundle id de la app a la que se
// envían los avisos (APNs exige que el topic sea el de la app dueña del token)
// y su forma de casar nombres. La de La Liga es exactamente la de siempre.
const ESPN = 'https://site.api.espn.com/apis/site/v2/sports/soccer';
const COMPETITIONS = {
  'esp.1': {
    base:    `${ESPN}/esp.1`,
    topic:   process.env.APNS_BUNDLE_ID,
    matches: teamMatches,
  },
  'uefa.champions': {
    base:    `${ESPN}/uefa.champions`,
    topic:   process.env.APNS_BUNDLE_ID_CHAMPIONS ?? 'com.cornellana.Champions',
    matches: championsTeamMatches,
  },
};
const UA   = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

// Ids de keyEvents de ESPN, verificados sobre 74 partidos reales de LaLiga.
// Los goles no tienen id fijo (70/97/98/137/138/173): se detectan con `scoringPlay`.
const TYPE_YELLOW      = '94';
const TYPE_RED         = '93';   // ojo: no es 95/96, esos no existen en LaLiga
const TYPE_OWN_GOAL    = '97';
const TYPE_PENALTY     = '98';
const TYPE_PEN_MISSED  = ['114', '140'];  // parado / al palo

// Se usa `fetch` (undici) y NO node:https a propósito: ESPN devuelve 403 al
// cliente HTTP clásico de Node, independientemente de las cabeceras que se le
// pongan. Con fetch responde 200. Verificado desde el propio contenedor.
async function fetchJson(url) {
  const res = await fetch(url, {
    headers: { 'User-Agent': UA, 'Accept': 'application/json' },
    signal: AbortSignal.timeout(12000),
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`HTTP ${res.status} en ${url}`);
  try {
    return await res.json();
  } catch {
    throw new Error(`JSON parse error for ${url}`);
  }
}

async function sendSafe(deviceToken, environment, title, body, topic) {
  try {
    const result = await sendPush(deviceToken, environment, title, body, topic);
    if (!result.success) {
      console.warn(`[apns] failed ${result.statusCode} ${result.reason} → ...${deviceToken.slice(-8)}`);

      // Solo se borra lo que APNs da por muerto de verdad. `BadDeviceToken`
      // casi siempre significa "token del entorno equivocado", no token
      // caducado: borrarlo hacía que el dispositivo desapareciera de la BD,
      // se volviera a registrar al abrir la app y el fallo se repitiera en
      // bucle sin dejar rastro de cuál era el problema.
      if (result.statusCode === 410 || result.reason === 'Unregistered') {
        store.deleteSubscription(deviceToken);
        console.log(`[store] removed stale token ...${deviceToken.slice(-8)}`);
      } else if (result.reason === 'BadDeviceToken') {
        console.warn(`[apns] ...${deviceToken.slice(-8)} está registrado como `
          + `"${environment}" pero APNs lo rechaza: probable desajuste entre `
          + `aps-environment del build y el entorno declarado. Se conserva.`);
      }
    } else {
      console.log(`[apns] ✓ push sent → ...${deviceToken.slice(-8)} | ${title}`);
    }
  } catch (err) {
    console.error('[apns] sendSafe error:', err.message);
  }
}

// ── Parseo de keyEvents ───────────────────────────────────────────────────────
// ESPN devuelve `athlete` y a veces `team` a null: hay que sacarlos del texto.

function parseClock(display) {
  const clean = String(display ?? '').replace(/'/g, '').trim();
  if (!clean) return '?';
  return clean;  // conserva el formato "90+3" tal cual para el título
}

function playerFromText(text, typeId) {
  if (!text) return '';
  if (typeId === TYPE_OWN_GOAL) {
    const m = /^own goal by ([^,]+),/i.exec(text);
    return m ? m[1].trim() : '';
  }
  if (typeId === TYPE_YELLOW || typeId === TYPE_RED) {
    const i = text.indexOf('(');
    return i > 0 ? text.slice(0, i).trim() : '';
  }
  // Goles y penaltis fallados: llevan el marcador delante, el jugador va después
  const parts = text.split('. ');
  if (parts.length > 1) {
    const rest = parts.slice(1).join('. ');
    const i = rest.indexOf('(');
    if (i > 0) return rest.slice(0, i).trim();
  }
  return '';
}

function teamFromText(text, typeId) {
  if (!text) return null;
  if (typeId === TYPE_YELLOW || typeId === TYPE_RED) {
    const m = /\(([^)]+)\)/.exec(text);
    if (m) return m[1];
  }
  return null;
}

function resolveTeam(name, home, away) {
  if (!name) return null;
  if (teamMatches(name, home)) return home;
  if (teamMatches(name, away)) return away;
  return name;
}

/** Convierte un keyEvent de ESPN en un aviso, o null si no interesa. */
function toNotification(ev, ctx) {
  const typeId  = String(ev.type?.id ?? '');
  const isGoal  = ev.scoringPlay === true;
  const text    = ev.text ?? '';
  const minute  = parseClock(ev.clock?.displayValue);
  const player  = playerFromText(text, typeId);
  const rawTeam = teamFromText(text, typeId) ?? ev.team?.displayName ?? null;
  const team    = resolveTeam(rawTeam, ctx.home, ctx.away) ?? '';
  const score   = `${ctx.home} ${ctx.homeScore}-${ctx.awayScore} ${ctx.away}`;

  if (isGoal) {
    if (typeId === TYPE_OWN_GOAL || /^own goal/i.test(text)) {
      return { prefKey: 'goals', title: `⚽ En propia meta (${minute}')`, body: `${player} · ${score}` };
    }
    if (typeId === TYPE_PENALTY) {
      return { prefKey: 'penalties', title: `⚽ Gol de penalti (${minute}')`, body: `${player} · ${score}` };
    }
    return { prefKey: 'goals', title: `⚽ GOL (${minute}')`, body: `${player} · ${score}` };
  }

  if (typeId === TYPE_RED) {
    return { prefKey: 'redCards', title: `🟥 Expulsión (${minute}')`,
             body: `${player} · ${team} · ${ctx.homeScore}-${ctx.awayScore}` };
  }

  if (TYPE_PEN_MISSED.includes(typeId)) {
    return { prefKey: 'penalties', title: `❌ Penalti fallado (${minute}')`,
             body: `${player} · ${team} · ${ctx.homeScore}-${ctx.awayScore}` };
  }

  return null;
}

// ── Ciclo de sondeo ───────────────────────────────────────────────────────────

/** Devuelve YYYYMMDD de hoy y de ayer en UTC (un partido nocturno cruza el día). */
function scoreboardDates() {
  const now = Date.now();
  return [now, now - 86400000].map(ms =>
    new Date(ms).toISOString().slice(0, 10).replace(/-/g, '')
  );
}

async function fetchTodaysEvents(base) {
  const seen = new Map();
  for (const date of scoreboardDates()) {
    const data = await fetchJson(`${base}/scoreboard?dates=${date}`);
    for (const ev of data?.events ?? []) {
      if (!seen.has(ev.id)) seen.set(ev.id, ev);
    }
  }
  return [...seen.values()];
}

// En el primer ciclo tras arrancar, los partidos YA terminados se marcan como
// vistos sin notificar. Evita la ráfaga de avisos atrasados al migrar desde
// SofaScore (cuyos ids de evento eran distintos) o al recrear la BD. Los
// partidos en juego se procesan con normalidad, así que un reinicio a media
// primera parte no se pierde ningún gol.
let firstCycle = true;

/** Un ciclo de una competición. Un fallo aquí no debe parar a la otra. */
async function pollCompetition(id, cfg, allSubsEnabled) {
  try {
    const events = await fetchTodaysEvents(cfg.base);

    // 'pre' aún no empezado | 'in' en juego | 'post' terminado
    const active = events.filter(e => {
      const state = e.competitions?.[0]?.status?.type?.state;
      return state === 'in' || state === 'post';
    });
    if (active.length === 0) return;

    // Solo las suscripciones de ESTA competición: un token de la Orejona no
    // debe recibir goles de La Liga ni al revés.
    const allSubs = allSubsEnabled.filter(s => s.competition === id);
    if (allSubs.length === 0) return;

    for (const event of active) {
      const comp  = event.competitions[0];
      const state = comp.status?.type?.state;
      const eventId = Number(event.id);

      const competitors = comp.competitors ?? [];
      const homeC = competitors.find(c => c.homeAway === 'home');
      const awayC = competitors.find(c => c.homeAway === 'away');
      const home  = homeC?.team?.displayName ?? '';
      const away  = awayC?.team?.displayName ?? '';
      const ctx = {
        home, away,
        homeScore: Number(homeC?.score ?? 0),
        awayScore: Number(awayC?.score ?? 0),
      };

      // Partido ya acabado antes de que arrancásemos: se registra en silencio
      const silent = firstCycle && state === 'post';

      // Suscripciones con un equipo implicado. No se hace continue si está vacío:
      // hay que marcar los incidentes como vistos igualmente para evitar duplicados.
      const intSubs = silent ? [] : allSubs.filter(sub =>
        sub.teams.some(t => cfg.matches(home, t) || cfg.matches(away, t))
      );

      // ── Inicio / final ──────────────────────────────────────────────
      const statusKey = `status_${state}`;
      if (!store.hasSeenIncident(eventId, statusKey)) {
        store.markIncidentSeen(eventId, statusKey);
        const title = state === 'in' ? '⚽ Partido comenzado' : '🏁 Partido terminado';
        const body  = state === 'in'
          ? `${home} - ${away}`
          : `${home} ${ctx.homeScore}-${ctx.awayScore} ${away}`;
        for (const sub of intSubs) {
          if (sub.prefs.startEnd) await sendSafe(sub.deviceToken, sub.environment, title, body, cfg.topic);
        }
      }

      // ── Incidentes ──────────────────────────────────────────────────
      // De los terminados se pide el resumen una única vez, para recoger los
      // últimos goles sin reconsultarlos indefinidamente el resto del día.
      const finalKey = 'final_processed';
      if (state === 'post' && store.hasSeenIncident(eventId, finalKey)) continue;

      const summary = await fetchJson(`${cfg.base}/summary?event=${event.id}`);
      if (state === 'post') store.markIncidentSeen(eventId, finalKey);
      if (!summary) continue;

      for (const [idx, ev] of (summary.keyEvents ?? []).entries()) {
        const incId = `${ev.id ?? 'x'}_${idx}`;
        if (store.hasSeenIncident(eventId, incId)) continue;
        store.markIncidentSeen(eventId, incId);

        const note = toNotification(ev, ctx);
        if (!note) continue;

        for (const sub of intSubs) {
          if (sub.prefs[note.prefKey]) {
            await sendSafe(sub.deviceToken, sub.environment, note.title, note.body, cfg.topic);
          }
        }
      }
    }

  } catch (err) {
    console.error(`[poller] error en ${id}:`, err.message || err);
  }
}

async function poll() {
  // Se leen una vez por ciclo y se reparten; las suscripciones no cambian a
  // mitad de un sondeo y así no se abre la base de datos dos veces.
  const allSubsEnabled = store.getAllSubscriptions().filter(s => s.prefs.enabled);
  for (const [id, cfg] of Object.entries(COMPETITIONS)) {
    await pollCompetition(id, cfg, allSubsEnabled);
  }
  store.pruneOldIncidents();
  firstCycle = false;
}

const INTERVAL = parseInt(process.env.POLL_INTERVAL_MS ?? '30000', 10);

function start() {
  console.log(`[poller] iniciado (ESPN: ${Object.keys(COMPETITIONS).join(', ')}), intervalo=${INTERVAL}ms`);
  poll();
  setInterval(poll, INTERVAL);
}

module.exports = { start, toNotification, poll };
