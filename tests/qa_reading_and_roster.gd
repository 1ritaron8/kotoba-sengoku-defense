extends SceneTree
const Ruby = preload("res://native/ruby_label.gd")
const Progress = preload("res://native/progress.gd")
var checks: int = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<20: push_error("READING_ROSTER: "+note)

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/reading-roster"):
		quit(2)
		return
	var face: Font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	var ruby = Ruby.new()
	ruby.font=face
	ruby.min_reading_size=22
	ruby.group_spacing=8
	ruby.merge_adjacent_readings=true
	ruby.show_reading_guides=true
	ruby.wrap_japanese=true
	root.add_child(ruby)
	for item in [
		{"jp":"地面は","ko":"땅바닥은","parts":[{"text":"地","reading":"じ"},{"text":"面","reading":"めん"},{"text":"は"}]},
		{"jp":"今日は","ko":"오늘은","parts":[{"text":"今日","reading":"きょう"},{"text":"は"}]},
		{"jp":"一昨日の雨","ko":"그저께의 비","parts":[{"text":"一昨日","reading":"おととい"},{"text":"の"},{"text":"雨","reading":"あめ"}]}
	]:
		ruby.size.x=300
		ruby.set_word(item,36,true)
		var layout: Dictionary = ruby.get_text_layout()
		check(int(layout.ruby_size)>=22,"Field reading uses at least 22px")
		var readings: Array = []
		for run in layout.runs:
			if run.role=="reading": readings.append(run)
			check(Rect2(0,0,300,layout.height).grow(1).encloses(run.bounds),"Grouped kana/body/Korean fit their measured bounds")
		check(readings.size()==(2 if str(item.jp)=="一昨日の雨" else 1),"A compound has one complete reading without invented kanji splits")
		check(layout.guides.size()==readings.size(),"A guide associates each reading with its full word group")
		if str(item.jp)=="地面は":
			check(str(readings[0].text)=="じめん","Adjacent correct parts produce the full ground reading")
			var last: Dictionary=layout.runs[-2]
			check(str(last.text)=="は" and int(last.group)!=int(readings[0].group),"The particle remains a distinct unannotated group")
	for example in [
		{"text":"固","reading":"かた","suffix":"いです。"},
		{"text":"食","reading":"た","suffix":"べます。"},
		{"text":"落","reading":"お","suffix":"とします。"}
	]:
		var annotated: Dictionary={"text":example.text,"reading":example.reading}
		check(is_zero_approx(ruby._group_gap(annotated,{"text":example.suffix})),"Okurigana remains attached even when it begins with a kana that is also a particle")
		check(is_equal_approx(ruby._group_gap(annotated,{"text":"は"}),8),"A standalone particle keeps a visible gap without inheriting a word reading")
	var store = Progress.new()
	check(store.hero_catalog.size()==9,"Eight confirmed commanders and one successor exist")
	check(str(store.army_commander("commander",40).id)=="kuroda_kanbei","Cavalry uses Kanbei rather than his later-born son")
	check(str(store.army_commander("ninja",34).id)=="hachisuka_masakatsu" and str(store.army_commander("ninja",35).id)=="hachisuka_iemasa","The late campaign replaces Masakatsu with his living successor")
	var hero_ids: Dictionary = {}
	for definition in store.unit_catalog:
		var id: String=str(definition.id)
		var hero: Dictionary=store.army_commander(id,1)
		check(not hero.is_empty() and not bool(hero.joined) and str(hero.displayRoleKo).contains("모티브"),"Early portraits are labelled a motif before the person's story join: "+id)
		check(str(hero.adaptationKo).contains("게임 각색"),"The troop assignment does not claim a historical specialization: "+id)
		hero_ids[str(hero.id)]=true
		check(bool(store.army_commander(id,int(hero.joinStage)).joined),"The commander label becomes active at its story join: "+id)
		var expected_levels: Array=[3,5,8] if id!="ninja" else []
		var actual_levels: Array=[]
		for skill in definition.get("skillUnlocks",[]): actual_levels.append(int(skill.level))
		check(actual_levels==expected_levels,"The planned mechanics unlock exactly at permanent 3,5,8: "+id)
		for level in range(1,11):
			for skill in store.army_skills(id,level):
				check(bool(skill.unlocked)==(level>=int(skill.level)),"Skill preview has the correct threshold: "+str(skill.id))
		var paid = Progress.new()
		paid.save_path="user://upgrade-"+id+".json"
		for map_id in paid.stage_numbers: paid.data.maps[str(map_id)]={"wins":1}
		paid.data.army.currency=100000
		for level in range(2,9):
			var before: int=int(paid.data.army.currency)
			var cost: int=paid.army_upgrade_cost(id)
			var result: Dictionary=paid.upgrade_army_unit(id)
			check(bool(result.ok) and paid.army_level(id)==level and int(paid.data.army.currency)==before-cost,"A real upgrade consumes the exact cost once: "+id)
			var expected: int=1 if id!="ninja" and level in [3,5,8] else 0
			check(result.skillsUnlocked.size()==expected,"The successful transaction reports only newly opened mechanics: "+id)
			var restored = Progress.new()
			restored.save_path=paid.save_path
			restored.read_save()
			check(restored.army_level(id)==level and restored.army_skills(id)==paid.army_skills(id),"Permanent mechanics survive an actual JSON save/reload: "+id)
		paid._save_read_blocked=true
		var before: Dictionary=paid.data.duplicate(true)
		check(not paid.upgrade_army_unit(id).ok and paid.data==before,"A failed save rolls back currency and permanent skill level: "+id)
	check(hero_ids.size()==8,"Every troop has a distinct approved commander")
	var curriculum: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	for tier in ["basic","beginner","intermediate","advanced"]:
		for lesson in curriculum[tier]:
			for word in lesson.newWords:
				for width in [230.0,764.0,1200.0]:
					ruby.size.x=width
					ruby.set_word(word if width==230 else word.example,36 if width==230 else 24,true)
					var layout: Dictionary=ruby.get_text_layout()
					check(int(layout.ruby_size)>=22,"All 900 words retain readable kana at every field width")
					for run in layout.runs:
						check(Rect2(0,0,width,layout.height).grow(1).encloses(run.bounds),"All authored subtitle glyphs fit after reading enlargement")
	var output = FileAccess.open("user://qa_reading_and_roster.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	output.close()
	print("READING_ROSTER checks=%d failures=%d" % [checks,failures.size()])
	ruby.queue_free()
	quit(0 if failures.is_empty() else 1)
