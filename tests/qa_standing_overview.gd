extends SceneTree

const Portrait = preload("res://native/barracks_portrait.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const NAMES = ["궁병","창병","사무라이","철포병","나기나타병","승병","기마 무장","닌자"]
var portraits: Array = []
var checks: int = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size = Vector2i(1440,900)
	root.title = "말의 전장 · 원형 병력 대기 동작 검수"
	var background = ColorRect.new()
	background.color = Color("171813")
	background.size = Vector2(1440,900)
	root.add_child(background)
	var font: Font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	for index in range(TYPES.size()):
		var panel = Control.new()
		panel.position = Vector2((index%4)*360,(index/4)*450)
		panel.size = Vector2(360,450)
		root.add_child(panel)
		var portrait = Portrait.new()
		portrait.position = Vector2(12,8)
		portrait.size = Vector2(336,400)
		portrait.configure(TYPES[index],0,true)
		panel.add_child(portrait)
		portraits.append(portrait)
		var name_label = Label.new()
		name_label.text = NAMES[index]
		name_label.position = Vector2(12,404)
		name_label.size = Vector2(336,40)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font",font)
		name_label.add_theme_font_size_override("font_size",24)
		name_label.add_theme_color_override("font_color",Color("d6bd86"))
		panel.add_child(name_label)
	await create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://dist/preview-standing-all-units.png")==OK,"Actual eight-class GPU contact sheet saves")
	var initial_hashes: Array = []
	var transforms: Array = []
	for index in range(portraits.size()):
		var portrait: Control = portraits[index]
		var data: Dictionary = portrait.diagnostics()
		check(data.ready and data.active and data.unitId==TYPES[index],TYPES[index]+": its own original artwork is active")
		initial_hashes.append(hash(root.get_texture().get_image().get_region(Rect2i(portrait.get_global_rect())).get_data()))
		transforms.append(portrait.output.get_global_transform())
		var fit: Vector2 = data.drawRect.size/data.canvasSize
		for bounds in data.registeredBounds:
			var shown: Rect2 = Rect2(data.drawRect.position+(bounds.position-data.canvasOrigin)*fit,bounds.size*fit)
			check(Rect2(Vector2.ZERO,portrait.size).grow(1).encloses(shown),TYPES[index]+": full registered pose stays inside its portrait")
	await create_timer(.8).timeout
	await RenderingServer.frame_post_draw
	var actual: Image = root.get_texture().get_image()
	for index in range(portraits.size()):
		var portrait: Control = portraits[index]
		check(initial_hashes[index]!=hash(actual.get_region(Rect2i(portrait.get_global_rect())).get_data()),TYPES[index]+": natural playback visibly changes actual rendered pose pixels")
		check(transforms[index].is_equal_approx(portrait.output.get_global_transform()),TYPES[index]+": canvas stays fixed")
	var report = {"checks":checks,"failures":failures,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Actual production standing-portrait renderer, all eight classes, original raster poses and stable canvas"}
	var file = FileAccess.open("res://tests/qa_standing_overview.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("STANDING_GPU_OVERVIEW ",JSON.stringify(report))
	for child in root.get_children(): child.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
