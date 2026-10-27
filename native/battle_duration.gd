extends RefCounted
## Finite campaign attack cycles. Elapsed time is a record, never a deadline.
## Keep the old minutes argument only for existing callers and stored UI state.
const CYCLE_MODE: int = 0
const FIXED_MINUTES: int = CYCLE_MODE
const MINUTES: Array[int] = [CYCLE_MODE]
# The global tempo keeps finite authored cycles while making arrivals denser.
# Living enemy counts never delay a scheduled arrival.
const ARRIVAL_COUNT_MULTIPLIER: float = 1.25
const ARRIVAL_INTERVAL_MULTIPLIER: float = .8
# Stage01 needs sustained early pressure without introducing later troops.
const STAGE01_COUNTS: Array[int] = [24,28,32,36]
const STAGE01_INTERVALS: Array[float] = [.90,.82,.74,.66]
# Stage02 adds an attack cycle and a capture objective.
const STAGE02_COUNTS: Array[int] = [24,26,28,30,32]
const STAGE02_INTERVALS: Array[float] = [.90,.86,.82,.78,.74]

static func normalize_minutes(_minutes: int) -> int:
	return CYCLE_MODE

static func progression_for(stage_number: int) -> Dictionary:
	var stage: int=clampi(stage_number,1,40)
	var cycles: int=4+ceili(float(stage-1)*12.0/39.0)
	# Every stage adds four finite main-line soldiers even when its cycle count
	# is unchanged. These are authored totals, never concurrent actor limits.
	var extra: int=(stage-1)*4
	var counts: Array[int]=[]
	var total: int=0
	for index in range(cycles):
		var count: int=12+index*2+extra/cycles+(1 if index<extra%cycles else 0)
		counts.append(count)
		total+=count
	var tier: int=(stage-1)/10
	return {"stageNumber":stage,"totalWaves":cycles,"cycleEnemyCounts":counts,"enemyBudget":total,"learningTier":["basic","beginner","intermediate","advanced"][tier],"newWordCount":[15,20,25,30][tier]}

static func preview(map_config: Dictionary, _minutes: int = CYCLE_MODE) -> Dictionary:
	var result: Dictionary=progression_for(int(map_config.get("stageNumber",1)))
	if str(map_config.get("id",""))=="basic-forest" and int(map_config.get("stageNumber",1))==1:
		result["cycleEnemyCounts"]=STAGE01_COUNTS.duplicate()
		result["totalWaves"]=STAGE01_COUNTS.size()
		var opening_budget: int=0
		for count in STAGE01_COUNTS: opening_budget+=count
		result["enemyBudget"]=opening_budget
	elif str(map_config.get("id",""))=="basic-farm" and int(map_config.get("stageNumber",0))==2 and not map_config.get("advanceMission",{}).is_empty():
		result["cycleEnemyCounts"]=STAGE02_COUNTS.duplicate()
		result["totalWaves"]=STAGE02_COUNTS.size()
		var advance_budget: int=0
		for count in STAGE02_COUNTS: advance_budget+=count
		result["enemyBudget"]=advance_budget
	var arrivals: Array[int]=[]
	var arrival_total: int=0
	for count in result.cycleEnemyCounts:
		var arrival_count: int=ceili(float(count)*ARRIVAL_COUNT_MULTIPLIER)
		arrivals.append(arrival_count)
		arrival_total+=arrival_count
	result["cycleEnemyCounts"]=arrivals
	result["enemyBudget"]=arrival_total
	result.merge({"battleMode":"cycles","battleMinutes":CYCLE_MODE,"battleTargetSeconds":0.0,"hasTimeLimit":false},true)
	return result

static func build(map_config: Dictionary, base_schedule: Array, _minutes: int = CYCLE_MODE) -> Dictionary:
	var summary: Dictionary=preview(map_config)
	var wave_count: int=int(summary.totalWaves)
	var stage: int=int(summary.stageNumber)
	var stage01: bool=str(map_config.get("id",""))=="basic-forest" and stage==1
	var stage02: bool=str(map_config.get("id",""))=="basic-farm" and stage==2 and not map_config.get("advanceMission",{}).is_empty()
	var waves: Array=[]
	for index in range(wave_count):
		var source: Array=base_schedule[mini(index,base_schedule.size()-1)] if not base_schedule.is_empty() else []
		var entries: Array=[]
		var count: int=int(summary.cycleEnemyCounts[index])
		for member in range(count):
			# Sample the existing authored recipe across the whole source batch,
			# retaining mixed rosters when a cycle has a smaller finite budget.
			var source_index: int=mini(source.size()-1,floori(float(member)*float(source.size())/float(count)))
			var entry: Dictionary=source[source_index].duplicate(true) if not source.is_empty() else {"kind":"raider"}
			entry["sourceWave"]=index+1
			entries.append(entry)
		# Preserve an orderly arrival cadence. Later difficulty comes from the
		# finite roster and its existing kinds, not a new speed multiplier.
		var interval: float=1.20 if index==0 else 1.10 if index==1 else lerpf(1.0,.72,float(index-2)/maxf(1.0,float(wave_count-3)))
		if stage01: interval=STAGE01_INTERVALS[index]
		if stage02: interval=STAGE02_INTERVALS[index]
		interval*=ARRIVAL_INTERVAL_MULTIPLIER
		waves.append({"cycle":index+1,"sourceWave":index+1,"entries":entries,"spawnInterval":interval,"enemyCount":count})
	return {"mode":"cycles","minutes":CYCLE_MODE,"targetSeconds":0.0,"hasTimeLimit":false,"totalWaves":wave_count,"baseTotalWaves":wave_count,"enemyBudget":int(summary.enemyBudget),"enemyBudgetScope":"main_line_only; authored guards, raids and commanders are finite additions","waves":waves}
