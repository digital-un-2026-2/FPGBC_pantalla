"""Genera Draw.io y SVG del flujo propuesto, sin dependencias externas."""
from pathlib import Path
import textwrap
import xml.etree.ElementTree as E

OUT = Path(__file__).resolve().parent
COLORS = {
    'process': ('#eaf2fc', '#5b7fa6'),
    'decision': ('#fff4d6', '#b69a50'),
    'terminal': ('#e8edf4', '#5c708a'),
    'fault': ('#fde9e7', '#ba5d54'),
    'text': ('none', 'none'),
    'register': ('#ffffff', '#344563'),
    'mux': ('#ffffff', '#344563'),
    'operator': ('#ffffff', '#344563'),
    'external': ('#f3f5f7', '#7a869a'),
    'control': ('#ffffff', '#7a869a'),
    'memory': ('#ffffff', '#344563'),
    'state': ('#eaf2fc', '#344563'),
}


class Page:
    def __init__(self, name, height):
        self.name, self.height = name, height
        self.nodes, self.edges = {}, []

    def node(self, key, text, x, y, w=620, h=110, kind='process'):
        self.nodes[key] = (text, x, y, w, h, kind)

    def edge(self, source, target, label='', points=(), ports='bt', dashed=False):
        self.edges.append((source, target, label, points, ports, dashed))

    def anchor(self, key, port):
        _, x, y, w, h, _ = self.nodes[key]
        return {'t': (x+w/2, y), 'b': (x+w/2, y+h),
                'l': (x, y+h/2), 'r': (x+w, y+h/2),
                'u': (x, y+h/4), 'd': (x, y+3*h/4)}[port]

    def write(self, doc, filename):
        diagram = E.SubElement(doc, 'diagram', id=filename, name=self.name)
        model = E.SubElement(diagram, 'mxGraphModel', grid='1', gridSize='10',
                             page='1', pageWidth='1800', pageHeight=str(self.height))
        root = E.SubElement(model, 'root')
        E.SubElement(root, 'mxCell', id='0')
        E.SubElement(root, 'mxCell', id='1', parent='0')
        svg = E.Element('svg', xmlns='http://www.w3.org/2000/svg',
                        width='1800', height=str(self.height),
                        viewBox=f'0 0 1800 {self.height}')
        E.SubElement(svg, 'title').text = self.name + ' — Planificador DSI propuesto'
        defs = E.SubElement(svg, 'defs')
        marker = E.SubElement(defs, 'marker', id='arrow', viewBox='0 0 10 10',
                              refX='9', refY='5', markerWidth='8', markerHeight='8',
                              orient='auto-start-reverse')
        E.SubElement(marker, 'path', d='M 0 0 L 10 5 L 0 10 z', fill='#5c708a')
        E.SubElement(svg, 'rect', width='1800', height=str(self.height), fill='white')
        coords = {'t': (0.5, 0), 'b': (0.5, 1), 'l': (0, 0.5), 'r': (1, 0.5),
                  'u': (0, 0.25), 'd': (0, 0.75)}
        labels = []
        for i, (a, b, label, points, ports, dashed) in enumerate(self.edges):
            ex, ey = coords[ports[0]]
            ix, iy = coords[ports[1]]
            cell = E.SubElement(root, 'mxCell', id=f'edge-{i}', parent='1',
                source=a, target=b, value=label, edge='1', style=(
                    'edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=block;'
                    'strokeColor=#5c708a;strokeWidth=2;fontSize=17;'
                    'labelBackgroundColor=#ffffff;'
                    f'exitX={ex};exitY={ey};entryX={ix};entryY={iy};'
                    + ('dashed=1;' if dashed else '')))
            geom = E.SubElement(cell, 'mxGeometry', relative='1', **{'as': 'geometry'})
            if points:
                arr = E.SubElement(geom, 'Array', **{'as': 'points'})
                for x, y in points:
                    E.SubElement(arr, 'mxPoint', x=str(x), y=str(y))
            raw_route = [self.anchor(a, ports[0]), *points, self.anchor(b, ports[1])]
            route = [raw_route[0]]
            for x, y in raw_route[1:]:
                px, py = route[-1]
                if px != x and py != y:
                    route.append((px, y) if ports[0] in 'tb' else (x, py))
                route.append((x, y))
            attrs = {'points': ' '.join(f'{x},{y}' for x, y in route),
                     'fill': 'none', 'stroke': '#5c708a', 'stroke-width': '2',
                     'marker-end': 'url(#arrow)'}
            if dashed:
                attrs['stroke-dasharray'] = '8 6'
            E.SubElement(svg, 'polyline', attrs)
            if label:
                (x1, y1), (x2, y2) = route[:2]
                labels.append(((x1+x2)/2 + (20 if x1 == x2 else 0),
                               (y1+y2)/2 - (0 if x1 == x2 else 12), label))
        for key, (text, x, y, w, h, kind) in self.nodes.items():
            fill, stroke = COLORS[kind]
            style = ('html=0;whiteSpace=wrap;fontFamily=Helvetica;fontSize=19;'
                     'fontColor=#172b4d;strokeWidth=2;align=center;verticalAlign=middle;'
                     f'fillColor={fill};strokeColor={stroke};spacing=10;')
            style += {'decision': 'rhombus;', 'terminal': 'rounded=1;arcSize=50;',
                      'text': 'text;align=left;spacing=0;',
                      'register': 'rounded=0;', 'memory': 'rounded=0;',
                      'operator': 'ellipse;', 'state': 'ellipse;', 'control': 'rounded=0;dashed=1;',
                      'mux': 'shape=trapezoid;direction=east;'}.get(kind, 'rounded=1;arcSize=12;')
            cell = E.SubElement(root, 'mxCell', id=key, parent='1', value=text,
                                vertex='1', style=style)
            E.SubElement(cell, 'mxGeometry', x=str(x), y=str(y), width=str(w),
                         height=str(h), **{'as': 'geometry'})
            if kind == 'decision':
                E.SubElement(svg, 'polygon', points=f'{x+w/2},{y} {x+w},{y+h/2} '
                             f'{x+w/2},{y+h} {x},{y+h/2}', fill=fill, stroke=stroke,
                             **{'stroke-width': '2'})
            elif kind == 'mux':
                E.SubElement(svg, 'polygon', points=f'{x},{y} {x+w},{y+20} '
                             f'{x+w},{y+h-20} {x},{y+h}', fill=fill, stroke=stroke,
                             **{'stroke-width': '2'})
            elif kind in ('operator', 'state'):
                E.SubElement(svg, 'ellipse', cx=str(x+w/2), cy=str(y+h/2),
                             rx=str(w/2), ry=str(h/2), fill=fill, stroke=stroke,
                             **{'stroke-width': '2'})
            elif kind != 'text':
                E.SubElement(svg, 'rect', x=str(x), y=str(y), width=str(w),
                             height=str(h), rx=('0' if kind in ('register', 'memory', 'control')
                                              else '28' if kind == 'terminal' else '12'),
                             fill=fill, stroke=stroke, **{'stroke-width': '2',
                             'stroke-dasharray': '8 6' if kind == 'control' else 'none'})
            lines = []
            for line in text.splitlines():
                lines += textwrap.wrap(line, width=max(18, int(w/10)-3)) or ['']
            font = 28 if key == 'title' else 19
            line_height = font + 7
            top = y + (h-len(lines)*line_height)/2 + font
            for j, line in enumerate(lines):
                E.SubElement(svg, 'text', x=str(x if kind == 'text' else x+w/2),
                    y=str(top+j*line_height), fill='#172b4d',
                    **{'font-family': 'Helvetica, Arial, sans-serif',
                       'font-size': str(font), 'text-anchor': 'start' if kind == 'text' else 'middle'}).text = line
        for x, y, label in labels:
            E.SubElement(svg, 'text', x=str(x), y=str(y), fill='#344563',
                **{'font-family': 'Helvetica, Arial, sans-serif', 'font-size': '17',
                   'paint-order': 'stroke', 'stroke': 'white', 'stroke-width': '6',
                   'stroke-linejoin': 'round'}).text = label
        E.indent(svg)
        E.ElementTree(svg).write(OUT / f'{filename}.svg', encoding='utf-8', xml_declaration=True)


def firmware():
    p = Page('1 · FIRMWARE RISC-V Y CSR LITEX', 2700)
    p.node('title', 'PLANIFICADOR DSI · FIRMWARE RISC-V', 60, 20, 1680, 70, 'text')
    p.node('subtitle', 'PROPUESTA · Inicialización y supervisión por software; vídeo coordinado por RTL.\nUna caja representa una operación, no un ciclo ni un estado definitivo.', 60, 100, 1680, 80, 'text')
    def n(k, t, y, kind='process', h=110):
        p.node(k, t, 430, y, 660, h, kind)
    n('start', 'ARRANQUE DEL FIRMWARE', 230, 'terminal', 65)
    n('safe', 'MANTENER VÍDEO DETENIDO\nInicializar CPU, memoria y acceso a CSR\nInvalidar panel_initialized', 355)
    n('profile', '¿Perfil de panel y PHY\nvalidado para el destino?', 535, 'decision', 160)
    n('init', 'INICIALIZAR PANEL POR LPDT\nEnviar comandos DCS desde software\nEsperar fin de cada envío y retardos del panel', 770, h=140)
    n('initialized', '¿Secuencia completada\nsin fallo local?', 990, 'decision', 160)
    n('config', 'CONFIGURAR POR CSR CON VÍDEO DETENIDO\nSeleccionar perfil compatible y VC\nAPPLY valida dimensiones y calendario del perfil', 1230, h=140)
    n('accepted', '¿Configuración aceptada\ny ruta disponible?', 1450, 'decision', 160)
    n('run', 'AUTORIZAR E INICIAR VÍDEO\npanel_initialized ← 1; emitir START\nEl RTL captura la configuración activa', 1690, h=120)
    n('monitor', 'SUPERVISAR POR CSR\nLeer estado, cuadros y causa de fallo\nAtender solicitudes de parada o cambios', 1890, h=120)
    n('faultq', '¿Hay fallo?', 2080, 'decision', 140)
    n('stopq', '¿Parar o reconfigurar?', 2300, 'decision', 150)
    p.node('stop', 'SOLICITAR STOP\nEsperar stopped y enlace libre\nAntes de reconfigurar o enviar DCS', 1200, 2310, 500, 140)
    p.node('fault', 'BLOQUEAR NUEVOS INICIOS\nRegistrar causa; invalidar autorización\nRecuperación con reset coordinado\ny nueva inicialización', 1200, 900, 500, 180, 'fault')
    p.node('blocked', 'SIN PERFIL VÁLIDO\nMantener salida física inhibida\nUsar perfil sintético solo en simulación', 1200, 525, 500, 170, 'fault')
    p.node('csr', 'PUENTE LITEX / CSR PROPUESTO\n\nCPU → RTL\nCONFIG + APPLY; START; STOP\npanel_initialized; reset coordinado\n\nRTL → CPU\nconfig_ok; running; stopped\nframe_count; error; error_cause\n\nEventos persistentes o contadores:\nel software no debe perder pulsos.\nCSR concretos y mapa: por implementar.', 1200, 1200, 500, 480, 'text')
    p.node('limits', 'RESPONSABILIDADES\n\nRISC-V configura y supervisa.\nLos píxeles no pasan por la CPU.\nInicialización LPDT solo con vídeo parado.\nFin LPDT no confirma recepción del LCD.\nCambios activos se rechazan: parar primero.', 1200, 1730, 500, 310, 'text')
    for a, b in [('start','safe'), ('safe','profile'), ('init','initialized'), ('config','accepted'), ('run','monitor'), ('monitor','faultq')]:
        p.edge(a,b)
    for a,b in [('profile','init'), ('initialized','config'), ('accepted','run')]:
        p.edge(a,b,'Sí')
    p.edge('profile','blocked','No',ports='rl')
    p.edge('initialized','fault','No',[(1140,1070),(1140,990)],'rl')
    p.edge('accepted','fault','No',[(1140,1530),(1140,990)],'rl')
    p.edge('faultq','fault','Sí',[(1760,2150),(1760,990)],'rr')
    p.edge('faultq','stopq','No')
    p.edge('stopq','monitor','No',[(280,2375),(280,1950)],'ll')
    p.edge('stopq','stop','Sí',ports='rl')
    p.edge('stop','config','Enlace libre',[(1740,2500),(150,2500),(150,1300)],'bl')
    p.node('footer', 'PROPUESTA · Sin CPU, firmware ni CSR nuevos implementados. Reset o fallo global invalidan la autorización.\nLa página 2 detalla el flujo RTL. El perfil real del LCD continúa pendiente.', 60, 2570, 1680, 100, 'text')
    return p


def rtl():
    p = Page('2 · PLANIFICADOR RTL DE VIDEO', 3450)
    p.node('title', 'PLANIFICADOR DSI · FLUJO RTL', 60, 20, 1680, 70, 'text')
    p.node('subtitle', 'PROPUESTA · Calendario de eventos según el modo del panel, sin fijar porches, fps ni bitrate.\nFuente inicial: dsi_test_pattern; reloj de vídeo y relación con CSR por definir al integrar.', 60, 100, 1680, 90, 'text')
    def n(k,t,y,kind='process',h=110):
        p.node(k,t,430,y,660,h,kind)
    n('reset','RESET COORDINADO\nInvalidar cuadro, eventos y configuración activa\nBloquear nuevas transferencias',240,h=120)
    n('wait','ESPERAR START AUTORIZADO\nConfiguración válida + panel inicializado\nPHY disponible + cadena libre de fallos',440,h=120)
    n('begin','INICIAR CUADRO\nConservar perfil activo; reiniciar línea y calendario\nIniciar fuente con start_valid ∧ start_ready',640,h=120)
    n('event','SELECCIONAR SIGUIENTE EVENTO\nSegún línea, cuadro y modo del perfil\nEvento: espera, paquete o fin de cuadro',850,h=120)
    n('isend','¿Evento = fin de cuadro?',1050,'decision',140)
    n('iswait','¿Evento = espera?',1280,'decision',140)
    n('descriptor','OFRECER DESCRIPTOR DEL PAQUETE\nMantener campos y valid hasta ready\nRGB888: DT=0x3E; WC=3×WIDTH; VC del perfil',1520,h=130)
    n('payload','PREPARAR Y CARGAR PAQUETE COMPLETO\nPara RGB: conectar payload de la fuente\nSolo valid ∧ ready consume bytes; comprobar marcas',1740,h=130)
    n('packet','¿Paquete aceptado completo\npor la cadena de salida?',1960,'decision',160)
    n('physical','ESPERAR FIN DEL TRANSPORTE\nRetener eventos de fin aunque lleguen antes\nEsperar hs_complete y transporte disponible',2220,h=130)
    n('deadline','¿Se cumple el calendario\nsin error de la cadena?',2440,'decision',160)
    n('advance','AVANZAR EVENTO / LÍNEA\nSolo después del paquete completo\nNo iniciar otro cuadro con fin local del payload',2700,h=120)
    p.node('frame','CUADRO TRANSMITIDO LOCALMENTE\nIncrementar frame_count\nIncluye finalización del último evento',1200,1000,510,150)
    p.node('stopq','¿STOP pendiente?',1200,1240,510,150,'decision')
    p.node('stopped','DETENIDO\nPublicar stopped con enlace libre\nAceptar configuración o inicialización',1200,1480,510,140,'terminal')
    p.node('delay','ESPERAR PLAZO\nContador RTL\nAl vencer: avanzar',50,1280,290,180)
    p.node('fault','FALLO PERSISTENTE\nBloquear nuevos descriptores\nPublicar primera causa por CSR\nSi falla PHY: aplicar aborto existente\nRecuperar con reset de toda la cadena',1200,2410,510,220,'fault')
    p.node('meaning','DOS FINALES DIFERENTES\n\npacket_done: CRC final aceptado por el consumidor del preparador.\nhs_done: última palabra entregada al PHY.\nhs_complete: secuencia HS finalizada.\n\nEl planificador debe conservar estos eventos, no exigir pulsos simultáneos.\nNinguno confirma recepción del LCD.',1200,1750,510,440,'text')
    p.node('global','PRIORIDADES GLOBALES\n\n1. Reset coordinado → RESET.\n2. Fallo / aborto → FALLO.\n3. STOP → retener solicitud y terminar cuadro.\n\nFallo o plazo perdido no se reintentan como cuadro correcto.',1200,2800,510,300,'text')
    for a,b in [('reset','wait'),('wait','begin'),('begin','event'),('event','isend'),('descriptor','payload'),('payload','packet'),('physical','deadline')]:
        p.edge(a,b)
    p.edge('isend','iswait','No')
    p.edge('isend','frame','Sí',ports='rl')
    p.edge('frame','stopq')
    p.edge('stopq','stopped','Sí')
    p.edge('stopq','begin','No',[(1750,1315),(1750,700)],'rr')
    p.edge('iswait','delay','Sí',[(385,1350),(385,1370)],'lr')
    p.edge('delay','event','Venció',[(30,1370),(30,910)],'ll')
    p.edge('iswait','descriptor','No')
    p.edge('packet','physical','Sí')
    p.edge('packet','payload','No: continuar',[(360,2040),(360,1805)],'ll')
    p.edge('deadline','advance','Sí')
    p.edge('deadline','fault','No',ports='rl')
    p.edge('advance','event','Siguiente',[(760,2900),(390,2900),(390,910)],'bl')
    p.node('notes','CONTRATO DE LA PROPUESTA\n\n• Esperas y ready: conservar datos y descriptor; reset/fallo tienen prioridad global.\n• Un paquete en vuelo; el transporte actual no carga el siguiente durante HS.\n• Configuración activa inmutable; STOP se atiende al terminar el cuadro.\n• Si un plazo vence en cualquier operación, registrar fallo; no acumular retraso silencioso.\n• El calendario debe incluir carga del paquete, arranque/parada HS y tiempo de enlace.',60,2980,1060,340,'text')
    p.node('footer','LÍMITES · El calendario exacto depende de Video/Command Mode y del panel. Eventos no RGB requieren\npreparación adicional. Este flujo no demuestra que el transporte actual alcance la frecuencia de imagen requerida.',60,3340,1680,90,'text')
    return p


def main():
    from generar_datapath import pages as datapath_pages
    from generar_fsm import pages as fsm_pages
    doc = E.Element('mxfile', host='app.diagrams.net')
    firmware().write(doc, 'flujo_firmware')
    rtl().write(doc, 'flujo_rtl')
    for filename, page in datapath_pages(Page):
        page.write(doc, filename)
    for filename, page in fsm_pages(Page):
        page.write(doc, filename)
    doc.set('pages', str(len(doc.findall('diagram'))))
    E.indent(doc)
    E.ElementTree(doc).write(OUT / 'DSI_VIDEO_SCHEDULER.drawio', encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    main()
