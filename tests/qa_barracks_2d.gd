extends SceneTree

const Store = preload("res://native/progress.gd")
const Barracks = preload("res://native/barracks.gd")
const Portrait = preload("res://native/commander_portrait.gd")
const UnitPreview = preload("res://native/barracks_portrait.gd")
const GameFonts = preload("res://native/game_fonts.gd")

var panel: Control
var store: RefCounted
var checks: int = 0
var failures: Array = []
var images: Array = []
var observations: Array = []
var capture_enabled: bool = false
var packed: bool = false
var require_named: bool = false
var changed_count: int = 0
var closed_count: int = 0
var trained_units: Array = []
var detailed_geometry: Dictionary = {}

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size()<25: push_error("BARRACKS_2D: "+note)

func settle(count: int = 8) -> void:
	for unused in range(count): await process_frame

func nodes(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		result.append(child)
		result.append_array(nodes(child))
	return result

func named(value: String) -> Control:
	return panel.find_child(value,true,false) as Control

func click(value: String) -> void:
	var button: Button = named(value) as Button
	check(button!=null and not button.disabled,"The actual action is enabled: "+value)
	if button!=null and not button.disabled:
		button.pressed.emit()
		await settle()

func caption_bounds(control: Control, note: String) -> void:
	for run in control.get_text_layout().runs:
		check(Rect2(Vector2.ZERO,control.size).grow(1).encloses(run.bounds),note+": complete glyph bounds "+str(run.text))
	check(int(control.get_text_layout().ruby_size)>=16,note+": readable kana size")

func geometry(id: String, dimensions: Vector2i) -> void:
	var screen: Rect2 = root.get_visible_rect()
	var portrait: Control = named("SelectedArmyPortrait")
	check(portrait!=null and portrait.get_script()==Portrait,"Selected art uses the shared static 2D component: "+id)
	var details: Dictionary = portrait.diagnostics()
	check(bool(details.ready),"Selected art is available or has a safe same-class fallback: "+id)
	if require_named:
		check(not bool(details.fallback) and str(details.sourcePath)=="res://assets/commanders/"+str(store.army_commander(id).id)+".png","The production commander uses its final named cutout: "+id)
		check(bool(details.hasTransparency),"The named illustration has a transparent cutout background: "+id)
		check(details.pixelSize==Vector2(1024,1536),"The final commander artwork uses the common 1024x1536 canvas: "+id)
	check(str(details.heroId)==str(store.army_commander(id).id),"The correct historical commander/successor is selected: "+id)
	check(not portrait.is_processing() and not portrait.is_physics_processing(),"The selected illustration has no animation/process cost: "+id)
	check(screen.encloses(portrait.get_global_rect()),"The complete portrait control fits: "+id+" "+str(dimensions))
	check(portrait.size.x>=260 and portrait.size.y>=360,"The selected portrait has a large minimum presentation: "+id)
	var art_bounds: Rect2 = details.visibleBounds
	check(Rect2(Vector2.ZERO,portrait.size).grow(1).encloses(art_bounds),"No nonzero-alpha face/clothing edge is cropped: "+id)
	var title: Control = named("CommanderName")
	caption_bounds(title,"Commander name "+id)
	check(title.get_text_layout().ruby_size>=20,"Historical commander names keep large kana: "+id)
	var plaque: Control = named("CommanderNamePlaque")
	check(plaque.get_global_rect().grow(1).encloses(title.get_global_rect()),"A light paper nameplate separates ink from the painted background: "+id+" plaque="+str(plaque.get_global_rect())+" title="+str(title.get_global_rect()))
	check(not title.get_global_rect().intersects(portrait.get_global_rect()),"The commander name has its own readable area: "+id)
	var detail: Control = named("CommanderDetail")
	var roster: Control = named("BarracksRoster")
	var header: Control = named("BarracksHeader")
	for item in nodes(header):
		if item is Label:
			check(header.get_global_rect().grow(1).encloses(item.get_global_rect()),"Header labels leave the lower border clear: "+str(item.name))
	check(screen.encloses(detail.get_global_rect()) and screen.encloses(roster.get_global_rect()),"Detail and the eight-unit selector fit: "+id)
	check(not detail.get_global_rect().intersects(roster.get_global_rect()) and not portrait.get_global_rect().intersects(detail.get_global_rect()),"Illustration, details and selector have distinct areas: "+id)
	check(portrait.position.x>detail.get_global_rect().end.x,"The static historical commander is to the right of the skill panel: "+id)
	var skill_scroll: ScrollContainer = named("CommanderSkillsScroll") as ScrollContainer
	var actions: Control = named("CommanderUpgradeActions")
	check(detail.get_global_rect().encloses(actions.get_global_rect()),"The real permanent upgrade footer stays inside the detail frame: "+id+" detail="+str(detail.get_global_rect())+" actions="+str(actions.get_global_rect()))
	check(not skill_scroll.get_global_rect().intersects(actions.get_global_rect()),"Long skill descriptions cannot cover upgrade controls: "+id)
	check(skill_scroll.size.y>=84,"Small screens retain a usable skill scroll area: "+id)
	for item in nodes(portrait):
		check(not item is SubViewport and not item is Node3D,"The historical commander portrait remains static 2D: "+str(item.name))
	for item in nodes(panel):
		if item is Label:
			check(item.get_theme_font_size("font_size")>=20,"Visible Korean/UI labels retain at least 20px: "+str(item.name))
			check(item.get_minimum_size().y<=item.size.y+1,"Wrapped label gets its full height: "+str(item.name)+" "+id)
		if item is Button:
			check(screen.encloses(item.get_global_rect()),"Every real button fits: "+str(item.name)+" "+str(dimensions))
			if not item.text.is_empty():
				var box: StyleBox = item.get_theme_stylebox("normal")
				var available: float = item.size.x-box.get_content_margin(SIDE_LEFT)-box.get_content_margin(SIDE_RIGHT)
				check(item.get_theme_font("font").get_string_size(item.text,HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x<=available+1,"Button text is readable without clipping: "+str(item.name))
	var cards: Array = panel.find_children("ArmyCard_*","Button",true,false)
	check(cards.size()==8,"Exactly eight actual troop selectors are displayed")
	for card in cards:
		check(panel.scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"All eight troop cards are visible together: "+str(card.name))
		caption_bounds(card.get_node("ArmyCardName"),"Troop selector "+str(card.name))
		var card_ruby: Control = card.get_node("ArmyCardName")
		check(card_ruby.colour_reading_groups and not card_ruby.merge_adjacent_readings and not card_ruby.show_reading_guides,"Troop reading/body colours follow authored parts without added separators")
		var reading_colours: Dictionary = {}
		var layout: Dictionary = card_ruby.get_text_layout()
		for run in layout.runs:
			if str(run.role)=="reading": reading_colours[int(run.group)]=Color(run.color)
		for run in layout.runs:
			if reading_colours.size()>1 and str(run.role)=="body" and reading_colours.has(int(run.group)):
				check(Color(run.color)==reading_colours[int(run.group)],"Each actual kanji part and its kana use the same colour: "+str(card.name))
		if reading_colours.size()>1:
			var groups: Array = reading_colours.keys()
			check(reading_colours[groups[0]]!=reading_colours[groups[1]] and layout.guides.is_empty(),"Separate authored kana parts use gold/blue without extra lines: "+str(card.name))
		check(bool(card.get_meta("selected"))==(str(card.get_meta("unitId"))==id),"Exactly the inspected troop has the selected marker")
	var all_skills: Array = store.army_skills(id)
	var basic_ninja: bool = id=="ninja" and all_skills.is_empty()
	check(str(named("CommanderSkillHeading").text)==("기습·암살 운용" if basic_ninja else "전투 스킬"),"The section uses accurate battle-skill/basic-operation wording: "+id)
	check(str(named("CommanderSkillThresholds").text)==("기본 행동" if basic_ninja else "영구 Lv.3 · 5 · 8"),"Ninja basics do not imply unregistered Lv3/5/8 unlocks: "+id)
	if basic_ninja:
		check(store.unit_definition(id).get("skillUnlocks",[]).is_empty(),"Ninja retains the unchanged empty skill-unlock contract")
		var texts: Array[String] = []
		for action_id in ["ambush","raid","return"]:
			var heading: Label = named("NinjaBasic_"+action_id) as Label
			var description: Label = named("NinjaBasicDescription_"+action_id) as Label
			check(heading!=null and description!=null,"The actual ninja action has a separate readable explanation: "+action_id)
			texts.append(heading.text+" "+description.text)
			check(not (heading.text+description.text).contains("Lv."),"Basic ninja actions never show invented skill-level thresholds: "+action_id)
		check(texts[0].contains("보라색") and texts[0].contains("자동"),"Ambush explains the actual violet concealment placement and automatic nearby attack")
		check(texts[1].contains("선택") and texts[1].contains("클릭") and texts[1].contains("같은 길") and texts[1].contains("즉사를 보장하지") and texts[1].contains("물이나 막힌 지형"),"Ninja raid explains selection, direct orders, range/land constraints and ordinary attacks")
		check(texts[2].contains("처음 배치한 엄폐") and texts[2].contains("돌아가 대기"),"Ninja returns to its original concealment point after a raid")
	for skill in all_skills:
		var heading: Control = named("Skill_"+str(skill.id))
		check(heading!=null and bool(heading.get_meta("unlocked"))==(id in store.unlocked_units() and bool(skill.unlocked)),"Lv.3/5/8 availability follows actual permanent level: "+str(skill.id))
		check(str(named("SkillDescription_"+str(skill.id)).text)==str(skill.descriptionKo),"The actual approved skill text is retained: "+str(skill.id))
	observations.append({"unit":id,"dimensions":str(dimensions),"hero":details.heroId,"portrait":str(portrait.get_global_rect()),"visibleArt":str(art_bounds),"fallback":details.fallback,"skillsHeight":skill_scroll.size.y,"detail":str(detail.get_global_rect()),"actions":str(actions.get_global_rect())})
	preview_geometry(id,dimensions)
	if not all_skills.is_empty() or basic_ninja:
		skill_scroll.scroll_vertical=int(skill_scroll.get_v_scroll_bar().max_value)
		await settle()
		var last: Control = named("NinjaBasicDescription_return") if basic_ninja else named("SkillDescription_"+str(all_skills[-1].id))
		check(skill_scroll.get_global_rect().grow(2).encloses(last.get_global_rect()),"The final skill description is fully reachable by scrolling: "+id)
		var amount: int = skill_scroll.scroll_vertical
		panel._rebuild()
		await settle()
		check(panel.skills_scroll.scroll_vertical==amount,"Same-unit rebuild keeps the skill reading position: "+id+" before="+str(amount)+" after="+str(panel.skills_scroll.scroll_vertical))

func preview_geometry(id: String, dimensions: Vector2i) -> void:
	var preview: Control = named("SelectedUnitPreview")
	check(preview!=null and preview.get_script()==UnitPreview,"The soldier uses the original authored standing artwork: "+id)
	var details: Dictionary = preview.diagnostics()
	check(details.ready and details.unitId==id and details.sourceKind=="authored-idle-sheet","The actual class source loaded successfully: "+id)
	check(FileAccess.file_exists(str(details.sourcePath)) or ResourceLoader.exists(str(details.sourcePath)),"The standing sheet is present in this build: "+id)
	check(details.evolution==int(store.army_evolution(id).stage),"The selected permanent equipment metadata follows the actual level: "+id)
	check(nodes(panel).filter(func(item): return item is SubViewport or item is Node3D).is_empty(),"Barracks uses no 3D model or 3D rendering viewport: "+id)
	check(preview.mouse_filter==Control.MOUSE_FILTER_IGNORE and preview.output.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Standing art cannot intercept the actual controls: "+id)
	var skill_scroll: Control = named("CommanderSkillsScroll")
	check(preview.get_global_rect().position.x>=skill_scroll.get_global_rect().end.x,"The standing soldier is to the right of the skill descriptions: "+id)
	check(named("CommanderDetail").get_global_rect().encloses(preview.get_global_rect()),"The standing portrait fits its skill panel: "+id+" "+str(dimensions))
	check(not preview.get_global_rect().intersects(named("CommanderUpgradeActions").get_global_rect()) and not preview.get_global_rect().intersects(named("BarracksRoster").get_global_rect()),"All actions and troop selectors remain visible: "+id)
	check(Rect2(Vector2.ZERO,preview.size).grow(1).encloses(details.renderedBounds),"Every visible standing body/weapon edge fits the preview: "+id)
	check(not preview.animate_poses and not preview.smooth_blending and not preview.is_processing() and not details.active,"The selected standing pose stays sharp and static without repeated updates: "+id)
	check(int(details.frame)==0 and is_zero_approx(float(details.blend)),"The original first standing pose does not blend with another frame: "+id)
	var texture_id: int = preview.texture.get_instance_id()
	var foot: Vector2 = details.footPosition
	for unused in range(60): preview._process(.01)
	var after: Dictionary = preview.diagnostics()
	check(texture_id==preview.texture.get_instance_id() and after.footPosition==foot and after.frame==details.frame and after.animationClock==details.animationClock,"Static previews do not flicker, move their feet or allocate new textures: "+id)
	observations.append({"unit":id,"dimensions":str(dimensions),"preview":str(preview.get_global_rect()),"source":details.sourcePath,"standing":true,"equipment":details.evolution,"drawRect":str(details.drawRect)})

func preview_visibility() -> void:
	panel.open()
	await settle()
	var preview: Control = named("SelectedUnitPreview")
	var preview_id: int = preview.get_instance_id()
	var before: Dictionary = store.data.duplicate(true)
	var pose: Dictionary = preview.diagnostics()
	for unused in range(4):
		panel.hide()
		await settle()
		preview._process(2.0)
		check(not preview.is_processing(),"A hidden standing portrait has no CPU animation cost")
		panel.show()
		await settle()
		check(not preview.is_processing() and preview.get_instance_id()==preview_id,"Returning preserves the same sharp static portrait")
		check(preview.diagnostics().animationClock==pose.animationClock and preview.diagnostics().frame==pose.frame,"Show/hide does not change the standing pose")
	check(store.data==before,"Standing previews never change economy, learning or battle settings")
	var old_preview: WeakRef = weakref(preview)
	panel._select_unit("monk")
	await settle()
	check(old_preview.get_ref()==null and nodes(panel).filter(func(item): return item is SubViewport).is_empty(),"Changing the troop releases old standing controls without a GPU viewport")

func capture(id: String, _impact: bool = false) -> void:
	if not capture_enabled: return
	await settle(12)
	await RenderingServer.frame_post_draw
	var path: String = "user://barracks-2d-%s-%dx%d.png" % [id,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"Rendered standing barracks capture saved: "+id)
	images.append(ProjectSettings.globalize_path(path))

func ui_matrix() -> void:
	for stage_id in store.stage_numbers: store.data.maps[stage_id]={"wins":1}
	store.data.army.currency=100000
	for definition in store.unit_catalog: store.data.army.levels[str(definition.id)]=8
	var original: Dictionary = store.data.duplicate(true)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		panel.open()
		await settle()
		var background: TextureRect = named("BarracksWarroom") as TextureRect
		check(background.texture!=null and background.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_COVERED,"Warroom art fills the viewport with aspect-preserving cover")
		check(root.get_visible_rect().encloses(background.get_global_rect()),"Background follows the actual viewport")
		check(panel.get_children().filter(func(item): return item is ColorRect).is_empty(),"No solid full-screen overlay obscures the painted warroom")
		for definition in store.unit_catalog:
			var id: String = str(definition.id)
			await click("ArmyCard_"+id)
			await geometry(id,dimensions)
			if dimensions!=Vector2i(1440,900):
				await capture(id)
		check(store.data==original,"Selection/resize/scroll are read-only for all learning, progress and economy")
	for level in [1,2,3,4,5,7,8,10]:
		for definition in store.unit_catalog:
			var id: String = str(definition.id)
			store.data.army.levels[id]=level
			panel._select_unit(id)
			await settle()
			for skill in store.army_skills(id):
				check(bool(named("Skill_"+str(skill.id)).get_meta("unlocked"))==(level>=int(skill.level)),"Actual level boundary changes visible skill availability: "+id+" Lv."+str(level))
			check(bool(named("Train_"+id).disabled)==(level>=10),"The real maximum level controls upgrade availability: "+id)
			if id=="ninja": check(store.army_skills(id).is_empty() and str(named("CommanderSkillThresholds").text)=="기본 행동","Permanent ninja levels never invent new skill thresholds: Lv."+str(level))
			var preview: Control = named("SelectedUnitPreview")
			check(preview.evolution_stage==int(store.army_evolution(id).stage),"Level changes reconfigure the original standing preview: "+id+" Lv."+str(level))
			check(not preview.is_processing() and int(preview.diagnostics().frame)==0,"All permanent levels retain the requested sharp standing pose: "+id)

func economy_and_navigation() -> void:
	root.content_scale_size=Vector2i(1280,800)
	root.size=Vector2i(1280,800)
	panel._select_unit("archer")
	store.data.army.levels.archer=2
	store.data.army.currency=10000
	panel._rebuild()
	await settle()
	var cost: int = store.army_upgrade_cost("archer")
	var before: Dictionary = store.data.duplicate(true)
	var notifications: int = changed_count
	await click("Train_archer")
	check(store.army_level("archer")==3 and int(store.data.army.currency)==int(before.army.currency)-cost,"Actual upgrade button pays once and reaches the requested permanent level")
	check(changed_count==notifications+1,"A successful upgrade emits one army refresh callback")
	check(bool(named("Skill_archer_volley").get_meta("unlocked")),"Upgrade immediately reveals the newly unlocked actual skill")
	check(str(named("BarracksFeedback").text)==panel.feedback and named("BarracksFeedback").get_minimum_size().y<=named("BarracksFeedback").size.y+1,"The complete actual upgrade explanation is shown without ellipsis")
	check(named("CommanderDetail").get_global_rect().encloses(named("CommanderUpgradeActions").get_global_rect()),"Upgrade feedback preserves the footer at the minimum viewport")
	check(store.data.maps==before.maps and store.data.words==before.words and store.data.learning==before.learning and store.data.settings==before.settings,"An upgrade preserves maps, learning, voice settings and selected duration")
	var reload = Store.new()
	reload.save_path=store.save_path
	reload.read_save()
	check(reload.data.army==store.data.army,"The actual upgrade is persisted and reloadable")
	await click("BarracksTraining")
	check(trained_units[-1]=="archer","The real separate training callback carries the inspected troop")
	var old_closed: int = closed_count
	await click("BarracksBack")
	check(not panel.visible and closed_count==old_closed+1,"The real return action hides barracks and emits one close callback")
	panel.open(false)
	await settle()
	before=store.data.duplicate(true)
	check(named("Train_archer").disabled,"Active-battle navigation disables permanent upgrades")
	panel._train("archer")
	check(store.data==before,"Even a stale upgrade callback cannot spend during battle navigation")
	check(not named("BarracksTraining").disabled,"The separate paused-battle drill remains available as before")
	panel.open(true)
	store.data.army.currency=0
	panel._rebuild()
	await settle()
	check(named("Train_archer").disabled,"Insufficient funds disables the actual upgrade action")
	before=store.data.duplicate(true)
	panel._train("archer")
	check(store.data==before,"Insufficient funds creates no upgrade or payment")
	var original_path: String = store.save_path
	store.data.army.currency=10000
	store.save_path="user://missing-parent-%d/save.json" % Time.get_ticks_usec()
	panel._rebuild()
	await settle()
	before=store.data.duplicate(true)
	notifications=changed_count
	await click("Train_archer")
	check(store.data==before and changed_count==notifications,"A failed save rolls back the real upgrade and emits no successful refresh")
	check(not panel.feedback.is_empty(),"The failed upgrade remains explained in the actual UI")
	check(named("CommanderDetail").get_global_rect().encloses(named("CommanderUpgradeActions").get_global_rect()),"Even save failure feedback preserves all upgrade controls")
	store.save_path=original_path
	var maps: Dictionary = store.data.maps.duplicate(true)
	store.data.maps={}
	panel._select_unit("ninja")
	await settle()
	check(named("Train_ninja").disabled and named("BarracksTraining").disabled,"Locked troop detail retains both original action restrictions")
	before=store.data.duplicate(true)
	panel._train("ninja")
	check(store.data==before,"A locked troop cannot spend or upgrade through the real handler")
	store.data.maps=maps
	for stage_id in store.stage_numbers:
		if int(store.stage_numbers[stage_id])>=35: store.data.maps.erase(stage_id)
	panel._rebuild()
	await settle()
	check(str(named("SelectedArmyPortrait").hero_id)=="hachisuka_masakatsu","Earlier stages retain the predecessor's static portrait")
	if require_named: check(not bool(named("SelectedArmyPortrait").diagnostics().fallback),"The predecessor uses his final named historical portrait")
	await capture("ninja-predecessor")
	for stage_id in store.stage_numbers:
		if int(store.stage_numbers[stage_id])==35: store.data.maps[stage_id]={"wins":1}
	panel._rebuild()
	await settle()
	check(str(named("SelectedArmyPortrait").hero_id)=="hachisuka_iemasa","The existing stage-35 succession selects the successor's static portrait")
	if require_named: check(not bool(named("SelectedArmyPortrait").diagnostics().fallback),"The successor uses his final named historical portrait")
	await capture("ninja-successor")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/barracks-2d"):
		quit(2)
		return
	packed="--packed" in OS.get_cmdline_user_args()
	require_named="--require-named" in OS.get_cmdline_user_args()
	capture_enabled="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	store=Store.new()
	store.save_path="user://qa-barracks-%d.json" % Time.get_ticks_usec()
	panel=Barracks.new()
	panel.progress=store
	panel.font=GameFonts.body()
	panel.army_changed.connect(func(): changed_count+=1)
	panel.closed.connect(func(): closed_count+=1)
	panel.training_requested.connect(func(unit_id): trained_units.append(unit_id))
	root.add_child(panel)
	await settle()
	if "--probe" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i(1280,800)
		root.size=Vector2i(1280,800)
		panel.open()
		await settle()
		for name_value in ["CommanderNamePlaque","CommanderName","SelectedArmyPortrait"]:
			print("BARRACKS_LAYOUT ",name_value," ",named(name_value).get_global_rect()," min=",named(name_value).get_minimum_size())
		for item in nodes(named("CommanderDetail")):
			if item is Control:
				print("BARRACKS_LAYOUT ",item.name," ",item.get_global_rect()," min=",item.get_minimum_size())
		quit(0)
		return
	await ui_matrix()
	await preview_visibility()
	await economy_and_navigation()
	var path: String = "user://qa_barracks_2d_packed.json" if packed else "res://tests/qa_barracks_2d.json"
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"images":images,"observations":observations},"\t"))
	file.close()
	print("BARRACKS_2D checks=%d failures=%d images=%d" % [checks,failures.size(),images.size()])
	panel.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
