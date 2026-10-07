"""Prepare and verify a narrow, private placement-pocket amendment.

Roads, terrain, objectives, economics and learning points are immutable here.
Production replacement is explicit and guarded by the candidate's CPU proof.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
PROFILE = ROOT / 'tests/profiles/compact-placement'
SOURCE = ROOT / 'native/maps.json'
EXPECTED_BASELINE = '9f1fe753a4dcc5f7c03fa9c26b546f9e47ed432e99bf3a59a3ba3aab59179bfd'
sys.path.insert(0, str(ROOT / 'tools'))
from normalize_battlefield_layouts import closest, xy

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--radius-overrides', type=Path)
    parser.add_argument('--additional-centres', type=Path)
    parser.add_argument('--commit', action='store_true')
    parser.add_argument('--finalize-n', action='store_true')
    args = parser.parse_args()
    PROFILE.mkdir(parents=True, exist_ok=True)
    before = PROFILE/'maps-pocket-before.json'
    candidate = PROFILE/'maps-pocket-draft.json'
    if args.finalize_n:
        proof = json.loads((PROFILE/'ambush-verification.json').read_text(encoding='utf-8'))
        if not proof.get('passed') or proof.get('failures') or proof.get('candidateSha256')!=sha(candidate):
            raise SystemExit('Refuse N sync: actual matching candidate proof is required')
        actual = {row['stageId']:row['ambushClearings'] for row in proof['ambushEnrichments']}
        stages = json.loads(candidate.read_text(encoding='utf-8'))
        for stage in stages: stage['historicalBattlefield']['ambushClearings']=actual[stage['id']]
        write(candidate,stages)
        print('Actual N metadata synchronized; re-observe final candidate',sha(candidate))
        return
    if args.commit:
        proof = json.loads((PROFILE/'runtime-verification.json').read_text(encoding='utf-8'))
        if not proof.get('passed') or proof.get('failures') or proof.get('candidateSha256') != sha(candidate):
            raise SystemExit('Refuse commit: matching complete candidate proof is required')
        if proof.get('singleClassDeployments')!=320 or proof.get('mixedDistinctDeployments')!=320:
            raise SystemExit('Refuse commit: full forty-map eight-class observation is required')
        if sha(SOURCE) != EXPECTED_BASELINE:
            raise SystemExit('Refuse commit: production differs from the reviewed baseline')
        for name in ['capacity-verification.json','native-clearance-verification.json']:
            independent=json.loads((PROFILE/name).read_text(encoding='utf-8'))
            if not independent.get('passed') or independent.get('candidateSha256')!=sha(candidate):
                raise SystemExit('Refuse commit: matching capacity and original-body clearance proofs are required')
        SOURCE.write_bytes(candidate.read_bytes())
        print('Committed compact placement maps', sha(SOURCE))
        return
    if not before.exists():
        if sha(SOURCE) != EXPECTED_BASELINE:
            raise SystemExit('Refuse draft: unexpected production baseline')
        before.write_bytes(SOURCE.read_bytes())
    if sha(before) != EXPECTED_BASELINE:
        raise SystemExit('Refuse draft: immutable pocket baseline differs')
    original = json.loads(before.read_text(encoding='utf-8'))
    result = copy.deepcopy(original)
    for stage in result:
        for zone in stage['buildZones']: zone['r'] = min(float(zone['r']), .030)
        for post in stage['tactics']['groundPosts']: post['r'] = min(float(post['r']), .025)
    result[16]['buildZones'][9]['y'] = .175
    result[16]['buildZones'][9]['r'] = .025
    result[26]['buildZones'][13]['y'] = .175
    result[26]['buildZones'][13]['r'] = .025
    post = result[39]['tactics']['groundPosts'][0]
    route = result[39]['paths'][post['pathIndex']]['points']
    _, position, segment, fraction = closest((.92102,.39903), [xy(p) for p in route])
    post.update(segmentIndex=segment,t=round(fraction,6),r=.025)
    # Native original-mesh observations require twelve upper emplacements to
    # move a few pixels rather than becoming unusably tiny click pockets.
    hints_path = ROOT/'tests/profiles/map-render-blueprints/guided-lower-v4-20261007-pocket-draft/guide_clipping_radius_hints.json'
    if hints_path.exists():
        hints = json.loads(hints_path.read_text(encoding='utf-8'))
        for item in hints['buildEdgeHints']:
            zone = result[int(item['stageNumber'])-1]['buildZones'][int(item['label'][1:])-1]
            zone['y'] = round(max(float(zone['y']),float(item['alternativeCentreYAtSameRadius'])+.001),6)
    # Two source road posts share the old entry bend. Leave the now-safe first
    # post in place and put the second farther along its own unchanged route.
    post_two = result[39]['tactics']['groundPosts'][1]
    second_route = result[39]['paths'][post_two['pathIndex']]['points']
    _, second_position, second_segment, second_fraction = closest((.878,.46),[xy(p) for p in second_route])
    post_two.update(segmentIndex=second_segment,t=round(second_fraction,6),r=.025)
    if args.radius_overrides:
        overrides = json.loads(args.radius_overrides.read_text(encoding='utf-8'))
        for item in overrides:
            stage = next(s for s in result if s['id']==item['stageId'])
            group = stage['buildZones'] if item['role']=='ranged' else stage['tactics']['groundPosts']
            zone = next(z for z in group if z['id']==item['id'])
            zone['r'] = float(item['radius'])
    if args.additional_centres:
        additions=json.loads(args.additional_centres.read_text(encoding='utf-8'))
        for item in additions:
            stage=next(s for s in result if s['id']==item['stageId'])
            old_stage=next(s for s in original if s['id']==item['stageId'])
            if item['role']!='ground': raise SystemExit('Only previously legal ground sub-centres are approved')
            host=next(p for p in old_stage['tactics']['groundPosts'] if p['id']==item['sourcePostId'])
            post=item['zone']
            points=stage['paths'][int(post['pathIndex'])]['points']
            origin_points=old_stage['paths'][int(host['pathIndex'])]['points']
            def post_xy(p,route):
                a,b=xy(route[int(p['segmentIndex'])]),xy(route[int(p['segmentIndex'])+1])
                return tuple(a[i]+(b[i]-a[i])*p['t'] for i in range(2))
            a,b=post_xy(post,points),post_xy(host,origin_points)
            if sum((a[i]-b[i])**2 for i in range(2))**.5+post['r']>host['r']+.00002:
                raise SystemExit('Sub-centre escapes the original allowed pocket')
            stage['tactics']['groundPosts'].insert(int(item.get('insertionIndex',len(stage['tactics']['groundPosts']))),post)
    changes = []
    for old, new in zip(original,result):
        for role,old_zones,new_zones in [('ranged',old['buildZones'],new['buildZones']),('ground',old['tactics']['groundPosts'],new['tactics']['groundPosts'])]:
            indexed={z['id']:z for z in new_zones}
            for oz in old_zones:
                nz=indexed[oz['id']]
                if oz != nz:
                    changes.append({'stageNumber':new['stageNumber'],'stageId':new['id'],'role':role,'id':nz['id'],'before':oz,'after':nz})
    # Keep the amendment narrow even when a later override is applied.
    stripped = copy.deepcopy(result)
    for old, new in zip(original,stripped):
        new['buildZones'] = old['buildZones']
        new['tactics']['groundPosts'] = old['tactics']['groundPosts']
    if stripped != original:
        raise SystemExit('Refuse draft: changes escaped placement fields')
    write(candidate,result)
    write(PROFILE/'pocket-amendment.json',{'baselineSha256':sha(before),'candidateSha256':sha(candidate),'changes':changes,'additionalCentres':additions if args.additional_centres else [],'scope':'Compact B/S radii, Native-measured clipped centres and capacity-preserving sub-centres wholly inside original allowed pockets; every other source value is identical','ground40NewPosition':{'x':position[0],'y':position[1]}})
    print('Private candidate ready',sha(candidate),'changes',len(changes),'additional compact centres',len(additions) if args.additional_centres else 0)

if __name__=='__main__': main()
