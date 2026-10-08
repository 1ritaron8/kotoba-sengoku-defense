extends SceneTree

const Preview = preload("res://native/battlefield_preview.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
var failures: Array[String] = []
var reports: Array = []

func _initialize() -> void:
	print("CATALOG_PREVIEW_START")
	if "--gpu" in OS.get_cmdline_user_args():
		root.position=Vector2i(-6000,100)
	call_deferred("run")

func run() -> void:
	print("CATALOG_PREVIEW_RUN")
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	var boundary: String = ProjectSettings.globalize_path("res://tests/profiles/catalog-preview-").replace("\\", "/").to_lower()
	if not profile.begins_with(boundary):
		push_error("An isolated catalog-preview profile is required.")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for index in [0,1,2,0,1,2]:
		var preview: Control = Preview.new()
		preview.size = Vector2(828,312)
		preview.configure(maps[index])
		var start: int = Time.get_ticks_usec()
		root.add_child(preview)
		preview._refresh()
		var request_elapsed: float = (Time.get_ticks_usec()-start)/1000.0
		var maximum_slice: float = request_elapsed
		var frame_count: int = 0
		while preview.is_loading():
			var frame_start: int = Time.get_ticks_usec()
			await process_frame
			maximum_slice = maxf(maximum_slice,(Time.get_ticks_usec()-frame_start)/1000.0)
			frame_count += 1
			if frame_count > 5000:
				failures.append("Preview did not finish")
				break
		var elapsed: float = (Time.get_ticks_usec()-start)/1000.0
		var info: Dictionary = preview.diagnostics()
		reports.append({"stageId":maps[index].id,"buildMilliseconds":elapsed,"requestMilliseconds":request_elapsed,"maximumFrameMilliseconds":maximum_slice,"loadingFrames":frame_count,"diagnostics":info})
		if str(info.stageId)!=str(maps[index].id): failures.append("Wrong selected stage")
		if str(info.get("terrain",{}).get("stageId",""))!=str(maps[index].id): failures.append("Wrong completed terrain")
		if frame_count==0 and index==0 and reports.size()==1: failures.append("New preview must yield while building its exact height grid")
		await process_frame
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		preview.free()
		await process_frame
	var result: Dictionary = {"failures":failures,"reports":reports,"renderer":DisplayServer.get_name()}
	var file: FileAccess = FileAccess.open("user://catalog-preview-performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("CATALOG_PREVIEW_PERFORMANCE "+JSON.stringify(reports.map(func(value): return {"stageId":value.stageId,"buildMilliseconds":value.buildMilliseconds,"requestMilliseconds":value.requestMilliseconds,"maximumFrameMilliseconds":value.maximumFrameMilliseconds,"loadingFrames":value.loadingFrames})))
	Preview.release_shared_resources()
	Battlefield.release_shared_resources()
	quit(0 if failures.is_empty() else 1)
