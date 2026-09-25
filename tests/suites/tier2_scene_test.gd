extends RefCounted

## Tier 2: Scene Integrity & Instantiation
## Verifies that all stage scenes and key component scenes instantiate cleanly
## and execute _init() and _enter_tree() without crashes or null references.

const STAGE_SCENES: Array[String] = [
	"res://scenes/stages/_level_template.tscn",
	"res://scenes/stages/level_1.tscn",
	"res://scenes/stages/level_1_boss.tscn",
	"res://scenes/stages/level_2.tscn",
	"res://scenes/stages/level_3.tscn"
]

const PLAYER_SCENES: Array[String] = [
	"res://scenes/player.tscn"
]

const PROJECTILE_SCENES: Array[String] = [
	"res://scenes/bullet.tscn",
	"res://scenes/bullet_mobile.tscn",
	"res://scenes/projectiles/energy_ball.tscn",
	"res://scenes/projectiles/player_missile.tscn"
]

const ENEMY_SCENES: Array[String] = [
	"res://scenes/enemies/enemy_bomb.tscn",
	"res://scenes/enemies/enemy_bomber.tscn",
	"res://scenes/enemies/enemy_bullet.tscn",
	"res://scenes/enemies/enemy_bullet_1.tscn",
	"res://scenes/enemies/enemy_fighter.tscn",
	"res://scenes/enemies/enemy_heavy.tscn",
	"res://scenes/enemies/enemy_scout.tscn",
	"res://scenes/enemies/enemy_tank.tscn",
	"res://scenes/enemies/enemy_truck.tscn",
	"res://scenes/enemies/tank_bullet.tscn",
	"res://scenes/enemies/tutorial_enemy.tscn"
]

const UI_WORLD_SCENES: Array[String] = [
	"res://scenes/level_complete.tscn",
	"res://scenes/main_menu.tscn",
	"res://scenes/splash_screen.tscn",
	"res://scenes/ui/hud.tscn",
	"res://scenes/effects/shield_bubble.tscn",
	"res://scenes/world/big_rock.tscn",
	"res://scenes/world/mothership.tscn",
	"res://scenes/world/orbital_planet.tscn"
]


func run(tf: RefCounted, host_node: Node) -> void:
	var test_container := Node.new()
	test_container.name = "SceneTestSandbox"
	host_node.add_child(test_container)

	_run_scene_group(tf, test_container, "Stage", STAGE_SCENES)
	_run_scene_group(tf, test_container, "Player", PLAYER_SCENES)
	_run_scene_group(tf, test_container, "Projectile", PROJECTILE_SCENES)
	_run_scene_group(tf, test_container, "Enemy", ENEMY_SCENES)
	_run_scene_group(tf, test_container, "UI/World", UI_WORLD_SCENES)

	test_container.queue_free()


func _run_scene_group(tf: RefCounted, container: Node, group_name: String, scene_list: Array[String]) -> void:
	for path in scene_list:
		var scene_label := group_name + " Scene: " + path.get_file()
		tf.start_test(scene_label)

		tf.assert_true(ResourceLoader.exists(path), "Scene file exists: " + path)

		var packed := load(path) as PackedScene
		if not tf.assert_not_null(packed, "Failed to load PackedScene: " + path):
			tf.end_test()
			continue

		tf.assert_true(packed.can_instantiate(), "PackedScene can_instantiate() returned false: " + path)

		var instance: Node = packed.instantiate()
		if not tf.assert_not_null(instance, "Scene instantiate() returned null: " + path):
			tf.end_test()
			continue

		# Verify _enter_tree() without crash
		container.add_child(instance)
		tf.assert_true(instance.is_inside_tree(), "Instance successfully entered scene tree: " + path)

		container.remove_child(instance)
		instance.free()

		tf.end_test()
