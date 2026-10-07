extends RefCounted
## Pure runtime plans. Stage geometry, traits and saved progression stay in the map.
const MINUTES: Array[int] = [10,20]
const OPENING_SECONDS: Array[float] = [20.0,25.0]
const REGULAR_WAVE_SECONDS: float = 30.0
const ACTIVE_ENEMY_CAP: int = 36
const LATE_RAMP_WAVE: int = 8

static func normalize_minutes(minutes: int) -> int:
	return minutes if minutes in MINUTES else 10

static func preview(_map_config: Dictionary, minutes: int) -> Dictionary:
	var selected: int=normalize_minutes(minutes)
	var target: float=float(selected)*60.0
	var later_waves: int=ceili((target-OPENING_SECONDS[0]-OPENING_SECONDS[1])/REGULAR_WAVE_SECONDS)
	return {"battleMinutes":selected,"battleTargetSeconds":target,"totalWaves":2+later_waves}

static func build(map_config: Dictionary, base_schedule: Array, minutes: int) -> Dictionary:
	var summary: Dictionary=preview(map_config,minutes)
	var wave_count: int=int(summary.totalWaves)
	var target: float=float(summary.battleTargetSeconds)
	var later_seconds: float=(target-OPENING_SECONDS[0]-OPENING_SECONDS[1])/float(wave_count-2)
	var waves: Array=[]
	var clock: float=0.0
	var base_count: int=base_schedule.size()
	for index in range(wave_count):
		var base_index: int=mini(index,maxi(0,base_count-1))
		if index>=2:
			var ramp: float=clampf(float(index-2)/float(LATE_RAMP_WAVE-3),0.0,1.0)
			base_index=mini(maxi(0,base_count-1),2+roundi(float(maxi(0,base_count-3))*ramp))
		var duration: float=OPENING_SECONDS[index] if index<2 else later_seconds
		var end: float=target if index==wave_count-1 else clock+duration
		var entries: Array=base_schedule[base_index].duplicate(true) if base_count>0 else []
		var cap: int=8 if index==0 else 12 if index==1 else roundi(lerpf(16.0,float(ACTIVE_ENEMY_CAP),clampf(float(index-2)/float(LATE_RAMP_WAVE-3),0.0,1.0)))
		waves.append({"startSeconds":clock,"endSeconds":end,"baseIndex":base_index,"sourceWave":base_index+1,"entries":entries,"activeCap":cap,"refillCount":clampi(ceili(float(entries.size())*.18),1,8),"refillThreshold":clampi(ceili(float(entries.size())*.25),2,12)})
		clock=end
	return {"minutes":int(summary.battleMinutes),"targetSeconds":target,"totalWaves":wave_count,"baseTotalWaves":base_count,"activeCap":ACTIVE_ENEMY_CAP,"waves":waves}
