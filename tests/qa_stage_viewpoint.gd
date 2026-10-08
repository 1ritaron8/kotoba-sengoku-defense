extends SceneTree
## Real camera, soldiers, faction/HP anchors and game click selection at two sizes.
const Troops = preload("res://native/troops_3d.gd")
const Game = preload("res://native/game.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var gpu: bool = false

func _initialize() -> void:
	root.position = Vector2i(-16000,-16000)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for unused in range(4): await process_frame
	if gpu: await RenderingServer.frame_post_draw

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var allowed: String = ProjectSettings.globalize_path("res://tests/profiles/stage-viewpoint/").replace("\\","/").to_lower()
	if not profile.begins_with(allowed): quit(2);return
	gpu = DisplayServer.get_name()!="headless"
	check(is_equal_approx(Presentation.elevation_for_stage({}),50),"Default remains 50 degrees")
	check(is_equal_approx(Presentation.elevation_for_stage({"historicalBattlefield":{"viewpoint":{"elevationDegrees":12}}}),35),"Low angle clamps safely")
	check(is_equal_approx(Presentation.elevation_for_stage({"historicalBattlefield":{"viewpoint":{"elevationDegrees":88}}}),65),"High angle clamps safely")
	check(is_equal_approx(Presentation.elevation_for_stage({"historicalBattlefield":{"viewpoint":{"elevationDegrees":NAN}}}),50),"Invalid angle uses safe default")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var troops: Control = Troops.new()
	troops.stage = maps[14].duplicate(true)
	troops.stage.historicalBattlefield["viewpoint"] = {"elevationDegrees":38.0}
	root.add_child(troops)
	troops.set_process(false)
	check(is_equal_approx(troops.elevation_degrees,38.0) and is_equal_approx(troops.battlefield.elevation,38.0),"Initial stage configures its own angle before building terrain")
	var game: Node2D = Game.new()
	game.three_d_enabled = true
	root.add_child(game)
	game.set_process(false)
	game.hide()
	troops.bind_battle(game)
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size = dimensions
		troops.set_field_size(Vector2(dimensions))
		game.set_field_rect(Rect2(Vector2.ZERO,Vector2(dimensions)))
		for fixture in [{"map":14,"angle":35.0},{"map":14,"angle":38.0},{"map":36,"angle":42.0},{"map":39,"angle":58.0},{"map":39,"angle":65.0}]:
			var stage: Dictionary = maps[int(fixture.map)].duplicate(true)
			stage.historicalBattlefield["viewpoint"] = {"elevationDegrees":float(fixture.angle)}
			game.load_map(stage,0)
			game.set_process(false)
			troops.set_stage(stage)
			game.presentation_mirrored = troops.presentation_mirrored
			check(is_equal_approx(troops.elevation_degrees,float(fixture.angle)),"Real troop camera uses stage angle")
			check(is_equal_approx(troops.battlefield.elevation,float(fixture.angle)),"Terrain uses the same stage angle")
			check(is_equal_approx(troops.world_depth,troops.world_width/(float(dimensions.x)/dimensions.y)/sin(deg_to_rad(float(fixture.angle)))),"World depth matches stage angle and viewport aspect")
			var maximum_error: float = 0.0
			for y in [.02,.25,.5,.75,.98]:
				for x in [.02,.25,.5,.75,.98]:
					var p: Vector2 = Vector2(x,y)
					var foot: Vector3 = troops.normalized_to_world(p)
					var projected: Vector2 = troops.project_world_to_field(foot)
					var expected: Vector2 = Presentation.to_view(p,troops.presentation_mirrored)*Vector2(dimensions)
					maximum_error = maxf(maximum_error,projected.distance_to(expected))
					check(projected.distance_to(expected)<.12,"Raised terrain foot keeps authored pixel anchor")
					check(troops.world_to_normalized(foot).distance_to(p)<.00001,"World/normalized coordinate round trip")
					check(not troops.camera.is_position_behind(foot) and troops.camera.global_position.distance_to(foot)<troops.camera.far,"Near/far limits include upper and lower terrain")
					check(absf(foot.y-troops.battlefield.height_at(p))<.00001,"Actual terrain height reaches the foot")
			var states: Array = []
			game.units.clear()
			var points: Array[Vector2] = [Vector2(.30,.76),Vector2(.68,.36)]
			for index in range(points.size()):
				var p: Vector2 = points[index]
				var id: int = index+901
				states.append({"id":id,"type":"archer","friendly":index==0,"x":p.x,"y":p.y,"animation":"idle","animationClock":.4,"motionTime":.4,"aimX":0,"aimY":-1,"hp":75.0,"maxHp":100.0})
				if index==0:
					var unit: Dictionary = Game.UNIT_TYPES[0].duplicate(true)
					unit.merge({"id":id,"type":"archer","position":p,"hp":75.0,"maxHp":100.0,"animation":"idle","aim":Vector2.UP},true)
					game.units.append(unit)
			troops.sync_actor_states(states)
			await settle()
			for state in states:
				var actor: Node3D = troops.actors[str(state.id)+":0"]
				var p: Vector2 = Vector2(state.x,state.y)
				var expected: Vector2 = Presentation.to_view(p,troops.presentation_mirrored)*Vector2(dimensions)
				var actual: Vector2 = troops.project_world_to_field(actor.position)
				check(actual.distance_to(expected)<.12,"Actual soldier body uses exact click/foot position")
				check(absf(actor.position.y-troops.battlefield.height_at(p))<.00001,"Actual soldier stands on physical height")
				var hp: Dictionary = troops.health_anchor_for(int(state.id))
				check(not hp.is_empty() and hp.footPosition.distance_to(expected)<.12,"Faction marker shares exact actor foot")
				var head: Vector2 = troops.project_world_to_field(actor.bones.head.global_position+Vector3.UP*.26*actor.scale.y)
				check(hp.headPosition.distance_to(head)<.12 and bool(hp.friendly)==bool(state.friendly),"Health anchor follows actual 3D head and faction")
				check(hp.headPosition.y<hp.footPosition.y,"Health bar remains above the soldier at every angle")
				if bool(state.friendly):
					var layout: Dictionary = game.healthbar_layout(game.units[0],true)
					check(bool(layout.projected) and layout.anchor.distance_to(head)<.12,"Actual game HP bar uses the same rendered head")
					var click: InputEventMouseButton = InputEventMouseButton.new()
					click.button_index = MOUSE_BUTTON_LEFT
					click.pressed = true
					click.position = actual
					game._unhandled_input(click)
					check(game.selected_id==int(state.id),"Actual game click selects the displayed soldier")
					check(game.screen_to_field_point(actual).distance_to(p)<.00001,"Actual game screen lookup returns canonical position")
			if gpu:
				var capture: Image = troops.viewport.get_texture().get_image()
				check(capture!=null and capture.get_size()==dimensions,"Real GPU scene renders at both resolutions")
				check(capture.save_png("user://viewpoint-%02d-%d-%dx%d.png" % [int(stage.stageNumber),int(fixture.angle),dimensions.x,dimensions.y])==OK,"Actual viewpoint screenshot saved")
			observations.append({"stage":stage.stageNumber,"angle":fixture.angle,"dimensions":str(dimensions),"maximumProjectionErrorPixels":maximum_error,"depth":troops.world_depth,"cameraFar":troops.camera.far,"shadowDistance":troops.sun.directional_shadow_max_distance,"mirror":troops.presentation_mirrored})
	var report: Dictionary = {"checks":checks,"failures":failures,"gpu":gpu,"observations":observations}
	var file: FileAccess = FileAccess.open("user://stage-viewpoint-%s.json" % ("gpu" if gpu else "cpu"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("STAGE_VIEWPOINT checks=%d failures=%d gpu=%s path=%s" % [checks,failures.size(),gpu,ProjectSettings.globalize_path("user://")])
	game.queue_free()
	troops.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
