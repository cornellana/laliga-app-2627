#!/usr/bin/env python3
"""Minutos transcurridos desde la última publicación de datos.

Lo usa el workflow para decidir si tiene algo que hacer: desde el 22/08/26 el
titular es el NAS y GitHub Actions solo actúa si los datos llevan rato sin
refrescarse. Ante cualquier duda —fichero ilegible, marca corrupta— devuelve un
número enorme, porque el fallo seguro es actuar de más, no de menos.
"""

import json
import os
import sys
from datetime import datetime, timezone

RUTA = os.path.join(os.path.dirname(__file__), "..", "data", "laliga2627.json")

try:
    with open(RUTA, encoding="utf-8") as f:
        marca = json.load(f)["lastUpdated"]
    publicado = datetime.strptime(marca, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    minutos = int((datetime.now(timezone.utc) - publicado).total_seconds() // 60)
    print(max(minutos, 0))
except Exception as e:                      # noqa: BLE001 — cualquier fallo cuenta igual
    print(f"no se pudo leer la marca de tiempo ({e}); asumo datos viejos",
          file=sys.stderr)
    print(9999)
