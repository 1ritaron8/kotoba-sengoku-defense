extends Node3D
## One physical scene consumes the same normalized roads, water and objectives
## as combat. Height is sheared toward the camera so an elevated foot still
## projects onto its exact 2D gameplay anchor.

const Materials = preload("res://native/battlefield_materials.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const Weather = preload("res://native/battlefield_weather.gd")
const GRID_X: int = 96
const GRID_Y: int = 64
const GRID_BORDER: float = 0.065
const ROAD_HALF_WIDTH: float = 0.55
const ROAD_SURFACE_OFFSET: float = 0.005
const MODEL_ROOT: String = "res://assets/models/battlefield/"
const INTERACTIVE_FRAME_BUDGET_USEC: int = 6000
const PREPARATION_FRAME_BUDGET_USEC: int = 24000
const DEFAULT_HEIGHT_LIMIT_WORLD: float = 1.45
const MAX_HEIGHT_LIMIT_WORLD: float = 3.0

static func preview_frame_budget(value: int) -> int:
	return clampi(value,1000,PREPARATION_FRAME_BUDGET_USEC)

static func height_limit_for_history(value: Dictionary) -> float:
	var requested: Variant=value.get("heightLimitWorld",DEFAULT_HEIGHT_LIMIT_WORLD)
	if not (requested is float or requested is int) or not is_finite(float(requested)):
		return DEFAULT_HEIGHT_LIMIT_WORLD
	return clampf(float(requested),DEFAULT_HEIGHT_LIMIT_WORLD,MAX_HEIGHT_LIMIT_WORLD)

static var model_cache: Dictionary = {}
static var primitive_cache: Dictionary = {}
static var height_grid_cache: Dictionary = {}
static var height_grid_order: Array[String] = []
const HEIGHT_GRID_CACHE_LIMIT: int = 12

static func release_shared_resources() -> void:
	# These caches span battle and preview instances. Do not flush them on each
	# scene change; release them once when the application is shutting down.
	model_cache.clear()
	primitive_cache.clear()
	height_grid_cache.clear()
	height_grid_order.clear()
	Materials.release_shared_resources()
	RenderedArt.release_shared_resources()

static func shared_cache_diagnostics() -> Dictionary:
	var source_vertices: int = 0
	var uploaded_vertices: int = 0
	for variants in model_cache.values():
		for variant in variants:
			source_vertices += int(variant.get("sourceVertices",0))
			uploaded_vertices += int(variant.get("uploadedVertices",0))
	return {"modelVariantGroups":model_cache.size(),"primitiveMeshes":primitive_cache.size(),"sourceScanVertices":source_vertices,"uploadedScanVertices":uploaded_vertices,"materials":Materials.cache_diagnostics()}
var stage: Dictionary = {}
var history: Dictionary = {}
var width: float = 18.5
var depth: float = 12.0
var elevation: float = 50.0
var geometry_fingerprint: String = ""
var rebuild_count: int = 0
var heights: PackedFloat32Array = PackedFloat32Array()
var height_features: Array = []
var landmarks: Array = []
var road_segments: Array = []
var water_regions: Array = []
var shallow_regions: Array = []
var bridge_regions: Array = []
var clearing_centers: Array[Vector2] = []
var clearing_radii: Array[float] = []
var batches: Dictionary = {}
var structural_parts: Array = []
var structure_owner: String = ""
var structure_phase: String = "structure"
var objects: Array = []
var stats: Dictionary = {}
var seed_value: int = 1
var height_noise: FastNoiseLite
var height_centers: Array[Vector2] = []
var height_scale_x: Array[float] = []
var height_scale_y: Array[float] = []
var height_amplitudes: Array[float] = []
var height_rotations: Array[float] = []
var height_has_edge_ridge: bool = false
var height_limit_world: float = DEFAULT_HEIGHT_LIMIT_WORLD
var anchor_heights: Dictionary = {}
var ground_mesh: MeshInstance3D
var art_manifest_path: String = RenderedArt.MANIFEST_PATH
var legacy_art_preview: bool = false
var render_record: Dictionary = {}
var render_signature: String = ""

func configure(value: Dictionary, world_width: float, world_depth: float, elevation_degrees: float = 50.0) -> void:
	if not _begin_configure(value,world_width,world_depth,elevation_degrees): return
	var build_start: int = Time.get_ticks_usec()
	_collect_geometry()
	_build_height_grid()
	stats["heightBuildMilliseconds"] = (Time.get_ticks_usec()-build_start)/1000.0
	build_start = Time.get_ticks_usec()
	_build_ground()
	stats["groundBuildMilliseconds"] = (Time.get_ticks_usec()-build_start)/1000.0
	_complete_configure()

func configure_preview(value: Dictionary, world_width: float, world_depth: float, elevation_degrees: float = 50.0, frame_budget_usec: int = INTERACTIVE_FRAME_BUDGET_USEC) -> void:
	# Catalog input and scrolling keep receiving frames while an unseen map's
	# exact height grid is generated. Combat retains the synchronous contract.
	if not _begin_configure(value,world_width,world_depth,elevation_degrees): return
	stats["previewFrameBudgetUsec"] = preview_frame_budget(frame_budget_usec)
	var build_start: int = Time.get_ticks_usec()
	_collect_geometry()
	await _build_height_grid(true,preview_frame_budget(frame_budget_usec))
	stats["heightBuildMilliseconds"] = (Time.get_ticks_usec()-build_start)/1000.0
	build_start = Time.get_ticks_usec()
	await _build_ground(true,preview_frame_budget(frame_budget_usec))
	stats["groundBuildMilliseconds"] = (Time.get_ticks_usec()-build_start)/1000.0
	await get_tree().process_frame
	_complete_configure()

func _begin_configure(value: Dictionary, world_width: float, world_depth: float, elevation_degrees: float) -> bool:
	var new_width: float = maxf(world_width, 2.0)
	var new_depth: float = maxf(world_depth, 2.0)
	var new_elevation: float = clampf(elevation_degrees, 35.0, 85.0)
	var geometry: Dictionary = _geometry_contract(value)
	var fingerprint: String = (JSON.stringify(geometry) + ":%.5f:%.5f:%.4f" % [new_width, new_depth, new_elevation]).sha256_text()
	var physical_fingerprint: String = JSON.stringify(_physical_contract(value)).sha256_text()
	var new_record: Dictionary = RenderedArt.resolve(value,physical_fingerprint,art_manifest_path,legacy_art_preview)
	var new_render_signature: String = JSON.stringify(new_record).sha256_text()
	if fingerprint == geometry_fingerprint and new_render_signature == render_signature:
		return false
	geometry_fingerprint = fingerprint
	render_record = new_record
	render_signature = new_render_signature
	stage = value.duplicate(true)
	history = stage.get("historicalBattlefield", {})
	width = new_width
	depth = new_depth
	elevation = new_elevation
	# Repeated battles can share one site's physical relief and scatter seed.
	# Their stage IDs, seasonal surfaces and combat/learning state stay distinct.
	seed_value = absi(str(history.get("terrainLayout",{}).get("seed",stage.get("id", "battlefield"))).hash())
	rebuild_count += 1
	for child in get_children():
		remove_child(child)
		child.free()
	batches.clear()
	structural_parts.clear()
	structure_owner = ""
	structure_phase = "structure"
	objects.clear()
	stats = {"stageId": str(stage.get("id", "")), "terrainTriangles": GRID_X * GRID_Y * 2, "roadTriangles": 0, "waterTriangles": 0, "meshNodes": 0, "batches": 0, "instances": 0, "scannedModels": 0, "modelBaseTriangles": 0, "renderTrianglesUpperBound": 0, "bridgeCount": 0, "gateCount": 0, "treeCount": 0, "photoFloor": false}
	return true

func _complete_configure() -> void:
	var build_start: int = Time.get_ticks_usec()
	if str(render_record.get("mode","native")) == "native":
		_build_roads()
		_build_water()
		_build_shallow_crossings()
		_build_water_banks()
		_build_bridges()
		_build_landmarks()
		_build_objectives()
		_build_obstacles()
		_build_scatter()
		_commit_batches()
	else:
		# Static trees, roofs, bridges and road shading are already rendered in
		# the art. Keep only their exact terrain/navigation source and the live
		# terrain shadow receiver; never layer generic props over the artwork.
		for objective in stage.get("objectives",[]):
			var presentation: String = objective_presentation(objective)
			objects.append({"kind":"defended_gate" if presentation=="castle_gate" else "friendly_objective","point":_point(objective),"presentation":presentation,"id":objective.get("id","main"),"renderedBy":"artwork"})
		# Keep the physical architecture in this terrain instance, without
		# uploading generic buildings over the painted background.
		var artwork_objects: Array = objects.duplicate(true)
		_build_water_banks()
		_build_landmarks()
		_build_objectives()
		batches.clear()
		objects = artwork_objects
	stats["seasonDetails"] = Weather.build_ground_details(self,stage,Callable(self,"world_point"),Callable(self,"_weather_detail_clear"))
	stats["propsBuildMilliseconds"] = (Time.get_ticks_usec()-build_start)/1000.0
	stats["presentationWeather"] = Weather.profile_for_stage(stage)
	stats["renderLayerContract"] = render_layer_contract()
	stats["sourceDataContractValid"] = _validate_contract()
	stats["geometryFingerprint"] = geometry_fingerprint
	stats["physicalGeometryFingerprint"] = JSON.stringify(_physical_contract()).sha256_text()
	stats["rebuildCount"] = rebuild_count
	set_process(false)

func set_legacy_art_preview(enabled: bool) -> void:
	if legacy_art_preview == enabled:
		return
	legacy_art_preview = enabled
	refresh_rendered_art()

func refresh_rendered_art() -> void:
	RenderedArt.release_shared_resources()
	if not stage.is_empty():
		configure(stage,width,depth,elevation)

func render_layer_contract() -> Dictionary:
	var result: Dictionary = render_record.duplicate(true)
	var rendered: bool = str(result.get("mode","native")) != "native"
	result["staticGeometryVisible"] = not rendered
	result["heightPreserved"] = true
	result["dynamicShadowReceiver"] = true
	result["shadowReceiverLayer"] = 1
	result["flatPhotoPlane"] = false
	result["renderedArtwork"] = rendered
	result["normalizedUvHeightIndependent"] = true
	return result

func _geometry_contract(value: Dictionary) -> Dictionary:
	var historical: Dictionary = value.get("historicalBattlefield", {})
	var result: Dictionary = {}
	for key in ["id", "stageNumber", "paths", "objectives", "buildZones", "obstacles", "water", "bridges", "base", "sideAmbushEntrances"]:
		result[key] = value.get(key, null)
	for key in ["sceneLandmarks", "landmarkLabels", "heightFeatures", "materialTheme", "groundSeason", "sceneBiome", "waterFeatures", "traces", "terrain", "season", "timeOfDay", "weather", "presentationWeather", "ambushClearings", "terrainLayout"]:
		result[key] = historical.get(key, null)
	if historical.has("heightLimitWorld"):
		result["heightLimitWorld"] = historical.heightLimitWorld
	return result

func _collect_geometry() -> void:
	road_segments.clear()
	water_regions.clear()
	shallow_regions.clear()
	bridge_regions.clear()
	clearing_centers.clear()
	clearing_radii.clear()
	landmarks = history.get("sceneLandmarks", history.get("landmarkLabels", [])).duplicate(true)
	height_features = _resolved_height_features(history)
	height_centers.clear()
	height_scale_x.clear()
	height_scale_y.clear()
	height_amplitudes.clear()
	height_rotations.clear()
	anchor_heights.clear()
	height_limit_world=height_limit_for_history(history)
	# Unspecified/default relief keeps its original 1.4 amplitude ceiling.
	var amplitude_limit: float=height_limit_world if height_limit_world>DEFAULT_HEIGHT_LIMIT_WORLD else 1.4
	for feature in height_features:
		height_centers.append(_point(feature))
		height_scale_x.append(maxf(0.035,float(feature.get("w",0.25))*0.5))
		height_scale_y.append(maxf(0.035,float(feature.get("h",0.25))*0.5))
		height_amplitudes.append(clampf(float(feature.get("amplitudeWorld",feature.get("heightWorld",0.75))),-0.5,amplitude_limit))
		height_rotations.append(-float(feature.get("orientationRadians",0.0)))
	var biome: String = str(history.get("sceneBiome",history.get("terrain",{}).get("key","")))
	height_has_edge_ridge = "hill" in biome or "mountain" in biome or "ridge" in biome or "valley" in biome
	var seen_segments: Dictionary = {}
	var shared_layout: Dictionary = history.get("terrainLayout", {})
	for path in stage.get("paths", []):
		var points: Array = path.get("points", [])
		for index in range(points.size() - 1):
			_append_road(_point(points[index]), _point(points[index + 1]), false, seen_segments)
	for entry in shared_layout.get("hiddenApproaches",stage.get("sideAmbushEntrances", [])):
		var points: Array = entry.get("connectionPoints", []).duplicate(true)
		var origin: Vector2 = _point(entry.get("point", {}))
		if points.is_empty() or origin.distance_to(_point(points[0])) > 0.001:
			points.push_front({"x": origin.x, "y": origin.y})
		for index in range(points.size() - 1):
			_append_road(_point(points[index]), _point(points[index + 1]), true, seen_segments)
	if shared_layout.has("clearings"):
		for clearing in shared_layout.clearings:
			_append_clearing(clearing)
	else:
		for zone in stage.get("buildZones", []):
			_append_clearing(zone)
		for objective in stage.get("objectives", []):
			_append_clearing(objective)
		for clearing in history.get("ambushClearings", []):
			_append_clearing(clearing)
	var water_data: Dictionary = stage.get("water", {})
	if not water_data.is_empty():
		water_regions.append({"rect": _rect(water_data), "kind": "river"})
	for feature in history.get("waterFeatures", []):
		if feature is Dictionary and feature.has("w") and feature.has("h"):
			if str(feature.get("kind", "")) == "wetland":
				continue
			var rect: Rect2 = _rect(feature)
			if rect.size.x > 0.001 and rect.size.y > 0.001 and not _same_water_rect(rect):
				water_regions.append({"rect": rect, "kind": str(feature.get("kind", "river"))})
	for bridge in stage.get("bridges", []):
		bridge_regions.append({"rect": _rect(bridge), "kind": str(bridge.get("kind", "bridge")), "data": bridge})
	_collect_shallow_crossings()
	height_noise = FastNoiseLite.new()
	height_noise.seed = seed_value
	height_noise.frequency = 0.13
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

func _append_clearing(value: Dictionary) -> void:
	clearing_centers.append(_point(value))
	# Game permits an entire normalized placement circle, not just its center.
	# Keep scenery outside that circle plus the standing body's floor margin.
	clearing_radii.append(maxf(0.0,float(value.get("r",0.0)))*maxf(width,depth))

func _resolved_height_features(historical: Dictionary) -> Array:
	# Source hashing and actual height construction must include the same
	# landmark-derived relief when explicit height features are absent.
	var result: Array = historical.get("heightFeatures",[]).duplicate(true)
	if result.is_empty():
		for landmark in historical.get("sceneLandmarks",historical.get("landmarkLabels",[])):
			var kind: String = str(landmark.get("kind",""))
			if kind in ["hill", "low_rise", "ridge", "hill_slope", "foothill", "mountain_fort", "hill_fort", "low_hill_fort", "plateau", "stone_terrace", "river_terrace"]:
				var scale_data: Dictionary = landmark.get("scale",{"w":.25,"h":.2})
				result.append({"x":landmark.get("x",.5),"y":landmark.get("y",.5),"w":scale_data.get("w",.25),"h":scale_data.get("h",.2),"amplitudeWorld":1.10 if kind in ["ridge","mountain_fort"] else .65,"orientationRadians":landmark.get("orientationRadians",0.0),"kind":kind})
	return result

func _collect_shallow_crossings() -> void:
	# Authoring describes a whole river landmark while collision rectangles
	# describe only deep water. A marked ford supplies the shallow remainder;
	# this changes neither navigation, terrain height nor placement rules.
	for landmark in landmarks:
		if str(landmark.get("kind","")) not in ["river","stream","valley_river","waterway"]:
			continue
		var size_data: Dictionary = landmark.get("scale",{})
		var size_value: Vector2 = Vector2(float(size_data.get("w",0)),float(size_data.get("h",0)))
		if size_value.x <= .01 or size_value.y <= .01:
			continue
		var full_rect: Rect2 = Rect2(_point(landmark)-size_value*.5,size_value)
		var has_ford: bool = false
		for bridge in bridge_regions:
			if str(bridge.kind) == "ford" and full_rect.intersects(bridge.rect):
				has_ford = true
		if not has_ford:
			continue
		var parts: Array[Rect2] = [full_rect]
		var has_deep_water: bool = false
		for region in water_regions:
			if not full_rect.intersects(region.rect):
				continue
			has_deep_water = true
			var remaining: Array[Rect2] = []
			for part in parts:
				remaining.append_array(_subtract_rect(part,region.rect))
			parts = remaining
		if has_deep_water:
			for part in parts:
				if part.size.x > .004 and part.size.y > .004:
					shallow_regions.append({"rect":part,"fullRect":full_rect,"kind":"ford"})

func _subtract_rect(source: Rect2,cut: Rect2) -> Array[Rect2]:
	if not source.intersects(cut):
		return [source]
	var overlap: Rect2 = source.intersection(cut)
	var result: Array[Rect2] = []
	for piece in [Rect2(source.position,Vector2(source.size.x,overlap.position.y-source.position.y)),Rect2(Vector2(source.position.x,overlap.end.y),Vector2(source.size.x,source.end.y-overlap.end.y)),Rect2(Vector2(source.position.x,overlap.position.y),Vector2(overlap.position.x-source.position.x,overlap.size.y)),Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(source.end.x-overlap.end.x,overlap.size.y))]:
		if piece.size.x > .0001 and piece.size.y > .0001:
			result.append(piece)
	return result

func _shallow_at(p: Vector2) -> bool:
	for region in shallow_regions:
		if region.rect.has_point(p):
			return true
	return false

func _append_road(a: Vector2, b: Vector2, side: bool, seen: Dictionary) -> void:
	if a.distance_squared_to(b) < 0.000001:
		return
	var key: String = "%.5f,%.5f:%.5f,%.5f" % [a.x, a.y, b.x, b.y]
	var reversed_key: String = "%.5f,%.5f:%.5f,%.5f" % [b.x, b.y, a.x, a.y]
	if seen.has(key) or seen.has(reversed_key):
		return
	seen[key] = true
	road_segments.append({"a": a, "b": b, "side": side})

func _point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x", 0.5)), float(value.get("y", 0.5)))

func _rect(value: Dictionary) -> Rect2:
	return Rect2(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("w", 0.0)), float(value.get("h", 0.0)))

func _same_water_rect(rect: Rect2) -> bool:
	for region in water_regions:
		if region.rect.position.distance_to(rect.position) < 0.001 and region.rect.size.distance_to(rect.size) < 0.001:
			return true
	return false

func _scaled(p: Vector2) -> Vector2:
	return p * Vector2(width, depth)

func _road_projection(p: Vector2, visible_only: bool = false) -> Dictionary:
	var target: Vector2 = _scaled(p)
	var best: Dictionary = {"distance": 1000.0, "t": 0.0, "a": p, "b": p, "side": false}
	for segment in road_segments:
		# Hunter corridors still shape physical relief and retain their metadata;
		# their centreline must not paint a road or clear a visible strip of trees.
		if visible_only and bool(segment.side): continue
		var a: Vector2 = _scaled(segment.a)
		var b: Vector2 = _scaled(segment.b)
		var axis: Vector2 = b - a
		var t: float = clampf((target - a).dot(axis) / maxf(axis.length_squared(), 0.0001), 0.0, 1.0)
		var distance: float = target.distance_to(a.lerp(b, t))
		if distance < float(best.distance):
			best = {"distance": distance, "t": t, "a": segment.a, "b": segment.b, "side": segment.side}
	return best

func _natural_height(p: Vector2) -> float:
	var result: float = 0.0
	for index in range(height_centers.size()):
		var scale_x: float = height_scale_x[index]
		var scale_y: float = height_scale_y[index]
		var relative: Vector2 = (p-height_centers[index]).rotated(height_rotations[index])
		var radius: float = pow(relative.x / scale_x, 2.0) + pow(relative.y / scale_y, 2.0)
		var amplitude: float = height_amplitudes[index]
		result += amplitude * exp(-radius * 1.35)
	result += height_noise.get_noise_2d(p.x * width, p.y * depth) * 0.06
	if height_has_edge_ridge:
		var edge: float = minf(minf(p.x,1.0-p.x)*width,minf(p.y,1.0-p.y)*depth)
		var ridge: float = 1.0-smoothstep(.18,1.95,edge)
		var broken_edge: float = .78+height_noise.get_noise_2d(p.x*width*.9+30.0,p.y*depth*.9-8.0)*.35
		result += ridge*broken_edge*1.16
	return clampf(result, -0.16, height_limit_world)

func _anchor_height(p: Vector2) -> float:
	if not anchor_heights.has(p): anchor_heights[p] = _natural_height(p)
	return float(anchor_heights[p])

func _raw_height(p: Vector2) -> float:
	var value: float = _natural_height(p)
	var nearest: Dictionary = _road_projection(p)
	var distance: float = float(nearest.distance)
	if distance < 0.80:
		var road_height: float = lerpf(_anchor_height(nearest.a), _anchor_height(nearest.b), float(nearest.t))
		value = lerpf(value, road_height, 1.0 - smoothstep(0.42, 0.80, distance))
	for center in clearing_centers:
		var center_distance: float = _scaled(p - center).length()
		if center_distance < 0.63:
			value = lerpf(value, _anchor_height(center), 1.0 - smoothstep(0.32, 0.63, center_distance))
	for region in water_regions:
		var rect: Rect2 = region.rect
		if rect.has_point(p):
			var water_edge: float = minf(minf(p.x - rect.position.x, rect.end.x - p.x) * width, minf(p.y - rect.position.y, rect.end.y - p.y) * depth)
			value = lerpf(value, -0.23, smoothstep(0.0, 0.22, water_edge))
	for bridge in bridge_regions:
		var bridge_rect: Rect2 = bridge.rect
		if bridge_rect.grow(0.006).has_point(p):
			var edge_distance: float = minf(minf(p.x - bridge_rect.position.x, bridge_rect.end.x - p.x) * width, minf(p.y - bridge_rect.position.y, bridge_rect.end.y - p.y) * depth)
			value = lerpf(value, 0.045 if str(bridge.kind) != "ford" else -0.012, smoothstep(-0.08, 0.06, edge_distance))
	return value

func _grid_point(x: int, y: int) -> Vector2:
	return Vector2(float(x) / GRID_X, float(y) / GRID_Y) * (1.0 + GRID_BORDER * 2.0) - Vector2.ONE * GRID_BORDER

func _build_height_grid(responsive: bool = false, frame_budget_usec: int = INTERACTIVE_FRAME_BUDGET_USEC) -> void:
	if not geometry_fingerprint.is_empty() and height_grid_cache.has(geometry_fingerprint):
		heights = height_grid_cache[geometry_fingerprint]
		height_grid_order.erase(geometry_fingerprint)
		height_grid_order.append(geometry_fingerprint)
		stats["heightCacheHit"] = true
		return
	stats["heightCacheHit"] = false
	var slice_start: int = Time.get_ticks_usec()
	heights.resize((GRID_X + 1) * (GRID_Y + 1))
	for y in range(GRID_Y + 1):
		for x in range(GRID_X + 1):
			heights[y * (GRID_X + 1) + x] = _raw_height(_grid_point(x, y))
			if responsive and x % 8 == 0 and Time.get_ticks_usec()-slice_start >= frame_budget_usec:
				await get_tree().process_frame
				slice_start = Time.get_ticks_usec()
	if not geometry_fingerprint.is_empty():
		height_grid_cache[geometry_fingerprint] = heights
		height_grid_order.append(geometry_fingerprint)
		while height_grid_order.size() > HEIGHT_GRID_CACHE_LIMIT:
			height_grid_cache.erase(height_grid_order.pop_front())

func height_at(p: Vector2) -> float:
	if heights.is_empty():
		return 0.0
	var normalized: Vector2 = (p + Vector2.ONE * GRID_BORDER) / (1.0 + GRID_BORDER * 2.0)
	var gx: float = clampf(normalized.x * GRID_X, 0.0, float(GRID_X) - 0.0001)
	var gy: float = clampf(normalized.y * GRID_Y, 0.0, float(GRID_Y) - 0.0001)
	var x: int = floori(gx)
	var y: int = floori(gy)
	var fx: float = gx - x
	var fy: float = gy - y
	var index: int = y * (GRID_X + 1) + x
	var h00: float = heights[index]
	var h10: float = heights[index + 1]
	var h01: float = heights[index + GRID_X + 1]
	var h11: float = heights[index + GRID_X + 2]
	# Exactly the same diagonal as the ground mesh, not a second approximation.
	if fx + fy <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fy
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fy)

func world_point(p: Vector2) -> Vector3:
	var height: float = height_at(p)
	return Vector3((p.x - 0.5) * width, height, (p.y - 0.5) * depth + height / tan(deg_to_rad(elevation)))

func _ground_colour(p: Vector2) -> Color:
	var nearest: Dictionary = _road_projection(p, true)
	var road: float = 1.0 - smoothstep(ROAD_HALF_WIDTH * 0.5, ROAD_HALF_WIDTH * 1.8, float(nearest.distance))
	var clearing: float = 0.0
	for center in clearing_centers:
		clearing = maxf(clearing, 1.0 - smoothstep(0.3, 0.65, _scaled(p - center).length()))
	var growth: float = 0.66 + height_noise.get_noise_2d(p.x * width * 2.1, p.y * depth * 2.1) * 0.3
	var wetness: float = 0.0
	if _shallow_at(p):
		growth *= .12
		clearing = maxf(clearing,.88)
		wetness = .94
	for trace in history.get("traces", []):
		if trace is Dictionary:
			var radius: float = float(trace.get("scale",.18))*minf(width,depth)*.33
			var wear: float = 1.0-smoothstep(radius*.55,radius,_scaled(p-_point(trace)).length())
			clearing = maxf(clearing,wear*.83)
	if str(history.get("materialTheme", "forest_ground")) == "dry_earth":
		growth *= 0.62
	return Color(maxf(road, clearing), growth * (1.0 - clearing), wetness, 0.9)

func _build_ground(responsive: bool = false, frame_budget_usec: int = INTERACTIVE_FRAME_BUDGET_USEC) -> void:
	var slice_start: int = Time.get_ticks_usec()
	var rendered: bool = str(render_record.get("mode","native")) != "native"
	var art_material: ShaderMaterial = Materials.rendered_art(render_record,stage) if rendered else null
	if rendered and art_material == null:
		render_record["mode"] = "native"
		render_record["reason"] = "art_texture_decode_failed"
		render_record["distributionReady"] = false
		rendered = false
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normalized_uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var count: int = (GRID_X + 1) * (GRID_Y + 1)
	vertices.resize(count)
	normals.resize(count)
	tangents.resize(count * 4)
	colors.resize(count)
	uvs.resize(count)
	normalized_uvs.resize(count)
	for y in range(GRID_Y + 1):
		for x in range(GRID_X + 1):
			var index: int = y * (GRID_X + 1) + x
			var p: Vector2 = _grid_point(x,y)
			vertices[index] = world_point(p)
			colors[index] = _ground_colour(p) if str(render_record.get("mode","native")) == "native" else Color.WHITE
			uvs[index] = _scaled(p)
			normalized_uvs[index] = p
		if responsive and Time.get_ticks_usec()-slice_start >= frame_budget_usec:
			await get_tree().process_frame
			slice_start = Time.get_ticks_usec()
	for y in range(GRID_Y + 1):
		for x in range(GRID_X + 1):
			var index: int = y * (GRID_X + 1) + x
			var left: Vector3 = vertices[y*(GRID_X+1)+maxi(0,x-1)]
			var right: Vector3 = vertices[y*(GRID_X+1)+mini(GRID_X,x+1)]
			var north: Vector3 = vertices[maxi(0,y-1)*(GRID_X+1)+x]
			var south: Vector3 = vertices[mini(GRID_Y,y+1)*(GRID_X+1)+x]
			var tangent: Vector3 = (right-left).normalized()
			normals[index] = (south-north).cross(right-left).normalized()
			tangents[index*4] = tangent.x
			tangents[index*4+1] = tangent.y
			tangents[index*4+2] = tangent.z
			tangents[index*4+3] = -1.0
		if responsive and Time.get_ticks_usec()-slice_start >= frame_budget_usec:
			await get_tree().process_frame
			slice_start = Time.get_ticks_usec()
	for y in range(GRID_Y):
		for x in range(GRID_X):
			var a: int = y * (GRID_X + 1) + x
			var b: int = a + 1
			var c: int = a + GRID_X + 1
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = normalized_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	ground_mesh = MeshInstance3D.new()
	ground_mesh.name = "PhysicalTerrain"
	ground_mesh.mesh = mesh
	ground_mesh.material_override = art_material if rendered else Materials.terrain(str(history.get("materialTheme", "forest_ground")), str(history.get("groundSeason", "neutral")))
	if not rendered:
		ground_mesh.material_override = ground_mesh.material_override.duplicate()
		ground_mesh.material_override.set_shader_parameter("wetness",float(Weather.profile_for_stage(stage).get("wetness",0)))
	ground_mesh.layers = 1
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if rendered else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(ground_mesh)
	stats.meshNodes += 1
	stats.renderTrianglesUpperBound += GRID_X * GRID_Y * 2

func _build_roads() -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(0)
	var triangle_count: int = 0
	var junctions: Dictionary = {}
	for segment in road_segments:
		if bool(segment.side): continue
		var a: Vector2 = segment.a
		var b: Vector2 = segment.b
		var axis: Vector2 = _scaled(b-a)
		var normal: Vector2 = Vector2(-axis.y,axis.x).normalized()
		var half: float = ROAD_HALF_WIDTH
		var offset: Vector2 = normal*half/Vector2(width,depth)
		var polygon: PackedVector2Array = PackedVector2Array([a-offset,b-offset,b+offset,a+offset])
		triangle_count += _append_draped_road(tool,polygon,{"origin":a,"normal":normal,"radius":half,"radial":false})
		for endpoint in [a,b]:
			var key: String = "%.5f,%.5f" % [endpoint.x,endpoint.y]
			if not junctions.has(key) or float(junctions[key].radius) < half:
				junctions[key] = {"point":endpoint,"radius":half}
	for junction in junctions.values():
		var center: Vector2 = junction.point
		if _is_water(center):
			continue
		var polygon: PackedVector2Array = PackedVector2Array()
		for index in range(20):
			var angle: float = TAU*float(index)/20.0
			polygon.append(center+Vector2(cos(angle),sin(angle))*float(junction.radius)/Vector2(width,depth))
		triangle_count += _append_draped_road(tool,polygon,{"origin":center,"radius":junction.radius,"radial":true})
	if triangle_count > 0:
		tool.generate_normals()
		tool.generate_tangents()
		tool.index()
		var road: MeshInstance3D = MeshInstance3D.new()
		road.name = "AuthoredRoads"
		road.mesh = tool.commit()
		road.material_override = Materials.road(str(history.get("materialTheme","")) == "wet_mud")
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(road)
		stats.meshNodes += 1
	stats.roadTriangles = triangle_count
	stats.renderTrianglesUpperBound += triangle_count

func _append_draped_road(tool: SurfaceTool,polygon: PackedVector2Array,recipe: Dictionary) -> int:
	# Clip the road to the actual terrain triangles. Sampling independent road
	# strips across terrain diagonals causes visible holes at hills and bends.
	var lower: Vector2 = polygon[0]
	var upper: Vector2 = polygon[0]
	for point in polygon:
		lower = lower.min(point)
		upper = upper.max(point)
	var grid_size: Vector2 = Vector2(GRID_X,GRID_Y)
	var first: Vector2i = Vector2i(((lower+Vector2.ONE*GRID_BORDER)/(1.0+GRID_BORDER*2.0)*grid_size).floor())
	var last: Vector2i = Vector2i(((upper+Vector2.ONE*GRID_BORDER)/(1.0+GRID_BORDER*2.0)*grid_size).ceil())
	first.x = clampi(first.x,0,GRID_X-1)
	first.y = clampi(first.y,0,GRID_Y-1)
	last.x = clampi(last.x,0,GRID_X-1)
	last.y = clampi(last.y,0,GRID_Y-1)
	var count: int = 0
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var a: Vector2 = _grid_point(x,y)
			var b: Vector2 = _grid_point(x+1,y)
			var c: Vector2 = _grid_point(x,y+1)
			var d: Vector2 = _grid_point(x+1,y+1)
			for terrain_triangle in [PackedVector2Array([a,b,c]),PackedVector2Array([b,d,c])]:
				for clipped in Geometry2D.intersect_polygons(terrain_triangle,polygon):
					for index in range(1,clipped.size()-1):
						var points: Array[Vector2] = [clipped[0],clipped[index],clipped[index+1]]
						var area: float = (points[1]-points[0]).cross(points[2]-points[0])
						if absf(area) < .00000001:
							continue
						if area < 0:
							var swap: Vector2 = points[1]
							points[1] = points[2]
							points[2] = swap
						var middle: Vector2 = (points[0]+points[1]+points[2])/3.0
						var on_deck: bool = false
						for bridge in bridge_regions:
							if str(bridge.kind) != "ford" and bridge.rect.has_point(middle):
								on_deck = true
						if on_deck:
							continue
						for p in points:
							var relative: Vector2 = _scaled(p-Vector2(recipe.origin))
							var across: float = .5*(1.0-relative.length()/float(recipe.radius)) if bool(recipe.radial) else .5+relative.dot(Vector2(recipe.normal))/(2.0*float(recipe.radius))
							tool.set_color(Color(1,1,1.0 if _shallow_at(p) else 0.0,clampf(across,0,1)))
							tool.set_uv(_scaled(p))
							tool.add_vertex(world_point(p)+Vector3(0,ROAD_SURFACE_OFFSET,0))
						count += 1
	return count

func _build_water() -> void:
	for region in water_regions:
		var rect: Rect2 = region.rect
		var mesh: PlaneMesh = PlaneMesh.new()
		mesh.size = rect.size * Vector2(width, depth)
		mesh.subdivide_width = 12
		mesh.subdivide_depth = 12
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = "Water_" + str(region.kind)
		instance.mesh = mesh
		var center: Vector2 = rect.get_center()
		instance.position = Vector3((center.x - 0.5) * width, -0.055, (center.y - 0.5) * depth - 0.055 / tan(deg_to_rad(elevation)))
		var material: ShaderMaterial = Materials.water(str(region.kind)).duplicate()
		material.set_shader_parameter("shore_size",rect.size*Vector2(width,depth))
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		stats.meshNodes += 1
		stats.waterTriangles += 338
		stats.renderTrianglesUpperBound += 338

func _build_water_banks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value+9731
	for region in water_regions:
		var rect: Rect2 = region.rect
		for side in range(4):
			var along_x: bool = side < 2
			var length: float = rect.size.x*width if along_x else rect.size.y*depth
			var count: int = maxi(2,ceili(length/.72))
			for index in range(count):
				var t: float = (float(index)+rng.randf_range(.15,.85))/count
				var p: Vector2 = rect.position+Vector2(rect.size.x*t,0 if side == 0 else rect.size.y) if along_x else rect.position+Vector2(0 if side == 2 else rect.size.x,rect.size.y*t)
				p += Vector2(0,(-1 if side == 0 else 1)*rng.randf_range(.007,.016)) if along_x else Vector2((-1 if side == 2 else 1)*rng.randf_range(.004,.012),0)
				if not _scatter_clear(p,.64):
					continue
				var rock_size: float = rng.randf_range(.20,.45)
				_add_model("boulder_01",p,Vector3(rock_size,rock_size*.42,rock_size*.83),rng.randf_range(0,TAU))
				if index%3 == 0:
					_add_model("grass_medium_01",p,Vector3.ONE*.20,rng.randf_range(0,TAU),index%5)

func _build_shallow_crossings() -> void:
	for region in shallow_regions:
		var rect: Rect2 = region.rect
		var full: Rect2 = region.fullRect
		var sx: int = maxi(2,ceili(rect.size.x*width/.16))
		var sy: int = maxi(2,ceili(rect.size.y*depth/.16))
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(0)
		for y in range(sy):
			for x in range(sx):
				var a: Vector2 = rect.position+rect.size*Vector2(float(x)/sx,float(y)/sy)
				var b: Vector2 = rect.position+rect.size*Vector2(float(x+1)/sx,float(y)/sy)
				var c: Vector2 = rect.position+rect.size*Vector2(float(x)/sx,float(y+1)/sy)
				var d: Vector2 = rect.position+rect.size*Vector2(float(x+1)/sx,float(y+1)/sy)
				for point in [a,b,c,b,d,c]:
					var p: Vector2 = point
					tool.set_uv((p-full.position)/full.size)
					tool.add_vertex(world_point(p)+Vector3(0,.018,0))
		tool.generate_normals()
		tool.generate_tangents()
		tool.index()
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = "WalkableShallowRiver"
		instance.mesh = tool.commit()
		var material: ShaderMaterial = Materials.water("river").duplicate()
		material.set_shader_parameter("shore_size",full.size*Vector2(width,depth))
		material.set_shader_parameter("shallowness",1.0)
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		stats.meshNodes += 1
		stats.waterTriangles += sx*sy*2
		stats.renderTrianglesUpperBound += sx*sy*2

func _build_bridges() -> void:
	for bridge in bridge_regions:
		var rect: Rect2 = bridge.rect
		var center: Vector2 = rect.get_center()
		var size_world: Vector2 = rect.size * Vector2(width, depth)
		if str(bridge.kind) == "ford":
			for index in range(12):
				var p: Vector2 = rect.position + Vector2(0.12 + fmod(index * 0.273, 0.76), 0.10 + float(index) / 12.0 * 0.8) * rect.size
				_add_model("boulder_01", p, Vector3(0.14, 0.09, 0.12), index * 0.63)
			stats.bridgeCount += 1
			continue
		var along_x: bool = size_world.x > size_world.y
		var length: float = maxf(size_world.x, size_world.y)
		var across: float = minf(size_world.x, size_world.y)
		var yaw: float = PI * 0.5 if along_x else 0.0
		var base: Vector3 = world_point(center)
		var count: int = maxi(5, ceili(length / 0.12))
		for index in range(count):
			var position: Vector3 = base + Vector3(0, -0.043, (float(index) / maxf(count - 1, 1) - 0.5) * length).rotated(Vector3.UP, yaw)
			_box("wood", position, Vector3(across, 0.085, 0.125), yaw, Color(0.86, 0.84, 0.77))
		for side in [-1.0, 1.0]:
			_box("wood", base + Vector3(side * across * 0.51, 0.46, 0).rotated(Vector3.UP, yaw), Vector3(0.055, 0.065, length), yaw)
			for index in range(5):
				var position: Vector3 = base + Vector3(side * across * 0.51, 0.0, (float(index) / 4.0 - 0.5) * length).rotated(Vector3.UP, yaw)
				_box("wood", position + Vector3(0, 0.26, 0), Vector3(0.075, 0.64, 0.075), yaw)
		stats.bridgeCount += 1

func _build_landmarks() -> void:
	var supply_house_floors: Array[Vector2] = []
	for landmark in landmarks:
		var kind: String = str(landmark.get("kind", ""))
		var point: Vector2 = _point(landmark)
		structure_owner = kind+"@"+str(point)
		var scale_data: Dictionary = landmark.get("scale", {"w": 0.18, "h": 0.14})
		var size_world: Vector2 = Vector2(float(scale_data.get("w", 0.18)) * width, float(scale_data.get("h", 0.14)) * depth)
		var yaw: float = float(landmark.get("orientationRadians", 0.0))
		if kind in ["earthen_fort", "hill_fort", "low_hill_fort", "mountain_fort", "plain_fort", "field_fort", "temple_fort", "island_earthen_fort", "lowland_island_fort", "river_cliff_fort", "terrace_fort", "earthwork_castle_town"]:
			for objective in stage.get("objectives", []):
				if _point(objective).distance_to(point) < 0.025:
					yaw = _objective_yaw(point)
					break
			_build_fort(point, size_world, yaw, kind)
		elif kind in ["palisade", "earthen_wall", "outer_earthwork", "dry_earthwork", "siege_dike", "levee", "natural_levee"]:
			_build_wall(point, size_world, yaw, kind)
		elif kind in ["town", "camp", "camps", "siege_camp", "siege_camps"]:
			_build_settlement(point, size_world, yaw, kind)
		elif kind == "enemy_entry_camp":
			# The departure floor remains open. Small camp props sit behind it,
			# where the hostile column visibly enters the authored corridor.
			var edge: Vector2=(point+Vector2(-.035,-.022)).clamp(Vector2(.025,.025),Vector2(.975,.975))
			if not _is_water(edge) and _road_projection(edge).distance>.35:
				_add_supply(edge,yaw)
			objects.append({"kind":kind,"point":point,"physical":true})
		elif kind == "enemy_dock":
			structure_phase = "ground_surface"
			var dock: Vector3=world_point(point)
			for plank in range(7):
				_box("wood",dock+Vector3(float(plank-3)*.13,.02,0),Vector3(.12,.07,.42),0)
			objects.append({"kind":kind,"point":point,"physical":true})
			structure_phase = "structure"
		elif kind == "supply_camp":
			# Keep the original supply house behind its open objective floor.
			# A camp has no automatic gate; a legacy gate still owns its house.
			var camp_point: Vector2 = point
			var gate_owned: bool = false
			var defended_floor: bool = false
			for objective in stage.get("objectives", []):
				if _point(objective).distance_to(point) < 0.025:
					gate_owned = objective_presentation(objective) == "castle_gate"
					yaw = _objective_yaw(point)
					defended_floor = true
					break
			# Separate contacts may share one HP anchor. Their camp buildings
			# must sit behind each own road end, just like the central camp.
			if not defended_floor:
				for path in stage.get("paths", []):
					var points: Array = path.get("points", [])
					if points.size() < 2 or _point(points[-1]).distance_to(point) >= .025:
						continue
					var direction: Vector2 = _scaled(_point(points[-1])-_point(points[-2])).normalized()
					yaw = atan2(direction.x,direction.y)
					defended_floor = true
					break
			if defended_floor:
				camp_point += Vector2(sin(yaw),cos(yaw)) * Vector2(1.15/width,1.15/depth)
			var duplicate_floor: bool = false
			for existing_floor in supply_house_floors:
				if existing_floor.distance_to(camp_point) < .001:
					duplicate_floor = true
					break
			if not gate_owned and not duplicate_floor and _inside(camp_point) and not _is_water(camp_point):
				supply_house_floors.append(camp_point)
				_build_house(camp_point,yaw,.75,true)
				_add_supply(camp_point + Vector2(.024,-.012),yaw)
				objects.append({"kind":"supply_camp","point":camp_point,"objectiveFloor":point,"physical":true})
		elif kind in ["fields", "rolling_fields", "wetland_fields"]:
			structure_phase = "ground_surface"
			_build_fields(point, size_world, yaw)
			structure_phase = "structure"
		elif kind in ["dry_moat", "ridged_dry_moat", "grid_dry_moat"]:
			_build_moat_edges(point, size_world, yaw, kind)
		elif kind in ["stone_terrace", "river_terrace", "plateau"]:
			_build_terrace(point, size_world, yaw)
		structure_owner = ""
	for trace in history.get("traces", []):
		_build_trace(trace)

func _build_fort(point: Vector2, footprint: Vector2, yaw: float, kind: String) -> void:
	var width_local: float = clampf(footprint.x, 2.4, 4.4)
	var depth_local: float = clampf(footprint.y, 1.7, 3.4)
	var base: Vector3 = world_point(point)
	for side in [-1.0, 1.0]:
		var center: Vector3 = base + Vector3(side * width_local * 0.5, 0.0, depth_local * 0.18).rotated(Vector3.UP, yaw)
		_earth_bank(center, Vector3(0.6, 0.43, depth_local), yaw)
		_palisade(center + Vector3(0, 0.33, 0), depth_local, yaw, true)
	var back: Vector3 = base + Vector3(0, 0, depth_local * 0.65).rotated(Vector3.UP, yaw)
	_earth_bank(back, Vector3(width_local + 0.4, 0.5, 0.7), yaw)
	_palisade(back + Vector3(0, 0.40, 0), width_local, yaw + PI * 0.5, true)
	var tower_point: Vector2 = point + Vector2(width_local * 0.36 / width, depth_local * 0.39 / depth).rotated(yaw)
	if _road_projection(tower_point).distance > 0.65 and not _is_water(tower_point):
		_build_watchtower(tower_point, yaw, kind == "mountain_fort")
	objects.append({"kind": kind, "point": point, "physical": true})

func _build_wall(point: Vector2, footprint: Vector2, yaw: float, kind: String) -> void:
	var along_x: bool = footprint.x > footprint.y
	var rotation: float = yaw + (PI * 0.5 if along_x else 0.0)
	var length: float = clampf(maxf(footprint.x, footprint.y), 1.4, 6.0)
	var center: Vector3 = world_point(point)
	if kind == "palisade":
		_palisade(center, length, rotation, false)
	else:
		_earth_bank(center, Vector3(0.7 if kind != "siege_dike" else 1.0, 0.48, length), rotation)
		if kind in ["earthen_wall", "outer_earthwork", "dry_earthwork"]:
			_palisade(center + Vector3(0, 0.32, 0), length, rotation, true)
	objects.append({"kind": kind, "point": point, "physical": true})

func _build_settlement(point: Vector2, footprint: Vector2, yaw: float, kind: String) -> void:
	var count: int = 3 if kind == "town" else 2
	for index in range(count):
		var local: Vector2 = Vector2((float(index) - (count - 1) * 0.5) * 1.70 / width, 0.25 / depth).rotated(yaw)
		var p: Vector2 = point + local
		if _road_projection(p).distance > 1.15 and not _is_water(p):
			_build_house(p, yaw + index * 0.1, 0.85 if kind != "town" else 1.0, kind != "town")
			_add_supply(p + Vector2(0.025, 0.028), yaw)
	objects.append({"kind": kind, "point": point, "physical": true})

func _build_fields(point: Vector2, footprint: Vector2, yaw: float) -> void:
	var half: float = minf(footprint.x, 4.6) * 0.5
	var length: float = minf(footprint.y, 3.0)
	for index in range(8):
		var local: Vector2 = Vector2(lerpf(-half, half, float(index) / 7.0) / width, 0).rotated(yaw)
		var p: Vector2 = point + local
		if _road_projection(p).distance > 0.66 and not _is_water(p):
			_earth_bank(world_point(p), Vector3(0.075, 0.035, length), yaw)
	objects.append({"kind": "fields", "point": point, "physical": true})

func _build_moat_edges(point: Vector2, footprint: Vector2, yaw: float, kind: String) -> void:
	var length: float = clampf(footprint.x, 1.8, 4.8)
	for side in [-1.0, 1.0]:
		var p: Vector2 = point + Vector2(0, side * clampf(footprint.y, 0.5, 1.5) * 0.5 / depth).rotated(yaw)
		if _road_projection(p).distance > 0.75:
			_earth_bank(world_point(p), Vector3(length, 0.22, 0.38), yaw)
	if kind in ["ridged_dry_moat", "grid_dry_moat"]:
		for index in range(4):
			var p: Vector2 = point + Vector2((index - 1.5) * 0.7 / width, 0).rotated(yaw)
			if _road_projection(p).distance > 0.75:
				_earth_bank(world_point(p), Vector3(0.22, 0.20, minf(footprint.y, 1.5)), yaw)
	objects.append({"kind": kind, "point": point, "physical": true})

func _build_terrace(point: Vector2, footprint: Vector2, yaw: float) -> void:
	for index in range(9):
		var p: Vector2 = point + Vector2((float(index) / 8.0 - 0.5) * minf(footprint.x, 4.2) / width, -minf(footprint.y, 2.0) * 0.35 / depth).rotated(yaw)
		if _road_projection(p).distance > 0.70 and not _is_water(p):
			_add_model("boulder_01", p, Vector3(0.33, 0.23, 0.28), index * 0.5)

func _build_trace(trace: Variant) -> void:
	var point: Vector2 = Vector2(0.45, 0.73)
	var kind: String = "aftermath"
	if trace is Dictionary:
		point = _point(trace)
		kind = str(trace.get("kind", trace.get("id", "aftermath")))
	elif trace is String:
		kind = str(trace)
	for index in range(7):
		var p: Vector2 = point + Vector2(sin(index * 2.4) * 0.035, cos(index * 1.7) * 0.025)
		if _road_projection(p).distance > 0.45 and not _is_water(p):
			_box("wood", world_point(p) + Vector3(0, 0.07, 0), Vector3(0.1, 0.12, 0.65), index * 0.73, Color(0.35, 0.31, 0.27))
	if kind == "weathered_earthwork":
		for index in range(5):
			var p: Vector2 = point+Vector2((index-2.0)*.032,sin(index*2.1)*.013)
			if _road_projection(p).distance > .6 and not _is_water(p):
				_earth_bank(world_point(p),Vector3(.47,.09+.11*fmod(index*.47,1.0),.62),index*.32)
	objects.append({"kind": "trace:" + kind, "point": point, "physical": true})

func objective_presentation(objective: Dictionary) -> String:
	if bool(objective.get("mobile", false)):
		return "supply_cart"
	var presentation: String = str(objective.get("presentation", "castle_gate"))
	return presentation if presentation in ["castle_gate", "field_camp", "defense_line"] else "castle_gate"

func _build_objectives() -> void:
	for objective in stage.get("objectives", []):
		var point: Vector2 = _point(objective)
		var presentation: String = objective_presentation(objective)
		if presentation == "supply_cart":
			# Troops renders the live cart at its escort position. Terrain must
			# leave this floor open instead of constructing a permanent gate.
			objects.append({"kind":"moving_supply_cart_floor","point":point,"id":objective.get("id","main"),"presentation":presentation,"physical":false})
			continue
		var yaw: float = _objective_yaw(point)
		structure_owner = "objective:"+str(objective.get("id","main"))
		if presentation == "castle_gate":
			var direction: Vector2 = Vector2(sin(yaw),cos(yaw))
			_build_gate(point, yaw)
			var behind: Vector2 = point + direction * Vector2(1.15/width,1.15/depth)
			if _inside(behind) and not _is_water(behind):
				_build_house(behind, yaw, 0.75, true)
				_add_supply(behind + Vector2(0.024, -0.012), yaw)
		else:
			# A shared HP anchor is not necessarily a gate or a road junction.
			# Camps and defenses are authored landmarks; retain their distinct
			# contact floors rather than auto-building a house over the center.
			_banner(world_point(point), yaw, true)
		objects.append({"kind":"friendly_objective","point":point,"id":objective.get("id","main"),"presentation":presentation,"physical":true})
		for path in stage.get("paths", []):
			if str(path.get("objectiveId","main")) != str(objective.get("id","main")):
				continue
			var points: Array = path.get("points", [])
			if not points.is_empty():
				objects.append({"kind":"defended_contact_floor","point":_point(points[-1]),"objectiveId":objective.get("id","main"),"pathId":path.get("id",""),"physical":false})
		structure_owner = ""

func _objective_yaw(point: Vector2) -> float:
	var direction: Vector2 = Vector2(0,1)
	var best: float = 100.0
	for path in stage.get("paths", []):
		var points: Array = path.get("points", [])
		if points.size() >= 2:
			var end: Vector2 = _point(points[-1])
			if end.distance_to(point) < best:
				best = end.distance_to(point)
				direction = _scaled(end-_point(points[-2])).normalized()
	return atan2(direction.x,direction.y)

func _build_gate(point: Vector2, yaw: float) -> void:
	var base: Vector3 = world_point(point)
	var gate_width: float = 1.65
	for side in [-1.0, 1.0]:
		var post: Vector3 = base + Vector3(side * gate_width * 0.5, 0, 0).rotated(Vector3.UP, yaw)
		_box("wood", post + Vector3(0, 0.92, 0), Vector3(0.16, 1.84, 0.17), yaw, Color(0.46, 0.42, 0.35))
		_box("rock", post + Vector3(0, 0.055, 0), Vector3(0.32, 0.11, 0.32), yaw)
		var wall_base: Vector3 = base + Vector3(side * 1.70, 0, 0.22).rotated(Vector3.UP, yaw)
		_earth_bank(wall_base, Vector3(1.20, 0.38, 0.60), yaw)
		_palisade(wall_base + Vector3(0, 0.30, 0), 1.20, yaw + PI * 0.5, true)
	structure_phase = "gate_upper"
	_box("wood", base + Vector3(0, 1.66, 0), Vector3(2.01, 0.17, 0.22), yaw, Color(0.46, 0.42, 0.35))
	_box("wood", base + Vector3(0, 1.81, 0), Vector3(1.95, 0.05, 0.55), yaw, Color(0.59, 0.55, 0.43))
	_roof(base + Vector3(0, 1.81, 0), Vector3(2.04, 0.40, 0.88), yaw)
	structure_phase = "structure"
	_banner(base + Vector3(1.30, 0, -0.20).rotated(Vector3.UP, yaw), yaw, true)
	stats.gateCount += 1

func _build_watchtower(point: Vector2, yaw: float, tall: bool = false) -> void:
	var base: Vector3 = world_point(point)
	var height: float = 1.62 if tall else 1.30
	for x in [-0.43, 0.43]:
		for z in [-0.40, 0.40]:
			_box("wood", base + Vector3(x, height * 0.5, z).rotated(Vector3.UP, yaw), Vector3(0.075, height, 0.075), yaw)
	structure_phase = "gate_upper"
	_box("wood", base + Vector3(0, height, 0), Vector3(1.15, 0.075, 1.04), yaw)
	for side in [-1.0, 1.0]:
		_box("wood", base + Vector3(side * 0.51, height + 0.25, 0).rotated(Vector3.UP, yaw), Vector3(0.045, 0.045, 1.05), yaw)
		_box("wood", base + Vector3(side * 0.51, height + 0.38, 0).rotated(Vector3.UP, yaw), Vector3(0.045, 0.045, 1.05), yaw)
	_roof(base + Vector3(0, height + 0.55, 0), Vector3(1.45, 0.35, 1.28), yaw)
	structure_phase = "structure"
	objects.append({"kind": "watchtower", "point": point, "physical": true})

func _build_house(point: Vector2, yaw: float, scale_value: float, camp: bool) -> void:
	var requested_floor: Vector2 = point
	var open_floor: Vector2 = _open_house_floor(point, scale_value, yaw)
	if not open_floor.is_finite():
		return
	point = open_floor
	var base: Vector3 = world_point(point)
	var size_value: Vector3 = Vector3(1.40, 0.83, 1.15) * scale_value
	var material: String = "wood" if camp else "earth"
	_box(material, base + Vector3(0, size_value.y * 0.5, 0), size_value, yaw, Color(0.76, 0.72, 0.60) if camp else Color(1.20, 1.13, 0.91))
	for side in [-1.0, 1.0]:
		_box("wood", base + Vector3(side * size_value.x * 0.5, size_value.y * 0.5, -size_value.z * 0.52).rotated(Vector3.UP, yaw), Vector3(0.065, size_value.y, 0.055), yaw, Color(0.37, 0.31, 0.25))
	_box("wood", base + Vector3(0, size_value.y * 0.42, -size_value.z * 0.513).rotated(Vector3.UP, yaw), Vector3(size_value.x * 0.27, size_value.y * 0.75, 0.03), yaw, Color(0.35, 0.30, 0.24))
	_roof(base + Vector3(0, size_value.y, 0), Vector3(size_value.x * 1.32, 0.44 * scale_value, size_value.z * 1.34), yaw)
	objects.append({"kind":"house_floor","point":point,"requestedPoint":requested_floor,"physical":true})

func _house_floor_open(point: Vector2, scale_value: float) -> bool:
	# The roof overhang is wider than the walls. Keep its complete footprint
	# and a soldier's body clear of both visible roads and concealed approaches.
	var roof_radius: float = Vector2(1.40*1.32,1.15*1.34).length()*.5*scale_value
	if not _inside(point) or _is_water(point):
		return false
	for step in range(8):
		var angle: float = TAU*step/8.0
		if _is_water(point+Vector2(cos(angle)/width,sin(angle)/depth)*roof_radius):
			return false
	var world_floor: Vector2 = _scaled(point)
	for segment in road_segments:
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(world_floor,_scaled(segment.a),_scaled(segment.b))
		var corridor: float = .18 if bool(segment.side) else ROAD_HALF_WIDTH
		if world_floor.distance_to(nearest) < roof_radius+corridor+.25:
			return false
	for index in range(clearing_centers.size()):
		if _scaled(point-clearing_centers[index]).length() < clearing_radii[index]+roof_radius+.25:
			return false
	return true

func _open_house_floor(requested: Vector2, scale_value: float, yaw: float) -> Vector2:
	if _house_floor_open(requested,scale_value):
		return requested
	# Move scenery locally instead of bending a soldier's authored road. The
	# same deterministic search also keeps camp houses off neighbouring ends.
	for distance in [.40,.80,1.20,1.60,2.00]:
		for step in range(16):
			var angle: float = yaw+TAU*step/16.0
			var candidate: Vector2 = requested+Vector2(sin(angle)/width,cos(angle)/depth)*float(distance)
			if _house_floor_open(candidate,scale_value):
				return candidate
	return Vector2(INF,INF)

func _add_supply(point: Vector2, yaw: float) -> void:
	if not _inside(point) or _is_water(point):
		return
	var base: Vector3 = world_point(point)
	for index in range(4):
		var plank: bool = index == 3
		var size_value: Vector3 = Vector3(.72,.035,.50) if plank else Vector3(.22,.26,.24)
		var offset: Vector3 = Vector3(.10,0,.32) if plank else Vector3(index*.19,0,0)
		var foot: Vector2 = _normalized_foot(base+offset.rotated(Vector3.UP,yaw))
		var radius: float = Vector2(size_value.x,size_value.z).length()*.5
		if not _inside(foot) or _is_water(foot) or _road_projection(foot).distance < ROAD_HALF_WIDTH+radius+.12:
			continue
		var occupied: bool = false
		for clearing_index in range(clearing_centers.size()):
			if _scaled(foot-clearing_centers[clearing_index]).length() < clearing_radii[clearing_index]+radius+.20:
				occupied = true
				break
		if occupied:
			continue
		# Sample each prop's actual foot, rather than carrying the camp center's
		# height onto a sloping road and lifting a plank into a soldier's torso.
		var center: Vector3 = world_point(foot)+Vector3(0,size_value.y*.5,0)
		_box("wood",center,size_value,yaw,Color.WHITE if plank else Color(1.01,.92,.72))

func _palisade(base: Vector3, length: float, yaw: float, short: bool) -> void:
	var count: int = maxi(3, ceili(length / 0.115))
	var height: float = 0.71 if short else 0.98
	for index in range(count):
		var offset: Vector3 = Vector3(0, 0, (float(index) / maxf(count - 1, 1) - 0.5) * length).rotated(Vector3.UP, yaw)
		var position: Vector3 = base + offset + Vector3(0, height * 0.5, 0)
		var p: Vector2 = _normalized_foot(base+offset)
		if _road_projection(p).distance < 0.55 or _is_water(p):
			continue
		position = world_point(p)+Vector3(0,maxf(0.0,base.y-height_at(_normalized_foot(base)))+height*.5,0)
		var variation: float = 0.94 + 0.08 * sin(index * 4.17)
		_add_batch("stake", _stake_mesh(), _structural_material("wood", Color(0.71, 0.67, 0.56)), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.085, height * variation, 0.085)), position))
	var rails: int = maxi(2,ceili(length/.44))
	for index in range(rails):
		var local: Vector3 = Vector3(.045,0,(float(index+.5)/rails-.5)*length).rotated(Vector3.UP,yaw)
		var p: Vector2 = _normalized_foot(base+local)
		if _road_projection(p).distance < 0.55 or _is_water(p):
			continue
		var foot: Vector3 = world_point(p)+Vector3(0,maxf(0.0,base.y-height_at(_normalized_foot(base))),0)
		_box("wood",foot+Vector3(0,height*.28,0),Vector3(.055,.055,length/rails+.01),yaw)
		_box("wood",foot+Vector3(0,height*.65,0),Vector3(.055,.055,length/rails+.01),yaw)

func _banner(base: Vector3, yaw: float, friendly: bool) -> void:
	var previous_phase: String = structure_phase
	structure_phase = "banner"
	_box("wood", base + Vector3(0, 1.00, 0), Vector3(0.035, 2.0, 0.035), yaw)
	var cloth: BoxMesh = _unit_box()
	var cloth_material: Material = Materials.cloth("friendly" if friendly else "enemy") if str(render_record.get("mode","native"))=="native" else null
	_add_batch("banner:" + str(friendly), cloth, cloth_material, Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.36, 0.80, 0.008)), base + Vector3(0.17, 1.48, 0).rotated(Vector3.UP, yaw)))
	var crest: Material = _structural_material("crest", Color(0.90, 0.80, 0.52))
	_add_batch("crest", _unit_box(), crest, Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.18, 0.15, 0.014)), base + Vector3(0.17, 1.53, -0.005).rotated(Vector3.UP, yaw)))
	structure_phase = previous_phase

func _roof(base: Vector3, size_value: Vector3, yaw: float) -> void:
	var previous_phase: String = structure_phase
	structure_phase = "roof"
	var mesh: ArrayMesh = _roof_mesh()
	_add_batch("roof", mesh, _structural_material("wood", Color(0.71, 0.66, 0.53)), Transform3D(Basis(Vector3.UP, yaw).scaled_local(size_value), base))
	_box("wood", base + Vector3(0, size_value.y * 0.98, 0), Vector3(size_value.x * 1.03, 0.045, 0.055), yaw, Color(0.29, 0.30, 0.26))
	for side in [-1.0, 1.0]:
		_box("wood", base + Vector3(0, 0, side * size_value.z * 0.5).rotated(Vector3.UP, yaw), Vector3(size_value.x * 1.04, 0.055, 0.04), yaw, Color(0.31, 0.32, 0.27))
	structure_phase = previous_phase

func _earth_bank(base: Vector3, size_value: Vector3, yaw: float) -> void:
	var previous_owner: String = structure_owner
	if structure_owner.is_empty() and size_value.y > .08:
		structure_owner = "bank@"+str(base)
	var along_x: bool = size_value.x > size_value.z
	var length: float = maxf(size_value.x,size_value.z)
	var pieces: int = maxi(1,ceili(length/.43))
	var axis: Vector3 = Vector3.RIGHT if along_x else Vector3.BACK
	for index in range(pieces):
		var offset: Vector3 = (axis*(float(index+.5)/pieces-.5)*length).rotated(Vector3.UP,yaw)
		var p: Vector2 = _normalized_foot(base+offset)
		var piece_size: Vector3 = size_value
		if along_x:
			piece_size.x = length/pieces+.012
		else:
			piece_size.z = length/pieces+.012
		# A center outside the road can still leave half a bank on the lane.
		var piece_radius: float = Vector2(piece_size.x,piece_size.z).length()*.5
		if _road_projection(p).distance < ROAD_HALF_WIDTH+piece_radius+.12 or _is_water(p):
			continue
		_add_batch("earth_bank",_bank_mesh(),_structural_material("earth",Color(.90,.80,.60)),Transform3D(Basis(Vector3.UP,yaw).scaled_local(piece_size),world_point(p)))
	structure_owner = previous_owner

func _normalized_foot(value: Vector3) -> Vector2:
	return Vector2(value.x/width+.5,(value.z-value.y/tan(deg_to_rad(elevation)))/depth+.5)

func _box(family: String, center: Vector3, size_value: Vector3, yaw: float, tint: Color = Color.WHITE) -> void:
	_add_batch("box:" + family + ":" + tint.to_html(), _unit_box(), _structural_material(family, tint), Transform3D(Basis(Vector3.UP, yaw).scaled_local(size_value), center))

func _structural_material(family: String, tint: Color) -> Material:
	# Rendered artwork already supplies these invisible meshes' appearance.
	# Retain the physical parts without decoding PBR textures to discard them.
	return Materials.surface(family,tint) if str(render_record.get("mode","native"))=="native" else null

func _unit_box() -> BoxMesh:
	if not primitive_cache.has("box"):
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3.ONE
		primitive_cache.box = mesh
	return primitive_cache.box

func _stake_mesh() -> CylinderMesh:
	if not primitive_cache.has("stake"):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.12
		mesh.bottom_radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 6
		mesh.rings = 1
		primitive_cache.stake = mesh
	return primitive_cache.stake

func _roof_mesh() -> ArrayMesh:
	if primitive_cache.has("roof"):
		return primitive_cache.roof
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	_add_quad(tool, Vector3(-0.5,0,-0.5), Vector3(0.5,0,-0.5), Vector3(0.5,1,0), Vector3(-0.5,1,0))
	_add_quad(tool, Vector3(-0.5,1,0), Vector3(0.5,1,0), Vector3(0.5,0,0.5), Vector3(-0.5,0,0.5))
	_add_triangle(tool, Vector3(-0.5,0,-0.5), Vector3(-0.5,1,0), Vector3(-0.5,0,0.5))
	_add_triangle(tool, Vector3(0.5,0,0.5), Vector3(0.5,1,0), Vector3(0.5,0,-0.5))
	tool.generate_normals()
	tool.generate_tangents()
	primitive_cache.roof = tool.commit()
	return primitive_cache.roof

func _bank_mesh() -> ArrayMesh:
	if primitive_cache.has("bank"):
		return primitive_cache.bank
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var a: Vector3 = Vector3(-0.5,0,-0.5)
	var b: Vector3 = Vector3(0.5,0,-0.5)
	var c: Vector3 = Vector3(0.5,0,0.5)
	var d: Vector3 = Vector3(-0.5,0,0.5)
	var aa: Vector3 = Vector3(-0.3,1,-0.4)
	var bb: Vector3 = Vector3(0.3,1,-0.4)
	var cc: Vector3 = Vector3(0.3,1,0.4)
	var dd: Vector3 = Vector3(-0.3,1,0.4)
	for quad in [[a,b,bb,aa],[b,c,cc,bb],[c,d,dd,cc],[d,a,aa,dd],[aa,bb,cc,dd]]:
		_add_quad(tool, quad[0], quad[1], quad[2], quad[3])
	tool.generate_normals()
	tool.generate_tangents()
	primitive_cache.bank = tool.commit()
	return primitive_cache.bank

func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var points: Array[Vector3] = [a,b,c,a,c,d]
	var uvs: Array[Vector2] = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]
	for index in range(6):
		tool.set_uv(uvs[index])
		tool.add_vertex(points[index])

func _add_triangle(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3) -> void:
	for pair in [[a,Vector2(0,0)],[b,Vector2(.5,1)],[c,Vector2(1,0)]]:
		tool.set_uv(pair[1])
		tool.add_vertex(pair[0])

func _add_batch(key: String, mesh: Mesh, material: Material, transform_value: Transform3D) -> void:
	if not structure_owner.is_empty():
		structural_parts.append({"key":key,"mesh":mesh,"transform":transform_value,"owner":structure_owner,"phase":structure_phase})
	if str(render_record.get("mode","native"))!="native": return
	if not batches.has(key):
		batches[key] = {"mesh": mesh, "material": material, "transforms": []}
	batches[key].transforms.append(transform_value)

func _commit_batches() -> void:
	for key in batches:
		var info: Dictionary = batches[key]
		var transforms: Array = info.transforms
		if transforms.is_empty():
			continue
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = info.mesh
		multi.instance_count = transforms.size()
		for index in range(transforms.size()):
			multi.set_instance_transform(index, transforms[index])
			multi.set_instance_custom_data(index,Color(fmod(index*0.317,1.0),fmod(index*0.731,1.0),0,0))
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = str(key).validate_node_name()
		instance.multimesh = multi
		if info.material != null:
			instance.material_override = info.material
		instance.layers = 1
		instance.lod_bias = 0.55
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(instance)
		stats.batches += 1
		stats.instances += transforms.size()
		stats.renderTrianglesUpperBound += _mesh_triangles(info.mesh) * transforms.size()

func _mesh_triangles(mesh: Mesh) -> int:
	var count: int = 0
	for index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
	return count

func _mesh_vertices(mesh: Mesh) -> int:
	var count: int = 0
	for index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(index)
		count += arrays[Mesh.ARRAY_VERTEX].size()
	return count

func _build_obstacles() -> void:
	for obstacle in stage.get("obstacles", []):
		var point: Vector2 = _point(obstacle)
		if _is_water(point) or _road_projection(point).distance < 0.75:
			continue
		var radius: float = float(obstacle.get("r", 0.035)) * minf(width, depth)
		_add_model("boulder_01", point, Vector3(radius * 0.8, radius * 0.5, radius * 0.7), point.x * 8.0)
		for index in range(2):
			var p: Vector2 = point + Vector2(sin(index * 3.8) * 0.013, cos(index * 3.8) * 0.014)
			_add_model("shrub_01", p, Vector3.ONE * 0.35, index * 0.7)
		for index in range(3):
			var angle: float = index*2.28+point.x*7.0
			var p: Vector2 = point+Vector2(cos(angle)*radius*.43/width,sin(angle)*radius*.43/depth)
			if _road_projection(p).distance > .9:
				_add_model("boulder_01",p,Vector3(radius*.62,radius*.56,radius*.60),angle)
		objects.append({"kind": "blocking_obstacle", "point": point, "radius": radius, "physical": true})

func _inside(p: Vector2) -> bool:
	return p.x > 0.02 and p.y > 0.025 and p.x < 0.975 and p.y < 0.975

func _weather_detail_clear(p: Vector2) -> bool:
	if not _inside(p) or _is_water(p): return false
	for crossing in bridge_regions:
		if crossing.rect.grow(.018).has_point(p): return false
	for index in range(clearing_centers.size()):
		if _scaled(p-clearing_centers[index]).length()<maxf(.70,clearing_radii[index]+.20): return false
	for obstacle in stage.get("obstacles",[]):
		if p.distance_to(_point(obstacle))<float(obstacle.get("r",.04))+.012: return false
	return _road_projection(p).distance>.22

func _is_water(p: Vector2) -> bool:
	for bridge in bridge_regions:
		if bridge.rect.has_point(p):
			return false
	for region in water_regions:
		if region.rect.has_point(p):
			return true
	return false

func _scatter_clear(p: Vector2, minimum_road_distance: float) -> bool:
	if not _inside(p) or _is_water(p) or _road_projection(p).distance < minimum_road_distance:
		return false
	for index in range(clearing_centers.size()):
		if _scaled(p-clearing_centers[index]).length() < maxf(.72,clearing_radii[index]+.35):
			return false
	for landmark in landmarks:
		if str(landmark.get("kind", "")) in ["town", "camp", "camps", "earthen_fort", "hill_fort", "mountain_fort", "plain_fort", "temple_fort", "siege_camp"] and _scaled(p - _point(landmark)).length() < 1.8:
			return false
	return true

func _tree_view_clear(p: Vector2, tree_height: float) -> bool:
	# The camera is fixed. Keep projected crowns out of combat lanes and tower
	# clearings instead of allowing foreground foliage to hide whole squads.
	var crown_radius: float = tree_height*.40
	for tier in [.42,.65,.86]:
		var projected: Vector2 = p-Vector2(0,tree_height*float(tier)/tan(deg_to_rad(elevation))/depth)
		if _road_projection(projected).distance < ROAD_HALF_WIDTH+crown_radius:
			return false
		for index in range(clearing_centers.size()):
			if _scaled(projected-clearing_centers[index]).length() < maxf(.36,clearing_radii[index])+crown_radius:
				return false
	return true

func _build_scatter() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var theme: String = str(history.get("materialTheme", "forest_ground"))
	var tree_limit: int = 44 if theme == "forest_ground" else 19
	var placed: int = 0
	var clusters: Array[Vector2] = [Vector2(.075,.10),Vector2(.32,.055),Vector2(.74,.06),Vector2(.96,.30),Vector2(.955,.79),Vector2(.73,.95),Vector2(.31,.96),Vector2(.08,.82)]
	for feature in height_features:
		clusters.append(_point(feature))
	for obstacle in stage.get("obstacles",[]):
		clusters.append(_point(obstacle))
	for attempt in range(400):
		if placed >= tree_limit:
			break
		var cluster: Vector2 = clusters[rng.randi_range(0,clusters.size()-1)]
		var p: Vector2 = cluster+Vector2(rng.randfn(0,.059),rng.randfn(0,.052))
		if not _scatter_clear(p, 1.0):
			continue
		var height: float = rng.randf_range(2.2, 3.6)
		if not _tree_view_clear(p,height):
			continue
		_add_model("pine_sapling_small", p, Vector3.ONE * height, rng.randf_range(0,TAU), placed % 3)
		_add_canopy(p,height,rng)
		stats.treeCount += 1
		placed += 1
	for attempt in range(40):
		var cluster: Vector2 = clusters[rng.randi_range(0,clusters.size()-1)]
		var p: Vector2 = cluster+Vector2(rng.randfn(0,.051),rng.randfn(0,.047))
		if _scatter_clear(p,1.02):
			_add_model("boulder_01",p,Vector3(rng.randf_range(.72,1.18),rng.randf_range(.49,.94),rng.randf_range(.68,1.1)),rng.randf_range(0,TAU))
	for attempt in range(150):
		var p: Vector2 = Vector2(rng.randf_range(0.01,0.99), rng.randf_range(0.01,0.99))
		if not _scatter_clear(p, 0.46):
			continue
		if attempt % 4 == 0:
			_add_model("boulder_01", p, Vector3.ONE * rng.randf_range(0.18,0.45), rng.randf_range(0,TAU))
		elif attempt % 3 == 0:
			_add_model("shrub_01", p, Vector3.ONE * rng.randf_range(0.23,0.55), rng.randf_range(0,TAU))
		else:
			_add_model("grass_medium_01", p, Vector3.ONE * rng.randf_range(0.13,0.26), rng.randf_range(0,TAU), attempt % 5)

func _model_variants(id: String) -> Array:
	if model_cache.has(id):
		return model_cache[id]
	var result: Array = []
	var path: String = MODEL_ROOT + id + "/" + id + "_1k.gltf"
	if not ResourceLoader.exists(path):
		model_cache[id] = result
		return result
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		model_cache[id] = result
		return result
	var temporary: Node = scene.instantiate()
	var meshes: Array = temporary.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var original: Mesh = node.mesh
		if original == null:
			continue
		var bounds: AABB = original.get_aabb()
		var extent: float = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z))
		var offset: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		var optimized: Mesh = _optimized_model_mesh(original, id)
		result.append({"mesh": optimized, "offset": offset, "extent": maxf(extent, 0.01), "originalTriangles": _mesh_triangles(original),"sourceVertices":_mesh_vertices(original),"uploadedVertices":_mesh_vertices(optimized)})
		if result.size() >= 6:
			break
	temporary.free()
	model_cache[id] = result
	return result

func _physical_contract(value: Dictionary = {}) -> Dictionary:
	# Labels and identifiers cannot make duplicate scenery look unique.
	var source: Dictionary = stage if value.is_empty() else value
	var historical: Dictionary = source.get("historicalBattlefield",{})
	var result: Dictionary = {"paths": [], "sideAmbushEntrances": [], "objectives": [], "buildZones": [], "obstacles": [], "water": [], "bridges": [], "landmarks": [], "heightFeatures": [], "traces": [], "ambushClearings": []}
	result["roadHalfWidthWorld"] = ROAD_HALF_WIDTH
	for path in source.get("paths",[]):
		result.paths.append(_shape_fields(path.get("points",[]),["x","y"]))
	for entry in source.get("sideAmbushEntrances",[]):
		result.sideAmbushEntrances.append({"point":_shape_fields([entry.get("point",{})],["x","y"]),"connectionPoints":_shape_fields(entry.get("connectionPoints",[]),["x","y"])})
	result.objectives = _shape_fields(source.get("objectives",[]),["x","y","mobile","presentation"])
	result.buildZones = _shape_fields(source.get("buildZones",[]),["x","y","r","elevation"])
	result.obstacles = _shape_fields(source.get("obstacles",[]),["x","y","r","blockPlacement"])
	if not source.get("water",{}).is_empty():
		result.water.append(_shape_fields([source.water],["x","y","w","h","kind"])[0])
	result.water.append_array(_shape_fields(historical.get("waterFeatures",[]),["x","y","w","h","kind","blocksMovement"]))
	result.bridges = _shape_fields(source.get("bridges",[]),["x","y","w","h","kind"])
	result.landmarks = _shape_fields(historical.get("sceneLandmarks",historical.get("landmarkLabels",[])),["x","y","kind","scale","heightWorld","orientationRadians"])
	result.heightFeatures = _shape_fields(_resolved_height_features(historical),["x","y","w","h","kind","amplitudeWorld","orientationRadians"])
	result.traces = _shape_fields(historical.get("traces",[]),["x","y","kind","scale"])
	result.ambushClearings = _shape_fields(historical.get("ambushClearings",[]),["x","y","r","entry"])
	result["sceneBiome"] = historical.get("sceneBiome",historical.get("terrain",{}).get("key",""))
	if historical.has("terrainLayout"):
		result["terrainLayout"] = historical.terrainLayout.duplicate(true)
	if historical.has("heightLimitWorld"):
		result["heightLimitWorld"] = historical.heightLimitWorld
	return result

func _shape_fields(values: Array, keys: Array) -> Array:
	var result: Array = []
	for value in values:
		if not value is Dictionary:
			continue
		var shape: Dictionary = {}
		for key in keys:
			if value.has(key):
				shape[key] = value[key]
		result.append(shape)
	return result

func _add_canopy(point: Vector2, tree_height: float, rng: RandomNumberGenerator) -> void:
	var base: Vector3 = world_point(point)
	for tier in range(4):
		var angle: float = rng.randf_range(0,TAU)
		var spread: float = tree_height * (0.18 if tier < 3 else 0.06)
		var center: Vector3 = base + Vector3(cos(angle)*spread,tree_height*(0.50+tier*0.12),sin(angle)*spread)
		var diameter: float = tree_height * (0.44 if tier < 3 else 0.34)
		for card in range(3):
			var variant: int = posmod(tier+card+seed_value,4)
			var mesh: ArrayMesh = _foliage_mesh(variant)
			var tilt: float = 0.24 if card == 0 else rng.randf_range(0.68,1.10)
			var rotation: Basis = Basis(Vector3.UP,angle+card*2.08) * Basis(Vector3.RIGHT,tilt)
			var scale_value: Vector3 = Vector3(diameter,diameter*.60,diameter*.77)
			_add_batch("canopy:"+str(variant),mesh,Materials.foliage(),Transform3D(rotation.scaled_local(scale_value),center))

func _foliage_mesh(variant: int) -> ArrayMesh:
	var key: String = "canopy:"+str(variant)
	if primitive_cache.has(key):
		return primitive_cache[key]
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(0)
	var tile: Vector2 = Vector2(float(variant%2),float(variant/2)) * .5
	for y in range(3):
		for x in range(3):
			var a: Vector2 = Vector2(float(x)/3.0,float(y)/3.0)
			var b: Vector2 = Vector2(float(x+1)/3.0,float(y)/3.0)
			var c: Vector2 = Vector2(float(x)/3.0,float(y+1)/3.0)
			var d: Vector2 = Vector2(float(x+1)/3.0,float(y+1)/3.0)
			for uv in [a,b,c,b,d,c]:
				var local: Vector2 = (Vector2(uv)-Vector2(.5,.5)) * 2.0
				var dome: float = .22 * maxf(0.0,1.0-local.length_squared()*.7)
				tool.set_uv(tile+Vector2(.012,.012)+Vector2(uv)*.476)
				tool.add_vertex(Vector3(local.x*.5,dome,local.y*.5))
	tool.generate_normals()
	tool.generate_tangents()
	tool.index()
	var result: ArrayMesh = tool.commit()
	primitive_cache[key] = result
	return result

func _optimized_model_mesh(original: Mesh, id: String) -> ArrayMesh:
	# Imported source scans contain hundreds of thousands of triangles. Use
	# Godot's actual meshoptimizer LODs once, preserving normals, UVs and masks.
	# MultiMesh then renders the chosen silhouette with shared materials.
	var importer: ImporterMesh = ImporterMesh.new()
	for surface_index in range(original.get_surface_count()):
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, original.surface_get_arrays(surface_index), [], {}, original.surface_get_material(surface_index))
	importer.generate_lods(25.0, 60.0, [])
	var target_triangles: int = 1800
	if id == "pine_sapling_small":
		target_triangles = 2200
	elif id == "boulder_01":
		target_triangles = 900
	elif id == "grass_medium_01":
		target_triangles = 160
	var result: ArrayMesh = ArrayMesh.new()
	for surface_index in range(importer.get_surface_count()):
		var arrays: Array = importer.get_surface_arrays(surface_index)
		var selected: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for lod_index in range(importer.get_surface_lod_count(surface_index)):
			var candidate: PackedInt32Array = importer.get_surface_lod_indices(surface_index, lod_index)
			if candidate.size() > 0 and (selected.is_empty() or candidate.size() < selected.size()):
				selected = candidate
			if selected.size() <= target_triangles * 3:
				break
		if not selected.is_empty():
			arrays[Mesh.ARRAY_INDEX] = selected
			arrays = _compact_surface_vertices(arrays)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface_index, importer.get_surface_material(surface_index))
	return result

func _compact_surface_vertices(arrays: Array) -> Array:
	# LOD indices alone leave the scan's unused source vertices in GPU memory.
	# Keep every vertex attribute, but upload only vertices that can be drawn.
	var original_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var retained: PackedInt32Array = PackedInt32Array()
	var remapped: PackedInt32Array = PackedInt32Array()
	var lookup: Dictionary = {}
	remapped.resize(original_indices.size())
	for index in range(original_indices.size()):
		var source: int = original_indices[index]
		if not lookup.has(source):
			lookup[source] = retained.size()
			retained.append(source)
		remapped[index] = int(lookup[source])
	for slot in range(Mesh.ARRAY_MAX):
		if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
			continue
		var source_data = arrays[slot]
		if source_data.size() == 0:
			continue
		var components: int = int(source_data.size()/float(original_vertices.size()))
		var compacted = source_data.duplicate()
		compacted.resize(retained.size()*components)
		for index in range(retained.size()):
			for component in range(components):
				compacted[index*components+component] = source_data[retained[index]*components+component]
		arrays[slot] = compacted
	arrays[Mesh.ARRAY_INDEX] = remapped
	return arrays

func _add_model(id: String, point: Vector2, scale_value: Vector3, yaw: float, variant: int = 0) -> void:
	if str(render_record.get("mode","native"))!="native": return
	var variants: Array = _model_variants(id)
	if variants.is_empty():
		return
	var chosen: Dictionary = variants[posmod(variant, variants.size())]
	var scale_fit: Vector3 = scale_value / float(chosen.extent)
	var basis: Basis = Basis(Vector3.UP, yaw).scaled_local(scale_fit)
	var position_value: Vector3 = world_point(point) - basis * Vector3(chosen.offset)
	var mesh: Mesh = chosen.mesh
	_add_batch("scan:" + id + ":" + str(posmod(variant, variants.size())), mesh, null, Transform3D(basis, position_value))
	stats.scannedModels += 1
	stats.modelBaseTriangles += int(chosen.originalTriangles)

func _validate_contract() -> bool:
	if str(stage.get("id", "")).is_empty() or stage.get("paths", []).is_empty() or stage.get("objectives", []).is_empty():
		return false
	for segment in road_segments:
		if not Vector2(segment.a).is_finite() or not Vector2(segment.b).is_finite():
			return false
	return not heights.is_empty() and ground_mesh != null

func diagnostics() -> Dictionary:
	var result: Dictionary = stats.duplicate(true)
	result["worldWidth"] = width
	result["worldDepth"] = depth
	result["heightMinimum"] = 0.0
	result["heightMaximum"] = 0.0
	if not heights.is_empty():
		result["heightMinimum"] = heights[0]
		result["heightMaximum"] = heights[0]
		for height in heights:
			result.heightMinimum = minf(float(result.heightMinimum), height)
			result.heightMaximum = maxf(float(result.heightMaximum), height)
	result["roadSegmentCount"] = road_segments.size()
	result["waterRegionCount"] = water_regions.size()
	result["shallowCrossingCount"] = shallow_regions.size()
	result["landmarkCount"] = landmarks.size()
	result["objects"] = objects.duplicate(true)
	result["renderLayerContract"] = render_layer_contract()
	var roof_arrays: Array = _roof_mesh().surface_get_arrays(0)
	var roof_normals: PackedVector3Array = roof_arrays[Mesh.ARRAY_NORMAL]
	result["roofSlopeNormalUp"] = roof_normals[0].y > 0.1 and roof_normals[6].y > 0.1
	result["roofFirstNormal"] = roof_normals[0]
	return result
