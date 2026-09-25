extends RefCounted

## Tier 1: Parse & Syntax Validation
## Recursively validates that all GDScript files in res://scripts/ (strictly excluding addons/)
## parse and compile with zero syntax errors.

# Autoload scripts that are already instantiated in the SceneTree
const AUTOLOAD_SCRIPTS: Array[String] = [
	"res://scripts/audio/sound_manager.gd",
	"res://scripts/config/game_config.gd",
	"res://scripts/config/user_settings.gd"
]


func run(tf: RefCounted) -> void:
	var script_paths := _gather_scripts("res://scripts")
	print("  Discovered ", script_paths.size(), " GDScript files in res://scripts/")

	tf.start_test("Discover Project Scripts")
	tf.assert_true(script_paths.size() > 0, "At least one GDScript file should exist in res://scripts/")
	tf.end_test()

	for path in script_paths:
		var test_title := "Compile: " + path.replace("res://scripts/", "")
		tf.start_test(test_title)

		var script_res = load(path)
		if not tf.assert_not_null(script_res, "Failed to load script resource at " + path):
			tf.end_test()
			continue

		if not tf.assert_true(script_res is GDScript, "Resource is not a GDScript: " + path):
			tf.end_test()
			continue

		var gd_script := script_res as GDScript

		if path in AUTOLOAD_SCRIPTS:
			# Autoloads are already loaded and instantiated; reloading returns ERR_ALREADY_IN_USE
			tf.assert_true(gd_script.can_instantiate(), "Autoload script cannot instantiate: " + path)
		else:
			var err = gd_script.reload()
			tf.assert_eq(err, OK, "GDScript compilation/reload error code " + str(err) + " in " + path)

		tf.end_test()


func _gather_scripts(dir_path: String) -> Array[String]:
	var results: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if not dir:
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var full_path := dir_path + "/" + file_name
		if dir.current_is_dir():
			# Strict exclusion of addons/
			if file_name != "addons":
				results.append_array(_gather_scripts(full_path))
		elif file_name.ends_with(".gd"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	results.sort()
	return results
