"""Link the final geometry to prior learning evidence without content reruns.

All coordinate observations come from the actual Game/Presentation/Nav CPU
snapshot. This checks bindings and preserved text; actual Main answers for the
six moved destinations are verified by qa_learning_direction_contract.gd.
"""
import copy
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROFILE = ROOT / "tests/profiles/learning-direction-contract/final-binding-6da86329"
SNAPSHOT = ROOT / "tests/profiles/learning-direction-contract/final-snapshot-6da86329/Godot/app_userdata/말의 전장/learning-layout-contract.json"
PRIOR_REPORT = ROOT / "tests/profiles/learning-direction-contract/cpu-main-final-9f1fe753-r3/Godot/app_userdata/말의 전장/qa_learning_direction_contract.json"
BASELINE = ROOT / "tests/profiles/learning-direction-contract/baseline/source-baseline.json"
FINAL_MAPS_SHA = "6da86329a6068860a1a409127184ebcf2a219f3f68b0c91928951738fd5423ef"
checks = 0
failures = []


def check(value, note):
    global checks
    checks += 1
    if not value:
        failures.append(note)


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def distance(a, b):
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def without_coordinates(plan):
    result = copy.deepcopy(plan)
    for stage in result["stages"].values():
        for mission in stage["missions"]:
            mission["action"].pop("position")
            for target in mission["targets"]:
                target.pop("position")
    return result


def main():
    maps = read(ROOT / "native/maps.json")
    plans = read(ROOT / "native/learning_plans.json")
    previous = read(PROFILE / "prior-plans.json")
    baseline = read(BASELINE)
    actual = read(SNAPSHOT)
    prior_report = read(PRIOR_REPORT)
    source_hashes = {name: sha(ROOT / path) for name, path in {
        "maps": "native/maps.json", "plans": "native/learning_plans.json",
        "curriculum": "native/curriculum.json", "voice": "assets/learning-voice/manifest.json",
        "main": "native/main.gd", "field": "native/learning_field.gd",
        "game": "native/game.gd", "presentation": "native/battlefield_presentation.gd",
        "progress": "native/progress.gd", "gate": "native/learning_gate.gd",
    }.items()}
    check(source_hashes["maps"] == FINAL_MAPS_SHA == actual["mapsSha256"], "Actual coordinate snapshot names the frozen final maps bytes")
    check(source_hashes["game"] == actual["gameSha256"] and source_hashes["presentation"] == actual["presentationSha256"], "Snapshot uses the current common runtime coordinate sources")
    check(prior_report["pass"] and prior_report["checks"] == 4949 and not prior_report["failures"], "Earlier complete actual Main matrix is valid evidence")
    check(prior_report["totals"] == {"stages": 40, "missions": 120, "actualTargetPoints": 360, "actualMainSupports": 120, "voiceKeys": 120, "assessmentScopes": 40, "preservedWords": 900}, "Earlier matrix completed every required observation")
    check(sha(PROFILE / "prior-plans.json") == prior_report["plansSha256"], "Before plans match the exact previously verified matrix")
    for name in ["curriculum", "voice", "main", "field", "progress", "gate"]:
        check(source_hashes[name] == baseline["sourceSHA256"][name], "Original protected source bytes preserved: " + name)
    check(actual["currentScopeHashes"] == actual["baselineScopeHashes"] == prior_report["scopeHashes"] and len(actual["currentScopeHashes"]) == 40, "All forty old unlock/assessment scopes remain identical")
    check(without_coordinates(previous) == without_coordinates(plans), "Only target/action coordinates change; all IDs, answers, text, ruby, grammar, item credits and feedback are identical")
    check(len(maps) == len(plans["stages"]) == len(actual["stages"]) == 40, "All forty final stages remain covered")
    changed = []
    count = 0
    overrides = []
    old_supports = {mission["missionId"]: mission["actualSupport"] for stage in prior_report["observations"] for mission in stage["missions"]}
    for stage in maps:
        stage_id = stage["id"]
        plan = plans["stages"][stage_id]
        runtime = actual["stages"][stage_id]
        check(not runtime["mirrored"], stage_id + " uses the final unreflected display layout")
        check(len(plan["missions"]) == 3, stage_id + " retains the original three reports")
        moved = []
        for old, mission in zip(previous["stages"][stage_id]["missions"], plan["missions"]):
            check(mission["targets"] == plan["missions"][0]["targets"], mission["id"] + " shares the same stage destination coordinates")
            points = []
            displayed = []
            for previous_target, target in zip(old["targets"], mission["targets"]):
                count += 1
                index = int(target["id"].removeprefix("zone-"))
                zone = stage["buildZones"][index]
                sample = runtime["candidates"][index]
                check(target["id"] == f"zone-{index:02d}" and sample["zoneIndex"] == index and sample["zoneId"] == zone["id"], mission["id"] + " retains the real build-zone identity " + target["id"])
                check(distance(target["position"], zone) < .00001 and distance(target["position"], sample["canonical"]) < .00001, mission["id"] + " canonical target matches the final actual zone " + target["id"])
                check(sample["landSafe"] is True and sample["margin"] == .008, mission["id"] + " actual Nav accepts its target with the original margin " + target["id"])
                points.append(target["position"])
                displayed.append(sample["displayed"])
                if previous_target["position"] != target["position"] and not any(move["targetId"] == target["id"] for move in moved):
                    moved.append({"targetId": target["id"], "labelJP": target["label"]["jp"], "before": previous_target["position"], "after": target["position"]})
            check(min(distance(a, b) for a, b in itertools.combinations(points, 2)) >= .22, mission["id"] + " preserves the original .22 minimum target separation")
            labels = [target["label"]["jp"] for target in mission["targets"]]
            axis = "x" if labels == ["左の支援点", "中央の支援点", "右の支援点"] else "y" if labels == ["上の支援点", "中央の支援点", "下の支援点"] else None
            check(axis is not None or labels == ["森", "川", "山"], mission["id"] + " preserves a known authored meaning family")
            if axis is not None:
                check(all(displayed[i][axis] < displayed[i+1][axis] - .00001 for i in range(2)), mission["id"] + " labels follow actual DISPLAY order")
            answer = next(target for target in mission["targets"] if target["id"] == mission["answerId"])
            check(distance(answer["position"], mission["action"]["position"]) < .00001, mission["id"] + " answer and action share one point")
            anchors = stage.get("historicalBattlefield", {}).get("learningSupportAnchors", {})
            if mission["id"] in anchors:
                anchor = anchors[mission["id"]]
                check(distance(answer["position"], anchor) < .00001 and distance(anchor, old_supports[mission["id"]]) < .00001, mission["id"] + " preserves the existing actual Main override point")
                check(runtime["learningSupportAnchors"][mission["id"]]["landSafe"] is True, mission["id"] + " preserved override remains actually land-safe")
                overrides.append(mission["id"])
        if moved:
            changed.append({"stageId": stage_id, "stageNumber": stage["stageNumber"], "destinations": moved})
    check(count == 360, "All 360 target references match the final actual runtime snapshot")
    check(len(overrides) == 9, "All nine original authoritative Main overrides are preserved")
    check([stage["stageNumber"] for stage in changed] == [15, 17, 20, 27, 29, 40], "Only the six actually moved selected destinations require narrow Main regression")
    check(sum(len(stage["destinations"]) for stage in changed) == 6, "The six affected stages each move exactly one shared destination")
    check(source_hashes["maps"] == sha(ROOT / "native/maps.json") and source_hashes["plans"] == sha(ROOT / "native/learning_plans.json"), "Final source and plans remain frozen during the audit")
    report = {"checks": checks, "failures": failures, "pass": not failures, "sourceSHA256": source_hashes, "priorMainReport": str(PRIOR_REPORT), "priorMainReportSHA256": sha(PRIOR_REPORT), "snapshot": str(SNAPSHOT), "snapshotSHA256": sha(SNAPSHOT), "targetsVerified": count, "preservedOverrideIds": overrides, "changedStages": changed, "scope": "Final actual Game/Nav/DISPLAY snapshot binding and exact source/text/scope preservation; only six moved destinations. Actual Main input/support regression is recorded separately. No new artwork, audio PCM, GPU, performance or PCK approval."}
    (PROFILE / "binding-impact.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"FINAL_LEARNING_BINDINGS {checks} checks / {len(failures)} failures / {count} targets; plansSHA={source_hashes['plans']}")
    for note in failures[:20]:
        print("FAIL", note)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
