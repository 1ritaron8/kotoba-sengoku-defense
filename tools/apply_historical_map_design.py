"""Apply the approved historical phases and terrain-dependent approaches.

Existing lower-base, water, full-body placement and convoy contracts remain
authoritative. Only land-safe approach prefixes are re-authored; references
to route segments are rebound to the same physical support floors.
"""
from __future__ import annotations
import copy
import json
import math
from pathlib import Path
from normalize_battlefield_layouts import Terrain, xy, rec, closest, along, distance

ROOT = Path(__file__).resolve().parent.parent
PROFILE = ROOT / "tests/profiles/history-design-20261007"
MULTI = {
    2: "여러 낮은 구릉 사이의 접근부", 9: "서로 떨어진 여울과 강둑 전선",
    11: "넓은 대지의 독립된 전열", 12: "저지대 요새 바깥의 육로",
    14: "계곡 마을의 골목과 하천변 길", 17: "개울 앞 서로 떨어진 사격 전선",
    19: "강변 철수로를 압박하는 여러 접근부", 21: "포위 초기의 분산된 진영",
    22: "성읍 외곽의 골목과 토루 접근부", 23: "장기 봉쇄로 닳은 포위 접근부",
    24: "사찰 성읍의 육상 출입로", 25: "산성 아래 여러 봉쇄 진지",
    30: "호수 주변 능선의 작은 진지 연결로", 31: "낮은 구릉 주변 평지 전선",
    32: "구릉과 밭 사이 분리된 교전 구역", 33: "산성 사면의 여러 육상 접근부",
    34: "평성 외곽 봉쇄 진영의 진입로", 35: "강변 여울과 하안단구 접근부",
    36: "밤중 야전 진지를 향한 분산 기습로", 37: "마른 해자 사이의 토교와 능선길",
    38: "구릉 요새를 둘러싼 포위 진영", 39: "습지의 서로 다른 육상 제방",
    40: "총구의 토루와 해자를 따라 나뉜 포위 접근부",
}

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")

def independent_prefix(points, terrain, used, number):
    # Follow the existing terrain corridor until it has separated from the
    # shared lead-in, then extend its local heading to a real field edge.
    lengths = [0.0]
    for a,b in zip(points,points[1:]): lengths.append(lengths[-1]+distance(a,b))
    for index in range(5, min(len(points)-5, 21)):
        if lengths[index] > lengths[-1]*.47: break
        anchor = points[index]
        forward = points[min(index+3,len(points)-1)]
        heading = (anchor[0]-forward[0],anchor[1]-forward[1])
        magnitude = max(math.hypot(*heading),1e-8)
        direction = (heading[0]/magnitude,heading[1]/magnitude)
        edges = [(i/100,.025) for i in range(4,97,4)]
        edges += [(side,i/100) for side in (.025,.975) for i in range(8,65,4)]
        candidates=[]
        for entry in edges:
            separation=min((distance(entry,u) for u in used),default=1)
            if separation < .085 or not terrain.segment(entry,anchor,.021): continue
            vector=(entry[0]-anchor[0],entry[1]-anchor[1])
            dot=(vector[0]*direction[0]+vector[1]*direction[1])/max(math.hypot(*vector),1e-8)
            if dot<.45: continue
            score=distance(entry,anchor)+(1-dot)*.55
            candidates.append((score,entry))
        if candidates:
            entry=min(candidates,key=lambda row:row[0])[1]
            return [entry]+points[index:], True
    return points, False

def main():
    PROFILE.mkdir(parents=True,exist_ok=True)
    source=ROOT/'native/maps.json'
    before=json.loads(source.read_text(encoding='utf-8-sig'))
    baseline=PROFILE/'maps.before.json'
    if not baseline.exists(): dump(baseline,before)
    maps=copy.deepcopy(before)
    geo=json.loads((ROOT/'native/campaign_geography.json').read_text(encoding='utf-8-sig'))['stages']
    changes=[]
    for stage,entry in zip(maps,geo):
        assert stage['id']==entry['stageId']
        n=stage['stageNumber']; h=stage['historicalBattlefield']
        for key in ('phasePeriodKo','presentationWeather','missionDesign','terrainDesignKo','season','weather','weatherKnown'):
            h[key]=copy.deepcopy(entry[key])
        h['timeOfDay']=entry['presentationWeather']['timeOfDay']
        season=entry['season']['key']
        h['groundSeason']='winter' if 'winter' in season else 'autumn' if 'autumn' in season else 'spring' if 'spring' in season else 'summer'
        old_paths=[[xy(p) for p in road['points']] for road in stage['paths']]
        terrain=Terrain(stage); used=[]; altered=0
        support=[]
        for post in stage.get('tactics',{}).get('groundPosts',[]):
            road=old_paths[int(post['pathIndex'])]
            a,b=road[int(post['segmentIndex'])],road[int(post['segmentIndex'])+1]
            t=float(post['t']); support.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))
        if n in MULTI:
            for road,points in zip(stage['paths'],old_paths):
                updated,changed=independent_prefix(points,terrain,used,n)
                used.append(updated[0]); road['points']=[rec(p) for p in updated]
                altered+=int(changed)
        new_paths=[[xy(p) for p in road['points']] for road in stage['paths']]
        for post,floor in zip(stage.get('tactics',{}).get('groundPosts',[]),support):
            d,q,index,t=closest(floor,new_paths[int(post['pathIndex'])])
            assert d<.025,(n,post['id'],d)
            post.update(segmentIndex=index,t=round(t,6))
        # A hunter joins the same physical land corridor, regardless of the
        # number of new prefix segments or independent main entrances.
        for side in stage.get('sideAmbushEntrances',[]):
            old_end=xy(side['connectionPoints'][-1])
            d,q,index,t=closest(old_end,new_paths[int(side['pathIndex'])])
            assert d<.025,(n,side['id'],d)
            side['connectionPoints'][-1]=rec(q)
            side['segmentIndex']=index; side['t']=round(t,6)
        starts=[road[0] for road in new_paths]
        unique=len({(round(p[0],4),round(p[1],4)) for p in starts})
        stage['enemyApproaches']=[dict(rec(p),pathIndex=i,role='path_attacker',terrainBasisKo=MULTI.get(n,'地形に沿う街道・尾根道から分岐')) for i,p in enumerate(starts)]
        if unique==1:
            stage['commonEnemyEntry']=dict(rec(starts[0]),branchPoint=rec(new_paths[0][1]),landingIndex=0)
        else:
            stage.pop('commonEnemyEntry',None)
        h['routeTopologyKo']=(MULTI[n]+"에서 들어온 적이 지형을 따라 본진을 향합니다. 동일 입구·분기 수를 전장마다 강제하지 않습니다." if n in MULTI else "지형에 존재하는 가도·능선길을 따라 접근하고 방어 구역 앞에서 나뉩니다.")
        h['roadArtPolicyKo']='실제 지형의 상대 관계에 맞춘 게임용 접근로입니다. 입구·굽이·갈림길 수는 전장마다 다르며, 길의 좌표와 건널목·배치 지면이 그림과 전투에서 일치해야 합니다.'
        h['layoutCoordinatePolicyKo']='아군 본진은 화면 8~5시 방향입니다. 지형 관계를 유지해 시점을 재구성했습니다. 적 접근부는 지형에 따라 독립 또는 공유하며 사격 진지 기습로는 별도입니다.'
        stage['camera']['designReasonKo']='실제 전장 중 교전 구역을 가까이 구성하고, 지형에 따라 여러 접근로를 사용합니다.'
        for road in new_paths:
            assert all(terrain.segment(a,b,.018) for a,b in zip(road,road[1:])),(n,'unsafe road')
        changes.append({'stageNumber':n,'stageId':stage['id'],'independentStarts':unique,'reworkedApproaches':altered,'supportFloorsPreserved':len(support),'presentationWeather':h['presentationWeather']})
    dump(PROFILE/'map-design-application.json',changes)
    dump(source,maps)
    print(json.dumps({'stages':len(maps),'independentApproachStages':sum(x['independentStarts']>1 for x in changes),'reworkedApproaches':sum(x['reworkedApproaches'] for x in changes),'report':str(PROFILE/'map-design-application.json')}))

if __name__=='__main__': main()
