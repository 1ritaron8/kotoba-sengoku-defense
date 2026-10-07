extends SceneTree
## Actual inspector/card bindings to approved authored poses. These are raster
## class portraits; evolution remains in names, stats and battlefield equipment.
const Portrait = preload("res://native/barracks_portrait.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array = []
var observations: Array = []
var app: Node
var capture_enabled: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("BATTLE PORTRAIT QA: "+message)

func settle() -> void:
	await process_frame
	await process_frame

func capture(name: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = "res://dist/preview-battle-portrait-"+name+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"Actual GPU inspector capture saves: "+name)

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"):
		push_error("Battle portrait QA refuses the player's profile")
		quit(2)
		return
	capture_enabled = OS.get_cmdline_user_args().has("--capture")
	root.size = Vector2i(1440,900)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://battle-portraits-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	root.add_child(app)
	await settle()
	app.progress.data.settings.music = false
	app.progress.data.settings.voice = false
	app.player.stop()
	app.game.set_process(false)
	check(app.selected_portrait.get_script()==Portrait,"Inspector uses the same authored live helper as the approved barracks")
	check(not app.selected_portrait.active,"Home hides and stops the inspector idle clock")
	# Fixture unlocks only; it neither completes maps nor awards persistent funds.
	for index in range(14): app.progress.data.maps[str(app.maps[index].id)] = {"wins":1}
	check(app.progress.unlocked_units().size()==8,"Fixture unlocks all eight actual roster classes")
	app._select_map(0)
	app._close_modal(false)
	app.game.set_input_enabled(true)
	var identities: Dictionary = {}
	for id in TYPES:
		for level in [1,4,8]:
			app.progress.data.army.levels[id] = level
			app.chosen_unit_id = id
			app.game.configure_roster(app.progress.unit_catalog,app.progress.unlocked_units(),app.progress.data.army.levels)
			app.game.load_map(app.current_map)
			app._rebuild_army_cards()
			await settle()
			var evolution: int = int(app.progress.army_evolution(id).stage)
			var state: Dictionary = app.selected_portrait.diagnostics()
			var source: Dictionary = Portrait.source_for(id,evolution)
			check(bool(state.ready) and bool(state.active),id+": inspector has real authored artwork")
			check(str(state.unitId)==id and int(state.evolution)==evolution,id+": actual class/evolution identity is retained")
			check(str(state.sourceKind)=="authored-idle-sheet" and str(state.sourcePath)==str(source.path) and int(state.row)==int(source.row),id+": correct original sheet and row are bound")
			check(not bool(state.visualEvolution),id+": portrait does not claim nonexistent evolution artwork")
			check(int(state.frames)==6 and float(state.fps)==2.0,id+": six real approved poses are used")
			var key: String = str(source.path)+":"+str(source.row)
			identities[id] = key
			var picture: TextureRect = app.army_grid.get_node("DeployCard_%s/UnitPortrait_%s" % [id,id])
			check(picture.texture is AtlasTexture,id+": deployment icon is an original atlas crop")
			if picture.texture is AtlasTexture:
				var atlas: AtlasTexture = picture.texture
				var first: AtlasTexture = Portrait.first_frame_texture(id,evolution)
				check(atlas.atlas.resource_path==str(source.path) and first.region.encloses(atlas.region),id+": icon samples only the actual class's first idle cell")
				check(atlas.region.size.y<first.region.size.y*.6,id+": icon uses a readable bust instead of a tiny full body")
			check(str(picture.get_meta("unit_id",""))==id and str(picture.get_meta("source_kind",""))=="authored-idle-sheet",id+": metadata identifies the actual approved character")
			check(not bool(picture.get_meta("visual_evolution",true)),id+": static icon is honest about class art across evolution levels")
			check(app.army_panel.size.x==330 and app.selected_portrait_window.size==Vector2(98,120),id+": existing inspector width and portrait slot are preserved")
			check(app.selected_word.position==Vector2(110,2) and app.selected_label.position==Vector2(110,78),id+": names and statistics keep their existing readable positions")
			check(app.selected_portrait_window.clip_contents,id+": the enlarged pose cannot spill over names or actions")
			var clip: Rect2 = app.selected_portrait_window.get_global_rect()
			var focus: Rect2 = app.PORTRAIT_FOCUS[id]
			var scale: float = minf(clip.size.x/focus.size.x,clip.size.y/focus.size.y)
			check(scale>.85 and app.selected_portrait.size.y>150,id+": authored face is displayed at bust scale")
			app.selected_portrait._process(.27)
			var clock: float = app.selected_portrait.elapsed
			var fixed_position: Vector2 = app.selected_portrait.position
			for index in range(120): app._on_state(app.game.snapshot())
			check(is_equal_approx(app.selected_portrait.elapsed,clock),id+": 120 unchanged state updates do not reconfigure/reset animation")
			var old_frame: int = app.selected_portrait.frame
			app.selected_portrait._process(.6)
			check(app.selected_portrait.frame!=old_frame,id+": idle animation advances actual source poses")
			check(app.selected_portrait.position==fixed_position,id+": animation uses a fixed viewport transform, without shaking the portrait canvas")
			check(app.selected_word.word.jp==str(app.progress.army_evolution(id).jp),id+": existing evolution name remains correct")
			observations.append({"id":id,"level":level,"evolution":evolution,"source":state.sourcePath,"row":state.row,"bustRegion":str(focus),"visualEvolution":false})
			if id in ["archer","samurai","ninja"] and level==1: await capture(id)
	var distinct: Dictionary = {}
	for value in identities.values(): distinct[value] = true
	check(distinct.size()==8,"Eight classes bind eight distinct approved character sources/rows")
	check(Portrait.source_for("missing-class").is_empty() and app._authored_bust_texture("missing-class",0)==null,"Missing art never borrows another class or procedural portrait")
	var clock: float = app.selected_portrait.elapsed
	app._show_catalog()
	app.selected_portrait._process(.5)
	check(not app.selected_portrait.active and not app.selected_portrait.is_processing() and app.selected_portrait.elapsed==clock,"Hidden navigation stops authored idle without changing the saved animation clock")
	app._resume_from_navigation()
	check(app.selected_portrait.active and app.selected_portrait.elapsed==clock,"Returning from navigation resumes the same character and clock")
	app._show_barracks()
	app.selected_portrait._process(.5)
	check(not app.selected_portrait.active and app.selected_portrait.elapsed==clock,"Barracks also hides/stops the battle inspector")
	app.barracks.hide()
	app._return_from_barracks()
	app._select_map(0)
	app._close_modal(false)
	app.game.set_input_enabled(true)
	app.progress.data.army.levels.commander = 8
	app.chosen_unit_id = "archer"
	app.game.configure_roster(app.progress.unit_catalog,app.progress.unlocked_units(),app.progress.data.army.levels)
	check(app.game.recruit("commander"),"An actual mounted commander can be recruited for inspector verification")
	var deployed: bool = false
	for point in app.game.placement_hints:
		if app.game.place_unit(point.x,point.y):
			deployed = true
			break
	check(deployed,"Actual commander selection comes from a legal battlefield placement")
	app._on_state(app.game.snapshot())
	check(app.chosen_unit_id=="archer" and app.selected_portrait.unit_id=="commander", "Selected mounted unit takes precedence over the recruitment card's class")
	check(app.selected_portrait.evolution_stage==2 and app.selected_word.word.jp==str(app.progress.army_evolution("commander").jp),"Mounted unit retains its evolved name and matching class portrait")
	check(app.selected_label.text.begins_with("훈련 Lv.8") and app.selected_label.text.contains("초당"),"Mounted inspection keeps actual deployed level, damage and DPS fields")
	await capture("commander")
	if capture_enabled:
		await create_timer(.65).timeout
		await capture("commander-idle")
		root.size = Vector2i(1280,800)
		await settle()
		check(app.selected_portrait_window.size==Vector2(98,120) and app.army_panel.size.x==330,"Minimum viewport preserves readable inspector geometry")
		await capture("commander-1280")
	var report_path: String = "user://qa_battle_portraits.json" if OS.get_cmdline_user_args().has("--packed") else "res://tests/qa_battle_portraits.json"
	var out: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	check(out!=null,"Portrait verification report can be written")
	if out!=null:
		out.store_string(JSON.stringify({"checks":checks,"failures":failures,"profile":profile,"observations":observations,"capture":capture_enabled},"  "))
		out.close()
	print("BATTLE_PORTRAITS_QA ",JSON.stringify({"checks":checks,"failures":failures,"variants":observations.size(),"capture":capture_enabled}))
	app.player.stop()
	app.player.stream = null
	await create_timer(.5).timeout
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
