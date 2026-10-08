extends SceneTree

const Preview=preload("res://native/battlefield_preview.gd")
var failures: Array[String]=[]
var observations: Array=[]
var checks: int=0

func _initialize() -> void:
	root.position=Vector2i(-6000,100)
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	call_deferred("run")

func check(condition: bool,note: String) -> void:
	checks+=1
	if not condition:
		failures.append(note)
		push_error("CATALOG_PREWARM "+note)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	var boundary: String=ProjectSettings.globalize_path("res://tests/profiles/catalog-preview-").replace("\\","/").to_lower()
	if not profile.begins_with(boundary) or DisplayServer.get_name()=="headless":
		push_error("An isolated GPU catalog-preview profile is required.")
		quit(2)
		return
	var start: int=Time.get_ticks_usec()
	var frozen_maps_sha: String=FileAccess.get_sha256("res://native/maps.json")
	var frozen_manifest_sha: String=FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json")
	var preparation_steps: Array=[]
	var app: Node=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://catalog-preview-prewarm-main.json"
	app.progress.data.settings.music=false
	app.progress.data.settings.voice=false
	app.progress.data.settings.effects=false
	root.add_child(app)
	var progress_before: String=JSON.stringify(app.progress.data)
	check(app.front_end.get_node("HomeSortie").disabled,"Catalog stays disabled while startup prepares the first snapshot")
	check(not app.front_end.get_node("HomeExit").disabled,"Exit remains available during startup preparation")
	app.player.stop()
	app._stop_narration()
	app.battle_audio.set_enabled(false)
	var last_completed: int=-1
	while not app.catalog_preparation_ready and app.catalog_preparation_error.is_empty():
		await process_frame
		if app.catalog_preparation_completed!=last_completed:
			last_completed=app.catalog_preparation_completed
			preparation_steps.append({"completed":last_completed,"elapsedMilliseconds":(Time.get_ticks_usec()-start)/1000.0,"staticMemoryBytes":OS.get_static_memory_usage()})
			print("CATALOG_PREWARM_PROGRESS %d/%d"%[last_completed,app.maps.size()])
		if Time.get_ticks_usec()-start>480000000:
			failures.append("Preparation exceeded eight minutes")
			break
	var preparation_ms: float=(Time.get_ticks_usec()-start)/1000.0
	check(app.catalog_preparation_error.is_empty(),"Preparation reports no render failure")
	check(app.catalog_preparation_ready and app.catalog_preparation_completed==40,"Actual main prepares all 40 stages before catalog navigation")
	check(Preview.completed_previews.size()==40,"Every stage retains its completed GPU snapshot")
	var cached_bytes: int=0
	var image_hashes: Dictionary={}
	for record in Preview.completed_previews.values():
		cached_bytes+=record.texture.get_width()*record.texture.get_height()*4
		var image: Image=record.texture.get_image()
		var hashing: HashingContext=HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(image.get_data())
		var signature: String=hashing.finish().hex_encode()
		image_hashes[signature]=true
	check(image_hashes.size()==40,"GPU snapshots contain 40 distinct rendered images")
	for tier in range(4):
		app.front_end.show_catalog(tier,false)
		await process_frame
		for index in range(10):
			var click_start: int=Time.get_ticks_usec()
			app.front_end._select_catalog_stage(index)
			var callback_ms: float=(Time.get_ticks_usec()-click_start)/1000.0
			await process_frame
			await process_frame
			var preview: Control=app.front_end.get_node("CatalogBattlefieldPreview")
			var info: Dictionary=preview.diagnostics()
			var expected: String=str(app.maps[tier*10+index].id)
			check(info.cacheHit and not info.loading and info.renderRequests==0,"Selection uses the prepared texture with no terrain build: "+expected)
			check(str(info.terrain.stageId)==expected,"Prepared snapshot belongs to the selected stage: "+expected)
			check(info.terrain.get("previewFrameBudgetUsec",0)==24000,"Prepared snapshot uses the startup 24ms generation budget: "+expected)
			var expected_elevation: float=preload("res://native/battlefield_presentation.gd").elevation_for_stage(app.maps[tier*10+index])
			check(info.elevation==expected_elevation,"Prepared camera follows the selected map viewpoint: "+expected)
			var layer: Dictionary=info.terrain.get("renderLayerContract",{})
			check(layer.get("mode","")=="rendered" and layer.get("distributionReady",false),"Prepared selection uses approved campaign artwork: "+expected)
			check(float(layer.get("sourceProjection",{}).get("elevation",-1))==expected_elevation,"Artwork projection agrees with the map camera: "+expected)
			check(layer.get("rawArtHashVerified",false) and layer.get("sourceDataVerified",false) and str(layer.get("artSha256",""))==FileAccess.get_sha256(str(layer.get("artPath",""))),"Snapshot retains the exact verified final artwork: "+expected)
			observations.append({"stageId":expected,"callbackMilliseconds":callback_ms,"cacheHit":info.cacheHit,"renderRequests":info.renderRequests,"elevation":expected_elevation,"artPath":layer.get("artPath",""),"artSha256":layer.get("artSha256",""),"sourceDataSha256":layer.get("sourceDataSha256","")})
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	await process_frame
	await process_frame
	var resized_preview: Control=app.front_end.get_node("CatalogBattlefieldPreview")
	check(resized_preview.diagnostics().cacheHit and resized_preview.render_requests==0,"Window resize reuses the prepared source snapshot")
	check(Preview.completed_previews.size()==40,"Resize preserves every stage instead of filling a second cache variant")
	check(JSON.stringify(app.progress.data)==progress_before,"Map browsing and preparation preserve campaign progress and settings")
	check(frozen_maps_sha==FileAccess.get_sha256("res://native/maps.json") and frozen_manifest_sha==FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json"),"Final maps and artwork manifest remain frozen throughout the run")
	var shutdown_start: int=Time.get_ticks_usec()
	await app._quit_game()
	var shutdown_ms: float=(Time.get_ticks_usec()-shutdown_start)/1000.0
	check(app.closing,"The actual game exit action completes its shutdown path")
	app.free()
	check(Preview.completed_previews.is_empty(),"Application shutdown releases all prepared GPU snapshots")
	var result: Dictionary={"checks":checks,"failures":failures,"preparationMilliseconds":preparation_ms,"shutdownMilliseconds":shutdown_ms,"snapshotBytesUpperBound":cached_bytes,"distinctImageCount":image_hashes.size(),"observations":observations,"preparationSteps":preparation_steps,"staticMemoryPeakBytes":OS.get_static_memory_peak_usage(),"sourceMapsSha256":frozen_maps_sha,"manifestSha256":frozen_manifest_sha,"renderer":RenderingServer.get_video_adapter_name()}
	var file: FileAccess=FileAccess.open("user://catalog-preview-prewarm.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("CATALOG_PREWARM checks=%d failures=%d preparationMs=%.1f snapshotMiB=%.1f"%[checks,failures.size(),preparation_ms,cached_bytes/1048576.0])
	quit(0 if failures.is_empty() else 1)
