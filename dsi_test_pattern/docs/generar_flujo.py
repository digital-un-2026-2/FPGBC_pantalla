"""Genera el flujo editable con las convenciones de los módulos DSI previos."""
from pathlib import Path
import xml.etree.ElementTree as E
from generar_datapath import add_datapath
from generar_fsm import add_fsm

OUT = Path(__file__).resolve().parent


def generate():
    doc = E.Element('mxfile', host='app.diagrams.net')
    page = E.SubElement(doc, 'diagram', id='dsi-test-pattern-flujo', name='FLUJO')
    model = E.SubElement(page, 'mxGraphModel', grid='1', gridSize='10', page='1',
                         pageWidth='1750', pageHeight='2550', background='#ffffff')
    root = E.SubElement(model, 'root')
    E.SubElement(root, 'mxCell', id='0')
    E.SubElement(root, 'mxCell', id='1', parent='0')
    base = ('html=0;whiteSpace=wrap;fontFamily=Helvetica;fontSize=19;'
            'fontColor=#172b4d;strokeWidth=2;align=center;verticalAlign=middle;spacing=10;')
    styles = {
        'process': 'rounded=1;arcSize=12;fillColor=#eaf2fc;strokeColor=#5b7fa6;',
        'decision': 'rhombus;fillColor=#fff4d6;strokeColor=#b69a50;spacing=3;',
        'terminal': 'rounded=1;arcSize=50;fillColor=#e8edf4;strokeColor=#5c708a;',
        'text': 'text;fillColor=none;strokeColor=none;align=left;spacing=0;',
    }

    def node(ident, value, x, y, w=600, h=100, kind='process', extra=''):
        cell = E.SubElement(root, 'mxCell', id=ident, parent='1', value=value,
                            vertex='1', style=base + styles[kind] + extra)
        E.SubElement(cell, 'mxGeometry', x=str(x), y=str(y), width=str(w),
                     height=str(h), **{'as': 'geometry'})

    def edge(source, target, label='', points=(), ports='', dashed=False):
        cell = E.SubElement(root, 'mxCell', id=f'edge-{len(root)}', parent='1',
                            source=source, target=target, value=label, edge='1',
                            style=('edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;'
                                   'endArrow=block;endFill=1;strokeColor=#5c708a;strokeWidth=2;'
                                   'fontFamily=Helvetica;fontSize=17;labelBackgroundColor=#ffffff;'
                                   'exitX=0.5;exitY=1;entryX=0.5;entryY=0;'
                                   + ('dashed=1;' if dashed else '') + ports))
        geometry = E.SubElement(cell, 'mxGeometry', relative='1', **{'as': 'geometry'})
        if points:
            array = E.SubElement(geometry, 'Array', **{'as': 'points'})
            for x, y in points:
                E.SubElement(array, 'mxPoint', x=str(x), y=str(y))

    node('title', 'DSI_TEST_PATTERN · DIAGRAMA DE FLUJO', 60, 25, 1630, 60,
         'text', 'fontSize=29;fontStyle=1;')
    node('subtitle', 'PROPUESTO · Fuente RGB888 autónoma de franjas verticales.\n'
         'Una caja es una operación; no fija un estado ni un ciclo de FSM.',
         60, 95, 1600, 65, 'text')
    node('start', 'INICIO', 650, 190, 280, 55, 'terminal')
    node('reset', 'RESET INTERNO\nx ← 0; y ← 0; componente ← R\n'
         'busy ← 0; frame_done ← 0; bloquear transferencias', 490, 290, h=115)
    node('global-reset', 'rst = 1\nDesde cualquier punto\nPrioridad sobre handshake',
         1250, 290, 420, 115, 'terminal')
    node('rst-low', '¿rst = 0?', 580, 460, 420, 130, 'decision')
    node('wait', 'ESPERAR SOLICITUD DE CUADRO\nstart_ready = 1; busy = 0; tx_byte_valid = 0',
         490, 645, h=100)
    node('start-fire', '¿START_FIRE = 1?\nstart_valid ∧ start_ready',
         560, 800, 460, 140, 'decision')
    node('accept', 'ACEPTAR CUADRO\nx ← 0; y ← 0; componente ← R\n'
         'busy ← 1; start_ready = 0', 490, 1000, h=110)
    node('offer', 'OFRECER COMPONENTE DEL PÍXEL (x,y)\n'
         'Color según franja de x; byte = R, G o B\n'
         'tx_byte_valid = 1; derivar line_last / frame_last', 490, 1180, h=125)
    node('byte-fire', '¿BYTE_FIRE = 1?\ntx_byte_valid ∧ tx_byte_ready',
         550, 1370, 480, 140, 'decision')
    node('is-b', '¿El byte aceptado era B?', 550, 1590, 480, 140, 'decision')
    node('next-component', 'SIGUIENTE COMPONENTE\nR → G; G → B\nConservar x e y',
         70, 1600, 300, 120)
    node('line-end', '¿x = WIDTH − 1?\nCon valores del byte aceptado',
         550, 1810, 480, 140, 'decision')
    node('next-pixel', 'SIGUIENTE PÍXEL\nx ← x + 1\ncomponente ← R', 70, 1820, 300, 120)
    node('frame-end', '¿y = HEIGHT − 1?\nCon valores del byte aceptado',
         550, 2030, 480, 140, 'decision')
    node('next-line', 'SIGUIENTE LÍNEA\nx ← 0; y ← y + 1\ncomponente ← R',
         1250, 2040, 420, 120)
    node('done', 'CUADRO ENTREGADO AL CONSUMIDOR\nbusy ← 0; tx_byte_valid = 0\n'
         'frame_done ← 1 durante un ciclo; volver a esperar', 490, 2260, h=115)

    edge('start', 'reset')
    edge('global-reset', 'reset', points=(), dashed=True,
         ports='exitX=0;exitY=0.5;entryX=1;entryY=0.5;')
    edge('reset', 'rst-low')
    edge('rst-low', 'wait', 'Sí')
    edge('rst-low', 'reset', 'No', [(440, 525), (440, 345)],
         'exitX=0;exitY=0.5;entryX=0;entryY=0.5;')
    edge('wait', 'start-fire')
    edge('start-fire', 'wait', 'No · esperar', [(1150, 870), (1150, 695)],
         'exitX=1;exitY=0.5;entryX=1;entryY=0.5;')
    edge('start-fire', 'accept', 'Sí')
    edge('accept', 'offer')
    edge('offer', 'byte-fire')
    edge('byte-fire', 'offer', 'No · conservar byte y marcas',
         [(1150, 1440), (1150, 1240)], 'exitX=1;exitY=0.5;entryX=1;entryY=0.5;')
    edge('byte-fire', 'is-b', 'Sí')
    edge('is-b', 'next-component', 'No', ports='exitX=0;exitY=0.5;entryX=1;entryY=0.5;')
    edge('next-component', 'offer', points=[(400, 1660), (400, 1210)],
         ports='exitX=1;exitY=0.5;entryX=0;entryY=0.25;')
    edge('is-b', 'line-end', 'Sí')
    edge('line-end', 'next-pixel', 'No', ports='exitX=0;exitY=0.5;entryX=1;entryY=0.5;')
    edge('next-pixel', 'offer', points=[(210, 1970), (30, 1970), (30, 1275)],
         ports='entryX=0;entryY=0.75;')
    edge('line-end', 'frame-end', 'Sí')
    edge('frame-end', 'next-line', 'No', ports='exitX=1;exitY=0.5;entryX=0;entryY=0.5;')
    edge('next-line', 'offer', points=[(1695, 2100), (1695, 1780), (1180, 1780), (1180, 1280)],
         ports='exitX=1;exitY=0.5;entryX=1;entryY=0.8;')
    edge('frame-end', 'done', 'Sí')
    edge('done', 'wait', points=[(790, 2410), (10, 2410), (10, 695)],
         ports='entryX=0;entryY=0.5;')

    node('parameters', 'PARÁMETROS DE ELABORACIÓN\nWIDTH = 720; HEIGHT = 720 (prueba)\n'
         'WIDTH ≥ 8 y múltiplo de 8; HEIGHT ≥ 1.\nConfiguración inválida: rechazar elaboración.\n'
         'B = WIDTH / 8 píxeles por franja.', 1250, 465, 420, 180, 'text')
    palette = [('0', 'Blanco', 'FFFFFF'), ('1', 'Amarillo', 'FFFF00'),
               ('2', 'Cian', '00FFFF'), ('3', 'Verde', '00FF00'),
               ('4', 'Magenta', 'FF00FF'), ('5', 'Rojo', 'FF0000'),
               ('6', 'Azul', '0000FF'), ('7', 'Negro', '000000')]
    node('palette-title', 'COLOR POR INTERVALO DE x\ni·B ≤ x < (i+1)·B',
         1250, 700, 420, 75, 'text')
    for index, (band, name, rgb) in enumerate(palette):
        node(f'color-{band}', f'{band}   {name}   RGB = {rgb}', 1250, 790 + index * 42,
             420, 42, 'process', 'rounded=0;fontSize=18;align=left;')
    node('markers', 'MARCAS DEL BYTE OFRECIDO\nL = (x = WIDTH−1) ∧ (componente = B)\n'
         'tx_line_last = tx_byte_valid ∧ L\n'
         'tx_frame_last = tx_line_last ∧ (y = HEIGHT−1)\n'
         'Con ready=0: conservar byte y marcas.', 1250, 1190, 420, 230, 'text')
    node('contract', 'CONTRATO TEMPORAL\nclk único; actualización en posedge.\n'
         'Solo BYTE_FIRE avanza el recorrido.\nDecisiones sobre el byte antes del flanco.\n'
         'Sin burbujas internas entre píxeles/líneas.\nframe_done: pulso tras último BYTE_FIRE.\n'
         'No aceptar inicio al entregar el último byte.\nstart_valid=1 permite repetir sin CPU.',
         1250, 1470, 420, 280, 'text')
    node('limits', 'FRONTERA DEL MÓDULO\nSalida: bytes RGB y marcas lógicas.\n'
         'Descriptor por línea, ECC/CRC, sincronismo,\nblanking y transporte: módulos externos.\n'
         'No fija fps, bitrate ni porches del LCD.\nSin RISC-V ni framebuffer.',
         1250, 2230, 420, 200, 'text')
    node('footer', 'DSI_TEST_PATTERN · PROPUESTA · 2026-11-09 | '
         'Flujo: pág. 1; datapath: págs. 2–3; FSM: pág. 4. Sin RTL. Contrato en flujo.md.',
         60, 2480, 1630, 35, 'text', 'fontSize=16;')

    add_datapath(doc)
    add_fsm(doc)
    doc.set('pages', str(len(doc.findall('diagram'))))
    E.indent(doc, space='  ')
    path = OUT / 'DSI_TEST_PATTERN.drawio'
    E.ElementTree(doc).write(path, encoding='utf-8', xml_declaration=True)
    print(path)


if __name__ == '__main__':
    generate()
