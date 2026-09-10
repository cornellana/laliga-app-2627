#!/usr/bin/env bash
#
# desplegar-api.sh — sube laliga-api al NAS y comprueba que las DOS
# competiciones siguen en pie.
#
#   ./nas/desplegar-api.sh
#
# Existe porque este servicio es el titular de La Liga en marcha: cualquier
# despliegue lo toca. El guion hace copia de seguridad antes, verifica después
# —La Liga primero, la Champions después— y si algo no responde dice cómo
# volver atrás en una sola orden.
#
# Hay que estar en la red de casa: el NAS solo escucha por SSH en la LAN.

set -euo pipefail

cd "$(dirname "$0")/.."

REMOTO="/share/Container/laliga-api"
API="nas/laliga-api"
# server.js viaja DENTRO de la imagen (`COPY . .`), así que un `up -d` a secas
# recrearía el contenedor con el código viejo y parecería que no ha pasado nada.
# `DOCKER_BUILDKIT=0` no es opcional: el BuildKit de Container Station falla al
# montar los datasets ZFS de las capas y ni siquiera llega a leer el Dockerfile
# («error creating zfs mount»). Con el constructor clásico va bien.
ENTORNO='export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; export DOCKER_CONFIG=$HOME/.docker; export DOCKER_BUILDKIT=0'
BASE="https://laliga-api.cornellanas.net"

FICHEROS=(server.js poller.js store.js apns.js championsTeams.js teamMatches.js docker-compose.yml)

# -- ¿Se llega al NAS? -------------------------------------------------------

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes nas true 2>/dev/null; then
  echo "❌ No se llega al NAS por SSH."
  echo "   Solo escucha en la red de casa: comprueba que estás en esa wifi."
  exit 1
fi

# -- Copia de seguridad ------------------------------------------------------

SELLO=$(date +%Y%m%d-%H%M%S)
echo "▸ Copia de seguridad en $REMOTO/copias/$SELLO"
ssh nas "mkdir -p $REMOTO/copias/$SELLO && cd $REMOTO && cp -p *.js docker-compose.yml copias/$SELLO/ 2>/dev/null || true"

# -- Subir -------------------------------------------------------------------

echo "▸ Subiendo"
for f in "${FICHEROS[@]}"; do
  [[ -f "$API/$f" ]] || continue
  scp -qO "$API/$f" "nas:$REMOTO/$f"
  echo "  · $f"
done

echo "▸ Reconstruyendo el contenedor"
ssh nas "$ENTORNO; cd $REMOTO && docker compose up -d --build" 2>&1 | tail -5

echo "▸ Esperando a que arranque"
for i in $(seq 1 20); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$BASE/health")" == "200" ]] && break
  sleep 3
done

# -- Verificar ---------------------------------------------------------------
#
# Un cuerpo vacío hace que el registro conteste 400 sin guardar nada, así que
# vale para saber si la ruta existe sin dejar un token de mentira dentro.

echo "▸ Comprobando"
FALLOS=0
comprobar() {
  local etiqueta="$1" esperado="$2" obtenido="$3"
  if [[ "$obtenido" == "$esperado" ]]; then
    echo "  ✅ $etiqueta"
  else
    echo "  ❌ $etiqueta → esperaba $esperado y ha dado $obtenido"
    FALLOS=$((FALLOS + 1))
  fi
}

post_vacio() {
  curl -s -o /dev/null -w "%{http_code}" -m 15 -X POST \
    -H 'Content-Type: application/json' -d '{}' "$BASE$1"
}
get() { curl -s -o /dev/null -w "%{http_code}" -m 20 "$BASE$1"; }

comprobar "el servicio responde"          200 "$(get /health)"
comprobar "La Liga: /register"            400 "$(post_vacio /register)"
comprobar "La Liga: /unregister"          400 "$(post_vacio /unregister)"
comprobar "La Liga: los datos"            200 "$(get /datos/laliga2627.json)"
comprobar "Champions: /champions/register"   400 "$(post_vacio /champions/register)"
comprobar "Champions: /champions/unregister" 400 "$(post_vacio /champions/unregister)"
comprobar "Champions: los datos"          200 "$(get /datos/champions2627.json)"

echo
if [[ $FALLOS -gt 0 ]]; then
  echo "⚠️  $FALLOS comprobación(es) han fallado. Para volver atrás:"
  echo
  echo "  ssh nas '$ENTORNO; cd $REMOTO && cp copias/$SELLO/* . && docker compose up -d --build'"
  exit 1
fi

echo "✅ Desplegado. La Liga sigue en pie y la Champions ya acepta registros."
echo
echo "   Falta que los teléfonos se den de alta: la app lo intenta al abrirse."
echo "   Abre la Champions en el iPhone, con los avisos activados, y míralo:"
echo
echo "     ssh nas '$ENTORNO; docker logs --tail 40 laliga-api | grep register'"
