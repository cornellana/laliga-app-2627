# Actualizador de La Liga en el NAS

Mover la actualización de datos de GitHub Actions al NAS, **sin desmontar lo
que ya funciona**. Ahora mismo está en modo sombra: corre, genera y compara,
pero quien alimenta la app sigue siendo el workflow de GitHub.

## Por qué

Tres fallos en dos días, los tres de la misma raíz — GitHub dispara cuando
quiere y obliga a coordinar procesos que no se conocen entre sí:

| Cuándo | Qué pasó |
|---|---|
| 20/08 19:01 | El bucle se apagó un minuto después del saque: ESPN todavía marcaba el partido como `pre` y la ventana previa no admitía minutos negativos. |
| 21/08 18:35→19:14 | El cron no disparó en 39 minutos. El Betis–Real Sociedad empezó sin cobertura y hubo que lanzarlo a mano. |
| 21/08 19:34→19:58 | Dos ejecuciones se pelearon por el mismo push; el `pull --rebase` de emergencia metió marcadores de conflicto dentro del JSON y el bucle estuvo 24 minutos girando en vacío, ocupando el turno de concurrencia. |

Un solo proceso con su propio reloj no tiene ninguno de los tres. Y el NAS ya
consulta ESPN 24/7 para las notificaciones push (`laliga-api`), así que el
terreno está probado.

## Qué hay montado

Un contenedor, `laliga-updater`, al lado de `laliga-api`, con `restart: always`
para que vuelva solo tras un reinicio o un corte de luz.

```
/share/Container/laliga-updater/
├── Dockerfile  docker-compose.yml  entrypoint.sh
├── repo/       clon del repositorio (de ahí sale el código)
└── estado/     laliga2627.json de trabajo · laliga.log · salud.json
```

El demonio **no reimplementa nada**: ejecuta `scripts/update_liga.py` como
subproceso, el mismo fichero que usa el workflow, sacado del clon. Así no hay
dos copias de la lógica que puedan divergir. Actualizarlo es `git push` desde
el Mac y reiniciar el contenedor.

El NAS no trae pip, ni requests, ni git — de ahí el contenedor en vez de un
cron del QNAP.

## Los dos modos

**`sombra`** (el actual): trabaja sobre su propia copia del JSON en `/estado`,
no publica nada, y después de cada ciclo compara lo que él generaría con lo que
hay publicado en GitHub. En el log:

```
✓ ciclo 12 · PARTIDO EN JUEGO
   En juego o a punto de empezar (1): Sevilla at Athletic
   ≡ Athletic-Sevilla: 1-0 34' (7 eventos) — coincide
```

Una línea `≠` significa desviación. Durante un partido es normal ver alguna:
el NAS mira cada 60 s y GitHub cada 3 min, así que el NAS va por delante. Lo
que no debe pasar es que el NAS se quede atrás o invente datos.

**`produccion`**: publica él. Cada ciclo parte del remoto (`rebase --abort` +
`fetch` + `checkout -B main origin/main`), así que no puede repetirse el atasco
del 21/08. Se activa con `LALIGA_MODO=produccion` en el compose.

## Uso diario

```bash
# seguir el log en vivo
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; docker logs -f laliga-updater'

# estado de un vistazo
ssh nas 'cat /share/Container/laliga-updater/estado/salud.json'

# actualizar el demonio tras un push
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; docker restart laliga-updater'
```

Desde el Mac: `./nas/comprobar-nas.sh` (no toca nada), `./nas/instalar.sh`
(idempotente), `./nas/desinstalar.sh` (lo quita; con `--todo` borra también
datos e imagen).

## Lo que falta para el relevo

1. **Ver una jornada en sombra.** Si no aparecen `≠` inexplicables, funciona.
2. **Credenciales de escritura** para que el NAS publique en GitHub: un deploy
   key o un token con permiso de push. Hoy el clon es HTTPS de solo lectura.
3. **Decidir la vía de publicación.** Dos opciones, no excluyentes:
   - *Push a GitHub*: cero cambios en la app, pero la CDN de
     `raw.githubusercontent.com` cachea unos 5 minutos — ese es el techo real
     de frescura, se actualice cada 60 s o cada 3 min.
   - *Servir el JSON desde `laliga-api.cornellanas.net`*: latencia de segundos,
     pero hay que tocar `Models.swift` y subir versión a TestFlight.
4. **Qué hacemos con el workflow.** Recomendación: dejarlo como red de
   seguridad con cron cada hora, no borrarlo. Si el NAS o la fibra caen, la app
   sigue recibiendo datos.

Mientras tanto el workflow sigue exactamente como estaba, cada 15 minutos.
