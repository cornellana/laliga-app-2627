# La Liga 26/27 — Documentación Técnica

App iOS personal para seguimiento de La Liga. Desarrollada en SwiftUI + backend Node.js en NAS QNAP propio. Cubre temporadas 24/25, 25/26 y 26/27.

---

## Índice

1. [App iOS](#app-ios)
2. [Backend en el NAS](#backend-en-el-nas)
3. [Push Notifications (APNs)](#push-notifications-apns)
4. [Infraestructura](#infraestructura)
5. [Comandos de operación y testing](#comandos-de-operación-y-testing)
6. [Credenciales y variables de entorno](#credenciales-y-variables-de-entorno)

---

## App iOS

### Datos del proyecto Xcode

| Campo | Valor |
|---|---|
| Bundle ID | `com.cornellana.OpencodeTest.-7` |
| Team ID Apple | `TJ6V4QM3GB` |
| Target mínimo | iOS 17 |
| SWIFT_DEFAULT_ACTOR_ISOLATION | `MainActor` (todos los tipos son `@MainActor` implícito) |
| Entitlements | `27/27/27.entitlements` → `aps-environment = development` |

### Funcionalidad

- **Pantalla principal**: lista de partidos agrupados por jornada, ordenados por fecha, con scroll automático a la jornada del día (o la siguiente).
- **Filtros**: por equipo y por jornada, combinables e independientes. Barra fija en la parte superior. Los equipos resaltados aparecen primero en el selector. Al seleccionar una jornada la vista hace scroll a ella mostrando también las siguientes.
- **Selector de temporada**: menú en el centro del navigation bar para cambiar entre 24/25, 25/26 y 26/27.
- **Detalle de partido**: sheet con alineaciones, eventos del partido (goles, tarjetas, sustituciones, penaltis) y estadísticas de momentum. Deslizando izquierda/derecha se navega al partido anterior/siguiente de la lista visible.
- **Clasificación**: sheet con tabla completa, colores de zona (UCL, UEL, Conference, descenso), calculada localmente o servida por el JSON remoto. Los equipos resaltados aparecen en su color de equipo.
- **Máximos goleadores**: sheet con ranking de goleadores de la temporada seleccionada. Los jugadores de equipos resaltados se muestran en su color de equipo.
- **Calendario por equipo**: sheet que muestra todos los partidos de un equipo en la temporada. Deslizando izquierda/derecha se navega entre equipos. Al pulsar un partido, la ficha de eventos permite deslizar entre los partidos del equipo.
- **Estadísticas de jugador**: sheet con stats individuales (si hay `athleteID` de ESPN disponible). Muestra la posición del jugador (Portero, Defensa, Centrocampista, Delantero).
- **Resaltado de equipos**: ajuste por usuario para colorear cualquier equipo favorito con su color personalizado. Sin tratamiento especial para ningún equipo: el color y resaltado se aplica únicamente a los equipos configurados. Los equipos resaltados aparecen primero en todos los selectores. Persistido en `UserDefaults` con clave `highlight_settings_v1`.
- **Avisos push**: configuración de notificaciones por evento (goles, penaltis, expulsiones, inicio/final) para los equipos resaltados. Persistido con clave `notification_prefs_v1`.

### Arquitectura iOS

```
ContentView
 ├── MatchStore (@Observable @MainActor)
 │    ├── fetchRemote()  → JSON en GitHub
 │    ├── loadSeedFromBundle()  → JSON embebido (fallback offline)
 │    └── computedStandings()  → clasificación calculada localmente
 ├── HighlightSettings (@Observable)
 │    ├── highlights: [TeamHighlight]   → didSet → NotificationService.sync()
 │    └── notifications: NotificationPrefs  → didSet → NotificationService.sync()
 ├── NotificationService (singleton @Observable)
 │    ├── setToken()   → llamado por AppDelegate
 │    └── sync() / updateCache()  → POST /register o /unregister al backend
 └── AppDelegate (UIApplicationDelegateAdaptor)
      ├── requestAuthorization()
      ├── registerForRemoteNotifications()
      └── didRegisterForRemoteNotificationsWithDeviceToken → NotificationService.setToken()
```

### Datos de partidos — fuentes y prioridad

1. **Remoto (GitHub raw)**: JSON actualizado manualmente para cada temporada.
   - 26/27: `https://raw.githubusercontent.com/cornellana/laliga-app-2627/main/data/laliga2627.json`
   - 25/26: `…/laliga2526.json`
   - 24/25: `…/laliga2425.json`
2. **UserDefaults**: caché del último JSON remoto descargado (clave `laliga_cache_v2_{code}`).
3. **Bundle seed**: JSON incluido en el `.app` (`laliga2627-seed.json`, etc.) como fallback sin internet.

El refresh ocurre al activar la app (`.task(id: scenePhase)`), al volver de primer plano, y con pull-to-refresh. Los datos de partido incluyen: hora, equipos, resultado, jornada, canal TV, estadio, alineaciones, eventos y `espnEventID` para enlazar estadísticas de jugador con ESPN.

### Archivos clave iOS

| Archivo | Rol |
|---|---|
| `27/27/_7App.swift` | Entry point, `AppDelegate`, registro APNs |
| `27/27/NotificationService.swift` | Token APNs, sync con backend |
| `27/27/27.entitlements` | `aps-environment = development` |
| `27/Models.swift` | Structs: `Match`, `MatchDay`, `MatchSnapshot`, `AppSeason`, `LeagueStanding`, `TopScorer`, `MatchEvent`, `PlayerSelection` |
| `27/MatchStore.swift` | Carga, caché y clasificación de datos |
| `27/HighlightSettings.swift` | Equipos resaltados + `NotificationPrefs`, persistencia |
| `27/HighlightSettingsSheet.swift` | UI de ajustes: colores y avisos |
| `27/ContentView.swift` | Vista principal, filtros, toolbar; `JornadaFilterBar` recibe `filterTeamHighlightColor: Color?` en vez de usar `@Environment` para evitar crash en contexto `Menu`/`safeAreaInset` |
| `27/SofaScoreService.swift` | Cliente SofaScore para detalles en tiempo real + `teamMatches()` |
| `27/MatchDetailSheet.swift` | Wrapper con `TabView(.page)` para deslizar entre partidos; `MatchDetailPage` (privado) gestiona el estado y contenido de cada partido |
| `27/TeamCalendarSheet.swift` | Calendario por equipo con `TabView(.page)` para deslizar entre equipos; pasa lista de partidos del equipo a `MatchDetailSheet` |
| `27/StandingsSheet.swift` | Clasificación; equipos resaltados en su color de equipo |
| `27/TopScorersSheet.swift` | Goleadores; jugadores de equipos resaltados en su color |
| `27/PlayerStatsSheet.swift` | Stats de jugador con posición en español |
| `27/TeamLogoView.swift` | Logos de equipos (SF Symbols / Assets) |

### UserDefaults keys

| Clave | Contenido |
|---|---|
| `highlight_settings_v1` | `[TeamHighlight]` codificado en JSON |
| `notification_prefs_v1` | `NotificationPrefs` codificado en JSON |
| `apns_device_token` | Token APNs en hex (64 chars) |
| `laliga_cache_v2_2627` | `MatchSnapshot` de la temporada 26/27 |
| `laliga_cache_v2_2526` | `MatchSnapshot` de la temporada 25/26 |
| `laliga_cache_v2_2425` | `MatchSnapshot` de la temporada 24/25 |

---

## Backend en el NAS

### Entorno

| Campo | Valor |
|---|---|
| Host | QNAP TBS-h574TX "CORNENAS" / QuTS hero |
| IP local | `192.168.1.66` |
| SSH | `ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66` |
| Docker | `/share/ZFS530_DATA/.qpkg/container-station/bin/docker` |
| DOCKER_HOST | `unix:///var/run/docker.sock` |
| Directorio del proyecto | `/share/Container/laliga-api/` |
| Nombre del contenedor | `laliga-api` |
| Puerto interno | `8090` |
| URL pública | `https://laliga-api.cornellanas.net` |

### Stack

- **Runtime**: Node 20 Alpine
- **HTTP**: Express
- **Base de datos**: SQLite (`better-sqlite3`) en modo WAL → `/app/data/laliga.db` (volumen ZFS persistente)
- **APNs**: HTTP/2 nativo (`node:http2`) + JWT ES256 (`jsonwebtoken`) con clave `.p8`
- **Fuente de eventos en vivo**: SofaScore API (no oficial)

### Archivos del backend

| Archivo | Rol |
|---|---|
| `server.js` | Express: endpoints `/health`, `/register`, `/unregister`. Arranca el poller. |
| `poller.js` | Loop cada 30 s: SofaScore → diff incidentes → APNs |
| `apns.js` | Envío HTTP/2 a APNs con JWT cacheado ~50 min |
| `store.js` | SQLite: suscripciones + incidentes vistos (dedup) |
| `teamMatches.js` | Match difuso de nombres (normaliza tildes, mayúsculas, abreviaciones) |
| `Dockerfile` | `node:20-alpine`, instala deps, copia fuentes |
| `docker-compose.yml` | Volumen ZFS, `env_file: .env`, `restart: always` |
| `.env` | Credenciales APNs (NUNCA en git) |

### Endpoints HTTP

| Método | Ruta | Body | Descripción |
|---|---|---|---|
| `GET` | `/health` | — | Devuelve `{status:"ok", ts:...}` |
| `POST` | `/register` | `{deviceToken, environment, teams[], prefs}` | Registra o actualiza suscripción |
| `POST` | `/unregister` | `{deviceToken}` | Elimina suscripción |

El campo `environment` debe ser `"sandbox"` (Debug/Xcode) o `"production"` (TestFlight/App Store).

### Schema SQLite

```sql
-- Suscripciones de dispositivos
CREATE TABLE subscriptions (
  device_token TEXT PRIMARY KEY,
  environment  TEXT NOT NULL,       -- 'sandbox' | 'production'
  teams        TEXT NOT NULL,       -- JSON array: ["FC Barcelona", ...]
  prefs        TEXT NOT NULL,       -- JSON: {enabled, goals, penalties, redCards, startEnd}
  updated_at   INTEGER NOT NULL     -- Unix timestamp ms
);

-- Incidentes ya notificados (evita duplicados tras reinicios)
CREATE TABLE seen_incidents (
  event_id    INTEGER NOT NULL,
  incident_id TEXT    NOT NULL,
  PRIMARY KEY (event_id, incident_id)
);
-- Se limpia automáticamente cuando supera 50 000 filas (mantiene últimas 40 000)
```

---

## Push Notifications (APNs)

### Credenciales APNs

| Campo | Valor |
|---|---|
| Key ID | `97X94V8XH8` |
| Team ID | `TJ6V4QM3GB` |
| Bundle ID (topic) | `com.cornellana.OpencodeTest.-7` |
| Clave `.p8` | Variable `APNS_KEY_B64` en `/share/Container/laliga-api/.env` (base64 del archivo .p8) |
| Entorno debug | `api.sandbox.push.apple.com` |
| Entorno producción | `api.push.apple.com` |

La clave `.p8` NUNCA se commitea a ningún repositorio. Solo existe en las variables de entorno del contenedor Docker.

### Flujo completo de notificación

```
App (abierta o cerrada)
  │
  ├─ AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken
  │   └─ NotificationService.setToken(data)
  │       └─ POST https://laliga-api.cornellanas.net/register
  │           { deviceToken, environment:"sandbox", teams:["FC Barcelona"], prefs:{...} }
  │
NAS (Docker, cada 30 s):
  ├─ GET api.sofascore.com/api/v1/sport/football/events/live
  │   └─ filtra La Liga (uniqueTournament.id === 8)
  │
  ├─ Para cada partido de La Liga en vivo:
  │   ├─ GET api.sofascore.com/api/v1/event/{id}/incidents
  │   ├─ diff vs seen_incidents (dedup)
  │   └─ Si hay nuevos: selecciona suscripciones con el equipo implicado
  │
  └─ POST api.sandbox.push.apple.com/3/device/{token}  (HTTP/2, JWT ES256)
      └─ iOS muestra banner al usuario
```

### Formato de mensajes push

| Evento | Título | Cuerpo |
|---|---|---|
| Gol | `⚽ GOL (45')` | `Lewandowski · FC Barcelona 2-1 Real Madrid` |
| Gol de penalti | `⚽ Gol de penalti (78')` | `Mbappé · FC Barcelona 2-1 Real Madrid` |
| En propia meta | `⚽ En propia meta (23')` | `Rüdiger · FC Barcelona 1-0 Real Madrid` |
| Expulsión | `🟥 Expulsión (67')` | `Vinicius · Real Madrid · 1-2` |
| Penalti fallado | `❌ Penalti fallado (55')` | `Mbappé · Real Madrid · 1-2` |
| Inicio de partido | `⚽ Partido comenzado` | `FC Barcelona - Real Madrid` |
| Final de partido | `🏁 Partido terminado` | `FC Barcelona 2-1 Real Madrid` |

### Lógica de dedup

- Cada incidente de SofaScore tiene un `id` único. Si no lo tiene, se genera clave compuesta: `{time}_{incidentType}_{incidentClass}_{player.id}`.
- Antes de notificar se consulta `seen_incidents`. Si ya está → se ignora.
- Se marca como visto AUNQUE no haya suscriptores interesados (evita duplicados si se registra un suscriptor después).
- Los tokens con error APNs `410` o razón `BadDeviceToken`/`Unregistered` se eliminan automáticamente de la BD.

### Entorno sandbox vs production

La app compilada con Xcode (Debug) usa `sandbox`. TestFlight y App Store usan `production`. El token APNs y el servidor APNs deben coincidir — enviar un token de sandbox al servidor de producción (o viceversa) da error `BadDeviceToken`.

---

## Infraestructura

### Ingreso público

El NAS no tiene puertos abiertos en el router. El tráfico entrante al backend (`POST /register`) llega por **Cloudflare Tunnel**:

```
iPhone → HTTPS → Cloudflare → Túnel → NAS:8090 (contenedor Docker)
```

- Dominio: `laliga-api.cornellanas.net`
- TLS: terminado por Cloudflare (certificado válido, sin advertencias ATS)
- Inmune a la IP dinámica de Movistar

El tráfico saliente (SofaScore + APNs) es directo desde el NAS, sin túnel.

### Persistencia de datos

El volumen Docker monta `/share/Container/laliga-api/data` → `/app/data` dentro del contenedor. La BD SQLite (`laliga.db`) sobrevive a:
- Reinicios del contenedor
- Reinicios del NAS
- Rebuilds de la imagen Docker

### Actualización del contenedor

Tras cambiar código en local, el flujo para desplegar es:

```bash
# 1. Sincronizar archivos al NAS
rsync -avz -e "ssh -i ~/.ssh/qnap_key -p 30" \
  /Users/Francisco_1/laliga-backend/archivo.js \
  cornellana@192.168.1.66:/share/Container/laliga-api/

# 2a. Para cambio inmediato sin rebuild (solo proceso actual):
DOCKER="DOCKER_HOST=unix:///var/run/docker.sock /share/ZFS530_DATA/.qpkg/container-station/bin/docker"
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  "$DOCKER cp /share/Container/laliga-api/archivo.js laliga-api:/app/archivo.js && \
   $DOCKER restart laliga-api"

# 2b. Para rebuild completo (permanente en imagen):
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  'cd /share/Container/laliga-api && \
   DOCKER_HOST=unix:///var/run/docker.sock \
   DOCKER_CONFIG=/share/homes/cornellana/.docker \
   DOCKER_BUILDKIT=0 \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker compose up -d --build'
```

---

## Comandos de operación y testing

### Acceso SSH al NAS

```bash
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66
```

### Alias útil (añadir a ~/.zshrc o usar inline)

```bash
QNAP="ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66"
DOCKER="DOCKER_HOST=unix:///var/run/docker.sock /share/ZFS530_DATA/.qpkg/container-station/bin/docker"
```

### Estado del contenedor

```bash
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker ps --filter name=laliga-api'
```

### Logs en tiempo real

```bash
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker logs laliga-api -f'
```

### Salud del backend (desde cualquier sitio)

```bash
curl https://laliga-api.cornellanas.net/health
# → {"status":"ok","ts":1785012345678}
```

### Ver todos los device tokens registrados

```bash
cat > /tmp/tokens.js << 'EOF'
const db = require('better-sqlite3')('/app/data/laliga.db');
db.prepare('SELECT device_token, environment, teams, updated_at FROM subscriptions ORDER BY updated_at DESC').all()
  .forEach(r => {
    const d = new Date(r.updated_at).toISOString();
    console.log(`${r.environment.padEnd(12)} ${d}  ${r.device_token}  teams=${r.teams}`);
  });
EOF

ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 'cat > /tmp/tokens.js' < /tmp/tokens.js
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker cp /tmp/tokens.js laliga-api:/app/tokens.js && \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker exec -w /app laliga-api node tokens.js'
```

Salida típica:
```
sandbox      2026-07-25T18:08:24.292Z  5a6bb121...bef5d28  teams=["FC Barcelona"]
production   2026-07-25T20:00:00.000Z  a1b2c3d4...xxxxxx   teams=["Real Madrid"]
```

### Enviar push de prueba a un token concreto

```bash
TOKEN="5a6bb12108acaad7855a256cc6067cdfd366dbfb4c8dcdd5590ab3842bef5d28"
ENV="sandbox"   # o "production" para TestFlight

cat > /tmp/testpush.js << EOF
const { sendPush } = require('./apns');
sendPush('$TOKEN', '$ENV', '⚽ GOL (45\')', 'FC Barcelona 2-1 Real Madrid')
  .then(r => { console.log('APNs:', JSON.stringify(r)); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });
EOF

ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 "cat > /tmp/testpush.js" < /tmp/testpush.js
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker cp /tmp/testpush.js laliga-api:/app/testpush.js && \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker exec -w /app laliga-api node testpush.js'
# → APNs: {"success":true}
```

### Registrar manualmente un token (simular la app)

```bash
curl -X POST https://laliga-api.cornellanas.net/register \
  -H "Content-Type: application/json" \
  -d '{
    "deviceToken": "TOKEN_DE_64_CHARS_HEX",
    "environment": "sandbox",
    "teams": ["FC Barcelona"],
    "prefs": {"enabled": true, "goals": true, "penalties": true, "redCards": true, "startEnd": true}
  }'
# → {"ok":true}
```

### Eliminar un token de la BD

```bash
curl -X POST https://laliga-api.cornellanas.net/unregister \
  -H "Content-Type: application/json" \
  -d '{"deviceToken": "TOKEN_DE_64_CHARS_HEX"}'
# → {"ok":true}
```

### Limpiar tokens obsoletos manualmente

```bash
TOKEN_ACTIVO="5a6bb12108acaad7855a256cc6067cdfd366dbfb4c8dcdd5590ab3842bef5d28"

cat > /tmp/cleanup.js << EOF
const db = require('better-sqlite3')('/app/data/laliga.db');
const del = db.prepare("DELETE FROM subscriptions WHERE device_token != ?").run('$TOKEN_ACTIVO');
console.log('Eliminados:', del.changes);
EOF

ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 "cat > /tmp/cleanup.js" < /tmp/cleanup.js
ssh -i ~/.ssh/qnap_key -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker cp /tmp/cleanup.js laliga-api:/app/cleanup.js && \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker exec -w /app laliga-api node cleanup.js'
```

### Ver incidentes procesados (para un eventId de partido)

```bash
cat > /tmp/incidents.js << 'EOF'
const db = require('better-sqlite3')('/app/data/laliga.db');
const EVENT_ID = 12345678;   // ID del partido en SofaScore
const rows = db.prepare('SELECT * FROM seen_incidents WHERE event_id = ?').all(EVENT_ID);
console.log(`Incidentes vistos para evento ${EVENT_ID}:`, rows.length);
rows.forEach(r => console.log(' ', r.incident_id));
EOF
# (copiar y ejecutar igual que los scripts anteriores)
```

### Cómo obtener el device token de la app en Xcode

Al lanzar la app con el dispositivo conectado, el token aparece en la consola de Xcode:
```
[APNs] device token: 5a6bb12108acaa...
```

Esto está implementado en `NotificationService.setToken()`.

### Troubleshooting de notificaciones

| Síntoma | Causa probable | Solución |
|---|---|---|
| `{"success":false,"reason":"BadDeviceToken"}` | Token inválido o entorno incorrecto | Verificar que `environment` coincide con el build (debug→sandbox, TestFlight→production) |
| `{"success":false,"reason":"Unregistered"}` (410) | App desinstalada o token caducado | El backend lo elimina automáticamente |
| `{"success":true}` pero no llega la notif | No Molestar activo, o permisos de notif desactivados en Ajustes | Desactivar Focus mode; revisar Ajustes → Notificaciones → 27 |
| No aparece `/register` en los logs | La app no tiene equipo resaltado o `enabled=false` | Activar avisos en la app y tener ≥1 equipo resaltado |
| Backend no envía pushes durante partidos | La Liga no está `uniqueTournament.id === 8`, o SofaScore cambió la API | Verificar con curl el endpoint live |

---

## Credenciales y variables de entorno

### `.env` en el NAS (`/share/Container/laliga-api/.env`)

```env
APNS_BUNDLE_ID=com.cornellana.OpencodeTest.-7
APNS_KEY_ID=97X94V8XH8
APNS_TEAM_ID=TJ6V4QM3GB
APNS_KEY_B64=<contenido base64 del archivo .p8>
POLL_INTERVAL_MS=30000
PORT=8090
```

La variable `APNS_KEY_B64` contiene el archivo `.p8` completo codificado en base64. Para generarla:
```bash
base64 -i AuthKey_97X94V8XH8.p8 | tr -d '\n'
```

### Seguridad

- El archivo `.p8` NUNCA se commitea a ningún repositorio git.
- Solo existe como variable de entorno en el contenedor Docker.
- El NAS usa autenticación SSH por clave únicamente (`~/.ssh/qnap_key`, ed25519 con passphrase). `PasswordAuthentication` desactivado.
- El endpoint `/register` valida que `deviceToken` sea exactamente 64 caracteres hexadecimales.
- No hay puertos del router abiertos; todo el ingreso es por Cloudflare Tunnel.

---

## Notas sobre la API de SofaScore

- **Endpoint en vivo**: `GET https://api.sofascore.com/api/v1/sport/football/events/live`
  - Filtro La Liga: `event.tournament.uniqueTournament.id === 8`
- **Incidents**: `GET https://api.sofascore.com/api/v1/event/{id}/incidents`
  - Campos relevantes: `incidentType` (`'goal'`, `'card'`, `'penalty'`), `incidentClass` (`'regular'`, `'penalty'`, `'ownGoal'`, `'red'`, `'yellowRed'`), `player.shortName`, `time` (minuto), `isHome`, `missed`
- **Header requerido**: `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)...`
- API no oficial, sin garantías de estabilidad. Sondeo cada 30 s (configurable con `POLL_INTERVAL_MS`).

---

---

## Notas de implementación relevantes

### Propagación de `@Environment` con `@Observable` en SwiftUI

`HighlightSettings` usa `@Observable` y se inyecta con `.environment(highlightSettings)` en `ContentView`. Puntos clave:

- **Todos los sheets** necesitan `.environment(highlightSettings)` explícito en el call site, ya que SwiftUI no garantiza la propagación automática a contextos de presentación modal con `@Observable`.
- **`JornadaFilterBar`** no usa `@Environment(HighlightSettings.self)` porque está en un `safeAreaInset` y abre un `Menu`: ambos contextos pueden romper la propagación. En su lugar recibe `filterTeamHighlightColor: Color?` como parámetro calculado desde `ContentView`.
- Las vistas dentro de `NavigationStack` (como `MatchRowView`, `StandingRow`, `LineupColumn`, `RosterColumn`) sí reciben el environment correctamente.

### Navegación por deslizamiento en `MatchDetailSheet`

`MatchDetailSheet` es un wrapper con `TabView(.page)` que recibe:
- `match: Match` — el partido inicial
- `season: AppSeason` — temporada
- `allMatches: [Match]` — lista completa para deslizar (por defecto solo el partido actual)

Cada página del `TabView` es un `MatchDetailPage` (privado) con sus propios `@State` para datos async (detalles ESPN, plantillas, momentum). El scroll vertical dentro de cada página y el deslizamiento horizontal del `TabView` coexisten sin conflicto.

`MatchItem` incluye `allMatches: [Match]` para transportar el contexto de navegación desde el punto de llamada hasta el sheet.

---

*Actualizado el 2026-07-26*
