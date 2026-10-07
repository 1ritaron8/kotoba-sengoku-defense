extends SceneTree
## Same frozen actual battle for previous/updated feedback. No staged combat poses.
const Store = preload("res://native/progress.gd")
const PreviousFeedback = preload("res://tests/fixtures/combat_feedback_before_premium.gd")
var app: Node
var previous: Node2D
var checks: int = 0
var failures: Array[String] = []
var captures: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok: failures.append(note); push_error(note)

func image_save(path: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png(path)==OK,"Actual GPU screenshot saved: "+path)
	return image

func difference(before: Image, after: Image, field: Rect2) -> Dictionary:
	var inside: int=0
	var outside: int=0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a: Color=before.get_pixel(x,y)
			var b: Color=after.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:
				if field.has_point(Vector2(x,y)): inside+=1
				else: outside+=1
	return {"insideChangedPixels":inside,"outsideChangedPixels":outside}

func save_comparison(name_value: String) -> void:
	var real_state: String=JSON.stringify(app.game.snapshot())
	app.combat_feedback.modulate=Color(1,1,1,0)
	previous.modulate=Color.WHITE
	var old: Image=await image_save("C:/JP_DF/dist/preview-premium-feedback-before-"+name_value+".png")
	previous.modulate=Color(1,1,1,0)
	app.combat_feedback.modulate=Color.WHITE
	var improved: Image=await image_save("C:/JP_DF/dist/preview-premium-feedback-after-"+name_value+".png")
	var change: Dictionary=difference(old,improved,app.game.field_rect)
	check(change.insideChangedPixels>10,"True event feedback changes visible battlefield pixels: "+name_value)
	check(change.outsideChangedPixels==0,"Actual clipped feedback never paints over toolbar/subtitle/inspector outside field: "+name_value)
	check(JSON.stringify(app.game.snapshot())==real_state,"GPU comparison preserves exactly the same actual combat snapshot: "+name_value)
	captures.append({"name":name_value,"elapsed":app.game.elapsed,"wave":app.game.wave,"enemyCount":app.game.enemies.size(),"state":app.game.snapshot(),"pixels":change,"feedback":app.combat_feedback.diagnostics()})

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/premium-feedback/") or DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(1440,900)
	var store: RefCounted=Store.new()
	store.save_path="user://premium-feedback-%d.json" % Time.get_ticks_msec()
	for stage in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		store.data.maps[str(stage.id)]={"wins":1}
	store.data.settings={"music":false,"voice":false,"effects":false}
	check(store.write_save(),"Isolated fixture unlocks visuals without editing real user progress")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=store.save_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.atmosphere.set_process(false)
	app.selected_portrait.set_process(false)
	app.player.stop()
	app.player.stream=null
	previous=PreviousFeedback.new()
	previous.battle=app.game
	previous.font=app.font
	previous.modulate=Color(1,1,1,0)
	app.field_clip.add_child(previous)
	previous.set_process(false)
	app.game.game_event.connect(previous.consume_event)
	for stage_info in [{"index":0,"name":"forest"},{"index":8,"name":"night"}]:
		app._select_tier(0)
		app._select_map(int(stage_info.index))
		app._begin_battle()
		app.game.set_process(false)
		app.combat_feedback.set_process(false)
		previous.reset()
		app.learning_field.clear()
		var supply: int=app.game.gold
		var total_cost: int=0
		var selected: int=-1
		for type_name in ["spear","gunner","archer"]:
			check(app.game.begin_placement(type_name),"Original supply previews real "+type_name)
			var chosen: Vector2=Vector2(-1,-1)
			var best: float=INF
			for hint in app.game.placement_hints:
				if hint.x<0: continue
				var score: float=hint.distance_to(app.game.paths[0].points[mini(2,app.game.paths[0].points.size()-1)])
				if score<best: best=score; chosen=hint
			check(chosen.x>=0 and app.game.place_unit(chosen.x,chosen.y),"Actual advertised post commits "+type_name)
			total_cost+=int(app.game.recruit_catalog[type_name].cost)
			if type_name=="spear": selected=int(app.game.units[-1].id)
		check(app.game.gold==supply-total_cost,"Visible army uses ordinary initial supply")
		app.game.select_unit(selected)
		await create_timer(0.7).timeout
		var found_contact: bool=false
		var found_gun: bool=false
		for frame in range(2100):
			app.game.advance_simulation(1.0/60)
			app._process(1.0/60)
			app.combat_feedback._process(1.0/60)
			previous._process(1.0/60)
			app.troops_3d.sync_actor_states(app.game.actor_states())
			app.game._emit_state()
			app.learning_field.clear()
			if app.game.between_waves: app._continue_battle(); app.learning_field.clear()
			var kinds: Dictionary=app.combat_feedback.diagnostics().activeKinds
			if not found_contact and int(kinds.get("number",0))>0 and int(kinds.get("steel",0))+int(kinds.get("contact",0))>0:
				await save_comparison(str(stage_info.name)+"-contact")
				found_contact=true
			if not found_gun and int(kinds.get("muzzle",0))>0:
				await save_comparison(str(stage_info.name)+"-matchlock")
				found_gun=true
			if found_contact and found_gun: break
			if frame%18==0: await process_frame
			if app.game.finished: break
		check(found_contact and found_gun,"Naturally spawned enemies reach both ground contact and actual matchlock release: "+str(stage_info.name))
		check(app.combat_feedback.troop_renderer==app.troops_3d,"Actual Main hooks the camera used by battlefield actors")
	var report: Dictionary={"checks":checks,"failures":failures,"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Two native stages using paid Lv1 troops, original initial supply, real spawn/routes/HP/timing. Same frozen combat snapshot receives old and new feedback; changed GPU pixels stay within the clipped field. Ordinary learning tasks are cleared for screenshot only. Independent headless tests verify pause, event counts and bounded stress."}
	var file: FileAccess=FileAccess.open("user://qa_premium_feedback_capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("PREMIUM_FEEDBACK_GPU ",JSON.stringify({"checks":checks,"failures":failures,"captures":captures.size(),"gpu":RenderingServer.get_video_adapter_name()}))
	app.battle_audio.shutdown()
	app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
