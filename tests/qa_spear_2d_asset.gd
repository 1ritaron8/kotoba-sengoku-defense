extends SceneTree
## Measures decoded PNG pixels independently of the preview renderer.

const DEFAULT_ATLAS: String = "res://assets/characters/spear-2d-pilot-01/spear-ne-walk-atlas.png"
const EVIDENCE: String = "res://tests/profiles/spear-2d-pilot-01/"
const FRAME_COUNT: int = 8
var options: Dictionary = {}
var checks: int = 0
var failures: Array = []
var review_flags: Array = []
var report: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var pair: PackedStringArray = argument.substr(2).split("=",true,1)
			options[pair[0]] = pair[1] if pair.size()>1 else "true"
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		push_error("SPEAR_ASSET "+note)

func numbers(value: Variant, length: int) -> bool:
	if not value is Array or value.size()!=length: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

func rect_array(rect: Rect2i) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func pixel_metrics(image: Image, rectangle: Rect2i) -> Dictionary:
	var cropped: Image = image.get_region(rectangle)
	var bytes: PackedByteArray = cropped.get_data()
	var width: int = cropped.get_width()
	var height: int = cropped.get_height()
	var min_x: int = width
	var min_y: int = height
	var max_x: int = -1
	var max_y: int = -1
	var core_min_x: int = width
	var core_min_y: int = height
	var core_max_x: int = -1
	var core_max_y: int = -1
	var nonzero: int = 0
	var partial: int = 0
	var transparent: int = 0
	var edge_pixels: int = 0
	for y in range(height):
		for x in range(width):
			var alpha: int = bytes[(y*width+x)*4+3]
			if alpha==0: transparent += 1
			if alpha>0 and alpha<255: partial += 1
			if alpha>8:
				nonzero += 1
				min_x = mini(min_x,x); min_y = mini(min_y,y)
				max_x = maxi(max_x,x); max_y = maxi(max_y,y)
				if x==0 or y==0 or x==width-1 or y==height-1: edge_pixels += 1
			if alpha>=128:
				core_min_x = mini(core_min_x,x); core_min_y = mini(core_min_y,y)
				core_max_x = maxi(core_max_x,x); core_max_y = maxi(core_max_y,y)
	var bounds: Rect2i = Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1) if nonzero>0 else Rect2i()
	var core: Rect2i = Rect2i(core_min_x,core_min_y,core_max_x-core_min_x+1,core_max_y-core_min_y+1) if core_max_y>=0 else Rect2i()
	var foot_sum: float = 0.0
	var foot_count: int = 0
	if core.has_area():
		var band_height: int = maxi(2,int(ceil(float(core.size.y)*.04)))
		for y in range(maxi(0,core_max_y-band_height+1),core_max_y+1):
			for x in range(width):
				if bytes[(y*width+x)*4+3]>=128:
					foot_sum += float(x)+.5
					foot_count += 1
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return {"rect":rect_array(rectangle),"visiblePixelsAlphaAbove8":nonzero,"transparentPixels":transparent,"partialAlphaPixels":partial,"transparentFraction":float(transparent)/float(width*height),"edgePixelsAlphaAbove8":edge_pixels,"bounds":rect_array(bounds),"coreBoundsAlpha128":rect_array(core),"margins":[min_x,min_y,width-max_x-1,height-max_y-1] if nonzero>0 else [],"footProxy":[foot_sum/float(foot_count),float(core_max_y)+1.0] if foot_count>0 else [],"pixelSha256":digest.finish().hex_encode()}

func run() -> void:
	var path: String = str(options.get("atlas",DEFAULT_ATLAS))
	var image: Image = Image.load_from_file(path)
	check(image!=null and not image.is_empty(),"PNG decodes into a nonempty image")
	if image==null or image.is_empty():
		finish()
		return
	var header: PackedByteArray = FileAccess.get_file_as_bytes(path).slice(0,26)
	var png_header: bool = header.size()==26 and header.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10])
	check(png_header,"Source has a real PNG signature")
	var color_type: int = int(header[25]) if png_header else -1
	check(color_type==6,"PNG source stores actual RGBA channels (IHDR color type 6)")
	var decoded_alpha: int = image.detect_alpha()
	check(decoded_alpha!=Image.ALPHA_NONE,"Decoded source contains real transparency")
	check(image.get_width()%4==0 and image.get_height()%2==0,"Source dimensions divide into the specified 4x2 grid")
	report = {"atlas":path,"atlasPixels":[image.get_width(),image.get_height()],"pngColorType":color_type,"pngBitDepth":int(header[24]) if png_header else -1,"decodedAlphaMode":decoded_alpha,"grid":[4,2],"frameCount":FRAME_COUNT,"animationFps":10,"loopSeconds":.8,"measurement":"Alpha bounds use alpha>8; core and foot proxy use alpha>=128. Foot proxy is lower4% opaque-pixel centroid, not a verified anatomical foot anchor.","acceptance":"Pixel integrity checks only. Consistent anatomy, weapon, lighting, direction and natural walk loop require user visual review. No gameplay FPS measured."}
	if image.get_width()%4!=0 or image.get_height()%2!=0:
		finish()
		return
	image.convert(Image.FORMAT_RGBA8)
	var cell: Vector2i = Vector2i(image.get_width()/4,image.get_height()/2)
	var metadata: Dictionary = {}
	var metadata_path: String = str(options.get("metadata",path.get_basename()+".json"))
	if FileAccess.file_exists(metadata_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		check(parsed is Dictionary,"Optional metadata is a JSON object")
		if parsed is Dictionary: metadata = parsed
	var authored_frames: Array = metadata.get("frames",[]) if metadata.get("frames",[]) is Array else []
	check(authored_frames.is_empty() or authored_frames.size()==FRAME_COUNT,"Optional frame registration supplies all8frames")
	if metadata.has("anchor"): check(numbers(metadata.anchor,2),"Global anchor is a finite2D pixel coordinate")
	var rows: Array = []
	var foot_points: Array[Vector2] = []
	var heights: Array[float] = []
	var widths: Array[float] = []
	var core_heights: Array[float] = []
	var total_pixels: int = 0
	var transparent_pixels: int = 0
	var partial_pixels: int = 0
	var hashes: Dictionary = {}
	var duplicate_pairs: Array = []
	var body_heights: Array[float] = []
	for index in range(FRAME_COUNT):
		var record: Dictionary = authored_frames[index] if index<authored_frames.size() and authored_frames[index] is Dictionary else {}
		var rectangle: Rect2i = Rect2i(Vector2i(index%4,index/4)*cell,cell)
		if record.has("rect"):
			check(numbers(record.rect,4),"Frame%d source rectangle has4finite values"%index)
			if numbers(record.rect,4):
				rectangle = Rect2i(int(record.rect[0]),int(record.rect[1]),int(record.rect[2]),int(record.rect[3]))
		var legal_rect: bool = rectangle.has_area() and Rect2i(Vector2i.ZERO,image.get_size()).encloses(rectangle)
		check(legal_rect,"Frame%d source rectangle stays inside the actual PNG"%index)
		if not legal_rect: continue
		var metrics: Dictionary = pixel_metrics(image,rectangle)
		metrics["frame"] = index
		check(int(metrics.visiblePixelsAlphaAbove8)>0,"Frame%d has visible character pixels"%index)
		check(int(metrics.edgePixelsAlphaAbove8)==0,"Frame%d silhouette is not clipped by any frame edge"%index)
		check(float(metrics.transparentFraction)>.1,"Frame%d has a transparent surrounding area"%index)
		var anchor: Vector2 = Vector2(cell.x*.5,cell.y*.88)
		var anchor_value: Variant = record.get("footAnchor",metadata.get("anchor",[]))
		if record.has("footAnchor"): check(numbers(record.footAnchor,2),"Frame%d foot anchor is finite"%index)
		if numbers(anchor_value,2): anchor = Vector2(float(anchor_value[0]),float(anchor_value[1]))
		var shift: Vector2 = Vector2.ZERO
		if record.has("offset"):
			check(numbers(record.offset,2),"Frame%d registration offset is finite"%index)
			if numbers(record.offset,2): shift = Vector2(float(record.offset[0]),float(record.offset[1]))
		if metrics.footProxy.size()==2:
			var foot: Vector2 = Vector2(float(metrics.footProxy[0]),float(metrics.footProxy[1]))-anchor+shift
			foot_points.append(foot)
			metrics["registeredFootProxy"] = [foot.x,foot.y]
		if record.has("bodyRect"):
			check(numbers(record.bodyRect,4),"Frame%d optional body rectangle is finite"%index)
			if numbers(record.bodyRect,4):
				var body_rect: Rect2 = Rect2(float(record.bodyRect[0]),float(record.bodyRect[1]),float(record.bodyRect[2]),float(record.bodyRect[3]))
				check(body_rect.has_area() and Rect2(Vector2.ZERO,Vector2(rectangle.size)).encloses(body_rect),"Frame%d body measurement stays inside its source frame"%index)
				if body_rect.has_area(): body_heights.append(body_rect.size.y)
		heights.append(float(metrics.bounds[3]))
		widths.append(float(metrics.bounds[2]))
		core_heights.append(float(metrics.coreBoundsAlpha128[3]))
		total_pixels += rectangle.size.x*rectangle.size.y
		transparent_pixels += int(metrics.transparentPixels)
		partial_pixels += int(metrics.partialAlphaPixels)
		var digest: String = str(metrics.pixelSha256)
		if hashes.has(digest): duplicate_pairs.append([hashes[digest],index])
		else: hashes[digest] = index
		rows.append(metrics)
	check(rows.size()==FRAME_COUNT,"All8real frames were measured")
	if hashes.size()==1: review_flags.append("All8frames are pixel-identical; there is no measured walk pose change.")
	var body_reference: float = 0.0
	var manual_height: Variant = metadata.get("bodyHeightPixels",0)
	if metadata.has("bodyHeightPixels"):
		check((manual_height is int or manual_height is float) and is_finite(float(manual_height)) and float(manual_height)>0,"Shared body-height measurement is finite and positive")
		if (manual_height is int or manual_height is float) and is_finite(float(manual_height)): body_reference = maxf(0.0,float(manual_height))
	if body_reference<=0 and body_heights.size()==FRAME_COUNT:
		body_heights.sort()
		body_reference = (body_heights[3]+body_heights[4])*.5
	var extent: Vector2 = Vector2.ZERO
	if not foot_points.is_empty():
		var min_point: Vector2 = foot_points[0]
		var max_point: Vector2 = foot_points[0]
		for foot in foot_points:
			min_point = min_point.min(foot)
			max_point = max_point.max(foot)
		extent = max_point-min_point
	var fallback_height: float = float(heights.max()) if not heights.is_empty() else 1.0
	var scale_basis: float = body_reference if body_reference>0 else maxf(1.0,fallback_height)
	report["metadata"] = metadata_path if not metadata.is_empty() else "none; exact grid only"
	report["frames"] = rows
	report["transparentFraction"] = float(transparent_pixels)/maxf(1.0,float(total_pixels))
	report["partialAlphaPixels"] = partial_pixels
	report["uniquePixelFrames"] = hashes.size()
	report["duplicateFramePairs"] = duplicate_pairs
	report["silhouetteHeightRangePixels"] = [heights.min(),heights.max()] if not heights.is_empty() else []
	report["silhouetteWidthRangePixels"] = [widths.min(),widths.max()] if not widths.is_empty() else []
	report["coreHeightRangePixels"] = [core_heights.min(),core_heights.max()] if not core_heights.is_empty() else []
	report["silhouetteHeightRatioMaxMin"] = float(heights.max())/maxf(1.0,float(heights.min())) if not heights.is_empty() else 0.0
	report["bodyHeightMeasured"] = body_reference>0
	report["bodyReferencePixels"] = body_reference
	report["uniformScaleReferencePixels"] = scale_basis
	report["registeredFootProxyRangePixels"] = [extent.x,extent.y]
	report["footProxyRangeAt48Pixels"] = [extent.x*48.0/scale_basis,extent.y*48.0/scale_basis]
	report["footProxyRangeAt64Pixels"] = [extent.x*64.0/scale_basis,extent.y*64.0/scale_basis]
	if body_reference<=0: review_flags.append("No authored body measurement;48/64preview heights refer to full silhouette including spear.")
	finish()

func finish() -> void:
	report["checks"] = checks
	report["failures"] = failures
	report["reviewFlags"] = review_flags
	var path: String = str(options.get("report",EVIDENCE+"asset_qa.json"))
	var absolute: String = ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
	var allowed: String = ProjectSettings.globalize_path(EVIDENCE).replace("\\","/")
	if not absolute.begins_with(allowed) or path.get_extension().to_lower()!="json":
		push_error("QA output must be JSON inside "+EVIDENCE)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output!=null:
		output.store_string(JSON.stringify(report,"\t"))
		output.close()
	else:
		failures.append("Could not write QA report")
	print("SPEAR_ASSET checks=%d failures=%d report=%s"%[checks,failures.size(),path])
	quit(0 if failures.is_empty() else 1)
