extends SceneTree
## GPU comparison of the untouched source, unlocked preview and locked preview.
const Preview = preload("res://native/barracks_portrait.gd")
const IDS: Array[String] = ["archer","spear","samurai","commander","gunner","naginata","monk","ninja"]
var failures: Array[String] = []
var observations: Array = []
var checks: int = 0

func _initialize() -> void:
	root.position = Vector2i(-16000,-16000)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func luminance(value: Color) -> float:
	return value.r*.2126+value.g*.7152+value.b*.0722

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var safe_root: String = ProjectSettings.globalize_path("res://tests/profiles/barracks-palette/").replace("\\","/").to_lower()
	if not profile.begins_with(safe_root) or DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size = Vector2i(32,32)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920,930)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for state in range(3):
		for index in range(IDS.size()):
			var preview: Control = Preview.new()
			preview.position = Vector2(index*240,state*310)
			preview.size = Vector2(240,310)
			preview.configure(IDS[index],0,state!=2)
			viewport.add_child(preview)
			if state==0:
				preview.output.material.set_shader_parameter("friendly_blue_armor",false)
				preview.output.material.set_shader_parameter("portrait_gamma",1.0)
			check(preview.texture.resource_path==str(Preview.source_for(IDS[index]).path),"Original standing sheet retained: "+IDS[index])
			check(not preview.is_processing(),"Standing pose remains static: "+IDS[index])
	for unused in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	check(image.save_png("user://barracks-palette-gpu.png")==OK,"Comparison capture saved")
	for index in range(IDS.size()):
		var original_sum: float = 0.0
		var unlocked_sum: float = 0.0
		var locked_sum: float = 0.0
		var pixels: int = 0
		var red_pixels: int = 0
		var blue_pixels: int = 0
		var warm_pixels: int = 0
		var warm_error: float = 0.0
		var alpha_error: float = 0.0
		for y in range(310):
			for x in range(240):
				var original: Color = image.get_pixel(index*240+x,y)
				var unlocked: Color = image.get_pixel(index*240+x,310+y)
				var locked: Color = image.get_pixel(index*240+x,620+y)
				alpha_error = maxf(alpha_error,absf(original.a-unlocked.a))
				if original.a<.95: continue
				pixels += 1
				original_sum += luminance(original)
				unlocked_sum += luminance(unlocked)
				locked_sum += luminance(locked)
				if IDS[index]=="naginata":
					if original.r>original.g+.10 and original.r>original.b+.10 and (original.g-original.b)/maxf(original.r,.001)<.08:
						red_pixels += 1
						if unlocked.b>unlocked.r+.08: blue_pixels += 1
					if original.r>original.g+.08 and original.g>original.b+.08 and (original.g-original.b)/maxf(original.r,.001)>.22:
						warm_pixels += 1
						warm_error += absf(unlocked.r-pow(original.r,.8))+absf(unlocked.g-pow(original.g,.8))+absf(unlocked.b-pow(original.b,.8))
		check(pixels>500,"Actual opaque portrait pixels: "+IDS[index])
		check(unlocked_sum>original_sum*1.08,"Unlocked preview visibly brighter: "+IDS[index])
		check(locked_sum<unlocked_sum*.75,"Locked preview remains distinct: "+IDS[index])
		check(alpha_error<.01,"Authored silhouette/weapon alpha preserved: "+IDS[index])
		if IDS[index]=="naginata":
			check(red_pixels>100 and blue_pixels>red_pixels*.90,"Red armor changes to allied blue")
			check(warm_pixels>100 and warm_error/maxi(warm_pixels,1)<.035,"Skin, wood and brass retain their warm pigment")
		observations.append({"unit":IDS[index],"sourceMean":original_sum/maxi(pixels,1),"unlockedMean":unlocked_sum/maxi(pixels,1),"lockedMean":locked_sum/maxi(pixels,1),"alphaError":alpha_error,"redArmorPixels":red_pixels,"blueArmorPixels":blue_pixels,"warmPixels":warm_pixels,"warmError":warm_error/maxi(warm_pixels,1)})
	var file: FileAccess = FileAccess.open("user://barracks-palette-gpu.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	print("BARRACKS_PALETTE checks=%d failures=%d capture=%s" % [checks,failures.size(),ProjectSettings.globalize_path("user://barracks-palette-gpu.png")])
	viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
