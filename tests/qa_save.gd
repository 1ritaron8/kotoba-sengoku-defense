extends SceneTree

const Store = preload("res://native/progress.gd")
var failures: Array = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var first = Store.new()
	check(first.data.settings.battleMinutes==5,"New player starts in five-minute mode")
	check(first.write_save(),"Initial save must succeed")
	first.record_word("basic-test",true,false)
	first.record_word("basic-test",true,false)
	check(first.mastered_count()==0,"Two same-session answers do not prove lasting word and sentence recall")
	first.complete_map("basic-forest",{"correct":2})
	first.data.settings.music = false
	first.data.settings.battleMinutes = 20
	check(first.write_save(),"Replacing an existing save must succeed")
	var reopened = Store.new()
	reopened.read_save()
	check(reopened.data.maps.has("basic-forest"),"Map clear persists")
	check(reopened.mastered_count()==0 and reopened.data.words["basic-test"].correct==2,"History persists without converting legacy streaks into mastery")
	check(reopened.data.settings.music==false,"Music preference persists")
	check(reopened.data.settings.battleMinutes==20,"Twenty-minute preference persists")
	for minutes in [5,10,20]:
		reopened.data.settings.battleMinutes = minutes
		check(reopened.write_save(),"Duration preference writes successfully")
		var duration_reopened = Store.new()
		duration_reopened.read_save()
		check(duration_reopened.data.settings.battleMinutes==minutes,"Each duration choice survives an actual save reload")
		check(duration_reopened.data.words==reopened.data.words and duration_reopened.data.maps==reopened.data.maps,"Duration preference preserves learning and map progress")
	reopened.record_word("basic-test",false,false)
	check(reopened.mastered_count()==0,"A wrong answer resets the recall streak")
	reopened.record_word("basic-test",true,true)
	check(reopened.mastered_count()==0,"Hinted answer does not count as independent recall")
	check(reopened.data.words["basic-test"].wrong==1,"Hinted correct answer is not recorded as wrong")
	var file = FileAccess.open(Store.SAVE_PATH,FileAccess.WRITE)
	file.store_string("{broken-json")
	file.close()
	var broken = Store.new()
	broken.read_save()
	check(broken.data.words==reopened.data.words and broken.data.maps==reopened.data.maps and not broken.read_error.is_empty(),"Corrupt primary JSON recovers the latest verified backup without discarding progress")
	file = FileAccess.open(Store.SAVE_PATH,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"words":{"bad":"invalid","ok":{"seen":"not-a-number"}},"maps":{"bad":false},"settings":{"music":"invalid"}}))
	file.close()
	var malformed = Store.new()
	malformed.read_save()
	check(not malformed.data.words.has("bad"),"Malformed word records are ignored")
	check(malformed.data.words.ok.seen==0,"Malformed counters reset safely")
	check(malformed.data.maps.is_empty(),"Malformed map records are ignored")
	check(malformed.data.settings.music==true,"Malformed settings use defaults")
	check(malformed.data.settings.battleMinutes==5,"Legacy save without duration chooses five-minute mode")
	for invalid in [-1,0,4,5.5,999,"10",true,null,{}]:
		var fixture: Dictionary = reopened.data.duplicate(true)
		fixture.settings.battleMinutes = invalid
		file = FileAccess.open(Store.SAVE_PATH,FileAccess.WRITE)
		file.store_string(JSON.stringify(fixture))
		file.close()
		var invalid_reopened = Store.new()
		invalid_reopened.read_save()
		check(invalid_reopened.data.settings.battleMinutes==5,"Invalid duration safely falls back to five minutes: "+str(invalid))
		check(invalid_reopened.data.words==reopened.data.words and invalid_reopened.data.maps==reopened.data.maps,"Invalid duration preserves unrelated saved progress")
	var clean = Store.new()
	clean.write_save()
	print("SAVE QA: ","PASS" if failures.is_empty() else "FAIL", " checks=",checks," (persistence, duration choices, overwrite, recall, corrupt input)")
	quit(0 if failures.is_empty() else 1)
