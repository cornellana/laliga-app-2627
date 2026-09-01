#!/usr/bin/env python3
"""Actualizador continuo de La Liga para el NAS.

Por qué existe: el cron de GitHub no baja de 5 minutos, llega cuando puede
—el 20 y el 21/08/26 se midieron retrasos de 16 a 39 minutos, y uno de ellos
se tragó entero el saque inicial— y serializa las ejecuciones por
concurrencia. El 21/08 dos de ellas se pelearon por el mismo push, el rebase
de emergencia dejó marcadores de conflicto dentro del JSON y el bucle estuvo
24 minutos girando en vacío en plena primera parte. Un solo proceso con su
propio reloj no tiene ninguno de esos tres problemas.

Arranca en MODO SOMBRA: genera los datos en su propia copia y los compara con
lo que hay publicado en GitHub, pero no publica nada. Así puede pasarse una
jornada entera demostrando que funciona sin tocar lo que ya está en marcha.
Cuando convenza, `LALIGA_MODO=produccion` y empieza a publicar él.

No llama a la API de ESPN por su cuenta: ejecuta scripts/update_liga.py, el
mismo que usa GitHub Actions, como subproceso. Así no hay dos copias de la
lógica que puedan divergir, y un fallo en un ciclo no se lleva por delante al
demonio.

Variables de entorno (todas con valor por defecto razonable):
    LALIGA_MODO              sombra | produccion          (por defecto: sombra)
    LALIGA_REPO              clon del repositorio          (~/laliga-app-2627)
    LALIGA_DATOS             JSON de trabajo en sombra     (<base>/datos/…)
    LALIGA_INTERVALO_VIVO    segundos entre ciclos con partido   (60)
    LALIGA_INTERVALO_REPOSO  segundos entre ciclos sin partido   (600)
    LALIGA_LOG               fichero de log                (<base>/laliga.log)
    LALIGA_PUBLICAR_EN       carpeta donde copiar el JSON servido (opcional)
"""

import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

BASE = os.path.dirname(os.path.abspath(__file__))
CASA = os.path.expanduser("~")

MODO              = os.environ.get("LALIGA_MODO", "sombra").strip().lower()
REPO              = os.environ.get("LALIGA_REPO", os.path.join(CASA, "laliga-app-2627"))
UPDATER           = os.path.join(REPO, "scripts", "update_liga.py")
DATOS_REPO        = os.path.join(REPO, "data", "laliga2627.json")
DATOS_SOMBRA      = os.environ.get("LALIGA_DATOS", os.path.join(BASE, "datos", "laliga2627.json"))
INTERVALO_VIVO    = int(os.environ.get("LALIGA_INTERVALO_VIVO", "60"))
INTERVALO_REPOSO  = int(os.environ.get("LALIGA_INTERVALO_REPOSO", "600"))
# Los ficheros de estado no pueden vivir dentro del clon del repositorio: en
# producción cada ciclo hace `checkout -B main origin/main` y se los llevaría
# por delante (o ensuciarían el árbol y romperían el push).
ESTADO_DIR        = os.environ.get("LALIGA_ESTADO_DIR", BASE)
LOG               = os.environ.get("LALIGA_LOG", os.path.join(ESTADO_DIR, "laliga.log"))
SALUD             = os.path.join(ESTADO_DIR, "salud.json")
BANDERA_ACTIVOS   = os.path.join(ESTADO_DIR, "activos.flag")
os.makedirs(ESTADO_DIR, exist_ok=True)
PUBLICAR_EN       = os.environ.get("LALIGA_PUBLICAR_EN", "").strip()

PUBLICADO_URL = ("https://raw.githubusercontent.com/cornellana/"
                 "laliga-app-2627/main/data/laliga2627.json")

# El updater tarda ~2 s; 180 es un tope generoso para que una llamada colgada a
# ESPN no congele el ciclo para siempre.
TOPE_UPDATER_SEGUNDOS = 180
TOPE_LOG_BYTES = 5 * 1024 * 1024

_parar = False


def _senal(num, _frame):
    global _parar
    _parar = True
    registrar(f"Recibida señal {num}: terminando al acabar el ciclo.")


def ahora():
    return datetime.now(timezone.utc)


def registrar(mensaje):
    """Una línea al log y a stdout. El log se trunca solo si engorda."""
    linea = f"{ahora().strftime('%Y-%m-%d %H:%M:%S')}Z  {mensaje}"
    print(linea, flush=True)
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > TOPE_LOG_BYTES:
            with open(LOG, encoding="utf-8", errors="replace") as f:
                cola = f.readlines()[-2000:]
            with open(LOG, "w", encoding="utf-8") as f:
                f.writelines(cola)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(linea + "\n")
    except OSError as e:
        print(f"(no se pudo escribir el log: {e})", flush=True)


def fichero_de_datos():
    return DATOS_REPO if MODO == "produccion" else DATOS_SOMBRA


def git(*args, capturar=True):
    """git dentro del clon. Devuelve (ok, salida)."""
    try:
        r = subprocess.run(["git", "-C", REPO, *args],
                           capture_output=capturar, text=True, timeout=120)
        return r.returncode == 0, ((r.stdout or "") + (r.stderr or "")).strip()
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, str(e)


def sincronizar_con_remoto():
    """Partir siempre del remoto, como hace ya el workflow.

    Si el push anterior se cruzó con otra ejecución, se descarta el intento: el
    JSON se reconstruye entero desde ESPN en cada pasada, así que no hay nada
    que conservar y así no puede haber conflicto.
    """
    git("rebase", "--abort")
    ok, salida = git("fetch", "-q", "origin", "main")
    if not ok:
        registrar(f"⚠️  fetch falló: {salida[:200]}")
        return False
    ok, salida = git("checkout", "-q", "-B", "main", "origin/main")
    if not ok:
        registrar(f"⚠️  no se pudo situar main sobre origin/main: {salida[:200]}")
    return ok


def ejecutar_updater():
    """Lanza scripts/update_liga.py. Devuelve (ok, líneas interesantes)."""
    entorno = dict(os.environ)
    entorno["ACTIVE_FLAG_FILE"] = BANDERA_ACTIVOS
    entorno["LALIGA_DATA_FILE"] = fichero_de_datos()
    entorno.setdefault("PRE_MATCH_MINUTES", "45")
    entorno["FORCE_REFRESH"] = "false"
    try:
        r = subprocess.run([sys.executable, UPDATER], capture_output=True,
                           text=True, timeout=TOPE_UPDATER_SEGUNDOS, env=entorno)
    except subprocess.TimeoutExpired:
        return False, ["el updater no terminó en "
                       f"{TOPE_UPDATER_SEGUNDOS}s; se reintenta en el siguiente ciclo"]
    except OSError as e:
        return False, [f"no se pudo lanzar el updater: {e}"]

    salida = (r.stdout or "") + (r.stderr or "")
    interesantes = [l for l in salida.splitlines()
                    if any(m in l for m in ("En juego", "Sin partidos", "⚠", "Error",
                                            "Traceback", "Goleadores"))]
    return r.returncode == 0, interesantes or ["(sin novedades)"]


def publicar():
    """Commit + push. Si el push se cruza, el siguiente ciclo republica."""
    ok, _ = git("add", "data/laliga2627.json")
    if not ok:
        return False
    sin_cambios, _ = git("diff", "--cached", "--quiet")
    if sin_cambios:
        return False  # nada que publicar

    # El updater reescribe `lastUpdated` en cada pasada, así que el fichero
    # SIEMPRE difiere aunque no haya cambiado ni un dato. A 60 segundos por
    # ciclo eso serían más de mil commits al día sin información nueva. Si lo
    # único que ha cambiado es la marca de tiempo, no se publica.
    _, diferencias = git("diff", "--cached", "-U0", "--", "data/laliga2627.json")
    reales = [l for l in diferencias.splitlines()
              if l[:1] in ("+", "-") and l[:3] not in ("+++", "---")
              and "lastUpdated" not in l]
    if not reales:
        git("reset", "-q", "HEAD", "--", "data/laliga2627.json")
        git("checkout", "--", "data/laliga2627.json")
        return False

    marca = ahora().strftime("%Y-%m-%dT%H:%M:%SZ")
    git("commit", "-q", "-m", f"chore: actualización automática LaLiga {marca}")
    ok, salida = git("push", "-q")
    if not ok:
        registrar("Push rechazado (otra ejecución se adelantó); "
                  "el siguiente ciclo republica sobre el remoto.")
        return False
    return True


def copiar_a_servido():
    """Deja el JSON donde lo sirve el NAS, si se ha configurado esa carpeta."""
    if not PUBLICAR_EN:
        return
    try:
        os.makedirs(PUBLICAR_EN, exist_ok=True)
        destino = os.path.join(PUBLICAR_EN, "laliga2627.json")
        temporal = destino + ".tmp"
        with open(fichero_de_datos(), "rb") as origen, open(temporal, "wb") as sal:
            sal.write(origen.read())
        os.replace(temporal, destino)  # atómico: nadie lee un fichero a medias
    except OSError as e:
        registrar(f"⚠️  no se pudo copiar a {PUBLICAR_EN}: {e}")


def resumen_partidos(ruta_o_datos):
    """{clave: (resultado, minuto, estado, nº eventos)} de los partidos de hoy."""
    try:
        if isinstance(ruta_o_datos, dict):
            datos = ruta_o_datos
        else:
            with open(ruta_o_datos, encoding="utf-8") as f:
                datos = json.load(f)
    except (OSError, ValueError):
        return {}
    hoy = ahora().strftime("%Y-%m-%d")
    ayer_y_hoy = {hoy}
    resumen = {}
    for dia in datos.get("matchDays", []):
        if dia.get("date") not in ayer_y_hoy:
            continue
        for g in dia.get("games", []):
            eventos = ((g.get("details") or {}).get("events") or [])
            resumen[f"{g.get('home')}-{g.get('away')}"] = (
                g.get("result"), g.get("clock"), g.get("state"), len(eventos))
    return resumen


def comparar_con_publicado():
    """Modo sombra: ¿lo que yo generaría coincide con lo que se ve en la app?"""
    try:
        with urllib.request.urlopen(PUBLICADO_URL, timeout=20) as r:
            publicado = json.loads(r.read().decode("utf-8"))
    except Exception as e:                      # red, JSON, lo que sea
        registrar(f"   (no se pudo leer lo publicado: {e})")
        return

    mio  = resumen_partidos(fichero_de_datos())
    suyo = resumen_partidos(publicado)
    if not mio and not suyo:
        return
    for clave in sorted(set(mio) | set(suyo)):
        a, b = mio.get(clave), suyo.get(clave)
        if a == b:
            registrar(f"   ≡ {clave}: {a[0]} {a[1] or ''} ({a[3]} eventos) — coincide")
        else:
            registrar(f"   ≠ {clave}: yo {a} · publicado {b}")


def escribir_salud(ciclo, activo, ok):
    """Marca de vida para que vigilar.sh sepa si esto sigue vivo o colgado."""
    try:
        with open(SALUD, "w", encoding="utf-8") as f:
            json.dump({
                "actualizado": ahora().strftime("%Y-%m-%dT%H:%M:%SZ"),
                "pid": os.getpid(),
                "modo": MODO,
                "ciclo": ciclo,
                "partidos_activos": activo,
                "ultimo_ciclo_ok": ok,
            }, f, ensure_ascii=False, indent=2)
    except OSError as e:
        registrar(f"⚠️  no se pudo escribir {SALUD}: {e}")


def dormir(segundos):
    """Sueño troceado para que una señal no tenga que esperar 10 minutos."""
    fin = time.time() + segundos
    while time.time() < fin and not _parar:
        time.sleep(min(2, max(0, fin - time.time())))


def comprobaciones_previas():
    problemas = []
    if MODO not in ("sombra", "produccion"):
        problemas.append(f"LALIGA_MODO='{MODO}' no es ni sombra ni produccion")
    if not os.path.isfile(UPDATER):
        problemas.append(f"no encuentro el updater en {UPDATER}")
    if MODO == "produccion" and not os.path.isdir(os.path.join(REPO, ".git")):
        problemas.append(f"{REPO} no es un clon de git y en producción hace falta")
    if MODO == "sombra":
        os.makedirs(os.path.dirname(DATOS_SOMBRA), exist_ok=True)
        if not os.path.exists(DATOS_SOMBRA):
            # Sin punto de partida el updater reconstruiría solo los días que
            # ESPN devuelve en la ventana de ±4 días y perdería el resto de la
            # temporada. Se arranca desde lo que ya está publicado.
            try:
                with urllib.request.urlopen(PUBLICADO_URL, timeout=30) as r:
                    contenido = r.read()
                with open(DATOS_SOMBRA, "wb") as f:
                    f.write(contenido)
                registrar(f"Copia inicial descargada en {DATOS_SOMBRA}")
            except Exception as e:
                problemas.append(f"no pude descargar la copia inicial: {e}")
    return problemas


def main():
    signal.signal(signal.SIGTERM, _senal)
    signal.signal(signal.SIGINT, _senal)

    registrar("═" * 60)
    registrar(f"Demonio arrancado · modo {MODO.upper()} · pid {os.getpid()}")
    registrar(f"   updater: {UPDATER}")
    registrar(f"   datos:   {fichero_de_datos()}")
    registrar(f"   ritmo:   {INTERVALO_VIVO}s con partido · {INTERVALO_REPOSO}s sin partido")
    if MODO == "sombra":
        registrar("   NO publica nada: solo compara con lo que hay en GitHub.")

    problemas = comprobaciones_previas()
    if problemas:
        for p in problemas:
            registrar(f"✗ {p}")
        return 1

    ciclo = 0
    while not _parar:
        ciclo += 1
        if MODO == "produccion":
            sincronizar_con_remoto()

        ok, lineas = ejecutar_updater()
        activo = os.path.exists(BANDERA_ACTIVOS)
        estado = "✓" if ok else "✗"
        registrar(f"{estado} ciclo {ciclo} · {'PARTIDO EN JUEGO' if activo else 'en reposo'}")
        for l in lineas:
            registrar(f"   {l.strip()}")

        if ok and MODO == "produccion":
            # La copia servida se hace ANTES de publicar, a propósito.
            #
            # `publicar()` revierte el fichero cuando lo único que ha cambiado
            # es `lastUpdated` —para no llenar el repositorio de commits sin
            # dato nuevo—, y esa reversión se llevaba por delante la marca
            # fresca. Copiando después, el NAS servía datos con la fecha del
            # último cambio REAL, que en reposo puede ser de hace medio día, y
            # la app los daba por caducados teniéndolos recién comprobados.
            copiar_a_servido()
            if publicar():
                registrar("   publicado en GitHub")
        elif ok:
            comparar_con_publicado()

        escribir_salud(ciclo, activo, ok)
        if _parar:
            break
        dormir(INTERVALO_VIVO if activo else INTERVALO_REPOSO)

    registrar(f"Demonio detenido tras {ciclo} ciclos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
