"""Modelo de especificación de la FSM; no es RTL ni simulación eléctrica."""
from collections import Counter
from enum import IntEnum


class S(IntEnum):
    BOOT=0; INIT=1; IDLE=2; CLK_LPX=3; CLK_PREP=4; CLK_ZERO=5; CLK_PRE=6
    WAIT_DATA=7; DATA_LPX=8; DATA_PREP=9; DATA_ZERO=10; WAIT_WORD=11
    SYNC_OPEN=12; SYNC_CLOSED=13; STREAM_OPEN=14; DRAIN_PENDING=15; FINAL=16
    DATA_TRAIL=17; DATA_EXIT=18; WAIT_CLK_STOP=19; CLK_TRAIL=20; CLK_EXIT=21
    RETURN=22; ABORT_EXIT=23; HALTED=24


TIMES = {0:4000, 1:2, 2:2, 3:10, 4:1, 5:3, 6:5, 7:3, 8:4, 9:3}
TIMED = {
    S.INIT:(S.IDLE,None), S.CLK_LPX:(S.CLK_PREP,2),
    S.CLK_PREP:(S.CLK_ZERO,3), S.CLK_ZERO:(S.CLK_PRE,4),
    S.CLK_PRE:(S.WAIT_DATA,None), S.DATA_LPX:(S.DATA_PREP,5),
    S.DATA_PREP:(S.DATA_ZERO,6), S.DATA_ZERO:(S.WAIT_WORD,None),
    S.DATA_TRAIL:(S.DATA_EXIT,8), S.DATA_EXIT:(S.WAIT_CLK_STOP,None),
    S.CLK_TRAIL:(S.CLK_EXIT,8), S.CLK_EXIT:(S.RETURN,None),
    S.ABORT_EXIT:(S.HALTED,None),
}
RX = {S.WAIT_WORD,S.SYNC_OPEN,S.STREAM_OPEN}
PAYLOAD = {S.STREAM_OPEN,S.DRAIN_PENDING,S.FINAL}


class Model:
    def __init__(self):
        self.state=S.BOOT; self.cause=0; self.time=0; self.post=0
        self.p=None; self.a=None; self.a_data=0

    def outputs(self, rst=False, abort=False):
        s=self.state
        normal=not (rst or abort)
        return dict(
            clk_prepared=normal and 7<=s<=19,
            data_prepared=normal and 11<=s<=16,
            data_stopped=normal and 19<=s<=22,
            clk_stopped=normal and s==S.RETURN,
            local_stop=(normal and s in {S.IDLE,S.RETURN}) or (not rst and s==S.HALTED),
            hs_clock=normal and s in set(range(5,21)),
            toggle=normal and s in set(range(6,20)),
            hs_data=normal and s in set(range(10,18)),
            word_sel=1 if s in {S.SYNC_OPEN,S.SYNC_CLOSED} else
                     2 if s in PAYLOAD else 3 if s==S.DATA_TRAIL else 0,
            error=self.cause!=0)

    def local_fault(self, x):
        s=self.state; v=x.get('valid',False); g=x.get('grant',False)
        cs=x.get('cs',False); ds=x.get('ds',False)
        dt=x.get('dt',False); ct=x.get('ct',False)
        if s not in set(S): return 5
        if x.get('bad_selector'): return 6
        if s==S.WAIT_WORD and (self.p is not None or self.a is not None): return 4
        if s in {S.SYNC_OPEN,S.SYNC_CLOSED}:
            if self.p is None or self.a is not None: return 4
            if self.p[1] != (s==S.SYNC_CLOSED): return 4
        if s in {S.STREAM_OPEN,S.DRAIN_PENDING}:
            if self.p is None or self.a is None or self.a[1]: return 4
            if self.p[1] != (s==S.DRAIN_PENDING): return 4
        if s==S.FINAL and (self.a is None or not self.a[1] or self.p is not None): return 4
        if s in RX and v and x.get('keep',3)!=3: return 1
        if v and (s not in RX or not g): return 3
        if ct and s not in {S.WAIT_CLK_STOP,S.CLK_TRAIL,S.CLK_EXIT,S.RETURN}: return 3
        if dt and s not in {S.SYNC_CLOSED,S.DRAIN_PENDING,S.FINAL,S.DATA_TRAIL,S.DATA_EXIT,S.WAIT_CLK_STOP,S.RETURN}: return 3
        if ds and s not in set(range(7,20))|{S.RETURN}: return 3
        if cs and s not in set(range(2,20))|{S.RETURN}: return 3
        if s in set(range(3,19)) and not cs: return 3
        if s in {S.DATA_LPX,S.DATA_PREP,S.DATA_ZERO,S.WAIT_WORD,S.SYNC_OPEN,S.STREAM_OPEN} and not ds: return 3
        if g and s not in set(range(10,18))|{S.RETURN}: return 3
        if s in {S.SYNC_OPEN,S.STREAM_OPEN} and not g: return 3
        if s==S.FINAL and not dt: return 3
        if s in {S.SYNC_OPEN,S.STREAM_OPEN} and not v: return 2
        return 0

    def step(self, **x):
        if x.get('rst'):
            self.__init__(); return dict(cap=False,move=False,retire=False)
        s=self.state; nxt=s; load=None; pl=False; cap=move=retire=clear=False
        ps=s in {S.DATA_EXIT,S.WAIT_CLK_STOP}
        fault=0
        if s in {S.ABORT_EXIT,S.HALTED}:
            if s==S.ABORT_EXIT and self.time==0: nxt=S.HALTED
        elif x.get('abort'):
            nxt=S.ABORT_EXIT; load=8; clear=True
        elif (fault:=self.local_fault(x)):
            nxt=S.ABORT_EXIT; load=8; clear=True
            if not self.cause: self.cause=fault
        elif s==S.BOOT: nxt=S.INIT; load=0; clear=True
        elif s in TIMED:
            if self.time==0:
                nxt,load=TIMED[s]
                pl=s==S.DATA_TRAIL
        elif s==S.IDLE and x.get('cs'): nxt=S.CLK_LPX; load=1; clear=True
        elif s==S.WAIT_DATA and x.get('ds'): nxt=S.DATA_LPX; load=1
        elif s==S.WAIT_WORD and x.get('valid'):
            cap=True; nxt=S.SYNC_CLOSED if x.get('last') else S.SYNC_OPEN
        elif s in {S.SYNC_OPEN,S.STREAM_OPEN}:
            cap=move=True; retire=s==S.STREAM_OPEN
            nxt=S.DRAIN_PENDING if x.get('last') else S.STREAM_OPEN
        elif s in {S.SYNC_CLOSED,S.DRAIN_PENDING}:
            move=True; retire=s==S.DRAIN_PENDING; nxt=S.FINAL
        elif s==S.FINAL: retire=True; nxt=S.DATA_TRAIL; load=7
        elif s==S.WAIT_CLK_STOP and x.get('ct') and self.post==0:
            nxt=S.CLK_TRAIL; load=9
        elif s==S.RETURN and not any(x.get(k) for k in ('cs','ds','dt','ct','grant')):
            nxt=S.IDLE
        old_p=self.p
        if clear: self.p=self.a=None
        else:
            if move:
                assert old_p is not None
                self.a=old_p; self.a_data=old_p[0]
            elif retire: self.a=None
            if cap: self.p=(x.get('data',0),x.get('last',False))
            elif move: self.p=None
        if load is not None: self.time=TIMES[load]-1
        elif s in TIMED and self.time>0: self.time-=1
        if pl: self.post=8
        elif ps and self.post>0: self.post-=1
        self.state=nxt
        return dict(cap=cap,move=move,retire=retire,fault=fault)


def stimulus(m):
    s=m.state
    return dict(cs=2<=s<=19,ds=7<=s<=14 and s!=S.SYNC_CLOSED,
                dt=s in {S.SYNC_CLOSED,S.DRAIN_PENDING,S.FINAL,S.DATA_TRAIL,S.DATA_EXIT,S.WAIT_CLK_STOP},
                ct=s in {S.WAIT_CLK_STOP,S.CLK_TRAIL,S.CLK_EXIT},
                grant=s in RX)


def transaction(length, delay=3, stop_delay=0):
    m=Model(); trace=[]; output=[]; snapshots={}; accepted=0; waits=0; cwaits=0
    source=[(i*971+0x8031)&65535 for i in range(length)]
    for tick in range(16000):
        s=m.state; trace.append(s)
        snapshots.setdefault(s,(m.p,m.a,m.time,m.post))
        if s in PAYLOAD:
            assert m.a is not None
            output.append(m.a[0])
        x=stimulus(m)
        if s==S.WAIT_WORD:
            waits+=1; x['valid']=waits>delay
        elif s in {S.SYNC_OPEN,S.STREAM_OPEN}: x['valid']=True
        if s==S.WAIT_CLK_STOP:
            cwaits+=1; x['ct']=cwaits>stop_delay
        if x.get('valid'):
            x.update(data=source[accepted],last=accepted==length-1)
        event=m.step(**x)
        accepted+=event['cap']
        assert not m.cause,(tick,s,m.cause)
        if s==S.RETURN and m.state==S.IDLE: break
    else: raise AssertionError('watchdog')
    assert output==source
    counts=Counter(trace)
    for state,n in ((S.INIT,4000),(S.CLK_LPX,2),(S.CLK_PREP,2),(S.CLK_ZERO,10),
                    (S.CLK_PRE,1),(S.DATA_LPX,2),(S.DATA_PREP,3),(S.DATA_ZERO,5),
                    (S.DATA_TRAIL,3),(S.DATA_EXIT,4),(S.CLK_TRAIL,3),(S.CLK_EXIT,4)):
        assert counts[state]==n,(state,counts[state])
    start=trace.index(S.DATA_EXIT); stop=trace.index(S.CLK_TRAIL)
    assert stop-start>=9
    sync=min(i for i,s in enumerate(trace) if s in {S.SYNC_OPEN,S.SYNC_CLOSED})
    assert trace[sync+1:sync+1+length] == ([S.FINAL] if length==1 else
            [S.DRAIN_PENDING,S.FINAL] if length==2 else
            [S.STREAM_OPEN]*(length-2)+[S.DRAIN_PENDING,S.FINAL])
    assert trace[sync+length+1]==S.DATA_TRAIL
    return snapshots


if __name__=='__main__':
    samples={}
    for n in (1,2,3,4,1083,2048): samples.update(transaction(n))
    transaction(3,delay=13,stop_delay=12)
    # Cada código 0…24: reset y aborto, incluso durante la recuperación.
    for state in S:
        m=Model(); m.state=state
        m.step(rst=True,abort=True,valid=True,keep=0)
        assert m.state==S.BOOT and m.cause==0 and m.p is None and m.a is None
        m=Model(); m.state=state; m.cause=1
        m.step(abort=True)
        if state not in {S.ABORT_EXIT,S.HALTED}: assert m.state==S.ABORT_EXIT
        for _ in range(6): m.step(abort=True)
        assert m.state==S.HALTED and m.cause==1
        assert m.outputs(abort=True)['local_stop']
        assert not m.outputs(abort=True)['hs_clock']
    # Aborto externo sin causa local; no convertirlo en éxito o autorreintento.
    m=Model(); m.state=S.WAIT_WORD; m.step(abort=True)
    for _ in range(8): m.step(abort=True)
    assert m.state==S.HALTED and m.cause==0
    for _ in range(3): m.step()
    assert m.state==S.HALTED
    cases=0
    for state,changes,cause in (
        (S.WAIT_WORD,dict(valid=True,keep=1),1),
        (S.WAIT_WORD,dict(valid=True,keep=0),1),
        (S.WAIT_WORD,dict(valid=True,keep=2),1),
        (S.SYNC_OPEN,dict(valid=False),2),
        (S.STREAM_OPEN,dict(valid=False),2),
        (S.STREAM_OPEN,dict(valid=True,grant=False),3),
        (S.DRAIN_PENDING,dict(valid=True),3),
        (S.FINAL,dict(dt=False),3),
        (S.DATA_PREP,dict(ct=True),3),
        (S.DATA_ZERO,dict(dt=True),3),
        (S.WAIT_WORD,dict(bad_selector=True),6)):
        m=Model();m.state=state
        m.p,m.a,m.time,m.post=samples[state]
        x=stimulus(m);x.update(changes);m.step(**x)
        assert m.state==S.ABORT_EXIT and m.cause==cause,(state,m.cause,cause)
        cases+=1
    for state in (S.SYNC_OPEN,S.SYNC_CLOSED,S.STREAM_OPEN,S.DRAIN_PENDING,S.FINAL):
        m=Model();m.state=state;m.step(**stimulus(m))
        assert m.cause==4
        cases+=1
    for code in range(25,32):
        m=Model();m.state=code;m.step();assert m.cause==5
    for state in S:
        m=Model();m.state=state
        o=m.outputs()
        assert not o['toggle'] or o['hs_clock']
        assert not o['hs_data'] or o['hs_clock']
        for reset,abort in ((True,False),(False,True)):
            o=m.outputs(rst=reset,abort=abort)
            assert not any(o[k] for k in ('hs_clock','toggle','hs_data','clk_prepared','data_prepared','data_stopped','clk_stopped'))
    assert set(samples)==set(S)-{S.ABORT_EXIT,S.HALTED}
    print(f'PASS: 7 recorridos; 25 resets y abortos; {cases} fallos; 7 codigos invalidos')
