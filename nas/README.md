# Actualizador de La Liga en el NAS

Desde el **22/08/26 el NAS es el titular**: actualiza cada 60 segundos durante
los partidos y publica él en GitHub. El workflow de GitHub Actions sigue ahí,
pero como suplente: solo actúa si el NAS se calla.

## Por qué

Tres fallos en dos días, los tres de la misma raíz — GitHub dispara cuando
quiere y obliga a coordinar procesos que no se conocen entre sí:

| Cuándo | Qué pasó |
|---|---|
| 20/08 19:01 | El bucle se apagó un minuto después del saque: ESPN todavía marcaba el partido como `pre` y la ventana previa no admitía minutos negativos. |
| 21/08 18:35→19:14 | El cron no disparó en 39 minutos. El Betis–Real Sociedad empezó sin cobertura y hubo que lanzarlo a mano. |
| 21/08 19:34→19:58 | Dos ejecuciones se pelearon por el mismo push; el `pull --rebase` de emergencia metió marcadores de conflicto dentro del JSON y el bucle estuvo 24 minutos girando en vacío, ocupando el turno de concurrencia. |

Un solo proceso con su propio reloj no tiene ninguno de los tres. Y el NAS ya
consulta ESPN 24/7 para las notificaciones push (`laliga-api`), así que el
terreno está probado.

## Qué hay montado

Un contenedor, `laliga-updater`, al lado de `laliga-api`, con `restart: always`
para que vuelva solo tras un reinicio o un corte de luz.

```
/share/Container/laliga-updater/
├── Dockerfile  docker-compose.yml  entrypoint.sh
├── repo/       clon del repositorio (de ahí sale el código)
└── estado/     laliga2627.json de trabajo · laliga.log · salud.json
```

El demonio **no reimplementa nada**: ejecuta `scripts/update_liga.py` como
subproceso, el mismo fichero que usa el workflow, sacado del clon. Así no hay
dos copias de la lógica que puedan divergir. Actualizarlo es `git push` desde
el Mac y reiniciar el contenedor.

El NAS no trae pip, ni requests, ni git — de ahí el contenedor en vez de un
cron del QNAP.

## Reparto de papeles

| | Titular (NAS) | Suplente (GitHub Actions) |
|---|---|---|
| Ritmo | 60 s con partido · 10 min en reposo | Cada 15 min comprueba y sale en segundos |
| Cuándo publica | Siempre que haya un dato nuevo | Solo si los datos llevan >15 min sin refrescarse |
| Firma los commits como | `laliga-nas[bot]` | `github-actions[bot]` |

El suplente mira la marca `lastUpdated` del JSON publicado (`scripts/edad_datos.py`).
Si es reciente, el titular está vivo y no hace nada. Si no —corte de luz, de
fibra, contenedor caído— toma el relevo con el bucle de siempre. Un disparo
manual del workflow se salta la comprobación y actúa igualmente.

Ver un `github-actions[bot]` en el historial de commits significa que el NAS
estuvo caído. Es la señal de alarma que hay que vigilar.

## Los dos modos

**`sombra`**: trabaja sobre su propia copia del JSON en `/estado`,
no publica nada, y después de cada ciclo compara lo que él generaría con lo que
hay publicado en GitHub. En el log:

```
✓ ciclo 12 · PARTIDO EN JUEGO
   En juego o a punto de empezar (1): Sevilla at Athletic
   ≡ Athletic-Sevilla: 1-0 34' (7 eventos) — coincide
```

Una línea `≠` significa desviación. Durante un partido es normal ver alguna:
el NAS mira cada 60 s y GitHub cada 3 min, así que el NAS va por delante. Lo
que no debe pasar es que el NAS se quede atrás o invente datos.

**`produccion`** (el actual): publica él. Cada ciclo parte del remoto
(`rebase --abort` + `fetch` + `checkout -B main origin/main`), así que no puede
repetirse el atasco del 21/08. Empuja por SSH con una deploy key de escritura
guardada en `estado/ssh/`, dada de alta en Settings → Deploy keys del
repositorio. El modo se fija en el fichero `.env` del NAS:

```
LALIGA_MODO=produccion     # sombra para volver a observar sin publicar
```

No publica cuando lo único que ha cambiado es `lastUpdated`: el updater
reescribe esa marca en cada pasada y, a 60 segundos por ciclo, serían más de
mil commits diarios sin un solo dato nuevo.

## Uso diario

```bash
# seguir el log en vivo
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; docker logs -f laliga-updater'

# estado de un vistazo
ssh nas 'cat /share/Container/laliga-updater/estado/salud.json'

# actualizar el demonio tras un push
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; docker restart laliga-updater'
```

Desde el Mac: `./nas/comprobar-nas.sh` (no toca nada), `./nas/instalar.sh`
(idempotente), `./nas/desinstalar.sh` (lo quita; con `--todo` borra también
datos e imagen).

`docker restart` basta cuando el cambio está en el repositorio, porque el
entrypoint hace `fetch` al arrancar. Si el cambio toca el `Dockerfile` o el
propio `entrypoint.sh`, que viajan dentro de la imagen, hay que reconstruirla.
**Con `DOCKER_BUILDKIT=0`**: el BuildKit de Container Station falla al montar
los datasets de las capas y ni siquiera llega a leer el `Dockerfile`:

```
failed to solve: failed to read dockerfile: error creating zfs mount:
mount zpool1/zfs530/zfs5300002/… : no such file or directory
```

El constructor clásico usa el mismo almacenamiento y sí funciona:

```bash
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; export DOCKER_CONFIG=$HOME/.docker; export DOCKER_BUILDKIT=0; cd /share/Container/laliga-updater && docker build -t laliga-updater-laliga-updater . && docker compose up -d --force-recreate'
```

## Volver atrás

Si algo va mal, devolver el mando a GitHub Actions es una línea:

```bash
ssh nas 'sed -i s/produccion/sombra/ /share/Container/laliga-updater/.env'
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; cd /share/Container/laliga-updater && docker compose up -d'
```

El NAS deja de publicar, los datos envejecen, y en 15 minutos como mucho el
workflow ve que nadie publica y retoma el trabajo solo. No hay que tocar nada
en GitHub.

## Lo que queda pendiente

- **El techo de los 5 minutos.** La app lee el JSON de
  `raw.githubusercontent.com`, cuya CDN cachea unos 5 minutos. Da igual que el
  NAS publique cada 60 segundos: la app no verá los datos más frescos que eso.
  Romper ese techo pasa por servir el JSON desde `laliga-api.cornellanas.net`
  y tocar `Models.swift`, es decir, una versión nueva en TestFlight.
- **Un aviso cuando el NAS se caiga.** Hoy hay que mirar el historial de
  commits para enterarse. El NAS ya sabe mandar notificaciones push, así que
  la pieza está a mano.
