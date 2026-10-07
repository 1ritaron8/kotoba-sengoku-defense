extends SceneTree

const Store = preload("res://native/progress.gd")
var checks: int = 0
var failures: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var store = Store.new()
	store.save_path = "user://campaign-qa.json"
	check(store.unit_catalog.size()==8,"Eight base classes keep roster size bounded")
	check(store.unlocked_units()==["archer","spear"],"New army begins with two complementary classes")
	check(store.data.army.currency==180,"New player can afford a first training upgrade")
	check(not store.upgrade_army_unit("ninja").ok,"Locked class cannot spend training funds")
	check(not store.select_army_unit("ninja"),"Locked class cannot be selected for deployment")
	store.data.army.currency = 100000
	var previous: float = store.army_stats("archer").damage
	for level in range(2,11):
		var before: int = int(store.data.army.currency)
		var cost: int = store.army_upgrade_cost("archer")
		var result: Dictionary = store.upgrade_army_unit("archer")
		check(bool(result.ok) and store.army_level("archer")==level,"Training reaches the requested persistent level")
		check(int(store.data.army.currency)==before-cost,"Training charges its displayed cost exactly once")
		check(store.army_stats("archer").damage>previous,"Training improves actual deployed damage")
		previous = store.army_stats("archer").damage
		check(bool(result.evolved)==(level in [4,8]),"Evolution happens only at level four and eight")
	check(store.army_evolution("archer").stage==2,"Final army form remains the same roster class")
	var capped_funds: int = int(store.data.army.currency)
	check(not store.upgrade_army_unit("archer").ok and int(store.data.army.currency)==capped_funds,"Maximum level rejects an extra debit")
	check(store.select_army_unit("spear"),"Player chooses a specific unlocked class")
	var reopened = Store.new()
	reopened.save_path = store.save_path
	reopened.read_save()
	check(reopened.army_level("archer")==10 and reopened.army_evolution("archer").stage==2,"Level and evolution survive app restart")
	check(reopened.data.army.currency==store.data.army.currency and reopened.data.army.selected=="spear","Wallet and chosen class survive app restart")
	var no_money = Store.new()
	no_money.data.army.currency = 0
	check(not no_money.upgrade_army_unit("archer").ok and no_money.army_level("archer")==1,"Insufficient funds leave level and wallet unchanged")
	var denied = Store.new()
	denied.save_path = "user://directory-that-does-not-exist/progress.json"
	var denied_before: String = JSON.stringify(denied.data.army)
	check(not denied.upgrade_army_unit("archer").ok,"A real unwritable save path rejects the transaction")
	check(JSON.stringify(denied.data.army)==denied_before,"Failed persistence rolls back both training level and currency")
	var campaign = Store.new()
	campaign.save_path = "user://clear-rewards-qa.json"
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var unlocks: Array = []
	for stage in maps:
		var reward: Dictionary = campaign.complete_map(str(stage.id),{"correct":2})
		check(bool(reward.firstClear),"Every distinct stage earns its first-clear reward")
		unlocks.append_array(reward.unlocked)
	check(campaign.unlocked_units().size()==8 and unlocks.size()==6,"Campaign unlocks exactly six additional classes, then evolves them")
	var repeat: Dictionary = campaign.complete_map(str(maps[0].id),{"correct":0})
	check(not bool(repeat.firstClear) and int(repeat.currency)==42 and repeat.unlocked.is_empty(),"Replaying earns the smaller reward and never repeats an unlock")
	check(campaign.data.maps.size()==40,"Replaying never inflates distinct cleared stage count")
	var old_path: String = "user://legacy-army-qa.json"
	var file = FileAccess.open(old_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"maps":{"basic-forest":{"wins":2}},"words":{},"settings":{"music":false,"voice":true}}))
	file.close()
	var migrated = Store.new()
	migrated.save_path = old_path
	migrated.read_save()
	check(migrated.data.version==2 and migrated.data.maps.has("basic-forest") and not migrated.data.settings.music,"Legacy save migrates without losing clear or settings")
	check(migrated.data.army.currency==328 and "samurai" in migrated.unlocked_units(),"Existing first clear earns retrospective funds and its unit")
	migrated.write_save()
	var twice = Store.new()
	twice.save_path = old_path
	twice.read_save()
	check(twice.data.army.currency==328,"Migration cannot award retrospective funds twice")
	file = FileAccess.open(old_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":2,"maps":{},"words":{},"settings":{},"army":{"currency":"bad","levels":{"archer":999,"ninja":-3,"unknown":7}}}))
	file.close()
	var malformed = Store.new()
	malformed.save_path = old_path
	malformed.read_save()
	check(malformed.data.army.selected=="archer" and malformed.data.army.currency==180,"Missing selection and malformed currency normalize safely")
	check(malformed.army_level("archer")==10 and malformed.army_level("ninja")==1 and not malformed.data.army.levels.has("unknown"),"Malformed levels are bounded to the eight known classes")
	var report: Dictionary = {"checks":checks,"failures":failures,"classes":store.unit_catalog.size(),"evolutionThresholds":[4,8],"saveFailureRollback":true,"legacyMigration":true}
	file = FileAccess.open("res://tests/qa_campaign.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CAMPAIGN_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
