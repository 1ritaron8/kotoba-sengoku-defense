extends SceneTree
## This verifies authored raster poses, not new 3D geometry. Run -- --partial
## only while the four support portraits are still being authored.
const Portrait = preload("res://native/barracks_portrait.gd")
const TYPES = ["archer","spear","samurai","commander","gunner","naginata","monk","ninja"]
var checks: int = 0
var failures: Array = []
var observations: Array = []
var images: Dictionary = {}
var complete: bool = true

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("AUTHORED PORTRAIT QA " + message)

func settle(frames: int = 3) -> void:
	for index in range(frames):
		await process_frame

func decoded_image(texture: Texture2D) -> Image:
	var path: String = texture.resource_path
	if images.has(path):
		return images[path]
	var image: Image = texture.get_image()
	if image!=null and not image.is_empty():
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		images[path] = image
	return image

func pose_observation(image: Image, region: Rect2i) -> Dictionary:
	var crop: Image = image.get_region(region)
	var rgba: PackedByteArray = crop.get_data()
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(region.size.x*region.size.y)
	var opaque: int = 0
	var minimum: Vector2i = region.size
	var maximum: Vector2i = Vector2i(-1,-1)
	for y in range(region.size.y):
		for x in range(region.size.x):
			var pixel: int = y*region.size.x+x
			if rgba[pixel*4+3]>=12:
				opaque += 1
				minimum = Vector2i(mini(minimum.x,x),mini(minimum.y,y))
				maximum = Vector2i(maxi(maximum.x,x),maxi(maximum.y,y))
				mask[pixel] = 255
			else:
				# Invisible RGB data cannot make identical visible poses look unique.
				rgba[pixel*4] = 0
				rgba[pixel*4+1] = 0
				rgba[pixel*4+2] = 0
				rgba[pixel*4+3] = 0
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(rgba)
	var visible_hash: String = hash.finish().hex_encode()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(mask)
	return {"visibleHash":visible_hash,"silhouetteHash":hash.finish().hex_encode(),"opaquePixels":opaque,"minimum":minimum,"maximum":maximum}

func expected_source(id: String, state: Dictionary) -> bool:
	var path: String = str(state.get("manifestPath",""))
	if not FileAccess.file_exists(path): return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("sprites",{}).has(id): return false
	var entry = data.sprites[id]
	var actual_path: String = str(entry.get("path","")) if entry is Dictionary else str(entry)
	var idle: Dictionary = data.get("animations",{}).get("idle",{})
	var actual_row: int = int(entry.get("row",idle.get("row",0))) if entry is Dictionary else int(idle.get("row",0))
	return actual_path==str(state.get("sourcePath","")) and actual_row==int(state.get("row",-1))

func check_pose_binding(portrait: Control, id: String) -> void:
	var state: Dictionary = portrait.diagnostics()
	var material: ShaderMaterial = portrait.output.material
	var size: Vector2 = portrait.texture.get_size()
	var a: Rect2 = state.frameRect
	var b: Rect2 = state.nextFrameRect
	check(material!=null and material.get_shader_parameter("frame_a")==Vector4(a.position.x/size.x,a.position.y/size.y,a.size.x/size.x,a.size.y/size.y),id+": actual canvas material samples the displayed pose region")
	check(material!=null and material.get_shader_parameter("frame_b")==Vector4(b.position.x/size.x,b.position.y/size.y,b.size.x/size.x,b.size.y/size.y),id+": actual canvas material samples the following pose region")
	check(material!=null and is_equal_approx(float(material.get_shader_parameter("pose_blend")),float(state.blend)),id+": live blend value is bound to the rendered material")
	check(material.get_shader_parameter("registration_a")==state.registration[int(state.frame)] and material.get_shader_parameter("registration_b")==state.registration[int(state.nextFrame)],id+": both rendered poses use their actual foot registration")
	check(material.get_shader_parameter("canvas_origin")==Vector2(state.canvasOrigin)/Vector2(state.cellSize) and material.get_shader_parameter("canvas_span")==Vector2(state.canvasSize)/Vector2(state.cellSize),id+": the rendered canvas includes the registered pose padding")

func run() -> void:
	complete = not OS.get_cmdline_user_args().has("--partial")
	var types: Array = TYPES if complete else TYPES.slice(0,4)
	root.size = Vector2i(1280,800)
	if complete:
		for path in ["res://assets/units-standing/core.json","res://assets/units-standing/support.json"]:
			check(FileAccess.file_exists(path),path+": actual raw source manifest is available")
	var panel: Control = Control.new()
	panel.position = Vector2(90,75)
	panel.size = Vector2(420,580)
	root.add_child(panel)
	var portrait = Portrait.new()
	portrait.size = Vector2(320,410)
	portrait.configure("archer",0,true)
	panel.add_child(portrait)
	await settle()
	var identities: Dictionary = {}
	for id in types:
		portrait.configure(id,0,true)
		await settle()
		var state: Dictionary = portrait.diagnostics()
		check(state.unitId==id and bool(state.ready),id+": selected class loads its own authored portrait")
		check(str(state.sourceKind)=="authored-idle-sheet" and expected_source(id,state),id+": actual bound source matches this class's manifest entry")
		if complete: check(str(state.manifestPath).begins_with("res://assets/units-standing/"),id+": finished standing art takes priority over older field sprites")
		check(bool(state.active) and portrait.is_processing() and portrait.output.visible,id+": visible portrait is actively rendered and animated")
		if not bool(state.ready) or portrait.texture==null:
			continue
		check(int(state.frames)==6 and float(state.fps)>0,id+": idle sequence contains six authored frames")
		check(portrait.output.texture==portrait.texture and portrait.output.texture.resource_path==state.sourcePath,id+": actual TextureRect receives the selected source sheet")
		var identity: String = str(state.sourcePath)+":"+str(state.row)
		check(not identities.has(identity),id+": sheet row is not borrowed from another class")
		identities[identity] = id
		var sheet_bounds: Rect2 = Rect2(Vector2.ZERO,portrait.texture.get_size())
		check(sheet_bounds.encloses(state.frameRect) and sheet_bounds.encloses(state.nextFrameRect),id+": both active sampling regions remain inside the real sheet")
		var cell: Vector2 = state.cellSize
		check(is_equal_approx(cell.x,roundf(cell.x)) and is_equal_approx(cell.y,roundf(cell.y)),id+": sprite cells have exact integer pixel boundaries")
		check(Vector2(state.baseline).x>=0 and Vector2(state.baseline).x<cell.x and Vector2(state.baseline).y>=0 and Vector2(state.baseline).y<cell.y,id+": fixed foot anchor lies inside its own cell")
		var draw: Rect2 = state.drawRect
		var used: Rect2 = state.visibleBounds
		var canvas: Vector2 = state.canvasSize
		var canvas_origin: Vector2 = state.canvasOrigin
		var fit: Vector2 = draw.size/canvas
		var visible: Rect2 = Rect2(draw.position+(used.position-canvas_origin)*fit,used.size*fit)
		check(Rect2(Vector2.ZERO,portrait.size).grow(1).encloses(visible),id+": visible body fits in the selected portrait panel")
		check(state.frameAnchors.size()==6 and state.registration.size()==6 and state.registeredBounds.size()==6,id+": all six authored poses have source-foot registration")
		for index in range(state.frameAnchors.size()):
			var source_foot: Vector2 = state.frameAnchors[index]
			var registered_foot: Vector2 = source_foot-Vector2(state.registration[index])*cell
			var displayed_foot: Vector2 = draw.position+(registered_foot-canvas_origin)*fit
			check(displayed_foot.distance_to(state.footPosition)<.001,id+": pose %d's actual source foot maps to the fixed screen contact" % index)
			check(Rect2(canvas_origin,canvas).encloses(state.registeredBounds[index]),id+": registered pose %d fits within the padded sampling canvas" % index)
		check_pose_binding(portrait,id)
		var image: Image = decoded_image(portrait.texture)
		check(image!=null and not image.is_empty(),id+": actual source pixels can be decoded for pose verification")
		var frame_data: Array = []
		var visible_hashes: Dictionary = {}
		var silhouette_hashes: Dictionary = {}
		if image!=null and not image.is_empty():
			for index in range(6):
				var region: Rect2i = Rect2i(roundi(index*cell.x),roundi(int(state.row)*cell.y),roundi(cell.x),roundi(cell.y))
				check(Rect2i(Vector2i.ZERO,image.get_size()).encloses(region),id+": pose %d crop remains inside source pixels" % index)
				var pose: Dictionary = pose_observation(image,region)
				check(int(pose.opaquePixels)>50 and pose.minimum.x>0 and pose.minimum.y>0 and pose.maximum.x<region.size.x-1 and pose.maximum.y<region.size.y-1,id+": pose %d has a nonempty body with transparent margins" % index)
				visible_hashes[pose.visibleHash] = true
				silhouette_hashes[pose.silhouetteHash] = true
				frame_data.append(pose)
			check(visible_hashes.size()==6,id+": all six visible poses are distinct after ignoring transparent RGB")
			check(silhouette_hashes.size()>1,id+": silhouette changes across idle poses, not only pixel colouring")
		var clock: float = float(state.animationClock)
		var initial_frame: int = int(state.frame)
		var visited: Dictionary = {}
		visited[initial_frame] = true
		for tick in range(7):
			await create_timer(1.0/float(state.fps)+.035).timeout
			visited[int(portrait.diagnostics().frame)] = true
		check(float(portrait.diagnostics().animationClock)>clock and visited.size()>=5,id+": real processing traverses the six-frame idle cycle")
		check_pose_binding(portrait,id)
		check(portrait.diagnostics().footPosition==state.footPosition and portrait.diagnostics().drawRect==state.drawRect,id+": idle animation keeps the canvas and foot anchor fixed")
		portrait.configure(id,2,false)
		await settle()
		check(portrait.diagnostics().evolution==2 and portrait.diagnostics().sourcePath==state.sourcePath and not bool(portrait.diagnostics().visualEvolution) and portrait.output.modulate!=Color.WHITE,id+": locked/evolution metadata keeps the correct class art without inventing alternate forms")
		observations.append({"unit":id,"source":state.sourcePath,"manifest":state.manifestPath,"row":state.row,"cellSize":cell,"frames":frame_data,"visitedFrames":visited.keys(),"visibleBody":visible})
	check(identities.size()==types.size(),"Every tested class has a unique authored source row")
	portrait.configure("samurai",1,true)
	await settle()
	var frozen: Dictionary = portrait.diagnostics()
	panel.hide()
	await settle()
	await create_timer(.3).timeout
	check(not bool(portrait.diagnostics().active) and not portrait.is_processing() and portrait.diagnostics().animationClock==frozen.animationClock and portrait.diagnostics().frame==frozen.frame,"Hidden parent pauses the actual portrait clock and pose")
	panel.show()
	await create_timer(.25).timeout
	check(bool(portrait.diagnostics().active) and float(portrait.diagnostics().animationClock)>float(frozen.animationClock),"Returning to the portrait resumes the same animation")
	frozen = portrait.diagnostics()
	paused = true
	await create_timer(.25).timeout
	check(portrait.diagnostics().animationClock==frozen.animationClock and portrait.diagnostics().frame==frozen.frame,"SceneTree pause freezes actual authored pose playback")
	paused = false
	await create_timer(.25).timeout
	check(float(portrait.diagnostics().animationClock)>float(frozen.animationClock),"Unpausing resumes authored pose playback")
	portrait.configure("__missing_portrait__",0,true)
	await settle()
	check(not bool(portrait.diagnostics().ready) and not bool(portrait.diagnostics().active) and portrait.texture==null and portrait.diagnostics().sourcePath=="" and not portrait.output.visible,"Unknown class displays no borrowed portrait or stale previous-class texture")
	portrait.configure("spear",0,true)
	await settle()
	check(bool(portrait.diagnostics().ready) and expected_source("spear",portrait.diagnostics()) and portrait.texture!=null and portrait.output.visible,"Reconfiguring after a missing class restores the selected class's real source")
	var report = {"checks":checks,"failures":failures,"complete":complete,"classes":observations,"scope":"Actual authored raster pose binding, pixel distinction, crop containment and playback lifecycle. Headless checks data and bindings; root separately verifies the visible canvas shader on GPU."}
	var file: FileAccess = FileAccess.open("user://qa_authored_portraits.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("AUTHORED_PORTRAITS_QA ",JSON.stringify({"checks":checks,"failures":failures,"complete":complete,"classes":observations.size(),"report":ProjectSettings.globalize_path("user://qa_authored_portraits.json")}))
	panel.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
