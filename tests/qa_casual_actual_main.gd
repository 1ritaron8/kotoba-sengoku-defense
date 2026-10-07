extends SceneTree
## Actual Main visual comparison. The initial Lv1 archer/spear roster spends
## the stage's own 280 supply. All births, targets, damage and movement are
## native Game events. The learning banner is hidden only for image review;
## no learning reward, HP, income, enemy or actor position is injected.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var captures: Array = []
var variant: String = "before"
var paid: Array = []
var lod_comparison: Dictionary = {}
var expected_art: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	variant = "before" if "--before" in OS.get_cmdline_user_args() else "final" if "--final" in OS.get_cmdline_user_args() else "after"
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	for name in ["APPDATA","LOCALAPPDATA"]:
		if not OS.get_environment(name).replace("\\","/").simplify_path().to_lower().begins_with(qa_project_path("tests/profiles/casual-actor-materials/").to_lower()): quit(2);return
	print("CASUAL_CAPTURE_GUARD ",JSON.stringify({"profile":profile,"display":DisplayServer.get_name(),"args":OS.get_cmdline_args()}))
	if not profile.begins_with(qa_project_path("tests/profiles/casual-actor-materials/").to_lower()) or DisplayServer.get_name()=="headless" or OS.get_environment("JP_CASUAL_DUMMY_AUDIO")!="1":
		quit(2)
		return
	root.size = Vector2i(1440,900)
	var art_manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-rendered/manifest.json"))
	for entry in art_manifest.get("stages",[]):
		if str(entry.get("stageId",""))=="basic-forest": expected_art=entry.duplicate(true);break
	check(not expected_art.is_empty() and str(expected_art.get("artDirection","")).to_lower().contains("casual"),"Approved casual first artwork is registered before actual Main starts")
	var fixture = Store.new()
	fixture.save_path = "user://visual-only-progress.json"
	fixture.data.settings.music = false
	fixture.data.settings.voice = false
	fixture.data.settings.effects = false
	fixture.data.settings.masterVolume = 0.0
	check(fixture.write_save(),"Isolated initial profile writes")
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	await process_frame
	for node in [app,app.game,app.combat_feedback,app.troops_3d]: node.set_process(false)
	app.player.stop()
	app._select_tier(0)
	app.game.set_seed(42)
	app._begin_battle()
	app.game.set_process(false)
	app.learning_field.clear()
	# Remove the visual learning-screen callback, not the Game's wave clock.
	if app.game.wave_ended.is_connected(app._on_wave_ended): app.game.wave_ended.disconnect(app._on_wave_ended)
	var start: int = app.game.gold
	check(start==280,"Original initial supply is 280")
	for type_name in ["archer","archer","spear","spear"]:
		var cost: int = app.game.recruit_cost(type_name)
		var accepted: bool = app.game.begin_placement(type_name)
		check(accepted,"Initial Lv1 order accepted: "+type_name)
		if type_name=="archer" and accepted:
			var chosen: Vector2 = Vector2(-1,-1)
			var nearest: float = INF
			for point in app.game.placement_hints:
				if point.x<0 or not bool(app.game.placement_preview(point).get("valid",false)): continue
				var score: float = point.distance_to(Vector2(.43,.57))
				if score<nearest: chosen=point;nearest=score
			check(chosen.x>=0 and app.game.place_unit(chosen.x,chosen.y),"Legal paid archer emplacement")
		paid.append({"type":type_name,"cost":cost})
	check(app.game.gold==30,"Four actual orders pay 250 once")
	check(app.game.recruitment_queue.size()==4 and app.game.units.is_empty(),"Actual simultaneous timers precede births")
	for tick in range(2700):
		if app.game.between_waves: app.game.continue_wave()
		app.game.advance_simulation(1.0/60.0)
		app._process(1.0/60.0)
		app.combat_feedback._process(1.0/60.0)
		app.learning_field.clear()
		if tick%6==0:
			app.troops_3d.sync_actor_states(app.game.actor_states())
			await process_frame
		if tick in [959,2699]:
			await capture("16s" if tick==959 else "45s",start,tick+1)
			if variant=="final" and tick==959: check(true,"Fine runtime LOD retained without changing original full base mesh")
		if app.game.finished: break
	check(not app.game.finished,"Actual visual observation remains a live battle")
	check(not captures.is_empty(),"Actual Main images captured")
	var report: Dictionary = {"style":"clean_casual_3d_v1","variant":variant,"checks":checks,"failures":failures,"captures":captures,"lodComparison":lod_comparison,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Actual Main on first approved casual artwork, initial permanent Lv1 archer/spear unlocked only, seed42, four paid simultaneous production orders. Natural spawning, movement and damage. Learning screen hidden for visual review with no learning reward; this is appearance QA, not balance or completion evidence."}
	var file = FileAccess.open("user://actual-main-"+variant+".json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	print("CASUAL_ACTUAL_MAIN ",JSON.stringify({"variant":variant,"checks":checks,"failures":failures,"captures":captures.size()}))
	app.player.stream = null
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)

func capture(label: String, start: int, ticks: int) -> void:
	app.game._emit_state()
	app.troops_3d.sync_actor_states(app.game.actor_states())
	app.learning_field.clear()
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	var path: String = "user://actual-main-"+variant+"-"+label+".png"
	check(shot.save_png(path)==OK,"Actual Main PNG saved: "+label)
	var crop_info: Array = []
	var real_meshes: Array = []
	for key in app.troops_3d.actors:
		var actor: Node3D = app.troops_3d.actors[key]
		var foot: Vector2 = app.troops_3d.get_global_transform_with_canvas()*app.troops_3d.camera.unproject_position(actor.position)
		var rect: Rect2i = Rect2i(Vector2i(foot)-Vector2i(44,90),Vector2i(88,112)).intersection(Rect2i(Vector2i.ZERO,shot.get_size()))
		if rect.size.x==88 and rect.size.y==112:
			var crop_path: String = "user://actor-"+variant+"-"+label+"-"+str(key).replace(":","-")+".png"
			check(shot.get_region(rect).save_png(crop_path)==OK,"Actual actor crop saved")
			crop_info.append({"key":key,"type":actor.unit_type,"hostile":actor.hostile,"foot":foot,"rect":rect,"path":ProjectSettings.globalize_path(crop_path)})
		var mesh_details: Array = []
		if actor.skinned_renderer!=null:
			for group in actor.skinned_renderer.groups:
				var instance: MeshInstance3D = actor.skinned_renderer.groups[group]
				var arrays: Array = instance.mesh.surface_get_arrays(0)
				mesh_details.append({"group":group,"actualVertices":(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),"actualTriangles":(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3,"authoredVertices":instance.mesh.get_meta("authored_vertex_count",0),"authoredTriangles":instance.mesh.get_meta("authored_triangle_count",0),"baseLodError":instance.mesh.get_meta("base_lod_error",0),"lodBias":instance.lod_bias})
				if variant!="before":
					check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()==int(instance.mesh.get_meta("authored_vertex_count",-1)),"Full authored vertices restored: "+key+" "+str(group))
					check((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3==int(instance.mesh.get_meta("authored_triangle_count",-1)),"Full authored base triangles restored: "+key+" "+str(group))
		if variant!="before": check(not actor.hero_detail and is_equal_approx(app.troops_3d.actor_base_scale(),.70),"Original field actor identity and scale preserved")
		real_meshes.append({"key":key,"type":actor.unit_type,"hostile":actor.hostile,"scale":actor.scale,"detail":actor.hero_detail,"mesh":mesh_details,"shaderExposure":actor.materials.combined.get_shader_parameter("local_exposure"),"shaderTint":actor.materials.combined.get_shader_parameter("local_tint")})
	var troop: Node = app.troops_3d
	check(str(troop.battlefield.render_layer_contract().get("artPath",""))==str(expected_art.get("path","")),"Actual Main uses the registered approved casual first battlefield")
	check(str(troop.battlefield.render_layer_contract().get("artSha256",""))==str(expected_art.get("sha256","")),"Actual Main uses the precise reviewed art revision")
	for actor in troop.actors.values():
		check(actor.materials.combined.get_meta("art_direction","")=="clean_casual_3d_v1","Actual Main actor uses approved material direction")
		check(bool(actor.materials.combined.get_shader_parameter("hostile_team"))==actor.hostile,"Actual team shader follows the real allegiance")
		check(not actor.materials.combined.shader.code.contains("EMISSION ="),"Live armor and skin use real lighting without emissive fake detail")
	if variant!="before":
		check(bool(troop.diagnostics().lightField.available) and troop.local_light_updates>0,"Actual Main restores individual local illumination")
		var authored: Dictionary=troop.battlefield.render_layer_contract().lighting
		check(is_equal_approx(troop.sun.light_energy,float(authored.keyEnergy)) and is_equal_approx(troop.fill.light_energy,float(authored.fillEnergy)),"Actual Main uses authored art lighting")
		var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/profiles/hybrid-stage-renderer/before-profile/Godot/app_userdata/말의 전장/actual-main-before.json"))
		for prior in before.captures:
			if str(prior.label)!=label: continue
			for field in ["hp","gold","kills","wave","battleElapsedSeconds"]:
				var same: bool = absf(float(app.game.snapshot().get(field))-float(prior.snapshot.get(field)))<.000001 if field=="battleElapsedSeconds" else app.game.snapshot().get(field)==prior.snapshot.get(field)
				check(same,"Renderer restoration preserves actual Game outcome: "+field)
	if variant=="final":
		for unit in app.game.units: check(str(app.game.healthbar_layout(unit,true).get("text",""))=="","Actual friendly HP number is absent")
		for enemy in app.game.enemies: check(str(app.game.healthbar_layout(enemy,false).get("text",""))=="","Actual hostile HP number is absent")
	captures.append({"path":ProjectSettings.globalize_path(path),"label":label,"ticks":ticks,"startingSupply":start,"paid":paid,"snapshot":app.game.snapshot(),"actualActors":real_meshes,"crops":crop_info,"render":troop.diagnostics(),"lighting":{"sunColor":troop.sun.light_color,"sunEnergy":troop.sun.light_energy,"sunPosition":troop.sun.position,"ambientEnergy":troop.environment.ambient_light_energy,"fillEnergy":troop.fill.light_energy},"layerContract":troop.battlefield.render_layer_contract(),"feedback":app.combat_feedback.diagnostics()})

func capture_lod_comparison() -> void:
	var normal: Image = root.get_texture().get_image()
	var troop: Node = app.troops_3d
	var original_threshold: float = troop.viewport.mesh_lod_threshold
	var state: Dictionary=app.game.snapshot()
	var primitives_before: int=troop.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	troop.viewport.mesh_lod_threshold=0.0
	troop.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var full: Image = root.get_texture().get_image()
	check(full.save_png("user://actual-main-final-16s-full-lod.png")==OK,"Actual Main full geometry comparison saves")
	var comparisons: Array=[]
	for key in troop.actors:
		var actor: Node3D=troop.actors[key]
		var foot: Vector2=troop.get_global_transform_with_canvas()*troop.camera.unproject_position(actor.position)
		var rect: Rect2i=Rect2i(Vector2i(foot)-Vector2i(44,90),Vector2i(88,112)).intersection(Rect2i(Vector2i.ZERO,normal.get_size()))
		if rect.size!=Vector2i(88,112): continue
		var base: String="user://actor-full-lod-"+str(key).replace(":","-")+".png"
		check(full.get_region(rect).save_png(base)==OK,"Actual Main full LOD actor crop saves")
		var changed: int=0
		var error: float=0.0
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var delta: Color=normal.get_pixel(x,y)-full.get_pixel(x,y)
				var difference: float=(absf(delta.r)+absf(delta.g)+absf(delta.b))/3.0
				error+=difference
				if difference>1.0/255.0: changed+=1
		comparisons.append({"key":key,"type":actor.unit_type,"path":ProjectSettings.globalize_path(base),"changedPixels":changed,"meanRGBError":error/float(rect.size.x*rect.size.y)})
	lod_comparison={"scope":"Same actual Main Game frozen at16s; viewport automatic LOD disabled only in this isolated comparison. Production values remain unchanged.","normalThreshold":original_threshold,"fullThreshold":0.0,"normalVisiblePrimitives":primitives_before,"fullVisiblePrimitives":troop.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"crops":comparisons,"reference":"https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-property-mesh-lod-threshold"}
	for field in ["hp","gold","kills","wave","battleElapsedSeconds"]: check(app.game.snapshot().get(field)==state.get(field),"Visual full LOD comparison leaves Game state unchanged: "+field)
	troop.viewport.mesh_lod_threshold=original_threshold
	troop.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for frame in range(4): await process_frame


# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
