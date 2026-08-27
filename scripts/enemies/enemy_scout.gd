class_name EnemyScout
extends EnemyBase

## Inimigo Caça Leve / Reconhecimento (Starship.002)
## Movimentação rápida em esquadrilha com curva senoidal e disparo frontal.

@export var forward_speed: float = 90.0  ## Velocidade de aproximação em Z local
@export var swoop_frequency: float = 1.8  ## Frequência da oscilação lateral
@export var swoop_amplitude: float = 18.0  ## Amplitude do movimento em X
@export var vertical_amplitude: float = 8.0  ## Amplitude em Y
@export var start_side: float = 1.0  ## 1.0 = entra pela direita, -1.0 = entra pela esquerda

var _time_alive: float = 0.0
var _has_fired: bool = false
var _fire_z_threshold: float = -90.0
var _initial_x: float = 0.0
var _initial_y: float = 10.0


func _ready() -> void:
	max_hp = 1
	score_value = 100
	super._ready()
	_initial_x = position.x
	_initial_y = position.y


func _physics_process(delta: float) -> void:
	_time_alive += delta

	# Movimento para frente (em direção ao jogador, +Z no espaço do PathFollower)
	position.z += forward_speed * delta

	# Curva senoidal lateral e vertical
	var lateral_offset := sin(_time_alive * swoop_frequency) * swoop_amplitude * start_side
	var vertical_offset := cos(_time_alive * swoop_frequency * 0.7) * vertical_amplitude

	position.x = _initial_x + lateral_offset
	position.y = _initial_y + vertical_offset

	# Rotação dinâmica (banking/inclinação nas curvas)
	var bank_angle := -cos(_time_alive * swoop_frequency) * 0.45 * start_side
	rotation.z = lerpf(rotation.z, bank_angle, 10.0 * delta)
	rotation.x = lerpf(rotation.x, -0.15, 8.0 * delta)

	# Disparo de oportunidade ao se aproximar do jogador
	if not _has_fired and position.z >= _fire_z_threshold:
		_has_fired = true
		_shoot()

	# Auto-remoção ao ultrapassar a câmera
	if position.z > 40.0 or _time_alive > 15.0:
		queue_free()


func _shoot() -> void:
	var shoot_pos := global_position + (-global_basis.z * 2.0)
	fire_towards_player(shoot_pos, 0.85)
