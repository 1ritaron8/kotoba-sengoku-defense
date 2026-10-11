extends RefCounted
## Post-timing controlled cache checks against the unchanged original R8 Game.
class MutableProjection extends Control:
	var delegate: Control
	var offset: Vector2 = Vector2.ZERO
	func uses_world_geometry() -> bool: return true
	func model_to_field_point(point: Vector2) -> Vector2:
		return delegate.model_to_field_point(point)+offset

func projected_oracle(oracle: Node2D, center: Vector2, radius: float, fill: bool) -> Dictionary:
	var layout: Dictionary = oracle._world_circle_surface_layout(center,radius,fill)
	var result: Dictionary = {"fills":[],"arcs":[]}
	for polygon in layout.fills:
		var points: PackedVector2Array = oracle._project_circle_points(polygon)
		var local: PackedVector2Array = oracle._prepare_circle_fill(points)
		if local.size()>=3: result.fills.append({"origin":points[0],"points":local})
	for arc in layout.arcs:
		var points: PackedVector2Array = oracle._project_circle_points(arc)
		if points.size()>=2: result.arcs.append(points)
	return result

func exact_check(harness: SceneTree, oracle: Node2D, center: Vector2, radius: float, note: String) -> void:
	var game: Node2D = harness.app.game
	for fill in [false,true]:
		var expected: Dictionary = oracle._world_circle_surface_layout(center,radius,fill)
		harness.check(game._world_circle_surface_layout(center,radius,fill)==expected,note+": model geometry equals unchanged uncached R8")
		var projected: Dictionary = projected_oracle(oracle,center,radius,fill)
		harness.check(game._circle_projected_layout(center,radius,fill)==projected,note+": projected geometry equals unchanged uncached R8")
		harness.check(game._circle_projected_layout(center,radius,fill)==projected,note+": cache hit retains exact geometry")

func run(harness: SceneTree) -> void:
	var app: Node = harness.app
	var game: Node2D = app.game
	var troops: Control = app.troops_3d
	var terrain: Node3D = troops.battlefield
	var original_processing: bool = game.is_processing()
	var troops_processing: bool = troops.is_processing()
	game.set_process(false)
	troops.set_process(false)
	var baseline_path: String = "C:/JP_DF/tests/profiles/r8-lag-01/evidence/R8-game.before-instrumentation.gd"
	if not harness.check(FileAccess.get_sha256(baseline_path)=="4e1d1b41b4139b7df8111ad55e5a3d0c6ab53246d91428705553827e174ae6ea","Cache oracle is exact unchanged R8 Game source"):
		game.set_process(original_processing)
		troops.set_process(troops_processing)
		return
	var oracle: Node2D = load(baseline_path).new()
	game.get_parent().add_child(oracle)
	oracle.hide()
	oracle.set_process(false)
	oracle.position = game.position
	oracle.scale = game.scale
	oracle.rotation = game.rotation
	oracle.config = game.config.duplicate(true)
	oracle.set_field_rect(game.field_rect)
	oracle.bind_render_projection(troops)
	oracle._cache_circle_floor()
	var center: Vector2 = Vector2(game.zones[0].position)
	var radius: float = float(game.zones[0].r)
	game._clear_circle_render_cache()
	exact_check(harness,oracle,center,radius,"Initial cold/hot cache")
	var expected: Dictionary = oracle._world_circle_surface_layout(center,radius,true)
	var returned: Dictionary = game._world_circle_surface_layout(center,radius,true)
	if not returned.fills.is_empty():
		var points: PackedVector2Array = returned.fills[0]
		points[0] += Vector2(3,4)
		returned.fills[0] = points
	returned.arcs.clear()
	harness.check(game._world_circle_surface_layout(center,radius,true)==expected,"Mutating original layout API return cannot poison cached geometry")
	game._clear_circle_render_cache()
	game._world_circle_surface_layout(center,radius,false)
	game._world_circle_surface_layout(center,radius+1e-12,false)
	harness.check(game.circle_render_cache_diagnostics().entries==2 and game._circle_cache_find(center,radius,false).radius==radius and game._circle_cache_find(center,radius+1e-12,false).radius==radius+1e-12,"Float64 radius differences remain distinct exact keys")
	var camera: Camera3D = troops.camera
	var camera_transform: Transform3D = camera.transform
	var generation: int = game.circle_render_cache_diagnostics().floorGeneration
	camera.position += Vector3(.1,0,0)
	exact_check(harness,oracle,center,radius,"Actual camera transform change")
	harness.check(game.circle_render_cache_diagnostics().floorGeneration>generation,"Camera change invalidates both cache layers")
	camera.transform = camera_transform
	var viewport_size: Vector2i = troops.viewport.size
	generation = game.circle_render_cache_diagnostics().floorGeneration
	troops.viewport.size = viewport_size+Vector2i(16,8)
	exact_check(harness,oracle,center,radius,"Actual viewport size change")
	harness.check(game.circle_render_cache_diagnostics().floorGeneration>generation,"Viewport change invalidates both cache layers")
	troops.viewport.size = viewport_size
	var mirrored: bool = troops.presentation_mirrored
	generation = game.circle_render_cache_diagnostics().floorGeneration
	troops.presentation_mirrored = not mirrored
	exact_check(harness,oracle,center,radius,"Actual mirror change")
	harness.check(game.circle_render_cache_diagnostics().floorGeneration>generation,"Mirror change invalidates both cache layers")
	troops.presentation_mirrored = mirrored
	var custom: MutableProjection = MutableProjection.new()
	custom.delegate = troops
	troops.get_parent().add_child(custom)
	custom.position = troops.position
	custom.scale = troops.scale
	game.bind_render_projection(custom)
	oracle.bind_render_projection(custom)
	exact_check(harness,oracle,center,radius,"Unknown mutable provider before mutation")
	var before_mutation: Dictionary = game._circle_projected_layout(center,radius,true)
	custom.offset = Vector2(7,11)
	exact_check(harness,oracle,center,radius,"Unknown mutable provider after mutation")
	harness.check(game._circle_projected_layout(center,radius,true)!=before_mutation and game.circle_render_cache_diagnostics().entries==0 and not game.circle_render_cache_diagnostics().projectionCached,"Unknown mutable provider bypasses BOTH caches")
	game.bind_render_projection(null)
	harness.check(not game._circle_cache_synchronize() and game.circle_render_cache_diagnostics().entries==0,"Inactive projection bypasses both layers")
	game.bind_render_projection(troops)
	oracle.bind_render_projection(troops)
	custom.free()
	var geometry: Dictionary = game.config.worldGeometry.duplicate(true)
	var changed_geometry: Dictionary = geometry.duplicate(true)
	changed_geometry.vertices[0].y = float(changed_geometry.vertices[0].y)+.001
	var material: Material = terrain.ground.material_override
	var old_hash: String = terrain.source_hash
	harness.check(terrain.load_geometry(changed_geometry),"Actual provider accepts controlled terrain reload")
	game.config.worldGeometry = changed_geometry
	oracle.config.worldGeometry = changed_geometry
	game._cache_circle_floor()
	oracle._cache_circle_floor()
	exact_check(harness,oracle,center,radius,"Actual terrain reload")
	harness.check(terrain.source_hash!=old_hash,"Terrain source signature changes after actual reload")
	game.config.worldGeometry = {}
	game._cache_circle_floor()
	harness.check(game.circle_render_cache_diagnostics().entries==0 and game._world_circle_surface_layout(center,radius,true)=={"fills":[],"arcs":[]},"Empty/invalid floor reload clears both caches and emits no stale circle")
	harness.check(terrain.load_geometry(geometry),"Original terrain restores after controlled fixture")
	terrain.ground.material_override = material
	terrain._material = material
	game.config.worldGeometry = geometry
	oracle.config.worldGeometry = geometry
	game._cache_circle_floor()
	oracle._cache_circle_floor()
	for index in range(36):
		game._world_circle_surface_layout(center+Vector2(index*.0002,0),.008,false)
	var bounded: Dictionary = game.circle_render_cache_diagnostics()
	harness.check(bounded.entries<=32 and bounded.units<=32768,"Many exact circles remain within entry and vertex/container bounds")
	var before_large: Dictionary = game.circle_render_cache_diagnostics()
	var huge: PackedVector2Array = PackedVector2Array()
	huge.resize(32769)
	game._circle_cache_store_layout(center,.9,true,{"fills":[huge],"arcs":[]})
	harness.check(game.circle_render_cache_diagnostics().entries==before_large.entries and game.circle_render_cache_diagnostics().units==before_large.units,"Oversized entry is rejected without growing cache")
	exact_check(harness,oracle,center,radius,"Restored actual provider and floor")
	harness.observations.append({"case":"posttiming exact-circle regression","scope":"Controlled posttiming original-R8 oracle comparison; actual camera/viewport/mirror/provider/floor mutations restored. No natural timing or physics claim.","cache_diagnostics":game.circle_render_cache_diagnostics()})
	oracle.free()
	game.set_process(original_processing)
	troops.set_process(troops_processing)
