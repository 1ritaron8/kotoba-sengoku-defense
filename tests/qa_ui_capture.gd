extends SceneTree

var screen: Control

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var output = "res://dist/preview-" + name + ".png"
	assert(root.get_texture().get_image().save_png(output)==OK)
	print("UI CAPTURE: ",name)

func run() -> void:
	screen = load("res://native/front_end.gd").new()
	screen.font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	screen.maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	screen.progress = load("res://native/progress.gd").new()
	screen.progress.read_save()
	screen.theme = Theme.new()
	screen.theme.default_font = screen.font
	root.add_child(screen)
	screen.show_home()
	await capture("home")
	screen.show_catalog(1)
	await capture("stages")
	screen.view = "settings"
	screen._rebuild()
	await capture("settings")
	screen.queue_free()
	await process_frame
	quit(0)
