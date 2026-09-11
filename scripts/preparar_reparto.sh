#!/usr/bin/env bash
#
# preparar_reparto.sh — lo que hay que hacer justo antes de compilar La Liga
# para repartirla.
#
# Lo llama solo `Reparto/repartir.sh`, que busca este fichero en cada proyecto
# y lo ejecuta si existe. Aquí va lo propio de esta app; firmar, publicar y
# verificar es común y vive allí.

set -euo pipefail

cd "$(dirname "$0")/.."

# El calendario viaja dentro de la app como semilla, para que arranque con
# algo aunque no haya red. Hasta el 11/09/26 nadie lo refrescaba al repartir y
# la build 4 salió con el del 21 de julio, de antes de empezar la temporada:
# el probador veía la jornada 0 hasta que la app terminaba de bajarse la de
# verdad.
#
# Solo se copia si los datos son más nuevos que la semilla. Las temporadas
# terminadas ya no cambian, y así nunca se pisa una semilla buena con datos
# más viejos.
for datos in data/laliga*.json; do
  temporada=$(basename "$datos" .json)
  semilla="27/${temporada}-seed.json"
  [[ -f "$semilla" ]] || continue
  if python3 - "$datos" "$semilla" <<'PY'
import json, sys
datos, semilla = (json.load(open(p)).get("lastUpdated", "") for p in sys.argv[1:3])
sys.exit(0 if datos > semilla else 1)
PY
  then
    cp "$datos" "$semilla"
    echo "  · $semilla al día"
  fi
done
