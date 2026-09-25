extends Node

const TestFrameworkScript = preload("res://tests/test_framework.gd")
const Tier1SyntaxTestScript = preload("res://tests/suites/tier1_syntax_test.gd")
const Tier2SceneTestScript = preload("res://tests/suites/tier2_scene_test.gd")
const Tier3LogicTestScript = preload("res://tests/suites/tier3_logic_test.gd")

var selected_tier: int = 0  # 0 means run all tiers


func _ready() -> void:
	_parse_command_line_args()
	_execute_test_suites()


func _parse_command_line_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()

	for i in range(args.size()):
		var arg := args[i]
		if arg == "--tier" and i + 1 < args.size():
			selected_tier = int(args[i + 1])
		elif arg.begins_with("--tier="):
			selected_tier = int(arg.trim_prefix("--tier="))


func _execute_test_suites() -> void:
	print("==================================================================")
	print("             PTERODON AUTOMATED TEST RUNNER                       ")
	print("==================================================================")
	print("Engine Version: ", Engine.get_version_info()["string"])
	var gc := get_node_or_null("/root/GameConfig")
	var is_mob: Variant = gc.get("is_mobile") if gc else "N/A"
	print("Platform:       ", OS.get_name(), " (Mobile profile: ", is_mob, ")")
	print("Execution Mode: Headless CLI")
	print("Selected Tier:  ", ("ALL TIERS (1, 2, 3)" if selected_tier == 0 else "Tier " + str(selected_tier)))
	print("==================================================================")

	var tf := TestFrameworkScript.new()

	# Tier 1
	if selected_tier == 0 or selected_tier == 1:
		tf.begin_tier("Tier 1: Parse & Syntax Validation")
		var t1 = Tier1SyntaxTestScript.new()
		t1.run(tf)
		tf.end_tier()

	# Tier 2
	if selected_tier == 0 or selected_tier == 2:
		tf.begin_tier("Tier 2: Scene Integrity & Instantiation")
		var t2 = Tier2SceneTestScript.new()
		t2.run(tf, self)
		tf.end_tier()

	# Tier 3
	if selected_tier == 0 or selected_tier == 3:
		tf.begin_tier("Tier 3: Core Logic & Unit Tests")
		var t3 = Tier3LogicTestScript.new()
		t3.run(tf, self)
		tf.end_tier()

	# Final Master Summary
	tf.print_master_summary()

	var exit_code := 1 if tf.has_failed() else 0
	await get_tree().process_frame
	get_tree().quit(exit_code)
