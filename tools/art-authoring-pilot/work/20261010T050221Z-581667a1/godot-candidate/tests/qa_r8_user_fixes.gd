extends "res://tests/qa_r8_lag.gd"
## Separate explicit user-fix validation; never used for the lag paired window.
var user_fix_receipts: Array = []
var user_fix_started: int = 0
var user_fix_ending: bool = false

func _initialize() -> void:
	call_deferred("user_fix_run")

func user_fix_watchdog() -> void:
	if not user_fix_ending and Time.get_ticks_usec()-user_fix_started>145000000:
		blockers.append("User-fix harness watchdog reached145s; incomplete checks remain unverified")
		user_fix_ending = true
		call_deferred("user_fix_finish")

func user_fix_unstarted_state() -> String:
	return JSON.stringify({"elapsed":app.game.elapsed,"running":app.game.running,"wave":app.game.wave,"enemies":app.game.enemies,"units":app.game.units,"spawns":app.game.spawn_queue,"production":app.game.recruitment_queue,"narration_battle_id":app.narration_battle_id,"battle_started":app.battle_started})

func user_fix_mission_gate() -> void:
	if not await desktop_click(desktop_button(app.modal_footer,"출진"),"Actual standard briefing opens mission modal"): return
	if not check(app.modal_context=="mission_briefing" and not app.battle_started and not app.game.running,"Mission modal appears before actual combat starts"): return
	var before: String = user_fix_unstarted_state()
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		await desktop_resize(dimensions)
		var caption: Control = app.modal_body.find_child("MissionBriefingText",true,false) as Control
		if check(is_instance_valid(caption),"Actual mission modal has production RubyText"):
			check(str(caption.word.get("jp",""))==str(app.current_story.get("briefingJP","")) and str(caption.word.get("ko",""))==str(app.current_story.get("briefingKo","")),"Mission Japanese and Korean match registered story")
			check(not str(caption.word.get("reading","")).is_empty() or not caption.word.get("parts",[]).is_empty(),"Mission carries native reading/parts")
			inspect_visible_furigana("Actual prebattle mission / "+str(dimensions),app.modal)
		var card: Rect2 = app.modal_card.get_global_rect()
		check(card.get_center().distance_to(Vector2(root.size)*.5)<1.0 and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(card),"Actual mission card is centered and inside viewport: "+str(dimensions))
		await create_timer(.5).timeout
		check(user_fix_unstarted_state()==before,"Before Confirm, combat clock/enemies/production/spawns stay frozen: "+str(dimensions))
		await capture("userfix-mission-%dx%d" % [dimensions.x,dimensions.y])
	var escape_press: InputEventKey = InputEventKey.new()
	escape_press.keycode = KEY_ESCAPE
	escape_press.physical_keycode = KEY_ESCAPE
	escape_press.pressed = true
	escape_press.echo = false
	Input.parse_input_event(escape_press)
	await settle(1)
	var escape_release: InputEventKey = InputEventKey.new()
	escape_release.keycode = KEY_ESCAPE
	escape_release.physical_keycode = KEY_ESCAPE
	escape_release.pressed = false
	escape_release.echo = false
	Input.parse_input_event(escape_release)
	await settle()
	check(app.modal_context=="briefing" and not app.battle_started and user_fix_unstarted_state()==before,"Native Escape returns to standard briefing without starting combat")
	if not await desktop_click(desktop_button(app.modal_footer,"출진"),"Re-enter actual mission modal"): return
	check(app.modal_context=="mission_briefing","Mission re-entry returns same gate")
	var confirm: Button = app.modal_footer.find_child("MissionBriefingConfirm",true,false) as Button
	if not await desktop_click(confirm,"Actual Confirm starts battle"): return
	check(app.battle_started and app.game.running,"Confirm starts native combat")
	var generation: int = app.game.battle_generation
	var narration_id: String = app.narration_battle_id
	# Controlled duplicate-handler guard, distinct from the preceding real click.
	app._confirm_mission_briefing()
	app._confirm_mission_briefing()
	check(app.game.battle_generation==generation and app.narration_battle_id==narration_id,"Duplicate Confirm handlers do not restart combat/narration")
	user_fix_receipts.append({"case":"mission modal","scope":"Actual entry, native Escape and Confirm clicks; duplicate-handler guard is controlled. Japanese/ruby/Korean pixels captured at both resolutions."})

func user_fix_archer_receipt() -> void:
	if not check(FileAccess.get_sha256("res://assets/units-animated/archer.png")=="74409c37a9b995e10b474ef6f083bd6399d509e10d65c03e4fb837669335883b","Exact approved blue archer PNG remains unchanged"): return
	var card: Button = app.army_grid.get_node_or_null("DeployCard_archer") as Button
	if not check(is_instance_valid(card) and not card.disabled,"Actual paid archer card is available"): return
	var target: Vector2 = Vector2(INF,INF)
	for zone in app.game.zones:
		var screen: Vector2 = app.game.field_point_to_screen(Vector2(zone.position))
		if str(zone.get("placementRole",""))=="ranged" and not app._deployment_surface_point(screen).is_empty() and bool(app.game.deployment_preview("archer",Vector2(zone.position),"").get("valid",false)):
			target = screen
			break
	if not check(target.is_finite(),"Actual pad offers legal visible archer destination"): return
	var order: int = app.game.next_recruitment_id
	var gold: int = app.game.gold
	var cost: int = app.game.recruit_cost("archer")
	await mouse(card.get_global_rect().get_center(),true)
	await motion(target)
	var preview: Node3D = app.troops_3d.placement_actor
	if check(is_instance_valid(preview) and preview.visible,"Actual drag creates visible placement preview"):
		user_fix_sprite(preview,"Actual paid preview")
		await capture("userfix-archer-preview")
	await mouse(target,false)
	if not check(app.game.next_recruitment_id==order+1 and app.game.gold<=gold-cost,"Actual release accepts exactly one paid archer order"): return
	var started: int = Time.get_ticks_usec()
	var paid: Node3D = null
	while Time.get_ticks_usec()-started<45000000 and not user_fix_ending:
		await process_frame
		await lag_continue_native_ui()
		for actor in app.troops_3d.actors.values():
			if actor.unit_type=="archer" and not actor.hostile:
				paid = actor
				break
		if is_instance_valid(paid): break
	if not check(is_instance_valid(paid),"Natural Game production creates actual paid archer actor"): return
	user_fix_sprite(paid,"Actual naturally produced paid archer")
	var actual: Dictionary = paid.authored_archer_diagnostics()
	user_fix_receipts.append({"case":"actual paid archer","diagnostics":actual,"scope":"Normal paid UI drag and native production. No clock/HP/actor injection."})
	await capture("userfix-archer-paid")
	# Separate controlled presentation fixture: no synthetic combat claim.
	var fixture: Node3D = load("res://native/sengoku_actor_3d.gd").new()
	app.troops_3d.world.add_child(fixture)
	fixture.configure("archer",false,99001,false,0)
	fixture.hide()
	var authoritative: String = JSON.stringify(app.game.actor_states())
	for data in [{"animation":"idle","animationClock":.41,"animationPhase":0.0},{"animation":"walk","animationClock":.41,"animationPhase":0.0},{"animation":"attack","animationClock":.32,"attackDuration":.5,"releaseTime":.3,"attackReleased":false},{"animation":"attack","animationClock":.31,"attackDuration":.5,"releaseTime":.3,"attackReleased":true},{"animation":"attack","animationClock":.32,"attackDuration":.5,"releaseTime":.3,"attackReleased":false,"attackCancelled":true},{"animation":"death","animationClock":.3},{"animation":"death","animationClock":.7}]:
		fixture.apply_state(data)
		var diagnostic: Dictionary = fixture.authored_archer_diagnostics()
		var sprite: Sprite3D = fixture.get_node("AuthoredArcherSprite") as Sprite3D
		match str(data.animation):
			"idle": check(diagnostic.row==0 and diagnostic.frame==2,"Controlled idle uses row0 and5fps native clock")
			"walk": check(diagnostic.row==1 and diagnostic.frame==3,"Controlled walk uses row1 and9fps native clock")
			"attack":
				check(diagnostic.row==2,"Controlled attack uses authored row2")
				if bool(data.get("attackReleased",false)): check(diagnostic.frame>=4 and diagnostic.attackReleased,"Actual release receipt enables authored release/recovery cells")
				elif bool(data.get("attackCancelled",false)): check(diagnostic.frame==5 and not diagnostic.attackReleased,"Cancelled shot recovers without a release receipt")
				else: check(diagnostic.frame<=3 and not diagnostic.attackReleased,"Elapsed clock alone does not release before actual receipt")
			"death": check(diagnostic.row==3 and diagnostic.frame==mini(5,int(floor(float(data.animationClock)*9.0))) and (sprite.modulate.a==0.0 if float(data.animationClock)>.6667 else sprite.modulate.a>0.0),"Controlled death row follows original clock and fade")
		user_fix_receipts.append({"case":"controlled sprite animation","input":data,"diagnostics":diagnostic})
	check(JSON.stringify(app.game.actor_states())==authoritative,"Controlled renderer fixtures do not change Game actors")
	var sprite_lifetime: WeakRef = weakref(fixture.get_node("AuthoredArcherSprite"))
	fixture.show()
	check(fixture.get_node("AuthoredArcherSprite").is_visible_in_tree()==false,"Completed death fade keeps sprite invisible even when actor root is shown")
	fixture.apply_state({"animation":"idle","animationClock":0.0,"animationPhase":0.0})
	check(fixture.get_node("AuthoredArcherSprite").is_visible_in_tree(),"Controlled live renderer is visible under visible root")
	fixture.hide()
	check(not fixture.get_node("AuthoredArcherSprite").is_visible_in_tree(),"Actor root culling also hides authored child")
	fixture.queue_free()
	await process_frame
	check(sprite_lifetime.get_ref()==null,"Actor queue_free removes authored sprite child")

func user_fix_sprite(actor: Node3D, note: String) -> void:
	var sprite: Sprite3D = actor.get_node_or_null("AuthoredArcherSprite") as Sprite3D
	if not check(is_instance_valid(sprite),note+": native actor owns authored Sprite3D"): return
	check(sprite.texture.resource_path=="res://assets/units-animated/archer.png" and sprite.hframes==6 and sprite.vframes==4 and sprite.texture.get_size()==Vector2(1536,1024),note+": actual texture and frame grid match approved sheet")
	check(sprite.is_visible_in_tree() and sprite.billboard==BaseMaterial3D.BILLBOARD_ENABLED and not sprite.no_depth_test and not sprite.fixed_size,note+": actual visible billboard retains world depth and scale")
	check(not actor.rig.visible and not actor.boat.visible and actor.meshes.is_empty(),note+": procedural body and weapon are absent")
	var triangle: TriangleMesh = sprite.generate_triangle_mesh()
	if not check(is_instance_valid(triangle),note+": actual sprite generates triangle geometry"): return
	var faces: PackedVector3Array = triangle.get_faces()
	if not check(faces.size()>=3,note+": actual sprite vertices exist"): return
	var top: float = -INF
	var left: float = INF
	var right: float = -INF
	for vertex in faces:
		top = maxf(top,vertex.y)
		left = minf(left,vertex.x)
		right = maxf(right,vertex.x)
	var baseline_y: float = top-228.0*sprite.pixel_size
	check(absf(baseline_y)<.00001 and absf((left+right)*.5)<.00001 and sprite.position==Vector3.ZERO,note+": actual vertices place PNG pixel(128,228) at actor foot root")
	user_fix_receipts.append({"case":note,"diagnostics":actor.authored_archer_diagnostics(),"geometry":{"top":top,"left":left,"right":right,"baselineY":baseline_y,"pixelSize":sprite.pixel_size}})

func user_fix_finish() -> void:
	user_fix_ending = true
	var after: Dictionary = lag_hashes()
	check(after==lag_sources,"Approved user-fix copied sources remain frozen")
	var report: Dictionary = {"status":"FAIL" if not failures.is_empty() else ("BLOCKED" if not blockers.is_empty() else "PASS"),"checks":checks,"failures":failures,"blockers":blockers,"source_hashes_before":lag_sources,"source_hashes_after":after,"source_freeze_unchanged":after==lag_sources,"receipts":user_fix_receipts,"captures":captures,"furigana_surfaces":furigana_surfaces,"furigana_geometry":furigana_geometry,"scope":"Explicit user fixes, separate from lag timing comparison. No fullsuite/overallG1/natural fullvictory claim."}
	var file: FileAccess = FileAccess.open("user://user-fixes-raw.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await settle()
	print("R8_USER_FIXES ",report.status," checks=",checks," failures=",failures.size()," blockers=",blockers.size())
	quit(0 if report.status=="PASS" else 1)

func user_fix_run() -> void:
	user_fix_started = Time.get_ticks_usec()
	process_frame.connect(user_fix_watchdog)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): lag_manifest = arg.trim_prefix("--manifest=")
	if not lag_guard():
		quit(2)
		return
	if not check(canonical(lag_manifest).begins_with(EVIDENCE_ROOT+"/") and FileAccess.file_exists(lag_manifest),"Separate HQ user-fix manifest required"):
		quit(2)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(lag_manifest))
	if not check(manifest is Dictionary and manifest.get("sources") is Dictionary,"Exact user-fix source manifest exists"):
		quit(2)
		return
	lag_sources = manifest.sources.duplicate(true)
	if not check(lag_hashes()==lag_sources,"User-fix source approval matches before initialization"):
		quit(2)
		return
	capture_requested = true
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	var store: RefCounted = Store.new()
	store.save_path = "user://user-fixes-private-account.json"
	store.read_save()
	app = load("res://native/main.tscn").instantiate()
	app.progress = store
	root.add_child(app)
	await settle()
	await desktop_resize(Vector2i(1440,900))
	if not await desktop_click(app.front_end.get_node_or_null("HomeSortie") as Button,"Actual user-fix Home sortie") or not await desktop_wait_catalog_entry():
		await user_fix_finish()
		return
	if not await desktop_click(app.front_end.find_child("Stage_basic-forest",true,false) as Button,"Actual user-fix stage selection") or not await desktop_click(app.front_end.get_node_or_null("CatalogSortie") as Button,"Actual user-fix catalog sortie"):
		await user_fix_finish()
		return
	await user_fix_mission_gate()
	if failures.is_empty(): await user_fix_archer_receipt()
	await user_fix_finish()
