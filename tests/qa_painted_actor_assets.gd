extends SceneTree
## Decoded-pixel checks. No battle handlers, product scenes or save access.

const DEFAULT_MANIFEST: String = "res://assets/characters/painted-v1/manifest.json"
const OUTPUT: String = "res://tests/profiles/painted-v1/asset_qa.json"
const FRIENDLY_ROLES: Array = ["spear","archer","gunner","samurai","monk","ninja","commander"]
const ENEMY_ROLES: Array = ["spear","runner","archer","gunner","samurai"]
var options: Dictionary = {}
var checks: int = 0
var failures: Array = []
var warnings: Array = []
var rows: Array = []
var textures: Dictionary = {}
var coverage: Dictionary = {}

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
		push_error("PAINTED_ASSET "+note)

func numbers(value: Variant, length: int) -> bool:
	if not value is Array or value.size()!=length: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

func texture(path: String) -> Image:
	if textures.has(path): return textures[path]
	var image: Image = Image.load_from_file(path)
	check(image!=null and not image.is_empty(),"Actual PNG decodes: "+path)
	if image==null or image.is_empty(): return null
	var header: PackedByteArray = FileAccess.get_file_as_bytes(path).slice(0,26)
	check(header.size()==26 and header.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]) and int(header[25])==6,"Source has actual RGBA PNG channels: "+path)
	check(image.detect_alpha()!=Image.ALPHA_NONE,"PNG contains actual transparency: "+path)
	image.convert(Image.FORMAT_RGBA8)
	textures[path] = image
	return image

func metrics(image: Image, rect: Rect2i) -> Dictionary:
	var pixels: PackedByteArray = image.get_region(rect).get_data()
	var min_point: Vector2i = rect.size
	var max_point: Vector2i = Vector2i(-1,-1)
	var core_bottom: int = -1
	var visible: int = 0
	var transparent: int = 0
	var partial: int = 0
	var edges: int = 0
	for y in range(rect.size.y):
		for x in range(rect.size.x):
			var alpha: int = pixels[(y*rect.size.x+x)*4+3]
			if alpha==0: transparent += 1
			if alpha>0 and alpha<255: partial += 1
			if alpha>=128: core_bottom = maxi(core_bottom,y)
			if alpha>8:
				visible += 1
				min_point.x = mini(min_point.x,x); min_point.y = mini(min_point.y,y)
				max_point.x = maxi(max_point.x,x); max_point.y = maxi(max_point.y,y)
				if x==0 or y==0 or x==rect.size.x-1 or y==rect.size.y-1: edges += 1
	var foot_sum: float = 0.0
	var foot_count: int = 0
	var band: int = maxi(2,int(ceil(float(maxi(0,core_bottom-min_point.y+1))*.04)))
	if core_bottom>=0:
		for y in range(maxi(0,core_bottom-band+1),core_bottom+1):
			for x in range(rect.size.x):
				if pixels[(y*rect.size.x+x)*4+3]>=128:
					foot_sum += float(x)+.5
					foot_count += 1
	var hash_context: HashingContext = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(pixels)
	return {"visiblePixelsAlphaAbove8":visible,"transparentFraction":float(transparent)/float(rect.size.x*rect.size.y),"partialAlphaPixels":partial,"edgePixelsAlphaAbove8":edges,"bounds":[min_point.x,min_point.y,max_point.x-min_point.x+1,max_point.y-min_point.y+1] if visible>0 else [],"footProxy":[foot_sum/float(foot_count),float(core_bottom)+1.0] if foot_count>0 else [],"pixelSha256":hash_context.finish().hex_encode()}

func inspect_direction(side: String, role: String, direction: String, role_record: Dictionary, context: Dictionary) -> void:
	var note: String = side+"/"+role+"/"+direction
	var direction_value: Variant = role_record.get(direction,{})
	var record: Dictionary = direction_value if direction_value is Dictionary else {"walk":direction_value} if direction_value is Array else {}
	check(not record.is_empty(),note+": authored direction exists")
	if record.is_empty(): return
	var walk_value: Variant = record.get("walk",[])
	var walk: Array = walk_value.get("frames",[]) if walk_value is Dictionary and walk_value.get("frames",[]) is Array else walk_value if walk_value is Array else []
	check(walk.size()>=2,note+": at least2authored walk poses exist")
	coverage[note] = walk.size()
	var base: Dictionary = context.duplicate(false)
	base.merge(record,true)
	var shared_body: float = float(context.get("bodyHeightPixels",0.0))
	check(is_finite(shared_body) and shared_body>0,note+": shared role body-height reference is explicit")
	var digests: Dictionary = {}
	var foot_points: Array[Vector2] = []
	var heights: Array[float] = []
	for index in range(walk.size()):
		var pose: Dictionary = walk[index] if walk[index] is Dictionary else {"rect":walk[index]} if numbers(walk[index],4) else {}
		var source: String = str(pose.get("texture",base.get("texture",base.get("atlas",""))))
		var image: Image = texture(source)
		var rectangle: Variant = pose.get("rect",base.get("rect",[]))
		check(numbers(rectangle,4),note+"/%d: finite source rectangle"%index)
		if image==null or not numbers(rectangle,4): continue
		var rect: Rect2i = Rect2i(int(rectangle[0]),int(rectangle[1]),int(rectangle[2]),int(rectangle[3]))
		var valid: bool = rect.has_area() and Rect2i(Vector2i.ZERO,image.get_size()).encloses(rect)
		check(valid,note+"/%d: source rectangle is inside actual PNG"%index)
		if not valid: continue
		var result: Dictionary = metrics(image,rect)
		result.merge({"side":side,"role":role,"direction":direction,"pose":index,"texture":source,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]},true)
		check(int(result.visiblePixelsAlphaAbove8)>0,note+"/%d: nonempty character"%index)
		check(int(result.edgePixelsAlphaAbove8)==0,note+"/%d: no character pixels clipped at source edges"%index)
		check(float(result.transparentFraction)>.1,note+"/%d: real transparent surrounding area"%index)
		var anchor: Variant = pose.get("anchor",base.get("anchor",[]))
		check(numbers(anchor,2),note+"/%d: explicit finite foot anchor"%index)
		var offset: Variant = pose.get("offset",base.get("offset",[0,0]))
		check(numbers(offset,2),note+"/%d: finite registration offset"%index)
		if numbers(anchor,2) and numbers(offset,2) and result.footProxy.size()==2:
			var foot: Vector2 = Vector2(float(result.footProxy[0])-float(anchor[0])+float(offset[0]),float(result.footProxy[1])-float(anchor[1])+float(offset[1]))
			foot_points.append(foot)
			result["registeredFootProxy"] = [foot.x,foot.y]
		if result.bounds.size()==4: heights.append(float(result.bounds[3]))
		digests[result.pixelSha256] = true
		rows.append(result)
	check(walk.size()<2 or digests.size()>=2,note+": walk poses differ in actual source pixels")
	var foot_range: Vector2 = Vector2.ZERO
	if not foot_points.is_empty():
		var low: Vector2 = foot_points[0]
		var high: Vector2 = foot_points[0]
		for foot in foot_points:
			low = low.min(foot); high = high.max(foot)
		foot_range = high-low
	coverage[note] = {"walkFrames":walk.size(),"uniquePixelFrames":digests.size(),"registeredFootProxyRangePixels":[foot_range.x,foot_range.y],"footProxyRangeAt44pxBody":[foot_range.x*44.0/shared_body,foot_range.y*44.0/shared_body] if shared_body>0 else [],"silhouetteHeightRangePixels":[heights.min(),heights.max()] if not heights.is_empty() else [],"bodyHeightPixels":shared_body}
	var head: float = float(context.get("headHeightPixels",0.0))
	if head>0 and shared_body>0: coverage[note]["authoredBodyHeadRatio"] = shared_body/head

func run() -> void:
	var path: String = str(options.get("manifest",DEFAULT_MANIFEST))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	check(parsed is Dictionary,"Painted manifest exists and decodes")
	if not parsed is Dictionary:
		finish(path)
		return
	var manifest: Dictionary = parsed
	var common: Dictionary = manifest.get("frames",{}) if manifest.get("frames",{}) is Dictionary else {}
	var factions: Dictionary = manifest.get("factions",{}) if manifest.get("factions",{}) is Dictionary else {}
	var enemy: Dictionary = factions.get("enemy",{}) if factions.get("enemy",{}) is Dictionary else {}
	var enemy_frames: Dictionary = enemy.get("frames",{}) if enemy.get("frames",{}) is Dictionary else {}
	for role in FRIENDLY_ROLES: check(common.has(role),"Active allied role has its own painted asset: "+str(role))
	check(not common.has("naginata"),"Retired naginata is excluded from the active painted roster")
	for role in ENEMY_ROLES: check(enemy_frames.has(role),"Enemy role has an explicit hostile asset: "+str(role))
	if not enemy_frames.has("commander"): warnings.append("Enemy mounted/commander asset is absent; do not claim that family is visually replaced.")
	for side in ["friendly","enemy"]:
		var side_frames: Dictionary = common if side=="friendly" else enemy_frames
		var side_context: Dictionary = manifest.duplicate(false)
		if side=="enemy": side_context.merge(enemy,true)
		for role in side_frames:
			if not side_frames[role] is Dictionary: continue
			var context: Dictionary = side_context.duplicate(false)
			context.merge(side_frames[role],true)
			for direction in ["ne","sw"]: inspect_direction(side,str(role),direction,side_frames[role],context)
	finish(path)

func finish(manifest_path: String) -> void:
	var path: String = str(options.get("report",OUTPUT))
	var allowed: String = ProjectSettings.globalize_path(OUTPUT.get_base_dir()+"/").replace("\\","/")
	check(ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().begins_with(allowed) and path.get_extension().to_lower()=="json","Report stays inside painted-v1 evidence")
	if not ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().begins_with(allowed):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output!=null:
		output.store_string(JSON.stringify({"manifest":manifest_path,"checks":checks,"failures":failures,"warnings":warnings,"decodedAtlasCount":textures.size(),"coverage":coverage,"poses":rows,"measurement":"Visible alpha>8; lower4% opaque(alpha>=128) centroid is a foot proxy, not anatomical verification. Body/head measurements are author-provided references. No silhouette stretching/perframe rescale used.","acceptance":"Asset integrity and reported pixel metrics only. Full battlefield composition, natural limbs, direction, team colors and walk quality require actual rendered review. No gameplay-performance claim."},"\t"))
		output.close()
	else: failures.append("Report write failed")
	print("PAINTED_ASSET checks=%d failures=%d report=%s"%[checks,failures.size(),path])
	quit(0 if failures.is_empty() else 1)
