#!/bin/bash
# Quita el actualizador del NAS. No toca laliga-api, ni los WordPress, ni el
# repositorio de GitHub, ni el workflow, ni la app: nada de eso ha dependido
# nunca de esto.
#
#     ./nas/desinstalar.sh          → para y borra el contenedor
#     ./nas/desinstalar.sh --todo   → además borra datos, log e imagen

set -uo pipefail
NAS="${LALIGA_NAS_HOST:-nas}"
DIR=/share/Container/laliga-updater
DOCKER='export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; export DOCKER_CONFIG=$HOME/.docker; mkdir -p $DOCKER_CONFIG'

ssh "$NAS" "$DOCKER; cd $DIR 2>/dev/null && docker compose down" && echo "  ✓ contenedor parado y eliminado"

if [ "${1:-}" = "--todo" ]; then
    ssh "$NAS" "$DOCKER; docker rmi laliga-updater-laliga-updater 2>/dev/null; rm -rf $DIR"
    echo "  ✓ imagen, datos y log borrados"
else
    echo "  · los datos y el log siguen en $DIR/estado (bórralos con --todo)"
fi
