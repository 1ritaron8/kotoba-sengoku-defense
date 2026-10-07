"""Merge independently authored stage assets into the native game's 40-stage catalog."""
from pathlib import Path
import json

root = Path(__file__).resolve().parent.parent
plan = json.loads((root / "assets/stage-plan.json").read_text(encoding="utf-8"))
previous = json.loads((root / "native/maps.json").read_text(encoding="utf-8"))
# Authored road-post tactics live in the native stage catalog. Art shards do
# not own these gameplay records and must not erase them during reassembly.
previous_tactics = {stage["id"]: stage["tactics"] for stage in previous if "tactics" in stage}
by_id = {stage["id"]: stage for stage in previous if stage["tier"] == "basic"}
for name in ("maps-art-a.json", "maps-art-b.json"):
    shard = json.loads((root / "assets/stages" / name).read_text(encoding="utf-8"))
    if len(shard) != 15:
        raise ValueError(f"{name} must contain all fifteen completed stages")
    for stage in shard:
        if stage["id"] in by_id:
            raise ValueError(f"Duplicate stage: {stage['id']}")
        by_id[stage["id"]] = stage
music = json.loads((root / "native/music.json").read_text(encoding="utf-8"))
tracks = {track["stageId"]: track for track in music["tracks"]}
if len(tracks) != 40 or len(music["tracks"]) != 40:
    raise ValueError("Exactly forty one-to-one music assignments are required")
trait_catalog = json.loads((root / "native/stage_traits.json").read_text(encoding="utf-8"))
stage_rules = {rule["stageId"]: rule for rule in trait_catalog["traits"]}
if len(stage_rules) != 40 or len(trait_catalog["traits"]) != 40:
    raise ValueError("Exactly forty stage-specific operation rules are required")
stages = []
for spec in plan:
    stage = by_id[spec["id"]]
    stage["stageNumber"] = spec["stageNumber"]
    stage["title"] = spec["title"]
    stage["background"] = spec["background"]
    stage["music"] = tracks[spec["id"]]["path"]
    stage["trait"] = stage_rules[spec["id"]]
    if spec["id"] in previous_tactics:
        stage["tactics"] = previous_tactics[spec["id"]]
    for resource in (stage["background"], stage["music"]):
        file_path = root / resource.removeprefix("res://")
        if not file_path.is_file():
            raise ValueError(f"Missing stage resource: {file_path}")
    stages.append(stage)
if len({stage["background"] for stage in stages}) != 40:
    raise ValueError("Every stage must use its own background")
if len({stage["music"] for stage in stages}) != 40:
    raise ValueError("Every stage must use its own music")
(root / "native/maps.json").write_text(json.dumps(stages, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
manifest_path = root / "assets/manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["version"] = 2
manifest["stages"] = {stage["id"]: {"number": stage["stageNumber"], "title": stage["title"], "background": stage["background"], "music": stage["music"], "operation": stage["trait"]["nameJP"]} for stage in stages}
manifest["mapNotes"] = "The ten original environments are used once each by Basic stages. Thirty additional stages have independently generated environments and authored roads, build zones, and objectives. No stage shares its background or music with another stage."
manifest["stagePromptFiles"] = ["assets/stage-plan.json", "assets/stages/prompts-art-a.json", "assets/stages/prompts-art-b.json"]
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Assembled 40 distinct stage maps, 40 operation rules, and 40 stage music assignments.")
