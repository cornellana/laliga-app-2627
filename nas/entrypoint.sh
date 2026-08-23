#!/bin/sh
# Pone al día el clon del repositorio y arranca el demonio.
#
# El demonio vive DENTRO del repositorio (nas/laliga_daemon.py), así que
# actualizarlo es un `git push` desde el Mac y un reinicio del contenedor. No
# hay copias sueltas del código dando vueltas por el NAS.
set -e

REPO="${LALIGA_REPO:-/repo}"
URL="${LALIGA_REPO_URL:-https://github.com/cornellana/laliga-app-2627.git}"
CLAVE="${LALIGA_DEPLOY_KEY:-/estado/ssh/id_ed25519}"

# La clave se prepara ANTES de tocar el clon, no después. El clon guarda el
# remoto por SSH de arranques anteriores, así que sin GIT_SSH_COMMAND el fetch
# de aquí abajo muere con "Host key verification failed" y el contenedor
# arranca con el código de la vez pasada. Pasó el 23/08: el log decía "sin red"
# y el demonio corrió unos minutos con un commit viejo antes de recuperarse
# solo en su primer ciclo.
if [ -f "$CLAVE" ]; then
    chmod 600 "$CLAVE" 2>/dev/null || true
    export GIT_SSH_COMMAND="ssh -i $CLAVE -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/estado/ssh/known_hosts"
fi

# ANTES de tocar el clon, no después: el volumen viene del host y es de otro
# dueño, así que git se niega a operar en él ("dubious ownership") y el fetch
# falla en silencio. Pasó el 22/08: el contenedor se reinició con el código
# viejo y el arreglo recién publicado no llegó a correr.
git config --global --add safe.directory "$REPO" 2>/dev/null || true

if [ -d "$REPO/.git" ]; then
    echo "Actualizando el clon en $REPO…"
    git -C "$REPO" fetch -q origin main \
        || echo "  (no se pudo contactar con el remoto: sigo con lo que hay clonado)"
    git -C "$REPO" checkout -q -B main origin/main || true
else
    echo "Clonando $URL en $REPO…"
    git clone -q "$URL" "$REPO"
fi

# Quién firma los commits que publique el NAS. Se distingue a simple vista de
# los de github-actions[bot], que es justo lo que interesa mientras conviven.
git -C "$REPO" config user.name  "laliga-nas[bot]"
git -C "$REPO" config user.email "laliga-nas@cornellanas.net"

# Con deploy key se empuja por SSH. Sin clave el clon sigue siendo de solo
# lectura por HTTPS, que es lo que necesita el modo sombra. El remoto se fija
# aquí y no arriba porque el `git clone` de un arranque en frío se hace por
# HTTPS, y hasta que no existe el clon no hay dónde escribir el remoto.
if [ -f "$CLAVE" ]; then
    git -C "$REPO" remote set-url origin "git@github.com:cornellana/laliga-app-2627.git"
    echo "Deploy key encontrada: el remoto se usa por SSH (se puede publicar)."
else
    echo "Sin deploy key: remoto de solo lectura (modo sombra)."
fi

echo "Versión del repositorio: $(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || echo desconocida)"
exec python3 "$REPO/nas/laliga_daemon.py"
