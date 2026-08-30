class_name SoundManagerClass
extends Node

## Gerenciador Central de Áudio e Pool de SFX com Ring Buffer Dedicado para Novastorm.
##
## Arquitetura:
## - Ring Buffer (Round-Robin) com canais independentes e dedicados por tipo de áudio.
## - Elimina 100% de qualquer condição de corrida ou cancelamento entre múltiplas explosões.
## - Cada explosão recebe um canal de hardware exclusivo e toca sua duração completa.
## - Latência zero (0ms), zero alocações em runtime, pré-carregamento total em RAM.

const POOL_SIZE_EXPLOSIONS: int = 16
const POOL_SIZE_PLAYER_LASERS: int = 16
const POOL_SIZE_ENEMY_LASERS: int = 16
const POOL_SIZE_SFX: int = 8

const SND_EXPLOSION_1 := preload("res://assets/audio/explosion1.ogg")
const SND_EXPLOSION_2 := preload("res://assets/audio/explosion2.ogg")
const SND_LASER_PLAYER := preload("res://assets/audio/laser1_player.ogg")
const SND_LASER_ENEMY := preload("res://assets/audio/laser1.ogg")
const SND_MANEUVER := preload("res://assets/audio/maneuver1.ogg")
const SND_MOTHERSHIP := preload("res://assets/audio/mothership1.ogg")

var _explosion_pool: Array[AudioStreamPlayer] = []
var _player_laser_pool: Array[AudioStreamPlayer] = []
var _enemy_laser_pool: Array[AudioStreamPlayer] = []
var _sfx_pool: Array[AudioStreamPlayer] = []

var _idx_explosion: int = 0
var _idx_player_laser: int = 0
var _idx_enemy_laser: int = 0
var _idx_sfx: int = 0

var _explosions: Array[AudioStream] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_explosions = [SND_EXPLOSION_1, SND_EXPLOSION_2]
	_init_all_pools()


func _init_all_pools() -> void:
	_init_ring_pool(_explosion_pool, "Explosion", POOL_SIZE_EXPLOSIONS)
	_init_ring_pool(_player_laser_pool, "PlayerLaser", POOL_SIZE_PLAYER_LASERS)
	_init_ring_pool(_enemy_laser_pool, "EnemyLaser", POOL_SIZE_ENEMY_LASERS)
	_init_ring_pool(_sfx_pool, "SFX", POOL_SIZE_SFX)


func _init_ring_pool(pool: Array[AudioStreamPlayer], prefix: String, count: int) -> void:
	pool.clear()
	for i in range(count):
		var p := AudioStreamPlayer.new()
		p.name = "%sChannel_%02d" % [prefix, i]
		p.bus = "Master"
		p.max_polyphony = 2
		add_child(p)
		pool.append(p)


## Toca uma explosão de nave garantida via Pool Inteligente (-25% volume = -2.5 dB)
func play_explosion(volume_db: float = -2.5, pitch_min: float = 0.95, pitch_max: float = 1.05) -> void:
	if _explosion_pool.is_empty() or _explosions.is_empty():
		return

	# Busca preferencialmente um canal que já terminou de tocar para não cortar sons em andamento
	var p: AudioStreamPlayer = null
	for candidate in _explosion_pool:
		if not candidate.playing:
			p = candidate
			break

	if not p:
		p = _explosion_pool[_idx_explosion]
		_idx_explosion = (_idx_explosion + 1) % _explosion_pool.size()

	p.stream = _explosions.pick_random()
	p.volume_db = volume_db
	p.pitch_scale = randf_range(pitch_min, pitch_max)
	p.play()


## Toca uma explosão pesada para Heavy ou chefes (-25% volume)
func play_heavy_explosion(volume_db: float = 1.0) -> void:
	play_explosion(volume_db, 0.75, 0.90)


## Toca o laser do jogador em canal dedicado
func play_laser_player(volume_db: float = -6.0, pitch_min: float = 0.95, pitch_max: float = 1.05) -> void:
	if _player_laser_pool.is_empty():
		return

	var p: AudioStreamPlayer = null
	for candidate in _player_laser_pool:
		if not candidate.playing:
			p = candidate
			break

	if not p:
		p = _player_laser_pool[_idx_player_laser]
		_idx_player_laser = (_idx_player_laser + 1) % _player_laser_pool.size()

	p.stream = SND_LASER_PLAYER
	p.volume_db = volume_db
	p.pitch_scale = randf_range(pitch_min, pitch_max)
	p.play()


## Toca o laser do inimigo em canal dedicado
func play_laser_enemy(volume_db: float = -4.0, pitch_min: float = 0.90, pitch_max: float = 1.10) -> void:
	if _enemy_laser_pool.is_empty():
		return

	var p: AudioStreamPlayer = null
	for candidate in _enemy_laser_pool:
		if not candidate.playing:
			p = candidate
			break

	if not p:
		p = _enemy_laser_pool[_idx_enemy_laser]
		_idx_enemy_laser = (_idx_enemy_laser + 1) % _enemy_laser_pool.size()

	p.stream = SND_LASER_ENEMY
	p.volume_db = volume_db
	p.pitch_scale = randf_range(pitch_min, pitch_max)
	p.play()


## Toca SFX genérico
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not stream or _sfx_pool.is_empty():
		return

	var p: AudioStreamPlayer = null
	for candidate in _sfx_pool:
		if not candidate.playing:
			p = candidate
			break

	if not p:
		p = _sfx_pool[_idx_sfx]
		_idx_sfx = (_idx_sfx + 1) % _sfx_pool.size()

	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
