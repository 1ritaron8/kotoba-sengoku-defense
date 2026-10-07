extends SceneTree
## Actual CPU Game contracts with fixture unlocks/funds, not a campaign win test.
## Only the test profile below may be written. No renderer, import or user save.
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
const Growth = preload("res://native/unit_growth.gd")
const Skills = preload("res://native/unit_skills.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const LEVELS: Array = [1,3,4,5,8,10]
const BASE_HP: Dictionary = {"archer":105.0,"spear":140.0,"samurai":175.0,"gunner":105.0,"naginata":135.0,"monk":125.0,"commander":210.0,"ninja":100.0}
const BASE_ARMOR: Dictionary = {"archer":.10,"spear":.18,"samurai":.24,"gunner":.10,"naginata":.10,"monk":.10,"commander":.18,"ninja":.10}
var checks: int = 0
var failures: Array[String] = []
var catalog: Array = []
var events: Array = []
var observations: Dictionary = {}
var original_bytes: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures.append(message)
	if failures.size() <= 35: push_error("UNIT_GROWTH: " + message)

func near(first: float, second: float, tolerance: float = .0001) -> bool:
	return is_finite(first) and is_finite(second) and absf(first-second) <= tolerance*maxf(1.0,absf(second))

func profile_allowed() -> bool:
	var prefix: String = qa_project_path("tests/profiles/unit-growth-scaling/").to_lower()
	var app_data: String = OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")+"/"
	var local_data: String = OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")+"/"
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	return app_data.begins_with(prefix) and local_data.begins_with(prefix) and user_path.begins_with(prefix)

func fixture() -> Dictionary:
	return {"id":"growth-scaling-fixture","theme":"farm","stageNumber":20,"initialGold":4000,"unitLimit":14,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]},{"id":"other","objectiveId":"main","points":[{"x":.05,"y":.35},{"x":.95,"y":.35}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.68,"r":.16,"elevation":1}],"tactics":{"groundPosts":[{"id":"road","nameKo":"성장 시험","pathIndex":0,"segmentIndex":0,"t":.55,"r":.19,"guardRadius":.2,"mobilityFactor":1.0},{"id":"north","nameKo":"북쪽 시험","pathIndex":1,"segmentIndex":0,"t":.55,"r":.15,"guardRadius":.2,"mobilityFactor":1.0}]}}

func make_game(levels: Dictionary = {}) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,TYPES,levels)
	game.load_map(fixture(),20)
	game.set_seed(83)
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	game.start_battle()
	game.spawn_queue=["raider"]
	game.spawn_source_waves=[1]
	game.spawn_clock=100000.0
	return game

func recruit(game: Node2D, type_name: String) -> Dictionary:
	var before: int = game.next_id
	if not game.begin_placement(type_name,0):
		check(false,type_name+" begins actual paid recruitment")
		return {}
	var placed: bool = game.pending.is_empty() # Ground deployment may commit directly to the selected post.
	for point in game.placement_hints:
		if bool(game.placement_preview(point).get("valid",false)):
			placed=game.place_unit(point.x,point.y)
			if placed: break
	if not placed:
		for x in [.4,.46,.52,.58,.64,.7]:
			for y in [.5,.68,.35,.6,.75]:
				if placed: break
				if bool(game.placement_preview(Vector2(x,y)).get("valid",false)): placed=game.place_unit(x,y)
	check(placed,type_name+" has a legal placement")
	var ticks: int = 0
	while not game.recruitment_queue.is_empty() and ticks<500:
		game.advance_simulation(.025)
		ticks+=1
	for unit in game.units:
		if int(unit.id)>=before and str(unit.type)==type_name:
			check(unit.has("hp") and unit.has("skillMana"),type_name+" completes native production with health and skill state")
			return unit
	check(false,type_name+" completes actual recruitment")
	return {}

func pose(unit: Dictionary, position: Vector2 = Vector2(.55,.5), path_index: int = 0) -> void:
	unit.merge({"position":position,"postPathIndex":path_index,"routeDistance":position.x-.05,"homeDistance":position.x-.05,"homePosition":position,"spawnPosition":position,"combatState":"guard" if str(unit.type) in ["monk","naginata","gunner"] else "engaged","gatherRemaining":0.0,"aim":Vector2.LEFT,"cooldown":1000.0,"animation":"idle","animationClock":0.0,"attackPlan":{},"deploying":false,"elevation":0},true)

func status_time(game: Node2D, seconds: float) -> void:
	var remaining: float = seconds
	while remaining>.0000001:
		var step: float = minf(.025,remaining)
		game.elapsed+=step
		game.unit_skills.step(step)
		remaining-=step

func enemy(game: Node2D, position: Vector2, source_wave: int = 1, kind: String = "raider") -> Dictionary:
	var target: Dictionary=game._spawn_enemy(kind,source_wave,{"pathIndex":0})
	target.merge({"position":position,"pointIndex":1},true)
	return target

func damage_source(game: Node2D, unit: Dictionary) -> Dictionary:
	var source: Dictionary=enemy(game,unit.position,1,"enemy_gunner")
	check(game.can_enemy_engage_unit(source,unit,true),"actual generated emplacement attacker is eligible for damage measurement")
	game.enemies.erase(source)
	return source

func expected(unit: Dictionary, definition: Dictionary) -> Dictionary:
	var level: int=clampi(int(unit.get("campaignLevel",1)),1,10)
	var stage: int=2 if level>=8 else 1 if level>=4 else 0
	var evolved_damage: float=1.3 if stage==2 else 1.12 if stage==1 else 1.0
	var permanent: float=(1.0+.08*(level-1))*evolved_damage
	var heal: float=permanent
	var type_name: String=str(unit.type)
	var damage_factor: float=0.0 if type_name=="monk" else 1.08 if type_name=="archer" and level>=3 else 1.0
	var range_factor: float=1.08 if type_name=="naginata" and level>=3 else 1.0
	var interval_factor: float=.92 if type_name=="gunner" and level>=5 else 1.0
	var armor: float=float(BASE_ARMOR[type_name])+.006*(level-1)+(.12 if type_name=="samurai" and level>=3 else 0.0)
	return {"damage":float(definition.damage)*permanent*damage_factor,"health":float(BASE_HP[type_name])*(1.0+.05*(level-1))*(1.25 if stage==2 else 1.12 if stage==1 else 1.0),"range":float(definition.range)*(1.0+.012*(level-1))*(1.0+.12*int(unit.get("elevation",0)))*(1.08 if stage==2 else 1.04 if stage==1 else 1.0)*range_factor,"interval":maxf(.25,float(definition.interval)*(.92 if stage==2 else .96 if stage==1 else 1.0)/(1.0+.015*(level-1))*interval_factor),"armor":minf(.65,armor),"healingFactor":heal,"resourceFactor":permanent,"healAmount":6.0*heal,"healInterval":1.0,"talismanPerSecond":2.0*heal,"prayerHealAmount":18.0*heal,"prayerManaAmount":minf(100.0,20.0*permanent),"prayerChargeSeconds":2.0*permanent,"mantraResourceFactor":1.0+.12*permanent,"stage":stage}

func assert_support(actual: Dictionary, wanted: Dictionary, tag: String) -> void:
	for key in ["healingFactor","resourceFactor","healAmount","healInterval","talismanPerSecond","prayerHealAmount","prayerManaAmount","prayerChargeSeconds","mantraResourceFactor"]:
		check(actual.has(key) and near(float(actual.get(key,-1)),float(wanted[key])),tag+" support field "+key)

func stats_and_display() -> void:
	var store=Store.new()
	var store_before: String=JSON.stringify(store.data)
	var rows: Array=[]
	for level in LEVELS:
		for type_name in TYPES:
			var game: Node2D=make_game({type_name:level})
			var unit: Dictionary=recruit(game,type_name)
			if unit.is_empty(): game.free();continue
			check(game.units.size()==(2 if type_name=="spear" and level>=5 else 1),"permanent recruitment quantity "+str(type_name)+" L"+str(level))
			game.units=[unit] # Solo fixture removes contextual auras and pair-count differences.
			pose(unit)
			var definition: Dictionary=game._unit_definition(unit)
			var display: Dictionary=store.army_stats(type_name,level)
			var base: Dictionary=game._stats(unit)
			for key in ["damage","range","interval","health","armor","healAmount","healInterval"]:
				check(near(float(display[key]),float(base[key])),"Progress/runtime solo %s L%d %s" % [type_name,level,key])
			assert_support(display.supportStats,expected(unit,definition),"Progress %s L%d" % [type_name,level])
			rows.append({"unit":type_name,"permanentLevel":level,"preview":display})
			var wanted: Dictionary=expected(unit,definition)
			var actual: Dictionary=game._stats(unit)
			var tag: String="%s L%d" % [type_name,level]
			for key in ["damage","range","interval","health","armor"]:
				check(near(float(actual[key]),float(wanted[key])),tag+" runtime "+key)
			check(near(float(unit.maxHp),float(wanted.health)),tag+" actual native maxHp")
			if type_name=="monk": assert_support(actual.supportStats,wanted,tag)
			else: check(actual.supportStats.is_empty(),tag+" does not compute unused healing preview fields")
			check(near(float(actual.healAmount),float(wanted.healAmount) if type_name=="monk" else 0),tag+" exposes healing only for monk")
			check(near(float(actual.healInterval),1.0),tag+" healing cadence stays one second")
			unit.hp=unit.maxHp
			var health: float=float(unit.hp)
			var gold: int=game.gold
			var received: float=game._damage_friendly(unit,10.0,damage_source(game,unit))
			check(near(received,10.0*(1.0-float(wanted.armor))) and near(health-float(unit.hp),received),tag+" actual incoming health loss uses growing armor once")
			check(game.gold==gold,tag+" incoming damage cannot grant money")
			check(not game.has_method("upgrade_selected") and not game.has_method("merge_selected"),tag+" has no battlefield growth action")
			check(not unit.has("tier") and not unit.has("level"),tag+" recruits only permanent growth state")
			var public: Dictionary=game._unit_public(unit)
			for removed_key in ["tier","level","upgradeCost","upgradeReady","mergeReady","mergeCandidateId","maxTier","maxLevel"]:
				check(not public.has(removed_key),tag+" public snapshot omits "+removed_key)
			check(near(float(public.maxHp),float(wanted.health)) and near(float(public.armor),float(wanted.armor)),tag+" snapshot agrees with live health and armor")
			for skill in Skills.UNLOCKS:
				var owned: bool=str(Skills.UNLOCKS[skill].type)==type_name and level>=int(Skills.UNLOCKS[skill].level)
				check(game.unit_skills.has_skill(unit,skill)==owned,tag+" permanent level unlocks "+str(skill))
			if type_name=="monk":
				var target: Dictionary=enemy(game,Vector2(.525,.5))
				check(near(float(actual.damage),0.0) and game.unit_skills.prepare_attack(unit,target,100,0).is_empty(),tag+" healing growth cannot invent a monk attack")
				game.enemies.clear()
			game.free()
	check(JSON.stringify(store.data)==store_before,"reading every army preview mutates no player progression")
	observations["soloDisplayedStats"]=rows

func pulse_and_talisman() -> void:
	var rows: Array=[]
	for level in LEVELS:
		var game: Node2D=make_game({"monk":level,"samurai":10})
		var monk: Dictionary=recruit(game,"monk")
		var ally: Dictionary=recruit(game,"samurai")
		if monk.is_empty() or ally.is_empty(): game.free();continue
		pose(monk,Vector2(.52,.5));pose(ally,Vector2(.58,.5))
		var wanted: Dictionary=expected(monk,game._unit_definition(monk))
		game._damage_friendly(ally,float(ally.maxHp)*.8/(1.0-float(game._stats(ally).armor)),damage_source(game,ally))
		check(float(ally.hp)>0 and float(ally.maxHp)-float(ally.hp)>float(wanted.healAmount)+4.0*float(wanted.talismanPerSecond),"fixture target survives with enough missing HP for full support measurement")
		var health: float=float(ally.hp)
		var gold: int=game.gold
		var event_begin: int=events.size()
		game.unit_skills._next_heal_at=float(game.elapsed)+1.0
		status_time(game,.975)
		check(near(float(ally.hp),health),"L%d no basic healing before the one-second pulse" % level)
		status_time(game,.075)
		var heal_delta: float=float(ally.hp)-health
		check(near(heal_delta,float(wanted.healAmount)),"L%d actual native basic heal scales" % level)
		check(game.gold==gold and bool(game.unit_skills.public_state(monk).healing),"actual healing has a heal pose and no money reward")
		var talisman: Dictionary=ally.get("friendlySkillStatuses",{}).get("talisman",{})
		check(not talisman.is_empty()==bool(level>=3),"only permanent Lv3 grants the talisman")
		var ticks_delta: float=0.0
		if level>=3:
			check(near(float(talisman.get("amountPerSecond",-1)),float(wanted.talismanPerSecond)),"talisman stores the cast-time actual growing amount")
			pose(ally,Vector2(.95,.5))
			monk.campaignLevel=1
			if level==8: monk.hp=0.0
			game.unit_skills._next_heal_at=100000.0
			health=float(ally.hp)
			status_time(game,4.10)
			ticks_delta=float(ally.hp)-health
			check(near(ticks_delta,4.0*float(wanted.talismanPerSecond)),"four committed talisman ticks preserve caster growth despite later level/death changes")
			check(not ally.friendlySkillStatuses.has("talisman"),"committed talisman expires after four ticks")
		var heal_events: int=0
		for index in range(event_begin,events.size()):
			var event: Dictionary=events[index]
			if str(event.get("type",""))!="heal": continue
			heal_events+=1
			check(float(event.healAmount)>0 and near(float(event.hpBefore)+float(event.healAmount),float(event.hpAfter)),"every support event reports only actual positive HP change")
		check(heal_events==(5 if level>=3 else 1),"one pulse/four committed ticks emit exactly their real heal events")
		rows.append({"permanentLevel":level,"actualBasicHeal":heal_delta,"actualFourTalismanTicks":ticks_delta})
		game.free()
	observations["actualHealingMatrix"]=rows

func prayer_and_resources() -> void:
	var rows: Array=[]
	for level in [8,10]:
		var game: Node2D=make_game({"monk":level,"naginata":10,"commander":3})
		var monk: Dictionary=recruit(game,"monk")
		var guard: Dictionary=recruit(game,"naginata")
		var horse: Dictionary=recruit(game,"commander")
		if monk.is_empty() or guard.is_empty() or horse.is_empty(): game.free();continue
		pose(monk,Vector2(.5,.5));pose(guard,Vector2(.58,.5));pose(horse,Vector2(.6,.5))
		var wanted: Dictionary=expected(monk,game._unit_definition(monk))
		game._damage_friendly(guard,float(guard.maxHp)*.8/(1.0-float(game._stats(guard).armor)),damage_source(game,guard))
		guard.skillMana=0.0
		horse.chargeCooldown=10.0
		game.unit_skills._next_heal_at=100000.0
		var health: float=float(guard.hp)
		var gold: int=game.gold
		var killed: Array=[]
		var rewards: int=0
		var event_begin: int=events.size()
		for index in range(6):
			var target: Dictionary=enemy(game,Vector2(.515,.5))
			rewards+=int(target.reward)
			killed.append(target)
			game._damage_enemy(target,float(target.hp)+1.0,"naginata",guard)
		game.advance_simulation(.025)
		check(game.kills==6 and game.gold==gold+rewards,"six actual deaths award exactly native kill funds")
		var heal: float=float(guard.hp)-health
		check(near(heal,float(wanted.prayerHealAmount)),"actual victory prayer HP includes all support growth once")
		var expected_mana: float=float(wanted.prayerManaAmount)+14.0*.025*float(wanted.mantraResourceFactor)
		var expected_charge: float=10.0-.025*float(wanted.mantraResourceFactor)-float(wanted.prayerChargeSeconds)
		check(near(float(guard.skillMana),expected_mana),"prayer mana and real mantra regeneration use permanent support growth")
		check(near(float(horse.chargeCooldown),expected_charge),"prayer readiness and real mantra cooldown use permanent support growth")
		check(int(monk.prayerCount)==0 and near(float(monk.prayerReadyAt)-float(game.unit_skills.clock),12.0),"six kills consume one prayer with its unchanged twelve-second cooldown")
		var prayer_events: int=0
		for index in range(event_begin,events.size()):
			if str(events[index].get("type",""))=="heal" and str(events[index].get("effectKind",""))=="victory_prayer": prayer_events+=1
		check(prayer_events==1,"only the wounded recipient emits an actual prayer HP event")
		var mana: float=float(guard.skillMana)
		var cooldown: float=float(horse.chargeCooldown)
		health=float(guard.hp)
		for target in killed: game.unit_skills.on_enemy_killed(target,guard)
		check(near(float(guard.hp),health) and near(float(guard.skillMana),mana) and near(float(horse.chargeCooldown),cooldown) and game.gold==gold+rewards,"duplicate kill notifications cannot replay a prayer or reward")
		monk.prayerCount=6
		game.unit_skills._cast_prayer(monk)
		check(near(float(guard.hp),health),"queued six kills cannot bypass prayer cooldown")
		rows.append({"permanentLevel":level,"actualPrayerHeal":heal,"actualGuardMana":mana,"actualChargeCooldown":cooldown})
		game.free()
	observations["actualPrayerMatrix"]=rows

func ordering_and_boundaries() -> void:
	var game: Node2D=make_game({"monk":10,"naginata":5,"samurai":10,"commander":3})
	var weak: Dictionary=recruit(game,"monk")
	var strong: Dictionary=recruit(game,"monk")
	var guard: Dictionary=recruit(game,"naginata")
	var target: Dictionary=recruit(game,"samurai")
	var horse: Dictionary=recruit(game,"commander")
	if weak.is_empty() or strong.is_empty() or guard.is_empty() or target.is_empty() or horse.is_empty(): game.free();return
	weak.campaignLevel=5
	pose(weak,Vector2(.47,.5));pose(strong,Vector2(.5,.5));pose(guard,Vector2(.57,.5));pose(target,Vector2(.58,.5));pose(horse,Vector2(.6,.5))
	var wanted: Dictionary=expected(strong,game._unit_definition(strong))
	var incoming: Dictionary=damage_source(game,target)
	game._damage_friendly(target,float(target.maxHp)*.8/(1.0-float(game._stats(target).armor)),incoming)
	var health: float=float(target.hp)
	game.unit_skills._next_heal_at=float(game.elapsed)+.025
	status_time(game,.05)
	check(near(float(target.hp)-health,float(wanted.healAmount)),"weak-first registration still lets the stronger monk claim one pulse")
	var status: Dictionary=target.friendlySkillStatuses.get("talisman",{})
	check(int(status.source.id)==int(strong.id),"strong-first support ordering records the actual stronger caster")
	var amount: float=float(status.amountPerSecond)
	pose(strong,Vector2(.95,.5))
	health=float(target.hp)
	game.unit_skills._heal_pulse()
	check(float(target.hp)>health and near(float(target.friendlySkillStatuses.talisman.amountPerSecond),amount),"weaker later healing cannot downgrade an unexpired stronger talisman")
	check(int(target.friendlySkillStatuses.talisman.source.id)==int(strong.id),"weaker refresh keeps the stronger talisman provenance")
	pose(strong,Vector2(.5,.5))
	game.units.reverse()
	health=float(target.hp)
	game.unit_skills._heal_pulse()
	check(near(float(target.hp)-health,float(wanted.healAmount)),"strong-first reversed registration gives the same single strongest basic heal")
	check(near(float(game.unit_skills.mana_charge_factor(guard)),float(wanted.mantraResourceFactor)),"overlapping mantras select the strongest resource source, not registration order")
	guard.skillMana=0.0
	game.unit_skills._next_heal_at=100000.0
	status_time(game,1.0)
	check(near(float(guard.skillMana),14.0*float(wanted.mantraResourceFactor)),"two mantras do not stack actual mana regeneration")
	guard.skillMana=99.9
	status_time(game,1.0)
	check(near(float(guard.skillMana),100.0),"actual mantra respects the guard resource cap")
	strong.prayerCount=6;strong.prayerReadyAt=0
	game.unit_skills._prayer_target_ready.clear()
	horse.chargeCooldown=.1
	game.unit_skills._cast_prayer(strong)
	check(near(float(guard.skillMana),100.0) and near(float(horse.chargeCooldown),0.0),"actual prayer clamps mana and remaining charge cooldown at their bounds")
	# Full/dead targets receive no fictional health events or resurrection.
	for unit in game.units: unit.hp=unit.maxHp;unit.friendlySkillStatuses={}
	var before: int=events.size()
	game.unit_skills._heal_pulse()
	check(events.size()==before,"full-health allies emit no zero-heal support event")
	target.hp=0.0
	game.unit_skills._heal_pulse()
	check(near(float(target.hp),0.0) and events.size()==before,"a dead ally is never revived by grown basic healing")
	target.hp=float(target.maxHp)*.2
	game.unit_skills._heal_pulse()
	var pending_status: Dictionary=target.friendlySkillStatuses.get("talisman",{}).duplicate(true)
	health=float(target.hp)
	var skill_clock: float=float(game.unit_skills.clock)
	var mana: float=float(guard.skillMana)
	for mode in ["pause","between","finish"]:
		game.paused=mode=="pause";game.between_waves=mode=="between";game.finished=mode=="finish"
		game.elapsed+=1.0
		game.unit_skills.step(1.0)
		check(near(float(target.hp),health) and near(float(guard.skillMana),mana) and near(float(game.unit_skills.clock),skill_clock),mode+" freezes committed support and resources")
	game.paused=false;game.between_waves=false;game.finished=false
	game.elapsed=skill_clock
	check(target.friendlySkillStatuses.get("talisman",{})==pending_status,"freeze retains cast-time talisman data")
	var generation: int=game.unit_skills.generation
	game.load_map(fixture(),20)
	check(game.units.is_empty() and game.unit_skills.generation>generation and near(float(game.unit_skills.clock),0.0),"new battle clears old support recipients and growth-dependent statuses")
	game.free()
	for level in LEVELS:
		var definition: Dictionary={}
		for entry in catalog:
			if str(entry.id)=="monk": definition=entry
		var helper=Skills.new()
		var support: Dictionary=helper.support_stats({"type":"monk","campaignLevel":level,"definition":definition})
		check(float(support.prayerManaAmount)<=100.0,"permanent prayer mana amount has a hard resource cap")
	var unit: Dictionary={"type":"samurai","campaignLevel":999}
	var helper=Skills.new()
	var capped: Dictionary=helper.modify_incoming(unit,100,.95)
	check(near(float(capped.armor),.65) and near(float(capped.amount),35.0),"defensive hook applies the common 65-percent cap even with an extreme base armor")
	unit.campaignLevel=-10
	check(near(float(Growth.armor(unit,false)),.24),"invalid low growth coordinates clamp to base armor")
	unit.invulnerableUntil=1.0
	check(near(float(helper.modify_incoming(unit,100,.24).amount),0.0),"actual approved guard invulnerability still overrides growing armor")
	unit.invulnerableUntil=0.0
	check(near(float(helper.modify_incoming(unit,NAN,.24).amount),0.0),"invalid incoming damage cannot corrupt health")

func attacks_scale_once() -> void:
	var rows: Array=[]
	for type_name in ["spear","gunner"]:
		for level in LEVELS:
			var game: Node2D=make_game({type_name:level})
			var unit: Dictionary=recruit(game,type_name)
			if unit.is_empty(): game.free();continue
			game.units=[unit]
			pose(unit)
			# High source-wave targets retain native health/armor but prevent damage clipping.
			var primary: Dictionary=enemy(game,Vector2(.525,.5),10000)
			var behind: Dictionary=enemy(game,Vector2(.485,.5),10000)
			var lateral: Dictionary=enemy(game,Vector2(.485,.535),10000)
			var wanted: Dictionary=expected(unit,game._unit_definition(unit))
			var damage: float=float(game._stats(unit).damage)
			var primary_hp: float=float(primary.hp)
			var behind_hp: float=float(behind.hp)
			var plan: Dictionary=game.unit_skills.prepare_attack(unit,primary,damage,0)
			check(not plan.is_empty() and near(float(plan.skillMeta.baseDamage),float(wanted.damage)),"committed attack stores already-grown damage exactly once")
			game._release_unit_attack(unit,plan)
			if type_name=="gunner":
				check(near(float(primary.hp),primary_hp),"grown gunner damage waits for actual bullet impact")
				for tick in range(80): game._update_projectiles(.01)
			var primary_loss: float=primary_hp-float(primary.hp)
			var secondary_loss: float=behind_hp-float(behind.hp)
			var pierce_factor: float=.55 if type_name=="spear" else .65
			check(near(primary_loss,float(wanted.damage)),"actual %s L%d primary damage has no duplicate growth" % [type_name,level])
			check(near(secondary_loss,float(wanted.damage)*pierce_factor if level>=3 else 0.0),"actual pierce uses the fixed skill coefficient on already-grown native damage")
			check(near(float(lateral.hp),float(lateral.maxHp)),"grown pierce still respects its unchanged narrow geometry")
			var after: float=float(primary.hp)+float(behind.hp)
			game._release_unit_attack(unit,plan)
			for tick in range(80): game._update_projectiles(.01)
			check(near(float(primary.hp)+float(behind.hp),after),"a consumed attack cannot pay out growing damage twice")
			if type_name=="spear" and level>=8:
				var poison: Dictionary=primary.get("skillStatuses",{}).get("poison",{})
				check(near(float(poison.get("dps",-1)),minf(20.0,float(wanted.damage)*.06)),"grown poison retains its original DPS cap and one damage multiplier")
			rows.append({"type":type_name,"permanentLevel":level,"actualPrimary":primary_loss,"actualPierce":secondary_loss})
			game.free()
	observations["actualPierceMatrix"]=rows

func save_preview_roundtrip() -> void:
	var store=Store.new()
	store.save_path="user://qa_unit_growth_progress.json"
	var map_id: String=""
	for id in store.stage_numbers: map_id=str(id);break
	store.data.maps[map_id]={"cleared":true,"bestKills":10}
	store.data.army.currency=987
	for type_name in TYPES: store.data.army.levels[type_name]=10
	var before: Dictionary=store.data.duplicate(true)
	var stats: Dictionary={}
	for type_name in TYPES: stats[type_name]=store.army_stats(type_name)
	check(store.write_save(),"isolated growth fixture persists through actual atomic save")
	var loaded=Store.new()
	loaded.save_path=store.save_path
	loaded.read_save()
	check(loaded.read_error.is_empty() and int(loaded.data.army.currency)==987 and loaded.data.maps.has(map_id),"growth preview save roundtrip preserves campaign funds and map progress")
	for type_name in TYPES:
		check(loaded.army_level(type_name)==10,"permanent level roundtrip "+str(type_name))
		var actual: Dictionary=loaded.army_stats(type_name)
		for key in ["damage","range","interval","health","armor","healAmount","healInterval"]:
			check(near(float(actual[key]),float(stats[type_name][key])),"saved preview agrees after reload "+str(type_name)+"/"+key)
	check(store.data==before,"preview and serialization do not change the test's army state")

func run() -> void:
	if not profile_allowed():
		push_error("UNIT_GROWTH refuses a profile outside "+qa_project_path("tests/profiles/unit-growth-scaling/"))
		quit(2)
		return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	for path in ["res://native/units.json","res://native/maps.json","res://native/curriculum.json","res://native/unit_growth.gd","res://native/unit_skills.gd","res://native/progress.gd","res://native/game.gd","res://native/ground_combat.gd"]:
		original_bytes[path]=FileAccess.get_file_as_string(path)
	stats_and_display()
	pulse_and_talisman()
	prayer_and_resources()
	ordering_and_boundaries()
	attacks_scale_once()
	save_preview_roundtrip()
	for path in original_bytes: check(FileAccess.get_file_as_string(path)==original_bytes[path],"QA preserves production source/data "+str(path))
	var result: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"Headless native Game recruitment/HP/heal/status/actual kill prayer/pierce/Progress preview contracts; fixture gold/unlocks/positions/power states and high-HP native enemies; no campaign difficulty/GPU claim","profile":ProjectSettings.globalize_path("user://"),"sourceHashes":{}}
	for path in original_bytes: result.sourceHashes[path]=str(original_bytes[path]).sha256_text()
	var output: FileAccess=FileAccess.open("user://qa_unit_growth_scaling.json",FileAccess.WRITE)
	if output==null:
		push_error("UNIT_GROWTH cannot write the isolated report")
		quit(3)
		return
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	print("UNIT_GROWTH_QA "+JSON.stringify({"checks":checks,"failures":failures,"report":ProjectSettings.globalize_path("user://qa_unit_growth_scaling.json")}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
