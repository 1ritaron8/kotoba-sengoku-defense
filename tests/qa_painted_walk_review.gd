extends "res://tests/qa_painted_game.gd"
## Actual Main, one paid spear, full viewport buffers; no gameplay mutation.
## Shared token observer, live-clock guard and foreground/contact evidence.

func end_review(reason: String) -> void:
	if stopped: return
	for label_value in capture_buffers.keys():
		evidence[str(label_value)+"Sequence"]["stopReason"]=reason
		flush_motion_buffer(str(label_value))
	stopped=true
	evidence["sourcesAtEnd"]=hash_sources()
	check(source_hashes==evidence.sourcesAtEnd,"Source/asset hashes stay unchanged during walk review")
	var passed: bool=reason=="complete" and failures.is_empty() and incomplete.is_empty()
	var report: Dictionary={"kind":"strict-live-walk-fix01","status":"passed" if passed else "partial_or_failed","visualAcceptance":"pending_HQ_original_PNG_review","reason":reason,"checks":check_rows,"failures":failures,"incomplete":incomplete,"captures":captures,"evidence":evidence,"clicks":clicks,"inputTrace":input_trace,"events":events,"paidOrders":paid_orders,"sources":source_hashes,"actualInputsOnly":true,"engineLaunches":1,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"One natural paid spear; current 2D main/front render passes and contact cache preserved per live frame. No all-direction/contact-lock or real-time gait-speed acceptance."}
	var file: FileAccess=FileAccess.open(output_dir.path_join("walk-review.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	print("WALK_REVIEW ",JSON.stringify({"report":ProjectSettings.globalize_path(output_dir.path_join("walk-review.json")),"frames":evidence.get("walkSequence",{}).get("frames",[]).size(),"status":report.status,"failures":failures}))
	if is_instance_valid(app): app.queue_free()
	quit(0 if passed else 1)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=OUTPUT_ROOT.path_join("walk-review-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if not check(canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(OUTPUT_ROOT))+"/") and DisplayServer.get_name()!="headless","Review uses isolated rendered FIX01 profile"):
		end_review("profile_rejected");return
	source_hashes=hash_sources()
	create_timer(90.0).timeout.connect(func(): end_review("deadline") if not stopped else null)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://walk-review-"+str(int(Time.get_unix_time_from_system()))+".json"
	if not check(not FileAccess.file_exists(app.progress.save_path),"Walk review uses a fresh isolated player file"):
		end_review("profile_rejected");return
	root.add_child(app)
	await settle(3)
	if not alive(): return
	app.game.game_event.connect(on_event)
	await key_enter()
	if not check(await wait_until(func(): return alive() and is_instance_valid(app.modal) and str(app.modal_context)=="briefing" and (not is_instance_valid(app.scene_transition) or not app.scene_transition.is_running()),12.0),"Actual Enter opens settled mission briefing"):
		end_review("entry_failed");return
	await settle(4)
	if not alive(): return
	if not await click_id(named_id(app.modal,"ConfirmMission"),"Walk-review mission confirmation first click"):
		end_review("confirm_input_failed");return
	if not check(await wait_until(func(): return live_battle(),5.0),"First confirm reaches actual live battle"):
		end_review("confirm_destination_failed");return
	if not await spear_order():
		end_review("recruit_input_failed");return
	if not check(await wait_until(func(): return live_battle() and app.game.units.size()>0 and app.game.recruitment_queue.is_empty(),6.0),"Paid spear naturally finishes production"):
		end_review("recruitment_failed");return
	phase="strict_live_walk_capture"
	await buffered_motion("walk",48,3)
	if not stopped: end_review("complete" if incomplete.is_empty() else "partial_sequence")
