extends SceneTree
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var images: Array = []
var capture_enabled: bool = false

func _initialize() -> void:
	Engine.max_fps=60
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<25: push_error("UPGRADE_UI: "+note)

func settle(count: int = 6) -> void:
	for unused in range(count): await process_frame

func capture(name: String) -> void:
	if not capture_enabled: return
	app._layout()
	app.troops_3d._process(0)
	await settle(12)
	await RenderingServer.frame_post_draw
	var path: String="user://upgrade-%s-%dx%d.png" % [name,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"GPU capture "+name)
	images.append(ProjectSettings.globalize_path(path))

func all_nodes(node: Node) -> Array:
	var found: Array=[]
	for child in node.get_children():
		found.append(child)
		found.append_array(all_nodes(child))
	return found

func roster() -> void:
	for stage_id in app.progress.stage_numbers: app.progress.data.maps[stage_id]={"wins":1}
	app.progress.data.army.currency=100000
	for definition in app.progress.unit_catalog: app.progress.data.army.levels[str(definition.id)]=8
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		app._show_barracks()
		await settle()
		for definition in app.progress.unit_catalog:
			var id: String=str(definition.id)
			app.barracks._select_unit(id)
			await settle()
			var portrait: Control=app.barracks.find_child("SelectedArmyPortrait",true,false)
			check(portrait!=null and portrait.is_visible_in_tree(),"The barracks shows the selected actual commander: "+id)
			if portrait==null: continue
			var detail: Dictionary=portrait.diagnostics()
			check(bool(detail.static2D) and not bool(detail.actual3D) and not bool(detail.alphaCrossfade) and not bool(detail.depthOfField),"Historical portrait is static 2D without blur or model rendering: "+id)
			check(str(detail.heroId)==str(app.progress.army_commander(id).id),"The selected troop displays its confirmed named commander: "+id)
			check(root.get_visible_rect().encloses(portrait.get_global_rect()),"Portrait fits the barracks at "+str(dimensions))
			var title: Control=app.barracks.find_child("CommanderName",true,false)
			for run in title.get_text_layout().runs:
				check(Rect2(Vector2.ZERO,title.size).grow(1).encloses(run.bounds),"The commander kana/Japanese/Korean title fits its control")
			check(int(detail.pixelSize.y)==1536 and int(detail.pixelSize.x)==1024,"Historical cutouts share a 1024 by 1536 canvas")
			check(not bool(detail.fallback) and bool(detail.hasTransparency),"Actual named historical cutout loaded with alpha")
			check(not portrait.is_processing() and not portrait.is_physics_processing(),"Selected cutout has no animation loop")
			check(Rect2(Vector2.ZERO,portrait.size).grow(1).encloses(detail.visibleBounds),"Every visible alpha pixel fits inside the portrait area")
			var button: Button=app.barracks.find_child("Train_"+id,true,false)
			check(root.get_visible_rect().encloses(button.get_global_rect()),"The permanent upgrade action fits every supported viewport")
			for skill in app.progress.army_skills(id):
				var label: Control=app.barracks.find_child("Skill_"+str(skill.id),true,false)
				check(label!=null and bool(label.get_meta("unlocked")),"The actual barracks displays the Lv.8 mechanic as unlocked")
			if dimensions==Vector2i(1280,800) and id=="archer": await capture("barracks-archer")
			if dimensions==Vector2i(1920,1080):
				await capture("barracks-"+id)
			var loads_before: int=int(detail.loads)
			app.barracks.hide()
			await settle()
			check(not portrait.is_processing() and int(portrait.diagnostics().loads)==loads_before,"Hidden cutouts do no work or reload their art")
			app.barracks.show()
	app.barracks._select_unit("ninja")
	var current_maps: Dictionary=app.progress.data.maps.duplicate(true)
	for stage_id in app.progress.stage_numbers:
		if int(app.progress.stage_numbers[stage_id])>=35: app.progress.data.maps.erase(stage_id)
	app.barracks._rebuild()
	await settle()
	var predecessor: Control=app.barracks.find_child("SelectedArmyPortrait",true,false)
	check(str(predecessor.hero_id)=="hachisuka_masakatsu","The pre-1586 barracks uses the predecessor's historical portrait")
	await capture("barracks-ninja-predecessor")
	app.progress.data.maps=current_maps
	app.barracks.hide()
	app._return_from_barracks()

func queue_and_ruby() -> void:
	root.content_scale_size=Vector2i(1280,800)
	root.size=Vector2i(1280,800)
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app._stop_narration()
	app.game.gold=5000
	app.game.set_process(false)
	app.game.spawn_clock=3600
	app._choose_unit("commander")
	check(app.game.snapshot().recruitmentQueue.size()==1,"One cavalry card click immediately starts one independent production order")
	app._choose_unit("spear")
	check(app.game.snapshot().recruitmentQueue.size()==2,"One spear card click starts its order in parallel with cavalry")
	app._choose_unit("archer")
	check(not app.game.pending.is_empty(),"Selecting an archer still asks for its actual legal fixed position")
	var point: Vector2=Vector2(-1,-1)
	for zone in app.game.zones:
		if str(zone.get("placementRole",""))==str(app.game.placement_contract("archer").placementRole):
			var candidate: Vector2=app.game._zone_placement_hint(zone,"archer")
			if candidate.x>=0 and bool(app.game.placement_preview(candidate).valid):
				point=candidate
				break
	check(app.game.place_unit(point.x,point.y),"An archer reserves a real fixed post while producing")
	var before: Dictionary=app.game.snapshot()
	check(before.recruitmentQueue.size()==3 and app.game.units.is_empty(),"Different types can start three independent production jobs at once")
	app._on_state(before)
	app._layout()
	await settle()
	check(app.production_panel.is_visible_in_tree() and app.production_cards.get_child_count()==3,"Actual battle UI displays all simultaneous production orders")
	check(str(app.production_title.text).contains("병렬"),"The production header describes independent simultaneous generation")
	check(root.get_visible_rect().encloses(app.production_panel.get_global_rect()),"Production controls fit inside the actual battlefield viewport")
	if app.learning_field.report_card.is_visible_in_tree():
		check(not app.production_panel.get_global_rect().intersects(app.learning_field.report_card.get_global_rect()),"Production controls do not cover the visible battlefield learning report")
	for card in app.production_cards.get_children():
		check(card.get_meta("jobId")!=null and not card.disabled,"Each outstanding job has a clickable cancellation action")
		check(card.size.y<=app.production_scroll.size.y,"Both text lines of each production button fit its scroll row")
	app.game.advance_simulation(1.0)
	var after: Dictionary=app.game.snapshot()
	for index in range(3):
		check(is_equal_approx(float(before.recruitmentQueue[index].remainingSeconds)-float(after.recruitmentQueue[index].remainingSeconds),1),"Every job's own timer advances together")
	app._on_state(after)
	var vocabulary: Dictionary={"jp":"地面","reading":"じめん","ko":"땅바닥","parts":[{"text":"地","reading":"じ"},{"text":"面","reading":"めん"}]}
	var sentence: Dictionary={"jp":"地面は固いです。","reading":"じめんはかたいです。","ko":"땅바닥은 단단합니다.","parts":[{"text":"地面","reading":"じめん"},{"text":"は"},{"text":"固","reading":"かた"},{"text":"いです。"}]}
	app.active_word.set_word(vocabulary,36,true)
	app.example_label.set_word(sentence,28,true)
	app._layout()
	for control in [app.active_word,app.example_label]:
		var layout: Dictionary=control.get_text_layout()
		check(int(layout.ruby_size)>=22 and layout.guides.is_empty(),"The actual field uses large kana without separators or connecting lines")
		var reading_runs: Array = []
		for run in layout.runs:
			if run.role=="reading": reading_runs.append(run)
		check(reading_runs.size()>=2 and reading_runs[0].group!=reading_runs[1].group,"Adjacent kanji retain separate reading groups")
		for run in layout.runs:
			check(Rect2(Vector2.ZERO,control.size).grow(1).encloses(run.bounds),"Enlarged field readings preserve their glyph bounds")
	await capture("parallel-production-ruby")
	var first_card: Button=app.production_cards.get_child(0)
	var cost: int=int(after.recruitmentQueue[0].cost)
	var wallet: int=app.game.gold
	first_card.pressed.emit()
	check(app.game.gold==wallet+cost and app.game.snapshot().recruitmentQueue.size()==2,"The actual queue button cancels exactly its order and refunds once")
	var remaining_before: Array=app.game.snapshot().recruitmentQueue
	app.game.paused=true
	app.game.advance_simulation(10)
	check(app.game.snapshot().recruitmentQueue==remaining_before,"Pause preserves all simultaneous generation timers")
	app.game.paused=false
	app.game.advance_simulation(1.30)
	check(app.game.snapshot().recruitmentQueue.is_empty() and app.game.units.size()==3,"The shorter archer and double spear finish independently of the cancelled slower cavalry")
	app._on_state(app.game.snapshot())
	check(not app.production_panel.visible,"The queue overlay clears when all production is complete")
	app.game.advance_simulation(2.6)
	app._on_state(app.game.snapshot())
	await capture("produced-army")

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/upgrade-ui/").to_lower()):
		quit(2)
		return
	capture_enabled="--capture" in OS.get_cmdline_user_args()
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://qa-upgrade-ui-%d.json" % Time.get_ticks_msec()
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.progress.data.settings.voice=false
	app.progress.data.settings.music=false
	app._stop_narration()
	app.player.stop()
	await roster()
	await queue_and_ruby()
	var file = FileAccess.open("user://qa_combat_upgrade_ui.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"images":images},"\t"))
	file.close()
	print("UPGRADE_UI checks=%d failures=%d images=%d" % [checks,failures.size(),images.size()])
	app._stop_narration()
	app.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
