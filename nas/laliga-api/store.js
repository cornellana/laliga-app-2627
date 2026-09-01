const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const DB_DIR = process.env.DB_PATH
  ? path.dirname(process.env.DB_PATH)
  : path.join(__dirname, 'data');
const DB_FILE = process.env.DB_PATH || path.join(DB_DIR, 'laliga.db');

fs.mkdirSync(DB_DIR, { recursive: true });

const db = new Database(DB_FILE);
db.pragma('journal_mode = DELETE');

db.exec(`
  CREATE TABLE IF NOT EXISTS subscriptions (
    device_token TEXT PRIMARY KEY,
    environment  TEXT NOT NULL,
    teams        TEXT NOT NULL,
    prefs        TEXT NOT NULL,
    updated_at   INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS seen_incidents (
    event_id    INTEGER NOT NULL,
    incident_id TEXT    NOT NULL,
    PRIMARY KEY (event_id, incident_id)
  );
`);

function upsertSubscription(deviceToken, environment, teams, prefs) {
  db.prepare(`
    INSERT INTO subscriptions (device_token, environment, teams, prefs, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(device_token) DO UPDATE SET
      environment = excluded.environment,
      teams       = excluded.teams,
      prefs       = excluded.prefs,
      updated_at  = excluded.updated_at
  `).run(deviceToken, environment, JSON.stringify(teams), JSON.stringify(prefs), Date.now());
}

function deleteSubscription(deviceToken) {
  db.prepare('DELETE FROM subscriptions WHERE device_token = ?').run(deviceToken);
}

function getAllSubscriptions() {
  return db.prepare('SELECT * FROM subscriptions').all().map(row => ({
    deviceToken: row.device_token,
    environment: row.environment,
    teams:       JSON.parse(row.teams),
    prefs:       JSON.parse(row.prefs),
  }));
}

function hasSeenIncident(eventId, incidentId) {
  return !!db.prepare(
    'SELECT 1 FROM seen_incidents WHERE event_id = ? AND incident_id = ?'
  ).get(eventId, String(incidentId));
}

function markIncidentSeen(eventId, incidentId) {
  db.prepare(
    'INSERT OR IGNORE INTO seen_incidents (event_id, incident_id) VALUES (?, ?)'
  ).run(eventId, String(incidentId));
}

// Evita crecimiento ilimitado de seen_incidents (max ~50 000 filas)
function pruneOldIncidents() {
  const { c } = db.prepare('SELECT COUNT(*) as c FROM seen_incidents').get();
  if (c > 50000) {
    db.prepare(
      'DELETE FROM seen_incidents WHERE rowid IN (SELECT rowid FROM seen_incidents ORDER BY rowid ASC LIMIT ?)'
    ).run(c - 40000);
    console.log(`[store] pruned ${c - 40000} old incidents`);
  }
}

function checkDb() {
  db.prepare('SELECT count(*) FROM subscriptions').get();
}

module.exports = { upsertSubscription, deleteSubscription, getAllSubscriptions, hasSeenIncident, markIncidentSeen, pruneOldIncidents, checkDb };
