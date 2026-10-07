extends SceneTree
const Store = preload("res://native/progress.gd")

func _initialize() -> void:
	var expected: String = "c:/users/playdata/appdata/roaming/godot/app_userdata/말의 전장"
	var actual: String = ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/").to_lower()
	if actual!=expected:
		push_error("Fresh-player QA refuses an unexpected profile")
		quit(2)
		return
	var store = Store.new()
	store.read_save()
	var unlocked: int = 0
	for stage_id in store.stage_numbers:
		if store.map_unlocked(stage_id): unlocked+=1
	var upgrades: int = 0
	for unit_id in store.data.army.levels:
		if int(store.data.army.levels[unit_id])>1: upgrades+=1
	var clean: bool = store.data.maps.is_empty() and store.data.words.is_empty() and store.data.learning.items.is_empty() and store.data.learning.attempts.is_empty() and store.data.learning.get("assessments",{}).is_empty() and upgrades==0 and int(store.data.army.currency)==180 and unlocked==1 and store.read_error.is_empty()
	print("ACTUAL_PLAYER_RESET clean=%s clears=%d words=%d upgradedUnits=%d currency=%d unlockedStages=%d; read-only check" % [str(clean),store.data.maps.size(),store.data.words.size(),upgrades,int(store.data.army.currency),unlocked])
	quit(0 if clean else 1)
