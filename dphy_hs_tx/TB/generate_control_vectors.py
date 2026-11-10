"""Fault-injection oracle for the UC: seeded combinations, including unused states."""
import random,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'docs'))
from verificar_fsm import Model
rng=random.Random(320);rows=[]
for state in range(32):
 for _ in range(128):
    flags=rng.randrange(64);cause=rng.randrange(7);bits=rng.randrange(512)
    x={key:bool(bits&(1<<i)) for i,key in enumerate(('last','valid','grant','ct','dt','ds','cs','abort','rst'))}
    keep=rng.randrange(4);x['keep']=keep
    m=Model();m.state=state;m.cause=cause
    m.p=(0,bool(flags&2)) if flags&1 else None
    m.a=(0,bool(flags&8)) if flags&4 else None
    m.time=0 if flags&16 else 7;m.post=0 if flags&32 else 7
    m.step(**x);o=m.outputs(rst=x['rst'],abort=x['abort'])
    expected=int(m.state)|(m.cause<<5)
    for i,k in enumerate(('clk_prepared','data_prepared','data_stopped','clk_stopped','local_stop','error','hs_data','hs_clock','toggle'),8):
        expected|=int(o[k])<<i
    inp=(bits<<18)|(keep<<16)
    rows.append(f'{state:02x} {cause:x} {flags:02x} {inp:07x} {expected:05x}\n')
Path(sys.argv[1]).write_text(''.join(rows))
print('Generated 4096 seeded UC fault-injection combinations')
