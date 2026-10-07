extends SceneTree

func _initialize() -> void:
	var face: Font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	for point_size in [6,12,16,18,20,24,26,30,36,44]:
		print("RUBY_METRICS ",point_size," ascent=",face.get_ascent(point_size)," descent=",face.get_descent(point_size)," height=",face.get_height(point_size)," kanaWidth=",face.get_string_size("きょう",HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x)
	quit()
