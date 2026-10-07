extends SceneTree
## Run with the editor executable --main-pack dist/KotobaSengoku.exe and this
## script's absolute OS path. Native resources are read from the embedded pack.
## APPDATA and LOCALAPPDATA must be beneath this workspace's tests/profiles/.
## --source-check-only explicitly reports a source check, never a packed pass.

const Actor = preload("res://native/sengoku_actor_3d.gd")
const Materials = preload("res://native/actor_materials.gd")
const Troops = preload("res://native/troops_3d.gd")
const Body = preload("res://native/human_body_geometry.gd")
const Portrait = preload("res://native/barracks_portrait.gd")
const Game = preload("res://native/game.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const TerrainMaterials = preload("res://native/battlefield_materials.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const LearningAudio = preload("res://native/learning_audio.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const ATLAS_PATH = "res://assets/materials/sengoku/surface-atlas-v1.png"
const COASTLINE_PATH = "res://assets/atlas/japan-coastline.json"
const CANOPY_PATH = "res://assets/materials/terrain/pine-canopy-atlas-v1.png"
const PROFILE_ROOT = "c:/jp_df/tests/profiles/"
var checks: int = 0
var failures: Array = []
var models: Array = []
var map_resources: Array = []
var portrait_paths: Array = []
var material_paths: Array = []
var terrain_paths: Array = []
var natural_models: Array = []
var font_paths: Array = []
var resource_inventory: Array[String] = []
var speech_report: Dictionary = {}
var coastline_report: Dictionary = {}
var source_only: bool = false
var pack_path: String = ""
var art_manifest: Dictionary = {}
var art_by_stage: Dictionary = {}
var art_report: Array = []
var art_fault_report: Array = []
var basis_report: Array = []
var fallback_count: int = 0
var guard_metadata: Dictionary = {}

func _initialize() -> void:
	source_only = "--source-check-only" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("PACK 3D QA "+message)

func json_resource(path: String, expected_type: int) -> Variant:
	check(FileAccess.file_exists(path),path+": raw JSON is included")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(typeof(parsed)==expected_type,path+": included JSON parses with expected shape")
	return parsed

func texture_resource(path: String) -> Texture2D:
	check(ResourceLoader.exists(path),path+": imported texture resource exists")
	var texture=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(texture is Texture2D,path+": actual imported texture loads")
	if texture is Texture2D:
		check(texture.get_width()>0 and texture.get_height()>0,path+": loaded texture has image dimensions")
		return texture
	return null

func normalized_os_path(path: String) -> String:
	return path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")

func command_pack_path() -> String:
	return option("--pack-file")

func option(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name+"="): return argument.trim_prefix(name+"=")
	return ""

func safe_environment() -> bool:
	var appdata: String = normalized_os_path(OS.get_environment("APPDATA"))
	var localdata: String = normalized_os_path(OS.get_environment("LOCALAPPDATA"))
	var user_path: String = normalized_os_path(ProjectSettings.globalize_path("user://"))
	# Godot removes consumed platform/pack switches from get_cmdline_args().
	# The saved invocation supplies --audio-driver Dummy/--main-pack; repeated
	# launcher declarations plus the mounted JSON hashes bind the concrete pack.
	var declared_audio: String = OS.get_environment("QA_AUDIO_DRIVER")
	check(DisplayServer.get_name() == "headless","CPU-only verifier uses the headless display server")
	check(declared_audio == "Dummy" and option("--declared-audio-driver") == declared_audio,"Resource launcher's Dummy audio declarations match its recorded startup command")
	check(appdata.begins_with(PROFILE_ROOT),"APPDATA is an isolated workspace test profile")
	check(localdata == appdata,"LOCALAPPDATA is the same isolated workspace test profile")
	check(user_path.begins_with(PROFILE_ROOT) and user_path.begins_with(appdata + "/"),"Actual Godot user:// is contained by the isolated profile before any writes")
	pack_path = command_pack_path()
	var resource_hashes: Dictionary = {}
	if not source_only:
		check(not pack_path.is_empty() and normalized_os_path(pack_path) == normalized_os_path(OS.get_environment("QA_MAIN_PACK")),"User QA target equals the launcher's actual main-pack declaration")
		check(normalized_os_path(pack_path).begins_with("c:/jp_df/tests/"),"The mounted release artifact is isolated under workspace tests")
		check(not pack_path.is_empty() and FileAccess.file_exists(pack_path),"Actual verifier explicitly mounts an existing --main-pack artifact")
		check(pack_path.get_extension().to_lower() in ["exe","pck"],"Mounted artifact is an embedded executable or PCK")
		var expected: String = option("--expected-pack-sha").to_lower()
		check(expected.length() == 64 and FileAccess.get_sha256(pack_path).to_lower() == expected,"Actual target bytes match the final executable/PCK SHA256")
		var cwd: String = DirAccess.open(".").get_current_dir()
		check(normalized_os_path(cwd) == "c:/jp_df/tools/pack-learning-verifier-empty" and normalized_os_path(OS.get_environment("QA_VERIFIER_CWD")) == normalized_os_path(cwd),"Actual empty pack-only working directory matches its launcher declaration")
		check(not FileAccess.file_exists(cwd.path_join("project.godot")) and not DirAccess.dir_exists_absolute(cwd.path_join("native")),"No loose source project can override the mounted artifact")
		check(not FileAccess.file_exists("res://tests/qa_pack_3d.gd"),"Actual mounted release excludes the external source QA")
		for key in ["maps","plans","voice","art"]:
			var path: String = {"maps":"res://native/maps.json","plans":"res://native/learning_plans.json","voice":"res://assets/learning-voice/manifest.json","art":"res://assets/battlefields-rendered/manifest.json"}[key]
			var required_hash: String = option("--expected-"+key+"-sha").to_lower()
			var actual_hash: String = FileAccess.get_sha256(path).to_lower()
			check(required_hash.length() == 64 and actual_hash == required_hash,"Actual mounted "+key+" resource matches the final source/build fingerprint")
			resource_hashes[key] = {"path":path,"expected":required_hash,"actual":actual_hash}
	guard_metadata = {"appData":appdata,"localAppData":localdata,"actualUserDataDir":user_path,"displayDriver":DisplayServer.get_name(),"declaredAudioDriver":declared_audio,"declaredMainPack":pack_path,"executableSha256":FileAccess.get_sha256(pack_path) if not source_only else "","mountedResourceHashes":resource_hashes,"sourceOnly":source_only}
	if not failures.is_empty():
		print("PACK_3D_QA_ENVIRONMENT ",JSON.stringify({"failures":failures,"sourceOnly":source_only,"appdata":appdata,"localdata":localdata,"userPath":user_path,"mainPack":pack_path}))
		return false
	return true

func inventory_files(directory: String) -> void:
	for file_name in DirAccess.get_files_at(directory):
		resource_inventory.append(directory.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(directory):
		inventory_files(directory.path_join(directory_name))

func verify_exclusions(stages: Array) -> void:
	if source_only:
		return
	for directory in ["res://assets/stages","res://assets/battlefields","res://assets/learning-voice/build-tools","res://assets/learning-voice/sources","res://assets/announcements/sources","res://assets/narration/sources","res://assets/commanders/sources","res://tools","res://tests"]:
		check(not DirAccess.dir_exists_absolute(directory),directory+": source/build/rejected-photo directory is absent from the actual pack")
	for path in ["res://assets/atlas/world-july-2004.jpg","res://assets/atlas/manifest.json","res://assets/bgm.wav","res://assets/learning-voice/build-tools/runtime/models/vvms/n0.vvm","res://assets/learning-voice/build-tools/runtime/onnxruntime/lib/voicevox_onnxruntime.dll","res://assets/learning-voice/build-tools/runtime/c_api/lib/voicevox_core.dll"]:
		check(not FileAccess.file_exists(path) and not ResourceLoader.exists(path),path+": original photo/OS voice model/build binary is excluded including resource remaps")
	for stage in stages:
		var old_background: String = str(stage.get("background",""))
		if not old_background.is_empty():
			check(not FileAccess.file_exists(old_background) and not ResourceLoader.exists(old_background),str(stage.id)+": old full-stage background is absent, not a native battlefield dependency")
	inventory_files("res://")
	for path in resource_inventory:
		var lower: String = path.to_lower()
		check(not lower.begins_with("res://assets/map-") and not lower.begins_with("res://assets/stages/") and not lower.begins_with("res://assets/battlefields/"),path+": no legacy full-map image is shipped")
		check(not lower.contains("/learning-voice/build-tools/") and not lower.contains("/learning-voice/sources/") and not lower.contains("/announcements/sources/") and not lower.contains("/narration/sources/"),path+": no voice generator or source archive is shipped")
		check(not (lower.get_extension() in ["onnx","vvm","dll","lib","tmp"]) and not lower.contains("open_jtalk_dic") and not lower.contains("/osmodels/") and not lower.contains("/os-models/"),path+": no OS speech/model/runtime or temporary build file is shipped")
		var art_path: String = path.trim_suffix(".remap")
		if art_path.begins_with("res://assets/battlefields-rendered/") and art_path.ends_with(".png"):
			var approved: bool = false
			for entry in art_by_stage.values():
				if str(entry.get("path","")) == art_path: approved = true
			check(approved,path+": actual pack ships only approved final battlefield renders")

func verify_coastline() -> void:
	var coast: Variant = json_resource(COASTLINE_PATH,TYPE_DICTIONARY)
	var provenance: Variant = json_resource("res://assets/atlas/coastline-manifest.json",TYPE_DICTIONARY)
	if not coast is Dictionary or not provenance is Dictionary:
		return
	check(str(coast.get("feature","")) == "Japan" and str(coast.get("coordinateSystem","")).contains("4326"),"Original drawn atlas loads the physical Japan longitude/latitude coastline")
	check(str(provenance.get("license","")) == "Public Domain" and str(provenance.get("licenseURL","")).begins_with("https://www.naturalearthdata.com/"),"Packed coastline retains Natural Earth public-domain provenance")
	check(FileAccess.get_sha256(COASTLINE_PATH).to_lower() == str(provenance.get("outputSha256","")).to_lower(),"Actual packed coastline bytes match their authored metadata hash")
	check(FileAccess.file_exists("res://assets/atlas/NOTICE-NaturalEarth.txt"),"Coastline credits ship with the original map geometry")
	var rings: Array = coast.get("rings",[])
	var points: int = 0
	check(not rings.is_empty(),"Original atlas coastline contains real rings")
	for ring in rings:
		check(ring is Array and ring.size() >= 4,"A physical coastline ring has enough coordinate points")
		if not ring is Array:
			continue
		for point in ring:
			check(point is Array and point.size() == 2,"Coastline vertex is a longitude/latitude pair")
			if point is Array and point.size() == 2:
				check(is_finite(float(point[0])) and is_finite(float(point[1])) and absf(float(point[0])) <= 180 and absf(float(point[1])) <= 90,"Coastline vertex uses finite real-world coordinates")
				points += 1
	coastline_report = {"path":COASTLINE_PATH,"rings":rings.size(),"points":points,"sha256":FileAccess.get_sha256(COASTLINE_PATH),"license":provenance.get("license","")}

func verify_terrain_resources() -> void:
	var manifest: Variant = json_resource("res://assets/materials/terrain/manifest.json",TYPE_DICTIONARY)
	if manifest is Dictionary:
		var recipes: Array = manifest.get("materials",[])
		check(recipes.size() == 4,"Four actual terrain PBR families are included")
		for recipe in recipes:
			check(recipe.get("files",[]).size() == 3 and str(recipe.get("license","")) == "CC0",str(recipe.get("id",""))+": terrain metadata retains three CC0 surface channels")
			for entry in recipe.get("files",[]):
				var path: String = str(entry.get("path",""))
				terrain_paths.append(path)
				texture_resource(path)
		check(terrain_paths.size() == 12,"All twelve actual terrain PBR textures load")
	for family in ["forest","earth","wood","rock"]:
		var surface: StandardMaterial3D = TerrainMaterials.surface(family)
		check(surface.albedo_texture is Texture2D and surface.normal_enabled and surface.normal_texture is Texture2D and surface.roughness_texture is Texture2D,family+": runtime terrain/prop material binds actual color, normal and roughness textures")
	var canopy_metadata: Variant = json_resource("res://assets/materials/terrain/pine-canopy-atlas-v1.metadata.json",TYPE_DICTIONARY)
	var canopy: Texture2D = texture_resource(CANOPY_PATH)
	if canopy_metadata is Dictionary:
		var dimensions: Array = canopy_metadata.get("dimensions",[])
		check(dimensions.size() == 2 and canopy != null and canopy.get_width() == int(dimensions[0]) and canopy.get_height() == int(dimensions[1]),"Packed pine canopy texture and actual metadata dimensions agree")
		check(str(canopy_metadata.get("sourcePhoto","")) == "none" and str(canopy_metadata.get("tool","")) == "image_gen.imagegen" and bool(canopy_metadata.get("transparent_background",false)),"Pine canopy retains project-generated transparent material provenance")
		check(not bool(canopy_metadata.get("integration",{}).get("billboard",true)) and not bool(canopy_metadata.get("integration",{}).get("cameraFacing",true)),"Canopy metadata identifies real foliage meshes sharing battlefield lighting")
	var foliage: ShaderMaterial = TerrainMaterials.foliage()
	check(foliage.shader != null and foliage.get_shader_parameter("canopy") is Texture2D and foliage.shader.code.contains("ALPHA_SCISSOR_THRESHOLD"),"Actual native foliage material binds its canopy and alpha-cutout surface")
	var models_manifest: Variant = json_resource("res://assets/models/battlefield/manifest.json",TYPE_DICTIONARY)
	if not models_manifest is Dictionary:
		return
	var entries: Array = models_manifest.get("models",[])
	check(entries.size() == 4,"Four approved natural scanned model identities ship")
	for entry in entries:
		var path: String = str(entry.get("path",""))
		check(str(entry.get("license","")) == "CC0" and str(entry.get("source","")).begins_with("https://polyhaven.com/a/"),path+": natural model retains exact CC0 source metadata")
		check(ResourceLoader.exists(path,"PackedScene"),path+": imported natural model exists")
		var scene: PackedScene = ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(scene != null,path+": actual imported glTF scene loads all mesh dependencies")
		var mesh_count: int = 0
		var vertex_count: int = 0
		if scene != null:
			var instance: Node = scene.instantiate()
			for child in instance.find_children("*","MeshInstance3D",true,false):
				if child.mesh == null:
					continue
				mesh_count += 1
				for surface_index in range(child.mesh.get_surface_count()):
					var arrays: Array = child.mesh.surface_get_arrays(surface_index)
					vertex_count += arrays[Mesh.ARRAY_VERTEX].size()
					check(arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_NORMAL].size() > 0,path+": actual natural-model surface retains physical normals")
			instance.free()
		check(mesh_count > 0 and vertex_count > 0,path+": natural scenery contains actual loaded mesh geometry")
		for file in entry.get("files",[]):
			var dependency: String = str(file.get("path",""))
			if dependency.get_extension().to_lower() in ["jpg","png"]:
				texture_resource(dependency)
		natural_models.append({"id":entry.get("id",""),"path":path,"meshNodes":mesh_count,"sourceVertices":vertex_count})

func verify_fonts() -> void:
	for path in [GameFonts.HEADING_PATH,GameFonts.BODY_PATH,GameFonts.JAPANESE_PATH,GameFonts.READING_PATH]:
		font_paths.append(path)
		check(ResourceLoader.exists(path,"FontFile"),path+": approved runtime font is included")
		var font: FontFile = ResourceLoader.load(path,"FontFile",ResourceLoader.CACHE_MODE_IGNORE) as FontFile
		check(font != null and not font.data.is_empty(),path+": actual packed font data loads")
	check(font_paths.size() == 4,"All four chosen Korean/Japanese interface fonts load")
	check(GameFonts.body().get_string_size("전투 연습",HORIZONTAL_ALIGNMENT_LEFT,-1,20).x > 40,"Actual runtime Korean body-font helper provides measurable Korean glyphs")
	check(GameFonts.japanese().get_string_size("槍兵",HORIZONTAL_ALIGNMENT_LEFT,-1,28).x > 30 and GameFonts.reading().get_string_size("そうへい",HORIZONTAL_ALIGNMENT_LEFT,-1,16).x > 30,"Actual packed Japanese font helpers provide readable kanji and kana")

func sha256_shape(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not str(character) in "0123456789abcdef":
			return false
	return true

func verify_rendered_art_manifest(stages: Array) -> bool:
	var parsed: Variant = json_resource(RenderedArt.MANIFEST_PATH,TYPE_DICTIONARY)
	if not parsed is Dictionary:
		return false
	art_manifest = parsed
	var entries: Array = art_manifest.get("stages",[])
	check(int(art_manifest.get("version",0)) == 1 and bool(art_manifest.get("complete",false)),"Release art manifest is explicitly complete and uses the supported schema")
	check(int(art_manifest.get("expectedStageCount",0)) == 40 and entries.size() == stages.size() and stages.size() == 40,"Release manifest covers exactly the forty authored battles")
	var camera: Dictionary = art_manifest.get("camera",{})
	check(is_equal_approx(float(camera.get("elevation",0)),50.0) and is_equal_approx(float(camera.get("worldWidth",0)),18.5),"Approved art was generated for the actual 50 degree, 18.5 unit camera")
	var data_hash: String = FileAccess.get_sha256("res://native/maps.json")
	check(str(art_manifest.get("sourceMapsSha256",art_manifest.get("sourceDataSha256",""))) == data_hash,"Packed art manifest identifies the actual packed navigation/height data bytes")
	var hashes: Dictionary = {}
	var paths: Dictionary = {}
	for index in range(entries.size()):
		var entry: Variant = entries[index]
		check(entry is Dictionary,"Approved artwork entry is an object")
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("stageId",""))
		var path: String = str(entry.get("path",""))
		var digest: String = str(entry.get("sha256",""))
		check(not id.is_empty() and not art_by_stage.has(id),id+": release artwork has a unique stage identity")
		if index < stages.size():
			check(id == str(stages[index].id) and int(entry.get("stageNumber",0)) == index+1,id+": artwork order and stage number match the actual campaign")
		check(path.begins_with("res://assets/battlefields-rendered/") and path.ends_with(".png") and not paths.has(path),id+": battle uses its own approved rendered PNG")
		check(sha256_shape(digest) and not hashes.has(digest),id+": approved artwork has a distinct full SHA256")
		check(sha256_shape(str(entry.get("sourceGeometryFingerprint",""))),id+": artwork binds the frozen physical blueprint fingerprint")
		check(int(entry.get("width",0)) >= 1280 and int(entry.get("height",0)) >= 720,id+": approved render retains at least the blueprint resolution")
		var texture: Texture2D = texture_resource(path)
		if texture != null:
			check(texture.get_width() == int(entry.get("width",0)) and texture.get_height() == int(entry.get("height",0)),id+": actual imported artwork dimensions match its metadata")
		var raw_verified: bool = FileAccess.file_exists(path)
		if raw_verified:
			check(FileAccess.get_sha256(path) == digest,id+": actual raw artwork matches its approved hash when raw bytes ship")
		var bounds: Variant = entry.get("normalizedBounds",[])
		check(bounds is Array and bounds.size() == 4,id+": approved normalized artwork crop is explicit")
		if bounds is Array and bounds.size() == 4:
			var crop: Rect2 = Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3]))
			check(crop.size.x > 0 and crop.size.y > 0 and Rect2(0,0,1,1).grow(.0001).encloses(crop),id+": approved artwork crop stays within actual texture coordinates")
		art_by_stage[id] = entry
		paths[path] = true
		hashes[digest] = true
		art_report.append({"stageId":id,"stageNumber":index+1,"path":path,"sha256":digest,"sourceGeometryFingerprint":entry.get("sourceGeometryFingerprint",""),"rawHashVerified":raw_verified,"actualImportedResource":texture != null,"width":texture.get_width() if texture != null else 0,"height":texture.get_height() if texture != null else 0})
	check(art_by_stage.size() == 40 and paths.size() == 40 and hashes.size() == 40,"Release art has forty distinct identities, texture paths and image hashes")
	return failures.is_empty()

func verify_geography_basis(stages: Array) -> void:
	var geography: Variant = json_resource("res://native/campaign_geography.json",TYPE_DICTIONARY)
	if not geography is Dictionary:
		return
	var entries: Array = geography.get("stages",[])
	check(entries.size() == 40,"Packed historical geography includes all forty map production explanations")
	for index in range(mini(stages.size(),entries.size())):
		var geo: Dictionary = entries[index]
		var id: String = str(stages[index].id)
		var basis: String = str(geo.get("renderingBasisKo","")).strip_edges()
		check(str(geo.get("stageId","")) == id,id+": production basis stays attached to the selected campaign stage")
		check(not basis.is_empty() and basis.length() <= 130,id+": map production basis is present and concise")
		var urls: Array = geo.get("sources",[])
		check(not urls.is_empty(),id+": map production basis retains its historical sources")
		for url in urls:
			check(str(url).begins_with("https://") and not str(url).contains("\n"),id+": production reference is a complete HTTPS URL")
		basis_report.append({"stageId":id,"basis":basis,"characters":basis.length(),"sourceUrls":urls})

func verify_art_faults(stage: Dictionary,physical_fingerprint: String) -> void:
	var selected_index: int = -1
	for index in range(art_manifest.stages.size()):
		if str(art_manifest.stages[index].get("stageId","")) == str(stage.id):
			selected_index = index
	if selected_index < 0:
		check(false,"Artwork fault fixtures resolve an actual authored stage")
		return
	for kind in ["missing_hash","missing_art","stale_data","stale_geometry","partial","duplicate_art"]:
		var fixture: Dictionary = art_manifest.duplicate(true)
		match kind:
			"missing_hash": fixture.stages[selected_index].erase("sha256")
			"missing_art": fixture.stages[selected_index].path = "res://assets/battlefields-rendered/qa-intentionally-missing.png"
			"stale_data":
				fixture.sourceMapsSha256 = "0".repeat(64)
				fixture.stages[selected_index]["sourceDataSha256"] = "0".repeat(64)
			"stale_geometry": fixture.stages[selected_index].sourceGeometryFingerprint = "0".repeat(64)
			"partial": fixture.stages.pop_back()
			"duplicate_art":
				for entry in fixture.stages:
					entry.path = fixture.stages[selected_index].path
					entry.sha256 = fixture.stages[selected_index].sha256
		var fixture_path: String = "user://qa-art-"+kind+".json"
		var file: FileAccess = FileAccess.open(fixture_path,FileAccess.WRITE)
		check(file != null,kind+": negative art fixture can only be written in the isolated profile")
		if file == null:
			continue
		file.store_string(JSON.stringify(fixture))
		file.close()
		var record: Dictionary = RenderedArt.resolve(stage,physical_fingerprint,fixture_path,false)
		check(not bool(record.get("distributionReady",true)),kind+": invalid or incomplete artwork cannot be reported as distributable")
		if kind in ["missing_hash","missing_art","stale_data","stale_geometry"]:
			check(str(record.get("mode","")) == "native" and str(record.get("artPath","")) == "",kind+": rejected release artwork does not silently select a legacy image")
		var expected: Dictionary = {"missing_hash":"art_hash_missing","missing_art":"art_missing","stale_data":"source_data_changed","stale_geometry":"source_geometry_changed"}
		if expected.has(kind):
			check(str(record.get("reason","")) == str(expected[kind]),kind+": actual loader reports the rejected dependency")
		if kind == "partial":
			check(int(record.get("coverage",0)) == 39,"Partial art manifest preserves its actual 39-stage coverage")
		if kind == "duplicate_art":
			check(int(record.get("coverage",0)) == 40,"Repeated art cannot pass the uniqueness gate even with forty valid records")
		art_fault_report.append({"kind":kind,"mode":record.get("mode",""),"coverage":record.get("coverage",0),"distributionReady":record.get("distributionReady",false),"reason":record.get("reason",""),"fixture":ProjectSettings.globalize_path(fixture_path)})
	RenderedArt.release_shared_resources()

func collect_japanese(value: Variant, texts: Dictionary) -> void:
	if value is Dictionary:
		if value.get("jp") is String and not str(value.jp).strip_edges().is_empty():
			texts[str(value.jp).strip_edges()] = true
		for child in value.values():
			collect_japanese(child,texts)
	elif value is Array:
		for child in value:
			collect_japanese(child,texts)

func verify_offline_speech(curriculum: Dictionary, catalog: Dictionary, stages: Array) -> void:
	var manifest: Variant = json_resource(LearningAudio.MANIFEST_PATH,TYPE_DICTIONARY)
	var plans: Variant = json_resource("res://native/learning_plans.json",TYPE_DICTIONARY)
	var story: Variant = json_resource("res://native/campaign_story.json",TYPE_DICTIONARY)
	if not manifest is Dictionary or not plans is Dictionary or not story is Dictionary:
		return
	var clips: Dictionary = manifest.get("clips",{})
	check(bool(manifest.get("complete",false)) and int(manifest.get("wordCount",0)) == 900,"Packed offline voice manifest is complete for the actual 900-word curriculum")
	check(clips.size() == 3117 and int(manifest.get("uniqueTextCount",0)) == 3117 and int(manifest.get("generatedClipCount",0)) == 3117,"All 3,117 original learning/briefing audio entries are completed in the actual pack")
	check(bool(manifest.get("briefingComplete",false)) and int(manifest.get("briefingStageCount",0)) == 40,"Offline manifest explicitly includes all forty completed mission briefings")
	check(FileAccess.file_exists("res://assets/learning-voice/NOTICE.txt"),"Packed generated speech carries its required VOICEVOX Nemo credits")
	var actual_stage_ids: Dictionary = {}
	for stage in stages:
		actual_stage_ids[str(stage.id)] = true
	var texts: Dictionary = {}
	collect_japanese(curriculum,texts)
	collect_japanese(plans,texts)
	collect_japanese(catalog,texts)
	var briefings: int = 0
	for stage in story.get("stages",[]):
		var text: String = str(stage.get("briefingJP","")).strip_edges()
		check(not text.is_empty() and actual_stage_ids.has(str(stage.get("stageId",""))),"Mission briefing belongs to an actual packed historical stage")
		if text.is_empty():
			continue
		briefings += 1
		texts[text] = true
		var info: Dictionary = clips.get(text.sha256_text(),{})
		check(str(info.get("voiceType","")) == "mission-briefing" and int(info.get("styleId",0)) == 10001,str(stage.get("stageId",""))+": mission uses its approved separate male Nemo recording")
		check(str(info.get("reading","")) == str(stage.get("briefingReading","")) and str(info.get("ko","")) == str(stage.get("briefingKo","")),str(stage.get("stageId",""))+": actual recording metadata preserves the authored reading and Korean meaning")
	check(briefings == 40 and texts.size() == 3117,"Current packed authored learning texts and forty stage briefings exactly cover the 3,117-entry corpus")
	var reader: Node = LearningAudio.new()
	root.add_child(reader)
	reader.set_process(false)
	check(reader.setup(),"Actual packed offline reading backend opens its complete manifest without OS-TTS dispatch")
	check(reader._streams.is_empty(),"Offline setup does not preload 3,117 speech streams")
	var decoded: int = 0
	var maximum_cache_count: int = 0
	var maximum_cache_bytes: int = 0
	for key in clips:
		var info: Dictionary = clips[key]
		var text: String = str(info.get("text","")).strip_edges()
		var path: String = str(info.get("path",""))
		check(not text.is_empty() and str(key) == text.sha256_text() and texts.has(text),path+": actual audio entry belongs to its exact authored Japanese text")
		check(reader._safe_path(path) and reader.can_speak(text),path+": native offline resolver can find the actual packed clip")
		check(is_finite(float(info.get("duration",0))) and float(info.get("duration",0)) > .15 and float(info.get("peak",0)) > .005 and float(info.get("rms",0)) > .001,path+": manifest contains positive non-silent speech metadata")
		var stream: AudioStream = reader._stream_for(str(key))
		check(stream != null and is_finite(stream.get_length()) and stream.get_length() > .15,path+": actual native packed audio stream loads and decodes")
		if stream != null:
			decoded += 1
			check(absf(stream.get_length() - float(info.get("duration",0))) < .025,path+": decoded native audio length agrees with the actual clip metadata")
		var state: Dictionary = reader.diagnostics()
		maximum_cache_count = maxi(maximum_cache_count,int(state.cacheCount))
		maximum_cache_bytes = maxi(maximum_cache_bytes,int(state.cacheBytes))
		check(int(state.cacheCount) <= LearningAudio.CACHE_LIMIT and int(state.cacheBytes) <= LearningAudio.CACHE_BYTE_LIMIT,"Actual full-corpus decode retains the bounded native speech cache")
		if decoded % 128 == 0:
			await process_frame
	for text in texts:
		check(clips.has(str(text).sha256_text()),"Every current authored phrase has its exact packed offline recording: "+str(text))
	check(decoded == 3117,"All 3,117 real native audio streams decoded, including forty briefings")
	check(reader.player != null and not reader.player.playing and reader.played == 0,"Resource verification never dispatches OS speech or plays a standalone audio sample")
	speech_report = {"entries":clips.size(),"decoded":decoded,"authoredTexts":texts.size(),"briefings":briefings,"cacheCountMaximum":maximum_cache_count,"cacheBytesMaximum":maximum_cache_bytes,"played":reader.played,"complete":manifest.get("complete",false)}
	reader.shutdown()
	check(reader._streams.is_empty() and reader._cache_bytes == 0,"Actual packed speech backend releases its decoded cache on shutdown")
	reader.free()

func actual_mesh_fingerprint(field: Node3D) -> String:
	# Hash the built vertex/index/instance data, never labels or stage IDs.
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for child in field.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = child.mesh
		if mesh == null:
			continue
		digest.update(var_to_bytes(child.transform))
		for surface in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			digest.update(vertices.to_byte_array())
			if arrays[Mesh.ARRAY_INDEX] != null:
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				digest.update(indices.to_byte_array())
	for child in field.find_children("*","MultiMeshInstance3D",true,false):
		var instances: MultiMesh = child.multimesh
		if instances == null or instances.mesh == null:
			continue
		for surface in range(instances.mesh.get_surface_count()):
			var arrays: Array = instances.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			digest.update(vertices.to_byte_array())
			if arrays[Mesh.ARRAY_INDEX] != null:
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				digest.update(indices.to_byte_array())
		for index in range(instances.instance_count):
			digest.update(var_to_bytes(instances.get_instance_transform(index)))
	return digest.finish().hex_encode()

func road_contains(field: Node3D, start: Vector2, end: Vector2) -> bool:
	for segment in field.road_segments:
		var forward: bool = Vector2(segment.a).is_equal_approx(start) and Vector2(segment.b).is_equal_approx(end)
		var reverse: bool = Vector2(segment.a).is_equal_approx(end) and Vector2(segment.b).is_equal_approx(start)
		if forward or reverse:
			return true
	return false

func verify_hybrid_stage(stage: Dictionary, troops: Control, game: Node2D) -> Dictionary:
	var note: String = str(stage.id) + ": "
	check(is_instance_valid(troops.battlefield),note+"renderer builds the actual physical height provider")
	if not is_instance_valid(troops.battlefield):
		return {}
	var field: Node3D = troops.battlefield
	var info: Dictionary = field.diagnostics()
	var render_info: Dictionary = troops.diagnostics()
	var layer: Dictionary = field.render_layer_contract()
	var approved: Dictionary = art_by_stage.get(str(stage.id),{})
	if str(layer.get("mode","native")) != "rendered":
		fallback_count += 1
	check(troops.stage.id == stage.id and field.stage.id == stage.id and game.config.id == stage.id,note+"Game, renderer and physical terrain consume the same packed stage definition")
	check(field.get_parent() == troops.world and bool(render_info.nativeBattlefield) and bool(render_info.realShadowCasting),note+"terrain and articulated actors inhabit the same world and real shadow lighting")
	check(not bool(info.get("photoFloor",true)) and not bool(render_info.get("photoGround",true)) and game.background == null,note+"height-preserving hybrid execution never loads or substitutes an old background photograph")
	check(bool(info.get("sourceDataContractValid",false)) and field.ground_mesh != null,note+"actual packed geometry satisfies the shared authored source contract")
	check(str(layer.get("mode","")) == "rendered" and bool(render_info.get("renderedArtwork",false)),note+"approved hybrid art is actually selected with no native or legacy fallback")
	check(bool(layer.get("distributionReady",false)) and int(layer.get("coverage",0)) == 40 and bool(layer.get("sourceDataVerified",false)),note+"actual selected release manifest covers all forty source-verified stages")
	check(str(layer.get("artPath","")) == str(approved.get("path","")) and str(layer.get("artSha256","")) == str(approved.get("sha256","")),note+"actual runtime artwork identity agrees with this stage's approved entry")
	check(str(approved.get("sourceGeometryFingerprint","")) == str(info.get("physicalGeometryFingerprint","")),note+"actual physical source fingerprint agrees with the frozen art blueprint")
	if FileAccess.file_exists(str(approved.get("path",""))):
		check(bool(layer.get("rawArtHashVerified",false)),note+"source/raw-resource mode verifies the actual image bytes")
	check(bool(layer.get("heightPreserved",false)) and bool(layer.get("normalizedUvHeightIndependent",false)) and not bool(layer.get("flatPhotoPlane",true)),note+"art follows real terrain height while its anchors remain normalized")
	check(bool(layer.get("dynamicShadowReceiver",false)) and int(layer.get("shadowReceiverLayer",0)) == 1 and field.ground_mesh.layers == 1,note+"live soldiers cast onto the actual rendered terrain receiver")
	check(not bool(layer.get("staticGeometryVisible",true)) and int(info.get("meshNodes",0)) == 1 and int(info.get("terrainTriangles",0)) == 12288,note+"the actual hybrid scene uses one relief mesh without duplicate static scenery")
	check(int(info.get("roadTriangles",-1)) == 0 and int(info.get("waterTriangles",-1)) == 0 and int(info.get("gateCount",-1)) == 0 and int(info.get("scannedModels",-1)) == 0,note+"roads, water and buildings are rendered in the approved art")
	check(int(info.get("roadSegmentCount",0)) > 0 and field.objects.size() == stage.get("objectives",[]).size(),note+"logical authored routes and all objective anchors remain available")
	check(float(info.get("heightMaximum",0)) - float(info.get("heightMinimum",0)) > .025 and field.heights.size() == (Battlefield.GRID_X+1)*(Battlefield.GRID_Y+1),note+"actual native field has sampled physical relief")
	check(is_equal_approx(float(info.get("worldWidth",0)),18.5) and is_equal_approx(field.width,troops.world_width) and is_equal_approx(field.depth,troops.world_depth),note+"terrain and human-scale renderer share actual world dimensions")
	check(is_equal_approx(field.elevation,50.0) and is_equal_approx(troops.elevation_degrees,50.0),note+"gameplay and artwork share the actual 50 degree camera")
	var ground_material: ShaderMaterial = field.ground_mesh.material_override as ShaderMaterial
	check(ground_material != null and ground_material.shader != null and ground_material.shader.code.contains("uniform sampler2D artwork"),note+"actual relief mesh binds the hybrid artwork shader")
	if ground_material != null:
		var artwork: Texture2D = ground_material.get_shader_parameter("artwork") as Texture2D
		check(artwork != null and artwork.get_width() == int(approved.get("width",0)) and artwork.get_height() == int(approved.get("height",0)),note+"actual ground binds the approved texture at its authored dimensions")
		check(artwork == TerrainMaterials.rendered_art_texture(str(approved.get("path","")),str(approved.get("sha256",""))),note+"actual shader binds this selected stage's real loaded texture object")
		check(ground_material.get_shader_parameter("normalized_bounds") == layer.get("normalizedBounds",Vector4(-1,-1,-1,-1)),note+"actual material uses the selected stage's normalized art crop")
	var ground_arrays: Array = field.ground_mesh.mesh.surface_get_arrays(0)
	var ground_vertices: PackedVector3Array = ground_arrays[Mesh.ARRAY_VERTEX]
	check(ground_vertices.size() == field.heights.size() and ground_arrays[Mesh.ARRAY_INDEX] != null and ground_arrays[Mesh.ARRAY_INDEX].size() == 12288*3,note+"actual terrain mesh contains the declared indexed grid")
	var anchors: PackedVector2Array = ground_arrays[Mesh.ARRAY_TEX_UV2]
	check(anchors.size() == ground_vertices.size(),note+"every physical vertex retains its actual normalized art anchor")
	var maximum_height_error: float = 0.0
	for index in range(mini(ground_vertices.size(),anchors.size())):
		var vertex: Vector3 = ground_vertices[index]
		var point: Vector2 = anchors[index]
		maximum_height_error = maxf(maximum_height_error,maxf(field.world_point(point).distance_to(vertex),absf(field.height_at(point)-vertex.y)))
	check(maximum_height_error < .0001,note+"world_point and height_at agree with all actual normalized terrain vertices")
	check(game.paths.size() == stage.paths.size(),note+"native combat retains every authored lane")
	for path_index in range(stage.paths.size()):
		var source_points: Array = stage.paths[path_index].points
		check(game.paths[path_index].points.size() == source_points.size(),note+"combat route retains its authored point count")
		for point_index in range(source_points.size()):
			var source: Dictionary = source_points[point_index]
			var point: Vector2 = Vector2(float(source.x),float(source.y))
			check(game.paths[path_index].points[point_index].is_equal_approx(point),note+"actual Game route point matches the packed terrain source")
			var position_value: Vector3 = field.world_point(point)
			check(position_value.is_finite() and absf(position_value.y-field.height_at(point)) < .0001 and troops.normalized_to_world(point).distance_to(position_value) < .0001,note+"route and actor foot use the same physical height provider")
			var projected: Vector2 = troops.camera.unproject_position(position_value)
			check(projected.distance_to(point*troops.field_size) < .5,note+"actual elevated route projects onto its exact gameplay coordinate")
			if point_index > 0:
				var previous: Dictionary = source_points[point_index-1]
				check(road_contains(field,Vector2(float(previous.x),float(previous.y)),point),note+"actual logical road retains this precise combat route segment")
	var wet_regions: int = 0
	for rect in game.ground_combat.water_rects:
		var matched: bool = false
		for region in field.water_regions:
			if region.rect == rect:
				matched = true
		check(matched,note+"physical terrain retains the exact gameplay blocking-water rectangle")
		check(not game.ground_combat.land_segment_safe(rect.get_center(),rect.get_center(),0),note+"actual land movement API still rejects the center of blocking water")
		wet_regions += 1
	check(not game.ground_combat.land_segment_safe(Vector2(INF,0),Vector2.ZERO),note+"actual land movement API rejects a nonfinite endpoint")
	for region in field.water_regions:
		var probe: Vector2 = region.rect.get_center()
		var bridged: bool = false
		for bridge in field.bridge_regions:
			if bridge.rect.has_point(probe): bridged = true
		check(field._is_water(probe) == (not bridged),note+"actual terrain water provider preserves its bridge exclusion")
	for objective in game.objectives:
		var found: bool = false
		for object in field.objects:
			if str(object.get("kind","")) == "defended_gate" and str(object.get("renderedBy","")) == "artwork":
				found = Vector2(object.point).is_equal_approx(objective.position)
				if found:
					break
		check(found,note+"rendered objective anchor matches the actual gameplay base")
	var placement_checks: int = 0
	game.gold = 10000
	game.set_input_enabled(true)
	check(game.begin_placement("archer"),note+"actual support placement API starts on the rendered battlefield")
	for hint in game.placement_hints:
		if hint.x < 0: continue
		var preview: Dictionary = game.placement_preview(hint)
		if not bool(preview.get("valid",false)): continue
		var actual: Vector2 = game._point(preview.position)
		check(field.world_point(actual).is_finite() and troops.normalized_to_world(actual).distance_to(field.world_point(actual)) < .0001,note+"valid placement shares the actual relief provider")
		troops.sync_placement_preview(preview)
		check(is_instance_valid(troops.placement_actor) and troops.placement_actor.visible and troops.placement_actor.position.distance_to(field.world_point(actual)) < .0001,note+"actual placement ghost stands at the validated elevated anchor")
		var gold_before: int = game.gold
		check(game.place_unit(hint.x,hint.y) and game.recruitment_queue.size() == 1,note+"actual placement commits one production reservation")
		if not game.recruitment_queue.is_empty():
			var job: Dictionary = game.recruitment_queue[0]
			check(Vector2(job.position).distance_to(actual) < .0001 and game.gold == gold_before-int(job.cost),note+"production reserves the exact validated anchor and cost")
			check(game.cancel_recruitment(int(job.id)) and game.gold == gold_before and game.recruitment_queue.is_empty(),note+"cancelling the isolated test reservation releases its anchor and refunds its cost")
		placement_checks += 1
		break
	check(placement_checks == 1,note+"an authored support emplacement remains usable")
	game.pending.clear()
	game.placement_cursor_visible = false
	game.set_input_enabled(false)
	troops.sync_placement_preview({"active":false,"visible":false})
	var rebuilds: int = field.rebuild_count
	troops.set_stage(stage)
	check(field.rebuild_count == rebuilds,note+"unchanged native stage reuses its geometry instead of rebuilding")
	var sample: Vector2 = game.paths[0].points[int(game.paths[0].points.size()/2)]
	var actor_state: Dictionary = {"id":901,"type":"archer","friendly":true,"position":sample,"x":sample.x,"y":sample.y,"hp":100.0,"maxHp":100.0,"animation":"idle","animationClock":0.0,"motionTime":0.0,"motionReset":true,"aimX":0.0,"aimY":-1.0,"sailing":false}
	troops.sync_actor_states([actor_state])
	check(troops.actors.has("901:0") and troops.contact_shadows.has("901:0"),note+"actual soldier and contact shadow are created on this terrain")
	if troops.actors.has("901:0") and troops.contact_shadows.has("901:0"):
		var actor: Node3D = troops.actors["901:0"]
		var contact: Node3D = troops.contact_shadows["901:0"]
		check(actor.position.distance_to(field.world_point(sample)) < .0001 and contact.position.distance_to(actor.position+Vector3(0,.002,0)) < .0001,note+"real actor foot/contact geometry shares the terrain height")
		var hp_anchor: Dictionary = troops.health_anchor_for(901)
		check(game.presentation_mirrored == troops.presentation_mirrored,note+"actual Game and renderer agree on the display orientation")
		check(not hp_anchor.is_empty() and Vector2(hp_anchor.get("footPosition",Vector2(-999,-999))).distance_to(game.view_point(sample)*troops.field_size) < .5,note+"actual public HP provider follows the camera-projected actor foot in display coordinates")
		if not hp_anchor.is_empty():
			var head: Vector2 = hp_anchor.headPosition
			check(head.is_finite() and head.y < Vector2(hp_anchor.footPosition).y and float(hp_anchor.hp) == 100 and float(hp_anchor.maxHp) == 100,note+"actual HP anchor belongs above this soldier and retains real displayed HP")
			var layout: Dictionary = game.healthbar_layout(actor_state,true)
			var expected_head: Vector2 = game.get_global_transform_with_canvas().affine_inverse()*(troops.get_global_transform_with_canvas()*head)
			check(bool(layout.projected) and Vector2(layout.anchor).distance_to(expected_head) < .5 and is_equal_approx(float(layout.ratio),1.0) and str(layout.text).is_empty(),note+"actual Game HP bar uses the displayed renderer head, real health ratio and no numeric label")
			for friendly in [true,false]:
				var actual_bar: Dictionary = game.healthbar_layout(actor_state,bool(friendly))
				var fill: Color = Color(str(actual_bar.color))
				var background: Color = Color(str(actual_bar.backgroundColor))
				check(is_equal_approx(actual_bar.rect.size.y,2.0) and is_equal_approx(actual_bar.fillRect.size.y,2.0),note+"actual shared 3D HP bar is a two-pixel solid line")
				check(fill.a==1.0 and background.a==1.0 and maxf(background.r,maxf(background.g,background.b))<.2,note+"actual HP fill and dark background are fully opaque")
				check((fill.g>fill.r*1.5 and fill.g>fill.b*1.5) if friendly else (fill.r>fill.g*1.5 and fill.r>fill.b*1.5),note+"actual friendly HP is green and hostile HP is red")
	troops.sync_actor_states([])
	info["actualMeshFingerprint"] = actual_mesh_fingerprint(field)
	info["actualVertexHeightMaximumError"] = maximum_height_error
	info["blockingWaterRegionsChecked"] = wet_regions
	info["placementReservationsChecked"] = placement_checks
	info["approvedArtResource"] = layer.get("artPath","")
	var material_cache: Dictionary = TerrainMaterials.cache_diagnostics()
	check(int(material_cache.get("renderedArtTextureCount",99)) <= 3 and int(material_cache.get("renderedArtTextureLimit",0)) == 3,note+"actual rendered texture cache stays within the three-texture LRU limit")
	return info

func run() -> void:
	if not safe_environment():
		quit(2)
		return
	# This is also a guard against accidentally validating the loose project.
	var working_directory: String = DirAccess.open(".").get_current_dir()
	if not source_only:
		check(not FileAccess.file_exists(working_directory.path_join("project.godot")),"Actual verifier working directory contains no loose Godot project")
		check(not DirAccess.dir_exists_absolute(working_directory.path_join("native")),"Actual verifier working directory contains no loose runtime source")
		check(not FileAccess.file_exists("res://tests/qa_pack_3d.gd"),"Tests are excluded from the production pack")
		check(not FileAccess.file_exists("res://tools/build.ps1"),"Build tools are excluded from the production pack")
		check(not DirAccess.dir_exists_absolute("res://assets/models3d/rocketbox"),"Rejected Rocketbox research assets are excluded from the production pack")
		check(not DirAccess.dir_exists_absolute("res://assets/models3d/makehuman"),"Rejected MakeHuman research assets are excluded from the production pack")
		check(not ResourceLoader.exists("res://native/imported_human_head.gd"),"Unused external-human research helper is excluded from the production pack")
		check(not ResourceLoader.exists("res://assets/units-standing/idle-core-v1.png"),"Rejected core portrait candidate is excluded from the production pack")
		if not failures.is_empty():
			print("PACK_3D_QA_MOUNT ",JSON.stringify({"checks":checks,"failures":failures,"workingDirectory":working_directory,"mainPack":pack_path}))
			quit(2)
			return
	var catalog=json_resource("res://native/units.json",TYPE_DICTIONARY)
	var stages=json_resource("res://native/maps.json",TYPE_ARRAY)
	var music=json_resource("res://native/music.json",TYPE_DICTIONARY)
	var materials=json_resource("res://native/material_sources.json",TYPE_DICTIONARY)
	var visual_profiles=json_resource("res://native/visual_profiles.json",TYPE_DICTIONARY)
	var curriculum=json_resource("res://native/curriculum.json",TYPE_DICTIONARY)
	var core_portraits=json_resource("res://assets/units-standing/core.json",TYPE_DICTIONARY)
	var support_portraits=json_resource("res://assets/units-standing/support.json",TYPE_DICTIONARY)
	if not catalog is Dictionary or not stages is Array or not music is Dictionary or not materials is Dictionary or not curriculum is Dictionary:
		quit(1)
		return
	if not verify_rendered_art_manifest(stages):
		print("PACK_3D_QA_ART_GATE ",JSON.stringify({"checks":checks,"failures":failures,"mode":"source-resource-only" if source_only else "actual-pack","approvedStageCount":art_by_stage.size(),"manifestComplete":art_manifest.get("complete",false)}))
		quit(2)
		return
	verify_geography_basis(stages)
	verify_exclusions(stages)
	verify_coastline()
	verify_terrain_resources()
	verify_fonts()
	await verify_offline_speech(curriculum,catalog,stages)
	check(catalog.units.size()==8,"Embedded catalog contains the eight actual classes")
	check(stages.size()==40,"Embedded maps contain forty stages")
	check(music.tracks.size()==40,"Embedded music manifest contains forty stage assignments")
	check(visual_profiles is Dictionary and visual_profiles.profiles.size()==40,"Embedded renderer lighting profiles cover all stages")
	var word_count: int=0
	for tier in curriculum.values():
		for lesson in tier:
			word_count+=lesson.newWords.size()
	check(word_count==900,"Embedded curriculum retains nine hundred new words")
	for script_path in ["res://native/human_face_3d.gd","res://native/human_body_geometry.gd","res://native/sengoku_armor_geometry.gd","res://native/sengoku_equipment_geometry.gd","res://native/actor_materials.gd","res://native/troops_3d.gd","res://native/sengoku_actor_3d.gd","res://native/sengoku_ui.gd","res://native/front_end.gd","res://native/campaign_atlas.gd","res://native/battlefield_preview.gd","res://native/barracks.gd","res://native/barracks_portrait.gd","res://native/battlefield_3d.gd","res://native/battlefield_materials.gd","res://native/rendered_battlefield_helpers.gd","res://native/battle_camera.gd","res://native/game.gd","res://native/ground_combat.gd","res://native/game_fonts.gd","res://native/learning_audio.gd","res://native/voice_director.gd"]:
		check(ResourceLoader.exists(script_path),script_path+": runtime geometry/shader source resource exists")
		check(ResourceLoader.load(script_path) is GDScript,script_path+": embedded script actually loads")
	var authored_portraits: Array = []
	var standing_sheets: Dictionary = {}
	var standing_rows: Dictionary = {}
	if core_portraits is Dictionary and support_portraits is Dictionary:
		check(core_portraits.sprites.size()==4 and support_portraits.sprites.size()==4,"Embedded standing manifests retain four original core classes and four support classes")
		for definition in catalog.units:
			var id: String = str(definition.id)
			var source: Dictionary = Portrait.resolve_source(id)
			check(not source.is_empty(),id+": packed standing source resolves for this actual class")
			if source.is_empty(): continue
			var core_class: bool = core_portraits.sprites.has(id)
			var expected: Dictionary = core_portraits.sprites.get(id,{}) if core_class else support_portraits.sprites.get(id,{})
			var expected_manifest: String = "res://assets/units-standing/core.json" if core_class else "res://assets/units-standing/support.json"
			check(source.manifestPath==expected_manifest and source.path==expected.get("path","") and int(source.row)==int(expected.get("row",-1)),id+": actual resolver uses the requested manifest's own PNG and row")
			check(int(source.frames)==6 and int(source.columns)==6 and int(source.rows)==4,id+": packed source retains six authored idle poses")
			if not standing_sheets.has(source.path): standing_sheets[source.path]=texture_resource(source.path)
			var first: AtlasTexture = Portrait.first_frame_texture(id)
			check(first!=null and first.atlas!=null and first.atlas.resource_path==source.path and Rect2(Vector2.ZERO,first.atlas.get_size()).encloses(first.region),id+": helper actually binds an in-bounds portrait crop from the packed texture")
			var row_key: String = str(source.path)+":"+str(source.row)
			check(not standing_rows.has(row_key),id+": actual source row is not borrowed from another class")
			standing_rows[row_key]=id
			authored_portraits.append({"unit":id,"path":source.path,"manifest":source.manifestPath,"row":source.row,"frames":source.frames,"fps":source.fps})
		check(authored_portraits.size()==8 and standing_rows.size()==8 and standing_sheets.size()==5,"Eight authored standing identities load from four approved original sheets and one support sheet")
	for recipe in materials.materials:
		check(recipe.files.size()==3,str(recipe.id)+": material manifest includes color/normal/roughness")
		for entry in recipe.files:
			material_paths.append(str(entry.path))
			texture_resource(str(entry.path))
	check(material_paths.size()==9,"All nine PBR texture resources load from the embedded pack")
	var combined: ShaderMaterial=Materials.material()
	var atlas=texture_resource(ATLAS_PATH)
	check(atlas!=null and atlas.get_width()==1254 and atlas.get_height()==1254,"Packed generated atlas preserves its actual 1254-square dimensions")
	check(bool(combined.get_shader_parameter("use_sengoku_surface")),"Actual packed material enables the Sengoku atlas")
	var bound_atlas=combined.get_shader_parameter("sengoku_surface")
	check(bound_atlas is Texture2D and bound_atlas.resource_path==ATLAS_PATH and bound_atlas.get_width()==1254,"Actual shader parameter binds the packed generated atlas")
	# Human and mounted body geometry share one helper; exercise both entry points.
	var body_geometry: Dictionary={}
	for sample in [{"name":"human","parts":Body.build("samurai",false)},{"name":"mounted","parts":Body.build_horse(false)}]:
		var index_count: int=0
		var vertex_count: int=0
		var indexed: bool=true
		for piece in sample.parts:
			var mesh: ArrayMesh=piece.mesh
			for surface in range(mesh.get_surface_count()):
				var arrays=mesh.surface_get_arrays(surface)
				vertex_count+=arrays[Mesh.ARRAY_VERTEX].size()
				var indices=arrays[Mesh.ARRAY_INDEX]
				indexed=indexed and indices!=null and indices.size()>0
				if indices!=null: index_count+=indices.size()
		check(sample.parts.size()>0 and vertex_count>0 and index_count>0,str(sample.name)+": exported body helper actually constructs geometry")
		check(indexed,str(sample.name)+": exported body helper returns indexed meshes")
		body_geometry[str(sample.name)]={"parts":sample.parts.size(),"vertices":vertex_count,"triangles":index_count/3}
	check(combined.shader!=null and combined.shader.code.contains("surface_recipe = CUSTOM0"),"Actual packed actor material creates its geometry-recipe shader")
	check(combined.shader.code.contains("sampled_colour") and combined.shader.code.contains("OUTPUT_IS_SRGB"),"Updated packed material includes calibrated renderer-aware albedo sampling")
	check(combined.shader.code.contains("NORMAL_MAP") and combined.shader.code.contains("METALLIC") and combined.shader.code.contains("ROUGHNESS"),"Packed actor shader retains normal/PBR surface channels")
	for family in ["steel","cloth","leather"]:
		for channel in ["normal","rough","colour"]:
			var parameter: String=family+"_"+channel
			check(combined.get_shader_parameter(parameter) is Texture2D,parameter+": actual shader parameter has a loaded texture")
	var world=Node3D.new()
	root.add_child(world)
	for definition in catalog.units:
		for evolution in range(3):
			var portrait_path: String="res://assets/portraits3d/%s-e%d.png" % [definition.id,evolution]
			portrait_paths.append(portrait_path)
			texture_resource(portrait_path)
			var actor=Actor.new()
			world.add_child(actor)
			actor.configure(str(definition.id),false,31,false,evolution)
			actor.apply_state({"animation":"walk","animationClock":0.18,"aimX":0.0,"aimY":-1.0})
			var diagnostics: Dictionary=actor.diagnostics()
			check(str(diagnostics.type)==str(definition.id) and int(diagnostics.evolution)==evolution,str(definition.id)+": requested class/evolution is configured")
			check(int(diagnostics.triangleEstimate)>1000 and int(diagnostics.unreferencedVertices)==0,str(definition.id)+": generated model has real indexed geometry")
			var indexed: bool=true
			var shader_bound: bool=true
			var custom_data: bool=true
			for instance in actor.meshes:
				shader_bound=shader_bound and instance.material_override is ShaderMaterial and instance.material_override.shader!=null
				for surface in range(instance.mesh.get_surface_count()):
					var arrays=instance.mesh.surface_get_arrays(surface)
					indexed=indexed and arrays[Mesh.ARRAY_INDEX]!=null and arrays[Mesh.ARRAY_INDEX].size()>0
					custom_data=custom_data and arrays[Mesh.ARRAY_CUSTOM0]!=null and arrays[Mesh.ARRAY_CUSTOM0].size()>0
			check(indexed,str(definition.id)+": all rendered surfaces have indices")
			check(shader_bound,str(definition.id)+": all rendered batches bind the PBR shader")
			check(custom_data,str(definition.id)+": all rendered batches retain per-vertex material recipes")
			models.append(diagnostics)
			actor.queue_free()
			await process_frame
	check(models.size()==24 and portrait_paths.size()==24,"Twenty-four real models and corresponding portraits load")
	var music_by_stage: Dictionary={}
	for track in music.tracks: music_by_stage[str(track.stageId)]=track
	var troops=Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1100,620))
	troops.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var game: Node2D = Game.new()
	game.three_d_enabled = true
	root.add_child(game)
	game.set_process(false)
	game.set_input_enabled(false)
	game.set_field_rect(Rect2(Vector2.ZERO,Vector2(1100,620)))
	troops.bind_battle(game)
	check(game.render_projection_provider == troops,"Actual packed renderer bind_battle connects the native HP projection provider")
	var physical_fingerprints: Dictionary = {}
	var rendered_fingerprints: Dictionary = {}
	for stage in stages:
		check(music_by_stage.has(str(stage.id)),str(stage.id)+": stage has music manifest entry")
		var track: Dictionary=music_by_stage.get(str(stage.id),{})
		var stream=ResourceLoader.load(str(track.get("path","")),"",ResourceLoader.CACHE_MODE_IGNORE)
		check(stream is AudioStream and stream.get_length()>20.0,str(stage.id)+": actual embedded audio stream is playable")
		game.load_map(stage,10)
		troops.set_stage(stage)
		troops.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var geometry: Dictionary = verify_hybrid_stage(stage,troops,game)
		var physical_key: String = str(geometry.get("physicalGeometryFingerprint",""))
		var rendered_key: String = str(geometry.get("actualMeshFingerprint",""))
		check(not physical_key.is_empty() and not physical_fingerprints.has(physical_key),str(stage.id)+": real authored physical geometry is distinct even after ignoring stage names/identifiers")
		check(not rendered_key.is_empty() and not rendered_fingerprints.has(rendered_key),str(stage.id)+": actual instantiated terrain/scenery mesh data is distinct")
		physical_fingerprints[physical_key] = true
		rendered_fingerprints[rendered_key] = true
		geometry["stage"] = stage.id
		geometry["audio"] = track.get("path","")
		geometry["seconds"] = stream.get_length() if stream is AudioStream else 0.0
		map_resources.append(geometry)
		await process_frame
	check(physical_fingerprints.size() == 40 and rendered_fingerprints.size() == 40,"All forty authored and actually built 3D battlefields have unique physical geometry")
	check(fallback_count == 0 and map_resources.size() == 40,"Actual forty-stage release has zero native or legacy artwork fallbacks")
	if not map_resources.is_empty():
		verify_art_faults(stages[0],str(map_resources[0].get("physicalGeometryFingerprint","")))
	# Verify the new renderer connection in the installed artifact, not loose source.
	var contact_state={"id":901,"type":"archer","friendly":true,"x":0.5,"y":0.5,"hp":100.0,"maxHp":100.0,"animation":"idle","animationClock":0.0,"motionTime":0.0,"aimX":0.0,"aimY":-1.0,"sailing":false}
	troops.sync_actor_states([contact_state])
	check(troops.contact_shadows.size()==1 and troops.contact_shadows.has("901:0") and troops.contact_shadows["901:0"].visible,"Packed renderer adds ground contact to an actual standing soldier")
	if troops.contact_shadows.has("901:0"):
		var contact: MeshInstance3D=troops.contact_shadows["901:0"]
		var soldier: Node3D=troops.actors["901:0"]
		check(contact.position.x==soldier.position.x and contact.position.z==soldier.position.z and contact.scale==soldier.scale,"Packed contact follows the real soldier's mapped position and scale")
		check(is_equal_approx(contact.position.y,soldier.position.y + .002) and soldier.position.distance_to(troops.battlefield.world_point(Vector2(.5,.5))) < .0001,"Packed contact and real soldier share the actual elevated terrain, with only a .002 contact offset")
		contact_state.sailing=true
		troops.sync_actor_states([contact_state])
		check(not contact.visible,"Packed boat state hides standing ground contact")
		contact_state.sailing=false
		contact_state.animation="death"
		troops.sync_actor_states([contact_state])
		check(not contact.visible,"Packed death state hides standing ground contact")
	troops.sync_actor_states([])
	check(troops.actors.is_empty() and troops.contact_shadows.is_empty(),"Packed renderer removes ground contact when its soldier is removed")
	var cache_before_release: Dictionary = Battlefield.shared_cache_diagnostics()
	troops.free()
	game.free()
	world.free()
	await process_frame
	Battlefield.release_shared_resources()
	for frame in range(24):
		await process_frame
	var cache_after_release: Dictionary = Battlefield.shared_cache_diagnostics()
	check(int(cache_after_release.modelVariantGroups) == 0 and int(cache_after_release.primitiveMeshes) == 0 and int(cache_after_release.materials.textureCount) == 0 and int(cache_after_release.materials.materialCount) == 0,"Actual packed terrain model/material/texture caches release at application shutdown")
	check(int(cache_after_release.materials.get("renderedArtTextureCount",-1)) == 0 and not bool(cache_after_release.materials.get("renderedShaderCached",true)),"Actual rendered artwork textures and shader release after worlds are freed")
	check(RenderedArt.manifest_cache.is_empty() and RenderedArt.hash_cache.is_empty(),"Actual manifest and hash caches release with the shared renderer")
	check(not FileAccess.file_exists("user://progress.json"),"Resource verifier never creates a default player save")
	var report={"checks":checks,"failures":failures,"pass":failures.is_empty(),"verificationMode":"source-resource-only" if source_only else "actual-pack","packedArtifactVerified":not source_only and failures.is_empty(),"mainPack":pack_path,"mainPackSha256":FileAccess.get_sha256(pack_path) if not pack_path.is_empty() else "","godot":Engine.get_version_info().string,"resourceRoot":ProjectSettings.globalize_path("res://"),"workingDirectory":working_directory,"userPath":ProjectSettings.globalize_path("user://"),"models":models,"portraits":portrait_paths,"authoredStandingPortraits":authored_portraits,"materialTextures":material_paths,"terrainTextures":terrain_paths,"naturalModels":natural_models,"fonts":font_paths,"offlineSpeech":speech_report,"originalCoastline":coastline_report,"approvedArtwork":art_report,"artworkFaults":art_fault_report,"fallbackCount":fallback_count,"mapRenderingBasis":basis_report,"resourceInventoryCount":resource_inventory.size(),"sengokuAtlas":{"path":ATLAS_PATH,"width":atlas.get_width() if atlas!=null else 0,"height":atlas.get_height() if atlas!=null else 0,"enabled":bool(combined.get_shader_parameter("use_sengoku_surface"))},"bodyHelper":body_geometry,"stages":map_resources,"sharedCachesBeforeShutdown":cache_before_release,"sharedCachesAfterShutdown":cache_after_release,"scope":"Headless hybrid terrain/material binding, forty actual imported approved textures with complete source/hash/blueprint identities and zero fallback, actual indexed UV2-height mesh/navigation/water/placement/HP providers, six invalid-art fixtures, every offline speech stream, map basis sources, coastline, fonts and actors/standing portraits/music. A remapped PCK texture can lack raw PNG bytes; its approved metadata hash is checked with actual ResourceLoader loading and source-data verification. Actual-pack mode additionally verifies excluded source/photo/build/OS-model assets from a cwd with no loose project. Source-only mode cannot claim packaged validation. No GPU, OS-TTS dispatch, audio playback, campaign balance claim, browser navigation, or production writes."}
	var file=FileAccess.open("user://qa_pack_3d.json",FileAccess.WRITE)
	report["launcherAndResourceGuards"] = guard_metadata
	check(file != null,"Actual verifier can write its result only within the guarded workspace profile")
	report["checks"] = checks
	report["pass"] = failures.is_empty()
	report["packedArtifactVerified"] = not source_only and failures.is_empty()
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("PACK_3D_QA ",JSON.stringify({"checks":checks,"failures":failures,"mode":report.verificationMode,"packedArtifactVerified":report.packedArtifactVerified,"models":models.size(),"portraits":portrait_paths.size(),"materialTextures":material_paths.size(),"terrainTextures":terrain_paths.size(),"naturalModels":natural_models.size(),"audioDecoded":speech_report.get("decoded",0),"briefings":speech_report.get("briefings",0),"fonts":font_paths.size(),"stages":map_resources.size(),"resourceRoot":report.resourceRoot,"workingDirectory":working_directory,"report":ProjectSettings.globalize_path("user://qa_pack_3d.json")}))
	quit(0 if failures.is_empty() else 1)
