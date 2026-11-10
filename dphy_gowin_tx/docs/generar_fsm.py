"""FSM UC_SUP: se añade al mismo editable que flujo y datapath."""
from diagramas import Page

def add_fsm(doc):
    p=Page(doc,'fsm-supervisor','08 · FSM · Supervisor','DPHY_GOWIN_TX · FSM 1/2 · SUPERVISOR UC_SUP',
           'STATE [3] en ↑ref_clk (40 MHz). Entradas evaluadas antes del flanco. Salidas combinacionales con valores por defecto. Sin next_state ni ACTION.',width=1900,height=2100)
    def state(ident,text,x,y):
        p.node(ident,text,x,y,420,300,'ellipse;spacing=15;fontSize=20;')
    state('reset','RESET · 000\n____________________\nBOOT_ALLOWED=1\nRELEASE_SAFE=0\nCon rst: limpiar memoria UC\nINHIBIT permanece a 1',80,250)
    state('wait','WAIT_LOCK · 001\n____________________\nBOOT_ALLOWED=1\nRELEASE_SAFE=0\nEsperar B=1\nSin timeout de arranque',740,250)
    state('release','RELEASE · 011\n____________________\nBOOT_ALLOWED=0\nRELEASE_SAFE=G_RELEASE\nDuración: un ciclo REF\nRUN_STARTED ya está a 1',1400,250)
    state('ready','WAIT_READY · 010\n____________________\nRELEASE_SAFE=0\nEsperar READY_REF=1\nRUN_B llena R_CTRL\nSAFE se calcula en byte_clk',1400,1050)
    state('active','ACTIVE · 110\n____________________\nRELEASE_SAFE=0\nCaptura continua con LD_CMD\nSin estados LPDT/HS propios\nVigilar F y READY_REF',740,1050)
    state('blocked','BLOCKED · 111\n____________________\nUC_BLOCK=1\nRELEASE_SAFE=0\nInvalidar tubería / HS_OE=0\nSolo rst permite salir',80,1050)
    p.node('entry','',80,190,22,22,'ellipse;fillColor=#344563;')
    p.wire('entry','reset','rst',ports='exitX=0.5;exitY=1;entryX=0.1;entryY=0;')
    p.wire('reset','wait','1 (rst=0)')
    p.wire('wait','release','B / RUN_STARTED←1')
    p.wire('release','ready','1',ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
    p.wire('ready','active','READY_REF',ports='exitX=0;exitY=0.5;entryX=1;entryY=0.5;')
    p.wire('wait','wait','!B',[(950,640),(680,640),(680,490)],ports='exitX=0.5;exitY=1;entryX=0;entryY=0.8;')
    p.wire('ready','ready','!READY_REF',[(1780,950),(1780,1200)],ports='exitX=0.9;exitY=0;entryX=1;entryY=0.5;')
    p.wire('active','active','1 si !F',[(1034,1440),(1250,1440),(1250,1320)],ports='exitX=0.7;exitY=1;entryX=1;entryY=0.9;')
    p.wire('blocked','blocked','!rst',[(290,1460),(40,1460),(40,1200)],ports='exitX=0.5;exitY=1;entryX=0;entryY=0.5;')
    p.wire('active','blocked','F (prioridad global)',ports='exitX=0;exitY=0.5;entryX=1;entryY=0.5;')
    p.reg('global','PRIORIDADES GLOBALES · APLICAN A TODAS LAS FLECHAS\n1. rst=1 → RESET; limpiar RUN_STARTED / ABORT_SEEN / CLOCK_FAULT.\n2. STATE inválido (100/101) → BLOCKED. UC_BLOCK inhibe sin esperar al salto.\n3. F=1 → BLOCKED desde cualquier estado válido, salvo reset activo.\n4. Si no aplica 1–3, seguir recorrido y bucles dibujados.\nLa inhibición asíncrona actúa antes que la transición de estado.',80,710,1180,230)
    p.table('guards',[
      ('Símbolo','Definición exacta (1 bit)'),
      ('B','PROFILE_OK & LOCK_SYNC & !ABORT_REF & !EV_REF'),
      ('EV_RAW / EV_REF','ABORT_SEEN | CLOCK_FAULT / su copia sincronizada con dos FF REF'),
      ('READY_REF','Dos FF REF de (RUN_B & V_P & !rst_byte); no cruza el bus de tramas'),
      ('F','EV_REF | (RUN_STARTED & (!LOCK_SYNC | ABORT_REF | !PROFILE_OK)) | (STATE=ACTIVE & !READY_REF)'),
      ('G_RELEASE','!rst & PROFILE_OK & LOCK_SYNC & LOCK_RAW & !phy_abort & !EV_RAW')
    ],80,1550,[260,1540],60,18)
    p.text('gray','Codificación Gray del recorrido normal: 000→001→011→010→110. Evita atravesar códigos inválidos al avanzar entre fases normales.\nLas flechas normales presuponen !rst, STATE válido y !F. BLOCKED no sale por clear_error, recuperación de LOCK o retirada de phy_abort.',80,1940,1740,70,16)

    p=Page(doc,'fsm-controles','09 · FSM · Controles y eventos','DPHY_GOWIN_TX · FSM 2/2 · CONTROLES, MEMORIA Y CRUCES',
           'UC: STATE [3] + RUN_STARTED [1] + ABORT_SEEN [1] + CLOCK_FAULT [1] = 6 bits. BOOT_ALLOWED es decodificación, no otro registro.',height=2300)
    p.table('outputs',[
      ('STATE','BOOT_ALLOWED','UC_BLOCK','RELEASE_SAFE','Acción / condición de salida'),
      ('RESET 000','1','0','0','Con rst limpiar memoria. !rst & !F → WAIT_LOCK.'),
      ('WAIT_LOCK 001','1','0','0','B & !F: RUN_STARTED←1 y STATE←RELEASE en ese ↑REF.'),
      ('RELEASE 011','0','0','G_RELEASE','Limpiar R_INHIBIT solo si G_RELEASE=1. !F → WAIT_READY.'),
      ('WAIT_READY 010','0','0','0','READY_REF & !F → ACTIVE. Captura ya funciona cuando RUN_B=1.'),
      ('ACTIVE 110','0','0','0','Mantener operación; cualquier F → BLOCKED.'),
      ('BLOCKED 111','0','1','0','Mantener bloqueo hasta rst, aun con LOCK y phy_abort recuperados.'),
      ('Inválido 100/101','0','1','0','Bloquear inmediatamente; en siguiente ↑REF ir a BLOCKED.')
    ],50,200,[260,200,170,220,850],70,18)
    p.text('memory','CAPTURA PERSISTENTE DE EVENTOS · rst TIENE PRIORIDAD',50,850,1700,40,22)
    p.reg('arm','RUN_STARTED [1]\n↑ref_clk\nrst → 0\nBOOT_FIRE → 1\nResto: conservar',50,960,400,160)
    p.reg('abort','ABORT_SEEN [1]\nSet asíncrono:\nRUN_STARTED & phy_abort\nrst → 0; resto conservar\nNo se limpia al retirar phy_abort',680,960,440,160)
    p.reg('clock','CLOCK_FAULT [1]\nSet asíncrono:\nRUN_STARTED & !LOCK_RAW\nrst → 0; resto conservar\nSalida clock_fault → G_ERR',1320,960,430,160)
    p.text('fire','BOOT_FIRE = !rst & (STATE=WAIT_LOCK) & B & !F\nEvento de aceptación anterior al ↑REF. Estado RELEASE y RUN_STARTED=1 aparecen juntos después del flanco.\nEn RELEASE, un evento breve queda en EV_RAW e impide volver a limpiar INHIBIT, aunque el nivel de entrada ya se haya recuperado.',50,1180,1700,120)
    p.reg('inhibit','R_INHIBIT [1] · MEMORIA DE SEGURIDAD\nSET async = rst | phy_abort | !LOCK_RAW | UC_BLOCK | EV_RAW\nCLEAR = RELEASE_SAFE; SET > CLEAR > conservar\nNo depende de FCLK. No borra una causa retenida.',50,1380,1700,150)
    p.text('cdc','CRUCES HACIA REF_CLK · SOLO SEÑALES DE UN BIT',50,1600,1700,40,22)
    p.table('sync',[
      ('Origen','Sincronizador / destino','Uso'),
      ('LOCK_RAW','R_LOCK0/R_LOCK1 en REF (existentes)','LOCK_SYNC → B/F; no sustituye la inhibición raw.'),
      ('phy_abort','R_ABORT0/R_ABORT1 en REF (2 FF)','ABORT_REF → B/F; startup puede esperar al reset del árbitro.'),
      ('ABORT_SEEN | CLOCK_FAULT','R_EV0/R_EV1 en REF (2 FF)','EV_REF → F; EV_RAW inhibe directamente sin esperar CDC.'),
      ('RUN_B & V_P & !rst_byte','R_READY0/R_READY1 en REF (2 FF)','READY_REF → transición WAIT_READY/ACTIVE; solo observación.')
    ],50,1690,[510,550,640],65,18)
    p.text('safe','SAFE = RUN_B & V_P & !rst_byte & !phy_abort & LOCK_RAW & !INHIBIT & !UC_BLOCK & !EV_RAW\npll_ready = RUN_B & !rst_byte & LOCK_RAW & !INHIBIT & !UC_BLOCK & !EV_RAW. ACK_OUT=ACK_P & {4{SAFE}}; stop_ready=C_STOP.\nRST_PIPE y LD_CMD conservan las ecuaciones del datapath. ACTIVE no se añade como permiso: hacerlo alteraría el retardo L.',50,2080,1700,110)
