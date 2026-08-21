# El NAS trae Python 3.12 pero sin pip ni requests, y sin git. En vez de
# ensuciar el sistema del QNAP instalando cosas a mano, el actualizador vive en
# su propio contenedor — igual que laliga-api, que ya corre ahí al lado.
FROM python:3.12-slim

# git: para clonar el repositorio y, en producción, publicar el JSON.
# ca-certificates: para hablar con ESPN y GitHub por HTTPS.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir requests

# Zona horaria: el updater trabaja en UTC pero convierte a hora de Madrid para
# las fechas de los partidos, así que conviene tener la base de datos tzdata.
ENV TZ=Europe/Madrid
ENV PYTHONUNBUFFERED=1

WORKDIR /estado
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# El demonio escribe una marca de vida en cada ciclo. Si deja de latir durante
# más de media hora, el contenedor se marca como unhealthy y se ve de un
# vistazo en `docker ps` — que es justo lo que faltó el 21/08, cuando el bucle
# de GitHub estaba vivo pero no publicaba nada.
HEALTHCHECK --interval=5m --timeout=10s --start-period=2m \
  CMD python3 -c "import json,time,sys; s=json.load(open('/estado/salud.json')); \
      t=time.mktime(time.strptime(s['actualizado'],'%Y-%m-%dT%H:%M:%SZ')); \
      sys.exit(0 if (time.time()-t) < 1800 else 1)" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
