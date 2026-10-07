"""Prepare and register approved casual terrain art against the 40 authored maps."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/battlefields-rendered"
PLAN = ART / "casual-v3-prompt-set.json"
BLUEPRINT_MANIFEST = ROOT / "tests/profiles/map-render-blueprints/export-73323cb9/map_render_blueprints_manifest.json"
GUIDANCE_MANIFEST = ROOT / "tests/profiles/map-render-blueprints/guided-81a07fca/map_render_guidance_manifest.json"
STYLE = ROOT / "output/art-direction/01-clean-casual-3d-standing-v2.png"

# Emphasize each battlefield's identity over the shared forest style reference.
SCENE_IDENTITIES = {
    1: "Compact wooded low-hill EARTHEN/TIMBER FORT approach. No agricultural plots.",
    2: "OPEN early-summer agricultural valley and THREE simple cloth-tent supply camps. Small edge groves; no roofed fortress gates or golden ripe harvest.",
    3: "GINKA MOUNTAIN FOOTHILL CASTLE-TOWN supply approach with wooded sculpted slopes, an old small summit fort as a separate landmark, Nagara river at northwest edge and timber castle-town roofs at the far southwest edge. The single main road defends the lower supply camp, not the summit fort. No flat farm field. Keep town roofs outside all actual standing-body windows.",
    4: "RUGGED MOUNTAIN CASTLE terraces: irregular grey stone retaining walls and rocky slope contours behind the exact winding roads. Small low stockade opening, no tall timber gate copied from stage 1. No river or farm field.",
    5: "KYOTO BASIN lowland EARTHWORK CASTLE: earthen ramparts, a readable modest moat and timber stockade around the rear fort, with flat dry land approaches and southeast river edge. No port, rice plot carpet, tall keep or later stone castle.",
    6: "Wooded LOW HILL SIEGE with stream/valley edge and rear supply road circuit. O is a moving cart floor: no gate/building at O. A separate small hill fort and modest supply tents remain off the loop. No farms or painted cart.",
    7: "COASTAL LOW-HILL FORT: broad blue Tsuruga bay northwest, small earth/timber fort northeast, dry Wakasa retreat road southwest. No farm fields, docks, landing boats or shrines.",
    8: "Same COASTAL LOW-HILL site as stage 7 in late spring/early summer: recognizable bay and fort, worn stockade and rutted retreat road; southwest objective is a modest withdrawal camp, not the northeast enemy fort. No snow or farm fields.",
    9: "SUMMER RIVER-FORD battle: broad shallow Anegawa across the tactical field, exposed gravel ford at the annotated crossing, open floodplain grass and modest riverbank camp. The ford is dry/shallow gravel, never deep water under the road. No large bridge, festival or night.",
    10: "USAYAMA wooded RIDGE and small timber kuruwa in the selected SEPTEMBER early engagement: mixed green and restrained early-autumn leaves, with Biwa lake along the east edge. Hill contour and forest paths, no winter foliage, snow, plain farms or big keep.",
    11: "DRY WINTER PLATEAU at Mikatagahara: broad tawny short grass, dusty ochre road, low rolling rises and small retreat camp. Very few tree clumps; no lush green forest, snow, paddies or canyon.",
    12: "SUMMER LOWLAND river-island EARTH FORT near Uji/Ogura: low banks and island-like land, quiet river edges and dry cultivated-land roads. No terrace rice staircases, watermill or coast.",
    13: "FOREST PASS RETREAT at Tonezaka: late-summer/autumn woodland, rocky low saddle, broad rutted MAIN roads at the guide's mandatory 1.10 width, with abandoned supply bundles beside the roads. Hidden flank approaches remain ordinary unmarked grass or woodland-edge ground. No separate side footpaths, town market, flat farmland or giant cliffs.",
    14: "NARROW VALLEY CASTLE TOWN at Ichijodani: north-south valley, small west-side stream, timber streets and earth-walled compounds on eastern dry ground, restrained scorched traces at far edge. Houses stay off all B/S/N clearings. No port or waterfall.",
    15: "ODANI WOODED MOUNTAIN RIDGE: several uneven earthwork kuruwa along the ridge, curved ascent paths and small foothill siege camp. Noticeable sculpted slope bands, no port, flat farms or enormous keep.",
    16: "NAGASHINO RIVER-CONFLUENCE: steep riverbanks, small period fort near the confluence, eastern dry relief-camp supply loop. O is a moving cart floor, never a building. No Shitaragahara palisade copied around this castle or painted cart.",
    17: "SHITARAGAHARA FIELD DEFENSE: open early-summer low grass, narrow Rengo stream and timber ANTI-CAVALRY PALISADE sections with earth berms beside the western line. Leave the exact shallow ford and all paths open. No temple, big castle or decorative farm grid.",
    18: "IWAMURA HIGH RIDGE SIEGE: brown late-autumn/winter leaves and dry grass, modest timber/earth mountain fort and winding dirt ascent. No green rice fields, blizzard, icy lake or fully developed later stone walls.",
    19: "TEDORIGAWA AUTUMN RIVER WITHDRAWAL: cloudy late-afternoon river plain, rain-darkened banks, rising turbid water at the specified existing water boundaries, exposed crossing land and muted grasses. The mission is retreat escort after a defeat. No summer sunshine, night-festival street or invented snow.",
    20: "SHIGISAN AUTUMN FOREST RIDGE: small irregular earthen fort platforms, a timber stockade and valley-edge slope. Brown leaves and quiet clay roads; no level grand double gate, tea-kettle fantasy, farms or moat lake.",
    21: "MIKI SPRING ENCIRCLEMENT: a historical enemy low hill fort and SEPARATE SMALL FRIENDLY SIEGE POSTS on foothill ground. Keep the enemy fort and defended friendly positions distinct, exactly as the guide places them. Spring cherry clusters and scattered petals are conspicuous around the margins where the selected seasonal phase permits them; fresh short grass on playable ground. The siege posts and low hill identity dominate; no generic central Y-shaped stockade, repeated dense forest enclosure or huge stone keep.",
    22: "ARIOKA LATE-AUTUMN CASTLE TOWN: low earthen castle walls and moat on the Itami terrace, timber town roofs around the edges and a dusty street approach. No coastal delta, paddies, giant waterwheel or farm-only scene.",
    23: "EXACT SAME MIKI terrain, roads, fort and siege-post locations as stage21 after the long blockade. Replace spring blossom/foliage with bare winter branches, tawny short grass, cold subdued light and weathered supplies. War traces and seasonal surfaces change, all physical geometry remains identical. No invented snow or lush spring landscape.",
    24: "ISHIYAMA FORTIFIED MONASTERY PLATEAU: modest 1580 timber temple roofs behind earth walls/stockade, northwest low waterways and dry raised entrances. Monastery identity is clear. No later Osaka keep, farm-only field or fantasy temple statues.",
    25: "TOTTORI MOUNTAIN BLOCKADE: a prominent Kyusho wooded slope with a modest enemy hill fort above separate friendly foothill blockade positions, dry contact land and the western low river edge. Follow the guide's mountain contour and post layout; do not reuse the Miki central-stockade/Y-road composition. Autumn foliage varies in grouped patches, fallen leaves collect beside low banks, and playable grass stays quiet. No sea cliff warehouse, landing boats, broad port or uniform farm field.",
    26: "TAKAMATSU FLOOD SIEGE: visibly extensive blue-grey flood basin around a small northeast LOWLAND ISLAND FORT, continuous earthen siege levee and DRY SOUTHERN supply circuit. O is a moving cart floor; no permanent gate or painted cart there. Ashimori river remains mostly beyond the far left edge. No sunny mountain fort, farms, sheer rock canyon or tall keep.",
    27: "SAME TAKAMATSU flood basin/levee/island fort as stage26, wet summer rear camp with messenger supply bundles and communication flags. Objective is dry rear-camp entrance. No burning Kyoto temple, snow, or Mitsuhide standing here.",
    28: "SAME TAKAMATSU wet summer flood-siege site as stages26/27, organized camp teardown, worn wheel tracks and withdrawal pennants along southwest road. Preserve flood water and levee anchors; no snow, ice or winter scene.",
    29: "YAMAZAKI WET SUMMER FIELD near western Tennozan FOOT SLOPES and eastern river edge, overcast late-afternoon light, muddy but traversable routes and modest battle camp. No summit combat, moonlight, invented fog, port or uniform crop field.",
    30: "SHIZUGATAKE WOODED RIDGE battle: Lake Yogo northwest edge, several SMALL earth/timber positions on separate hill spurs and winding woodland contact roads. Late spring/early summer; no identical grand twin gates, port, snow or farm-only field.",
    31: "KOMAKI SPRING LOW-HILL STANDOFF: small earthwork hill fort overlooking an open fresh-grass plain, separate low field positions and contact ground. Where the selected spring phase permits, show conspicuous grouped cherry blossoms along the margins with sparse petals; keep all standing-body areas clear. Low natural hill rise and broad field, no sheer cedar mountain, deep valley or farm carpet.",
    32: "NAGAKUTE ROLLING-HILL FIELD: early-summer green low hills, broad pasture-like clear land and modest dispersed field camp, low ridge lines. No duplicate Komaki summit, dense surrounding forest, golden harvest or collapsing dike.",
    33: "SHIKOKU ICHINOMIYA EARTH/TIMBER HILL FORT with wooded back ridge and Akui river edge below southwest, winding dry land approach. No later stone castle, canal city, flat farm carpet or gigantic coast fort.",
    34: "TOYAMA FLATLAND MOATED EARTH CASTLE: autumn muted ground, timber stockade and broad modest moat with two dry approach corridors. No mountain cliff, waterfall, modern white reconstructed keep or rice-grid scene.",
    35: "HETSUGIGAWA WINTER INLAND RIVER: broad dry gravel/shallow land crossing on Ono river, tawny grass and modest terrace camp. No sea, harbor, ships, lush summer farms, invented snow or storm.",
    36: "NEJIROZAKA NIGHT RAID: low hill/field edge, small earthen field posts and canvas tents, readable cool night with warm stable camp flames and DRY rear supply circuit. O is moving-cart ground, not a castle. No painted cart, sheer mountain void, invented storm or daylit rice field.",
    37: "YAMANAKA EARTH CASTLE: prominent exposed RED-BROWN LOAM CHECKERED DRY MOAT (shojibori) and RIDGED DRY DITCHES, modest timber/earth kuruwa and routes OUTSIDE the ditch cells. Spring grass sparse at edges. No flooded crop squares, big temple, fantasy stone castle or fully green restored monument turf.",
    38: "NIRAYAMA LOW-HILL ENCIRCLEMENT at Tagata plain: small earth fort, dry/wet modest moat, scattered hilltop siege posts and open spring/summer land roads. No winter snow, icy ridge, huge Fuji panorama, lush forest enclosure or farm-only grid.",
    39: "OSHI SUMMER WETLAND SIEGE: blue-grey low water channels, islands and natural earthen levees around a small earthen fort, dry approach roads OUTSIDE flooded marsh. Extensive wetland identity, no captured rubble, manor infiltration scene, mountains or dry farm-only field.",
    40: "ODAWARA GRAND OUTER EARTHWORK SIEGE: broad SOGAMAE EARTH RAMPART and empty dry moat on low hills, separate water moat on lowland edge, period timber castle-town roofs behind defenses. Clear outer gate road and staging land. No reconstructed modern white keep, three enormous roof gates, farm-grid carpet or copied forest fort.",
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lighting(number: int, blueprint: dict, presentation: dict):
    time = presentation.get("timeOfDay", blueprint["lighting"]["timeKey"])
    result = {"shadowStrength": 0.40, "ambientTint": "#e8e5ce", "keyTint": "#fff2d7", "keyEnergy": 1.12,
              "ambientEnergy": 0.40, "fillEnergy": 0.16, "shadowDirection": {"x": -0.7, "y": 0.45}}
    if "night" in time:
        result.update(ambientTint="#bac8de", keyTint="#c3d5ff", keyEnergy=0.55, ambientEnergy=0.35, fillEnergy=0.32)
    elif float(presentation.get("wetness", 0)) > .50:
        result.update(ambientTint="#c5d3d5", keyTint="#e3ece7", keyEnergy=0.85, ambientEnergy=0.48, fillEnergy=0.22)
    elif time in ("late_afternoon", "dusk", "evening"):
        result.update(ambientTint="#dac3b0", keyTint="#ffddb4", keyEnergy=0.95, ambientEnergy=0.40, fillEnergy=0.20)
    elif time == "dawn":
        result.update(ambientTint="#bdcbd6", keyTint="#dfdfd9", keyEnergy=.78, ambientEnergy=.46, fillEnergy=.25)
    return result


COMMON = """Use case: sketch-to-render.
Asset type: one production 16:9 EMPTY terrain image for a Japanese Sengoku-era strategy-defense PC game.
Input image 1 is the mandatory GEOMETRY/CAMERA blueprint with REFERENCE-ONLY annotations. Broad filled CYAN corridors show actual usable roads (their centre lines are exact); O marks the exact objective floor; gold B patches show archer placement ground AND clear standing-body space; teal S patches show frontline/support ground AND clear standing-body space; purple N patches are ninja clearings; orange X points are side entrances. Pale swept-body patches show every legally selectable position around a deployment centre. Remove ALL annotation lines, patches, circles, letters, numbers and black legend strips from final art. Input image 2 is the user-approved casual-3D STYLE reference only: its LEFT tactical map gives the sculpted painted material appearance; ignore its portrait-panel composition, troop models, fort placement and forest layout.
Render the blueprint using appealing sculpted, hand-painted casual 3D game materials: broad grouped foliage, clear rock contours, tactile but quiet soil, painted timber and authentic modest Japanese fortifications. Keep polished PC strategy-game depth. No photographic leaf/gravel microtexture, no flat green placeholders, no toy blocks, no gritty brown MMO gloom. Match the approved reference's style/detail budget while adapting vegetation, season, architecture and terrain to THIS actual historical battlefield. Do not clone the reference forest fort.
Preserve the exact orthographic oblique 50-degree camera, frame, road centerlines and forks, objective gate FLOORS, land heights, water boundaries and crossings from image 1 at the SAME normalized image coordinates. No overhead view, horizon or sky. Compact close tactical area. Replace crude geometry with artful period structures, keeping where their actual ground-level openings meet roads. Gates are about two standing soldiers tall; the playable dirt lanes fit small infantry formations. Natural open deployment clearings beside the routes, no symbols.
Terrain around troops must have calm middle values for blue/red warriors to read clearly. More detailed foliage and props belong on the edges. Trees, walls and rocks never cover roads, deployment clearings, support posts, or side ambush entrances. Some crude placeholder roofs/posts overlap annotated B or S ground: do NOT preserve those particular roofs/posts. The annotations are authoritative; redraw a smaller or shifted structure around the exact objective floor so every B and S center is visibly open natural earth/low grass. The entire clear-body patch immediately ABOVE each center is mandatory open earth or short grass: allow roughly x center +/- .026 and y center minus .140 to plus .018, or the larger measured patch shown in the guide. This floor AND body window must be free of roofs, fences, tree crowns and cliff faces. Use coherent soft light from UPPER RIGHT with shadows toward LOWER LEFT, including moonlight on a documented night stage; interpret the specified time/season/weather. When historical weather is unknown, follow the explicitly approved seasonal artistic presentation rather than claiming it is an observed weather record. Night stages remain readable with small camp torches, never a black screen.
Empty environment only: NO people, troops, horses, corpses, portrait inserts, loose weapons, interface, health bars, place labels, text, colored circles, markers, watermark, frame or comparison panels. No fantastical statues, modern reconstructed castle keeps, cherry-petal effects, neon or miniature tilt-shift. One full-frame image, at least 1672x941 or higher 16:9 resolution.
"""


COMMON_EDIT = """Use case: style-transfer, precise terrain edit.
EDIT INPUT IMAGE 1 IN PLACE into one empty full-frame 16:9 Sengoku battlefield, at least 1672x941. Input 1 is the clean native layout. Input 2 is the exact road and standing-body clearance guide for that same layout. Input 3 is MATERIAL STYLE ONLY: use its left tactical map's polished sculpted, hand-painted casual 3D finish; ignore its roads, buildings, forest composition, troops and portrait panel.
Preserve the exact frame, 50-degree oblique orthographic camera, EVERY main-road centreline and width, entrance, fork, merge, water boundary, dry crossing and objective floor at the same coordinates. No zoom, overhead view, sky or horizon. The ONLY visible roads are the main cyan corridors in image 2. They become broad, continuous traversable dirt ramps of the existing 1.10-world-unit width with the existing separation. Smooth the crude black stair-step seams into soft natural banks without moving the road surface. Remove arbitrary wood placeholder blocks on road entries.
GLOBAL RULE: emplacement attackers have NO visible separate road, path, arrow, dotted line, trench or cleared stripe. Their internal approaches cross ordinary grass, slopes, forest-edge ground or shore. Do NOT connect camps, roads or emplacement positions with extra lateral dirt tracks. The guide deliberately hides these internal routes. Boat transit remains WATER and its shore remains natural; never turn it into another dirt lane or bridge. Render only the main cyan road network and any explicitly separate cart supply circuit already in image 1.
Image 2's pale rectangles reserve SCREEN SPACE for standing bodies and weapons; they are NOT rectangular patches of flat terrain. Gold B is archer placement, teal S frontline/support, purple N ninja clearing. Keep every floor anchor and its original terrain elevation, slope, bank, moat, water/shore boundary and walkable bridge/dock deck. Preserve the historical low earthworks shown in image 1. Remove or move only scenery that would visually hide a standing soldier: tree crowns/trunks, roofs, high fences, high cliff faces and tall props. Retain continuous natural ground and low readable landforms behind the reserved bodies; do not flatten hills or erase earthworks across whole screen rectangles. Shrink or shift conflicting decoration while keeping the floor fixed. Small fort scenery belongs behind/left/below its floor and outside body windows. Do not wrap palisades around nearby placement points. Keep all deployment pockets and enemy departure body space readable. Never copy any guide markings, colours, labels or legend bars into final art.
Give each historical terrain its own identity and season, with readable broad rock/earth contours and period timber structures. Calm middle-value playable ground, restrained microtexture, detail grouped at edges. Soft upper-right light and lower-left shadows, readable moonlight for night scenes. No photography, toy cubes, gritty MMO gloom, fantasy architecture, modern reconstructed keeps. Empty battlefield: no people, troops, horses, corpses, loose weapons, vehicles, UI, health bars, labels, watermarks, panels or frame. Compass words below describe geography, NOT screen directions; image 1 fixes screen positions. Historical terrain is sourced, exact roads/props are game adaptations. Unknown weather is a seasonal artistic choice, not a historical observation.
"""


def prepare():
    source = ROOT / "native/maps.json"
    maps = read(source)
    old = read(ART / "prompt-set.json")["prompts"]
    blueprints = read(BLUEPRINT_MANIFEST)
    guides = read(GUIDANCE_MANIFEST)
    assert len(maps) == len(old) == len(blueprints["stages"]) == 40
    snapshot = Path(blueprints.get("sourceSnapshot", ""))
    if snapshot.is_file():
        frozen_maps = snapshot
    elif snapshot.is_dir():
        frozen_maps = snapshot / "maps.json"
    else:
        frozen_maps = BLUEPRINT_MANIFEST.parent / "source-snapshot/maps.json"
    assert digest(frozen_maps) == blueprints["mapsSha256"]
    original = read(frozen_maps)
    if maps != original:
        assert REVISION == "v3", "Current geometry revisions require an exact fresh blueprint snapshot"
        current_without_first_pocket = copy.deepcopy(maps)
        current_without_first_pocket[0]["buildZones"][0] = original[0]["buildZones"][0]
        assert current_without_first_pocket == original, "Changed layouts require a new blueprint snapshot; only the recorded first-pocket v3 correction is compatible with the old snapshot"
        expected_pocket = dict(original[0]["buildZones"][0], x=0.72, y=0.19, r=0.018)
        assert maps[0]["buildZones"][0] == expected_pocket
    assert guides["complete"] and guides["stageCount"] == 40
    assert digest(frozen_maps) == guides["mapsSha256"]
    previous_plan = read(PLAN) if PLAN.exists() else {}
    previous = {p["stageNumber"]: p for p in previous_plan.get("prompts", [])}
    entries = []
    for stage, prior, bp, guide in zip(maps, old, blueprints["stages"], guides["stages"]):
        number = stage["stageNumber"]
        assert stage["id"] == prior["stageId"] == bp["stageId"]
        assert number == prior["stageNumber"] == bp["stageNumber"]
        blueprint_path = Path(bp["path"])
        assert digest(blueprint_path) == bp["sha256"]
        guidance_path = Path(guide["path"])
        assert guide["stageId"] == stage["id"] and guide["stageNumber"] == number
        assert digest(guidance_path) == guide["sha256"]
        old_prompt = prior["prompt"]
        if "Ground season:" in old_prompt:
            scene = old_prompt.split("Scene:", 1)[1].split("Ground season:", 1)[0].strip()
        else:
            scene = "1560, Marune. Low wooded hill, small earthen/timber fort, dry defensive ditch; neutral season and daylight. No snow or storm."
        routes = [{"id": p["id"], "points": [[v["x"], v["y"]] for v in p["points"]]} for p in stage["paths"]]
        goals = [[v["x"], v["y"]] for v in stage["objectives"]]
        build = [[v["x"], v["y"]] for v in stage["buildZones"]]
        support_values = stage.get("tactics", {}).get("groundPosts", [])
        supports = []
        for post in support_values:
            anchor = post.get("position", post)
            if isinstance(anchor, dict) and "x" in anchor and "y" in anchor:
                supports.append([anchor["x"], anchor["y"]])
        history = stage["historicalBattlefield"]
        presentation = history.get("presentationWeather", {})
        weather = history.get("weather", {})
        time = presentation.get("timeOfDay", bp["lighting"]["timeKey"])
        details = "\nHistorical terrain and selected phase: " + str(history.get("terrainDesignKo", scene))
        details += "\nSelected date/season: " + str(history.get("phasePeriodKo", ""))
        details += f"\nTime of day: {time}; historical weather evidence (not automatically the rendering): " + json.dumps(weather, ensure_ascii=False)
        details += "\nMANDATORY approved seasonal/weather art direction: " + json.dumps(presentation, ensure_ascii=False)
        details += "\nTactical phase design: " + json.dumps(history.get("missionDesign", {}), ensure_ascii=False)
        details += "\nMANDATORY distinct battlefield terrain composition: " + json.dumps(history.get("terrainComposition", {}), ensure_ascii=False)
        details += "\nThis composition is based on historical terrain/ruins; exact road bends and prop positions are explicitly game adaptations. Only stages marked emphasizedBend use a conspicuous terrain-driven bend. On other stages keep approaches broad and simple. A small projecting rock warrants a small local deflection, never a giant U-turn. Show the hill contour, retaining bank or dry-moat edge that causes a bend; do not add a zigzag gate or extra road merely to decorate the image. Any stairs are secondary edge details at terrace changes, and all actual main roads remain traversable connected ramps."
        details += "\nWar/withdrawal/blockade traces: " + json.dumps(history.get("traces", []), ensure_ascii=False)
        details += "\nMANDATORY widened road/branch spacing: " + str(history.get("roadArtPolicyKo", ""))
        details += "\nBetween-road deployment policy: " + json.dumps(history.get("interRoadPlacement", {}), ensure_ascii=False)
        details += "\nThe broad cyan corridors use the actual widened 1.10-world-unit main-road width. Keep neighbouring branches visibly distinct, with a substantial strip of terrain between them. Two branches keep a steady separation through their separated middle section; three branches have evenly spaced terminal approaches. A real shared gate/ford may join roads, but never squeeze the whole battlefield's lanes into a ribbon. Gold B patches mark legal ranged positions: where between-road policy is outer_only, use wooded banks, rocky rises or dry-ditch terrain between roads and keep B positions on their designated outer shoulders. Where policy is dry_pockets, only the annotated dry deployment pockets are buildable. Do not add unmarked deployment platforms."
        details += "\nRoad centers, normalized from TOP LEFT (x,y): " + json.dumps(routes, separators=(",", ":"))
        details += "\nVisible ground-level gate/camp entrances (NOT roofs): " + json.dumps(goals, separators=(",", ":"))
        details += "\nOpen dry deployment centers, NO rocks/buildings/trees on these: " + json.dumps(build, separators=(",", ":"))
        if supports:
            details += "\nAdditional dry support clearings: " + json.dumps(supports, separators=(",", ":"))
        side_entries = [[v["point"]["x"], v["point"]["y"]] for v in stage.get("sideAmbushEntrances", [])]
        ninja_clearings = [[v["x"], v["y"]] for v in stage["historicalBattlefield"].get("ambushClearings", [])]
        details += "\nEmplacement attackers use HIDDEN internal approaches through natural grass, slopes or shore. Do NOT draw any separate dirt road, visible path, stripe or connection to a tower. Departure/landing body clearances remain natural open ground; boat transit stays water."
        details += "\nHidden but traversable ninja clearings among sparse edge vegetation: " + json.dumps(ninja_clearings, separators=(",", ":"))
        details += "\nMANDATORY BATTLEFIELD IDENTITY (takes priority over forest scenery in the style reference): " + SCENE_IDENTITIES[number]
        if REVISION in ("v4", "v5"):
            details += "\nThe gameplay view has been reoriented for a LOWER friendly headquarters (8, 7, 6 or 5 o'clock). Historical compass directions in the source identity are historical geographic relationships, NOT literal screen directions. Follow input image 1 for every reoriented river, fort, slope and road position. Keep all scenery upright with the same 50-degree oblique camera; never rotate or flip the pixels of a previous image. The broad cyan filled corridors must become CONTINUOUS naturally worn earth lanes from THIS battlefield's independently authored entrances through terrain-justified forks or parallel fronts to the lower headquarters. Do not invent extra bends, U-turns, mazes, houses in an entrance or roads that miss the highlighted corridors. The B/S clear-body patches in the guide are strictly empty earth or short grass, including their entire standing body area, not roofs or elevated structures."
        if number == 2:
            details += "\nObjectives are humble supply shelters and small tent garrison entrances on the early-summer field, NOT three identical fortress gates."
        if number in (26, 27, 28):
            details += "\nWet summer flood siege; preserve the lowland island fort and surrounding flood waters, with the rear supply circuit on the dry levee shown in the reoriented guide. Use the GUIDE, not literal compass words, for its on-screen position. The Ashimori river itself is mostly outside this compact tactical area. Rear friendly supply-camp gate must remain on DRY road, NOT the surrounded enemy island fort."
        if any(objective.get("mobile", False) for objective in stage["objectives"]):
            details += "\nThis stage has a MOVING friendly supply cart rendered as a live 3D object by the game. Do NOT paint any cart, vehicle or permanent gate/building at the O marker. Keep the entire rear supply circuit and O floor clear, with a modest supply camp beside the road rather than ON it. The surrounded enemy fort, if present, is a separate historical landmark."
        same_location = {8: 7, 23: 21, 27: 26, 28: 26}.get(number)
        if same_location:
            details += f"\nSame historical site and tactical area as stage {same_location}: reuse the EXACT terrain, road centre lines and widths, waterways, fort and camp locations. Do not change viewpoint, road topology or building footprints. Change ONLY this later phase's season, weather, vegetation surfaces, wear, depleted supplies and withdrawal traces. The current guide must agree with the canonical earlier layout."
        references = [str(guidance_path), str(STYLE)]
        common = COMMON
        if REVISION == "v6":
            common = COMMON_EDIT
            references = [str(blueprint_path), str(guidance_path), str(STYLE)]
            composition = history.get("terrainComposition", {})
            details = "\nBATTLEFIELD IDENTITY: " + SCENE_IDENTITIES[number]
            details += "\nPHASE/SEASON: " + str(history.get("phasePeriodKo", ""))
            details += "\nATMOSPHERE: " + str(presentation.get("labelKo", ""))
            details += f"\nTIME: {time}; rain intensity {presentation.get('rainIntensity', 0)}, frost {presentation.get('frostCoverage', 0)}, snow {presentation.get('snowCoverage', 0)}."
            details += "\nTERRAIN: " + str(composition.get("appearanceKo", ""))
            details += "\nWAR TRACES: " + json.dumps(history.get("traces", []), ensure_ascii=False, separators=(",", ":"))
            details += "\nDEPLOYMENT POLICY: " + str(history.get("interRoadPlacement", {}).get("policy", "open_positions")) + "; preserve the guide's exact clear pockets."
            details += "\nMAIN ROADS: " + str(len(stage["paths"])) + "; no extra lateral or emplacement-attack tracks."
            details += "\nOBJECTIVE FLAG FLOORS (x,y): " + json.dumps(goals, separators=(",", ":")) + "; keep each flag floor and the actual attack-contact floors below. A shared-health flag is not necessarily a road endpoint."
            objective_presentations = [{"objectiveId": objective["id"], "presentation": "supply_cart" if objective.get("mobile", False) else objective.get("presentation", "castle_gate")} for objective in stage["objectives"]]
            details += "\nFRIENDLY DEFENSE PRESENTATION: " + json.dumps(objective_presentations, separators=(",", ":")) + ". Paint a friendly gate only for castle_gate. For field_camp or defense_line, preserve the explicitly placed camp and bank landmarks rather than building an automatic gate or house over O. The historical enemy fort remains a separate landmark."
            contacts = [{"pathId": path["id"], "objectiveId": path.get("objectiveId", "main"), "floor": [path["points"][-1]["x"], path["points"][-1]["y"]]} for path in stage["paths"]]
            details += "\nACTUAL DEFENDED ATTACK CONTACT FLOORS: " + json.dumps(contacts, separators=(",", ":")) + ". Preserve EVERY separate road endpoint. Several endpoints may defend different portions of ONE shared-health camp or line; never force them to merge at the objective flag. A historical enemy fort is a separate landmark, not automatically the friendly objective."
            if len(goals) > 1:
                details += " Use separate modest camps, not repeated enormous gates. Keep roofs and supplies outside all pale standing-body windows."
            if any(objective.get("mobile", False) for objective in stage["objectives"]):
                details += " O is moving-cart ground. Never paint a cart, vehicle or permanent gate there. Keep its rear circuit open; supply camp stands beside it."
            if same_location:
                details += f"\nIf input 4 is supplied, it is the canonical earlier phase of this same tactical area (stage {same_location}). Edit that image in place: retain the EXACT camera, terrain shapes, roads, water boundaries, fort and camp positions, building footprints and dry floors. Change only this phase's weather, season, foliage surfaces and war traces. Inputs 1/2 must agree with these same physical coordinates; do not introduce a new viewpoint or road layout."
        entry = {"stageId": stage["id"], "stageNumber": number, "battleKo": prior["battleKo"], "prompt": common + details,
                 "referenceImages": references, "sameLocationReferenceStage": same_location,
                 "sourceGeometryFingerprint": bp["geometry"]["physicalGeometryFingerprint"],
                 "lighting": lighting(number, bp, presentation), "path": f"res://assets/battlefields-rendered/stage-{number:02d}-{stage['id']}-casual-{REVISION}.png", "status": "pending"}
        if previous_plan.get("sourceMapsSha256") == digest(source) and previous.get(number, {}).get("status") == "generated" and previous[number].get("sourceGeometryFingerprint") == entry["sourceGeometryFingerprint"] and previous[number].get("guidanceSha256") == guide["sha256"] and f"casual-{REVISION}" in previous[number].get("path", ""):
            entry = previous[number]
        entry["guidanceSha256"] = guide["sha256"]
        entries.append(entry)
    write(PLAN, {"version": 1, "mode": "built-in image_gen", "artDirection": "Approved option 1: clear casual sculpted/painted 3D", "sourceMapsSha256": digest(source), "approvedReference": "output/art-direction/01-clean-casual-3d-standing-v2.png", "prompts": entries})
    print(json.dumps({"prepared": len(entries), "path": str(PLAN), "lighting": [{"number": p["stageNumber"], "key": p["lighting"]["keyEnergy"]} for p in entries]}))


def register(records_path: Path, inspected: bool):
    records = read(records_path)
    plan = read(PLAN)
    manifest_path = ART / "manifest.json"
    manifest = read(manifest_path)
    assert digest(ROOT / "native/maps.json") == plan["sourceMapsSha256"]
    by_number = {p["stageNumber"]: p for p in plan["prompts"]}
    stages = {p["stageNumber"]: p for p in manifest["stages"]}
    # Partial registration must not relabel old paintings as current data.
    for previous_entry in stages.values():
        if not previous_entry.get("sourceDataSha256"):
            previous_entry["sourceDataSha256"] = manifest.get("sourceMapsSha256", "")
    for record in records:
        number = record["stageNumber"]
        entry = by_number[number]
        if record.get("path"):
            entry["path"] = record["path"]
        if record.get("referenceImages"):
            entry["referenceImages"] = record["referenceImages"]
        source = Path(record["generatedPath"]).resolve()
        target = (ROOT / entry["path"].removeprefix("res://")).resolve()
        assert target.parent == ART.resolve()
        assert source.is_file() and source.suffix.lower() == ".png"
        if target.exists():
            assert digest(target) == digest(source), "Refusing to overwrite a different approved art file"
        else:
            shutil.copyfile(source, target)
        with Image.open(target) as image:
            width, height = image.size
            assert 1.7 < width / height < 1.85 and width >= 1280
        entry.update(status="generated", generatedPath=str(source), sha256=digest(target), width=width, height=height)
        if record.get("prompt"):
            entry["prompt"] = record["prompt"]
        stages[number] = {"stageId": entry["stageId"], "stageNumber": number, "path": entry["path"], "sourceGeometryFingerprint": entry["sourceGeometryFingerprint"],
                          "sourceDataSha256": plan["sourceMapsSha256"],
                          "sha256": entry["sha256"], "width": width, "height": height, "normalizedBounds": [0, 0, 1, 1], "lighting": entry["lighting"],
                          "generatedBy": "OpenAI built-in image_gen", "artDirection": plan["artDirection"],
                          "review": {"assetInspected": inspected, "inGameReviewed": False, "status": "Actual game integration verification pending"}}
    manifest.update(sourceMapsSha256=plan["sourceMapsSha256"], expectedStageCount=40, artDirection=plan["artDirection"], stages=[stages[n] for n in sorted(stages)])
    current_entries = [p for number, p in stages.items() if p.get("artDirection") == plan["artDirection"] and p.get("sourceGeometryFingerprint") == by_number[number]["sourceGeometryFingerprint"] and by_number[number].get("status") == "generated"]
    manifest["complete"] = len(stages) == len(current_entries) == 40
    write(PLAN, plan)
    write(manifest_path, manifest)
    print(json.dumps({"registered": [r["stageNumber"] for r in records], "coverage": len(stages), "approvedStyleCount": len(current_entries), "complete": manifest["complete"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "register", "chunk"))
    parser.add_argument("--records", type=Path)
    parser.add_argument("--inspected", action="store_true")
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--revision", choices=("v3", "v4", "v5", "v6"), default="v3")
    parser.add_argument("--blueprints", type=Path)
    parser.add_argument("--guides", type=Path)
    args = parser.parse_args()
    REVISION = args.revision
    PLAN = ART / f"casual-{REVISION}-prompt-set.json"
    if args.blueprints is not None:
        BLUEPRINT_MANIFEST = args.blueprints
    if args.guides is not None:
        GUIDANCE_MANIFEST = args.guides
    if args.command == "prepare":
        prepare()
    elif args.command == "register":
        assert args.records is not None
        register(args.records, args.inspected)
    else:
        print(json.dumps(read(PLAN)["prompts"][args.start - 1:args.start - 1 + args.count], ensure_ascii=False))
