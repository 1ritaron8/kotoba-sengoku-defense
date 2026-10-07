extends SceneTree
## Exact installed pack, real Main and native viewport input. Learning banner
## hidden only for unobstructed preview inspection; production state unchanged.
const Store=preload("res://native/progress.gd")
const ActorMaterials=preload("res://native/actor_materials.gd")
var app: Node
var checks: int=0
var failures: Array=[]
var images: Array=[]
var observations: Array=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok: failures.append(note);push_error("DIRECT PLACEMENT GPU "+note)

func settle() -> void:
	app.learning_field.clear()
	app._process(0)
	app.troops_3d._process(0)
	app.game.queue_redraw()
	app.game.actor_overlay.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func motion(point: Vector2) -> void:
	var event=InputEventMouseMotion.new()
	event.position=point
	event.global_position=point
	Input.parse_input_event(event)
	await process_frame
	await settle()

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()

func capture(path: String) -> void:
	await settle()
	check(root.get_texture().get_image().save_png(path)==OK,"Actual full Main GPU screenshot saves")
	images.append(path)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/premium-models/").to_lower()) or DisplayServer.get_name()=="headless": quit(2);return
	root.size=Vector2i(1440,900)
	var fixture=Store.new()
	fixture.save_path="user://direct-preview-%d.json"%Time.get_ticks_msec()
	fixture.data.settings={"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Fresh isolated profile saves")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await process_frame
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.player.stop()
	await create_timer(.7).timeout
	await settle()
	check(app.progress.data.maps.is_empty(),"No fabricated campaign clears or upgraded units")
	check(app.game.external_placement_ghost and app.game.three_d_enabled,"Final Main enables exclusive 3D preview")
	check(app.army_toolbar.visible and app.army_grid.get_child_count()==8,"Actual fixed bottom roster has eight cards")
	var initial_gold: int=app.game.gold
	var initial_id: int=app.game.next_id
	var ground_point: Vector2
	for id in ["archer","spear"]:
		app._choose_unit(id)
		var point: Vector2=Vector2(-1,-1)
		for hint in app.game.placement_hints:
			if hint.x>=0: point=hint;break
		check(point.x>=0,"Actual class has a role-eligible placement point "+id)
		await motion(app.game._screen(point))
		var preview: Dictionary=app.game.placement_preview(app.game.placement_cursor)
		var ghost: Node3D=app.troops_3d.placement_actor
		check(preview.active and preview.valid and preview.visible,"Mouse motion drives valid actual snap preview "+id)
		check(is_instance_valid(ghost) and ghost.visible and ghost.unit_type==id and ghost.evolution_stage==0,"Actual class-specific Lv1 3D model rendered "+id)
		check(ghost.position.is_equal_approx(app.troops_3d.normalized_to_world(Vector2(preview.position.x,preview.position.y))),"Actual ghost feet match eventual committed coordinates "+id)
		check(app.game.gold==initial_gold and app.game.next_id==initial_id and app.game.units.is_empty() and app.troops_3d.actors.is_empty() and app.troops_3d.side_markers.is_empty(),"Preview has zero supply/id/unit/side-marker effects "+id)
		check(ActorMaterials.placement_preview_material().shader.code.contains("ALPHA = 0.75") and not ActorMaterials.material().shader.code.contains("ALPHA = 0.75"),"Pack loads separate transparent shader without making combat actors transparent")
		var overrides_ok: bool=true
		for instance in ghost.meshes:
			overrides_ok=overrides_ok and instance.material_override==app.troops_3d.placement_actor.materials.combined and instance.material_override!=ActorMaterials.material() and instance.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		check(overrides_ok,"All original model joints use private preview material without active-unit shadows "+id)
		observations.append({"type":id,"preview":preview,"scale":ghost.scale.x,"meshBatches":ghost.meshes.size(),"gold":app.game.gold,"actualActors":app.troops_3d.actors.size()})
		if id=="spear":
			ground_point=point
			await capture(qa_project_path("dist/premium-placement.png"))
	await motion(app.game._screen(Vector2(.04,.78)))
	check(not bool(app.game.placement_preview(app.game.placement_cursor).valid) and app.troops_3d.placement_actor.visible,"Invalid point retains a preview model with engine rejection footprint")
	await capture(qa_project_path("dist/premium-placement-invalid.png"))
	await motion(app.pause_button.get_global_rect().get_center())
	check(not app.game.placement_cursor_visible and not app.troops_3d.placement_actor.visible,"Actual STOP/HUD GUI region hides the ghost")
	await motion(app.game._screen(ground_point))
	check(app.troops_3d.placement_actor.visible,"Returning to actual battlefield restores ghost")
	await click(app.game._screen(ground_point))
	check(app.game.units.size()==1 and app.game.gold==initial_gold-65 and app.game.next_id==initial_id+1,"Native viewport click commits spear once and charges exact65")
	check(not app.troops_3d.placement_actor.visible and app.troops_3d.actors.size()==1 and app.troops_3d.side_markers.size()==1,"Committed real actor replaces ghost without duplicate identity")
	app._choose_unit("archer")
	await settle()
	app.game.cancel_recruit()
	await settle()
	check(not app.troops_3d.placement_actor.visible and app.game.gold==initial_gold-65,"Cancel neither refunds an uncharged preview nor keeps a ghost")
	var file=FileAccess.open("user://qa_premium_models_placement.json",FileAccess.WRITE)
	check(file!=null,"Exact-pack isolated QA report opens")
	if file:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"images":images,"observations":observations,"adapter":RenderingServer.get_video_adapter_name(),"scope":"Installed pack actual Main; fresh starter-only original progress and supply; no fabricated clears or levels. Native viewport motion/commit events. First passive learning banner hidden only for unobstructed visual capture."},"  "))
		file.close()
	print("DIRECT_PLACEMENT_GPU ",JSON.stringify({"checks":checks,"failures":failures,"images":images}))
	if app.battle_audio!=null: app.battle_audio.shutdown()
	app.player.stream=null
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
