"""Generator regression cases; no production output or curriculum mutation.

The frozen actual-Game snapshot supplies the real candidate points and Nav
observations. Additional reflected/invalid observations are explicit unit
fixtures, not claims about the current map policy or rendered artwork.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / 'tests/profiles/learning-direction-contract/baseline/source-baseline.json'
SNAPSHOT = ROOT / 'tests/profiles/learning-direction-contract/draft-snapshot-739b3089-final/Godot/app_userdata/말의 전장/learning-layout-contract.json'
OUT = ROOT / 'tests/profiles/learning-direction-contract/generator-preparation/results.json'
checks = 0
failures = []

def check(condition, message):
    global checks
    checks += 1
    if not condition:
        failures.append(message)

def winner(mission):
    return next(target for target in mission['targets'] if target['id'] == mission['answerId'])

def reject(operation, message):
    try:
        operation()
    except ValueError:
        check(True, message)
    else:
        check(False, message)

def main():
    specification = importlib.util.spec_from_file_location('learning_plan_generator', ROOT / 'tools/build_learning_plans.py')
    generator = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(generator)
    baseline = json.loads(BASELINE.read_text(encoding='utf-8'))
    snapshot = json.loads(SNAPSHOT.read_text(encoding='utf-8'))
    voice = json.loads((ROOT / 'assets/learning-voice/manifest.json').read_text(encoding='utf-8'))
    protected = ['native/curriculum.json', 'native/learning_plans.json', 'assets/learning-voice/manifest.json']
    source_hashes = {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in protected}
    # Reconstruct only the generator's input fields from the immutable runtime
    # observation. The live Engine draft may already have been revised.
    maps = []
    for stage_id in baseline['mapIds']:
        runtime = snapshot['stages'][stage_id]
        maps.append({'id': stage_id, 'buildZones': [dict(id=sample['zoneId'], **sample['canonical']) for sample in runtime['candidates']],
                     'historicalBattlefield': {'learningSupportAnchors': {mission_id: sample['canonical'] for mission_id, sample in runtime['learningSupportAnchors'].items()}}})
    pristine = copy.deepcopy((baseline, maps, snapshot))
    rebound, advice = generator.build_plans(baseline['curriculum'], maps, baseline['plans'], snapshot, True)
    check((baseline, maps, snapshot) == pristine, 'Generator never mutates authored plans or coordinate inputs')
    check(len(rebound['stages']) == 40, 'All40 stages survive coordinate rebinding')
    check(sum(len(stage['missions']) for stage in rebound['stages'].values()) == 120, 'All120 mission identities survive')
    check(sum(bool(mission['itemIds']) for stage in rebound['stages'].values() for mission in stage['missions']) == 30, 'Original30 explicit vocabulary-credit missions remain exact')
    check(sum(len(values) for values in advice.values()) == 9, 'Advice contains only the original9 Main overrides')
    for stage_id, stage in rebound['stages'].items():
        previous = baseline['plans']['stages'][stage_id]
        check({k:v for k,v in stage.items() if k != 'missions'} == {k:v for k,v in previous.items() if k != 'missions'}, stage_id+' preserves lesson/goal/grammar metadata')
        axis = generator._direction_axis([target['label'] for target in stage['missions'][0]['targets']])
        for old, mission in zip(previous['missions'], stage['missions']):
            immutable_old = copy.deepcopy(old)
            immutable_new = copy.deepcopy(mission)
            for value in [immutable_old, immutable_new]:
                value.pop('targets')
                value.pop('answerId')
                value['action'].pop('position')
            check(immutable_old == immutable_new, mission['id']+' preserves every authored field/report/ruby/focus span/credit')
            check(winner(old)['label'] == winner(mission)['label'], mission['id']+' requests the same semantic answer')
            check(mission['action']['position'] == winner(mission)['position'], mission['id']+' action is the selected picture point')
            key = hashlib.sha256(mission['report']['jp'].strip().encode('utf-8')).hexdigest()
            check(key in voice['clips'] and voice['clips'][key]['text'] == mission['report']['jp'], mission['id']+' retains its actual existing voice clip')
            check(mission['targets'] == stage['missions'][0]['targets'], mission['id']+' shares one map-wide destination set')
            displayed = [snapshot['stages'][stage_id]['candidates'][int(target['id'].split('-')[1])]['displayed'] for target in mission['targets']]
            if axis:
                check(displayed[0][axis] < displayed[1][axis] < displayed[2][axis], mission['id']+' follows actual observed DISPLAY meaning order')
    # The maps writer, not this test or generator, applies the advice. Here a
    # private in-memory fixture proves that final Main authority is enforced.
    aligned_maps = copy.deepcopy(maps)
    aligned_snapshot = copy.deepcopy(snapshot)
    for stage in aligned_maps:
        for mission_id, point in advice.get(stage['id'], {}).items():
            stage['historicalBattlefield']['learningSupportAnchors'][mission_id] = point
            sample = next(sample for sample in aligned_snapshot['stages'][stage['id']]['candidates'] if generator._same_point(point, sample['canonical']))
            aligned_snapshot['stages'][stage['id']]['learningSupportAnchors'][mission_id] = {k:copy.deepcopy(sample[k]) for k in ['canonical', 'displayed', 'landSafe', 'margin']}
    enforced, enforced_advice = generator.build_plans(baseline['curriculum'], aligned_maps, baseline['plans'], aligned_snapshot)
    check(enforced == rebound and enforced_advice == advice, 'Final plans use actual Main authority with no independent support point')
    repeated, repeated_advice = generator.build_plans(baseline['curriculum'], aligned_maps, enforced, aligned_snapshot)
    check(repeated == enforced and repeated_advice == advice, 'Already rebound plans regenerate identically without text/ID drift')
    reflected = copy.deepcopy(snapshot)
    reflected_stage = reflected['stages']['basic-farm']
    reflected_stage['mirrored'] = not reflected_stage['mirrored']
    for sample in reflected_stage['candidates']:
        sample['displayed']['x'] = 1-sample['displayed']['x']
    mirrored_plans, unused = generator.build_plans(baseline['curriculum'], maps, baseline['plans'], reflected, True)
    for mission in mirrored_plans['stages']['basic-farm']['missions']:
        positions = [reflected_stage['candidates'][int(target['id'].split('-')[1])]['displayed']['x'] for target in mission['targets']]
        check(positions[0] < positions[1] < positions[2], mission['id']+' reflected left/right remains true on the visible map')
        check(mission['report'] == next(old['report'] for old in baseline['plans']['stages']['basic-farm']['missions'] if old['id'] == mission['id']), mission['id']+' reflected display does not rewrite speech')
    reject(lambda: generator.build_plans(baseline['curriculum'], maps, baseline['plans']), 'Missing common runtime coordinate authority is rejected')
    stale = copy.deepcopy(snapshot)
    stale['stages']['basic-farm']['candidates'][0]['canonical']['x'] += .01
    reject(lambda: generator.build_plans(baseline['curriculum'], maps, baseline['plans'], stale, True), 'Stale candidate point is rejected rather than inferred from a second policy')
    blocked = copy.deepcopy(snapshot)
    for sample in blocked['stages']['basic-farm']['candidates']:
        sample['landSafe'] = False
    reject(lambda: generator.build_plans(baseline['curriculum'], maps, baseline['plans'], blocked, True), 'Blocked candidates cannot become support destinations')
    invalid_anchor = copy.deepcopy(aligned_snapshot)
    invalid_anchor['stages']['beginner-night']['learningSupportAnchors']['beginner-night-context-2']['landSafe'] = False
    reject(lambda: generator.build_plans(baseline['curriculum'], aligned_maps, baseline['plans'], invalid_anchor), 'Unsafe actual Main authority is rejected')
    check(all(hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest for path,digest in source_hashes.items()), 'Regression cases write no production curriculum/plans/voice bytes')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    result = {'checks': checks, 'failures': failures, 'passed': not failures, 'actualInputSnapshot': str(SNAPSHOT), 'inputSnapshotMapsSha256': snapshot['mapsSha256'],
              'sourceHashesBeforeAfterUnchanged': source_hashes, 'scope': 'Generator text/voice/identity preservation; forty observed input layouts; explicit reflected/invalid fixtures. Live final geometry and actual Main integration are verified separately after the maps writer publishes.'}
    OUT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'checks':checks,'failures':failures,'report':str(OUT)},ensure_ascii=False))
    raise SystemExit(0 if not failures else 1)

if __name__ == '__main__':
    main()
