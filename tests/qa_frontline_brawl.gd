extends SceneTree
## Changed recruitment, one local brawl, physical return and coordinated raids.
const Battle=preload("res://native/game.gd")
const Growth=preload("res://native/unit_growth.gd")
var catalog: Array=[]
var checks: int=0
var failures: Array=[]
var evidence: Dictionary={}

func _initialize() -> void: call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("FRONTLINE_BRAWL "+note)

func fixture() -> Dictionary:
	return {"id":"frontline-brawl-fixture","stageNumber":1,"theme":"forest","initialGold":10000,"unitLimit":1,"totalWaves":10,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"north","x":.5,"y":.64,"r":.09},{"id":"south","x":.5,"y":.36,"r":.09}],"tactics":{"groundPosts":[]}}

func make_game(levels: Dictionary={}, timed: bool=false) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,["archer","spear","samurai","gunner","naginata","monk","ninja","commander"],levels)
	game.load_map(fixture(),10 if timed else 0)
	return game

func hold(game: Node2D) -> void:
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=10000

func tick(game: Node2D, seconds: float) -> void:
	for unused in range(ceili(seconds/.025)): game.advance_simulation(.025)

func hostile(game: Node2D, point: Vector2, kind: String="enemy_samurai") -> Dictionary:
	var enemy: Dictionary=game._spawn_enemy(kind,1,{"originKind":"raider","pathIndex":0})
	enemy.position=point;enemy.pointIndex=1;enemy.routeProgress=point.x-.05
	enemy["ingressActive"]=false
	return enemy

func quantities_and_capacity() -> void:
	for level in range(1,11):
		check(Growth.recruit_quantity("spear",level)==(1 if level<4 else 3 if level<8 else 5),"Spear 1/3/5 at real Lv1/4/8, level "+str(level))
		check(Growth.recruit_quantity("archer",level)==(1 if level<5 else 2),"Archer 1/2 at real middle Lv5, level "+str(level))
	var game: Node2D=make_game({"spear":8,"archer":5})
	hold(game)
	for unused in range(30): check(game.begin_placement("spear",0),"Paid marching order accepted beyond old24-order limit")
	var bow: Dictionary=game.submit_deployment("archer",Vector2(.5,.64))
	check(bool(bow.ok) and int(bow.quantity)==2,"Paid archer order reserves two actual member positions")
	check(game.recruitment_queue.size()==31,"More than24 queued orders coexist")
	var paid: int=10000-game.gold
	game.paused=true
	tick(game,3)
	check(game.units.is_empty(),"Pause freezes production and does not spend additional gold")
	game.paused=false
	tick(game,2.2)
	check(game.units.size()==152 and game.recruitment_queue.is_empty(),"All150 spears plus2 archers spawn despite legacy unitLimit1")
	var bows: Array=game.units.filter(func(unit: Dictionary): return str(unit.type)=="archer")
	check(bows.size()==2 and bows[0].position.distance_to(bows[1].position)>.02,"Archer members occupy separate real homes")
	var receipts: int=0
	for unit in game.units: receipts+=int(unit.paid)
	check(paid==810 and receipts==paid,"Each multi-member order charges once and conserves per-member receipts")
	check(game.snapshot().unitLimit==null and game.snapshot().recruitmentCapacity==null,"Public limits are explicitly absent")
	evidence["unlimitedRecruitment"]={"orders":31,"actors":game.units.size(),"goldSpent":paid,"archerHomes":[str(bows[0].position),str(bows[1].position)]}
	game.free()
	var cancelled: Node2D=make_game({"spear":4})
	hold(cancelled)
	check(cancelled.begin_placement("spear",0),"Three-member order can be queued")
	var job: int=int(cancelled.recruitment_queue[0].id)
	check(cancelled.cancel_recruitment(job) and not cancelled.cancel_recruitment(job) and cancelled.gold==10000,"Squad cancellation refunds exactly one original order once")
	cancelled.free()

func local_brawl() -> void:
	var game: Node2D=make_game({"spear":4})
	hold(game)
	var a: Dictionary=hostile(game,Vector2(.49,.60))
	var b: Dictionary=hostile(game,Vector2(.53,.60))
	var c: Dictionary=hostile(game,Vector2(.51,.58),"raider")
	var opposite: Dictionary=hostile(game,Vector2(.5,.36))
	var drop: Vector2=Vector2(.5,.63)
	var preview: Dictionary=game.deployment_preview("spear",drop,"lane")
	check(bool(preview.ok) and bool(preview.get("supportDeployment",false)) and game._point(preview.position).distance_to(drop)<.001,"Tower drag preview keeps actual drop, not base position")
	check(bool(game.submit_deployment("spear",drop,"lane").ok),"Tower support commits through normal paid deployment API")
	game._advance_recruitment(1.3)
	var unit: Dictionary=game.units[0]
	check(game.units.size()==3 and str(unit.supportPhase)=="brawl","Produced three-member support squad enters one local brawl")
	check(unit.supportEnemyIds.has(int(a.id)) and unit.supportEnemyIds.has(int(b.id)) and unit.supportEnemyIds.has(int(c.id)) and not unit.supportEnemyIds.has(int(opposite.id)),"Initial cohort includes local group, excludes opposite emplacement")
	var locked: Array=unit.supportEnemyIds.duplicate()
	a.hp=0
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="brawl" and not game.ground_combat._support_target(unit).is_empty(),"First enemy defeat does NOT end the group brawl")
	var late: Dictionary=hostile(game,Vector2(.51,.61))
	game.ground_combat.step(.025)
	check(unit.supportEnemyIds==locked and not game.ground_combat.primary_target_allowed(unit,late,"prepare"),"Late wave is never added or acquired during the committed brawl")
	b.hp=0;c.hp=0
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="return" and int(unit.targetId)==-1,"Resolved group causes immediate return despite live late attacker")
	var previous: Vector2=unit.position
	var max_stride: float=0.0
	for unused in range(600):
		game.ground_combat.step(.025)
		max_stride=maxf(max_stride,unit.position.distance_to(previous))
		previous=unit.position
		if str(unit.supportPhase)=="done": break
	check(str(unit.supportPhase)=="done" and max_stride<.006,"Return physically retraces/join route without teleporting")
	var distance_before: float=float(unit.routeDistance)
	game.enemies.clear()
	for unused in range(30): game.ground_combat.step(.025)
	check(float(unit.routeDistance)<distance_before and str(unit.supportPhase)=="done","Returned survivors resume ordinary advance and never start another support mission")
	evidence["oneLocalBrawl"]={"initialEnemyIds":locked,"lateEnemyId":int(late.id),"maxReturnStride":max_stride,"returnPhase":str(unit.supportPhase)}
	game.free()
	var empty: Node2D=make_game()
	hold(empty)
	check(bool(empty.submit_deployment("spear",drop,"lane").ok),"Empty tower neighborhood remains a legal support drop")
	empty._advance_recruitment(1.3)
	check(str(empty.units[0].supportPhase)=="return","No group means return immediately, never wait for next assault")
	check(not bool(empty.deployment_preview("spear",Vector2(.2,.9),"lane").ok),"Support cannot deploy on arbitrary unconnected ground")
	empty.free()

func ordinary_only_brawl() -> void:
	var game: Node2D=make_game({"spear":4})
	hold(game)
	var first: Dictionary=hostile(game,Vector2(.49,.60),"raider")
	var second: Dictionary=hostile(game,Vector2(.53,.60),"raider")
	check(bool(game.submit_deployment("spear",Vector2(.5,.63),"lane").ok),"Ordinary-only local support is paid through normal deployment")
	game._advance_recruitment(1.3)
	check(game.units.size()==3,"Ordinary-only support produces the full paid squad")
	if game.units.is_empty(): game.free();return
	var unit: Dictionary=game.units[0]
	var cohort: Array=unit.supportEnemyIds.duplicate()
	check(str(unit.supportPhase)=="brawl" and cohort.size()==2 and cohort.has(int(first.id)) and cohort.has(int(second.id)),"Local ordinary soldiers form a valid brawl without any emplacement attacker")
	first.hp=0
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="brawl" and int(game.ground_combat._support_target(unit).get("id",-1))==int(second.id),"Ordinary-only brawl continues against the remaining original soldier")
	var late: Dictionary=hostile(game,Vector2(.51,.61),"raider")
	check(not game.ground_combat.primary_target_allowed(unit,late,"prepare"),"Ordinary-only brawl also excludes late reinforcements")
	second.hp=0
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="return" and unit.supportEnemyIds==cohort,"Ordinary-only group completion returns without committing another group")
	evidence["ordinaryOnlyBrawl"]={"committedIds":cohort,"lateId":int(late.id),"phaseAfterCompletion":str(unit.supportPhase)}
	game.free()

func raid_admission_budget() -> void:
	var game: Node2D=make_game({},true)
	hold(game)
	game.wave=3
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
	var active_cap: int=int(game._timed_wave().activeCap)
	check(active_cap==16,"Early coordinated assault uses the actual16-actor window")
	for unused in range(2): hostile(game,Vector2(.5,.6))
	var dead: Dictionary=hostile(game,Vector2(.52,.6))
	dead.hp=0
	hostile(game,Vector2(.7,.5),"raider")
	# These real queued units and departure warnings are not yet live actors.
	for kind in ["enemy_samurai","enemy_archer","raider"]:
		game.spawn_queue.append(kind)
		game.spawn_source_waves.append(1)
		game.spawn_metadata.append({"originKind":"raider","pathIndex":0})
	var entry: Dictionary={"id":"budget-authored-entry","pathIndex":0,"points":[Vector2(.5,-.1),Vector2(.5,.5)],"joinDistance":.45,"pointIndex":1}
	for unused in range(2): game._queue_enemy_spawn("enemy_archer",1,{"originKind":"raider","pathIndex":0,"ambushEntry":entry.duplicate(true)})
	check(game.ambush_warnings.size()==2,"Two authored-entry attackers are genuinely awaiting departure")
	check(game._emplacement_spawn_budget()==2,"Live, queued and warned raiders jointly reserve admission; dead/main troops do not consume raid slots")
	var notices: Array=[]
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="emplacement_warning": notices.append(event.duplicate(true))
	)
	var queued_before: int=game.spawn_queue.size()
	game._append_emplacement_assault()
	var dispatched: Dictionary={}
	for index in range(queued_before,game.spawn_metadata.size()):
		var zone_id: String=str(game.spawn_metadata[index].get("assaultZoneId",""))
		dispatched[zone_id]=int(dispatched.get(zone_id,0))+1
	check(game.spawn_queue.size()-queued_before==2 and dispatched.size()==1 and int(dispatched.get("north",0))==2,"Constrained admission dispatches one complete pair, never a partial second group")
	check(game._emplacement_spawn_budget()==0,"Admitted raids fill only half of the16-actor enemy budget")
	check(notices.size()==1,"A real constrained dispatch emits exactly one warning")
	if not notices.is_empty():
		var notice: Dictionary=notices[0]
		var announced: Array=notice.get("targetZoneIds",[])
		check(int(notice.get("count",-1))==2 and announced.size()==1 and announced.has("north") and not announced.has("south"),"Warning names and counts only the emplacement group actually dispatched")
	var notice_count: int=notices.size()
	var queued_full: int=game.spawn_queue.size()
	game._append_emplacement_assault()
	check(game.spawn_queue.size()==queued_full and notices.size()==notice_count,"No admission capacity produces neither extra raiders nor a false warning")
	var budget_before_departure: int=game._emplacement_spawn_budget()
	game._advance_ambush_warnings(2.1)
	check(game.ambush_warnings.is_empty() and game._emplacement_spawn_budget()==budget_before_departure,"Departure warning becoming a live raider does not release reserved capacity")
	var removed: bool=false
	for index in range(game.spawn_queue.size()):
		if str(game.spawn_queue[index]) not in Battle.EMPLACEMENT_ENEMY_KINDS: continue
		game.spawn_queue.remove_at(index);game.spawn_source_waves.remove_at(index);game.spawn_metadata.remove_at(index)
		removed=true
		break
	check(removed and game._emplacement_spawn_budget()==1,"One released raid slot is recorded while the other occupied slots remain")
	var queued_odd: int=game.spawn_queue.size()
	game._append_emplacement_assault()
	check(game.spawn_queue.size()==queued_odd and notices.size()==notice_count,"One remaining slot cannot create a partial raid or claim another attacked zone")
	evidence["raidAdmissionBudget"]={"activeCap":active_cap,"dispatchedGroups":dispatched,"notices":notices,"remainingBudget":game._emplacement_spawn_budget(),"queuedMainTroops":game.spawn_queue.count("raider")}
	game.free()

func coordinated_pressure() -> void:
	var game: Node2D=make_game({},true)
	hold(game)
	for wave_index in [1,2,4,5]:
		game.wave=wave_index
		check(not bool(game.emplacement_assault_plan().active),"Main pressure has no new tower assault on wave "+str(wave_index))
	game.wave=3
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
	game._append_emplacement_assault()
	var assigned: Dictionary={}
	for entry in game.spawn_metadata: assigned[str(entry.assaultZoneId)]=int(assigned.get(str(entry.assaultZoneId),0))+1
	check(game.spawn_queue.size()==4 and assigned.get("north",0)==2 and assigned.get("south",0)==2,"One assault dispatches finite groups at BOTH emplacements")
	for unused in range(4): hostile(game,Vector2(.5,.6))
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear();game.battle_refill_clock=0
	game._refill_timed_wave()
	check(not game.spawn_queue.is_empty(),"Surviving tower raiders do NOT suppress main-line replenishment")
	check(game.spawn_queue.all(func(kind: String): return kind not in Battle.EMPLACEMENT_ENEMY_KINDS),"Main-line refill never creates another tower assault")
	check(not game.emplacement_protection_active(),"Starter emplacements have no naginata-unlock immunity")
	evidence["coordinatedAssault"]={"wave":3,"groups":assigned,"frontlineRefill":game.spawn_queue.duplicate(),"cadenceWaves":3}
	game.free()
	var simultaneous: Node2D=make_game()
	hold(simultaneous)
	check(bool(simultaneous.submit_deployment("archer",Vector2(.5,.64)).ok) and bool(simultaneous.submit_deployment("archer",Vector2(.5,.36)).ok),"Both emplacements receive real paid archers")
	simultaneous._advance_recruitment(2.2)
	var north: Dictionary=simultaneous.units[0]
	var south: Dictionary=simultaneous.units[1]
	var north_enemy: Dictionary=simultaneous._spawn_enemy("enemy_archer",1,{"originKind":"raider","pathIndex":0,"assaultZoneId":"north"})
	var south_enemy: Dictionary=simultaneous._spawn_enemy("enemy_archer",1,{"originKind":"raider","pathIndex":0,"assaultZoneId":"south"})
	north_enemy.position=Vector2(.5,.5);south_enemy.position=Vector2(.5,.5)
	check(int(simultaneous._hunter_target(north_enemy,0).id)==int(north.id) and int(simultaneous._hunter_target(south_enemy,0).id)==int(south.id),"Coordinated groups choose DIFFERENT assigned emplacements")
	tick(simultaneous,1.3)
	check(float(north.hp)<float(north.maxHp) and float(south.hp)<float(south.maxHp),"Both emplacements actually take attack damage in the same combat window")
	evidence["simultaneousDamage"]={"northHp":float(north.hp),"southHp":float(south.hp),"seconds":1.3}
	simultaneous.free()

func actual_group_combat() -> void:
	var game: Node2D=make_game({"spear":4})
	hold(game)
	var first: Dictionary=hostile(game,Vector2(.49,.60))
	var second: Dictionary=hostile(game,Vector2(.53,.60))
	check(bool(game.submit_deployment("spear",Vector2(.5,.63),"lane").ok),"Real group-combat squad is paid and placed")
	game._advance_recruitment(1.3)
	var squad_ids: Array=game.units.map(func(unit: Dictionary): return int(unit.id))
	var attacked: Dictionary={}
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="shot" and str(event.get("side",""))=="friendly": attacked[int(event.get("victimId",-1))]=true
	)
	var first_down: bool=false
	var continued: bool=false
	var late: Dictionary={}
	for unused in range(1600):
		game.advance_simulation(.025)
		if not first_down and (float(first.hp)<=0 or float(second.hp)<=0):
			first_down=true
			late=hostile(game,Vector2(.56,.65))
			for unit in game.units:
				if squad_ids.has(int(unit.id)) and str(unit.get("supportPhase",""))=="brawl": continued=true
		if float(first.hp)<=0 and float(second.hp)<=0: break
	check(first_down and continued and float(first.hp)<=0 and float(second.hp)<=0,"Actual support attacks defeat MORE THAN ONE original enemy before returning")
	check(not game.units.is_empty() and not late.is_empty() and float(late.hp)==float(late.maxHp),"Late reinforcing attacker survives without extending the completed encounter")
	evidence["actualGroupCombat"]={"firstEnemyHp":float(first.hp),"secondEnemyHp":float(second.hp),"continuedAfterFirstKill":continued,"survivors":game.units.size(),"lateEnemyHp":float(late.get("hp",-1)),"elapsed":game.elapsed,"attacked":attacked}
	game.free()

func starter_duel() -> void:
	var game: Node2D=make_game()
	hold(game)
	check(game.begin_placement("spear",0),"Fragile starter spear is bought through real recruitment")
	game._advance_recruitment(1.3)
	var unit: Dictionary=game.units[0]
	unit.combatState="march";unit.gatherRemaining=0
	var enemy: Dictionary=hostile(game,unit.position+Vector2(-.025,0),"raider")
	var start: Dictionary={"spearHp":float(unit.hp),"enemyHp":float(enemy.hp),"spearHit":float(game._stats(unit).damage),"spearInterval":float(game._stats(unit).interval)}
	for unused in range(800):
		game.advance_simulation(.025)
		if game.units.is_empty() or float(enemy.hp)<=0: break
	check(game.units.is_empty() and float(enemy.hp)>0,"Unsupported basic spear loses actual one-on-one instead of overpowering raider")
	evidence["starterDuel"]={"start":start,"enemyRemainingHp":float(enemy.hp),"spearSurvived":not game.units.is_empty()}
	game.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(ProjectSettings.globalize_path("res://tests/profiles/frontline-brawl-01/").replace("\\","/").to_lower()): quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	quantities_and_capacity()
	local_brawl()
	ordinary_only_brawl()
	raid_admission_budget()
	coordinated_pressure()
	actual_group_combat()
	starter_duel()
	var report: Dictionary={"checks":checks,"failures":failures,"evidence":evidence,"scope":"Focused paid recruitment, actual local group commitment/physical return, finite multi-emplacement raids plus continuous main pressure. CPU simulation, not rendered full-game performance or completed balance acceptance."}
	var output: FileAccess=FileAccess.open("res://tests/qa_frontline_brawl.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("FRONTLINE_BRAWL_QA checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
