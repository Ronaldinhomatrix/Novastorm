extends RefCounted

## Tier 3: Core Logic & Unit Tests
## Covers:
## 1. Bullet friendly filtering logic (player bullets ignore each other & friendly player)
## 2. EnergyBall coordinate conversion & terrain collision logic
## 3. GameController score tracking (add_score(), score_updated signal)
## 4. LevelComplete screen touch event handling (InputEventScreenTouch)
## 5. AGENTS.md compliance checker (static mesh architecture & FlightPath decoupling)

const LevelCompleteBaseScript = preload("res://scripts/ui/level_complete.gd")


func run(tf: RefCounted, host_node: Node) -> void:
	test_bullet_friendly_filtering(tf, host_node)
	test_energy_ball_coordinate_conversion(tf, host_node)
	test_game_controller_score_tracking(tf, host_node)
	test_level_complete_touch_handling(tf, host_node)
	test_agents_md_compliance(tf)


# ---------------------------------------------------------------------------
# 1. Bullet Friendly Filtering Logic
# ---------------------------------------------------------------------------
func test_bullet_friendly_filtering(tf: RefCounted, host_node: Node) -> void:
	var bullet_scene := load("res://scenes/bullet.tscn") as PackedScene
	if not bullet_scene:
		tf.start_test("Bullet Friendly Filtering: Scene Load")
		tf.assert_not_null(bullet_scene, "res://scenes/bullet.tscn should load cleanly")
		tf.end_test()
		return

	# Subtest 1.1: Bullet ignores friendly bullet in area_entered
	tf.start_test("Bullet Friendly: Mutual Bullet Area Collision")
	var bullet_a: Area3D = bullet_scene.instantiate()
	var bullet_b: Area3D = bullet_scene.instantiate()
	host_node.add_child(bullet_a)
	host_node.add_child(bullet_b)

	tf.assert_true(bullet_a.is_in_group("player_bullets"), "Bullet A is in player_bullets group")
	tf.assert_true(bullet_b.is_in_group("player_bullets"), "Bullet B is in player_bullets group")

	if bullet_a.has_method("_on_area_entered"):
		bullet_a.call("_on_area_entered", bullet_b)
		tf.assert_false(bullet_a.is_queued_for_deletion(), "Bullet A should NOT queue_free after colliding with friendly Bullet B")
	else:
		tf.assert_true(false, "Bullet script missing _on_area_entered method")

	bullet_a.queue_free()
	bullet_b.queue_free()
	tf.end_test()

	# Subtest 1.2: Bullet ignores friendly player in area/body entered
	tf.start_test("Bullet Friendly: Player Ship Collision")
	var bullet_c: Area3D = bullet_scene.instantiate()
	var player_dummy := CharacterBody3D.new()
	player_dummy.add_to_group("player")
	host_node.add_child(bullet_c)
	host_node.add_child(player_dummy)

	if bullet_c.has_method("_on_body_entered"):
		bullet_c.call("_on_body_entered", player_dummy)
		tf.assert_false(bullet_c.is_queued_for_deletion(), "Bullet should NOT queue_free after colliding with player body")

	bullet_c.queue_free()
	player_dummy.queue_free()
	tf.end_test()

	# Subtest 1.3: Bullet destroys enemy target and applies damage
	tf.start_test("Bullet Combat: Enemy Damage and Destruction")
	var bullet_d: Area3D = bullet_scene.instantiate()
	host_node.add_child(bullet_d)

	var enemy_mock := MockDamageableArea.new()
	host_node.add_child(enemy_mock)

	if bullet_d.has_method("_on_area_entered"):
		bullet_d.call("_on_area_entered", enemy_mock)
		tf.assert_true(bullet_d.is_queued_for_deletion(), "Bullet should queue_free after hitting enemy")
		tf.assert_true(enemy_mock.took_damage, "Enemy received take_damage call")
		tf.assert_eq(enemy_mock.damage_amount, bullet_d.get("damage"), "Enemy received exact bullet damage")

	bullet_d.queue_free()
	enemy_mock.queue_free()
	tf.end_test()


# ---------------------------------------------------------------------------
# 2. EnergyBall Coordinate Conversion & Collision Logic
# ---------------------------------------------------------------------------
func test_energy_ball_coordinate_conversion(tf: RefCounted, host_node: Node) -> void:
	var eb_scene := load("res://scenes/projectiles/energy_ball.tscn") as PackedScene
	if not eb_scene:
		tf.start_test("EnergyBall: Scene Load")
		tf.assert_not_null(eb_scene, "res://scenes/projectiles/energy_ball.tscn should load cleanly")
		tf.end_test()
		return

	# Subtest 2.1: Coordinate conversion from global travel vector to RayCast3D local space
	tf.start_test("EnergyBall: RayCast3D Coordinate Space Conversion")
	var eb: Area3D = eb_scene.instantiate()
	host_node.add_child(eb)

	# Position and rotate the energy ball to test non-aligned local/global spaces
	eb.global_position = Vector3(100.0, 50.0, -200.0)
	eb.rotation_degrees = Vector3(0.0, 90.0, 0.0) # Rotated 90 degrees around Y axis

	var ray: RayCast3D = eb.get("_ray") as RayCast3D
	tf.assert_not_null(ray, "EnergyBall has internal RayCast3D node (_ray)")

	if ray:
		var travel := Vector3(0.0, 0.0, -50.0) # Global travel vector along -Z
		var prev_pos := eb.global_position
		eb.set("_prev_position", prev_pos)
		eb.global_position = prev_pos + travel

		# Call _check_hits (or check calculation)
		if eb.has_method("_check_hits"):
			eb.call("_check_hits")
			# The target_position of the raycast MUST be in ray's local space.
			# When rotated 90 deg around Y, global -Z maps to local -X (or +X).
			var expected_local := ray.to_local(prev_pos + travel)
			tf.assert_vector3_almost_eq(ray.target_position, expected_local, 0.1,
				"RayCast target_position must be converted to local space via to_local()")

	eb.queue_free()
	tf.end_test()

	# Subtest 2.2: Terrain (StaticBody3D) collision handling
	tf.start_test("EnergyBall: Terrain StaticBody3D Collision")
	var eb_terrain: Area3D = eb_scene.instantiate()
	host_node.add_child(eb_terrain)

	var terrain_dummy := StaticBody3D.new()
	host_node.add_child(terrain_dummy)

	if eb_terrain.has_method("_on_body_entered"):
		eb_terrain.call("_on_body_entered", terrain_dummy)
		tf.assert_true(eb_terrain.is_queued_for_deletion(),
			"EnergyBall must queue_free and explode when colliding with StaticBody3D terrain")

	eb_terrain.queue_free()
	terrain_dummy.queue_free()
	tf.end_test()


# ---------------------------------------------------------------------------
# 3. GameController Score Tracking Logic
# ---------------------------------------------------------------------------
func test_game_controller_score_tracking(tf: RefCounted, host_node: Node) -> void:
	tf.start_test("GameController: Score Tracking & Signal")
	var gc_script := load("res://scripts/world/game_controller.gd") as GDScript
	if not gc_script:
		tf.assert_not_null(gc_script, "Failed to load game_controller.gd")
		tf.end_test()
		return

	var gc: Node = gc_script.new()
	host_node.add_child(gc)

	var has_add_score := gc.has_method("add_score")
	tf.assert_true(has_add_score, "GameController has method 'add_score(amount: int)'")

	if has_add_score:
		var has_signal := gc.has_signal("score_updated")
		tf.assert_true(has_signal, "GameController has signal 'score_updated'")

		var score_state := {"received": false, "score": -1}
		if has_signal:
			gc.connect("score_updated", func(s: int):
				score_state.received = true
				score_state.score = s
			)

		# Add 100 points
		gc.call("add_score", 100)
		var current_score: Variant = gc.get("_score")
		if current_score == null:
			current_score = gc.get("score")
		tf.assert_eq(current_score, 100, "Score incremented to 100")
		if has_signal:
			tf.assert_true(score_state.received, "score_updated signal emitted")
			tf.assert_eq(score_state.score, 100, "score_updated emitted with score 100")

		# Add 250 points
		score_state.received = false
		gc.call("add_score", 250)
		current_score = gc.get("_score")
		if current_score == null:
			current_score = gc.get("score")
		tf.assert_eq(current_score, 350, "Score incremented to 350")
		if has_signal:
			tf.assert_eq(score_state.score, 350, "score_updated emitted with score 350")

	gc.queue_free()
	tf.end_test()


# ---------------------------------------------------------------------------
# 4. LevelComplete Touch Event Handling
# ---------------------------------------------------------------------------
func test_level_complete_touch_handling(tf: RefCounted, host_node: Node) -> void:
	tf.start_test("LevelComplete: Screen Touch Event Handling")
	var lc := TestableLevelComplete.new()
	host_node.add_child(lc)

	# Allow clicking
	lc.set("_can_click", true)

	var touch_state := {"emitted": false}
	lc.level_completed.connect(func(): touch_state.emitted = true)

	# Test 4.1: ScreenTouch pressed=true triggers level completion
	var touch_down := InputEventScreenTouch.new()
	touch_down.pressed = true
	touch_down.position = Vector2(400, 300)

	lc._input(touch_down)
	tf.assert_true(touch_state.emitted, "InputEventScreenTouch (pressed=true) triggers level_completed signal")
	tf.assert_true(lc.click_called, "InputEventScreenTouch triggered _on_click()")
	tf.assert_false(lc.get("_can_click"), "_can_click is reset to false after touch to prevent double clicks")

	# Test 4.2: ScreenTouch release (pressed=false) does not re-trigger
	touch_state.emitted = false
	lc.click_called = false
	var touch_up := InputEventScreenTouch.new()
	touch_up.pressed = false
	touch_up.position = Vector2(400, 300)

	lc._input(touch_up)
	tf.assert_false(touch_state.emitted, "InputEventScreenTouch (pressed=false) does not re-trigger completion")
	tf.assert_false(lc.click_called, "InputEventScreenTouch (pressed=false) does not call _on_click()")

	lc.queue_free()
	tf.end_test()


# ---------------------------------------------------------------------------
# 5. AGENTS.md Compliance Checker
# ---------------------------------------------------------------------------
func test_agents_md_compliance(tf: RefCounted) -> void:
	var stage_paths: Array[String] = [
		"res://scenes/stages/level_1.tscn",
		"res://scenes/stages/level_2.tscn",
		"res://scenes/stages/level_3.tscn"
	]

	for stage_path in stage_paths:
		var stage_name := stage_path.get_file()
		tf.start_test("AGENTS.md Compliance: " + stage_name)

		var packed := load(stage_path) as PackedScene
		if not tf.assert_not_null(packed, "Stage scene loads: " + stage_path):
			tf.end_test()
			continue

		var stage_root: Node = packed.instantiate()
		if not tf.assert_not_null(stage_root, "Stage instantiates: " + stage_path):
			tf.end_test()
			continue

		# Rule 1: No procedural CanyonMeshGenerator active with auto_generate_on_ready
		var procedural_generators: Array[Node] = _find_nodes_with_script(stage_root, "canyon_mesh_generator.gd")
		var has_active_procedural_generator := false
		for gen in procedural_generators:
			var auto_gen: Variant = gen.get("auto_generate_on_ready")
			if auto_gen == null or auto_gen == true:
				has_active_procedural_generator = true

		tf.assert_false(has_active_procedural_generator,
			stage_name + " must NOT have active procedural CanyonMeshGenerator in _ready() (AGENTS.md Rule 1)")

		# Rule 2: Terrain must be decoupled from FlightPath
		var flight_path := stage_root.get_node_or_null("FlightPath")
		var terrain_nested_under_flight_path := false
		if flight_path:
			for child in flight_path.get_children():
				if child is MeshInstance3D and child.name != "SplineVisualizer":
					terrain_nested_under_flight_path = true
				if child.get_script() and "canyon" in child.get_script().resource_path.to_lower():
					terrain_nested_under_flight_path = true

		tf.assert_false(terrain_nested_under_flight_path,
			stage_name + " terrain must be decoupled from FlightPath (AGENTS.md Rule 2)")

		stage_root.free()
		tf.end_test()


func _find_nodes_with_script(root: Node, script_name: String) -> Array[Node]:
	var result: Array[Node] = []
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var curr = stack.pop_back()
		var s: Script = curr.get_script()
		if s and s.resource_path.ends_with(script_name):
			result.append(curr)
		for child in curr.get_children():
			stack.append(child)
	return result


# ---------------------------------------------------------------------------
# Test Helpers
# ---------------------------------------------------------------------------
class TestableLevelComplete extends LevelCompleteBaseScript:
	var click_called: bool = false

	func _on_click() -> void:
		_can_click = false
		level_completed.emit()
		click_called = true


class MockDamageableArea extends Area3D:
	var took_damage: bool = false
	var damage_amount: int = 0

	func take_damage(amount: int) -> void:
		took_damage = true
		damage_amount = amount
