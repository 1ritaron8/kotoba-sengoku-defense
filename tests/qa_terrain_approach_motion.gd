extends SceneTree
const Actor=preload("res://native/sengoku_actor_3d.gd")
const Troops=preload("res://native/troops_3d.gd")
const Game=preload("res://native/game.gd")
const Battlefield=preload("res://native/battlefield_3d.gd")
var checks: int=0
var failures: Array=[]
var grid_observations: Array=[]

class SlopeTerrain extends Node3D:
	var slope: float=4.0
	func height_at(point: Vector2) -> float: return .5+(point.x-.5)*slope
	func world_point(point: Vector2) -> Vector3:
		var height: float=height_at(point)
		return Vector3((point.x-.5)*18.5,height,(point.y-.5)*13.0+height/tan(deg_to_rad(50.0)))

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		if failures.size()<20: push_error("TERRAIN MOTION "+label)

func pose(actor: Node3D) -> Dictionary:
	var result: Dictionary={}
	for key in actor.bones: result[key]=actor.bones[key].global_transform
	return result

func difference(a: Dictionary,b: Dictionary) -> float:
	var largest: float=0.0
	for key in a:
		largest=maxf(largest,(a[key] as Transform3D).origin.distance_to((b[key] as Transform3D).origin))
	return largest

func sources(clock: float, role: String="emplacement_assault", sailing: bool=false) -> Array:
	return [{"id":1,"type":"samurai","kind":"enemy_samurai","friendly":false,"combatRole":role,"hunterState":"ingress","x":.48+clock*.01,"y":.5,"animation":"walk","animationClock":clock,"motionTime":clock,"animationPhase":0.0,"aimX":1.0,"aimY":0.0,"sailing":sailing}]

func renderer() -> Control:
	var troops: Control=Troops.new()
	root.add_child(troops)
	troops.set_field_size(Vector2(1100,620))
	var stage: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))[0].duplicate(true)
	stage.historicalBattlefield.materialTheme="forest_ground"
	stage.historicalBattlefield.ambushClearings=[{"role":"external_ambush_cover","x":.5,"y":.5,"r":.1}]
	troops.set_stage(stage)
	var terrain: Node3D=SlopeTerrain.new()
	troops.world.add_child(terrain)
	troops.battlefield=terrain
	return troops

func cover_and_grade() -> void:
	var troops: Control=renderer()
	check(troops._forest_approach_cover(Vector2(.5,.5))>.99,"Actual forest material and authored cover select a crouch")
	check(troops._forest_approach_cover(Vector2(.8,.8))==0.0,"Open part of the same forest-themed battlefield stays upright")
	troops.stage.historicalBattlefield.materialTheme="dry_earth"
	check(troops._forest_approach_cover(Vector2(.5,.5))==0.0,"Historical open-earth terrain overrides the legacy forest theme")
	troops.stage.historicalBattlefield.materialTheme="forest_ground"
	var actor: Node3D
	for frame in range(31):
		var clock: float=frame*.04
		var records: Array=sources(clock)
		troops.sync_actor_states(records)
		actor=troops.actors["1:0"]
		check(actor.position.distance_to(troops.normalized_to_world(Vector2(records[0].x,.5)))<.00001,"Terrain posture never changes the authored root position")
		check(actor.rotation.x==0 and actor.rotation.z==0,"Terrain posture never tilts the root/artwork coordinate frame")
		for bone in actor.bones.values(): check(bone.global_transform.is_finite(),"Terrain IK keeps finite joint transforms")
	check(float(actor.current_state.approachCover)>.98 and actor.rig.position.y<.81,"Moving hostile emplacement crew visibly lowers the pelvis in cover")
	check(float(actor.current_state.terrainPitch)>.15 and actor.rig.rotation.x<-.1,"Uphill travel contributes a real forward body lean")
	check(float(actor.current_state.strideLength)<.78,"Covered grade approach uses shorter quicker distance-driven steps")
	check(actor.current_state.get("groundHeightSampler",Callable()).is_valid(),"Actual terrain height is delivered to foot IK")
	for suffix in ["L","R"]:
		var lowest: float=INF
		for mesh in actor.meshes:
			if mesh.get_parent()!=actor.bones["foot"+suffix]: continue
			for surface in range(mesh.mesh.get_surface_count()):
				for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var world_vertex: Vector3=mesh.global_transform*vertex
					lowest=minf(lowest,world_vertex.y-troops._ground_contact_height(world_vertex))
		check(lowest>-.015,"Actual shoe sole stays above the sampled inclined ground within 15mm")
	var frozen: Dictionary=pose(actor)
	var root_position: Vector3=actor.position
	for repeat in range(4): troops.sync_actor_states(sources(1.2))
	check(difference(frozen,pose(actor))<.00005 and actor.position==root_position,"Paused terrain approach preserves every joint and root")
	var opposite: Dictionary=troops._terrain_approach_profile({"friendly":false,"combatRole":"emplacement_assault","animation":"walk","hunterState":"ingress","aimX":-1.0,"aimY":0.0},Vector2(.5,.5))
	check(float(opposite.pitch)<-.15,"Downhill travel reverses the sampled slope")
	for record in [{"friendly":true},{"combatRole":"path_assault"}]:
		var input: Dictionary=sources(0)[0].duplicate()
		input.merge(record,true)
		var ground: Dictionary=troops._terrain_approach_profile(input,Vector2(.5,.5))
		check(bool(ground.enabled) and float(ground.cover)==0.0 and float(ground.pitch)>.15,"Both armies follow the actual grade without borrowing the hunter crouch")
	for record in [{"animation":"idle"},{"sailing":true},{"dead":true}]:
		var input: Dictionary=sources(0)[0].duplicate()
		input.merge(record,true)
		check(not bool(troops._terrain_approach_profile(input,Vector2(.5,.5)).enabled),"Standing/boat/death pose remains outside moving terrain posture")
	troops.free()

func facing_and_corners() -> void:
	var troops: Control=renderer()
	troops.set_process(false)
	for model in ["samurai","commander"]:
		for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)]:
			troops.sync_actor_states([])
			var record: Dictionary=sources(0,"path_assault")[0]
			record.type=model
			record.x=.5;record.y=.5
			record.aimX=direction.x;record.aimY=direction.y
			troops.sync_actor_states([record])
			var actor: Node3D=troops.actors["1:0"]
			var ahead: Vector3=troops.normalized_to_world(Vector2(.5,.5)+direction.normalized()*.006)-actor.position
			ahead.y=0
			check((-actor.global_basis.z).normalized().dot(ahead.normalized())>.999,"Fresh infantry/cavalry faces the real world direction in all eight headings")
			# Deliberately stale logical aim must not make a walking body slide sideways.
			record.aimX=-direction.x;record.aimY=-direction.y
			for frame in range(1,31):
				var point: Vector2=Vector2(.5,.5)+direction.normalized()*frame*.0004
				record.x=point.x;record.y=point.y
				record.motionTime=frame*.02;record.animationClock=frame*.02
				troops.sync_actor_states([record])
			check((-actor.global_basis.z).normalized().dot(ahead.normalized())>.999,"Moving infantry/cavalry follows actual displacement instead of stale smoothed aim")
			var yaw: float=actor.rotation.y
			var frozen: Dictionary=pose(actor)
			for repeat in range(3): troops.sync_actor_states([record])
			check(difference(frozen,pose(actor))<.00005 and is_equal_approx(actor.rotation.y,yaw),"Paused oblique movement preserves direction and every joint")
			record.motionTime+=.02
			troops.sync_actor_states([record])
			check(absf(wrapf(actor.rotation.y-yaw,-PI,PI))<.00001,"A queued marcher keeps its last heading without turning toward stale aim")
	# Observe a real right-angle turn: roots remain at the authored points and
	# visual rotation advances continuously rather than snapping at the corner.
	troops.sync_actor_states([])
	var record: Dictionary=sources(0,"path_assault")[0]
	record.type="samurai";record.aimX=1.0;record.aimY=0.0
	var actor: Node3D
	var previous_yaw: float=0.0
	for frame in range(61):
		var point: Vector2=Vector2(.48+minf(frame,30)*.0004,.5+maxf(frame-30,0)*.0004)
		record.x=point.x;record.y=point.y
		record.motionTime=frame*.02;record.animationClock=frame*.02
		troops.sync_actor_states([record])
		actor=troops.actors["1:0"]
		check(actor.position.distance_to(troops.normalized_to_world(point))<.00001,"Corner facing never rounds or shortcuts the physical route")
		if frame>0: check(absf(wrapf(actor.rotation.y-previous_yaw,-PI,PI))<.36,"Corner turn keeps continuous restrained yaw")
		previous_yaw=actor.rotation.y
	check((-actor.global_basis.z).normalized().dot(Vector3.BACK)>.99,"Corner completes facing along the new segment")
	var before: float=actor.rotation.y
	record.animation="attack";record.aimX=-1.0;record.aimY=0.0
	for frame in range(1,31):
		record.motionTime=1.2+frame*.02;record.animationClock=frame*.02
		troops.sync_actor_states([record])
	var attack_heading: Vector3=troops.normalized_to_world(Vector2(record.x,record.y)+Vector2.LEFT*.006)-actor.position
	attack_heading.y=0
	check((-actor.global_basis.z).normalized().dot(attack_heading.normalized())>.99 and absf(wrapf(actor.rotation.y-before,-PI,PI))>1.0,"Stopped attack turns toward its real target rather than retaining travel heading")
	var stopped: Dictionary=pose(actor)
	for repeat in range(3): troops.sync_actor_states([record])
	check(difference(stopped,pose(actor))<.00005,"Paused attack after a terrain turn freezes the planted pose")
	troops.sync_actor_states(sources(0,"path_assault"))
	check(bool(actor.current_state.motionReset),"Restart with a reused actor ID discards old heading and foot contacts")
	for bone in actor.bones.values(): check(bone.global_transform.is_finite(),"Restart preserves finite joints after terrain travel and combat")
	troops.free()

func landing_and_speed() -> void:
	var a: Node3D=Actor.new()
	var b: Node3D=Actor.new()
	root.add_child(a);root.add_child(b)
	a.configure("samurai",true,13,false)
	b.configure("samurai",true,13,false)
	var last: Dictionary={}
	for frame in range(31):
		var clock: float=frame*.02
		var sailing: bool=clock<.2
		var data: Dictionary={"animation":"idle" if sailing else "walk","sailing":sailing,"motionTime":clock,"animationClock":clock,"animationPhase":0.0,"aimX":0.0,"aimY":-1.0,"groundMotion":true,"locomotionPhase":clock,"runBlend":.2}
		# 1x and 2x receive the same simulation timestamp, despite different wall time.
		a.apply_state(data)
		b.apply_state(data.duplicate(true))
		check(difference(pose(a),pose(b))<.00001,"1x/2x equal simulation time produces identical landing skeletons")
		check(a.boat.visible==sailing,"Hull disappears on land; it is never dragged along ground ingress")
		check(a.position==Vector3.ZERO,"Landing skeleton never translates the route root")
		if not last.is_empty(): check(difference(last,pose(a))<.12,"Rowing to foot planting and rising has continuous joint endpoints")
		last=pose(a)
		var frozen: Dictionary=pose(a)
		a.apply_state(data)
		check(difference(frozen,pose(a))<.00005,"Paused landing blend never advances from wall-clock redraws")
	check(a.landing_transition.is_empty() and a.rig.position.y>.79,"Landing finishes after .35 simulation seconds and resumes normal gait")
	a.free();b.free()

func actual_boats() -> void:
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for number in [9,12,39]:
		var game: Node2D=Game.new()
		root.add_child(game)
		game.set_process(false)
		game.load_map(maps[number-1])
		var troops: Control=Troops.new()
		root.add_child(troops)
		troops.set_stage(maps[number-1])
		troops.bind_battle(game)
		var entry: Dictionary=game._prepared_ambush_entry(0)
		var enemy: Dictionary=game._spawn_enemy("enemy_samurai",1,{"ambushEntry":entry})
		var saw_hull: bool=false
		var saw_landing: bool=false
		for frame in range(1800):
			game.animation_time=frame*.025
			troops.sync_actor_states(game.actor_states())
			var actor: Node3D=troops.actors[str(enemy.id)+":0"]
			check(actor.position.distance_to(troops.normalized_to_world(enemy.position))<.00001,"Actual boat/root remains exactly at its route position")
			if actor.boat.visible:
				saw_hull=true
				check(troops._boat_water_visual(enemy.position),"Actual inland hull is visible only on water")
			if str(actor.motion_debug.get("mode",""))=="landing": saw_landing=true
			if not bool(enemy.transportActive) and saw_landing and actor.landing_transition.is_empty(): break
			game._move_enemy(enemy,.025)
		check(saw_hull and saw_landing and not bool(enemy.transportActive),"Actual stage %d completes water rowing → shore landing → land ingress" % number)
		game.enemies.clear()
		game.death_actors=[{"id":enemy.id,"position":game._point(maps[number-1].sideAmbushEntrances[0].point),"aim":Vector2.RIGHT,"kind":"enemy_samurai","animationClock":.2,"sailing":true}]
		troops.sync_actor_states(game.actor_states())
		check(not troops.actors[str(enemy.id)+":0"].boat.visible,"Shore casualty cannot inherit a stale water-hull flag")
		troops.free();game.free()

func native_grid_roundtrip() -> void:
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var troops: Control=Troops.new()
	# Scalar height grids use the same field geometry without rebuilding map art.
	troops.world_depth=troops.world_width/(1100.0/620.0)/sin(deg_to_rad(troops.elevation_degrees))
	for map in maps:
		var terrain: Node3D=Battlefield.new()
		terrain.stage=map.duplicate(true)
		terrain.history=terrain.stage.get("historicalBattlefield",{})
		terrain.width=troops.world_width;terrain.depth=troops.world_depth;terrain.elevation=troops.elevation_degrees
		terrain.seed_value=absi(str(terrain.stage.get("id","battlefield")).hash())
		terrain._collect_geometry()
		terrain._build_height_grid()
		troops.battlefield=terrain
		var count: int=0
		var fallback_count: int=0
		var maximum_error: float=0.0
		var maximum_point: Vector2=Vector2.ZERO
		# Both halves of every triangle, all grid vertices, and outer clamped edges.
		for y in range(Battlefield.GRID_Y+1):
			for x in range(Battlefield.GRID_X+1):
				var points: Array=[terrain._grid_point(x,y)]
				if x<Battlefield.GRID_X and y<Battlefield.GRID_Y:
					for offset in [Vector2(.23,.31),Vector2(.77,.71)]:
						points.append((Vector2(x,y)+offset)/Vector2(Battlefield.GRID_X,Battlefield.GRID_Y)*(1.0+Battlefield.GRID_BORDER*2.0)-Vector2.ONE*Battlefield.GRID_BORDER)
				if x==0 or x==Battlefield.GRID_X or y==0 or y==Battlefield.GRID_Y:
					points.append(terrain._grid_point(x,y)*1.10-Vector2.ONE*.05)
				for point in points:
					var world_point: Vector3=terrain.world_point(point)
					var direct: float=troops._native_grid_contact_height(world_point)
					if not is_finite(direct): fallback_count+=1
					var sampled: float=troops._ground_contact_height(world_point)
					var error: float=absf(sampled-terrain.height_at(point)) if is_finite(sampled) else INF
					count+=1
					if error>maximum_error: maximum_error=error;maximum_point=point
		grid_observations.append({"stage":str(map.id),"samples":count,"maxErrorM":maximum_error,"maxPoint":str(maximum_point),"fallbackSamples":fallback_count})
		check(maximum_error<=.0005,"Every actual stage %s triangle/vertex/border forward→inverse height stays within 0.5mm (error %.8fm at %s)"%[str(map.id),maximum_error,str(maximum_point)])
		terrain.free()
	troops.free()

func run() -> void:
	if not ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower().begins_with(qa_project_path("tests/profiles/").to_lower()): quit(2);return
	cover_and_grade()
	facing_and_corners()
	landing_and_speed()
	actual_boats()
	native_grid_roundtrip()
	var output: FileAccess=FileAccess.open("user://qa_terrain_approach_motion.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"gridRoundtrip":grid_observations,"scope":"Actual skeleton/root observations; eight-direction infantry/cavalry facing, stale aim, corners and route anchors; queued heading and attack/restart; historical cover/grade/soles; pause/speed determinism; finite three-map water-only hull/landing sequence; all 40 native cached grids, both triangles, vertices and clamped borders."},"  "))
	output.close()
	print("TERRAIN_APPROACH_MOTION checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
