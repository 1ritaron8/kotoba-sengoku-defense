extends RefCounted
## First-stage presentation geometry. This produces a copy; campaign, economy,
## troop statistics, wave recipes and the stored source map remain untouched.

const CampaignScenarios = preload("res://native/campaign_scenarios.gd")
const BACKGROUND_PATH: String = "res://assets/painted-battlefield/stage01.png"
const ART_SIZE: Vector2i = Vector2i(1831,859)
const INGRESS: Vector2 = Vector2(1.07,-.05)
const GATE: Vector2 = Vector2(.255,.79)
const NORTH_DECK: Vector2 = Vector2(.447,.285)
# The source map, two foot slots and foreground rail share this one translation.
const SOUTH_DECK_ART_SHIFT: Vector2 = Vector2(-40,-18)
const SOUTH_DECK: Vector2 = Vector2(.643,.738)+SOUTH_DECK_ART_SHIFT/Vector2(1831,859)
const LEARNING_SUPPORT: Vector2 = Vector2(.284,.760)
const DECK_RADIUS: float = .024
const DECK_ELEVATION: int = 2
const ROADSIDE_OFFSET: float = .105
const ROADSIDE_SLOT_OFFSET: float = .013
const DECK_POST_RANGE_BONUS: float = 60.0
const ROADSIDE_POST_RANGE_BONUS: float = 25.0
# Progress runs from the allied gate toward ingress. Every added slot remains
# in the allied half; these choices do not create routes or unlock other maps.
const ROADSIDE_LAYOUTS: Dictionary = {
	"defense":[.12,.25,.38],
	"withdrawal":[.10,.24],
	"advance":[.28,.44],
	"escort":[.12,.30],
	"interception":[.32,.46],
	"encirclement":[.20,.34,.46],
	"handoff":[],
}

static func applies_to(stage: Dictionary) -> bool:
	return str(stage.get("id","")) == "basic-forest" and int(stage.get("stageNumber",1)) == 1

static func _point(value: Vector2) -> Dictionary:
	return {"x":value.x,"y":value.y}

static func _deck(id: String, label: String, center: Vector2) -> Dictionary:
	var result: Dictionary = _point(center)
	var tangent: Vector2 = (GATE-INGRESS).normalized()
	result.merge({"id":id,"nameKo":label,"label":"높은 사격대","terrain":"wood","r":DECK_RADIUS,"elevation":DECK_ELEVATION,"guardRadius":.19,"pathIndex":0,"segmentIndex":0,"slotCapacity":2,"slotPositions":[_point(center-tangent*.013),_point(center+tangent*.013)],"acceptedUnitTypes":["archer","gunner"],"postRangeBonusPercent":DECK_POST_RANGE_BONUS,"rangeBonusPercent":((1.0+DECK_ELEVATION*.12)*(1.0+DECK_POST_RANGE_BONUS/100.0)-1.0)*100.0,"placementRole":"ranged"})
	return result

static func _roadside_post(id: String, label: String, center: Vector2) -> Dictionary:
	var result: Dictionary = _point(center)
	var tangent: Vector2 = (INGRESS-GATE).normalized()
	# The grass offset clears the painted dirt even above each soldier's feet.
	# A real post modifier preserves road coverage without inventing elevation.
	result.merge({"id":id,"nameKo":label,"terrain":"grass","r":DECK_RADIUS,"elevation":0,"guardRadius":.19,"pathIndex":0,"segmentIndex":0,"slotCapacity":2,"slotPositions":[_point(center-tangent*ROADSIDE_SLOT_OFFSET),_point(center+tangent*ROADSIDE_SLOT_OFFSET)],"acceptedUnitTypes":["archer","gunner"],"postRangeBonusPercent":ROADSIDE_POST_RANGE_BONUS,"rangeBonusPercent":ROADSIDE_POST_RANGE_BONUS,"placementRole":"ranged"})
	return result

static func _roadside_posts(stage: Dictionary) -> Array:
	# Main applies the scenario after this presentation copy. Read the same
	# registry here rather than treating the legacy map.mode as the mission mode.
	var scenario: Dictionary = stage.get("scenario",{})
	if scenario.is_empty(): scenario=CampaignScenarios.scenario_for(str(stage.get("id","")))
	if not bool(scenario.get("combatEnabled",true)): return []
	var mode: String = str(scenario.get("missionMode",stage.get("missionMode","defense")))
	var fractions: Array = ROADSIDE_LAYOUTS.get(mode,[]).duplicate()
	# Stage01's withdrawal mission defends the existing castle approach.
	if str(stage.get("id",""))=="basic-forest" and mode=="withdrawal": fractions=[.12,.25,.38]
	var tangent: Vector2 = (INGRESS-GATE).normalized()
	var normal: Vector2 = Vector2(-tangent.y,tangent.x)
	var result: Array = []
	for index in range(fractions.size()):
		var anchor: Vector2 = GATE.lerp(INGRESS,float(fractions[index]))
		for side in [-1,1]:
			var center: Vector2 = anchor+normal*ROADSIDE_OFFSET*float(side)
			var suffix: String = "northwest" if side<0 else "southeast"
			var id: String = "painted-roadside-%s-%d-%s" % [mode,index+1,suffix]
			result.append(_roadside_post(id,"길가 사격 지점 %d" % (result.size()+1),center))
	return result

static func _shooting_posts(stage: Dictionary) -> Array:
	var result: Array = [_deck("left-shoulder-pad","북쪽 사격대",NORTH_DECK),_deck("right-shoulder-pad","남쪽 사격대",SOUTH_DECK)]
	result.append_array(_roadside_posts(stage))
	return result

static func _scenery_obstacles() -> Array:
	# Small ground footprints follow trunks, stones and the closed castle body.
	# Canopies are not full movement disks. The road and both deck tops stay clear.
	var authored: Array = [
		["tree-west",.151,.399,.017], ["tree-north",.652,.173,.015],
		["tree-east",.941,.375,.014], ["tree-southwest",.047,.635,.014],
		["tree-southeast",.899,.827,.018],
		["rock-west",.229,.273,.021], ["rock-midwest",.294,.453,.025],
		["rock-north",.594,.255,.025], ["rock-east",.785,.524,.033],
		["rock-east-small",.825,.570,.024], ["rock-south",.410,.851,.028],
		["rock-southeast",.817,.919,.032], ["rock-southeast-small",.852,.958,.022],
		["rock-front",.263,.960,.026], ["rock-corner",.028,.954,.020],
		["castle-interior-west",.077,.797,.055],
		["castle-interior-center",.131,.855,.065],
		["castle-interior-east",.189,.854,.042],
		["castle-gate-wall",.190,.774,.034],
	]
	var result: Array = []
	for entry in authored:
		result.append({"id":entry[0],"x":float(entry[1]),"y":float(entry[2]),"r":float(entry[3]),"blockPlacement":true})
	return result

static func _river_features() -> Array:
	# The existing navigation contract accepts water rectangles. Small connected
	# rectangles follow this diagonal river, instead of blocking a whole quadrant.
	var result: Array = []
	for index in range(9):
		var x: float = float(index)*.055
		var y: float = .207-.56*x
		result.append({"id":"painted-river-%02d" % index,"kind":"river","x":x-.03,"y":y-.045,"w":.061,"h":.09,"blocksMovement":true})
	return result

static func _ground_posts(original: Array) -> Array:
	var result: Array = []
	var fractions: Array = [.24,.34,.44,.54,.64,.74,.83,.90]
	for index in range(fractions.size()):
		var post: Dictionary = original[index].duplicate(true) if index < original.size() and original[index] is Dictionary else {}
		post.merge({"id":str(post.get("id","painted-ground-%d" % index)),"nameKo":str(post.get("nameKo","전선 지원 지점")),"pathIndex":0,"segmentIndex":0,"t":float(fractions[index]),"r":float(post.get("r",.025)),"guardRadius":float(post.get("guardRadius",.145)),"mobilityFactor":float(post.get("mobilityFactor",1.0)),"capacityBonus":int(post.get("capacityBonus",0))},true)
		result.append(post)
	return result

static func apply(base: Dictionary) -> Dictionary:
	var stage: Dictionary = base.duplicate(true)
	if not applies_to(base):
		return stage
	for old_spatial_key in ["worldGeometry","visualComposition","remasterSource","water","bridges","escortRoute"]:
		stage.erase(old_spatial_key)
	stage["paintedPresentation"] = true
	stage["paintedBackground"] = BACKGROUND_PATH
	stage["background"] = BACKGROUND_PATH
	stage["paintedComposition"] = {
		"revision":"painted-stage01-7", "artSize":{"width":ART_SIZE.x,"height":ART_SIZE.y},
		"coordinateSpace":"canonical_normalized_map", "gate":_point(GATE),
		"northDeck":_point(NORTH_DECK), "southDeck":_point(SOUTH_DECK),
		# The rectangle only bounds sampling. Coverage is the irregular object
		# mask; neither surrounding grass nor a reflected grass strip is moved.
		"southDeckArtMove":{"sourceRect":[976,508,400,292],"objectMaskTexture":"res://assets/painted-battlefield/stage01-south-island-mask-patch22.svg","restorationTexture":"res://assets/painted-battlefield/stage01-south-ground-patch22.png","maskSpace":"original1831x859_source_pixels","composition":"original_object_rgb_only; native_grass_underlay_only_inside_old_object_coverage","pixelOffset":{"x":SOUTH_DECK_ART_SHIFT.x,"y":SOUTH_DECK_ART_SHIFT.y}},
		"deckElevationRule":"original decks retain elevation +24% and multiply post range +60% (combined +98.4%); grass posts elevation 0 and post range +25%; two shared archer/gunner slots per post",
		"learningLandmarks":{"forest":{"x":.151,"y":.335},"river":{"x":.20,"y":.095},"stone":{"x":.594,"y":.235}},
		"supplyMarker":{"x":LEARNING_SUPPORT.x,"y":LEARNING_SUPPORT.y,"kind":"supply_marker","labelKo":"학습 보급 도착점","building":false},
		"terrainHeight":"painted surfaces; no 3D height provider", "crop":"none",
	}
	var old_paths: Array = stage.get("paths",[])
	var path: Dictionary = old_paths[0].duplicate(true) if not old_paths.is_empty() else {"id":"painted-approach","objectiveId":"main"}
	path["points"] = [_point(INGRESS),_point(GATE)]
	stage["paths"] = [path]
	var old_objectives: Array = stage.get("objectives",[])
	var objective: Dictionary = old_objectives[0].duplicate(true) if not old_objectives.is_empty() else {"id":"main","label":"丸根砦","hp":26}
	objective.merge(_point(GATE),true)
	objective["mobile"] = false
	stage["objectives"] = [objective]
	stage["buildZones"] = _shooting_posts(stage)
	stage["obstacles"] = _scenery_obstacles()
	var tactics: Dictionary = stage.get("tactics",{}).duplicate(true)
	tactics["groundPosts"] = _ground_posts(tactics.get("groundPosts",[]))
	stage["tactics"] = tactics
	var history: Dictionary = stage.get("historicalBattlefield",{}).duplicate(true)
	for old_feature in ["heightFeatures","treeFeatures","structureFeatures","roadFeatures"]:
		history.erase(old_feature)
	history["waterFeatures"] = _river_features()
	var support_anchors: Dictionary = history.get("learningSupportAnchors",{}).duplicate(true)
	for key in support_anchors:
		support_anchors[key] = _point(LEARNING_SUPPORT)
	history["learningSupportAnchors"] = support_anchors
	stage["historicalBattlefield"] = history
	var camera: Dictionary = stage.get("camera",{}).duplicate(true)
	camera["allowZoom"] = false
	stage["camera"] = camera
	return stage
