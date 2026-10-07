extends SceneTree
const Game=preload("res://native/game.gd")
const Troops=preload("res://native/troops_3d.gd")
var checks: int=0
var failures: Array=[]
var stages: Array=[]

func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label);push_error(label)

func run() -> void:
	var allowed: String=qa_project_path("tests/profiles/casual-actor-materials/").to_lower()
	for name in ["APPDATA","LOCALAPPDATA"]:
		if not OS.get_environment(name).replace("\\","/").simplify_path().to_lower().begins_with(allowed): quit(2);return
	if DisplayServer.get_name()!="headless" or not ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower().begins_with(allowed): quit(2);return
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var source_hash: String=JSON.stringify(maps).sha256_text()
	var game=Game.new()
	root.add_child(game)
	var troops=Troops.new()
	root.add_child(troops)
	await process_frame
	game.set_process(false);troops.set_process(false)
	troops.bind_battle(game)
	troops.set_field_size(Vector2(1408,736))
	for index in [5,15,25,35]:
		game.load_map(maps[index],10)
		troops.set_stage(maps[index])
		var config_hash: String=JSON.stringify(game.config).sha256_text()
		var before: Dictionary=game.snapshot()
		troops.sync_actor_states([])
		check(troops.mobile_objectives.size()==1,"Existing convoy has one actual 3D moving objective: "+str(maps[index].id))
		if troops.mobile_objectives.is_empty(): continue
		var cart: Node3D=troops.mobile_objectives.values()[0]
		var marker: Dictionary=mobile_marker(game.field_markers())
		check(not marker.is_empty() and cart.marker_id==str(marker.id),"Renderer binds actual existing objective ID")
		check(cart.position.distance_to(troops.normalized_to_world(Vector2(marker.x,marker.y)))<.00001,"Initial cart centre equals Game anchor and terrain height")
		var first: Dictionary=maps[index].escortRoute[0]
		var next: Dictionary=maps[index].escortRoute[1]
		var tangent: Vector3=troops.normalized_to_world(Vector2(next.x,next.y))-troops.normalized_to_world(Vector2(first.x,first.y))
		check(absf(angle_difference(cart.rotation.y,atan2(-tangent.x,-tangent.z)))<.00001,"Initial cart faces its actual authored next road segment")
		check(cart.get_meta("render_only",false) and game.units.is_empty() and game.recruitment_queue.is_empty(),"Cart creates no army, production or combat registration")
		check(before==game.snapshot() and config_hash==JSON.stringify(game.config).sha256_text(),"Visual initialization preserves existing combat state/config")
		check(cart.pieces.size()==5 and cart.wheels.size()==2,"Cargo cart has body, two real spoked wheels, flag and contact shadow")
		check(cart.pieces[0].get_active_material(0)!=cart.pieces[0].get_active_material(2),"Timber frame and canvas sacks retain distinct actual materials")
		check(cart.flag.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and cart.flag.layers==3,"Live blue banner casts shared sun shadow")
		check(absf(cart.pieces[-1].position.y-.002)<.00001,"Cart contact shadow stays at terrain surface plus 2mm")
		game.start_battle()
		check(game.running,"Real convoy battle starts normally")
		var start_point: Vector3=cart.position
		for tick in range(600):
			game.advance_simulation(1.0/60.0)
			troops.sync_field_markers(game.field_markers(),game.animation_time)
			marker=mobile_marker(game.field_markers())
			check(cart.position.distance_to(troops.normalized_to_world(Vector2(marker.x,marker.y)))<.00001,"Live cart stays on actual convoy anchor: "+str(index)+":"+str(tick))
		check(not game.finished and cart.position.distance_to(start_point)>.1,"Real convoy makes visible progress without forced HP")
		check(cart.wheel_distance>0.0 and absf(cart.wheels[0].rotation.x)>0.01,"Wheel spin derives from actual travelled distance")
		check(absf(cart.wheels[0].rotation.x-cart.wheels[1].rotation.x)<.00001,"Both actual wheels share consistent rolling angle")
		var state: Dictionary=game.snapshot()
		var distance: float=cart.wheel_distance
		var yaw: float=cart.rotation.y
		var flag_clock: float=float(cart.flag.material_override.get_shader_parameter("battle_clock"))
		for redraw in range(12): troops.sync_field_markers(game.field_markers(),game.animation_time)
		check(state==game.snapshot() and is_equal_approx(distance,cart.wheel_distance) and is_equal_approx(yaw,cart.rotation.y),"Repeated paused draw cannot move cart/wheels or alter Game")
		check(is_equal_approx(flag_clock,float(cart.flag.material_override.get_shader_parameter("battle_clock"))),"Banner does not animate on a frozen battle clock")
		game.pause_battle()
		for tick in range(10): game._process(.1);troops.sync_field_markers(game.field_markers(),game.animation_time)
		check(is_equal_approx(distance,cart.wheel_distance),"Actual Game pause holds cart rolling position")
		game.pause_battle()
		game.set_speed(2)
		var battle_time: float=game.animation_time
		for tick in range(10): game._process(.1);troops.sync_field_markers(game.field_markers(),game.animation_time)
		check(absf(game.animation_time-battle_time-2.0)<.00001 and cart.wheel_distance>distance,"Actual 2x clock advances the existing cart route")
		var before_resize: float=cart.wheel_distance
		troops.set_field_size(Vector2(1280,640))
		troops.sync_field_markers(game.field_markers(),game.animation_time)
		marker=mobile_marker(game.field_markers())
		check(cart.position.distance_to(troops.normalized_to_world(Vector2(marker.x,marker.y)))<.00001,"Resize preserves Game-to-world anchor")
		check(cart.wheel_distance<=before_resize+.00001,"Projection update cannot add fictitious cart travel")
		stages.append({"id":maps[index].id,"startingHP":before.hp,"endingHP":game.snapshot().hp,"initialSupply":before.gold,"endingSupply":game.gold,"actualMarker":marker,"cart":cart.diagnostics()})
		game.load_map(maps[index],10)
		troops.set_stage(maps[index]);troops.sync_actor_states([])
		check(troops.mobile_objectives.size()==1 and is_zero_approx(troops.mobile_objectives.values()[0].wheel_distance),"Same-stage reset keeps exactly one cart and clears previous travel")
	game.load_map(maps[0],10)
	troops.set_stage(maps[0]);troops.sync_actor_states([])
	check(troops.mobile_objectives.is_empty(),"Static first stage creates no duplicate 3D base/cart")
	check(JSON.stringify(maps).sha256_text()==source_hash,"All historical map data preserved")
	var report: Dictionary={"checks":checks,"failures":failures,"stages":stages,"scope":"CPU actual convoy stages6/16/26/36 and real Game route/time/pause/2x. Render-only native cart anchored by public field_markers; no HP, money, enemy or route injection."}
	var file: FileAccess=FileAccess.open("user://mobile-objective-cart.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	print("MOBILE_OBJECTIVE_CART ",JSON.stringify({"checks":checks,"failures":failures,"stages":stages.size()}))
	game.queue_free();troops.queue_free()
	await process_frame
	Troops.Battlefield.release_shared_resources()
	quit(0 if failures.is_empty() else 1)

func mobile_marker(markers: Array) -> Dictionary:
	for marker in markers:
		if bool(marker.get("mobile",false)) and str(marker.get("markerKind",""))=="objective": return marker
	return {}

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
