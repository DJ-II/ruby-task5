import math
import argparse
import subprocess
from pathlib import Path
import hashlib
import numpy as np
from scipy.signal import butter, sosfilt

SR = 32000
DURATION = 8.4
TOTAL = int(SR * DURATION)
OUT = Path(__file__).resolve().parents[1] / 'public' / 'audio'
OUT.mkdir(parents=True, exist_ok=True)
PITCHES = {'major':[0,2,4,5,7,9,11], 'minor':[0,2,3,5,7,8,10], 'dorian':[0,2,3,5,7,9,10]}
PROGRESSION = {'major':[[0,4,5,3],[0,3,4,0],[5,3,0,4],[0,5,3,4],[0,2,5,4]],'minor':[[0,5,2,6],[0,6,5,4],[0,3,6,5],[0,5,6,3],[0,2,5,6]],'dorian':[[0,3,4,3],[0,4,3,6],[0,6,3,4],[0,2,5,3]]}
SETUPS={
'action':dict(tempo=(125,162),mode=['minor','minor','dorian'],lead=['brass','synth','bell','epiano'],chord=['strings','pad','brass','synth'],arp=['pluck','synth','bell'],bass=['bass','synthbass'], drums='driving'),
'city':dict(tempo=(95,128),mode=['dorian','major','major'],lead=['epiano','synth','pluck','bell'],chord=['epiano','pad','strings'],arp=['pluck','bell','epiano'],bass=['synthbass','bass'],drums='groovy'),
'mystery':dict(tempo=(78,112),mode=['minor','minor','dorian'],lead=['bell','flute','epiano','strings'],chord=['pad','strings','epiano'],arp=['bell','pluck','epiano'],bass=['bass'],drums='sparse'),
'nature':dict(tempo=(90,122),mode=['major','major','dorian'],lead=['flute','pluck','bell','guitar'],chord=['guitar','pad','strings','epiano'],arp=['pluck','guitar','bell'],bass=['bass'],drums='organic'),
'people':dict(tempo=(87,119),mode=['major','minor','major'],lead=['piano','epiano','guitar','strings'],chord=['piano','epiano','strings','guitar'],arp=['epiano','guitar','pluck'],bass=['bass','synthbass'],drums='soft'),
}

def midi_to_hz(note):
    return 440.0 * (2.0 ** ((note-69)/12))


def tone(freq, seconds, kind, rng):
    n=max(1,int(seconds*SR))
    t=np.arange(n,dtype=np.float32)/SR
    ph=(2*np.pi*freq*t).astype(np.float32)
    if kind in ('piano','epiano'):
        x=np.zeros(n,dtype=np.float32)
        for h,a in enumerate([0.85,0.34,0.22,0.13,0.08,0.05,0.025],1):
            x+=a*np.sin(ph*h+0.11*h)*np.exp(-t*(0.75+0.34*h))
        if kind=='epiano':
            x=.68*x+.32*np.sin(ph+1.8*np.sin(2.0*ph))*np.exp(-t*1.2)
        env=np.minimum(1,t/0.009)*np.minimum(1,(seconds-t)/0.11)
    elif kind in ('guitar','pluck'):
        x=np.zeros(n,dtype=np.float32)
        for h in range(1,11):
            weight=(1/h)**1.4
            x+=weight*np.sin(ph*h+0.02*h)*np.exp(-t*(0.60+0.45*h))
        env=np.minimum(1,t/0.003)*np.minimum(1,(seconds-t)/0.065)
        if kind=='guitar':
            x*=np.exp(-t*0.5)
    elif kind=='bell':
        x=np.zeros(n,dtype=np.float32)
        for h,a in [(1,0.9),(2.002,0.28),(2.75,0.20),(4.05,0.13),(5.38,0.08)]:
            x+=a*np.sin(ph*h)*np.exp(-t*(0.5+0.36*h))
        env=np.minimum(1,t/0.004)*np.minimum(1,(seconds-t)/0.09)
    elif kind=='pad':
        p=ph+0.09*np.sin(2*np.pi*5.2*t)
        x=(.58*np.sin(p)+.23*np.sin(p*0.997)+.20*np.sin(p*1.003)+.10*np.sin(2*p)+.055*np.sin(3*p))
        env=np.minimum(1,t/0.28)*np.minimum(1,(seconds-t)/0.26)
    elif kind=='strings':
        p=ph+0.05*np.sin(2*np.pi*5.1*t)
        x=np.zeros(n,dtype=np.float32)
        for h in range(1,9):
            x+=0.83/(h**1.25)*np.sin(p*h + h*0.06)
        x*=.84 + .16*np.sin(2*np.pi*4.4*t)**2
        env=np.minimum(1,t/0.16)*np.minimum(1,(seconds-t)/0.20)
    elif kind=='brass':
        x=np.zeros(n,dtype=np.float32)
        for h in range(1,9):
            x+=.9/(h**1.15)*np.sin(ph*h+0.03*h)
        env=np.minimum(1,t/0.035)*np.minimum(1,(seconds-t)/0.13)
        x*=.78+.22*np.minimum(1,t/.15)
    elif kind in ('synth','synthbass'):
        x=np.zeros(n,dtype=np.float32)
        for h in range(1,8):
            x+=(0.65/h)*np.sin(ph*h)
        x+=.13*np.sin(ph*1.007)
        env=np.minimum(1,t/.012)*np.minimum(1,(seconds-t)/.10)
        if kind=='synthbass':
            x=.65*np.sin(ph)+.16*np.sin(2*ph)+.18*np.sin(3*ph)
            env*=np.exp(-t*.48)
    elif kind=='bass':
        x=.95*np.sin(ph)+.25*np.sin(2*ph)+.09*np.sin(3*ph)
        env=np.minimum(1,t/.007)*np.minimum(1,(seconds-t)/.08)*np.exp(-t*.24)
    elif kind=='flute':
        p=ph + .07*np.sin(2*np.pi*5.2*t)
        x=np.sin(p)+.13*np.sin(2*p)+.04*np.sin(3*p)
        env=np.minimum(1,t/.07)*np.minimum(1,(seconds-t)/.16)
    else:
        raise ValueError(kind)
    x=x*env
    return x.astype(np.float32)


def drum(kind, rng):
    seconds={'kick':.32,'snare':.26,'hat':.115,'openhat':.36,'rim':.10,'tom':.27,'crash':.85,'clap':.24,'shaker':.12}[kind]
    n=int(seconds*SR)
    t=np.arange(n,dtype=np.float32)/SR
    noise=rng.normal(0,1,n).astype(np.float32)
    if kind=='kick':
        freq=48+135*np.exp(-t*25)
        x=np.sin(2*np.pi*np.cumsum(freq)/SR)*np.exp(-t*15)
        x+=.10*noise*np.exp(-t*100)
    elif kind in ('snare','clap'):
        h=sosfilt(butter(2, 1700, 'highpass',fs=SR,output='sos'),noise).astype(np.float32)
        if kind=='snare':
            x=(.78*h+.22*np.sin(2*np.pi*180*t))*np.exp(-t*18)
        else:
            env=np.exp(-t*18)*(1 + .35*np.sin(2*np.pi*39*t))
            x=h*env
    elif kind in ('hat','openhat','shaker','crash'):
        h=sosfilt(butter(2, 2800 if kind!='crash' else 1100, 'highpass',fs=SR,output='sos'),noise).astype(np.float32)
        d={'hat':48,'openhat':11,'shaker':35,'crash':4}[kind]
        x=h*np.exp(-t*d)
        if kind=='shaker': x*=.65
    elif kind=='rim':
        x=np.sin(2*np.pi*820*t)*np.exp(-t*65) + .20*noise*np.exp(-t*85)
    elif kind=='tom':
        f=98+85*np.exp(-t*16)
        x=np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-t*13)
    return np.array(x,dtype=np.float32)

def degree_pitch(key,scale,degree,octave=4):
    notes=PITCHES[scale]
    return 12*(octave+1)+key+notes[degree%7]+12*(degree//7)

class Track:
    def __init__(self,rng):
        self.audio=np.zeros((TOTAL,2),dtype=np.float32)
        self.rng=rng
    def put(self,x,at,gain,pan=0.0):
        start=int(at*SR)
        if start>=TOTAL or start<0:return
        end=min(start+len(x),TOTAL)
        if end<=start:return
        x=x[:end-start]*gain
        self.audio[start:end,0]+=x*math.sqrt((1-pan)/2)
        self.audio[start:end,1]+=x*math.sqrt((1+pan)/2)
    def note(self,pitch,at,duration,kind,level=.15,pan=0):
        if at>=DURATION or duration<=.02:return
        x=tone(midi_to_hz(pitch),duration,kind,self.rng)
        self.put(x,at,level,pan)
    def hit(self,kind,at,level=.13,pan=0):
        self.put(drum(kind,self.rng),at,level,pan)
    def finish(self):
        a=self.audio
        wet=np.zeros_like(a)
        for delay,amount,cross in [(.093,.09,False),(.157,.075,True),(.223,.060,False),(.337,.035,True)]:
            n=int(delay*SR)
            wet[n:]+=(a[:-n,::-1] if cross else a[:-n])*amount
        a+=wet
        env=np.minimum(1,np.arange(TOTAL)/(.075*SR))*np.minimum(1,(TOTAL-1-np.arange(TOTAL))/(0.55*SR))
        a*=np.maximum(0,env)[:,None]
        p=np.max(np.abs(a))
        if p>0:a*=.87/p
        a=np.tanh(a*1.08)
        rms=float(np.sqrt(np.mean(a*a)))
        return np.clip(a,-.99,.99),rms


def create(mood,num):
    cfg=SETUPS[mood]
    rng=np.random.default_rng(int.from_bytes(hashlib.sha256(f'MovieGenerator-original-music-v2:{mood}:{num}'.encode()).digest()[:8],'big'))
    tempo=int(rng.integers(cfg['tempo'][0],cfg['tempo'][1]+1))
    beat=60/tempo
    bar=beat*4
    mode=str(rng.choice(cfg['mode']))
    key=int(rng.integers(0,12))
    prog=list(PROGRESSION[mode][int(rng.integers(0,len(PROGRESSION[mode])))])
    chordinst=str(rng.choice(cfg['chord']))
    leadinst=str(rng.choice(cfg['lead']))
    arpinst=str(rng.choice(cfg['arp']))
    bassinst=str(rng.choice(cfg['bass']))
    track=Track(rng)
    def degree_at(t):return prog[min(int(t/bar),100)%len(prog)]
    def root_at(t):return degree_pitch(key,mode,degree_at(t),3)
    chord_t=0
    while chord_t<DURATION:
        d=degree_at(chord_t)
        pitches=[degree_pitch(key,mode,d,4),degree_pitch(key,mode,d+2,4),degree_pitch(key,mode,d+4,4)]
        if mood in ('city','people','nature'):
            pitches.append(degree_pitch(key,mode,d+6,4) - (12 if mood=='people' else 0))
        dur=min(bar+.18,DURATION-chord_t+.1)
        if dur>0:
            for i,p in enumerate(pitches):
                gain={'action':.075,'city':.092,'mystery':.075,'nature':.085,'people':.09}[mood]
                track.note(p,chord_t,dur,chordinst,gain/(1+.11*len(pitches)),pan=(i-(len(pitches)-1)/2)*.20)
        chord_t+=bar
    t=0
    while t<DURATION:
        r=root_at(t)
        if mood=='action':
            offsets=[(0,.7),(.5,.35),(1.0,.7),(1.5,.35)]
        elif mood=='city': offsets=[(0,.78),(.75,.30),(1.5,.55),(2.75,.35)]
        elif mood=='mystery': offsets=[(0,1.4),(2.0,.6)]
        elif mood=='nature': offsets=[(0,1.6),(2.,.6)]
        else: offsets=[(0,.8),(1.5,.42),(3.,.55)]
        for offset,length in offsets:
            at=t+offset*beat
            if at>=DURATION:continue
            newroot=root_at(at)
            choice=newroot if rng.random()>.25 else newroot+7
            track.note(choice-12,at,length*beat,bassinst,.21 if mood=='action' else .155,pan=-.05)
        t+=bar
    arppatterns=[(0,1,2,1,0,2,1,3),(0,2,1,3,2,1,0,1),(0,1,0,2,1,3,2,1),(0,2,3,2,0,1,2,1)]
    arppat=arppatterns[num%len(arppatterns)]
    division=4 if mood in ('action','city') else 2
    if mood=='mystery' and num%3==0:division=4
    step=beat/division
    t=0.;idx=0
    while t<DURATION:
        d=degree_at(t)
        offsets=[0,2,4,6]
        oi=arppat[idx%len(arppat)]
        p=degree_pitch(key,mode,d+offsets[oi],4+(1 if mood=='action' and idx%7==3 else 0))
        chance={'action':.95,'city':.82,'mystery':.54,'nature':.72,'people':.62}[mood]
        if rng.random()<chance:
            level={'action':.074,'city':.09,'mystery':.075,'nature':.090,'people':.073}[mood]
            track.note(p,t,step*(1.32 if mood=='nature' else .85),arpinst,level,pan=(-.24 if idx%2 else .24))
        t+=step;idx+=1
    base_motif=[]
    for j in range(8):
        if j in (0,4): interval=0 if j==0 else 4
        else: interval=int(rng.choice([0,1,2,3,4,5,7]))
        base_motif.append(interval)
    if mood=='mystery': rhythm=[0,1.5,3,3.75]
    elif mood=='action': rhythm=[0,.75,1.5,2.5,3,3.5]
    elif mood=='nature': rhythm=[0,1,1.75,2.5,3.5]
    elif mood=='people': rhythm=[0,1,2.5,3.25]
    else:rhythm=[0,.75,1.5,2.25,3.25]
    m=0
    while m*bar<DURATION:
        at0=m*bar
        d=degree_at(at0)
        for j,off in enumerate(rhythm):
            at=at0+off*beat
            if at>=DURATION:continue
            deg=base_motif[(j+2*m)%len(base_motif)]
            note=degree_pitch(key,mode,(d+deg)%7,5 if mood!='mystery' else 4)
            if mood=='action' and m%2==1:note+=12 if j==2 else 0
            dur=beat*(1.0 if mood in ('nature','people') else .55)
            lv={'action':.13,'city':.12,'mystery':.12,'nature':.14,'people':.13}[mood]
            track.note(note,at,dur,leadinst,lv,pan=.13 if m%2==0 else -.13)
        m+=1
    if mood in ('action','city','people','nature'):
        beats=int(DURATION/beat)+1
        for k in range(beats):
            t=k*beat
            if t>=DURATION:continue
            b=k%4
            if mood=='action':
                track.hit('kick',t,.24)
                if b in (1,3):track.hit('snare',t,.17)
                if b==0 and k%8==0:track.hit('crash',t,.10)
                if b==3 and k%8==7:track.hit('tom',t+beat*.6,.15)
            elif mood=='city':
                if b in (0,2) or (b==3 and k%8==7):track.hit('kick',t,.205)
                if b in (1,3):track.hit('clap',t,.116)
            elif mood=='nature':
                if b==0:track.hit('kick',t,.10)
                if b==2:track.hit('rim',t,.065)
            elif mood=='people':
                if b in (0,2):track.hit('kick',t,.135)
                if b in (1,3):track.hit('snare',t,.075)
        subdiv=2 if mood!='action' else 4
        for n in range(int(DURATION/(beat/subdiv))+1):
            t=n*beat/subdiv
            if t>=DURATION:continue
            if mood=='nature':
                if n%2==0: track.hit('shaker',t,.045,pan=.28 if n%4==0 else -.28)
            elif mood=='people':
                track.hit('hat',t,.045 if n%2 else .055,pan=.18 if n%2 else -.18)
            elif mood=='city':
                track.hit('hat' if n%4 else 'openhat',t,.074 if n%2 else .056,pan=.16 if n%2 else -.16)
            else:
                track.hit('hat',t,.057 if n%2 else .07,pan=.12 if n%2 else -.12)
    else:
        for i,at in enumerate(np.arange(0,DURATION,beat*2)):
            if i%2==0:track.hit('kick',float(at),.14)
            else:track.hit('tom',float(at),.09)
        for i,at in enumerate(np.arange(0,DURATION,beat)):
            if i%3==0:track.hit('hat',float(at),.036,pan=.3)
    if mood in ('action','mystery'):
        t=max(0,DURATION-1.6)
        d=degree_at(t)
        for i in range(3):
            track.note(degree_pitch(key,mode,d+i*2,4),t,DURATION-t+.07,'strings',.082,pan=(i-1)*.3)
    out,rms=track.finish()
    target=OUT/f'{mood}-{num}.mp3'
    command=['ffmpeg','-hide_banner','-loglevel','error','-y','-f','f32le','-ar',str(SR),'-ac','2','-i','pipe:0','-c:a','libmp3lame','-b:a','128k','-ar',str(SR),str(target)]
    res=subprocess.run(command,input=out.astype('<f4',copy=False).tobytes(),stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    if res.returncode:
        raise RuntimeError(f'ffmpeg failed for {target}: {res.stderr.decode()}')
    return target,tempo,mode,rms

if __name__=='__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--per-mood', type=int, default=12)
    args = parser.parse_args()
    if not 1 <= args.per_mood <= 30:
        raise SystemExit('Number per mood must be between 1 and 30')
    for mood in SETUPS:
        for n in range(1,args.per_mood + 1):
            result=create(mood,n)
            print(f'{result[0].name} | bpm={result[1]} mode={result[2]} rms={result[3]:.3f}',flush=True)
