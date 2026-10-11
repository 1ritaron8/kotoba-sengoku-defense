"""Bounded HQ-only execution; outputs and saves stay in the prepared work."""
from pathlib import Path
import argparse, datetime as dt, hashlib, json, os, subprocess, time

RUN = Path(__file__).resolve().parent
ROOT = Path('C:/JP_DF')
ENGINE = ROOT/'tools/godot/Godot_v4.7.2-stable_win64.exe'
BLENDER = Path('C:/Program Files/Blender Foundation/Blender 5.2/blender.exe')
GATE = RUN/'BLENDER_PRODUCTION_GATE.json'

def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,d): p.write_text(json.dumps(d,indent=2,ensure_ascii=False),encoding='utf-8')
def protected():
    baseline=load(RUN/'HQ_SOURCE_BASELINE.json')
    candidate=Path(baseline['candidate'])
    changed=[k for k,v in baseline['files'].items() if not (candidate/k).is_file() or sha(candidate/k)!=v['sha256']]
    assert not changed,('Current candidate changed',changed)
    live=load(ROOT/'tests/profiles/common-overlay-01/evidence/baseline-source.json')
    prepared=load(ROOT/'tests/profiles/common-overlay-01/evidence/FUN_SOURCE_MANIFEST.json')
    for root,sources in [(ROOT,live['sources']),(Path(prepared['preparedRoot']),{k:v['sha256'] for k,v in prepared['runtimeFiles'].items()})]:
        altered=[k for k,v in sources.items() if sha(root/k.removeprefix('res://'))!=v]
        assert not altered,('Protected source changed',altered)
    game_freeze=RUN/'GAME_SOURCE_FREEZE.json'
    if game_freeze.is_file():
        frozen=load(game_freeze)
        isolated=Path(frozen['candidate'])
        altered=[k for k,v in frozen['all_isolated_sources'].items() if not (isolated/k).is_file() or sha(isolated/k)!=v]
        assert not altered,('Frozen isolated source changed',altered)
    return {'current_candidate_files':len(baseline['files']),'changed':[],'live137_changed':[],'prepared4_changed':[]}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('phase',choices=['produce','produce-recheck','export','import','syntax','game','material-probe-check','material-probe','correction-produce','correction-import','correction-syntax','correction-game'])
    parser.add_argument('--script',type=Path)
    parser.add_argument('--workshop',type=Path)
    args=parser.parse_args()
    gate=load(GATE)
    deadline=dt.datetime.fromisoformat(gate['hard_stop_utc'].replace('Z','+00:00'))
    assert gate['status']=='RUNNING' or gate['status']=='SOURCE_FROZEN'
    assert dt.datetime.now(dt.timezone.utc)<deadline-dt.timedelta(seconds=60)
    phase=args.phase
    if 'produce' in phase:
        production_stop=dt.datetime.fromisoformat(gate['production_stop_utc'].replace('Z','+00:00'))
        assert dt.datetime.now(dt.timezone.utc)<production_stop,'New production window closed'
    assert not (RUN/f'{phase}-receipt.json').exists(),'Each phase once; explicit correction only'
    profile=RUN/'evidence'/('game-correction' if phase=='correction-game' else phase)
    assert not profile.exists() or set(p.name for p in profile.iterdir())<= {'temp'}, 'Preserve any earlier execution evidence'
    profile.mkdir(parents=True,exist_ok=True)
    (profile/'temp').mkdir(exist_ok=True)
    env=os.environ.copy()
    env.update(APPDATA=str(profile),LOCALAPPDATA=str(profile),TEMP=str(profile/'temp'),TMP=str(profile/'temp'),BLENDER_USER_RESOURCES=str(profile/'blender-user'))
    candidate=RUN/'godot-candidate'
    is_blender='produce' in phase or phase=='export'
    if is_blender:
        assert args.script and args.script.resolve().is_relative_to(ROOT/'tools/art-authoring-pilot')
        assert args.workshop and args.workshop.resolve().is_relative_to(RUN)
        ready=load(RUN/'UX_ASSET_READY.json')
        assert ready['script_sha256']==sha(args.script), 'Producer must match writer freeze'
        if phase=='produce-recheck':
            prior=load(RUN/'produce-receipt.json')
            assert not prior['accepted'] and not (RUN/'assets/authored_assets.blend').exists()
        command=[str(BLENDER),'--background','--factory-startup','--disable-autoexec','--python-exit-code','2','--python',str(args.script.resolve()),'--','--workshop',str(args.workshop.resolve()),'--run',str(RUN)]
        if phase=='correction-produce': command+=['--correction']
        limit=480
    else:
        assert (RUN/'integration_result.json').is_file(), 'Wait for isolated copy/integration completion'
        assert sha(ENGINE)=='ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
        assert candidate.is_dir() and not candidate.is_junction() and not candidate.is_symlink()
        other=subprocess.run(['powershell.exe','-NoProfile','-Command',"if(@(Get-Process -Name '*Godot*' -ErrorAction SilentlyContinue).Count){exit 7}"],capture_output=True,timeout=15)
        assert other.returncode==0,'Another Godot is running'
        command=[str(ENGINE),'--path',str(candidate),'--accessibility','disabled','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--log-file',str(profile/'godot.log')]
        if 'import' in phase:
            command+=['--headless','--editor','--import']
            limit=240
        else:
            assert args.script and args.script.resolve().is_relative_to(RUN)
            if 'syntax' in phase or phase.endswith('-check'): command+=['--headless','--check-only']
            command+=['--resolution','1440x900','--script',str(args.script.resolve()),'--','--deadline-unix='+str(int(deadline.timestamp()))]
            limit=60 if 'syntax' in phase or phase.endswith('-check') else 90 if phase=='material-probe' else 360
    guard_before=protected()
    receipt={'phase':phase,'started_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'command':command,'profile':str(profile),'protected_before':guard_before,'timed_out':False,'script_error':False,'blender':is_blender,'script_sha256_before':sha(args.script) if args.script else None}
    started=time.monotonic()
    with (profile/'stdout.log').open('wb') as out,(profile/'stderr.log').open('wb') as err:
        proc=subprocess.Popen(command,cwd=RUN,env=env,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
        receipt['pid']=proc.pid
        dump(RUN/f'{phase}-receipt.json',receipt)
        print(json.dumps({'state':'RUNNING','phase':phase,'pid':proc.pid,'profile':str(profile)}),flush=True)
        while proc.poll() is None:
            logs=(profile/'stderr.log').read_text(encoding='utf-8',errors='replace')
            if any(s in logs for s in ['SCRIPT ERROR:','Parse Error:','SHADER ERROR:','Traceback (most recent call last):']):
                receipt['script_error']=True
                proc.kill()
                break
            if time.monotonic()-started>limit or dt.datetime.now(dt.timezone.utc)>deadline-dt.timedelta(seconds=10):
                receipt['timed_out']=True
                proc.kill()
                break
            time.sleep(.25)
        proc.wait(timeout=10)
    logs=(profile/'stderr.log').read_text(encoding='utf-8',errors='replace')
    receipt.update(exit_code=proc.returncode,ended_utc=dt.datetime.now(dt.timezone.utc).isoformat(),wall_seconds=time.monotonic()-started,protected_after=protected())
    receipt['script_error']=receipt['script_error'] or any(s in logs for s in ['SCRIPT ERROR:','Parse Error:','SHADER ERROR:','Traceback (most recent call last):'])
    receipt['accepted']=proc.returncode==0 and not receipt['timed_out'] and not receipt['script_error']
    receipt['script_sha256_after']=sha(args.script) if args.script else None
    receipt['accepted']=receipt['accepted'] and receipt['script_sha256_after']==receipt['script_sha256_before']
    receipt['captures']=[str(p) for p in profile.rglob('*.png')]
    receipt['results']=[str(p) for p in profile.rglob('*.json')]
    dump(RUN/f'{phase}-receipt.json',receipt)
    key='blender_launches' if is_blender else 'engine_launches'
    gate=load(GATE);gate[key].append({'phase':phase,'pid':proc.pid,'receipt':str(RUN/f'{phase}-receipt.json'),'accepted':receipt['accepted']});dump(GATE,gate)
    print(json.dumps({k:v for k,v in receipt.items() if k not in ['command','protected_before','protected_after']},ensure_ascii=False),flush=True)
    raise SystemExit(0 if receipt['accepted'] else 1)

if __name__=='__main__': main()
