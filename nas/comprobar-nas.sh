#!/bin/bash
# Comprobación previa del NAS. NO instala ni cambia nada: solo mira si están
# las piezas que hacen falta. Se ejecuta desde el Mac.
#
#     ./nas/comprobar-nas.sh
#
# Sale con 0 si el NAS está listo, 1 si falta algo.

set -uo pipefail
NAS="${LALIGA_NAS_HOST:-nas}"
DOCKER='export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; export DOCKER_CONFIG=$HOME/.docker; mkdir -p $DOCKER_CONFIG'
FALLOS=0

bien()  { printf '  ✓ %s\n' "$*"; }
mal()   { printf '  ✗ %s\n' "$*"; FALLOS=$((FALLOS+1)); }
nota()  { printf '  · %s\n' "$*"; }

echo "── Acceso ────────────────────────────────────────────────"
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$NAS" 'echo ok' >/dev/null 2>&1; then
    mal "no se entra por SSH a '$NAS' sin contraseña"
    echo
    echo "  Arréglalo en una ventana de Terminal y repite:"
    echo "      eval \"\$(ssh-agent -s)\" && ssh-add --apple-use-keychain ~/.ssh/qnap_key"
    exit 1
fi
bien "SSH sin contraseña"
nota "$(ssh "$NAS" 'uptime' 2>/dev/null | sed 's/^ *//')"

echo "── Docker ────────────────────────────────────────────────"
V=$(ssh "$NAS" "$DOCKER; docker version --format '{{.Server.Version}}'" 2>/dev/null)
if [ -n "$V" ]; then bien "docker $V"; else mal "no responde el docker de Container Station"; fi

C=$(ssh "$NAS" "$DOCKER; docker compose version" 2>/dev/null | head -1)
if [ -n "$C" ]; then bien "$C"; else mal "no está el plugin 'docker compose'"; fi

if ssh "$NAS" "$DOCKER; docker ps --format '{{.Names}}' | grep -qx laliga-updater" 2>/dev/null; then
    nota "el contenedor laliga-updater YA existe (se recreará al instalar)"
fi

echo "── Lo que ya hay corriendo (no se toca) ──────────────────"
ssh "$NAS" "$DOCKER; docker ps --format '{{.Names}}\t{{.Status}}'" 2>/dev/null \
    | grep -E 'laliga|wordpress|cloudflare' | sed 's/^/  · /'

echo "── Red y espacio ─────────────────────────────────────────"
if ssh "$NAS" 'curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/scoreboard"' 2>/dev/null | grep -q 200; then
    bien "el NAS llega a la API de ESPN"
else
    mal "el NAS no llega a ESPN (sin eso no hay nada que hacer)"
fi
nota "espacio en /share/Container: $(ssh "$NAS" 'df -h /share/Container 2>/dev/null | tail -1' | awk '{print $4" libres"}')"

echo
if [ "$FALLOS" -eq 0 ]; then
    echo "Todo listo. Siguiente paso:  ./nas/instalar.sh"
else
    echo "$FALLOS cosa(s) por resolver antes de instalar."
fi
[ "$FALLOS" -eq 0 ]
