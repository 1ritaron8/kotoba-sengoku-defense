extends SceneTree
## Static training UI, real menu callbacks and safe ready-state battlefield sizing.
## Deliberately does not repeat the existing 14,265 actual-drill checks.
const Training = preload("res://native/unit_training.gd")
const Store = preload("res://native/progress.gd")
const Style = preload("res://native/sengoku_ui.gd")
var checks: int = 0
var failures: Array[String] = []
var samples: Array = []
var controller: Control
var store: RefCounted
var maps: Array = []
var close_count: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size()<25: push_error("TRAINING_MATERIALS "+note)

func settle() -> void:
	for frame in range(6): await process_frame

func geometry(scope: String) -> void:
	var window: Rect2 = controller.get_global_rect()
	for control in controller.find_children("*","Control",true,false):
		if not control.is_visible_in_tree() or control.is_queued_for_deletion(): continue
		var bounds: Rect2 = control.get_global_rect()
		var visible_bounds: Rect2 = bounds
		var owner: Node = control.get_parent()
		while owner!=null and owner!=controller:
			if owner is Control and owner.clip_contents:
				visible_bounds=visible_bounds.intersection(owner.get_global_rect())
			owner=owner.get_parent()
		if not visible_bounds.has_area(): continue
		check(window.grow(2).encloses(visible_bounds),scope+": visible control is inside the screen "+str(control.name))
		if control is Label:
			var points: int = control.get_theme_font_size("font_size")
			check(points>=20,scope+": label size stays readable")
			check(control.get_minimum_size().y<=control.size.y+1,scope+": label height fits "+control.text.left(32))
			if control.autowrap_mode==TextServer.AUTOWRAP_OFF:
				var glyphs: Vector2=control.get_theme_font("font").get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,points)
				check(glyphs.x<=control.size.x+1,scope+": unwrapped instruction fits "+control.text.left(32))
		if control is Button:
			var surface: StyleBox=control.get_theme_stylebox("normal")
			check(surface is StyleBoxTexture and surface.texture!=null,scope+": button wood texture is loaded")
			check(control.size.y>=48,scope+": button retains its minimum touch height")
			var points: int=control.get_theme_font_size("font_size")
			var glyphs: Vector2=control.get_theme_font("font").get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,points)
			check(control.size.x+1>=glyphs.x+surface.get_minimum_size().x,scope+": button text plus padding fits")
		if control.has_method("get_text_layout"):
			var layout: Dictionary=control.get_text_layout()
			check(float(layout.ruby_size)>=16,scope+": furigana keeps its readable size")
			for run in layout.runs:
				check(Rect2(Vector2.ZERO,control.size).grow(2).encloses(run.bounds),scope+": Japanese/reading/translation fit")
	var backdrop: TextureRect=null
	for candidate in controller.get_children():
		if candidate is TextureRect and candidate.is_visible_in_tree() and not candidate.is_queued_for_deletion(): backdrop=candidate
	check(backdrop!=null and backdrop.texture!=null,scope+": actual painted warroom backdrop is loaded")
	check(backdrop!=null and backdrop.mouse_filter==Control.MOUSE_FILTER_IGNORE,scope+": backdrop does not intercept field clicks")
	var footer: HBoxContainer=controller.footer_box
	check(footer.size.y>=48 and footer.size.y<=60,scope+": footer stays between 48 and 60px")
	check(window.grow(1).encloses(footer.get_global_rect()),scope+": footer stays inside the screen")
	var previous_end: float=footer.get_global_rect().position.x
	for child in footer.get_children():
		if not child is Control or not child.visible: continue
		var bounds: Rect2=child.get_global_rect()
		check(footer.get_global_rect().grow(1).encloses(bounds),scope+": footer controls stay in their row")
		check(bounds.position.x>=previous_end-.1,scope+": footer controls do not overlap")
		previous_end=bounds.end.x
	if controller.view=="training":
		var field: Control=controller.field_clip
		check(field.size.x>=240 and field.size.y>=300,scope+": practice battlefield keeps its useful minimum area")
		check(field.clip_contents and field.mouse_filter==Control.MOUSE_FILTER_STOP,scope+": practice field input and clipping remain intact")
		check(field.find_children("TrainingWarroom","TextureRect",true,false).is_empty(),scope+": painted shell does not cover the practice battlefield")
		var panels: Array=[]
		for candidate in controller.find_children("*","PanelContainer",true,false):
			if str(candidate.name).contains("TrainingInstructionPanel") and candidate.is_visible_in_tree(): panels.append(candidate)
		check(panels.size()==1 and panels[0].get_theme_stylebox("panel") is StyleBoxTexture,scope+": instruction panel uses the same lacquer material")
		check(controller.phase=="ready" and controller.elapsed_seconds==0.0,scope+": layout inspection does not advance the drill")
		check(controller.observations.deployments==0 and controller.observations.hits==0 and controller.observations.heals==0,scope+": UI fixture performs no drill attacks/heals/deployments")
	samples.append({"scope":scope,"viewport":root.size,"view":controller.view,"unitId":controller.unit_id,"footerHeight":footer.size.y,"fieldSize":controller.field_clip.size if controller.view=="training" else Vector2.ZERO})

func menu_cards(scope: String, all_unlocked: bool) -> void:
	var buttons: Array=[]
	for button in controller.find_children("*","Button",true,false):
		if button.has_meta("trainingUnit") and button.is_visible_in_tree(): buttons.append(button)
	check(buttons.size()==8,scope+": all eight class education cards are present")
	for button in buttons:
		var id: String=str(button.get_meta("trainingUnit"))
		check(button.disabled!=(all_unlocked or id in ["archer","spear"]),scope+": existing class unlock gating is preserved "+id)
		var card: PanelContainer=button.get_parent().get_parent()
		check(card.get_theme_stylebox("panel") is StyleBoxTexture,scope+": class card material is real texture "+id)
		check(card.size.x>=245,scope+": class card preserves readable width "+id)

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/training-menu-materials/").to_lower()) or DisplayServer.get_name()!="headless":
		push_error("Refusing a player profile or GPU training-material test")
		quit(2)
		return
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var original_maps: String=FileAccess.get_file_as_string("res://native/maps.json")
	store=Store.new()
	store.save_path="user://training-materials-never-write.json"
	check(not FileAccess.file_exists(store.save_path),"isolated fixture starts without a save file")
	controller=Training.new()
	controller.render_enabled=false
	root.add_child(controller)
	controller.configure(store,maps,load("res://assets/fonts/NotoSansCJKjp-Regular.otf"))
	controller.closed.connect(func(): close_count+=1)
	var starter_data: String=JSON.stringify(store.data)
	for screen in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=screen
		root.content_scale_size=screen
		controller.open_menu("archer")
		await settle()
		geometry("starter menu "+str(screen))
		menu_cards("starter menu "+str(screen),false)
	check(JSON.stringify(store.data)==starter_data,"menu reading preserves the actual starter account")
	# Only unlock availability is varied; no currency, training or lesson rewards are granted.
	for stage in maps: store.data.maps[str(stage.id)]={"cleared":true}
	var unlocked_data: String=JSON.stringify(store.data)
	for screen in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=screen
		root.content_scale_size=screen
		controller.open_menu("samurai")
		await settle()
		geometry("unlocked menu "+str(screen))
		menu_cards("unlocked menu "+str(screen),true)
		for id in Training.UNIT_ORDER:
			var button: Button=null
			for candidate in controller.find_children("*","Button",true,false):
				if str(candidate.get_meta("trainingUnit",""))==id and candidate.is_visible_in_tree(): button=candidate
			check(button!=null and not button.disabled,"real menu entrance is available "+id)
			if button==null: continue
			button.pressed.emit()
			controller.set_process(false)
			await settle()
			check(controller.unit_id==id and controller.view=="training" and controller.battle!=null,"real button callback enters the correct independent lesson "+id)
			geometry("ready "+str(screen)+" "+id)
			controller.menu_button.pressed.emit()
			await settle()
			check(controller.view=="menu" and controller.battle==null,"real return callback closes the independent battlefield "+id)
	check(JSON.stringify(store.data)==unlocked_data,"all ready-state UI callbacks preserve currency/progression/training values")
	check(not FileAccess.file_exists(store.save_path),"UI callbacks never write a campaign save")
	check(FileAccess.get_file_as_string("res://native/maps.json")==original_maps,"menu checks do not mutate authored map data")
	controller.close()
	check(close_count==1 and controller.view=="closed" and not controller.visible,"close callback fires once and returns to caller")
	controller.queue_free()
	await settle()
	var report: Dictionary={"checks":checks,"failed":failures.size(),"failures":failures,"samples":samples,"scope":"CPU/headless, two viewports, eight menu cards, real entrance/return/close callbacks, texture resources, Japanese and Korean font bounds, input/field/footer geometry; no battle simulation or GPU visual judgment"}
	var output: FileAccess=FileAccess.open("user://qa_training_menu_materials.json",FileAccess.WRITE)
	check(output!=null,"isolated test report can be opened")
	if output!=null:
		report.checks=checks
		report.failed=failures.size()
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	print(JSON.stringify({"checks":checks,"failed":failures.size(),"samples":samples.size(),"report":ProjectSettings.globalize_path("user://qa_training_menu_materials.json")}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
