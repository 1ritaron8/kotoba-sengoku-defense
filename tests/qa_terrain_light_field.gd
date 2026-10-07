extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var field = load("res://native/terrain_light_field.gd").new()
	var synthetic: Image = Image.create(96,64,false,Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(96):
			synthetic.set_pixel(x,y,Color(.12,.15,.12) if x<48 else Color(.66,.61,.48))
	field.configure({"background":"fixture://shadow-and-sun"},synthetic)
	var shade: Dictionary = field.sample(Vector2(.2,.5))
	var sun: Dictionary = field.sample(Vector2(.8,.5))
	check(shade.exposure<.85 and sun.exposure>1.05,"Moving from broad shade onto a sunny road changes exposure")
	check(synthetic.get_size()==Vector2i(96,64),"Sampling never resizes or edits the authored source")
	var largest_jump: float = 0.0
	var previous: float = float(field.sample(Vector2(0,.5)).exposure)
	for x in range(501):
		var value: Dictionary = field.sample(Vector2(float(x)/500.0,.5))
		largest_jump = maxf(largest_jump,absf(float(value.exposure)-previous))
		previous = float(value.exposure)
		check(is_finite(value.exposure) and value.exposure>=.66 and value.exposure<=1.16,"Moving exposure stays finite and bounded")
		var tint: Color = value.tint
		check(minf(tint.r,minf(tint.g,tint.b))>=.919 and maxf(tint.r,maxf(tint.g,tint.b))<=1.081,"Reflected colour preserves faction identity")
	check(largest_jump<.025,"Bilinear neighbourhood sampling does not flash at a shadow edge")
	for invalid in [Vector2(NAN,0),Vector2(INF,0),Vector2(0,-INF)]:
		check(is_equal_approx(field.sample(invalid).exposure,1.0),"Invalid positions safely return neutral illumination")
	check(field.sample(Vector2(-2,-1))==field.sample(Vector2.ZERO) and field.sample(Vector2(3,4))==field.sample(Vector2.ONE),"Off-map samples clamp to the photograph edge")
	field.configure({"background":"res://assets/no-such-light-field.png"})
	check(not field.diagnostics().available and is_equal_approx(field.sample(Vector2(.5,.5)).exposure,1.0),"Missing image falls back without retaining the previous map's light")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var observations: Array = []
	for stage in maps:
		field.configure(stage)
		check(field.diagnostics().available,"Real authored photograph produces a local light field "+str(stage.id))
		var min_exposure: float = INF
		var max_exposure: float = -INF
		for y in range(10):
			for x in range(10):
				var value: Dictionary = field.sample(Vector2((float(x)+.5)/10,(float(y)+.5)/10))
				min_exposure = minf(min_exposure,float(value.exposure))
				max_exposure = maxf(max_exposure,float(value.exposure))
				check(is_finite(value.exposure) and value.exposure>=.66 and value.exposure<=1.16,"Actual map sample stays within readable bounds "+str(stage.id))
		var first: Dictionary = field.sample(Vector2(.4,.6))
		field.configure(stage)
		check(first==field.sample(Vector2(.4,.6)),"Cached battlefield illumination is deterministic "+str(stage.id))
		check(max_exposure-min_exposure>.03,"Authored scene has real spatial brightness variation "+str(stage.id))
		observations.append({"stageId":stage.id,"minExposure":min_exposure,"maxExposure":max_exposure,"field":field.diagnostics()})
	check(field.diagnostics().cachedFields==40 and field.diagnostics().cachedGridPixels==61440,"All forty maps retain only small grids rather than full-size image copies")
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"shadowEdgeMaximumStep":largest_jump,"scope":"CPU samples of all 40 real battlefield photographs; synthetic moving shadow edge, invalid/missing data, cached fields. Actual actor uniform changes are verified separately on GPU."}
	var file = FileAccess.open("user://qa_terrain_light_field.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("TERRAIN_LIGHT_FIELD ",checks," checks / ",failures.size()," failures; largest edge step=",largest_jump)
	quit(0 if failures.is_empty() else 1)
