"""Drive the RTL through the executable specification, using public transactions."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'docs'))
from verificar_fsm import Model, S, RX, stimulus

out=Path(sys.argv[1]);out.parent.mkdir(parents=True,exist_ok=True)
rows=[]
m=Model()

def emit(**x):
    inp=x.get('data',0)|(x.get('keep',3)<<16)
    for bit,key in enumerate(('last','valid','grant','ct','dt','ds','cs','abort','rst'),18):
        inp|=int(bool(x.get(key)))<<bit
    m.step(**x)
    o=m.outputs(rst=x.get('rst',False),abort=x.get('abort',False))
    kind=o['word_sel']
    frame=0 if kind==0 else 0xb8b8 if kind==1 else m.a_data
    if kind==3:
        frame=((0xff if not (m.a_data&0x8000) else 0)<<8)|(0xff if not (m.a_data&0x80) else 0)
    exp=frame|(kind<<16)
    for bit,key in enumerate(('clk_prepared','data_prepared','data_stopped','clk_stopped','local_stop','error','hs_data','hs_clock','toggle'),18):
        exp|=int(bool(o[key]))<<bit
    exp|=m.cause<<27
    lc=ld=3
    if not (x.get('rst') or x.get('abort')):
        s=m.state
        if s==S.CLK_LPX:lc=1
        elif s==S.CLK_PREP or o['hs_clock']:lc=0
        if s==S.DATA_LPX:ld=1
        elif s==S.DATA_PREP or o['hs_data']:ld=0
    exp|=ld<<30|ld<<32|lc<<34
    rows.append(f'{inp:07x} {exp:09x}\n')


def walk(target=None,n=3,delay=3,stop_delay=0):
    emit(rst=True)
    accepted=waits=cwait=0
    for tick in range(15000):
        s=m.state
        if target is not None and s==target:return accepted
        x=stimulus(m)
        if s==S.WAIT_WORD:
            waits+=1;x['valid']=waits>delay
        elif s in {S.SYNC_OPEN,S.STREAM_OPEN}:x['valid']=True
        if s==S.WAIT_CLK_STOP:
            cwait+=1;x['ct']=cwait>stop_delay
        if x.get('valid'):
            x.update(data=(accepted*971+0x8031)&65535,last=accepted==n-1)
            accepted+=1
        emit(**x)
        if s==S.RETURN and m.state==S.IDLE:return accepted
    raise AssertionError('walk watchdog')

for n in (1,2,3,4,1083,2048):walk(n=n)
walk(n=3,delay=13,stop_delay=12)
for state in S:
    for reset in (True,False):
        if state in {S.ABORT_EXIT,S.HALTED}:
            walk(S.WAIT_WORD);emit(abort=True)
            if state==S.HALTED:
                for _ in range(4):emit(abort=True)
        else:walk(state,n=1 if state==S.SYNC_CLOSED else 3)
        assert m.state==state
        emit(**({'rst':True,'abort':True} if reset else {'abort':True}))
        for _ in range(6):emit(abort=not reset)
        if not reset:assert m.state==S.HALTED and m.cause==0
for state,changes,code in (
 (S.WAIT_WORD,dict(valid=True,keep=1),1),
 (S.WAIT_WORD,dict(valid=True,keep=0),1),
 (S.WAIT_WORD,dict(valid=True,keep=2),1),
 (S.SYNC_OPEN,dict(valid=False),2),
 (S.STREAM_OPEN,dict(valid=False),2),
 (S.STREAM_OPEN,dict(valid=True,grant=False),3),
 (S.DRAIN_PENDING,dict(valid=True),3),
 (S.FINAL,dict(dt=False),3),
 (S.DATA_PREP,dict(ct=True),3),
 (S.DATA_ZERO,dict(dt=True),3)):
    walk(state);x=stimulus(m);x.update(changes);emit(**x)
    assert m.cause==code
    for _ in range(6):emit(abort=True,valid=True,keep=0)
    assert m.cause==code and m.state==S.HALTED
out.write_text(''.join(rows))
print(f'Generated {len(rows)} public-interface cycles from specification')
