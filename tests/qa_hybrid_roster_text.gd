extends SceneTree
## Verifies roster copy in the real barracks layout without loading a battle.
const Store = preload("res://native/progress.gd")
const Barracks = preload("res://native/barracks.gd")
const Portrait = preload("res://native/barracks_portrait.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const CAMPAIGN_FIXTURE = "res://tests/profiles/campaign-balance/Godot/app_userdata/말의 전장/campaign-balance-progress.json"
var checks: int = 0
var failures: Array = []
var observations: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("HYBRID ROSTER TEXT: "+message)

func settle() -> void:
	await process_frame
	await process_frame

func find_label(node: Node, text: String) -> Label:
	if node is Label and node.text==text: return node
	for child in node.get_children():
		var found: Label = find_label(child,text)
		if found!=null: return found
	return null

func compare_saved_state(before: Dictionary, after: Dictionary) -> void:
	check(before.maps.keys()==after.maps.keys(),"Cleared map identities survive save/reload")
	for id in before.maps:
		check(int(before.maps[id].get("wins",0))==int(after.maps[id].get("wins",0)),"Map wins preserved: "+str(id))
	check(int(before.army.currency)==int(after.army.currency),"Earned army funding survives save/reload")
	check(str(before.army.selected)==str(after.army.selected),"Selected class survives save/reload")
	for id in TYPES:
		check(int(before.army.levels[id])==int(after.army.levels[id]),"Permanent training survives save/reload: "+id)
	check(before.settings==after.settings,"Music and voice preferences survive save/reload")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/hybrid-roster-text/"):
		push_error("Refusing a profile outside the isolated roster text directory")
		quit(2)
		return
	var store = Store.new()
	check(store.unit_catalog.size()==8,"Eight base classes are retained")
	check(store.unlocked_units()==["archer","spear"],"The fresh roster still starts with two classes")
	var fixture_available: bool = FileAccess.file_exists(CAMPAIGN_FIXTURE)
	check(fixture_available,"Existing actual forty-stage campaign fixture is available")
	if fixture_available:
		store.save_path = CAMPAIGN_FIXTURE
		store.read_save()
		check(store.read_error.is_empty(),"Actual campaign fixture loads without migration damage")
		check(store.data.maps.size()==40,"All forty actual campaign clears remain")
		check(store.unlocked_units()==TYPES,"All eight actual unlocked classes remain in order")
	var before: Dictionary = store.data.duplicate(true)
	store.save_path = "user://roster-text-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	check(store.write_save(),"Actual campaign state saves into the isolated test profile")
	var loaded = Store.new()
	loaded.save_path = store.save_path
	loaded.read_save()
	check(loaded.read_error.is_empty(),"The isolated saved state reloads without error")
	compare_saved_state(before,loaded.data)
	for id in TYPES:
		for level in [1,4,8]:
			var stage: int = 2 if level==8 else 1 if level==4 else 0
			var evolution: Dictionary = loaded.army_evolution(id,level)
			var stats: Dictionary = loaded.army_stats(id,level)
			var definition: Dictionary = loaded.unit_definition(id)
			check(int(evolution.stage)==stage and int(stats.evolution)==stage,id+": Lv1/Lv4/Lv8 evolution mapping retained")
			check(is_equal_approx(float(stats.damage),float(definition.damage)*(1+.08*(level-1))*float(evolution.damageMultiplier)),id+": permanent damage formula retained")
			check(is_equal_approx(float(stats.range),float(definition.range)*(1+.012*(level-1))*float(evolution.rangeMultiplier)),id+": permanent range formula retained")
			check(is_equal_approx(float(stats.interval),float(definition.interval)/(1+.015*(level-1))*float(evolution.intervalMultiplier)),id+": permanent attack interval formula retained")
	var barracks = Barracks.new()
	barracks.progress = loaded
	barracks.font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	check(barracks.font!=null,"The real Japanese/Korean barracks font loads")
	root.add_child(barracks)
	for screen in [Vector2i(1280,800),Vector2i(1440,900)]:
		root.content_scale_size = screen
		root.size = screen
		await settle()
		check(root.get_visible_rect().size==Vector2(screen),"The barracks is measured at the actual requested logical resolution")
		for id in TYPES:
			for level in [1,4,8]:
				loaded.data.army.levels[id] = level
				barracks.selected_unit_id = id
				barracks.open()
				await settle()
				var definition: Dictionary = loaded.unit_definition(id)
				var role: Label = find_label(barracks,str(definition.role))
				var description: Label = find_label(barracks,str(definition.description))
				var prefix: String = "%s Lv%d at %dx%d: " % [id,level,screen.x,screen.y]
				check(role!=null and description!=null,prefix+"actual role and description labels exist")
				if role==null or description==null: continue
				check(role.get_line_count()==1 and role.position.y+role.get_minimum_size().y<=171,prefix+"role fits before the description starts")
				check(description.get_line_count()<=2 and description.get_line_count()*description.get_line_height()+maxi(0,description.get_line_count()-1)*description.get_theme_constant("line_spacing")<=73,prefix+"description glyphs fit the existing 73px height")
				check(description.position.y+description.size.y<253,prefix+"description remains above the stats divider")
				var portrait: Node = barracks.find_child("SelectedArmyPortrait",true,false)
				check(portrait!=null and portrait.get_script()==Portrait,prefix+"approved authored live portrait helper is retained")
				if portrait!=null:
					var state: Dictionary = portrait.diagnostics()
					var source: Dictionary = Portrait.source_for(id,int(loaded.army_evolution(id).stage))
					check(bool(state.ready) and str(state.unitId)==id and str(state.sourcePath)==str(source.path),prefix+"the correct original class artwork remains bound")
				observations.append({"unitId":id,"level":level,"screen":str(screen),"roleLines":role.get_line_count(),"roleMinHeight":role.get_minimum_size().y,"rolePosition":str(role.position),"descriptionLines":description.get_line_count(),"descriptionMinHeight":description.get_minimum_size().y,"descriptionWidth":description.size.x,"descriptionPosition":str(description.position),"descriptionSize":str(description.size),"descriptionLineHeight":description.get_line_height(),"descriptionFontSize":description.get_theme_font_size("font_size")})
	barracks.free()
	var report: FileAccess = FileAccess.open("res://tests/qa_hybrid_roster_text.json",FileAccess.WRITE)
	check(report!=null,"The QA report can be written")
	var result: Dictionary = {"checks":checks,"failures":failures,"actualCampaignFixture":fixture_available,"observations":observations}
	if report!=null:
		report.store_string(JSON.stringify(result,"  "))
		report.flush()
		report.close()
	print("HYBRID_ROSTER_TEXT_QA ",JSON.stringify({"checks":checks,"failures":failures,"layouts":observations.size()}))
	quit(0 if failures.is_empty() else 1)
