#!/usr/bin/env python3
"""¿Tiene que actuar el suplente, o el titular está haciendo su trabajo?

Desde el 22/08/26 quien publica es el NAS y GitHub Actions solo interviene si
el NAS se calla. La pregunta es cómo distinguir "callado porque está muerto" de
"callado porque no hay nada que contar".

Mirar solo la antigüedad de `lastUpdated` no vale: el NAS no publica cuando lo
único que cambiaría es la marca de tiempo, así que en una mañana sin partidos
puede pasar horas sin un commit estando perfectamente vivo. Con ese criterio a
secas, el suplente saltaba cada 15 minutos a "rescatar" a un titular que estaba
tan campante.

El silencio solo es sospechoso cuando debería haber ruido. Por eso se releva si:

  · hay un partido en juego o a punto, y los datos llevan parados más de
    RELEVO_MINUTOS (durante un partido el NAS publica cada minuto), o
  · los datos llevan parados más de RELEVO_HORAS_MAXIMAS, pase lo que pase:
    red de seguridad para una caída larga, que también hay que enterarse de
    los cambios de calendario.

Código de salida 0 = hay que relevar. 1 = el titular está en su sitio.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

RUTA = os.path.join(os.path.dirname(__file__), "..", "data", "laliga2627.json")
MADRID = ZoneInfo("Europe/Madrid")

RELEVO_MINUTOS = int(os.environ.get("RELEVO_MINUTOS", "15"))
RELEVO_HORAS_MAXIMAS = int(os.environ.get("RELEVO_HORAS_MAXIMAS", "6"))

# El endpoint del titular. Devuelve 503 en cuanto su fichero lleva más de 20
# minutos sin refrescarse, así que un 200 es una señal de vida directa: no hay
# que deducirla de la antigüedad de los datos, que se congela legítimamente
# cuando no hay nada nuevo que contar.
ENDPOINT = os.environ.get(
    "LALIGA_ENDPOINT", "https://laliga-api.cornellanas.net/datos/laliga2627.json")

# Cuánto rato alrededor de un partido se considera "debería haber ruido".
# Antes del saque, por el margen previo del updater; después, porque 105
# minutos no cubren prórrogas de tiempo añadido ni finales eternos.
ANTES_DEL_SAQUE = timedelta(minutes=45)
DESPUES_DEL_SAQUE = timedelta(hours=2, minutes=45)


def titular_responde():
    """¿Contesta el NAS con datos frescos? None si no se puede saber."""
    for metodo in ("HEAD", "GET"):
        try:
            # Con el User-Agent por defecto de Python, Cloudflare devuelve 403
            # y el titular parecería muerto siempre.
            peticion = urllib.request.Request(
                ENDPOINT, method=metodo,
                headers={"User-Agent": "laliga-relevo/1.0 (+github-actions)"})
            with urllib.request.urlopen(peticion, timeout=10) as r:
                if r.status == 200:
                    return True
        except urllib.error.HTTPError as e:
            if e.code == 503:       # el propio servidor dice que están rancios
                return False
            continue                # otro código: se prueba con GET
        except Exception:           # noqa: BLE001 — red, DNS, timeout…
            return None
    return None


def relevar(razon):
    print(f"RELEVO: {razon}")
    sys.exit(0)


def esperar(razon):
    print(f"El titular está en su sitio: {razon}")
    sys.exit(1)


def main():
    ahora = datetime.now(timezone.utc)

    try:
        with open(RUTA, encoding="utf-8") as f:
            datos = json.load(f)
    except Exception as e:                  # noqa: BLE001
        relevar(f"no se puede leer el JSON publicado ({e})")

    try:
        marca = datos["lastUpdated"]
        publicado = datetime.strptime(marca, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except Exception as e:                  # noqa: BLE001
        relevar(f"marca de tiempo ilegible ({e})")

    edad = int((ahora - publicado).total_seconds() // 60)

    if edad >= RELEVO_HORAS_MAXIMAS * 60:
        # Antes de dar por muerto al titular por llevar horas callado, se le
        # pregunta. En una jornada sin partidos calla porque no hay novedades,
        # y sin esta comprobación el suplente entraba a "rescatarlo" cada seis
        # horas, ensuciando justo la señal que sirve de alarma: un commit de
        # github-actions[bot] tiene que significar que el NAS se cayó.
        vivo = titular_responde()
        if vivo is True:
            esperar(f"lleva {edad} min sin publicar, pero su endpoint responde: "
                    "está vivo y no hay novedades")
        motivo = "no responde" if vivo is False else "no se le puede preguntar"
        relevar(f"los datos llevan {edad} min parados ({motivo} el titular)")

    # ¿Debería estar pasando algo ahora mismo?
    en_marcha = []
    for dia in datos.get("matchDays", []):
        for partido in dia.get("games", []):
            nombre = f"{partido.get('home')}-{partido.get('away')}"
            if partido.get("state") == "in":
                en_marcha.append(nombre)
                continue
            if partido.get("done"):
                continue
            hora = partido.get("time") or ""
            if ":" not in hora:
                continue
            try:
                saque = datetime.strptime(f"{dia['date']} {hora}", "%Y-%m-%d %H:%M")
                saque = saque.replace(tzinfo=MADRID).astimezone(timezone.utc)
            except ValueError:
                continue
            if saque - ANTES_DEL_SAQUE <= ahora <= saque + DESPUES_DEL_SAQUE:
                en_marcha.append(nombre)

    if not en_marcha:
        esperar(f"no hay partidos ahora (datos de hace {edad} min, y sin novedades no publica)")

    if edad >= RELEVO_MINUTOS:
        relevar(f"hay partido ({', '.join(en_marcha[:3])}) y los datos llevan {edad} min parados")

    esperar(f"publicando durante {', '.join(en_marcha[:3])} (hace {edad} min)")


if __name__ == "__main__":
    main()
