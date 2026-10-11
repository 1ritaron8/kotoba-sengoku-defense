extends "res://tests/qa_common_first_integration.gd"
## Focused normal-entry performance receipt. No synthetic actors or runtime edits.
const LAG_ROOT = "c:/jp_df/tests/profiles/r8-lag-01/candidate"
const EVIDENCE_ROOT = "c:/jp_df/tests/profiles/r8-lag-01/evidence"
var lag_phase: String = "baseline"
var lag_manifest: String = ""
var lag_sources: Dictionary = {}
var lag_rows: Array = []
var lag_start: int = 0
var lag_profile_active: bool = false
var lag_profile_available: bool = false
var lag_events: Array = []
var lag_ui_interruptions: int = 0
var lag_measure_start_elapsed: float = 0.0
var lag_end_elapsed: float = 0.0
var lag_empty_calibration: Dictionary = {}
var lag_instrumentation: Dictionary = {}

func _initialize() -> void:
	call_deferred("lag_run")

func lag_guard() -> bool:
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	return check(canonical(ProjectSettings.globalize_path("res://"))==LAG_ROOT and roaming.begins_with(EVIDENCE_ROOT+"/") and canonical(OS.get_environment("LOCALAPPDATA"))==roaming and canonical(ProjectSettings.globalize_path("user://")).begins_with(roaming+"/") and DisplayServer.get_name()!="headless","Exact copied candidate and private evidence account, GPU only; no live fallback")

func lag_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in lag_sources:
		result[path] = FileAccess.get_sha256(path)
	return result

func lag_event(event: Dictionary) -> void:
	if str(event.get("type","")) in ["wave","hit","killed","recruited","placed","finished"]:
		lag_events.append(event.duplicate(true))

func lag_continue_native_ui() -> bool:
	if app.modal==null: return false
	var button: Button = null
	if app.learning_field.visible: button = app.learning_field.continue_button
	elif is_instance_valid(app.quiz_continue_button) and app.quiz_continue_button.is_visible_in_tree(): button = app.quiz_continue_button
	if is_instance_valid(button) and not button.disabled:
		lag_ui_interruptions += 1
		await desktop_click(button,"Natural learning UI skip/continue; no issued fixture")
		return true
	return false

func lag_warmup() -> void:
	var started: int = Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<8000000:
		await process_frame
		await lag_continue_native_ui()
		if app.game.finished: break

func lag_measure() -> void:
	var troop_rid: RID = app.troops_3d.viewport.get_viewport_rid()
	var root_rid: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(troop_rid,true)
	RenderingServer.viewport_set_measure_render_time(root_rid,true)
	app.game.lag_profile_reset()
	lag_profile_available = EngineDebugger.is_active() and EngineDebugger.has_profiler("scripts")
	if lag_profile_available:
		EngineDebugger.profiler_enable("scripts",true)
		lag_profile_active = true
	lag_measure_start_elapsed = app.game.elapsed
	var running_usec: int = 0
	var previous: int = Time.get_ticks_usec()
	var measurement_start: int = previous
	while running_usec<40000000 and Time.get_ticks_usec()-measurement_start<90000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var interval: int = now-previous
		previous = now
		var eligible: bool = app.game.running and not app.game.paused and not app.game.between_waves and app.modal==null and not app.game.finished
		var probe_start: int = Time.get_ticks_usec()
		lag_rows.append({"t_usec":now-measurement_start,"frame_ms":float(interval)/1000.0,"eligible_running":eligible,"combat_elapsed":app.game.elapsed,"wave":app.game.wave,"actors":app.troops_3d.actors.size(),"friendlies":app.game.units.size(),"enemies":app.game.enemies.size(),"cpu_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"cpu_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"battlefield_troops_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(troop_rid),"battlefield_troops_render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(troop_rid),"root_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root_rid),"root_render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root_rid),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),"probe_self_usec":0})
		lag_rows[-1].probe_self_usec = Time.get_ticks_usec()-probe_start
		if eligible: running_usec += interval
		else:
			await lag_continue_native_ui()
			previous = Time.get_ticks_usec()
		if app.game.finished or Time.get_ticks_usec()-lag_start>150000000: break
	lag_end_elapsed = app.game.elapsed
	lag_instrumentation = app.game.lag_profile_snapshot(false)
	if lag_profile_active:
		EngineDebugger.profiler_enable("scripts",false)
		lag_profile_active = false
	check(running_usec>=30000000,"At least30 seconds of actual unpaused natural running frames were measured")
	check(lag_profile_available,"Built-in script profiler supplies self/inclusive/call receipts")
	check(is_equal_approx(app.game.speed,1.0),"Natural measurement remains1x")
	observations.append({"case":"measurement window","running_wall_seconds":float(running_usec)/1000000.0,"total_wall_seconds":float(Time.get_ticks_usec()-measurement_start)/1000000.0,"ui_interruptions":lag_ui_interruptions,"script_profiler":lag_profile_available,"profiler_scope":"Local built-in scripts profiler prints one frame table per second plus accumulated table at disable; no per-frame text or screenshot encoding"})

func lag_report() -> Dictionary:
	var after: Dictionary = lag_hashes()
	check(after==lag_sources,"All approved copied R8 inputs stay frozen during this run")
	var report: Dictionary = {"phase":lag_phase,"status":"MEASURED" if failures.is_empty() else "FAILED","checks":checks,"failures":failures,"source_hashes_before":lag_sources,"source_hashes_after":after,"source_freeze_unchanged":after==lag_sources,"rows":lag_rows,"events":lag_events,"observations":observations,"captures":captures,"hardware":{"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"processor_count":OS.get_processor_count(),"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"window_size":str(root.size),"field_size":str(app.troops_3d.viewport.size) if is_instance_valid(app) else "","vsync_mode":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps},"combat_elapsed_start":lag_measure_start_elapsed,"combat_elapsed_end":lag_end_elapsed,"scope":"Actual Main Home/catalog/briefing/start with four paid UI orders, natural1x waves and normal UI continues; no injected actors/clock/HP/physics checkpoint, no full victory or G1 claim. Probe overhead measured; built-in profiler overhead is not independently calibrated. Unsupported or all-zero GPU timers must be reported N/A."}
	report["instrumentation"] = lag_instrumentation
	report["empty_timer_overhead"] = lag_empty_calibration
	report["gpu_metric_scope"] = "battlefield_troops_render_* measures the shared battlefield+troops SubViewport, not troop-only GPU time"
	return report

func lag_persist_timing() -> void:
	var path: String = "user://lag-timing-raw.json"
	if not check(not FileAccess.file_exists(path),"Timing raw is written once before all screenshots and cache fixtures"): return
	var report: Dictionary = lag_report()
	report["checkpoint"] = "TIMING_PERSISTED_BEFORE_SCREENSHOTS_AND_CACHE_FIXTURES"
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if not check(file!=null,"Timing raw file opens in isolated account"): return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("R8_LAG_TIMING_SAVED ",lag_phase," samples=",lag_rows.size())

func lag_finish() -> void:
	if lag_profile_active:
		EngineDebugger.profiler_enable("scripts",false)
		lag_profile_active = false
	var report: Dictionary = lag_report()
	var file: FileAccess = FileAccess.open("user://lag-raw.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	if is_instance_valid(app):
		app._stop_narration()
		app.player.stop()
		app.player.stream = null
		app.battle_audio.shutdown()
		app.game.close_battle()
		app.queue_free()
		await settle()
	print("R8_LAG_COMPLETE ",report.status," samples=",lag_rows.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func lag_run() -> void:
	lag_start = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): lag_phase = arg.trim_prefix("--phase=")
		elif arg.begins_with("--manifest="): lag_manifest = arg.trim_prefix("--manifest=")
	if not lag_guard():
		quit(2)
		return
	if not check(canonical(lag_manifest).begins_with(EVIDENCE_ROOT+"/") and FileAccess.file_exists(lag_manifest),"HQ approved manifest exists in this round evidence"):
		quit(2)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(lag_manifest))
	if not check(manifest is Dictionary and manifest.get("sources") is Dictionary,"Manifest supplies exact approved source hashes"):
		quit(2)
		return
	lag_sources = manifest.sources.duplicate(true)
	if not check(lag_hashes()==lag_sources,"Copied inputs match HQ manifest before Main initialization"):
		quit(2)
		return
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	var store: RefCounted = Store.new()
	store.save_path = "user://lag-private-account.json"
	store.read_save()
	app = load("res://native/main.tscn").instantiate()
	app.progress = store
	root.add_child(app)
	await settle()
	app.game.game_event.connect(lag_event)
	check(app.maps.size()==1 and not app.isolated_candidate,"Actual copied one-stage catalog; no constructed map")
	await desktop_resize(Vector2i(1440,900))
	if not await desktop_click(app.front_end.get_node_or_null("HomeSortie") as Button,"Actual Home sortie") or not await desktop_wait_catalog_entry():
		await lag_finish()
		return
	if not await desktop_click(app.front_end.find_child("Stage_basic-forest",true,false) as Button,"Actual canonical stage selection"):
		await lag_finish()
		return
	# Selecting a stage rebuilds the catalog and starts its native fade again.
	# Wait for that actual UI to settle before obtaining the new sortie button.
	if not await desktop_wait_catalog_entry() or not await desktop_click(app.front_end.get_node_or_null("CatalogSortie") as Button,"Actual catalog sortie"):
		await lag_finish()
		return
	var briefing_deadline: int = Time.get_ticks_usec()+10000000
	while Time.get_ticks_usec()<briefing_deadline and app.modal_context!="briefing":
		await process_frame
	observations.append({"case":"actual catalog sortie completion","modal_context":app.modal_context,"game_config_id":str(app.game.config.get("id","")),"frontend":desktop_frontend_state(),"scope":"Bounded actual UI readiness after native clicks; no direct callback or source changes"})
	if not check(app.modal_context=="briefing" and str(app.game.config.get("id",""))=="basic-forest","Actual canonical briefing and Game config"):
		await lag_finish()
		return
	if not await desktop_click(desktop_button(app.modal_footer,"출진"),"Actual briefing starts native battle"):
		await lag_finish()
		return
	for unit_id in ["archer","spear","archer","spear"]:
		if not await desktop_paid_order(unit_id):
			await lag_finish()
			return
	if not check(app.game.has_method("lag_profile_calibrate") and app.game.lag_profile_enabled,"HQ approved opt-in Game instrumentation is active"):
		await lag_finish()
		return
	lag_empty_calibration = app.game.lag_profile_calibrate(2000)
	await lag_warmup()
	await lag_measure()
	lag_persist_timing()
	capture_requested = true
	await capture("lag-"+lag_phase+"-after-timing")
	if lag_phase=="candidate":
		await load("res://tests/qa_r8_lag_cache_checks.gd").new().run(self)
	await lag_finish()
