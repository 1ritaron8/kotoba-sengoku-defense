extends SceneTree
const Atlas=preload("res://native/campaign_atlas.gd")
const Store=preload("res://native/progress.gd")
const Gate=preload("res://native/learning_gate.gd")
func _initialize() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_position(Vector2i(-16000,-16000))
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var safe_root: String=ProjectSettings.globalize_path("res://tests/profiles/atlas-cities-capture/").replace("\\","/").to_lower()
	if not profile.begins_with(safe_root): quit(2); return
	root.size=Vector2i(32,32)
	var viewport=SubViewport.new()
	viewport.size=Vector2i(1280,800)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var account=Store.new()
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for entry in maps:
		var lesson: Dictionary=account.stage_lessons[entry.id]
		var count: int=lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		account.data.maps[entry.id]={"wins":1}
		if not account.data.learning.has("assessments"): account.data.learning.assessments={}
		account.data.learning.assessments[entry.id]={"passed":true,"complete":true,"correctCount":count,"count":count,"scopeHash":Gate.scope_hash(lesson)}
	var atlas=Atlas.new()
	atlas.configure(account,maps,JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json")),JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json")),null)
	viewport.add_child(atlas)
	var representative: bool="--representative" in OS.get_cmdline_user_args()
	var sizes: Array=[Vector2i(1280,800)] if representative else [Vector2i(1280,800),Vector2i(1920,1080)]
	for dimensions in sizes:
		viewport.size=dimensions
		for zoom in [false,true]:
			atlas.all_japan=zoom
			var chapters: Array=[2 if zoom else 0] if representative else [0,2]
			for chapter in chapters:
				atlas.show_stage(str(maps[chapter*10].id))
				for frame in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path: String="user://atlas-%dx%d-japan-%s-chapter-%d.png"%[dimensions.x,dimensions.y,str(zoom),chapter]
				var image=viewport.get_texture().get_image()
				assert(image!=null and image.get_size()==dimensions)
				assert(image.save_png(path)==OK)
				print("ATLAS_CAPTURE ",ProjectSettings.globalize_path(path))
	quit(0)
