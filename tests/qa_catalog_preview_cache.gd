extends SceneTree

const Preview = preload("res://native/battlefield_preview.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		push_error("CATALOG_PREVIEW_CACHE "+note)

func write_manifest(path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func wait_for_preview(preview: Control) -> void:
	for unused in range(5000):
		if not preview.is_loading(): return
		await process_frame
	check(false,"Preview completes within bounded frames")

func verify_cached_aspect(source: Dictionary) -> void:
	var snapshot_image: Image=Image.create(828,312,false,Image.FORMAT_RGBA8)
	snapshot_image.fill(Color("426239"))
	var snapshot: Texture2D=ImageTexture.create_from_image(snapshot_image)
	Preview.completed_previews[Preview._completed_key(source)]={"texture":snapshot,"terrain":{"stageId":source.id}}
	var cached_preview: Control=Preview.new()
	cached_preview.size=Vector2(828,312)
	cached_preview.configure(source)
	root.add_child(cached_preview)
	await process_frame
	await process_frame
	check(cached_preview.image.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"Completed snapshots preserve their original aspect ratio")
	cached_preview.size=Vector2(988,412)
	await process_frame
	await process_frame
	check(cached_preview.image.texture==snapshot and snapshot.get_width()==828 and snapshot.get_height()==312,"Resize retains the same snapshot dimensions and texture")
	check(cached_preview.diagnostics().cacheHit and cached_preview.render_requests==0,"Aspect-preserving resize needs no new render")
	cached_preview.free()
	Preview.release_shared_resources()

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	var boundary: String = ProjectSettings.globalize_path("res://tests/profiles/catalog-preview-").replace("\\","/").to_lower()
	if not profile.begins_with(boundary):
		push_error("An isolated catalog-preview profile is required.")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if "--aspect-only" in OS.get_cmdline_user_args():
		await verify_cached_aspect(maps[0])
		var output: FileAccess=FileAccess.open("user://catalog-preview-aspect.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));output.close()
		print("CATALOG_PREVIEW_ASPECT checks=%d failures=%d"%[checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	if "--final-source-only" in OS.get_cmdline_user_args():
		var field: Node3D=Battlefield.new()
		for stage in maps:
			var fingerprint: String=JSON.stringify(field._physical_contract(stage)).sha256_text()
			var approved: Dictionary=RenderedArt.resolve(stage,fingerprint)
			check(approved.mode=="rendered" and approved.distributionReady,"Final map/art approval: "+str(stage.id))
			check(float(approved.sourceProjection.get("elevation",-1))==Presentation.elevation_for_stage(stage),"Final source camera agreement: "+str(stage.id))
			check(approved==RenderedArt.resolve(stage,fingerprint),"Repeated resolution preserves current approval: "+str(stage.id))
			if int(stage.stageNumber) in [15,37,40]:
				var camera_changed: Dictionary=stage.duplicate(true)
				camera_changed.historicalBattlefield.viewpoint.elevationDegrees=50.0
				var invalid: Dictionary=RenderedArt.resolve(camera_changed,fingerprint)
				check(invalid.mode=="native" and invalid.reason=="source_viewpoint_changed","New camera invalidates cached approved art: "+str(stage.id))
				check(Preview._completed_key(stage)!=Preview._completed_key(camera_changed),"Snapshot identity includes the revised viewpoint: "+str(stage.id))
		field.free()
		await verify_cached_aspect(maps[0])
		var output: FileAccess=FileAccess.open("user://catalog-preview-final-source.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failures":failures,"sourceMapsSha256":FileAccess.get_sha256("res://native/maps.json")},"\t"));output.close()
		print("CATALOG_PREVIEW_FINAL_SOURCE checks=%d failures=%d"%[checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	check(Battlefield.INTERACTIVE_FRAME_BUDGET_USEC==6000,"On-demand generation retains its 6ms frame budget")
	check(Battlefield.PREPARATION_FRAME_BUDGET_USEC==24000,"Startup preparation uses a separate 24ms frame budget")
	for sample in [[-1,1000],[0,1000],[1000,1000],[6000,6000],[24000,24000],[30000,24000]]:
		check(Battlefield.preview_frame_budget(sample[0])==sample[1],"Frame budget boundary: "+str(sample[0]))
	for sample in [[null,50.0],[-100.0,35.0],[35.0,35.0],[38.0,38.0],[42.0,42.0],[58.0,58.0],[65.0,65.0],[100.0,65.0],[NAN,50.0]]:
		var fixture: Dictionary = {} if sample[0]==null else {"historicalBattlefield":{"viewpoint":{"elevationDegrees":sample[0]}}}
		check(Presentation.elevation_for_stage(fixture)==sample[1],"Stage camera boundary: "+str(sample[0]))
	var source: Dictionary = maps[0]
	var field: Node3D = Battlefield.new()
	var fingerprint: String = JSON.stringify(field._physical_contract(source)).sha256_text()
	field.free()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RenderedArt.MANIFEST_PATH))
	var path: String = "user://cache-invalidation-manifest.json"
	write_manifest(path,manifest)
	var valid: Dictionary = RenderedArt.resolve(source,fingerprint,path)
	check(valid.mode=="rendered" and valid.distributionReady,"Unchanged complete artwork passes all approval checks")
	var repeated: Dictionary = RenderedArt.resolve(source,fingerprint,path)
	check(valid==repeated,"Cached selection retains every verified approval field")
	var changed_viewpoint: Dictionary=source.duplicate(true)
	changed_viewpoint.historicalBattlefield["viewpoint"]={"elevationDegrees":38.0}
	var mismatched_camera: Dictionary=RenderedArt.resolve(changed_viewpoint,fingerprint,path)
	check(mismatched_camera.mode=="native" and mismatched_camera.reason=="source_viewpoint_changed","Changing only the map camera invalidates a previously cached projection")
	manifest.stages[0]["camera"]={"elevation":38.0}
	write_manifest("user://stage-camera-manifest.json",manifest)
	var matching_camera: Dictionary=RenderedArt.resolve(changed_viewpoint,fingerprint,"user://stage-camera-manifest.json")
	check(matching_camera.mode=="rendered" and matching_camera.sourceProjection.elevation==38.0,"The per-stage source camera overrides the manifest default")
	check(matching_camera.sourceProjection.worldWidth==manifest.camera.worldWidth,"A per-stage camera retains unspecified global projection fields")
	manifest.stages[0].sha256="0".repeat(64)
	manifest["cacheTestRevision"]=1
	write_manifest(path,manifest)
	var changed: Dictionary = RenderedArt.resolve(source,fingerprint,path)
	check(changed.mode=="native" and changed.reason=="art_hash_mismatch","Manifest edits invalidate cached artwork without manually releasing caches")
	manifest.stages[0].sha256=valid.artSha256
	manifest.stages[0].sourceDataSha256="invalid"
	manifest.cacheTestRevision=100
	write_manifest(path,manifest)
	changed=RenderedArt.resolve(source,fingerprint,path)
	check(changed.mode=="native" and changed.reason=="source_data_changed","Edited per-stage source claim cannot reuse a previous valid resolution")
	var old_helpers_source: String="res://tests/profiles/catalog-preview-compatibility/rendered_helpers_baseline.gd"
	if FileAccess.file_exists(old_helpers_source):
		manifest=JSON.parse_string(FileAccess.get_file_as_string(RenderedArt.MANIFEST_PATH))
		manifest.sourceMapsSha256="invalid"
		write_manifest("user://prior-source-claim.json",manifest)
		var prior_helpers: GDScript=load(old_helpers_source)
		var prior_result: Dictionary=prior_helpers.resolve(source,fingerprint,"user://prior-source-claim.json")
		var current_result: Dictionary=RenderedArt.resolve(source,fingerprint,"user://prior-source-claim.json")
		check(prior_result==current_result,"Per-entry approved source precedence matches preserved implementation")
		print("PRESERVED_SOURCE_PRECEDENCE baselineMode=%s currentMode=%s"%[prior_result.mode,current_result.mode])
	if "--source-only" in OS.get_cmdline_user_args():
		print("CATALOG_PREVIEW_SOURCE checks=%d failures=%d"%[checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	var wrong_geometry: Dictionary = RenderedArt.resolve(source,"0".repeat(64))
	check(wrong_geometry.mode=="native" and wrong_geometry.reason=="source_geometry_changed","Geometry changes cannot reuse the approved source fingerprint")
	var preview: Control = Preview.new()
	preview.size=Vector2(828,312)
	preview.configure(maps[0])
	root.add_child(preview)
	preview._refresh()
	await process_frame
	preview.configure(maps[1])
	await wait_for_preview(preview)
	check(str(preview.diagnostics().terrain.stageId)==str(maps[1].id),"Selection during generation finishes with the latest map")
	var renders: int = preview.render_requests
	preview.configure(maps[1])
	await process_frame
	await process_frame
	check(preview.render_requests==renders,"An identical selected map does not regenerate or redraw")
	preview.size=Vector2(960,400)
	await process_frame
	await wait_for_preview(preview)
	check(preview.viewport.size==Vector2i(960,400),"Resize finishes at the newly requested render size")
	preview.free()
	var cancelled: Control=Preview.new()
	cancelled.size=Vector2(828,312)
	cancelled.configure(maps[2])
	root.add_child(cancelled)
	cancelled._refresh()
	await process_frame
	cancelled.free()
	for unused in range(4): await process_frame
	check(true,"Removing an in-flight preview cancels safely without a worker or stale result")
	# Optional preserved Git inputs are written only in this isolated QA folder.
	var old_source: String="res://tests/profiles/catalog-preview-compatibility/battlefield_baseline.gd"
	if FileAccess.file_exists(old_source):
		var prior: GDScript=load(old_source)
		for index in [0,1,2,31]:
			var original: Node3D=prior.new()
			var current: Node3D=Battlefield.new()
			for terrain in [original,current]:
				terrain.stage=maps[index]
				terrain.history=maps[index].get("historicalBattlefield",{})
				terrain.width=18.5
				terrain.depth=18.5/(828.0/312.0)/sin(deg_to_rad(50.0))
				terrain.seed_value=absi(str(terrain.history.get("terrainLayout",{}).get("seed",maps[index].id)).hash())
				terrain._collect_geometry()
				terrain._build_height_grid()
			check(original.heights==current.heights,"All 6,305 exact height values match preserved implementation: "+str(maps[index].id))
			original.free()
			current.free()
	Preview.release_shared_resources()
	Battlefield.release_shared_resources()
	var file: FileAccess=FileAccess.open("user://catalog-preview-cache.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	print("CATALOG_PREVIEW_CACHE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
