extends SceneTree

const Weather = preload("res://native/battlefield_weather.gd")

func _init() -> void:
	var geography: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
	assert(geography.stages.size() == 40)
	var evidence: Array[int] = []
	for record in geography.stages:
		var profile: Dictionary = record.presentationWeather
		assert(profile.isArtisticPresentation)
		assert(profile.snowCoverage == 0)
		assert(not record.weather.isContemporaneousObservation)
		assert(record.missionDesign.routePrecision == "qualitative_design_only")
		if record.weatherKnown:
			evidence.append(int(record.stageNumber))
		var stage: Dictionary = {"id":record.stageId,"historicalBattlefield":{"presentationWeather":profile}}
		var scene: Node3D = Node3D.new()
		var counts: Dictionary = Weather.build_ground_details(scene,stage,_flat_point,_allow)
		if profile.wetness > .5:
			assert(counts.wet_soil > 0 and counts.puddles > 0)
		if profile.leafCoverage > .1:
			assert(counts.leaves > 0)
		if profile.frostCoverage > .1:
			assert(counts.frost > 0)
		assert(scene.get_child_count() <= 4)
		for child in scene.get_children():
			assert(child.layers == 1)
			assert(child.multimesh.instance_count <= 155)
		scene.free()
	assert(evidence == [2,26,28,29])
	var wet: Dictionary = {"id":"blocked","historicalBattlefield":{"presentationWeather":{"wetness":1,"leafCoverage":1,"frostCoverage":1}}}
	var blocked: Node3D = Node3D.new()
	var blocked_counts: Dictionary = Weather.build_ground_details(blocked,wet,_flat_point,_deny)
	assert(blocked.get_child_count() == 0)
	assert(blocked_counts.puddles == 0)
	blocked.free()
	var slope: Node3D = Node3D.new()
	var slope_counts: Dictionary = Weather.build_ground_details(slope,wet,_steep_point,_allow)
	assert(slope_counts.puddles == 0)
	slope.free()
	assert(geography.stages[9].season.key == "autumn")
	assert(geography.stages[24].season.key == "late_autumn_early_winter")
	assert(geography.stages[37].season.key == "early_summer")
	print("PASS: 40 weather profiles; historical evidence scopes; land-mask exclusion; low-ground puddles; seasonal details bounded to four batches.")
	quit()

func _flat_point(p: Vector2) -> Vector3:
	return Vector3((p.x-.5)*18.5,0,(p.y-.5)*12)

func _steep_point(p: Vector2) -> Vector3:
	return Vector3((p.x-.5)*18.5,p.x*10,(p.y-.5)*12)

func _allow(_p: Vector2) -> bool:
	return true

func _deny(_p: Vector2) -> bool:
	return false
