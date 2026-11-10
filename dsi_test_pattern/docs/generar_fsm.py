"""FSM de dos estados; se añade al editable único junto a flujo y datapath."""
from generar_datapath import Page


def add_fsm(doc):
    p = Page(doc, 'fsm-control', 'FSM',
             'DSI_TEST_PATTERN · FSM · UNIDAD DE CONTROL',
             'STATE [1] en ↑clk: IDLE=0, STREAM=1. Salidas combinacionales con valores por defecto.\n'
             'Las flechas normales presuponen rst=0; reset síncrono tiene prioridad desde cualquier estado.',
             height=2400)
    p.root.find("mxCell[@id='footer']").set('value',
        'DSI_TEST_PATTERN · FSM PROPUESTA · 2026-11-09 | '
        'Sin RTL. Contrato, tablas y comprobaciones en fsm.md.')
    p.node('entry', '', 150, 310, 24, 24, 'ellipse;fillColor=#344563;')
    p.node('idle', 'IDLE · 0\n______________________\nstart_ready = !rst\ntx_byte_valid = 0\nbusy = 0\n'
           'Aceptar inicio → INIT', 250, 280, 470, 320, 'ellipse;fontSize=22;')
    p.node('stream', 'STREAM · 1\n______________________\nstart_ready = 0\ntx_byte_valid = !rst\nbusy = 1\n'
           'Entregar RGB; avanzar solo con BYTE_FIRE', 1050, 280, 500, 320, 'ellipse;fontSize=22;')
    p.wire('entry', 'idle', 'Reset', ports='exitX=1;exitY=0.5;entryX=0;entryY=0.2;')
    p.wire('idle', 'stream', 'START_FIRE / INIT=1',
           ports='exitX=1;exitY=0.3;entryX=0;entryY=0.3;')
    p.wire('stream', 'idle', 'FINISH / R_DONE ← 1',
           points=[(1300, 830), (485, 830)],
           ports='exitX=0.5;exitY=1;entryX=0.5;entryY=1;')
    p.wire('idle', 'idle',
           points=[(180, 710), (70, 710), (70, 470)],
           ports='exitX=0.2;exitY=1;entryX=0;entryY=0.6;')
    p.text('idle-loop-label', '!START_FIRE', 100, 735, 300, 45, 18)
    p.wire('stream', 'stream', '!FINISH',
           points=[(1690, 450), (1690, 710), (1500, 710)],
           ports='exitX=1;exitY=0.5;entryX=0.9;entryY=1;')
    p.node('reset', 'RESET GLOBAL · rst=1\n'
           'Enmascarar start_ready, tx_byte_valid, byte y marcas inmediatamente.\n'
           'En ↑clk: STATE←IDLE; R_DONE←0; X←0; Y←0; C←R.\n'
           'Sin INIT/STEP/FINISH; reset gana incluso sobre la última entrega.',
           100, 950, 1600, 150)
    p.text('guards', 'START_FIRE = start_valid & start_ready\n'
           'BYTE_FIRE = tx_byte_valid & tx_byte_ready\n'
           'FINISH = BYTE_FIRE & IS_B & X_END & Y_END\n'
           'IS_B / X_END / Y_END proceden de CC / CX / CY del datapath.',
           100, 1150, 1600, 150)

    rows = [
        ('Origen / condición (rst=0)', 'Destino', 'Operación antes del flanco'),
        ('IDLE; !start_valid', 'IDLE', 'Sin cargas; conservar X/Y/C'),
        ('IDLE; start_valid', 'STREAM', 'INIT=1; X=0, Y=0, C=R'),
        ('STREAM; !tx_byte_ready', 'STREAM', 'Sin cargas; conservar byte y marcas'),
        ('STREAM; BYTE_FIRE & !IS_B', 'STREAM', 'STEP_COMP=1; R→G o G→B'),
        ('STREAM; BYTE_FIRE & IS_B & !X_END', 'STREAM', 'STEP_PIXEL=1; X=X+1, C=R'),
        ('STREAM; BYTE_FIRE & IS_B & X_END & !Y_END', 'STREAM', 'STEP_LINE=1; X=0, Y=Y+1, C=R'),
        ('STREAM; FINISH', 'IDLE', 'Sin cargas X/Y/C; R_DONE←1')
    ]
    widths = [830, 190, 580]
    for i, row in enumerate(rows):
        x = 100
        for j, (value, width) in enumerate(zip(row, widths)):
            p.node(f'table-{i}-{j}', value, x, 1350+i*65, width, 65,
                   'align=left;fontSize=18;'+('fontStyle=1;' if i == 0 else ''))
            x += width
    p.node('state-reg', 'STATE [1] · ↑clk\nrst → IDLE\n'
           'IDLE + START_FIRE → STREAM\nSTREAM + FINISH → IDLE\nResto: conservar',
           100, 1940, 680, 170)
    p.node('done-reg', 'R_DONE [1] · ↑clk\nrst → 0; resto D=FINISH (cada ciclo)\n'
           'frame_done = R_DONE\nSe limpia también al aceptar el siguiente cuadro',
           960, 1940, 740, 170)
    p.text('counts', 'MEMORIA: UC=STATE[1]+R_DONE[1]=2 bits; datapath=22 bits (720×720); total lógico=24 bits.\n'
           'No hay estado DONE, registro busy ni FSM por componente. Con un bit no quedan códigos binarios sin usar.\n'
           'El primer R aparece tras START_FIRE. El último B libera STREAM; no se acepta inicio en ese mismo flanco.\n'
           'start_valid mantenido alto repite cuadros; frame_done confirma solo entrega local de bytes.',
           100, 2160, 1600, 145)
