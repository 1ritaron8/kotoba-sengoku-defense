extends SceneTree

const ImportedHead = preload("res://native/imported_human_head.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			path = argument.trim_prefix("--source=")
	var result: Dictionary = ImportedHead.inspect_source(path)
	var file: FileAccess = FileAccess.open("res://tests/qa_imported_head_inspect.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("IMPORTED_HEAD_INSPECT ",JSON.stringify({"path":path,"skeletons":result.skeletons.size(),"meshes":result.meshes.size(),"errors":result.errors}))
	quit(0 if bool(result.ready) else 1)
