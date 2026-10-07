extends SceneTree
const Store = preload("res://native/progress.gd")
var failures: Array = []
var checks: int = 0

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		push_error("TRAINING_SAVE: "+note)

func _initialize() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/training-save/").to_lower()):
		push_error("Training save QA refuses the player's profile")
		quit(2)
		return
	var store = Store.new()
	store.save_path = "user://training-%d.json" % Time.get_ticks_msec()
	check(not store.is_unit_trained("archer"),"A new account has no completed drill")
	var before: Dictionary = store.data.duplicate(true)
	for invalid in ["unknown","","ninja"]:
		check(not bool(store.record_unit_training(invalid).ok) and store.data==before,"Unknown and locked classes cannot save completed drills: "+invalid)
	check(bool(store.record_unit_training("archer").ok) and store.is_unit_trained("archer"),"An unlocked completed drill persists")
	check(store.data.maps==before.maps and store.data.words==before.words and store.data.learning==before.learning and store.data.army.currency==before.army.currency and store.data.army.levels==before.army.levels,"Saving a drill badge preserves campaign, learning, money and upgrades")
	var restored = Store.new()
	restored.save_path = store.save_path
	restored.read_save()
	check(restored.is_unit_trained("archer"),"The actual JSON reload restores the drill badge")
	var already: Dictionary = restored.data.duplicate(true)
	var duplicate: Dictionary = restored.record_unit_training("archer")
	check(bool(duplicate.ok) and not bool(duplicate.recorded) and restored.data==already,"Repeating a completed drill cannot grant rewards or alter the receipt")
	restored._save_read_blocked = true
	check(not bool(restored.record_unit_training("spear").ok) and not restored.is_unit_trained("spear") and restored.data==already,"A failed write rolls back the completion badge")
	restored._save_read_blocked = false
	restored.data.army.training={"archer":true,"spear":"true","samurai":1,"ninja":true,"unknown":true}
	check(restored.write_save(),"Malformed receipt fixture writes only inside the isolated profile")
	var sanitized = Store.new()
	sanitized.save_path=restored.save_path
	sanitized.read_save()
	check(sanitized.data.army.training=={"archer":true},"Only known unlocked boolean completions survive sanitization")
	print("TRAINING_SAVE checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
