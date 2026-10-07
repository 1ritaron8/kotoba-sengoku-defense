extends SceneTree
## Preview is an uncommitted renderer, never a unit, blocker, gold receipt or AI.
const Game=preload("res://native/game.gd")
const Store=preload("res://native/progress.gd")
const Troops=preload("res://native/troops_3d.gd")
const ActorMaterials=preload("res://native/actor_materials.gd")
const TYPES=["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int=0
var failures: Array=[]
var images: Array=[]
var game: Node2D
var troops: Control

func _initialize() -> void: call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok: failures.append(note);push_error("PLACEMENT GHOST "+note)

func valid_point() -> Vector2:
	for p in game.placement_hints:
		if p.x>=0: return p
	return Vector2(-1,-1)

func render_preview(delta: float=.1) -> Dictionary:
	var data: Dictionary=game.placement_preview(game.placement_cursor)
	troops.sync_placement_preview(data,delta)
	return data

func capture(name_value: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path="C:/JP_DF/dist/preview-placement-ghost-"+name_value+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"Actual GPU ghost screenshot saves "+name_value)
	images.append(path)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/placement-ghost/"): quit(2);return
	var gpu: bool="--gpu" in OS.get_cmdline_user_args()
	if gpu and DisplayServer.get_name()=="headless": quit(2);return
	root.size=Vector2i(1440,900)
	var store=Store.new()
	game=Game.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(store.unit_catalog,TYPES,{})
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	game.load_map(maps[0])
	game.set_field_rect(Rect2(0,0,1440,900))
	game.three_d_enabled=true
	game.external_placement_ghost=true
	troops=Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.bind_battle(game)
	troops.set_field_size(Vector2(1440,900))
	troops.set_stage(maps[0])
	var original: Dictionary={"gold":game.gold,"nextId":game.next_id,"recruits":game.recruits,"kills":game.kills}
	for level in [1,4,8]:
		for id in TYPES:
			game.campaign_levels[id]=level
			check(game.begin_placement(id),"Selected original class begins preview "+id+"/"+str(level))
			game.placement_cursor=valid_point()
			var preview: Dictionary=render_preview()
			check(bool(preview.valid) and bool(preview.visible),"Real role-eligible snap preview "+id)
			check(troops.placement_actor.visible and troops.placement_actor.unit_type==id,"Same selected 3D class rendered "+id)
			check(troops.placement_actor.evolution_stage==int(preview.evolution),"Earned evolution mapping reaches preview "+id)
			check(troops.placement_actor.position.is_equal_approx(troops.normalized_to_world(Vector2(preview.position.x,preview.position.y))),"Ghost uses the exact eventual snap position "+id)
			check(troops.camera.unproject_position(troops.placement_actor.position).distance_to(Vector2(preview.position.x,preview.position.y)*troops.field_size)<.1,"Ghost contact point uses same photo projection "+id)
			var identity: int=troops.placement_actor.get_instance_id()
			render_preview()
			check(troops.placement_actor.get_instance_id()==identity,"Moving preview reuses one actor instead of rebuilding each frame "+id)
			check(troops.actors.is_empty() and troops.side_markers.is_empty() and troops.contact_shadows.is_empty(),"Ghost is absent from combat/side/shadow dictionaries "+id)
			check(game.units.is_empty() and game.gold==original.gold and game.next_id==original.nextId and game.recruits==original.recruits and game.kills==original.kills,"No unit/charge/id/reward/collision side effects "+id)
			var overridden: bool=true
			for mesh in troops.placement_actor.meshes:
				overridden=overridden and mesh.material_override==troops.placement_actor.materials.combined and mesh.material_override!=ActorMaterials.material() and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			check(overridden,"Transparent ghost has private material and casts no active-unit shadow "+id)
			if gpu and id in ["archer","spear","commander"] and level==1:
				await capture(id)
			game.set_input_enabled(false)
			render_preview()
			check(not troops.placement_actor.visible,"Modal/nav lock hides ghost "+id)
			game.set_input_enabled(true)
			game.placement_cursor_visible=false
			render_preview()
			check(not troops.placement_actor.visible,"Pointer over HUD/outside field hides ghost "+id)
			game.placement_cursor_visible=true
			render_preview()
			check(troops.placement_actor.visible,"Pointer returning to battlefield restores ghost "+id)
			game.cancel_recruit()
			render_preview()
			check(not troops.placement_actor.visible,"Cancel clears preview without a permanent actor "+id)
			await process_frame
	check(not ActorMaterials.material().shader.code.contains("ALPHA = 0.75"),"Preview transparency never leaks into real shared armour materials")
	check(game.begin_placement("spear"),"Commit fixture begins pending selection")
	var p: Vector2=valid_point()
	game.placement_cursor=p
	render_preview()
	check(game.place_unit(p.x,p.y),"Actual commit uses original placement API")
	troops.sync_actor_states(game.actor_states())
	render_preview()
	check(not troops.placement_actor.visible and game.units.size()==1,"Commit replaces the ghost with exactly one paid actual unit")
	check(troops.actors.size()==1 and troops.side_markers.size()==1,"Only the committed actor has combat/side identity")
	if gpu: await capture("committed")
	troops.hide()
	troops.sync_placement_preview({"active":true,"visible":true,"type":"spear","position":{"x":.5,"y":.5}})
	check(not troops.placement_actor.visible,"Hidden/home field cannot leak a ghost")
	var file=FileAccess.open("user://qa_placement_ghost.json",FileAccess.WRITE)
	check(file!=null,"Isolated ghost report opens")
	if file:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"images":images,"scope":"24 class/evolution visual fixture only; no campaign progression mutation; preview uses actual legal snap metadata with zero supply/id/unit side effects."},"  "))
		file.close()
	print("PLACEMENT_GHOST_QA ",JSON.stringify({"checks":checks,"failures":failures,"gpu":gpu,"images":images}))
	game.queue_free()
	troops.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
