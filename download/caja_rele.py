"""
Caja para placa relé WiFi 1 canal (Newgoal St-dc1ew-rf, 67 x 41 mm)
Base + tapa con cierre a presión (snap-fit).

Sistema de coordenadas (vista superior, igual que la foto del producto):
  - Origen (0,0) = esquina inferior-izquierda de la PCB
  - X a lo largo de los 67 mm, Y a lo largo de los 41 mm
  - Borde Y=0  -> lado de las bornas (NO/COM/NC y entrada AC/DC)
  - Borde X=0  -> antena 433 MHz
  - Borde X=67 -> micro-USB
  - Z=0 = cara superior del suelo interior

Todas las cotas en mm. Ajusta los parámetros y vuelve a ejecutar.
"""
import cadquery as cq

# ---------------- PCB ----------------
PCB_L, PCB_W, PCB_T = 67.0, 41.0, 1.6
COMP_H = 17.0               # altura de componentes sobre la PCB (relé ~15.5)

# Taladros de la PCB (Ø3) — ¡verificar con calibre!
HOLE_INSET_X = 3.5
HOLE_INSET_Y = 3.6
HOLES = [(HOLE_INSET_X, HOLE_INSET_Y),
         (PCB_L - HOLE_INSET_X, HOLE_INSET_Y),
         (HOLE_INSET_X, PCB_W - HOLE_INSET_Y),
         (PCB_L - HOLE_INSET_X, PCB_W - HOLE_INSET_Y)]

# ---------------- Caja ----------------
CLEAR = 3.0                 # holgura PCB-pared por lado
WALL = 2.2
FLOOR = 2.2
R_OUT = 3.0                 # radio esquinas exteriores
STANDOFF_H = 5.0
STANDOFF_D = 6.0
SCREW_PILOT = 2.5           # tornillo autorroscante M3 / M2.5
INNER_TOP_GAP = 1.4         # aire entre componentes y tapa

PCB_TOP = STANDOFF_H + PCB_T
INNER_H = PCB_TOP + COMP_H + INNER_TOP_GAP
IN_L, IN_W = PCB_L + 2 * CLEAR, PCB_W + 2 * CLEAR
OUT_L, OUT_W = IN_L + 2 * WALL, IN_W + 2 * WALL
CX, CY = PCB_L / 2, PCB_W / 2

# ---------------- Aberturas ----------------
# (centro X, ancho, alto) en la pared frontal (Y=0), centradas en altura de borna
TERM_Z = PCB_TOP + 4.0
RELAY_SLOT = (15.3, 18.0, 8.0)    # NO / COM / NC
POWER_SLOT = (56.8, 15.0, 8.0)    # Entrada AC/DC 7-32 V
SLOT_R = 1.5
# micro-USB en pared derecha (X=67): (centro Y, ancho, alto)
USB_Y, USB_W, USB_H = 27.0, 12.0, 8.0
USB_Z = PCB_TOP + 1.6

# ---------------- Tapa / snap-fit ----------------
LID_T = 2.0
LIP_DEPTH = 5.0
LIP_T = 1.6
LIP_GAP = 0.2               # holgura lateral labio-pared (PLA/PETG)
LIP_CORNER_CUT = 4.0        # labios separados en esquinas -> flexan mejor
BEAD_R = 0.6                # cordón del labio
GROOVE_R = 0.75             # ranura en la pared
SNAP_Z_FROM_TOP = 2.6
NOTCH_W = 10.0              # muesca para abrir con uña/destornillador

# Pulsadores flexibles en la tapa: lengüeta con bisagra hacia -X y vástago
# que baja hasta el pulsador. (x, y, altura del pulsador sobre la PCB)
BUTTONS = [(55.3, 37.3, 5.0),     # modo momentáneo / enclavado
           (52.3, 28.1, 5.0)]     # emparejar RF / manual / ajuste
BTN_TONGUE_W = 6.0          # ancho de la lengüeta
BTN_TONGUE_L = 15.0         # largo (más largo = más blando)
BTN_TONGUE_T = 1.2          # espesor de la lengüeta (tapa = 2.0)
BTN_GAP = 0.8               # ranura alrededor de la lengüeta
BTN_PAD_OVER = 2.5          # lengüeta que sobresale más allá del pulsador
BTN_STEM_D = 4.5            # Ø del vástago
BTN_CLEAR = 0.8             # aire vástago-pulsador en reposo
BTN_DIMPLE_D, BTN_DIMPLE_H = 5.0, 0.4   # rebaje guía para el dedo

# Ventanas LED: (x, y, Ø) agujeros ; (x, y, ancho, alto) rectangulares
LED_HOLES = [(20.4, 34.0, 3.0)]          # LED ON/OFF
LED_WINDOWS = [(56.4, 27.0, 2.8, 9.0)]   # LEDs modo + WiFi (junto al pulsador RF)

# ---------------- Orejetas de fijación ----------------
EARS = True
EAR_W, EAR_L, EAR_T, EAR_HOLE = 14.0, 10.0, 3.0, 4.2


def rounded_box(l, w, h, r, z0=0.0):
    return (cq.Workplane("XY").workplane(offset=z0).center(CX, CY)
            .rect(l, w).extrude(h).edges("|Z").fillet(r))


def slot_cutter(plane, cx, cz, w, h, depth, r):
    return (cq.Workplane(plane).center(cx, cz).rect(w, h).extrude(depth, both=True)
            .edges(f"|{plane_normal(plane)}").fillet(r))


def plane_normal(plane):
    return {"XZ": "Y", "YZ": "X"}[plane]


def build_base():
    r_in = max(R_OUT - WALL, 0.5)
    body = rounded_box(OUT_L, OUT_W, FLOOR + INNER_H, R_OUT, z0=-FLOOR)
    if EARS:
        for sx in (-1, 1):
            ex = CX + sx * (OUT_L / 2 + EAR_L / 2 - R_OUT)
            ear = (cq.Workplane("XY", origin=(0, 0, -FLOOR)).center(ex, CY)
                   .rect(EAR_L + 2 * R_OUT, EAR_W).extrude(EAR_T)
                   .edges("|Z").fillet(2.5))
            hx = CX + sx * (OUT_L / 2 + EAR_L / 2 + 0.5)
            ear = ear.cut(cq.Workplane("XY", origin=(0, 0, -FLOOR)).center(hx, CY)
                          .circle(EAR_HOLE / 2).extrude(EAR_T))
            body = body.union(ear)
    body = body.cut(rounded_box(IN_L, IN_W, INNER_H + 1, r_in, z0=0))

    # Torretas
    for x, y in HOLES:
        post = (cq.Workplane("XY").center(x, y).circle(STANDOFF_D / 2)
                .extrude(STANDOFF_H).faces(">Z").workplane()
                .hole(SCREW_PILOT, STANDOFF_H + FLOOR - 0.6))
        body = body.union(post)
    body = body.cut(cq.Workplane("XY").pushPoints(HOLES)
                    .circle(SCREW_PILOT / 2).extrude(STANDOFF_H))

    # Pared frontal (bornas)
    y_front = -CLEAR - WALL / 2
    for cx, w, h in (RELAY_SLOT, POWER_SLOT):
        cut = (cq.Workplane("XZ", origin=(0, y_front, 0)).center(cx, TERM_Z)
               .rect(w, h).extrude(WALL, both=True).edges("|Y").fillet(SLOT_R))
        body = body.cut(cut)

    # Pared derecha (USB)
    x_right = PCB_L + CLEAR + WALL / 2
    usb = (cq.Workplane("YZ", origin=(x_right, 0, 0)).center(USB_Y, USB_Z)
           .rect(USB_W, USB_H).extrude(WALL, both=True).edges("|X").fillet(SLOT_R))
    body = body.cut(usb)

    # Ranuras snap en paredes largas (interior)
    zg = INNER_H - SNAP_Z_FROM_TOP
    glen = IN_L - 8
    for y in (-CLEAR, PCB_W + CLEAR):
        g = (cq.Workplane("YZ", origin=(CX - glen / 2, 0, 0)).center(y, zg)
             .circle(GROOVE_R).extrude(glen))
        body = body.cut(g)

    # Muesca de apertura (pared izquierda, borde superior)
    notch = (cq.Workplane("XY", origin=(-CLEAR - WALL / 2, CY, INNER_H - 1.5))
             .rect(WALL + 2, NOTCH_W).extrude(2))
    body = body.cut(notch)

    return body


def build_lid():
    z0 = INNER_H
    lid = rounded_box(OUT_L, OUT_W, LID_T, R_OUT, z0=z0)
    lid = lid.edges(">Z").chamfer(0.6)

    # Labio interior: 4 paneles separados en las esquinas
    o = LIP_GAP
    lip_out_l, lip_out_w = IN_L - 2 * o, IN_W - 2 * o
    lip_ring = (cq.Workplane("XY", origin=(0, 0, z0 - LIP_DEPTH)).center(CX, CY)
                .rect(lip_out_l, lip_out_w).extrude(LIP_DEPTH)
                .cut(cq.Workplane("XY", origin=(0, 0, z0 - LIP_DEPTH)).center(CX, CY)
                     .rect(lip_out_l - 2 * LIP_T, lip_out_w - 2 * LIP_T).extrude(LIP_DEPTH)))
    c = LIP_CORNER_CUT
    corners = (cq.Workplane("XY", origin=(0, 0, z0 - LIP_DEPTH))
               .pushPoints([(CX + sx * lip_out_l / 2, CY + sy * lip_out_w / 2)
                            for sx in (-1, 1) for sy in (-1, 1)])
               .rect(2 * c, 2 * c).extrude(LIP_DEPTH))
    lip_ring = lip_ring.cut(corners)

    # Cordones snap en labios largos
    zb = INNER_H - SNAP_Z_FROM_TOP
    blen = lip_out_l - 2 * c - 6
    for y in (-CLEAR + o, PCB_W + CLEAR - o):
        bead = (cq.Workplane("YZ", origin=(CX - blen / 2, 0, 0)).center(y, zb)
                .circle(BEAD_R).extrude(blen))
        lip_ring = lip_ring.union(bead)
    lid = lid.union(lip_ring)

    # Pulsadores flexibles
    z_top = z0 + LID_T
    for bx, by, sw_h in BUTTONS:
        x_end = bx + BTN_PAD_OVER
        x_root = x_end - BTN_TONGUE_L
        g, w = BTN_GAP, BTN_TONGUE_W
        u_cut = (cq.Workplane("XY", origin=(0, 0, z0 - 1))
                 .center((x_root + x_end + g) / 2, by)
                 .rect(BTN_TONGUE_L + g, w + 2 * g).extrude(LID_T + 2)
                 .cut(cq.Workplane("XY", origin=(0, 0, z0 - 1))
                      .center((x_root + x_end) / 2, by)
                      .rect(BTN_TONGUE_L, w).extrude(LID_T + 2)))
        lid = lid.cut(u_cut)
        # adelgazar la lengüeta por debajo
        lid = lid.cut(cq.Workplane("XY", origin=(0, 0, z0 - 1))
                      .center((x_root + x_end) / 2, by)
                      .rect(BTN_TONGUE_L, w).extrude(1 + LID_T - BTN_TONGUE_T))
        # vástago
        z_stem = PCB_TOP + sw_h + BTN_CLEAR
        stem = (cq.Workplane("XY", origin=(0, 0, z_stem)).center(bx, by)
                .circle(BTN_STEM_D / 2).extrude(z_top - BTN_TONGUE_T - z_stem + 0.01))
        lid = lid.union(stem.edges("<Z").chamfer(0.4))
        # rebaje para el dedo
        lid = lid.cut(cq.Workplane("XY", origin=(0, 0, z_top - BTN_DIMPLE_H)).center(bx, by)
                      .circle(BTN_DIMPLE_D / 2).extrude(1))

    # Ventanas LED
    for x, y, d in LED_HOLES:
        lid = lid.cut(cq.Workplane("XY", origin=(0, 0, z0 - 1)).center(x, y)
                      .circle(d / 2).extrude(LID_T + 2))
    for x, y, wd, ht in LED_WINDOWS:
        lid = lid.cut(cq.Workplane("XY", origin=(0, 0, z0 - 1)).center(x, y)
                      .rect(wd, ht).extrude(LID_T + 2))
    return lid


def build_pcb_dummy():
    pcb = (cq.Workplane("XY", origin=(0, 0, STANDOFF_H)).rect(PCB_L, PCB_W, centered=False)
           .extrude(PCB_T).faces(">Z").workplane().pushPoints(HOLES).hole(3.0))
    for bx, by, sw_h in BUTTONS:
        body = (cq.Workplane("XY", origin=(0, 0, PCB_TOP)).center(bx, by)
                .rect(6, 6).extrude(3.4))
        act = (cq.Workplane("XY", origin=(0, 0, PCB_TOP)).center(bx, by)
               .circle(1.75).extrude(sw_h))
        pcb = pcb.union(body).union(act)
    return pcb


if __name__ == "__main__":
    import os
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
    os.makedirs(out, exist_ok=True)
    base, lid, pcb = build_base(), build_lid(), build_pcb_dummy()

    # STEP en posición de montaje (para Fusion 360)
    asm = (cq.Assembly(name="caja_rele")
           .add(base, name="base", color=cq.Color(0.15, 0.15, 0.17))
           .add(lid, name="tapa", color=cq.Color(0.85, 0.85, 0.82))
           .add(pcb, name="pcb_referencia", color=cq.Color(0.1, 0.5, 0.2)))
    asm.save(os.path.join(out, "caja_rele_ensamblaje.step"))
    cq.exporters.export(base, os.path.join(out, "caja_rele_base.step"))
    cq.exporters.export(lid, os.path.join(out, "caja_rele_tapa.step"))

    # STL en orientación de impresión
    cq.exporters.export(base, os.path.join(out, "caja_rele_base.stl"), tolerance=0.02)
    lid_print = lid.rotate((0, 0, 0), (1, 0, 0), 180).translate((0, 0, INNER_H + LID_T))
    cq.exporters.export(lid_print, os.path.join(out, "caja_rele_tapa.stl"), tolerance=0.02)

    print(f"Exterior: {OUT_L:.1f} x {OUT_W:.1f} x {FLOOR + INNER_H + LID_T:.1f} mm")
    print(f"Interior: {IN_L:.1f} x {IN_W:.1f} x {INNER_H:.1f} mm")
