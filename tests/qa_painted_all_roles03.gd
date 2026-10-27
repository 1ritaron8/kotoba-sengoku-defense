extends SceneTree
## Isolated real renderer fixture: no Battle/Main/account/save or simulation writes.
const Actors = preload("res://native/painted_actor_renderer.gd")
const OUTPUT: String = "res://tests/profiles/painted-game-fix-03"
const FRIENDLY: Array = ["archer","spear","samurai","gunner","monk","commander","ninja"]
const ENEMY: Array = ["raider","runner","shield","heavy","enemy_archer","enemy_gunner","enemy_samurai","commander","enemy_cavalry"]
const DIRECTIONS: Array = [Vector2(2,-1),Vector2(2,1),Vector2(-2,1),Vector2(-2,-1)]
const NAMES: Array = ["ne","se","sw","nw"]
const MOMENTS: Array = [{"state":"idle","clock":0.0},{"state":"walk","clock":0.0},{"state":"walk","clock":.25},{"state":"walk","clock":.5},{"state":"walk","clock":.75},{"state":"attack","clock":0.0},{"state":"attack","clock":.28},{"state":"attack","clock":.50},{"state":"hit","clock":.09},{"state":"death","clock":.40}]

class MotionCanvas extends Node2D:
	var renderer: RefCounted
	var roles: Array=[]
	var friendly: bool=true
	var moment: Dictionary={}
	var drawn: Array=[]
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("82785f"))
		drawn.clear()
		renderer.actor_samples.clear()
		var vectors: Array=[Vector2(2,-1),Vector2(2,1),Vector2(-2,1),Vector2(-2,-1)]
		var names: Array=["ne","se","sw","nw"]
		for row in range(roles.size()):
			for column in range(4):
				var role: String=str(roles[row])
				var state: String="heal" if role=="monk" and str(moment.state)=="attack" else str(moment.state)
				var direction: Vector2=vectors[column].normalized()
				draw_string(ThemeDB.fallback_font,Vector2(column*360+8,row*220+21),role+" "+str(names[column])+" "+state,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
				for size_index in range(2):
					var height: float=44.0 if size_index==0 else 110.0
					var actor_id: int=row*100+column*10+size_index
					var role_key: String=("friendly/" if friendly else "enemy/")+renderer._role(role)+"/"+str(names[column])
					var stride: float=float(renderer.rigs.get(role_key,{}).get("strideBodyHeights",.62))
					var foot: Vector2=Vector2(column*360+65+size_index*170,row*220+202)
					var actor: Dictionary={"id":actor_id,"type":role,"animation":state,"animationClock":float(moment.clock),"preview":true,"walkDistanceBodyHeights":float(moment.clock)*stride,"attackDuration":.6,"healDuration":.6}
					var ok: bool=renderer.draw_actor(self,actor,foot,friendly,height,direction,true)
					var sample: Dictionary=renderer.actor_samples.get(("friendly/" if friendly else "enemy/")+str(actor_id),{}).duplicate(true)
					drawn.append({"type":role,"friendly":friendly,"state":state,"direction":names[column],"height":height,"ok":ok,"rig":sample.get("renderTechnique","")=="painted-source-uv-rig","atlas":bool(sample.get("authoredState",false)),"directSource":sample.get("sourceTexture",""),"directionalMirror":false,"directionFallback":sample.get("sourceDirection","")!=sample.get("requestedDirection",""),"sample":sample})

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("All-role QA requires rendered display");quit(2);return
	root.size=Vector2i(1440,900)
	root.content_scale_size=root.size
	var output: String=OUTPUT.path_join("all-roles-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var renderer: RefCounted=Actors.new()
	renderer.capture_rig_diagnostics=true
	var cache: Array=[renderer.diagnostics()]
	for index in range(3):
		var reused: RefCounted=Actors.new()
		cache.append({"warmIndex":index,"hit":reused.asset_cache_hit,"prepareMicroseconds":reused.asset_prepare_microseconds,"ready":reused.is_ready(),"rigs":reused.rigs.size()})
	var layer: MotionCanvas=MotionCanvas.new()
	layer.renderer=renderer
	root.add_child(layer)
	var frames: Array=[]
	var failures: Array=[]
	for side in range(2):
		var roles: Array=FRIENDLY if side==0 else ENEMY
		for page in range(int(ceil(float(roles.size())/4.0))):
			layer.roles=roles.slice(page*4,mini(roles.size(),page*4+4))
			layer.friendly=side==0
			for index in range(MOMENTS.size()):
				layer.moment=MOMENTS[index]
				layer.queue_redraw()
				await RenderingServer.frame_post_draw
				var path: String=output.path_join("side%d-page%d-state%02d.png" % [side,page,index])
				var error: int=root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
				frames.append({"path":ProjectSettings.globalize_path(path),"saveError":error,"moment":MOMENTS[index],"actors":layer.drawn.duplicate(true)})
				if error!=OK: failures.append("PNG write failed: "+path)
				for actor in layer.drawn:
					if not bool(actor.ok): failures.append("No source: "+str(actor.type)+"/"+str(actor.direction)+"/"+str(actor.state))
	var sources: Dictionary={}
	for path in ["res://native/painted_actor_renderer.gd","res://tests/qa_painted_all_roles03.gd","res://assets/characters/painted-v1/manifest.json","res://assets/characters/painted-v1/motion-registration.json"]: sources[path]=FileAccess.get_sha256(path)
	var report: Dictionary={"kind":"isolated_all_roles_actual_renderer","status":"pixels_collected_visual_review_required" if failures.is_empty() else "failed","failures":failures,"sources":sources,"frames":frames,"cache":cache,"renderer":renderer.diagnostics(),"engine":Engine.get_version_info(),"scope":"1440x900 original engine viewport; 44/110 body heights; all allied7 and actual enemy9 types; four requested diagonals; idle, four walk phases, attack/heal prepare/release/recover, hit, death exit. No composite PNG generation, simulation injection or save access. Missing enemy actions and borrowed mounted cavalry source remain limitations. Source availability is not motion quality acceptance; inspect all PNGs for clipping, anatomy, duplicate source limbs, proportions and direction."}
	var file: FileAccess=FileAccess.open(output.path_join("all-roles-report.json"),FileAccess.WRITE)
	if file==null: push_error("Cannot write all-role report");quit(2);return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ALL_ROLES03 ",ProjectSettings.globalize_path(output.path_join("all-roles-report.json")))
	quit(0 if failures.is_empty() else 1)
