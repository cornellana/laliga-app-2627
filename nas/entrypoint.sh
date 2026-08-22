#!/bin/sh
# Pone al día el clon del repositorio y arranca el demonio.
#
# El demonio vive DENTRO del repositorio (nas/laliga_daemon.py), así que
# actualizarlo es un `git push` desde el Mac y un reinicio del contenedor. No
# hay copias sueltas del código dando vueltas por el NAS.
set -e

REPO="${LALIGA_REPO:-/repo}"
URL="${LALIGA_REPO_URL:-https://github.com/cornellana/laliga-app-2627.git}"

# ANTES de tocar el clon, no después: el volumen viene del host y es de otro
# dueño, así que git se niega a operar en él ("dubious ownership") y el fetch
# falla en silencio. Pasó el 22/08: el contenedor se reinició con el código
# viejo y el arreglo recién publicado no llegó a correr.
git config --global --add safe.directory "$REPO" 2>/dev/null || true

if [ -d "$REPO/.git" ]; then
    echo "Actualizando el clon en $REPO…"
    git -C "$REPO" fetch -q origin main || echo "  (sin red: sigo con lo que hay clonado)"
    git -C "$REPO" checkout -q -B main origin/main || true
else
    echo "Clonando $URL en $REPO…"
    git clone -q "$URL" "$REPO"
fi

echo "Versión del repositorio: $(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || echo desconocida)"
exec python3 "$REPO/nas/laliga_daemon.py"
