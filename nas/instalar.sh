#!/bin/bash
# Instala el actualizador en el NAS, en MODO SOMBRA.
#
#     ./nas/instalar.sh
#
# Modo sombra = genera los datos y los compara con lo publicado, pero NO
# publica. GitHub Actions sigue alimentando la app exactamente igual que hasta
# ahora, así que esto se puede instalar en mitad de una jornada sin riesgo: si
# el demonio se equivoca, no se entera nadie.
#
# Es idempotente: relanzarlo actualiza la imagen y recrea el contenedor.
# Para quitarlo del todo:  ./nas/desinstalar.sh

set -euo pipefail
NAS="${LALIGA_NAS_HOST:-nas}"
DIR=/share/Container/laliga-updater
DOCKER='export DOCKER_HOST=unix:///var/run/docker.sock; /share/ZFS530_DATA/.qpkg/container-station/bin/docker'
AQUI="$(cd "$(dirname "$0")" && pwd)"

echo "── 1. Comprobando el NAS ─────────────────────────────────"
"$AQUI/comprobar-nas.sh" || { echo "Falta algo; no sigo."; exit 1; }

echo
echo "── 2. Copiando la receta del contenedor ──────────────────"
ssh "$NAS" "mkdir -p $DIR/estado $DIR/repo"
scp -q "$AQUI/Dockerfile" "$AQUI/entrypoint.sh" "$AQUI/docker-compose.yml" "$NAS:$DIR/"
echo "  ✓ Dockerfile, entrypoint.sh y docker-compose.yml en $DIR"
echo "  · el demonio no se copia: el contenedor lo saca del propio repositorio,"
echo "    así que actualizarlo será 'git push' + reiniciar el contenedor."

echo
echo "── 3. Construyendo y arrancando (tarda un par de minutos) ─"
ssh "$NAS" "$DOCKER; cd $DIR && docker compose up -d --build"

echo
echo "── 4. Primeros ciclos ────────────────────────────────────"
sleep 25
ssh "$NAS" "$DOCKER; docker logs --tail 30 laliga-updater" || true

cat <<FIN

── Listo ─────────────────────────────────────────────────
Corriendo en MODO SOMBRA: no publica, solo compara.

  Seguir el log:      ssh $NAS 'export DOCKER_HOST=unix:///var/run/docker.sock; /share/ZFS530_DATA/.qpkg/container-station/bin/docker logs -f laliga-updater'
  Estado de un vistazo: ssh $NAS 'cat $DIR/estado/salud.json'
  Pararlo:            ssh $NAS "\$DOCKER; cd $DIR && docker compose down"

Lo que hay que ver mañana: que durante un partido escriba una línea "≡"
por cada comparación (coincide con lo publicado) y ninguna "≠" que no se
explique por los 3 minutos de desfase del cron de GitHub.
FIN
