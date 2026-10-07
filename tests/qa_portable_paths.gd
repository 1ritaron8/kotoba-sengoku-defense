extends SceneTree
## Small portable path/guard contracts; no native imports, player save or GPU.
var checks: int=0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")
func check(value: bool,note: String) -> void:
	checks+=1
	if not value:failures.append(note);push_error("PORTABLE_PATHS "+note)
func normalized(path: String) -> String:
	return path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")
func contained(path: String,parent: String) -> bool:
	var root_path: String=normalized(parent)
	return root_path.is_absolute_path() and normalized(path).begins_with(root_path+"/")
func simulated_root(script_path: String,source_root: String="") -> String:
	var path: String=script_path.replace("\\","/")
	if path.begins_with("res://"):
		if source_root.is_empty():return "__invalid_qa_project__/"
		path=source_root.path_join(path.trim_prefix("res://"))
	var project_root: String=path.get_base_dir().get_base_dir().simplify_path()
	return project_root if project_root.is_absolute_path() else "__invalid_qa_project__/"
func guided_profile(path: String,project_root: String) -> bool:
	var parent: String=project_root.path_join("tests/profiles/map-render-blueprints")
	return contained(path,parent) and normalized(path).begins_with(normalized(parent)+"/guided-")

func run() -> void:
	var actual_root: String=ProjectSettings.globalize_path("res://").replace("\\","/").simplify_path().trim_suffix("/")
	check(qa_project_path()==actual_root,"Actual source QA root matches currently loaded project")
	check(qa_project_path("tests/qa_portable_paths.gd")==actual_root.path_join("tests/qa_portable_paths.gd"),"Actual QA file path is project relative")
	check(FileAccess.file_exists(qa_project_path("tests/qa_portable_paths.gd")),"Resolved actual source QA file exists at the bound project path")
	for project_root in ["E:/Home Game","D:/집PC/일본어 게임","/tmp/Project With Spaces"]:
		var file: String=project_root.path_join("tests/qa_pack_3d.gd")
		check(simulated_root(file)==project_root,"External packed verifier derives source workspace from actual QA file")
		check(simulated_root("res://tests/qa_portable_paths.gd",project_root)==project_root,"Source res:// QA resolves through current project")
		var prefix: String=project_root.path_join("tests/profiles")
		check(contained(prefix+"/guard-run/AppData",prefix),"Nested private profile accepted")
		check(contained((prefix+"/guard-run/AppData").to_upper().replace("/","\\"),prefix),"Windows slash and letter case accepted")
		check(not contained(project_root+"2/tests/profiles/run",prefix),"Similarly named project sibling rejected")
		check(not contained(project_root+"/tests/profiles-other/run",prefix),"Similarly named profile sibling rejected")
		check(not contained(prefix+"/../../../Player/AppData",prefix),"Canonical traversal outside profile rejected")
		check(not contained("",prefix) and not contained(prefix+"/run",""),"Empty path/root fail closed")
		check(not contained("user://progress.json",prefix),"Unresolved virtual player path rejected")
		check(contained(project_root+"/tests/unpacked/Game.exe",project_root+"/tests"),"Pack artifact remains in workspace tests")
		check(not contained(project_root+"/dist/Game.exe",project_root+"/tests"),"Production dist cannot impersonate isolated unpacked artifact")
		check(guided_profile(prefix+"/map-render-blueprints/guided-revision/AppData",project_root),"Intentional guided revision prefix retained")
		check(not guided_profile(prefix+"/map-render-blueprints-other/guided-revision",project_root),"Guided parent sibling rejected")
		check(project_root.path_join("tools/pack-learning-verifier-empty")!=project_root.path_join("dist"),"Empty verifier cwd remains distinct from distribution cwd")
	check(simulated_root("res://tests/qa_pack_3d.gd")=="__invalid_qa_project__/","Absent packed source root fails closed")
	check(not contained("E:/Player/AppData",simulated_root("qa_pack_3d.gd")),"Relative script path cannot authorize player profile")
	print("PORTABLE_PATHS_QA ",JSON.stringify({"checks":checks,"failures":failures,"projectRoot":actual_root,"scope":"Portable source/external-pack path derivation and exact canonical isolation boundaries. No native imports/GPU/profile writes."}))
	quit(0 if failures.is_empty() else 1)

# Same standalone path resolution used by external packed tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
