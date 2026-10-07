extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
		push_error(detail)

func run() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var battle = load("res://native/game.gd").new()
	root.add_child(battle)
	battle.set_process(false)
	var atmosphere = load("res://native/battle_atmosphere.gd").new()
	atmosphere.battle = battle
	root.add_child(atmosphere)
	atmosphere.set_process(false)
	var identities: Dictionary = {}
	for stage in maps:
		battle.load_map(stage)
		var original_gold: int = battle.gold
		var original_recruits: int = battle.recruits
		var original_config: Dictionary = battle.config.duplicate(true)
		atmosphere.set_stage(stage)
		check(not identities.has(atmosphere.seed_value),"Each of 40 maps has its own deterministic atmosphere "+str(stage.id))
		identities[atmosphere.seed_value] = true
		check(atmosphere.atmosphere_points.size()<=40,"Ambient drawing workload stays bounded "+str(stage.id))
		var points_before: Array = atmosphere.atmosphere_points.duplicate(true)
		var seed_before: float = atmosphere.seed_value
		atmosphere.set_stage(stage)
		check(points_before==atmosphere.atmosphere_points and seed_before==atmosphere.seed_value,"Re-entering a battlefield preserves its visual identity "+str(stage.id))
		check(atmosphere.field_finish.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Field finish cannot consume deployment clicks "+str(stage.id))
		check(battle.gold==original_gold and battle.recruits==original_recruits and battle.config==original_config,"Atmosphere never changes battle economy or map data "+str(stage.id))
		battle.elapsed = 12.0
		atmosphere._process(.04)
		check(is_equal_approx(atmosphere.world_time,12.0),"Atmosphere follows simulation time "+str(stage.id))
		battle.paused = true
		atmosphere._process(.5)
		check(is_equal_approx(atmosphere.world_time,12.0),"Pausing freezes wind and embers "+str(stage.id))
		battle.set_field_rect(Rect2(24,45,1280,650))
		atmosphere._process(.04)
		check(atmosphere.field_finish.position==battle.field_rect.position and atmosphere.field_finish.size==battle.field_rect.size,"Visual finish follows field resize without covering HUD "+str(stage.id))
		atmosphere.set_stage(stage)
		check(is_zero_approx(atmosphere.world_time),"New sortie resets atmosphere clock "+str(stage.id))
	check(identities.size()==40,"All 40 unique maps remain distinct")
	check(not atmosphere.finish_material.shader.code.contains("screen_texture"),"Edge treatment does not add a framebuffer copy")
	var report: Dictionary = {"checks":checks,"failures":failures,"maps":maps.size(),"scope":"Actual Battle + presentation node: 40 unique map identities, capped ambient work, paused-time and field-resize behavior, no deployment input/economy/map mutation."}
	var file = FileAccess.open("user://qa_premium_atmosphere.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("PREMIUM_ATMOSPHERE ",JSON.stringify(report))
	atmosphere.queue_free()
	battle.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
