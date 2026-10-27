extends "res://tests/qa_painted_game.gd"
## Narrow actual rollback path only. Reuses copied-token input observers.
## No placement, funds/stats/clock writes, hidden HUD, old regression or art pass.
const ROLLBACK_HASHES: Dictionary = {
	"res://native/game.gd":"4b7a2c4692d0e54d1613a1c0d8dbfd4c4391050f7cae1eed0b4aa1b42a89ca85",
	"res://native/ground_combat.gd":"5ce65ff3400b19a4e63eef8784901c6731f917ca0d78c2db57601a234faaf767",
	"res://native/painted_stage.gd":"2584365b367ca20905f7ee2acd887ea76600d067bef2040e612ac8d31567770c",
	"res://native/withdrawal_mission.gd":"31e672b94effc967b30ad6a4ae34c9915889726cb48fb52c39fa724274913ad8"
}

func rollback_hashes() -> Dictionary:
	var hashes: Dictionary=hash_sources()
	hashes["res://tests/qa_painted_rollback.gd"]=FileAccess.get_sha256("res://tests/qa_painted_rollback.gd")
	for filename in DirAccess.get_files_at("res://assets/commanders"):
		if filename.get_extension() in ["png","json"]:
			var path: String="res://assets/commanders/"+filename
			hashes[path]=FileAccess.get_sha256(path)
	return hashes

func copy_visible_ui(parent: Node, label_value: String) -> void:
	var rows: Array=[]
	for node in parent.find_children("*","Control",true,false):
		if not node.is_visible_in_tree(): continue
		if node is Label or node is Button or node.has_method("get_text_layout"):
			var row: Dictionary={"path":str(node.get_path()),"name":str(node.name),"bounds":str(node.get_global_rect()),"clip":str(visible_clip(node))}
			if node is Label or node is Button: row["text"]=str(node.text)
			if node.has_method("get_text_layout"): row["textLayout"]=node.get_text_layout().duplicate(true)
			rows.append(row)
	evidence[label_value+"VisibleText"]=rows

func commander_observation(label_value: String) -> void:
	if not alive(): return
	var portrait: Control=named_control(app.barracks,"SelectedArmyPortrait")
	var title: Control=named_control(app.barracks,"CommanderName")
	var copied: Dictionary={"scope":"Actual original commander nodes, diagnostic readiness and text/clip geometry only. Full PNG must be reviewed for readable pixels and art acceptance."}
	check(is_instance_valid(portrait) and portrait.is_visible_in_tree(),label_value+": original commander portrait node is visible")
	if is_instance_valid(portrait):
		copied["portrait"]={"bounds":str(portrait.get_global_rect()),"clip":str(visible_clip(portrait)),"diagnostics":portrait.diagnostics() if portrait.has_method("diagnostics") else {}}
		check(portrait.size.x>100 and portrait.size.y>100 and visible_clip(portrait).grow(1).encloses(portrait.get_global_rect()),label_value+": commander portrait area fits inside its visible clip")
		check(bool(copied.portrait.diagnostics.get("ready",false)),label_value+": original commander portrait image is ready")
	check(is_instance_valid(title) and title.is_visible_in_tree() and title.has_method("get_text_layout"),label_value+": original commander name is visible")
	if is_instance_valid(title) and title.has_method("get_text_layout"):
		var runs: Array=[]
		var all_inside: bool=true
		for run in title.get_text_layout().get("runs",[]):
			var bounds: Rect2=title.get_global_transform_with_canvas()*Rect2(run.bounds)
			all_inside=all_inside and visible_clip(title).grow(1.5).encloses(bounds)
			runs.append({"text":str(run.get("text","")),"role":str(run.get("role","")),"fontSize":run.get("size",0),"screenBounds":str(bounds)})
		copied["commanderName"]={"bounds":str(title.get_global_rect()),"runs":runs,"allRunsInsideClip":all_inside}
		check(not runs.is_empty() and all_inside,label_value+": commander name has actual unclipped text runs")
	evidence[label_value+"Commander"]=copied
	copy_visible_ui(app.barracks,label_value+"Barracks")

func battle_observation(label_value: String) -> void:
	if not alive(): return
	var posts: Array=app.game.shooting_position_snapshot().duplicate(true)
	var ids: Array=posts.map(func(row: Dictionary): return str(row.id))
	var withdrawal: Variant=app.game.get("withdrawal_mission")
	var enabled: bool=bool(withdrawal.get("enabled")) if is_instance_valid(withdrawal) else false
	var actors: Array=withdrawal.actor_states().duplicate(true) if is_instance_valid(withdrawal) and withdrawal.has_method("actor_states") else []
	check(posts.size()==2 and ids.has("left-shoulder-pad") and ids.has("right-shoulder-pad"),label_value+": exactly the original two shooting posts remain")
	check(posts.size()==2 and posts.all(func(row: Dictionary): return int(row.get("elevation",0))==2 and int(row.get("rangeBonusPercent",0))==24),label_value+": both retained posts are original high posts")
	check(not ids.any(func(id: String): return id.begins_with("painted-roadside-")),label_value+": added six roadside posts are absent")
	check(not enabled and actors.is_empty(),label_value+": added withdrawal mission and NPC actors are disabled")
	evidence[label_value+"Battle"]={"state":destination_snapshot(),"posts":posts,"withdrawalEnabled":enabled,"withdrawalActors":actors,"gold":int(app.game.gold),"friendly":app.game.units.size(),"enemies":app.game.enemies.size(),"hud":hud_evidence()}
	copy_visible_ui(app.ui,label_value+"HUD")

func finish(reason: String = "complete") -> void:
	if stopped: return
	if reason!="complete" and not output_dir.is_empty() and Engine.get_frames_drawn()>0 and DisplayServer.get_name()!="headless":
		var image: Image=root.get_texture().get_image()
		var path: String=output_dir.path_join("failure-final.png")
		captures.append({"label":"failure-final","path":ProjectSettings.globalize_path(path),"width":image.get_width(),"height":image.get_height(),"saveError":image.save_png(path),"phase":phase,"fullViewport":true,"artAccepted":false})
	stopped=true
	var end_hashes: Dictionary=rollback_hashes()
	check(source_hashes==end_hashes,"Product/QA/art source hashes remain unchanged during rollback capture")
	var report: Dictionary={"kind":"narrow-actual-painted-rollback","status":"evidence_collected" if reason=="complete" and failures.is_empty() else "partial_or_failed","reason":reason,"phase":phase,"checks":check_rows,"failures":failures,"captures":captures,"clicks":clicks,"inputTrace":input_trace,"hoverProbes":hover_probes,"evidence":evidence,"sources":source_hashes,"sourcesAtEnd":end_hashes,"rollbackExpectedSources":ROLLBACK_HASHES,"wallSeconds":wall_seconds(),"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"visualAcceptance":"pending_HQ_original_PNG_review","performanceMeasured":false,"automaticSecondClick":false,"gameplayStateInjected":false,"scope":"Actual Home/barracks/briefing/battle; fresh isolated save path. Full HUD/text retained. No placements or stress. Prior spear short click selects/previews by intended semantics; no recruitment or GUI-count failure assertion is applied here."}
	var file: FileAccess=FileAccess.open(output_dir.path_join("rollback-report.json"),FileAccess.WRITE)
	if file==null: push_error("Cannot save rollback report");quit(2);return
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("PAINTED_ROLLBACK ",JSON.stringify({"status":report.status,"reason":reason,"report":ProjectSettings.globalize_path(output_dir.path_join("rollback-report.json")),"failures":failures}))
	if is_instance_valid(app): app.queue_free()
	quit(0 if report.status=="evidence_collected" else 1)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=OUTPUT_ROOT.path_join("rollback-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	source_hashes=rollback_hashes()
	create_timer(90.0).timeout.connect(func(): finish("deadline") if not stopped else null)
	if not check(DisplayServer.get_name()!="headless" and canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(OUTPUT_ROOT))+"/"),"Rollback uses an isolated rendered FIX01 profile"):
		finish("profile_rejected");return
	for path in ROLLBACK_HASHES:
		if not check(str(source_hashes.get(path,""))==str(ROLLBACK_HASHES[path]),"Frozen rollback source matches: "+str(path)):
			finish("rollback_source_mismatch");return
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://rollback-"+str(int(Time.get_unix_time_from_system()))+".json"
	if not check(not FileAccess.file_exists(app.progress.save_path),"Fresh isolated player path is assigned before Main reads progress"):
		finish("profile_rejected");return
	root.add_child(app)
	await settle(4)
	if not alive(): return
	phase="home"
	await capture("home-1440x900")
	if not alive(): return
	if not check(app.front_end.visible and str(app.front_end.view)=="home","Actual Main starts on Home"): finish("home_failed");return
	if not await click_id(named_id(app.front_end,"HomeBarracks"),"Rollback Home barracks first click"): finish("barracks_input_failed");return
	if not check(await wait_until(func(): return alive() and app.barracks.visible,3.0),"Actual Home opens barracks"): finish("barracks_destination_failed");return
	phase="barracks"
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		await resize(dimensions)
		if not alive(): return
		var label_value: String="barracks-%dx%d" % [dimensions.x,dimensions.y]
		await capture(label_value)
		if not alive(): return
		commander_observation(label_value)
	if not await click_id(named_id(app.barracks,"BarracksBack"),"Rollback barracks back first click"): finish("back_input_failed");return
	if not check(await wait_until(func(): return alive() and app.front_end.visible and str(app.front_end.view)=="home" and not app.barracks.visible,3.0),"Actual back returns to Home"): finish("back_destination_failed");return
	await resize(Vector2i(1440,900))
	if not alive(): return
	phase="home_enter"
	await key_enter()
	if not alive(): return
	if not check(await wait_until(func(): return alive() and (str(app.modal_context)=="briefing" or (app.front_end.visible and str(app.front_end.view)=="catalog")),12.0),"One Home Enter reaches the real catalog or briefing"): finish("enter_failed");return
	if not alive(): return
	evidence["homeEnterDestination"]=destination_snapshot()
	if app.front_end.visible and str(app.front_end.view)=="catalog":
		await capture("actual-catalog-1440x900")
		if not alive(): return
		if not await click_id(named_id(app.front_end,"CatalogSortie"),"Rollback catalog sortie first click"): finish("catalog_input_failed");return
	if not check(await wait_until(func(): return alive() and is_instance_valid(app.modal) and str(app.modal_context)=="briefing" and (not is_instance_valid(app.scene_transition) or not app.scene_transition.is_running()),8.0),"Actual mission briefing settles"): finish("briefing_failed");return
	phase="briefing"
	await capture("briefing-1440x900")
	if not alive(): return
	copy_visible_ui(app.modal,"Briefing")
	if not await click_id(named_id(app.modal,"ConfirmMission"),"Rollback mission confirm first click"): finish("confirm_input_failed");return
	if not check(await wait_until(func(): return live_battle(),5.0),"First confirm reaches the actual live battle"): finish("battle_destination_failed");return
	phase="immediate_battle"
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		await resize(dimensions)
		if not alive(): return
		var label_value: String="battle-immediate-%dx%d" % [dimensions.x,dimensions.y]
		await capture(label_value)
		if not alive(): return
		battle_observation(label_value)
	phase="natural_short_observation"
	var clock_before: float=app.game.elapsed
	var wait_started: int=Time.get_ticks_usec()
	while live_battle() and Time.get_ticks_usec()-wait_started<3000000:
		await process_frame
	if not alive(): return
	check(live_battle() and app.game.elapsed>clock_before,"Short natural observation advances the battle clock without scripted timing changes")
	evidence["naturalShortWindow"]={"wallSeconds":float(Time.get_ticks_usec()-wait_started)/1000000.0,"clockBefore":clock_before,"clockAfter":app.game.elapsed,"performanceMeasured":false}
	await capture("battle-natural-three-seconds-1280x800")
	if not alive(): return
	battle_observation("battle-natural-three-seconds")
	finish()
