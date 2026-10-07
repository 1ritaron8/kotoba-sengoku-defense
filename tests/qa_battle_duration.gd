extends "res://tests/qa_campaign_balance.gd"
## Runtime plans for every authored stage and real starter-only survival battles.
## Recruitment and upgrades reuse the campaign bot's public placement/economy path.

var duration_results: Array = []
var opening_observations: Array = []
var plans_checked: int = 0

func run() -> void:
	started_at=Time.get_ticks_msec()
	var workspace: String=ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(workspace):
		push_error("Duration QA requires workspace-isolated APPDATA")
		quit(2)
		return
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	check(maps.size()==40,"All forty authored maps are tested")
	validate_plans()
	for minutes in [10,20]:
		store=Store.new()
		store.save_path="user://duration-%d-progress.json" % minutes
		check(store.unlocked_units()==["archer","spear"],"Actual timed battle starts with the shipped two-class roster")
		check(store.army_level("archer")==1 and store.army_level("spear")==1,"No permanent levels are injected into timed battles")
		check(int(store.data.army.currency)==180,"No army funds are injected into timed battles")
		var attempts: Array=[]
		var result: Dictionary={}
		for strategy in range(3):
			result=play_timed_stage(maps[0],minutes,strategy)
			attempts.append(result)
			print("DURATION_BATTLE minutes=",minutes," strategy=",strategy," victory=",result.victory," elapsed=",result.seconds," hp=",result.hp," kills=",result.kills," refills=",result.refills)
			if bool(result.victory): break
		check(bool(result.victory),"Starter-only real combat reaches the %d-minute survival goal" % minutes)
		if bool(result.victory):
			check(absf(float(result.seconds)-float(minutes)*60.0)<.000001,"Real victory occurs at the selected pure-combat deadline")
			check(int(result.refills)>0,"Strong defenders keep receiving actual opponents within timed waves")
			check(int(result.kills)>0,"Timed completion includes actual attacks and enemy kills")
			opening_observations.append(result.opening)
		duration_results.append({"minutes":minutes,"attempts":attempts,"won":bool(result.victory)})
	if opening_observations.size()==2:
		check(opening_observations[0]==opening_observations[1],"The first two actual waves have identical combat, economy and spawn observations in both durations")
	var report: Dictionary={"checks":checks,"failures":failures,"plansChecked":plans_checked,"results":duration_results,"seconds":float(Time.get_ticks_msec()-started_at)/1000.0,"scope":"40 authored maps × 10/20 runtime schedules, actual starter Lv1 battles, public placement and finite earned gold, no difficulty/HP/wallet/levels/map wins injected."}
	var output: FileAccess=FileAccess.open("res://tests/qa_battle_duration.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("BATTLE_DURATION plans=",plans_checked," checks=",checks," failures=",failures.size()," seconds=",report.seconds)
	quit(0 if failures.is_empty() else 1)

func validate_plans() -> void:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	for stage in maps:
		var authored: String=JSON.stringify(stage)
		game.load_map(stage)
		var original: Array=game._build_wave_schedule()
		var original_count: int=game.total_waves
		for minutes in [10,20]:
			game.load_map(stage,minutes)
			plans_checked+=1
			var label: String=str(stage.id)+" "+str(minutes)+"min"
			var plan: Dictionary=game.battle_plan
			var preview: Dictionary=Battle.battle_mode_preview(stage,minutes)
			check(int(plan.minutes)==minutes and int(game.snapshot().battleMinutes)==minutes,label+" selects its runtime mode")
			check(int(plan.totalWaves)=={10:21,20:41}[minutes],label+" adds real later combat windows")
			check(preview.totalWaves==plan.totalWaves and preview.battleTargetSeconds==plan.targetSeconds,label+" briefing agrees with actual runtime plan")
			check(game.wave_spawn_schedule[0]==original[0] and game.wave_spawn_schedule[1]==original[1],label+" preserves the exact two opening rosters and source strengths")
			check(float(plan.waves[0].endSeconds)==20.0 and float(plan.waves[1].endSeconds)==45.0,label+" preserves the same short opening in every duration")
			check(int(plan.baseTotalWaves)==original_count,label+" retains its authored difficulty range")
			check(int(plan.waves[-1].entries.size())>=int(plan.waves[0].entries.size())*3,label+" later groups are materially larger than the opening")
			check(plan.waves[7].entries==original[-1],label+" reaches authored late-wave pressure by window eight")
			var clock: float=0.0
			for window in plan.waves:
				check(absf(float(window.startSeconds)-clock)<.000001 and float(window.endSeconds)>clock,label+" has contiguous positive-duration combat windows")
				clock=float(window.endSeconds)
				check(int(window.activeCap)<=36 and int(window.activeCap)>0,label+" has a finite active enemy cap")
				check(int(window.sourceWave)>=1 and int(window.sourceWave)<=original_count,label+" normalizes counterattacks and scheduled commanders")
				check(not window.entries.is_empty(),label+" has actual opponent groups")
				for entry in window.entries:
					check(int(entry.sourceWave)>=1 and int(entry.sourceWave)<=original_count,label+" retains baseline opponent strength")
			check(absf(clock-float(minutes)*60.0)<.000001,label+" ends exactly at the selected combat time")
			check(JSON.stringify(stage)==authored,label+" leaves the authored map data unchanged")
		game.load_map(stage)
		check(game.total_waves==original_count and game._build_wave_schedule()==original, str(stage.id)+" preserves the legacy test/load path")
	game.load_map(maps[0],7)
	check(game.battle_minutes==10,"Unsupported nonzero selections fall back to ten minutes")
	game.load_map(maps[0],5)
	check(game.battle_minutes==10,"Removed five-minute selections normalize to ten minutes")
	game.free()

func play_timed_stage(stage: Dictionary, minutes: int, strategy: int) -> Dictionary:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(9876+strategy*997)
	game.configure_roster(store.unit_catalog,store.unlocked_units(),store.data.army.levels)
	game.load_map(stage,minutes)
	check(game.gold==int(stage.initialGold),"Timed combat receives the actual authored initial wallet")
	prepare_geometry(game,strategy)
	var composition: Dictionary={}
	var opening: Array=[]
	var terminals: Array=[]
	game.battle_finished.connect(func(result: Dictionary): terminals.append(result))
	var steps: int=0
	var maximum_active: int=0
	var paused_checked: bool=false
	var last_deployment: float=-5.0
	deploy_units(game,composition,strategy)
	game.start_battle()
	while not game.finished and steps<MAX_STEPS:
		if game.between_waves:
			if game.wave<=2:
				opening.append({"wave":game.wave,"elapsed":game.elapsed,"kills":game.kills,"hp":game.snapshot().hp,"spawned":game.next_id-1-game.recruits,"gold":game.gold})
			var clock: float=game.elapsed
			var live_enemies: Array=game.enemies.duplicate(true)
			var shots: Array=game.projectiles.duplicate(true)
			var fighters: Array=game.units.duplicate(true)
			game.advance_simulation(5.0)
			game._process(.25)
			check(game.elapsed==clock and game.enemies==live_enemies and game.projectiles==shots and game.units==fighters,"Learning pause preserves actual live combat states and excludes study time")
			# This baseline skips learning rewards entirely, as the none campaign
			# already does. Only actual kills and wave supplies finance the army.
			deploy_units(game,composition,strategy)
			game.continue_wave()
		elif game.elapsed-last_deployment>=5.0-.000001:
			deploy_units(game,composition,strategy)
			last_deployment=game.elapsed
		if not paused_checked and game.wave>=3 and game.wave_time>=1.0:
			game.pause_battle()
			var clock: float=game.elapsed
			game.advance_simulation(7.0)
			game._process(.25)
			check(game.elapsed==clock,"Manual pause excludes elapsed combat time")
			game.pause_battle()
			paused_checked=true
		game.advance_simulation(STEP)
		steps+=1
		maximum_active=maxi(maximum_active,game.enemies.size())
	check(game.finished,"Real timed battle terminates within the simulation guard")
	check(terminals.size()==1,"One actual timed battle emits one terminal result")
	check(maximum_active<=36,"Actual combat never exceeds the enemy cap")
	for unit in game.units:
		check(int(unit.campaignLevel)==1 and str(unit.type) in ["archer","spear"],"Actual timed deployment uses only untrained unlocked starters")
	var before_gold: int=game.gold
	var before_kills: int=game.kills
	var clock: float=game.elapsed
	game.start_battle()
	game.continue_wave()
	game._complete_wave()
	game.advance_simulation(100.0)
	check(game.gold==before_gold and game.kills==before_kills and game.elapsed==clock and terminals.size()==1,"Repeated terminal calls cannot attack, accrue time or duplicate wave/kill rewards")
	var result: Dictionary={"minutes":minutes,"victory":game.victory,"seconds":game.elapsed,"wave":game.wave,"totalWaves":game.total_waves,"hp":game.snapshot().hp,"kills":game.kills,"refills":game.battle_refill_count,"gold":game.gold,"composition":composition,"maximumActive":maximum_active,"opening":opening,"strategy":strategy,"learningRewards":0,"steps":steps}
	if not game.victory: result["diagnostics"]=coverage_diagnostics(game)
	game.free()
	return result
