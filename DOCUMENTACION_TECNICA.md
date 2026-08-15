# La Liga 26/27 — Documentación Técnica

App iOS personal para seguimiento de La Liga. SwiftUI + un actualizador de datos en GitHub Actions + un backend Node.js de avisos push en NAS QNAP propio. Cubre temporadas 24/25, 25/26 y 26/27.

---

## Índice

1. [App iOS](#app-ios)
2. [Pipeline de datos](#pipeline-de-datos)
3. [Backend en el NAS](#backend-en-el-nas)
4. [Push Notifications (APNs)](#push-notifications-apns)
5. [Infraestructura](#infraestructura)
6. [Comandos de operación y testing](#comandos-de-operación-y-testing)
7. [Credenciales y variables de entorno](#credenciales-y-variables-de-entorno)
8. [Notas sobre la API de ESPN](#notas-sobre-la-api-de-espn)
9. [Problemas conocidos](#problemas-conocidos)
10. [Notas de implementación](#notas-de-implementación)

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
| Repositorio | `github.com/cornellana/laliga-app-2627` |

### Funcionalidad

- **Pantalla principal**: lista de partidos agrupados por jornada, ordenados por fecha, con scroll automático a la jornada del día (o la siguiente).
- **Filtros**: por equipo y por jornada, combinables e independientes. Barra fija en la parte superior. Los equipos resaltados aparecen primero en el selector. Al seleccionar una jornada la vista hace scroll a ella mostrando también las siguientes.
- **Selector de temporada**: menú en el centro del navigation bar para cambiar entre 24/25, 25/26 y 26/27.
- **Detalle de partido**: sheet con alineaciones, eventos del partido (goles, tarjetas, sustituciones, penaltis) y estadísticas de momentum. Deslizando izquierda/derecha se navega al partido anterior/siguiente de la lista visible.
- **Clasificación**: sheet con tabla completa, colores de zona (UCL, UEL, Conference, descenso), calculada localmente o servida por el JSON remoto. Los equipos resaltados aparecen en su color de equipo.
- **Máximos goleadores**: sheet con ranking de goleadores de la temporada seleccionada. Los jugadores de equipos resaltados se muestran en su color de equipo.
- **Calendario por equipo**: sheet que muestra todos los partidos de un equipo en la temporada. Deslizando izquierda/derecha se navega entre equipos. Al pulsar un partido, la ficha de eventos permite deslizar entre los partidos del equipo.
- **Estadísticas de jugador**: sheet con stats individuales (si hay `athleteID` de ESPN disponible). Muestra la posición del jugador (Portero, Defensa, Centrocampista, Delantero).
- **Resaltado de equipos**: ajuste por usuario para colorear cualquier equipo favorito con su color personalizado. Sin tratamiento especial para ningún equipo. Los equipos resaltados aparecen primero en todos los selectores. Persistido en `UserDefaults` con clave `highlight_settings_v1`.
- **Avisos push**: configuración de notificaciones por evento (goles, penaltis, expulsiones, inicio/final) para los equipos resaltados. Persistido con clave `notification_prefs_v1`.

### Arquitectura iOS

```
ContentView
 ├── MatchStore (@Observable @MainActor)
 │    ├── fetchRemote()  → JSON en GitHub raw
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

1. **Remoto (GitHub raw)**, actualizado automáticamente (ver [Pipeline de datos](#pipeline-de-datos)):
   - 26/27: `https://raw.githubusercontent.com/cornellana/laliga-app-2627/refs/heads/main/data/laliga2627.json`
   - 25/26: `…/laliga2526.json` (estático, temporada cerrada)
   - 24/25: `…/laliga2425.json` (estático, temporada cerrada)
2. **UserDefaults**: caché del último JSON remoto descargado (clave `laliga_cache_v2_{code}`).
3. **Bundle seed**: JSON incluido en el `.app` (`laliga2627-seed.json`, etc.) como fallback sin internet.

El refresh ocurre al activar la app (`.task(id: scenePhase)`) y con pull-to-refresh. **No hay sondeo en segundo plano**: con la app cerrada, la única vía de aviso son las notificaciones push.

`fetchRemote()` añade `?t=<epoch>` a la URL y usa `.reloadIgnoringLocalAndRemoteCacheData`. Aun así, `raw.githubusercontent.com` sirve con `max-age=300` y distintos nodos pueden devolver copias diferentes, así que la app puede mostrar datos de hasta unos cinco minutos antes. Irrelevante frente al cron de 15 minutos.

### Nombres canónicos de equipo

Los nombres de equipo del JSON son **la clave de búsqueda** de escudos y plantillas: `TeamLogoView.logoIDs` y `MatchesData.espnTeamIDs` están indexados por ellos. Un nombre que no coincida deja al equipo sin escudo (cae al círculo con iniciales) y sin plantilla (`fetchRoster` devuelve vacío), en silencio.

Los 20 de la 26/27: `Real Madrid`, `FC Barcelona`, `Atlético`, `Athletic`, `R. Sociedad`, `Betis`, `Villarreal`, `Valencia`, `Sevilla`, `Osasuna`, `Celta`, `Getafe`, `Rayo`, `Alavés`, `Espanyol`, `Levante`, `Racing`, `Deportivo`, `Elche`, `Málaga`.

La traducción desde los nombres de ESPN vive en `TEAM_NAME_MAP` de `scripts/update_liga.py`. **Si se añade un equipo o ESPN renombra alguno, hay que tocar ese mapa además de los dos diccionarios Swift.**

### Archivos clave iOS

| Archivo | Rol |
|---|---|
| `27/27/_7App.swift` | Entry point, `AppDelegate`, registro APNs |
| `27/27/NotificationService.swift` | Token APNs, sync con backend |
| `27/27/27.entitlements` | `aps-environment = development` |
| `27/Models.swift` | Structs: `Match`, `MatchDay`, `MatchSnapshot`, `AppSeason`, `LeagueStanding`, `TopScorer`, `MatchEvent`, `PlayerSelection`. Aquí están las URLs remotas de cada temporada. |
| `27/MatchStore.swift` | Carga, caché en tres niveles y clasificación calculada |
| `27/MatchesData.swift` | `allTeams` y `espnTeamIDs` (id de equipo en ESPN, para plantillas) |
| `27/HighlightSettings.swift` | Equipos resaltados + `NotificationPrefs`, persistencia |
| `27/HighlightSettingsSheet.swift` | UI de ajustes: colores y avisos |
| `27/ContentView.swift` | Vista principal, filtros, toolbar; `JornadaFilterBar` recibe `filterTeamHighlightColor: Color?` en vez de usar `@Environment` para evitar crash en contexto `Menu`/`safeAreaInset` |
| `27/SofaScoreService.swift` | Cliente SofaScore para el gráfico de momentum. **Actualmente inoperativo**, ver [Problemas conocidos](#problemas-conocidos) |
| `27/MatchDetailSheet.swift` | Wrapper con `TabView(.page)` para deslizar entre partidos; `MatchDetailPage` (privado) gestiona estado y contenido. Descarga los detalles directamente de ESPN al abrirse. |
| `27/TeamCalendarSheet.swift` | Calendario por equipo con `TabView(.page)`; pasa lista de partidos del equipo a `MatchDetailSheet` |
| `27/StandingsSheet.swift` | Clasificación; equipos resaltados en su color |
| `27/TopScorersSheet.swift` | Goleadores; jugadores de equipos resaltados en su color |
| `27/PlayerStatsSheet.swift` | Stats de jugador con posición en español |
| `27/TeamLogoView.swift` | Escudos: asset local para el Barça, PNG del CDN de ESPN (`logoIDs`) para el resto, círculo con iniciales como fallback |

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

## Pipeline de datos

Los resultados **no** se actualizan a mano: los publica un GitHub Action en el propio repositorio de la app.

```
GitHub Actions (cron */15)
  └─ scripts/update_liga.py
       ├─ GET site.api.espn.com/.../scoreboard?dates=YYYYMMDD   (hoy ± 4 días)
       ├─ GET site.api.espn.com/.../summary?event={id}          (solo partidos terminados)
       ├─ recalcula topScorers
       └─ escribe data/laliga2627.json
  └─ git commit + push si el JSON cambió
       └─ raw.githubusercontent.com  →  la app lo descarga al abrirse
```

### Workflow

`.github/workflows/update-liga.yml`

- Cron `*/15 * * * *`, más `workflow_dispatch` manual con opción `force_refresh`.
- Solo mantiene `data/laliga2627.json`. Las temporadas cerradas son estáticas.
- Commitea como `github-actions[bot]` únicamente si hay cambios reales.
- En la práctica GitHub retrasa el cron: los intervalos reales son de 15 a 30 minutos.

### `scripts/update_liga.py`

Actualización incremental. Puntos que conviene conocer antes de tocarlo:

- **Ventana de consulta**: hoy ± 4 días. Los partidos fuera de esa ventana se conservan tal cual estaban en el JSON.
- **Partidos terminados**: se saltan en ejecuciones posteriores, salvo que les falten los detalles. Si el `summary` falló en su momento, se reintenta; de lo contrario sus goles nunca entrarían en la tabla de goleadores.
- **Jornada**: ESPN **ya no publica `week`** en el scoreboard de LaLiga (viene `null`, y `season.type` es un identificador interno, no `2`). La jornada se recupera del calendario ya guardado en el JSON, indexado por pareja (local, visitante). Si un partido no está en ese índice se avisa por log y se usa 1.
- **Nombres de equipo**: se traducen con `TEAM_NAME_MAP`. Un nombre sin equivalencia **se avisa por log**; antes se escribía crudo y rompía escudos y plantillas en silencio. Al cargar el archivo se hace además una pasada de saneado sobre los nombres ya guardados.
- **Goleadores**: `build_top_scorers()` los calcula a partir de los goles ya parseados de cada partido, sin peticiones extra. Los goles en propia meta no se atribuyen a su autor; los de penalti se cuentan además en la columna de penaltis.
- **Clasificación**: no se genera. `MatchStore.computedStandings()` la calcula en el dispositivo a partir de los partidos.
- **Tolerancia a fallos**: el parseo de detalles va en `try/except`. Un detalle ilegible no puede tumbar la actualización del marcador, que es lo importante.

Ejecución manual:

```bash
python3 scripts/update_liga.py
FORCE_REFRESH=true python3 scripts/update_liga.py   # reprocesa los partidos terminados
```

### Otros scripts

| Script | Rol |
|---|---|
| `scripts/update_liga.py` | El actualizador en producción. Es el único que ejecuta el workflow. |
| `scripts/fetch_season.py` | Generación inicial del calendario completo de una temporada. Uso puntual. |
| `scripts/fetch_scorers.py` | Relleno de goleadores para temporadas históricas. **Obsoleto para 26/27**: solo acepta los años 2024 y 2025 y busca un campo `espnEventID` que `update_liga.py` no escribe. |

### Estructura del JSON

```jsonc
{
  "lastUpdated": "2026-08-15T21:56:02Z",
  "season": "2026-27",
  "matchDays": [
    {
      "date": "2026-08-15",          // yyyy-MM-dd, hora de Madrid
      "jornada": 1,
      "games": [
        {
          "id": "401882926",          // event id de ESPN
          "time": "19:30",
          "home": "Alavés",           // nombre canónico
          "away": "Getafe",
          "jornada": 1,
          "tv": "DAZN",
          "done": true,
          "result": "3-0",            // null si no ha terminado
          "stadium": "Mendizorroza",
          "venueCity": "Vitoria-Gasteiz",
          "details": {                 // null si no ha terminado
            "homeLineup": { "formation": "3-5-2", "players": [ /* … */ ] },
            "awayLineup": { "formation": "3-5-2", "players": [ /* … */ ] },
            "events": [
              { "id": "…", "type": "GOAL", "minute": 90, "extraTime": 1,
                "playerName": "Mariano Díaz", "teamName": "Alavés", "text": null }
            ]
          }
        }
      ]
    }
  ],
  "standings": [],                     // siempre vacío: la app la calcula
  "topScorers": [
    { "player": "Mariano Díaz", "team": "Alavés", "goals": 1, "penalties": null }
  ]
}
```

Valores de `type` en los eventos: `GOAL`, `PENALTY`, `OWN_GOAL`, `YELLOW_CARD`, `RED_CARD`, `MISSED_PENALTY`, `SUBSTITUTION`. En los cambios, `playerName` es quien entra y `text` quien sale.

---

## Backend en el NAS

### Entorno

| Campo | Valor |
|---|---|
| Host | QNAP TBS-h574TX "CORNENAS" / QuTS hero |
| IP local | `192.168.1.66` |
| SSH | `ssh -p 30 cornellana@192.168.1.66` (contraseña; ver aviso abajo) |
| Docker | `/share/ZFS530_DATA/.qpkg/container-station/bin/docker` |
| DOCKER_HOST | `unix:///var/run/docker.sock` |
| Directorio del proyecto | `/share/Container/laliga-api/` |
| Nombre del contenedor | `laliga-api` |
| Puerto interno | `8090` |
| URL pública | `https://laliga-api.cornellanas.net` |

> **Acceso SSH.** No existe ninguna clave `~/.ssh/qnap_key` en el iMac: se entra con contraseña. Además el SSH del QNAP **no tiene habilitado el subsistema SFTP**, así que `scp` y `rsync` fallan con `subsystem request failed on channel 0`. Para mover archivos hay que usar `tar` por la tubería (ver [Actualización del contenedor](#actualización-del-contenedor)). La conexión se cae a ratos por el WiFi; los timeouts y los `EAI_AGAIN` de DNS son eso, no un bloqueo.

### Stack

- **Runtime**: Node 20 Alpine
- **HTTP**: Express
- **Base de datos**: SQLite (`better-sqlite3`) → `/app/data/laliga.db` (volumen ZFS persistente)
- **APNs**: HTTP/2 nativo (`node:http2`) + JWT ES256 (`jsonwebtoken`) con clave `.p8`
- **Fuente de eventos en vivo**: **API de ESPN** (desde el 15-08-2026; antes SofaScore, ver [Problemas conocidos](#problemas-conocidos))

### Archivos del backend

| Archivo | Rol |
|---|---|
| `server.js` | Express: endpoints `/health`, `/register`, `/unregister`. Arranca el poller. |
| `poller.js` | Loop cada 30 s: ESPN → diff de incidentes → APNs |
| `apns.js` | Envío HTTP/2 a APNs con JWT cacheado ~50 min |
| `store.js` | SQLite: suscripciones + incidentes vistos (dedup) |
| `teamMatches.js` | Match difuso de nombres (normaliza tildes, mayúsculas, abreviaciones) |
| `Dockerfile` | `node:20-alpine`, instala deps, copia fuentes |
| `docker-compose.yml` | Volumen ZFS, `env_file: .env`, `restart: always` |
| `.env` | Credenciales APNs (NUNCA en git) |

### Cómo funciona `poller.js`

Cada 30 segundos:

1. Descarga el scoreboard de ESPN de **hoy y ayer** en UTC (un partido nocturno cruza el cambio de día).
2. Se queda con los partidos en estado `in` (en juego) o `post` (terminado).
3. Por cada uno: publica las transiciones de estado (inicio y final) y descarga el `summary` para diffear los incidentes contra `seen_incidents`.
4. Envía por APNs a las suscripciones cuyo equipo esté implicado.

Tres detalles deliberados:

- **Usa `fetch` (undici), no `node:https`.** ESPN devuelve **403** al cliente HTTP clásico de Node se le pongan las cabeceras que se le pongan, y 200 con `fetch`. Verificado desde el propio contenedor. No cambiar sin comprobarlo.
- **Comprueba el código HTTP.** La versión anterior solo miraba el 404, así que un 403 se parseaba como JSON válido, daba lista vacía y salía en silencio. Ese fue exactamente el fallo que dejó el poller mudo durante semanas con `/health` respondiendo `ok`.
- **Arranque silencioso.** En el primer ciclo tras arrancar, los partidos ya terminados se marcan como vistos sin notificar, para no disparar una ráfaga de avisos atrasados tras un despliegue o al recrear la base de datos. Los partidos en juego se procesan con normalidad, así que un reinicio a media primera parte no se pierde ningún gol.

De los partidos terminados el `summary` se pide **una sola vez** (marca `final_processed`), no en bucle el resto del día.

### Endpoints HTTP

| Método | Ruta | Body | Descripción |
|---|---|---|---|
| `GET` | `/health` | — | Devuelve `{status:"ok", ts:...}`. Ojo: solo dice que Express vive, no que el poller funcione. |
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
  event_id    INTEGER NOT NULL,     -- event id de ESPN
  incident_id TEXT    NOT NULL,     -- '{keyEvent.id}_{índice}' o marcador de estado
  PRIMARY KEY (event_id, incident_id)
);
-- Se limpia automáticamente cuando supera 50 000 filas (mantiene últimas 40 000)
```

Los `incident_id` reservados son `status_in`, `status_post` y `final_processed`.

> Tras la migración a ESPN los `event_id` son los de ESPN, distintos de los de SofaScore. Las filas antiguas quedan huérfanas y se purgan solas con el tiempo.

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
  ├─ GET site.api.espn.com/.../scoreboard?dates=YYYYMMDD   (hoy y ayer, UTC)
  │   └─ se queda con los partidos en estado 'in' o 'post'
  │
  ├─ Para cada partido activo:
  │   ├─ transición de estado → aviso de inicio o final
  │   ├─ GET site.api.espn.com/.../summary?event={id}
  │   ├─ diff de keyEvents vs seen_incidents (dedup)
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

El minuto conserva el descuento tal cual lo da ESPN (`90+3`). El marcador que acompaña al aviso es el del momento de enviarlo, no el del instante del gol.

### Lógica de dedup

- Clave de incidente: `{keyEvent.id}_{índice}` dentro del `summary`. El índice desempata los eventos que ESPN repite con el mismo id.
- Antes de notificar se consulta `seen_incidents`. Si ya está → se ignora.
- Se marca como visto AUNQUE no haya suscriptores interesados (evita duplicados si se registra un suscriptor después).
- Los tokens con error APNs `410` o razón `BadDeviceToken`/`Unregistered` se eliminan automáticamente de la BD.

### Entorno sandbox vs production

La app compilada con Xcode (Debug) usa `sandbox`. TestFlight y App Store usan `production`. El token APNs y el servidor APNs deben coincidir — enviar un token de sandbox al servidor de producción (o viceversa) da error `BadDeviceToken`. **Es la causa más habitual de "el backend funciona pero no me llega nada"**: comprobar siempre con qué `environment` está registrado el dispositivo.

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

El tráfico saliente (ESPN + APNs) es directo desde el NAS, sin túnel.

### Persistencia de datos

El volumen Docker monta `/share/Container/laliga-api/data` → `/app/data` dentro del contenedor. La BD SQLite (`laliga.db`) sobrevive a reinicios del contenedor, reinicios del NAS y rebuilds de la imagen.

### Actualización del contenedor

El código va **dentro de la imagen**, no montado. Tras cambiar algo en local:

```bash
# 1. Copiar el archivo al NAS (sin scp: el QNAP no tiene SFTP)
tar -C ~/Desktop/laliga-api-src -cf - poller.js \
  | ssh -p 30 cornellana@192.168.1.66 "tar -C /share/Container/laliga-api -xf -"

# 2a. Cambio inmediato, sin rebuild (aguanta reinicios, no un rebuild)
ssh -p 30 cornellana@192.168.1.66 \
  "export DOCKER_HOST=unix:///var/run/docker.sock; \
   D=/share/ZFS530_DATA/.qpkg/container-station/bin/docker; \
   \$D cp /share/Container/laliga-api/poller.js laliga-api:/app/poller.js && \
   \$D restart laliga-api"

# 2b. Rebuild completo (permanente en la imagen)
ssh -p 30 cornellana@192.168.1.66 \
  'cd /share/Container/laliga-api && \
   DOCKER_HOST=unix:///var/run/docker.sock \
   DOCKER_CONFIG=/share/homes/cornellana/.docker \
   DOCKER_BUILDKIT=0 \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker compose up -d --build'
```

### Publicar cambios de la app y del updater

El repositorio `cornellana/laliga-app-2627` se sube por **HTTPS con token de acceso personal**, poniendo `cornellana` como usuario (no el correo). No sirven:

- `~/.ssh/github_rsa`, de 2015 y no registrada en la cuenta.
- El GitHub Desktop instalado, que es la versión antigua con diálogo de usuario y contraseña.

Un cambio en `scripts/` surte efecto en la siguiente ejecución del cron, o al lanzar el workflow a mano desde **Actions → Actualizar datos de La Liga 26/27 → Run workflow**. Los cambios en Swift requieren recompilar y redistribuir la app.

---

## Comandos de operación y testing

### Acceso SSH al NAS

```bash
ssh -p 30 cornellana@192.168.1.66
```

### Alias útil (añadir a ~/.zshrc o usar inline)

```bash
QNAP="ssh -p 30 cornellana@192.168.1.66"
DOCKER="DOCKER_HOST=unix:///var/run/docker.sock /share/ZFS530_DATA/.qpkg/container-station/bin/docker"
```

### Estado del contenedor

```bash
ssh -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker ps --filter name=laliga-api'
```

### Logs

```bash
# Últimas líneas con marca de tiempo
ssh -p 30 cornellana@192.168.1.66 \
  '/share/ZFS530_DATA/.qpkg/container-station/bin/docker logs -t --tail 40 laliga-api'

# Solo lo reciente
ssh -p 30 cornellana@192.168.1.66 \
  '/share/ZFS530_DATA/.qpkg/container-station/bin/docker logs --since 10m laliga-api'
```

> `docker logs` mezcla stdout (`console.log`) y stderr (`console.error`) y **el orden entre ambos flujos no está garantizado**: es normal ver errores viejos listados debajo de líneas nuevas. Usar siempre `-t` antes de sacar conclusiones.
>
> Sin partidos en juego, lo sano es que **no salga nada**. El poller consulta, ve que no hay nada activo y sale sin escribir.

### Comprobar que el poller alcanza ESPN

```bash
ssh -p 30 cornellana@192.168.1.66 '/share/ZFS530_DATA/.qpkg/container-station/bin/docker exec laliga-api node -e "fetch(process.argv[1]).then(r=>console.log(\"HTTP\",r.status)).catch(e=>console.log(\"ERR\",e.message))" https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/scoreboard'
# → HTTP 200
```

### Salud del backend (desde cualquier sitio)

```bash
curl https://laliga-api.cornellanas.net/health
# → {"status":"ok","ts":1785012345678}
```

### Estado del pipeline de datos

```bash
# Últimas ejecuciones del workflow
curl -s "https://api.github.com/repos/cornellana/laliga-app-2627/actions/runs?per_page=5" \
  | python3 -c "import json,sys; [print(r['created_at'],r['conclusion'],'run#',r['run_number']) for r in json.load(sys.stdin)['workflow_runs']]"

# Contenido publicado (el CDN cachea 5 min; git show es la fuente fiable)
git -C <repo> fetch -q origin && git show origin/main:data/laliga2627.json | head -3
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

ssh -p 30 cornellana@192.168.1.66 'cat > /tmp/tokens.js' < /tmp/tokens.js
ssh -p 30 cornellana@192.168.1.66 \
  'DOCKER_HOST=unix:///var/run/docker.sock \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker cp /tmp/tokens.js laliga-api:/app/tokens.js && \
   /share/ZFS530_DATA/.qpkg/container-station/bin/docker exec -w /app laliga-api node tokens.js'
```

Salida típica:
```
sandbox      2026-07-25T18:08:24.292Z  5a6bb121...bef5d28  teams=["FC Barcelona","Real Madrid"]
production   2026-08-15T21:15:34.597Z  a1b2c3d4...d964b68c teams=["FC Barcelona","Girona"]
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

ssh -p 30 cornellana@192.168.1.66 "cat > /tmp/testpush.js" < /tmp/testpush.js
ssh -p 30 cornellana@192.168.1.66 \
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

### Cómo obtener el device token de la app en Xcode

Al lanzar la app con el dispositivo conectado, el token aparece en la consola de Xcode:
```
[APNs] device token: 5a6bb12108acaa...
```

Implementado en `NotificationService.setToken()`.

### Troubleshooting

| Síntoma | Causa probable | Comprobación |
|---|---|---|
| Los resultados no se actualizan | El workflow está fallando | Pestaña Actions del repo; el paso que suele romperse es *Actualizar JSON desde ESPN* |
| El workflow va en verde pero el JSON no cambia | Caché del CDN | `git show origin/main:data/laliga2627.json` en vez de `curl` a raw |
| Un equipo sin escudo ni plantilla | Su nombre en el JSON no es el canónico | Buscar el aviso `Equipo sin equivalencia en TEAM_NAME_MAP` en el log del workflow |
| La app muestra datos viejos | Caché en `UserDefaults` | Pull-to-refresh, o cerrar la app del todo y reabrirla |
| `BadDeviceToken` | Token inválido o entorno incorrecto | Que `environment` case con el build (Xcode→sandbox, TestFlight→production) |
| `Unregistered` (410) | App desinstalada o token caducado | El backend lo elimina solo |
| `{"success":true}` pero no llega | Modo concentración o permisos | Ajustes → Notificaciones → 27 |
| No aparece `/register` en los logs | Sin equipo resaltado o `enabled=false` | Activar avisos y tener ≥1 equipo resaltado |
| El poller no manda nada durante los partidos | ESPN devolviendo error, o `fetch` sustituido por `node:https` | Ejecutar la comprobación de alcance a ESPN de más arriba |

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
- El endpoint `/register` valida que `deviceToken` sea exactamente 64 caracteres hexadecimales.
- No hay puertos del router abiertos; todo el ingreso es por Cloudflare Tunnel.
- **El SSH del NAS acepta contraseña.** Una versión anterior de este documento afirmaba que la autenticación era solo por clave con `PasswordAuthentication` desactivado; no es así. Endurecerlo (clave ed25519 y desactivar contraseña) es una tarea pendiente.
- El actualizador de datos no usa credenciales: el `GITHUB_TOKEN` del workflow es efímero y lo emite GitHub en cada ejecución.

---

## Notas sobre la API de ESPN

Base: `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1` (`esp.2` para Segunda).

| Endpoint | Uso |
|---|---|
| `/scoreboard?dates=YYYYMMDD` | Partidos y marcadores de un día |
| `/summary?event={id}` | Alineaciones y `keyEvents` de un partido |
| `/teams` | Los 20 equipos con su `id` y `displayName` |
| `/teams/{id}/roster` | Plantilla, usada por la app |
| `https://a.espncdn.com/i/teamlogos/soccer/500/{id}.png` | Escudo |

### Tipos de `keyEvent`

Verificados sobre 74 partidos reales. **Los goles no tienen un id fijo**: se detectan con `scoringPlay === true`.

| id | Evento | ¿Gol? |
|---|---|---|
| 70 | Goal | sí |
| 137 / 138 / 173 | Goal (cabeza / falta / volea) | sí |
| 97 | Own Goal | sí |
| 98 | Penalty - Scored | sí |
| 94 | Yellow Card | no |
| **93** | **Red Card** | no |
| 114 / 140 | Penalty - Saved / Hit Woodwork | no |
| 76 | Substitution | no |
| 80 / 81 / 82 / 83 | Kickoff / Halftime / Start 2nd Half / End Regular Time | no |

### Trampas conocidas

- `formation` en `rosters` es **un string** (`"3-5-2"`), no un objeto con `displayName`.
- La lista de jugadores está en `roster.roster`, no en `roster.athletes` (que viene a `null`).
- En los `keyEvents`, `athlete` viene a `null` y `team` a menudo también: el jugador y el equipo hay que sacarlos del campo `text`.
- El minuto está en `clock.displayValue` con el formato `"90'+3'"`; `clock.value` no sirve para el descuento.
- `week` viene a `null` en el scoreboard de LaLiga: la jornada no se puede leer de ahí.
- El `displayName` de los equipos cambia con el tiempo. Los actuales relevantes: `Atlético Madrid`, `Celta Vigo`, `Racing Santander`, `Barcelona`, `Athletic Club`, `Real Sociedad`, `Real Betis`, `Rayo Vallecano`.
- **ESPN devuelve 403 al cliente `node:https`** independientemente de las cabeceras. Con `fetch` (undici) y con `curl` responde 200.

### Ids de equipo en ESPN (verificados 16-08-2026)

| Equipo | id | | Equipo | id |
|---|---|---|---|---|
| FC Barcelona | 83 | | Elche | 3751 |
| Real Madrid | 86 | | Málaga | 99 |
| Atlético | 1068 | | Girona | 9812 |
| Athletic | 93 | | Mallorca | 84 |
| R. Sociedad | 89 | | Las Palmas | 98 |
| Betis | 244 | | Valladolid | 95 |
| Villarreal | 102 | | Leganés | 17534 |
| Valencia | 94 | | Cádiz | 3842 |
| Sevilla | 243 | | Granada | 3747 |
| Osasuna | 97 | | Almería | 6832 |
| Celta | 85 | | Real Oviedo | 92 |
| Getafe | 2922 | | | |
| Rayo | 101 | | | |
| Alavés | 96 | | | |
| Espanyol | 88 | | | |
| Levante | 1538 | | | |
| Racing | 87 | | | |
| Deportivo | 90 | | | |

---

## Problemas conocidos

### SofaScore bloquea las peticiones (15-08-2026)

`api.sofascore.com` devuelve **403** a las IPs residenciales, comprobado desde el iMac y desde dentro del contenedor del NAS, con y sin cabeceras de navegador. Consecuencias:

- El poller de avisos **se migró a ESPN**. Resuelto.
- `27/SofaScoreService.swift` sigue apuntando a SofaScore, así que **el gráfico de momentum de la ficha de partido no carga**. Falla en silencio (devuelve `nil`). Pendiente: migrarlo a ESPN o retirar la funcionalidad. Requiere recompilar.

### Las expulsiones no se ven en la ficha de partido

`MatchDetailSheet.swift` filtra los eventos con `nonGoalTypeIDs = ["76","94","95","96"]` y mapea `95`/`96` a roja. En LaLiga **la roja es el `93`** y los ids 95/96 no aparecen ni una vez en 74 partidos analizados, así que las expulsiones se descartan siempre. El JSON ya las trae correctamente desde el 15-08-2026; solo falta corregir la app. Requiere recompilar.

### Escudos incorrectos en temporadas antiguas

`TeamLogoView.logoIDs` y `MatchesData.espnTeamIDs` no coinciden entre sí y varios ids históricos son erróneos. Los valores correctos están en la tabla de arriba.

| Equipo | `logoIDs` | `espnTeamIDs` | Correcto |
|---|---|---|---|
| Mallorca | 95 ❌ (es Valladolid) | 84 ✓ | 84 |
| Las Palmas | 3842 ❌ (es Cádiz) | 98 ✓ | 98 |
| Valladolid | 100 ❌ (es Numancia) | 95 ✓ | 95 |
| Leganés | 6900 ❌ (no existe) | 17534 ✓ | 17534 |
| Cádiz | — | 2948 ❌ (es Marsaxlokk FC) | 3842 |
| Granada | — | 2858 ❌ (no existe) | 3747 |
| Almería | — | 1216 ❌ (no existe) | 6832 |

Solo afecta a las temporadas 24/25 y 25/26. Lo suyo sería unificar ambos diccionarios en uno. Requiere recompilar.

### Nombres de equipo en `topScorers` de temporadas antiguas

Los goleadores de 24/25 y 25/26 los generó `fetch_scorers.py`, cuyo mapa de nombres es distinto: hay entradas como `Alaves` sin tilde, que no casan con el catálogo canónico y dejan al jugador sin escudo en la lista de goleadores. Solo estético y solo en temporadas cerradas.

### Falta un partido en el calendario 26/27

El JSON tiene 379 partidos en vez de 380: falta el **Celta–Osasuna de la jornada 1**, que ESPN no tiene con fecha asignada. Se incorporará solo cuando ESPN lo programe.

---

## Notas de implementación

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

### Doble origen de los detalles de partido

Los detalles (alineaciones y eventos) llegan por dos caminos independientes:

1. El JSON remoto los trae ya parseados por `update_liga.py`, para los partidos terminados.
2. `MatchDetailSheet` los descarga **otra vez** directamente de ESPN al abrir la ficha, con su propio parseo.

Es redundante pero útil: la ficha funciona aunque el JSON esté atrasado. El coste es que **cualquier cambio en el formato de ESPN hay que corregirlo en los dos sitios**, y ahí es donde se coló la discrepancia de la roja `93` frente a `95`/`96`.

---

*Actualizado el 2026-08-16*
