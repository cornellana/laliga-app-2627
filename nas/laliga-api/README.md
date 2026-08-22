# Cambios en `laliga-api`

Copia de lo que corre en el NAS en `/share/Container/laliga-api/`, para que el
cambio quede en el repositorio y no solo dentro del contenedor. El resto del
servicio —`poller.js`, `apns.js`, `store.js`, la base de datos— no se ha tocado
y vive únicamente en el NAS.

## Qué se añadió

Una ruta, `GET /datos/laliga2627.json`, que sirve el JSON que deja el contenedor
`laliga-updater` en una carpeta compartida montada en solo lectura.

La app la prefiere a `raw.githubusercontent.com` porque la CDN de GitHub cachea
unos cinco minutos; aquí los datos llegan segundos después de generarse.

## El detalle que importa: la caducidad

Si el actualizador muriera, este servicio seguiría sirviendo tan tranquilo un
fichero congelado, y la app lo preferiría a los datos de GitHub, que en ese
escenario sí estarían al día — el suplente habría tomado el relevo. Sería peor
el remedio que la enfermedad.

Por eso la ruta mira la fecha del fichero antes de servirlo y devuelve **503 si
lleva más de 20 minutos sin refrescarse** (`DATOS_CADUCAN_MS`). El actualizador
lo reescribe en cada ciclo —60 s con partido, 10 min en reposo— aunque el
contenido no cambie, así que esa fecha es una señal de vida fiable.

Con el 503, la app se va sola a GitHub sin enterarse de nada. La lógica está
aquí y no en la app a propósito: se puede ajustar el umbral sin publicar una
versión nueva en TestFlight.

## Desplegar un cambio

```bash
scp -O nas/laliga-api/server.js nas:/share/Container/laliga-api/server.js
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; export DOCKER_CONFIG=$HOME/.docker; cd /share/Container/laliga-api && docker compose up -d --build'
```

**Con `--build`**: `server.js` viaja dentro de la imagen (`COPY . .`), así que un
`up -d` a secas recrea el contenedor con el código viejo y parece que el cambio
no ha surtido efecto.

Después conviene comprobar que las notificaciones siguen en pie, no solo la ruta
nueva:

```bash
curl -s https://laliga-api.cornellanas.net/health
curl -s -X POST https://laliga-api.cornellanas.net/register -H 'Content-Type: application/json' \
  -d '{"deviceToken":"00000000000000000000000000000000000000000000000000000000deadbeef","environment":"sandbox","teams":["FC Barcelona"],"prefs":{"enabled":true}}'
curl -s -X POST https://laliga-api.cornellanas.net/unregister -H 'Content-Type: application/json' \
  -d '{"deviceToken":"00000000000000000000000000000000000000000000000000000000deadbeef"}'
```

Hay copias con fecha de los ficheros originales en la misma carpeta del NAS
(`server.js.bak-*`, `docker-compose.yml.bak-*`).
