#!/usr/bin/env python3
"""Genera manual-usuario.pdf para la app La Liga."""

import os
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import cm
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Image, Table, TableStyle,
    PageBreak, HRFlowable, KeepTogether
)
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.pdfgen import canvas
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate
from PIL import Image as PILImage

# ── Rutas ─────────────────────────────────────────────────────────────────────
BASE    = os.path.dirname(os.path.abspath(__file__))
IMGS    = os.path.join(BASE, "manual-imagenes")
OUT     = os.path.join(BASE, "manual-usuario.pdf")

IMG = {
    "principal":  os.path.join(IMGS, "01-pantalla-principal.png"),
    "temporada":  os.path.join(IMGS, "02-selector-temporada.png"),
    "jornada":    os.path.join(IMGS, "03-filtro-jornada.png"),
    "equipo":     os.path.join(IMGS, "04-filtro-equipo.png"),
    "detalle":    os.path.join(IMGS, "05-detalle-partido.png"),
    "clasif":     os.path.join(IMGS, "06-clasificacion.png"),
    "goleadores": os.path.join(IMGS, "07-goleadores.png"),
    "calendario": os.path.join(IMGS, "08-calendario.png"),
    "ajustes":    os.path.join(IMGS, "09-ajustes.png"),
}

# ── Colores ────────────────────────────────────────────────────────────────────
ROJO   = colors.HexColor("#E8460B")
AZUL   = colors.HexColor("#004D98")
OSCURO = colors.HexColor("#0A0A14")
GRIS1  = colors.HexColor("#F5F5F8")
GRIS2  = colors.HexColor("#AAAAAA")
VERDE  = colors.HexColor("#1B8A4C")

# ── Dimensiones A4 ────────────────────────────────────────────────────────────
PW, PH  = A4          # 595.27 x 841.89 pts
ML = MR = 2.2 * cm
MT = MB = 2.0 * cm
CW = PW - ML - MR     # ancho de contenido ~510 pts

# ── Estilos de párrafo ─────────────────────────────────────────────────────────
def sty(name, **kw):
    base = dict(fontName="Helvetica", fontSize=10, leading=15,
                textColor=colors.HexColor("#2D2D4E"), spaceAfter=6)
    base.update(kw)
    return ParagraphStyle(name, **base)

S_BODY   = sty("body",   fontSize=10, leading=15, alignment=TA_JUSTIFY)
S_H2     = sty("h2",     fontName="Helvetica-Bold", fontSize=18, leading=22,
               textColor=OSCURO, spaceAfter=6, spaceBefore=4)
S_H3     = sty("h3",     fontName="Helvetica-Bold", fontSize=12, leading=16,
               textColor=OSCURO, spaceAfter=4, spaceBefore=10)
S_BULLET = sty("bullet", fontSize=10, leading=15, leftIndent=14, bulletIndent=0)
S_CALLOUT= sty("callout",fontSize=9,  leading=14, textColor=colors.HexColor("#1A1A3E"),
               leftIndent=10, rightIndent=10)
S_CAPTION= sty("caption",fontSize=8,  leading=11, textColor=GRIS2,
               alignment=TA_CENTER, spaceBefore=4)
S_TABLE  = sty("table",  fontSize=9,  leading=12)
S_COVER1 = sty("cover1", fontName="Helvetica-Bold", fontSize=42, leading=48,
               textColor=OSCURO, alignment=TA_CENTER)
S_COVER2 = sty("cover2", fontName="Helvetica-Bold", fontSize=20, leading=26,
               textColor=ROJO, alignment=TA_CENTER)
S_COVER3 = sty("cover3", fontSize=12, leading=16,
               textColor=GRIS2, alignment=TA_CENTER)
S_TOC_IT = sty("toc",    fontName="Helvetica", fontSize=11, leading=18,
               textColor=OSCURO)

# ── Helper: imagen escalada al ancho dado ──────────────────────────────────────
def img(key, width):
    path = IMG[key]
    w, h = PILImage.open(path).size
    return Image(path, width=width, height=width * h / w)

# ── Helper: bullet ──────────────────────────────────────────────────────────────
def bullet(text):
    return Paragraph(f"<bullet>▸</bullet> {text}", S_BULLET)

# ── Helper: callout box ────────────────────────────────────────────────────────
def callout(title, text, color=AZUL):
    data = [[Paragraph(f"<b>{title}</b><br/>{text}", S_CALLOUT)]]
    t = Table(data, colWidths=[CW - 1])
    t.setStyle(TableStyle([
        ("BACKGROUND",   (0,0), (-1,-1), colors.HexColor("#F0F4FF")),
        ("LEFTPADDING",  (0,0), (-1,-1), 10),
        ("RIGHTPADDING", (0,0), (-1,-1), 10),
        ("TOPPADDING",   (0,0), (-1,-1), 8),
        ("BOTTOMPADDING",(0,0), (-1,-1), 8),
        ("LINECOLOR",    (0,0), (-1,-1), color),
        ("LINEBEFORE",   (0,0), (0,-1),  4, color),
        ("ROUNDEDCORNERS", [4]),
    ]))
    return t

# ── Helper: texto + imagen en dos columnas ─────────────────────────────────────
def two_col(text_items, img_key, img_on_right=True, img_width=4.8*cm):
    image = img(img_key, img_width)
    caption_key = {
        "principal":  "Pantalla principal con FC Barcelona\nresaltado (Jornada 1)",
        "temporada":  "Selector de temporada desplegado\n(Temp. 25/26 activa)",
        "jornada":    "Filtro de jornada activo\n(Jornada 12, 7-9 nov)",
        "equipo":     "Filtro por equipo: solo partidos\ndel FC Barcelona",
        "detalle":    "Ficha del partido Mallorca 0-3\nFC Barcelona (Jornada 1)",
        "clasif":     "Clasificacion de La Liga 25/26\nal final de la temporada",
        "goleadores": "Ranking de goleadores 25/26.\nJugadores del Barca en azul.",
        "calendario": "Calendario de FC Barcelona:\nagosto y septiembre 2025",
        "ajustes":    "Ajustes: Barca y Real Madrid\nresaltados, avisos activados",
    }[img_key]

    img_cell  = [image, Paragraph(caption_key, S_CAPTION)]
    text_cell = text_items

    img_w  = img_width + 0.4*cm
    text_w = CW - img_w - 0.5*cm

    if img_on_right:
        data = [[text_cell, img_cell]]
        col_widths = [text_w, img_w]
    else:
        data = [[img_cell, text_cell]]
        col_widths = [img_w, text_w]

    t = Table(data, colWidths=col_widths)
    t.setStyle(TableStyle([
        ("VALIGN",        (0,0), (-1,-1), "TOP"),
        ("LEFTPADDING",   (0,0), (-1,-1), 0),
        ("RIGHTPADDING",  (0,0), (-1,-1), 0),
        ("TOPPADDING",    (0,0), (-1,-1), 0),
        ("BOTTOMPADDING", (0,0), (-1,-1), 0),
        ("COLPADDING",    (0,0), (-1,-1), 8),
    ]))
    return t

# ── Helper: encabezado de sección ─────────────────────────────────────────────
def section_header(num, title):
    badge = Table([[Paragraph(f"<b>{num}</b>",
                              ParagraphStyle("badge", fontName="Helvetica-Bold",
                                             fontSize=11, textColor=colors.white,
                                             alignment=TA_CENTER))]],
                  colWidths=[0.7*cm], rowHeights=[0.7*cm])
    badge.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (-1,-1), ROJO),
        ("ROUNDEDCORNERS",[14]),
        ("TOPPADDING",    (0,0), (-1,-1), 1),
        ("BOTTOMPADDING", (0,0), (-1,-1), 1),
    ]))
    row = Table([[badge, Paragraph(title, S_H2)]],
                colWidths=[1.0*cm, CW - 1.0*cm])
    row.setStyle(TableStyle([
        ("VALIGN",      (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 0),
        ("RIGHTPADDING",(0,0), (-1,-1), 0),
        ("TOPPADDING",  (0,0), (-1,-1), 0),
        ("BOTTOMPADDING",(0,0),(-1,-1), 0),
    ]))
    return [row, HRFlowable(width=CW, thickness=2, color=ROJO, spaceAfter=14)]

# ── Helper: tabla de eventos ────────────────────────────────────────────────────
def events_table(rows, headers):
    h_style = ParagraphStyle("th", fontName="Helvetica-Bold", fontSize=9,
                              textColor=colors.white, leading=12)
    d_style = S_TABLE
    data = [[Paragraph(h, h_style) for h in headers]]
    for r in rows:
        data.append([Paragraph(c, d_style) for c in r])
    col_n  = len(headers)
    widths = [CW / col_n] * col_n
    t = Table(data, colWidths=widths)
    t.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (-1,0),  OSCURO),
        ("BACKGROUND",    (0,1), (-1,-1), colors.white),
        ("ROWBACKGROUNDS",(0,1), (-1,-1), [colors.white, GRIS1]),
        ("GRID",          (0,0), (-1,-1), 0.25, colors.HexColor("#DDDDDD")),
        ("VALIGN",        (0,0), (-1,-1), "TOP"),
        ("TOPPADDING",    (0,0), (-1,-1), 6),
        ("BOTTOMPADDING", (0,0), (-1,-1), 6),
        ("LEFTPADDING",   (0,0), (-1,-1), 8),
        ("RIGHTPADDING",  (0,0), (-1,-1), 8),
    ]))
    return t

# ── Canvas: cabecera/pie en páginas interiores ─────────────────────────────────
class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_number(num_pages)
            canvas.Canvas.showPage(self)
        canvas.Canvas.save(self)

    def draw_page_number(self, page_count):
        pn = self._pageNumber
        if pn <= 2:   # portada + índice sin pie
            return
        self.saveState()
        self.setStrokeColor(colors.HexColor("#EEEEEE"))
        self.setLineWidth(0.5)
        self.line(ML, MB - 6, PW - MR, MB - 6)
        self.setFont("Helvetica", 8)
        self.setFillColor(GRIS2)
        self.drawString(ML, MB - 16, "La Liga App  ·  Manual de Usuario")
        self.drawRightString(PW - MR, MB - 16, f"Pagina {pn}")
        self.restoreState()

# ── Portada ────────────────────────────────────────────────────────────────────
def build_cover():
    story = []
    story.append(Spacer(1, 3.5*cm))

    # Banda decorativa superior
    band = Table([[""]], colWidths=[CW], rowHeights=[0.6*cm])
    band.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,-1), ROJO)]))
    story.append(band)
    story.append(Spacer(1, 1.4*cm))

    story.append(Paragraph("La Liga", S_COVER1))
    story.append(Spacer(1, 0.3*cm))
    story.append(Paragraph("Manual de Usuario", S_COVER2))
    story.append(Spacer(1, 0.8*cm))
    story.append(Paragraph("Guia completa de todas las funciones de la app", S_COVER3))
    story.append(Spacer(1, 0.5*cm))
    story.append(Paragraph("Temporadas 24/25 · 25/26 · 26/27  ·  iOS 17+", S_COVER3))
    story.append(Spacer(1, 3.0*cm))

    # Linea divisora
    story.append(HRFlowable(width=CW, thickness=1, color=colors.HexColor("#EEEEEE")))
    story.append(Spacer(1, 0.6*cm))
    story.append(Paragraph("Julio 2026", S_COVER3))
    story.append(PageBreak())
    return story

# ── Indice ─────────────────────────────────────────────────────────────────────
def build_toc():
    story = []
    story.append(Spacer(1, 0.6*cm))
    story.append(Paragraph("Contenido", S_H2))
    story.append(HRFlowable(width=CW, thickness=2, color=ROJO, spaceAfter=12))

    chapters = [
        "Pantalla principal",
        "Cambio de temporada",
        "Filtros: equipo y jornada",
        "Detalle de partido",
        "Clasificacion",
        "Maximos goleadores",
        "Calendario de equipo",
        "Equipos resaltados y avisos push",
    ]
    for i, ch in enumerate(chapters, 1):
        row = Table(
            [[Paragraph(f"<b>{i}.</b>", S_TOC_IT),
              Paragraph(ch, S_TOC_IT),
              Paragraph("", S_TOC_IT)]],
            colWidths=[0.8*cm, CW - 1.4*cm, 0.6*cm]
        )
        row.setStyle(TableStyle([
            ("LINEBELOW",     (0,0), (-1,-1), 0.5, colors.HexColor("#EEEEEE")),
            ("TOPPADDING",    (0,0), (-1,-1), 7),
            ("BOTTOMPADDING", (0,0), (-1,-1), 7),
            ("LEFTPADDING",   (0,0), (-1,-1), 0),
            ("RIGHTPADDING",  (0,0), (-1,-1), 0),
            ("TEXTCOLOR",     (0,0), (0,-1),  ROJO),
        ]))
        story.append(row)

    story.append(PageBreak())
    return story

# ── Contenido de las secciones ──────────────────────────────────────────────────
def build_sections():
    story = []

    # ── 1. Pantalla principal ────────────────────────────────────────────────
    story += section_header(1, "Pantalla principal")
    story.append(two_col([
        Paragraph("Al abrir la app aparece el calendario completo de La Liga ordenado por jornadas. Cada jornada agrupa los partidos de los dias en que se disputa, mostrando fecha, equipos, resultado y canal de television.", S_BODY),
        Paragraph("<b>Scroll automatico</b>", S_H3),
        Paragraph("La app se desplaza automaticamente a la jornada del dia actual o, si no hay partidos ese dia, a la siguiente jornada programada.", S_BODY),
        Paragraph("<b>Informacion de cada partido</b>", S_H3),
        bullet("Escudos de los equipos local y visitante"),
        bullet("Resultado final — en negrita el equipo ganador, atenuado el perdedor"),
        bullet("Hora del partido o estado “Final”"),
        bullet("Canal de TV (DAZN, Movistar, GOL...)"),
        Spacer(1, 8),
        Paragraph("<b>Equipos resaltados</b>", S_H3),
        Paragraph("Los partidos de los equipos favoritos aparecen con una barra de color lateral y un fondo tintado. En el ejemplo, FC Barcelona aparece destacado en azul.", S_BODY),
        Spacer(1, 8),
        callout("Actualizacion", "Los datos se actualizan automaticamente cada vez que abres la app. Desliza hacia abajo para forzar la actualizacion. El circulo rojo en el toolbar indica que se estan descargando datos."),
    ], "principal", img_on_right=True))
    story.append(PageBreak())

    # ── 2. Temporada ────────────────────────────────────────────────────────
    story += section_header(2, "Cambio de temporada")
    story.append(two_col([
        Paragraph("La app incluye los datos de tres temporadas: <b>26/27</b>, <b>25/26</b> y <b>24/25</b>. Puedes cambiar entre ellas en cualquier momento sin reiniciar la app.", S_BODY),
        Paragraph("<b>Como cambiar de temporada</b>", S_H3),
        Paragraph("Toca el titulo central del toolbar — donde aparece “La Liga” y debajo la temporada activa en naranja. Se despliega un menu con las tres opciones disponibles. La temporada seleccionada aparece marcada con un ✓.", S_BODY),
        Paragraph("<b>Comportamiento al cambiar</b>", S_H3),
        bullet("Se carga el calendario completo de la temporada elegida"),
        bullet("Los filtros de equipo y jornada se reinician automaticamente"),
        bullet("El scroll se ajusta a la jornada correspondiente"),
        bullet("Los datos de cada temporada se guardan en cache por separado"),
        Spacer(1, 10),
        callout("Por defecto", "La app siempre arranca en la temporada 26/27 (la mas reciente). Al cambiar de temporada y cerrar la app, al volver mostrara de nuevo la 26/27."),
    ], "temporada", img_on_right=False))
    story.append(PageBreak())

    # ── 3. Filtros ──────────────────────────────────────────────────────────
    story += section_header(3, "Filtros: equipo y jornada")
    story.append(Paragraph("Bajo el toolbar hay una barra de filtros con dos selectores que puedes combinar libremente. Cuando un filtro esta activo su capsula cambia de color: degradado azul-rojo para equipo, azul solido para jornada.", S_BODY))
    story.append(Spacer(1, 10))
    story.append(callout("Combinar filtros", "Puedes activar ambos a la vez. Por ejemplo: filtrar por “FC Barcelona” + “Jornada 12” para ver exactamente el partido del Barca en esa jornada.", VERDE))
    story.append(Spacer(1, 14))

    # Dos imagenes lado a lado
    img_eq  = img("equipo",  4.6*cm)
    img_jor = img("jornada", 4.6*cm)
    cap_eq  = Paragraph("Filtro por equipo activo:\nsolo partidos del FC Barcelona", S_CAPTION)
    cap_jor = Paragraph("Filtro por jornada activo:\nvista completa de la Jornada 12", S_CAPTION)
    t = Table(
        [[img_eq, img_jor],
         [cap_eq, cap_jor]],
        colWidths=[CW/2 - 0.3*cm, CW/2 - 0.3*cm],
        hAlign="CENTER"
    )
    t.setStyle(TableStyle([
        ("VALIGN",      (0,0), (-1,-1), "TOP"),
        ("ALIGN",       (0,0), (-1,-1), "CENTER"),
        ("COLPADDING",  (0,0), (-1,-1), 10),
        ("TOPPADDING",  (0,0), (-1,-1), 0),
        ("BOTTOMPADDING",(0,0),(-1,-1), 4),
    ]))
    story.append(t)
    story.append(Spacer(1, 14))

    story.append(Paragraph("<b>Filtro por equipo</b>", S_H3))
    story.append(Paragraph("Toca la capsula “Equipo” para ver todos los equipos de la temporada. Al seleccionar uno, la vista muestra unicamente sus partidos en todas las jornadas.", S_BODY))
    story.append(Paragraph("<b>Filtro por jornada</b>", S_H3))
    story.append(Paragraph("Toca “Jornada” para ver las 38 jornadas con su fecha aproximada. Al seleccionar una, la vista muestra todos los partidos de esa jornada.", S_BODY))
    story.append(Paragraph("<b>Quitar filtros</b>", S_H3))
    story.append(Paragraph("Toca el selector activo y elige “Todos los equipos” o “Todas las jornadas”. Al quitar ambos filtros el scroll vuelve automaticamente a la jornada actual.", S_BODY))
    story.append(PageBreak())

    # ── 4. Detalle de partido ────────────────────────────────────────────────
    story += section_header(4, "Detalle de partido")
    ev_table = events_table(
        [["Gol", ""],
         ["Gol de penalti", ""],
         ["Gol en propia puerta", ""],
         ["Tarjeta amarilla", ""],
         ["Tarjeta roja / doble amarilla", ""],
         ["Sustitucion (entra · sale)", ""],
         ["Penalti fallado", ""]],
        ["Evento", "Simbolo"]
    )
    # Rehace con simbolos separados
    ev_table = events_table(
        [["[gol]",        "Gol"],
         ["[pen]",        "Gol de penalti"],
         ["[pp]",         "Gol en propia puerta"],
         ["[amarilla]",   "Tarjeta amarilla"],
         ["[roja]",       "Tarjeta roja o doble amarilla"],
         ["[cambio]",     "Sustitucion (entra / sale)"],
         ["[pen fail]",   "Penalti fallado"]],
        ["Simbolo", "Evento"]
    )
    story.append(two_col([
        Paragraph("Toca cualquier partido de la lista para abrir su ficha completa. Aparece como un panel deslizante desde la parte inferior.", S_BODY),
        Paragraph("<b>Informacion disponible</b>", S_H3),
        bullet("Resultado final con escudos de ambos equipos"),
        bullet("Estadio y ciudad donde se disputo"),
        bullet("Grafico de momentum del partido (dominio por tramos)"),
        bullet("Eventos en orden cronologico (goles, tarjetas, cambios)"),
        bullet("Alineaciones — titulares y suplentes"),
        Spacer(1, 8),
        Paragraph("<b>Simbolos de eventos</b>", S_H3),
        events_table(
            [["Balon", "Gol"],
             ["Balon (P)", "Gol de penalti"],
             ["Balon (PP)", "Gol en propia puerta"],
             ["Cuadrado amarillo", "Tarjeta amarilla"],
             ["Cuadrado rojo", "Tarjeta roja"],
             ["Flechas", "Sustitucion (entra / sale)"],
             ["X", "Penalti fallado"]],
            ["Icono", "Evento"]
        ),
        Spacer(1, 8),
        callout("Estadisticas de jugador", "Toca el nombre de cualquier jugador en la alineacion para ver sus estadisticas individuales de la temporada."),
    ], "detalle", img_on_right=True))
    story.append(PageBreak())

    # ── 5. Clasificacion ────────────────────────────────────────────────────
    story += section_header(5, "Clasificacion")
    story.append(two_col([
        Paragraph("Toca el icono de lista numerada en el toolbar (esquina superior derecha) para ver la tabla de clasificacion completa de la temporada activa.", S_BODY),
        Paragraph("<b>Columnas de la tabla</b>", S_H3),
        bullet("<b>PJ</b> — Partidos jugados"),
        bullet("<b>PG</b> — Partidos ganados"),
        bullet("<b>PE</b> — Partidos empatados"),
        bullet("<b>PP</b> — Partidos perdidos"),
        bullet("<b>DG</b> — Diferencia de goles"),
        bullet("<b>Pts</b> — Puntos totales"),
        Spacer(1, 8),
        Paragraph("<b>Zonas de color</b>", S_H3),
        events_table(
            [["1–4",  "Champions League",   "Verde"],
             ["5–6",  "Europa League",       "Azul"],
             ["7",         "Conference League",   "Azul claro"],
             ["18–20","Descenso",            "Rojo"]],
            ["Posiciones", "Competicion", "Color"]
        ),
        Spacer(1, 8),
        callout("Fuente de datos", "La clasificacion se obtiene del JSON remoto. Si no hay conexion, se calcula localmente a partir de los resultados del calendario."),
    ], "clasif", img_on_right=False))
    story.append(PageBreak())

    # ── 6. Goleadores ────────────────────────────────────────────────────────
    story += section_header(6, "Maximos goleadores")
    story.append(two_col([
        Paragraph("Toca el icono del balon en el toolbar para ver el ranking de maximos goleadores de la temporada seleccionada.", S_BODY),
        Paragraph("<b>Informacion de cada jugador</b>", S_H3),
        bullet("Posicion en el ranking"),
        bullet("Nombre completo y equipo"),
        bullet("Total de goles marcados"),
        bullet("Goles de penalti entre parentesis"),
        Spacer(1, 8),
        Paragraph("<b>Equipos resaltados</b>", S_H3),
        Paragraph("Los jugadores de los equipos favoritos aparecen con su nombre y escudo en el color del equipo resaltado. En el ejemplo, los jugadores del FC Barcelona aparecen en azul.", S_BODY),
    ], "goleadores", img_on_right=True))
    story.append(PageBreak())

    # ── 7. Calendario ────────────────────────────────────────────────────────
    story += section_header(7, "Calendario de equipo")
    story.append(two_col([
        Paragraph("Toca el icono del calendario en el toolbar para ver todos los partidos de la temporada en formato de calendario mensual.", S_BODY),
        Paragraph("<b>Vista de calendario</b>", S_H3),
        Paragraph("Cada mes muestra los dias con los partidos marcados directamente en el dia correspondiente. Los dias con partido muestran el escudo del rival y el resultado.", S_BODY),
        bullet("Fondo <b>verde</b>: victoria"),
        bullet("Fondo <b>rojo</b>: derrota"),
        bullet("Fondo <b>gris</b>: empate"),
        bullet("Sin fondo: partido pendiente"),
        Spacer(1, 8),
        Paragraph("<b>Cambiar de equipo</b>", S_H3),
        Paragraph("Toca el nombre del equipo en la parte superior para ver el calendario de cualquier otro equipo de la liga.", S_BODY),
        Spacer(1, 8),
        callout("Consejo", "Ideal para planificar: puedes ver de un vistazo todos los partidos del mes de tu equipo y cuando juega en casa o fuera.", VERDE),
    ], "calendario", img_on_right=False))
    story.append(PageBreak())

    # ── 8. Resaltado y avisos ─────────────────────────────────────────────────
    story += section_header(8, "Equipos resaltados y avisos push")
    story.append(two_col([
        Paragraph("Toca el icono de ajustes (engranaje) en el toolbar para personalizar la app: que equipos resaltar y que notificaciones recibir.", S_BODY),
        Paragraph("<b>Equipos resaltados</b>", S_H3),
        Paragraph("Los equipos resaltados aparecen destacados en la lista de partidos (barra lateral de color + fondo tintado), en la clasificacion y en el ranking de goleadores.", S_BODY),
        bullet("Toca <b>Anadir equipo</b> para seleccionar un equipo y asignarle color"),
        bullet("Toca el circulo de color para cambiarlo con el selector de color del sistema"),
        bullet("Desliza a la izquierda sobre un equipo para eliminarlo"),
        bullet("Toca <b>Editar</b> (esquina superior derecha) para reordenar"),
        Spacer(1, 8),
        Paragraph("<b>Avisos push</b>", S_H3),
        Paragraph("Los avisos te informan en tiempo real de los eventos clave de los partidos de tus equipos resaltados, aunque la app este cerrada.", S_BODY),
        events_table(
            [["Activar avisos",  "Interruptor principal. Activa o desactiva todos los avisos."],
             ["Goles",           "Cada gol marcado, incluidos goles en propia puerta."],
             ["Penaltis",        "Goles de penalti y penaltis fallados."],
             ["Expulsiones",     "Tarjeta roja o doble amarilla."],
             ["Inicio y final",  "Pitido inicial y resultado final del partido."]],
            ["Aviso", "Que notifica"]
        ),
        Spacer(1, 8),
        callout("Permiso necesario", "La primera vez que actives los avisos, iOS pedira permiso para notificaciones. Si lo rechazas, activalo en Ajustes del iPhone > Notificaciones > 27."),
    ], "ajustes", img_on_right=True))

    return story

# ── Pie de documento ───────────────────────────────────────────────────────────
def build_footer():
    story = []
    story.append(Spacer(1, 1.5*cm))
    story.append(HRFlowable(width=CW, thickness=1, color=ROJO))
    story.append(Spacer(1, 0.5*cm))
    c_style = ParagraphStyle("center", fontName="Helvetica", fontSize=10,
                              textColor=GRIS2, alignment=TA_CENTER, leading=16)
    story.append(Paragraph("La Liga App  ·  Temporadas 24/25 · 25/26 · 26/27  ·  iOS 17+  ·  Julio 2026", c_style))
    return story

# ── Main ────────────────────────────────────────────────────────────────────────
def main():
    doc = SimpleDocTemplate(
        OUT,
        pagesize=A4,
        leftMargin=ML, rightMargin=MR,
        topMargin=MT, bottomMargin=MB + 0.8*cm,
        title="La Liga App — Manual de Usuario",
        author="La Liga App",
    )
    story = []
    story += build_cover()
    story += build_toc()
    story += build_sections()
    story += build_footer()

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"PDF generado: {OUT}")

if __name__ == "__main__":
    main()
