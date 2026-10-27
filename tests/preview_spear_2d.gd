extends SceneTree
## Independent user-review surface. No product scenes, saves, cameras or 3D assets.

const DEFAULT_ATLAS: String = "res://assets/characters/spear-2d-pilot-01/spear-ne-walk-atlas.png"
const EVIDENCE: String = "res://tests/profiles/spear-2d-pilot-01/"
const FRAME_COUNT: int = 8
const FPS: float = 10.0
var options: Dictionary = {}
var metadata: Dictionary = {}
var atlas: ImageTexture
var source_image: Image
var cell: Vector2
var frame_records: Array = []
var actors: Array[Sprite2D] = []
var frame_label: Label
var elapsed: float = 0.0
var running: bool = false
var capture_pending: bool = false
var current_frame: int = 0
var body_reference: float = 1.0
var body_measured: bool = false
var captures: Array = []
var failures: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var pair: PackedStringArray = argument.substr(2).split("=",true,1)
			options[pair[0]] = pair[1] if pair.size()>1 else "true"
	call_deferred("run")

func _process(delta: float) -> bool:
	if running and not capture_pending:
		elapsed += delta
		set_animation_frame(int(floor(elapsed*FPS))%FRAME_COUNT)
	return false

func _numbers(value: Variant, length: int) -> bool:
	if not value is Array or value.size()!=length: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

func _label(parent: Node, text_value: String, point: Vector2, width: float, text_size: int = 22) -> Label:
	var label: Label = Label.new()
	label.position = point
	label.size = Vector2(width,70)
	label.text = text_value
	label.add_theme_font_size_override("font_size",text_size)
	label.add_theme_color_override("font_color",Color("eef0ed"))
	parent.add_child(label)
	return label

func _output_path(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path).replace("\\","/")
	var allowed: String = ProjectSettings.globalize_path(EVIDENCE).replace("\\","/")
	return absolute.simplify_path().begins_with(allowed)

func _save_report() -> void:
	var path: String = str(options.get("report",EVIDENCE+"preview_report.json"))
	if not _output_path(path):
		push_error("Preview report must stay in "+EVIDENCE)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output==null: return
	output.store_string(JSON.stringify({"atlas":str(options.get("atlas",DEFAULT_ATLAS)),"atlasPixels":[source_image.get_width(),source_image.get_height()] if source_image!=null else [],"grid":[4,2],"frameCount":FRAME_COUNT,"animationFps":FPS,"loopSeconds":.8,"displayServer":DisplayServer.get_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"bodyReferencePixels":body_reference,"bodyHeightMeasured":body_measured,"uniformScale":true,"automaticPerFrameScaleOrFootSnap":false,"rootMoves":false,"camera":false,"captures":captures,"failures":failures,"acceptance":"User visual review pending; this preview does not establish motion quality or gameplay performance."},"\t"))
	output.close()

func run() -> void:
	var path: String = str(options.get("atlas",DEFAULT_ATLAS))
	source_image = Image.load_from_file(path)
	if source_image==null or source_image.is_empty():
		failures.append("Atlas cannot be decoded: "+path)
		_save_report()
		quit(1)
		return
	if source_image.get_width()%4!=0 or source_image.get_height()%2!=0:
		failures.append("Atlas dimensions do not divide into a 4x2 grid.")
		_save_report()
		quit(1)
		return
	cell = Vector2(source_image.get_width()/4.0,source_image.get_height()/2.0)
	var metadata_path: String = str(options.get("metadata",path.get_basename()+".json"))
	if FileAccess.file_exists(metadata_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if parsed is Dictionary: metadata = parsed
		else: failures.append("Metadata is not a JSON object.")
	var authored_frames: Array = metadata.get("frames",[]) if metadata.get("frames",[]) is Array else []
	var fallback_height: float = 1.0
	var authored_heights: Array[float] = []
	for index in range(FRAME_COUNT):
		var record: Dictionary = authored_frames[index].duplicate(true) if index<authored_frames.size() and authored_frames[index] is Dictionary else {}
		var region: Rect2 = Rect2(Vector2(float(index%4)*cell.x,float(index/4)*cell.y),cell)
		if _numbers(record.get("rect"),4):
			var rect_value: Array = record.rect
			region = Rect2(float(rect_value[0]),float(rect_value[1]),float(rect_value[2]),float(rect_value[3]))
		if not Rect2(Vector2.ZERO,Vector2(source_image.get_size())).encloses(region) or not region.has_area():
			failures.append("Invalid source rectangle for frame "+str(index))
			_save_report()
			quit(1)
			return
		var used: Rect2i = source_image.get_region(Rect2i(region)).get_used_rect()
		fallback_height = maxf(fallback_height,float(used.size.y))
		if _numbers(record.get("bodyRect"),4): authored_heights.append(float(record.bodyRect[3]))
		record["resolvedRect"] = region
		frame_records.append(record)
	var manual_height: Variant = metadata.get("bodyHeightPixels",0)
	if (manual_height is int or manual_height is float) and is_finite(float(manual_height)) and float(manual_height)>0:
		body_reference = float(manual_height)
		body_measured = true
	elif authored_heights.size()==FRAME_COUNT and authored_heights.min()>0:
		authored_heights.sort()
		body_reference = (authored_heights[3]+authored_heights[4])*.5
		body_measured = true
	else:
		body_reference = fallback_height
	atlas = ImageTexture.create_from_image(source_image)
	root.size = Vector2i(1440,900)
	var stage: Node2D = Node2D.new()
	stage.name = "Spear2DIndependentPreview"
	root.add_child(stage)
	var background: ColorRect = ColorRect.new()
	background.color = Color("515656")
	background.size = Vector2(1440,900)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	_label(stage,"SPEAR / NORTH-EAST WALK / 8 FRAMES / 10 FPS / 0.8 SECOND LOOP",Vector2(36,20),1370,26)
	_label(stage,"Fixed camera and root. Same scale for every frame. No blending, effects or gameplay.",Vector2(36,65),1370,20)
	var basis: String = "Body height from authored metadata" if body_measured else "Silhouette height includes spear; body height is unmeasured"
	_label(stage,basis,Vector2(36,105),1370,20)
	var sizes: Array = [48.0,64.0,192.0]
	var positions: Array[Vector2] = [Vector2(230,435),Vector2(600,435),Vector2(1090,435)]
	for index in range(sizes.size()):
		var actor: Sprite2D = create_sprite(stage,positions[index],float(sizes[index]))
		actors.append(actor)
		var size_text: String = ("BODY " if body_measured else "SILHOUETTE ")+str(int(sizes[index]))+" px"
		_label(stage,size_text,positions[index]+Vector2(-145,30),310,24)
		var baseline: Line2D = Line2D.new()
		baseline.add_point(positions[index]+Vector2(-110,0))
		baseline.add_point(positions[index]+Vector2(110,0))
		baseline.default_color = Color("b0b5b0")
		baseline.width = 1.0
		stage.add_child(baseline)
	frame_label = _label(stage,"",Vector2(36,510),1370,23)
	_label(stage,"ALL EIGHT SOURCE POSES / SAME REGISTRATION AND SCALE",Vector2(36,558),1370,20)
	for index in range(FRAME_COUNT):
		var point: Vector2 = Vector2(90+180*index,785)
		var pose: Sprite2D = create_sprite(stage,point,96.0)
		apply_frame(pose,index)
		_label(stage,"FRAME "+str(index+1),Vector2(point.x-60,810),150,18)
	set_animation_frame(clampi(int(options.get("capture-frame",0)),0,FRAME_COUNT-1))
	running = true
	if options.has("capture") or options.has("capture-all-dir"):
		capture_pending = true
		if DisplayServer.get_name()=="headless":
			failures.append("Actual preview captures require a rendered engine, not headless.")
		else:
			if options.has("capture"):
				await capture(str(options.capture),clampi(int(options.get("capture-frame",0)),0,FRAME_COUNT-1))
			if options.has("capture-all-dir"):
				for index in range(FRAME_COUNT):
					await capture(str(options["capture-all-dir"]).path_join("frame%02d.png"%index),index)
		capture_pending = false
	_save_report()
	if options.has("quit-after-capture") or not failures.is_empty(): quit(0 if failures.is_empty() else 1)

func create_sprite(parent: Node, foot_position: Vector2, target_height: float) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.hframes = 4
	sprite.vframes = 2
	sprite.position = foot_position
	sprite.scale = Vector2.ONE*target_height/body_reference
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(sprite)
	apply_frame(sprite,0)
	return sprite

func apply_frame(sprite: Sprite2D, index: int) -> void:
	var record: Dictionary = frame_records[index]
	var anchor: Vector2 = Vector2(cell.x*.5,cell.y*.88)
	var authored_anchor: Variant = record.get("footAnchor",metadata.get("anchor",[]))
	if _numbers(authored_anchor,2): anchor = Vector2(float(authored_anchor[0]),float(authored_anchor[1]))
	var shift: Vector2 = Vector2.ZERO
	if _numbers(record.get("offset"),2): shift = Vector2(float(record.offset[0]),float(record.offset[1]))
	if record.has("rect"):
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.region_enabled = true
		sprite.region_rect = record.resolvedRect
		sprite.frame = 0
	else:
		sprite.region_enabled = false
		sprite.hframes = 4
		sprite.vframes = 2
		sprite.frame = index
	sprite.offset = -anchor+shift

func set_animation_frame(index: int) -> void:
	current_frame = index
	for actor in actors: apply_frame(actor,index)
	if frame_label!=null: frame_label.text = "LOOP FRAME %d / 8    |    Source grid 4 x 2    |    USER VISUAL REVIEW PENDING"%(index+1)

func capture(path: String, index: int) -> void:
	if not _output_path(path) or path.get_extension().to_lower()!="png":
		failures.append("Capture path must be a PNG in "+EVIDENCE)
		return
	set_animation_frame(index)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(path)
	if error==OK: captures.append({"path":path,"frame":index,"pixels":[image.get_width(),image.get_height()]})
	else: failures.append("Capture save failed: "+path+" error "+str(error))
