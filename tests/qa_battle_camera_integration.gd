extends SceneTree
const Gate = preload("res://native/learning_gate.gd")
var app: Node
var checks: int=0
var failures: Array[String]=[]
var images: Array[String]=[]

func _initialize() -> void:
	Engine.max_fps=60
	call_deferred("run")

func check(value: bool,note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("CAMERA_INTEGRATION: "+note)

func settle(frames: int=5) -> void:
	for unused in range(frames): await process_frame

func run() -> void:
	check(OS.get_environment("APPDATA").replace("\\","/").to_lower().begins_with("c:/jp_df/tests/profiles/battle-camera-integration/"),"An isolated integration profile is used")
	if not failures.is_empty(): quit(2);return
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://camera-qa-%d.json"%Time.get_ticks_msec()
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.progress.data.settings.voice=false
	app.progress.data.settings.music=false
	app._stop_narration()
	app.player.stop()
	for id in app.progress.stage_numbers:
		app.progress.data.maps[id]={"wins":1}
		var lesson: Dictionary=app.progress.stage_lessons[id]
		var count: int=lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		if not app.progress.data.learning.has("assessments"): app.progress.data.learning["assessments"]={}
		app.progress.data.learning.assessments[id]={"passed":true,"count":count,"correctCount":count,"scopeHash":Gate.scope_hash(lesson)}
	app._select_tier(0)
	app._select_map(9)
	app._begin_battle()
	app._stop_narration()
	app.game.spawn_clock=3600
	check(app.battle_camera.enabled,"The authored wide siege stage enables the camera")
	check(app.game.render_projection_provider==app.troops_3d,"Main binds the actual troop head projection provider")
	for layer in [app.game,app.troops_3d,app.atmosphere,app.combat_feedback]:
		check(layer.get_parent()==app.battle_field_content,"All world layers share one camera transform")
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		app._layout()
		await settle()
		app._sync_battle_camera()
		check(app.camera_controls.visible and app.battle_camera.input_enabled,"Camera controls are active only in actual combat")
		check(root.get_visible_rect().encloses(app.camera_controls.get_global_rect()),"The fixed camera controls fit the viewport")
		var toolbar_rect: Rect2=app.army_toolbar.get_global_rect()
		var camera_rect: Rect2=app.camera_controls.get_global_rect()
		check(app.battle_camera.set_zoom(1.6),"The actual camera reaches the accepted maximum zoom")
		check(app.army_toolbar.get_global_rect()==toolbar_rect and app.camera_controls.get_global_rect()==camera_rect,"The camera never scales fixed UI")
		app.battle_camera.pan_by_clip_delta(Vector2(-99999,99999))
		var lower: Vector2=-app.field_clip.size*.6
		check(app.battle_camera.pan.distance_to(Vector2(lower.x,0))<.01,"Panning clamps to the field without blank edges")
		for point in [Vector2(.3,.25),Vector2(.6,.4),Vector2(.8,.7)]:
			var screen: Vector2=app.game.field_point_to_screen(point)
			check(app.game.screen_to_field_point(screen).distance_to(point)<.00001,"Actual game input follows the shared zoom and pan")
		var outside: Vector2=Vector2(dimensions.x*.5,app.field_clip.get_global_rect().end.y+20)
		check(not app.game.screen_point_in_field(outside),"The scaled battlefield cannot accept a click below its visible clip")
		app.battle_camera.reset()
		app.camera_zoom_in.pressed.emit()
		check(is_equal_approx(app.battle_camera.zoom,1.1),"The visible plus button operates the actual camera")
		app.camera_reset.pressed.emit()
		check(is_equal_approx(app.battle_camera.zoom,1.0) and app.battle_camera.pan.is_zero_approx(),"The visible reset button returns to the full field")
		app.game.paused=true
		app._on_state(app.game.snapshot())
		app._sync_battle_camera()
		check(not app.battle_camera.input_enabled and app.camera_zoom_in.disabled,"Paused combat cannot receive camera gestures")
		app.game.paused=false
		app._on_state(app.game.snapshot())
		app._sync_battle_camera()
		check(app.battle_camera.input_enabled,"Resuming restores camera input")
	app._choose_unit("archer")
	var placement: Vector2=Vector2(-1,-1)
	for zone in app.game.zones:
		var candidate: Vector2=app.game._zone_placement_hint(zone,"archer")
		if candidate.x>=0 and bool(app.game.placement_preview(candidate).valid): placement=candidate;break
	check(placement.x>=0 and app.game.place_unit(placement.x,placement.y),"A real legal archer emplacement is produced on the new terrain")
	app.game.advance_simulation(6)
	app.troops_3d._process(0)
	await settle()
	check(app.game.units.size()==1,"The real paid production creates its actor")
	if not app.game.units.is_empty():
		var unit: Dictionary=app.game.units[0]
		var head: Dictionary=app.troops_3d.health_anchor_for(int(unit.id))
		check(not head.is_empty(),"The real generated actor supplies a projected head position")
		check(not app.game.healthbar_layout(unit,true).rect.size.is_zero_approx(),"The real game generates a visible health bar from that actor")
	app._select_map(0)
	check(not app.battle_camera.enabled and app.battle_camera.zoom==1.0,"The close starter battlefield disables pan and zoom")
	app._show_home()
	app._sync_battle_camera()
	check(not app.battle_camera.input_enabled and not app.camera_controls.visible,"Home cannot receive battlefield gestures")
	print("CAMERA_INTEGRATION checks=",checks," failures=",failures.size())
	app._stop_narration()
	app.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
