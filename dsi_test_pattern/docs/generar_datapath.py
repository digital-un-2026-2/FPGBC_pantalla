"""Añade las dos páginas de datapath al editable único del generador."""
import xml.etree.ElementTree as E


class Page:
    def __init__(self, doc, ident, name, title, subtitle, height=2000):
        d = E.SubElement(doc, 'diagram', id=ident, name=name)
        g = E.SubElement(d, 'mxGraphModel', grid='1', gridSize='10', page='1',
                         pageWidth='1800', pageHeight=str(height), background='#ffffff')
        self.root = E.SubElement(g, 'root')
        E.SubElement(self.root, 'mxCell', id='0')
        E.SubElement(self.root, 'mxCell', id='1', parent='0')
        self.text('title', title, 50, 25, 1700, 60, 28)
        self.text('subtitle', subtitle, 50, 100, 1700, 90, 19)
        self.text('footer', 'DSI_TEST_PATTERN · DATAPATH PROPUESTO · 2026-11-09 | '
                  'FSM: pág. 4. Sin RTL. Contrato y ecuaciones: datapath.md.',
                  50, height-55, 1700, 35, 16)

    def node(self, ident, label, x, y, w, h, style=''):
        c = E.SubElement(self.root, 'mxCell', id=ident, value=label, vertex='1',
                         parent='1', style='html=0;whiteSpace=wrap;fontFamily=Helvetica;'
                         'fontSize=19;fontColor=#172b4d;fillColor=none;strokeColor=#344563;'
                         'strokeWidth=2;rounded=0;align=center;verticalAlign=middle;spacing=8;'+style)
        E.SubElement(c, 'mxGeometry', x=str(x), y=str(y), width=str(w), height=str(h),
                     **{'as': 'geometry'})

    def text(self, ident, label, x, y, w, h, size=19):
        self.node(ident, label, x, y, w, h,
                  f'text;strokeColor=none;align=left;spacing=0;fontSize={size};')

    def mux(self, ident, label, x, y, w=120, h=180, multi=False):
        shape = ('shape=trapezoid;direction=east;fixedSize=1;size=20;' if multi else
                 'shape=mxgraph.electrical.abstract.mux2;')
        self.node(ident, label, x, y, w, h, shape+'spacing=1;')

    def op(self, ident, label, x, y, w, h):
        self.node(ident, label, x, y, w, h, 'ellipse;')

    def wire(self, src, dst, label='', points=(), control=False, ports=''):
        c = E.SubElement(self.root, 'mxCell', id=f'edge-{len(self.root)}', value=label,
                         edge='1', parent='1', source=src, target=dst,
                         style='edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=block;'
                         'endFill=1;strokeColor=#344563;strokeWidth=2;fontFamily=Helvetica;'
                         'fontSize=17;labelBackgroundColor=#ffffff;'
                         'exitX=1;exitY=0.5;entryX=0;entryY=0.5;'
                         + ('dashed=1;' if control else '') + ports)
        g = E.SubElement(c, 'mxGeometry', relative='1', **{'as': 'geometry'})
        if points:
            a = E.SubElement(g, 'Array', **{'as': 'points'})
            for x, y in points:
                E.SubElement(a, 'mxPoint', x=str(x), y=str(y))


def add_datapath(doc):
    p = Page(doc, 'dp-recorrido', 'DATAPATH · Recorrido',
             'DSI_TEST_PATTERN · DATAPATH 1/2 · RECORRIDO Y CONDICIONES',
             'Bloques sin relleno · MUX con entradas numeradas · buses [n] · controles discontinuos.\n'
             'Registros en ↑clk; rst síncrono activo alto, prioritario sobre LD; LD=0 conserva Q.', 2350)
    for i, (reg, width, sel, ld, cond, compare) in enumerate([
        ('X', 'NX', 'STEP_PIXEL', 'INIT | STEP_PIXEL | STEP_LINE', 'X_END', 'WIDTH−1'),
        ('Y', 'NY', 'STEP_LINE', 'INIT | STEP_LINE', 'Y_END', 'HEIGHT−1'),
        ('C', '2', 'STEP_COMP', 'INIT | STEP_COMP | STEP_PIXEL | STEP_LINE', 'IS_B', '2 (B)')
    ]):
        y = 240 + i*460
        p.text(f'title-{reg}', f'{i+1}. R_{reg} · '+
               {'X':'PÍXEL EN LÍNEA', 'Y':'LÍNEA EN CUADRO', 'C':'COMPONENTE: R=0, G=1, B=2'}[reg],
               50, y-35, 1700, 40, 22)
        p.text(f'zero-{reg}', f'0 [{width}]', 70, y+35, 250, 65)
        p.text(f'one-{reg}', f'1 [{width}]', 70, y+165, 250, 65)
        p.op(f'add-{reg}', f'A{i} · +1\n[{width}]', 410, y+145, 200, 100)
        p.mux(f'mux-{reg}', f'M{i}\n2:1\n[{width}]', 780, y+20)
        p.node(f'reg-{reg}', f'R_{reg} [{width}]\nD=M{i}; LD=LD_{reg}\n↑clk; rst → 0',
               1080, y+40, 280, 150)
        p.text(f'q-{reg}', f'{reg} [{width}]\n→ '+('color (pág. 3)' if reg=='X' else
               'selector (pág. 3)' if reg=='C' else 'condición de fin'), 1480, y+50, 270, 80)
        p.op(f'cmp-{reg}', f'{["CX","CY","CC"][i]} · == {compare}\nEntrada: {reg} [{width}]',
             1480, y+210, 270, 110)
        p.text(f'cond-{reg}', f'{cond} [1] → UC y pág. 3', 1440, y+355, 320, 60)
        p.text(f'sel-{reg}', f'SEL_M{i} = {sel} [1]', 670, y+290, 360, 65)
        p.text(f'ld-{reg}', f'LD_{reg} = {ld}\nDesde UC; clk / rst comunes',
               1050, y+285, 370, 90, 17)
        p.wire(f'zero-{reg}', f'mux-{reg}', f'0 [{width}]',
               ports='entryX=0;entryY=0.25;')
        p.wire(f'one-{reg}', f'add-{reg}', f'[{width}]')
        p.wire(f'add-{reg}', f'mux-{reg}', f'1 [{width}]',
               points=[(680,y+195),(680,y+155)], ports='entryX=0;entryY=0.75;')
        p.wire(f'mux-{reg}', f'reg-{reg}', f'D [{width}]')
        p.wire(f'reg-{reg}', f'q-{reg}', f'Q [{width}]')
        p.wire(f'reg-{reg}', f'add-{reg}', f'{reg} [{width}]',
               [(1420,y+115),(1420,y+410),(510,y+410)],
               ports='entryX=0.5;entryY=1;')
        p.wire(f'q-{reg}', f'cmp-{reg}', f'[{width}]',
               ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
        p.wire(f'cmp-{reg}', f'cond-{reg}', '[1]',
               ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
        p.wire(f'sel-{reg}', f'mux-{reg}', 'SEL [1]', control=True,
               points=[(840,y+255)], ports='exitX=0.5;exitY=0;entryX=0.5;entryY=1;')
        p.wire(f'ld-{reg}', f'reg-{reg}', 'LD / clk / rst [1 c/u]', control=True,
               ports='exitX=0.5;exitY=0;entryX=0.5;entryY=1;')

    p.text('widths', 'NX=max(1, ceil(log2(WIDTH))); NY=max(1, ceil(log2(HEIGHT))).\n'
           '720×720: NX=10, NY=10 → 22 bits de datapath. No contar la memoria de UC aquí.\n'
           'M0–M2: 0 inicializa/reinicia; 1 incrementa. Retención mediante LD, sin MUX adicional.\n'
           'R_C solo suma en R/G; desde B vuelve a 0 al avanzar píxel o línea. No alcanza 3.',
           50, 1670, 1700, 160)
    p.node('uc', 'FRONTERA CON UC · FSM EN PÁGINA 4\n'
           'Entradas: start_valid, tx_byte_ready, X_END, Y_END, IS_B, clk, rst.\n'
           'Salidas: INIT, STEP_COMP, STEP_PIXEL, STEP_LINE, tx_byte_valid, start_ready, busy, frame_done.\n'
           'Todos los controles de carga son combinacionales antes del mismo posedge de aceptación.',
           50, 1880, 1700, 170)
    p.text('ops', 'INIT=START_FIRE; STEP_COMP=BYTE_FIRE & !IS_B;\n'
           'STEP_PIXEL=BYTE_FIRE & IS_B & !X_END;\n'
           'STEP_LINE=BYTE_FIRE & IS_B & X_END & !Y_END;\n'
           'FINISH=BYTE_FIRE & IS_B & X_END & Y_END → UC (no carga X/Y/C).',
           50, 2100, 1700, 140)

    p = Page(doc, 'dp-color', 'DATAPATH · Color y salida',
             'DSI_TEST_PATTERN · DATAPATH 2/2 · COLOR, BYTE Y MARCAS',
             'Toda esta página es combinacional. X y C vienen de R_X y R_C (pág. 2).\n'
             'No hay registro RGB, contador de franja, ROM secuencial ni registros de salida.', 2350)
    p.text('sect1', '1. SELECCIÓN DE FRANJA Y COLOR · B=WIDTH/8 CONSTANTE', 50, 205, 1700, 40, 22)
    p.text('xin', 'X [NX]\nDesde R_X', 50, 330, 200, 80)
    p.op('thresholds', 'C1…C7 · 7 comparadores ≥\nT_i = (X ≥ i·B), i=1…7\nCada umbral tiene NX bits',
         360, 290, 440, 160)
    p.node('encoder', 'P0 · CODIFICADOR DE PRIORIDAD\nT7…T1 [7] → S [3]\n'
           'Mayor i verdadero; ninguno → 0\nSin registro ni división variable', 990, 290, 430, 160)
    p.text('sout', 'S [3]\nFranja 0…7', 1550, 330, 200, 80)
    p.wire('xin','thresholds','[NX]'); p.wire('thresholds','encoder','T[7:1] [7]')
    p.wire('encoder','sout','[3]')
    p.text('palette', 'CONSTANTES RGB [24]\n0: FFFFFF · blanco\n1: FFFF00 · amarillo\n'
           '2: 00FFFF · cian\n3: 00FF00 · verde\n4: FF00FF · magenta\n'
           '5: FF0000 · rojo\n6: 0000FF · azul\n7: 000000 · negro', 50, 550, 390, 320)
    p.mux('palette-mux', 'M3\n8:1\n[24]', 570, 550, 130, 310, multi=True)
    for i in range(8):
        p.wire('palette', 'palette-mux', f'{i} [24]',
               ports=f'exitX=1;exitY={(i+0.5)/8};entryX=0;entryY={(i+0.5)/8};')
    p.text('rgb', 'RGB [23:0]\nR=[23:16]; G=[15:8]; B=[7:0]', 850, 630, 510, 100)
    p.wire('palette-mux','rgb','[24]')
    p.wire('sout','palette-mux','SEL_M3 [3]', [(1650,490),(635,490)], True,
           'exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
    p.text('sect2','2. COMPONENTE RGB → BYTE · SALIDA CERO CUANDO VALID=0',50,930,1700,40,22)
    p.text('components', '0: RGB[23:16] [8] (R)\n1: RGB[15:8] [8] (G)\n'
           '2: RGB[7:0] [8] (B)\n3: 00 [8] (no usado)',50,1040,390,180)
    p.mux('component-mux','M4\n4:1\n[8]',570,1030,130,200,multi=True)
    p.wire('rgb','components','[24]',[(1380,680),(1380,885),(20,885),(20,1010),(245,1010)],
           ports='entryX=0.5;entryY=0;')
    for i in range(4):
        p.wire('components','component-mux',f'{i} [8]',
               ports=f'exitX=1;exitY={(i+0.5)/4};entryX=0;entryY={(i+0.5)/4};')
    p.text('cin','C [2] desde R_C\nSEL_M4=C; 0=R, 1=G, 2=B',440,1320,530,85)
    p.wire('cin','component-mux','SEL [2]',control=True,
           ports='exitX=0.37;exitY=0;entryX=0.5;entryY=1;')
    p.mux('output-mux','M5\n2:1\n[8]',1130,1040,120,180)
    p.text('zero','0: 00 [8]',850,990,220,60)
    p.wire('zero','output-mux','0 [8]',ports='entryX=0;entryY=0.25;')
    p.wire('component-mux','output-mux','1: byte RGB [8]',[(800,1130),(800,1175)],
           ports='entryX=0;entryY=0.75;')
    p.text('output','tx_byte_data [8]',1430,1090,320,80)
    p.wire('output-mux','output','[8]')
    p.text('valid','tx_byte_valid [1] desde UC\n!rst & ACTIVE',1100,1320,650,85)
    p.wire('valid','output-mux','SEL_M5 [1]',control=True,
           ports='exitX=0.14;exitY=0;entryX=0.5;entryY=1;')
    p.text('sect3','3. FIN DE LÍNEA / CUADRO · NIVELES DEL BYTE, NO PULSOS',50,1490,1700,40,22)
    p.text('flags','IS_B, X_END, Y_END [1 c/u]\nDesde CC, CX, CY (pág. 2)\n'
           'tx_byte_valid [1] desde UC',50,1610,410,130)
    p.op('line','G0 · AND\nLINE_END = IS_B & X_END',570,1580,450,110)
    p.op('frame','G1 · AND\nFRAME_END = LINE_END & Y_END',570,1790,450,110)
    p.op('mask-line','G2 · AND\ntx_line_last = valid & LINE_END',1190,1580,550,110)
    p.op('mask-frame','G3 · AND\ntx_frame_last = valid & FRAME_END',1190,1790,550,110)
    p.wire('flags','line','[1] + [1]')
    p.wire('flags','frame','Y_END [1]',[(490,1675),(490,1845)])
    p.wire('line','frame','LINE_END [1]',control=False,
           ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
    p.wire('line','mask-line','LINE_END [1]');p.wire('frame','mask-frame','FRAME_END [1]')
    p.wire('valid','mask-line','valid [1]',control=True,
           ports='exitX=0.8;exitY=1;entryX=0.8;entryY=0;')
    p.wire('valid','mask-frame','valid [1]',[(1770,1360),(1770,1845)],True,
           'exitX=1;exitY=0.5;entryX=1;entryY=0.5;')
    p.text('stable','PAUSA: BYTE_FIRE=0 → STEP_COMP=STEP_PIXEL=STEP_LINE=0 → X/Y/C se conservan.\n'
           'Con un cuadro activo, byte y marcas permanecen estables hasta aceptación.\n'
           'Reset enmascara valid y marcas de inmediato; X/Y/C vuelven a 0 en el siguiente posedge.\n'
           'frame_done pertenece a UC: registro de un bit, D=FINISH, reset a 0; no duplicarlo aquí.',
           50,2010,1700,150)
    p.text('limits','Sin ECC/CRC, temporización de vídeo, FIFO ni pads. No añadir un registro de byte '
           'sin revisar la latencia y la alineación de las marcas.\n'
           'M4 selecciona 00 para C=3, código fuera de la secuencia legal; no constituye detección de fallos.',
           50,2190,1700,90)
