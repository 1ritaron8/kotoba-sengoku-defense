"""Author emplacement assault departures from enemy camps, including docks.

Main attackers retain their authored roads. Hunters use terrain-safe separate
land corridors; boats have a water transit followed by a real walkable landing.
All path shapes are game adaptations of the historical terrain.
"""
import copy
import json
import math
from pathlib import Path
from normalize_battlefield_layouts import Terrain,xy,rec,astar,rounded,closest,distance,collision_rects

ROOT=Path(__file__).resolve().parent.parent
PROFILE=ROOT/'tests/profiles/history-design-20261007'
BOATS={
    9: [( .50,.055),(.50,.22),(.545,.29),(.595,.31)],
    12:[(.10,.385),(.10,.46),(.15,.52),(.225,.52)],
    39:[(.63,.075),(.55,.17),(.42,.255),(.36,.345)],
}

def write(path,value): path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def safe_route(a,b,terrain,lane):
    if terrain.segment(a,b,.019): return [a,b]
    raw=astar(a,b,terrain,lane)
    for radius in (.045,.025,.012,.005):
        curve=rounded(raw,terrain,radius)
        if all(terrain.segment(p,q,.018) for p,q in zip(curve,curve[1:])): return curve
    return raw

def main():
    source=ROOT/'native/maps.json'
    maps=json.loads(source.read_text(encoding='utf-8-sig'))
    baseline=PROFILE/'maps.before-camp-approaches.json'
    if not baseline.exists(): write(baseline,maps)
    reports=[]
    for stage in maps:
        n=stage['stageNumber']; terrain=Terrain(stage); h=stage['historicalBattlefield']
        h['sceneLandmarks']=[v for v in h['sceneLandmarks'] if not str(v.get('id','')).startswith('enemy-departure-')]
        records=[]
        for i,entry in enumerate(stage.get('sideAmbushEntrances',[])):
            path_index=int(entry['pathIndex']); path=[xy(v) for v in stage['paths'][path_index]['points']]
            old_join=xy(entry['connectionPoints'][-1]); old_staging=xy(entry['point'])
            boat=n in BOATS and i==0
            if boat:
                transit=BOATS[n]; departure=transit[0]; start=transit[-1]
                target=min(stage['buildZones'],key=lambda b:distance(xy(b),start))
                # Stop near the intended emplacement, then join a real main
                # road if no emplacement is present or it has been destroyed.
                d,join,_,_=closest(xy(target),path)
                direction=(join[0]-xy(target)[0],join[1]-xy(target)[1]); length=max(math.hypot(*direction),1e-9)
                staging=(xy(target)[0]+direction[0]/length*.04,xy(target)[1]+direction[1]/length*.04)
                if not terrain.point(staging,.021): staging=join
                entry['transportKind']='boat'; entry['transportPoints']=[rec(p) for p in transit]
                entry['enemyDeparturePoint']=rec(departure)
                display='적진 나루 · 수상 별동대 상륙로'
            else:
                departure=path[0]; start=departure; staging=old_staging
                _,join,_,_=closest(old_join,path)
                target=min(stage['buildZones'],key=lambda b:distance(xy(b),staging))
                entry.pop('transportKind',None); entry.pop('transportPoints',None)
                entry['enemyDeparturePoint']=rec(departure)
                display='적진 출발 · 사격 진지 별동대 접근로'
            if not terrain.point(staging,.024):
                options=[(staging[0]+dx*.008,staging[1]+dy*.008) for dx in range(-8,9) for dy in range(-8,9)]
                options=[p for p in options if terrain.point(p,.024)]
                staging=min(options,key=lambda p:distance(p,staging)) if options else join
            try:
                try:
                    routes=safe_route(start,staging,terrain, .06 if i%2==0 else -.06)
                except ValueError:
                    if boat: raise
                    routes=[]
                    for prefix_end in range(1,min(len(path)-1,12)):
                        try:
                            tail=safe_route(path[prefix_end],staging,terrain,.06 if i%2==0 else -.06)
                            routes=path[:prefix_end]+tail
                            break
                        except ValueError: continue
                    if not routes: raise
                routes+=safe_route(staging,join,terrain,0)[1:]
            except ValueError as error:
                raise ValueError((n,i,start,staging,join,str(error))) from error
            assert all(terrain.segment(a,b,.018) for a,b in zip(routes,routes[1:])),(n,i,'land')
            assert distance(routes[-1],closest(routes[-1],path)[1])<.001
            entry.update(point=rec(start),connectionPoints=[rec(p) for p in routes],displayNameKo=display,
                         role='tower_hunter_only',departureKind='enemy_dock' if boat else 'enemy_camp',
                         targetBuildZoneId=target['id'],approachDesignKo='적진에서 출발해 지형을 따라 사격 진지에 접근하는 별동대입니다. 실제 당시 부대 동선을 재현한 것은 아닙니다.')
            h['sceneLandmarks'].append({'id':f'enemy-departure-{i+1}','kind':'enemy_dock' if boat else 'enemy_entry_camp',**rec(departure),'scale':{'w':.08,'h':.055},'isGameAdaptation':True})
            records.append({'pathIndex':path_index,'departure':rec(departure),'landing':rec(start) if boat else None,'transportKind':'boat' if boat else 'land','landPoints':len(routes),'targetBuildZoneId':target['id']})
        h['roadArtPolicyKo']+=' 사격 진지 공격 별동대도 적진에서 출발합니다. 수상 접근이 있는 전장은 적진 나루·뱃길·상륙 지면을 구분합니다.'
        h['hunterApproachPolicyKo']='주력은 본진 공격 경로, 별동대는 적진에서 갈라지는 사격 진지 공격 경로를 이용합니다. 나룻배는 지정된 수역에서만 이동하고 상륙 후 지상 전투를 시작합니다.'
        reports.append({'stageNumber':n,'approaches':records})
    write(source,maps)
    write(PROFILE/'enemy-camp-approaches.json',reports)
    print(json.dumps({'stages':40,'hunterLandApproaches':sum(len(s['approaches']) for s in reports),'boatStages':list(BOATS)}))

if __name__=='__main__': main()
