extends SceneTree
## Renderer-only presentation fixture. No Main, Battle, account or save access.
const Actors = preload("res://native/painted_actor_renderer.gd")
const OUTPUT: String = "res://tests/profiles/painted-game-fix-01"
class RigCanvas extends Node2D:
	var renderer: RefCounted
	var phase_value: float = 0.0
	var drawn: Array = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,800),Color("82785f"))
		drawn.clear()
		var names: Array = ["ne","sw","se","nw"]
		var vectors: Array = [Vector2(2,-1),Vector2(-2,1),Vector2(2,1),Vector2(-2,-1)]
		for side in range(2):
			for column in range(4):
				var friendly: bool = side==0
				var direction: Vector2 = vectors[column].normalized()
				for size_index in range(2):
					var height: float = 44.0 if size_index==0 else 110.0
					var foot: Vector2 = Vector2(120+column*310,180+side*370+size_index*140)+direction*phase_value*.6*height
					var actor: Dictionary = {"id":side*100+column*2+size_index+1,"type":"spear","animation":"walk","animationClock":phase_value,"preview":true,"previewDirection":names[column],"walkDistanceBodyHeights":phase_value*.6}
					var ok: bool = renderer.draw_actor(self,actor,foot,friendly,height,direction,true)
					drawn.append({"friendly":friendly,"direction":names[column],"height":height,"foot":str(foot),"ok":ok,"sample":renderer.actor_samples.get(("friendly/" if friendly else "enemy/")+str(actor.id),{}).duplicate(true)})

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Rig evidence requires a rendered display");quit(2);return
	root.size=Vector2i(1280,800)
	root.content_scale_size=root.size
	var output: String=OUTPUT.path_join("rig-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var renderer: RefCounted=Actors.new()
	var layer: RigCanvas=RigCanvas.new()
	layer.renderer=renderer
	root.add_child(layer)
	var failures: Array=[]
	var frames: Array=[]
	var images: Array[Image]=[]
	for index in range(24):
		layer.phase_value=float(index)/24.0
		layer.queue_redraw()
		await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
		frames.append({"index":index,"phase":layer.phase_value,"actors":layer.drawn.duplicate(true),"path":ProjectSettings.globalize_path(output.path_join("rig-%02d.png" % index))})
		for actor in layer.drawn:
			if not bool(actor.ok) or str(actor.sample.get("renderTechnique",""))!="painted-source-uv-rig": failures.append("Missing spear UV rig: "+str(actor.direction)+" friendly="+str(actor.friendly))
	for index in range(images.size()):
		var error: int=images[index].save_png(str(frames[index].path))
		frames[index]["saveError"]=error
		if error!=OK: failures.append("PNG save failed "+str(index))
	var hashes: Dictionary={"res://native/painted_actor_renderer.gd":FileAccess.get_sha256("res://native/painted_actor_renderer.gd"),"res://tests/qa_painted_fix01_rig.gd":FileAccess.get_sha256("res://tests/qa_painted_fix01_rig.gd")}
	for filename in DirAccess.get_files_at("res://assets/characters/painted-v1"):
		if filename.get_extension() in ["png","json"]:
			var path: String="res://assets/characters/painted-v1/"+filename
			hashes[path]=FileAccess.get_sha256(path)
	var report: Dictionary={"kind":"renderer_only_spear_rig_fixture","status":"pixels_collected_visual_review_required" if failures.is_empty() else "failed","failures":failures,"sources":hashes,"frames":frames,"renderer":renderer.diagnostics(),"engine":Engine.get_version_info(),"scope":"Both factions, NE/SW/SE/NW, 24 deterministic distance phases, heights44/110. Full viewport original PNGs, writes deferred. Presentation fixture only: no natural walking speed, Battle contact-lock or gameplay acceptance. Inspect sole alternation, knees/hips, body proportions and contact visually; sourceFrame equality is allowed."}
	var file: FileAccess=FileAccess.open(output.path_join("rig-report.json"),FileAccess.WRITE)
	if file==null: push_error("Cannot save rig report");quit(2);return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FIX01_RIG ",ProjectSettings.globalize_path(output.path_join("rig-report.json")))
	quit(0 if failures.is_empty() else 1)
