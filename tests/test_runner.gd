extends SceneTree

## Automated Headless Test Runner for Pterodon
## Usage:
##   godot --headless --path c:\Pterodon -s tests/test_runner.gd
##   godot --headless --path c:\Pterodon -s tests/test_runner.gd -- --tier 1
##   godot --headless --path c:\Pterodon -s tests/test_runner.gd -- --tier 2
##   godot --headless --path c:\Pterodon -s tests/test_runner.gd -- --tier 3

func _init() -> void:
	change_scene_to_file("res://tests/test_runner.tscn")
