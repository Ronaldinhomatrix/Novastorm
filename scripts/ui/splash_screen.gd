class_name SplashScreen
extends Node3D

## Splashscreen cinematográfica 3D inspirada na icônica abertura arcade de After Burner II.
##
## Sequência:
##   1. O logo Nivora (Sprite3D) surge suavemente com fade-in e realiza um zoom
##      contínuo e suave em direção à câmera até o instante do impacto.
##   2. Dois mísseis rasantes de alta velocidade disparam de TRÁS da câmera em sequência 1-2
##      (staggered launch), deixando uma densa esteira volumétrica de fumaça branca
##      (baforadas tridimensionais que permanecem ancoradas no espaço do mundo).
##   3. Cada míssil cruza rente à câmera (passando por dentro do plano de visão, fora de quadro,
##      e reaparecendo já colado na lente), descreve um arco pronunciado e agressivo
##      (swoop outward aberto com banking roll aerodinâmico correto na curva)
##      e converge em direção ao logo central.
##   4. No momento do impacto:
##      - O 1º míssil atinge o topo-esquerdo do logo: flash brilhante, som de explosão ensurdecedor,
##        sacudida violenta de câmera e explosão procedural em chamas.
##      - O logo é fisicamente DESPEDAÇADO em centenas de blocos 3D (MultiMeshInstance3D),
##        cada um contendo a fatia exata da textura com iluminação sombreada e bordas chanfradas incandescentes.
##      - Os blocos explodem radialmente em 360° com alta velocidade e rodopiam (tumbling) caoticamente em 3D,
##        com detritos acelerando em direção à câmera (+Z) passando raspando pela tela.
##      - 0.1s depois, o 2º míssil impacta na base-direita, gerando uma segunda detonação que acelera ainda
##        mais a dispersão de todos os fragmentos no espaço.
##   5. Transição suave com fade branco para res://scenes/main_menu.tscn.
##   6. Splashsceen OBRIGATÓRIA: não existe skip. Todo input (teclado, mouse,
##      toque, gamepad) é consumido e o botão "voltar" do Android é bloqueado,
##      tanto em PC quanto em Mobile.

signal splash_finished

# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
const SND_MISSILE: AudioStream = preload("res://assets/audio/missile.ogg")
const SND_EXPLOSION_1: AudioStream = preload("res://assets/audio/explosion1.ogg")
const SND_EXPLOSION_2: AudioStream = preload("res://assets/audio/explosion2.ogg")
const MISSILE_SCENE: PackedScene = preload("res://scenes/projectiles/player_missile.tscn")
const ExplosionScript := preload("res://scripts/effects/explosion.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

# ---------------------------------------------------------------------------
# Timing (segundos)
# ---------------------------------------------------------------------------
@export_group("Timing")
@export var delay_before_missiles: float = 2.4       ## Tempo até o primeiro míssil disparar
@export var missile_launch_stagger: float = 0.08     ## Delay entre o disparo do míssil 0 e míssil 1
@export var missile_flight_duration: float = 1.65    ## Duração do voo em arco do míssil
@export var missile_impact_stagger: float = 0.10     ## Intervalo entre os dois impactos no logo
@export var post_explosion_delay: float = 2.8        ## Tempo para contemplar os estilhaços voando
@export var splash_fps: int = 60                     ## Framerate da splashscreen
@export var fade_duration: float = 0.5               ## Duração da transição branca final

# ---------------------------------------------------------------------------
# Logo & Câmera
# ---------------------------------------------------------------------------
@export_group("Logo & Visual")
@export var logo_distance: float = 110.0             ## Distância do logo à frente da câmera (m)
@export var logo_screen_fraction: float = 0.52       ## Fração da altura da tela ocupada pelo logo
@export var logo_start_scale: float = 0.82           ## Escala inicial do zoom contínuo
@export var logo_end_scale: float = 1.16             ## Escala do logo no momento do impacto
@export var logo_fade_duration: float = 0.8          ## Duração do fade-in inicial do logo

# ---------------------------------------------------------------------------
# Trajetória dos mísseis (Rasante rente à câmera + Arco com Banking Correto)
# ---------------------------------------------------------------------------
# A rota é uma spline Catmull-Rom (centrípeta) que passa exatamente por 4 waypoints:
#   W0 nascimento (ATRÁS da câmera, fora de quadro)
#   W1 rasante (rente à câmera, o momento em que o míssil "encosta" na lente)
#   W2 ápice do arco aberto para fora
#   W3 impacto no logo
# O avanço é reparametrizado por comprimento de arco, então o míssil voa em
# velocidade constante (sem freada/arrancada entre os trechos).
@export_group("Missile Flyby Trajectory")
@export_enum("Opposite Flank (Inverted)", "Cross Diagonal") var trajectory_mode: int = 0 ## Modo da curva dos mísseis
@export var spawn_behind: float = 16.0               ## Distância ATRÁS da câmera onde o míssil nasce (fora de quadro)
# IMPORTANTE: mantenha spawn_* MENOR que flyby_*. O míssil nasce perto do eixo e vai
# abrindo sempre; se nascer mais afastado que o rasante ele "entra" antes de abrir,
# desenhando um S (duas curvas) na tela.
@export var spawn_side: float = 1.6                  ## Deslocamento lateral do nascimento (atrás da câmera)
@export var spawn_vertical: float = 1.0              ## Deslocamento vertical do nascimento (atrás da câmera)
@export var flyby_side: float = 2.4                  ## Deslocamento lateral no ponto de rasante (controla o quanto ele raspa)
@export var flyby_vertical: float = 1.5              ## Deslocamento vertical no ponto de rasante
@export var flyby_distance: float = 2.8              ## Distância à FRENTE da câmera onde acontece o rasante
@export var arc_flare_x: float = 20.0                ## Amplitude lateral do ápice do arco (maior = arco mais aberto e gancho final mais fechado)
@export var arc_flare_y: float = 1.5                 ## Altura do ápice em relação à linha de centro (o arco cruza o centro aqui)
@export var arc_flare_z: float = 52.0                ## Posição Z do ápice da curva aberta
@export var bank_angle_degrees: float = 50.0         ## Inclinação lateral máxima (roll) na curva
@export var impact_offset_x: float = 0.35            ## Deslocamento X relativo do ponto de impacto
@export var impact_offset_y: float = 0.28            ## Deslocamento Y relativo do ponto de impacto
@export_range(32, 512, 8) var path_samples: int = 128 ## Resolução da tabela de comprimento de arco

# ---------------------------------------------------------------------------
# Visual dos Mísseis & Fumaça Volumétrica
# ---------------------------------------------------------------------------
@export_group("Missile & Smoke Visuals")
@export var missile_scale: float = 1.6               ## Escala do modelo 3D do míssil na splash
@export var missile_smoke_amount: int = 500          ## Quantidade de partículas de fumaça na esteira
@export var missile_smoke_scale: float = 0.9         ## Fator de escala das baforadas de fumaça
@export var missile_smoke_lifetime: float = 3.2      ## Tempo de vida da fumaça suspensa no ar
@export var missile_smoke_opacity: float = 0.35      ## Multiplicador de opacidade da fumaça (35% = baforadas bem transparentes)
@export var missile_smoke_growth: float = 2.4        ## Escala máxima que cada baforada atinge ao longo da vida
@export var missile_smoke_spread: float = 0.0        ## Abertura do cone de emissão da fumaça em graus (0 = rastro reto, sem leque diagonal)
@export var smoke_proximity_fade: float = 12.0       ## Distância (m) em que a fumaça desvanece perto da câmera (0 = desligado)
@export var missile_smoke_preprocess: float = 0.18   ## Warm-up da esteira (s): aquece o sistema no disparo para a fumaça já nascer cheia em vez de subir do zero

# ---------------------------------------------------------------------------
# Despedaçamento 3D do Logo (Physical Shatter - Expansão Lenta e Majestosa)
# ---------------------------------------------------------------------------
@export_group("Logo Shatter")
@export var shatter_grid_size: int = 18              ## Resolução da grade de blocos (18x18 = 324 blocos)
@export var shatter_block_depth: float = 0.55        ## Espessura 3D de cada bloco
@export var shatter_radial_speed_min: float = 9.0    ## Velocidade radial mínima de expansão
@export var shatter_radial_speed_max: float = 20.0   ## Velocidade radial máxima de expansão
@export var shatter_forward_speed_min: float = 6.0   ## Velocidade em direção à câmera mínima (+Z)
@export var shatter_forward_speed_max: float = 15.0  ## Velocidade em direção à câmera máxima (+Z)
@export var shatter_tumble_speed_min: float = 1.0    ## Velocidade de rotação mínima dos blocos
@export var shatter_tumble_speed_max: float = 2.6    ## Velocidade de rotação máxima dos blocos
@export var camera_shake_intensity: float = 2.6      ## Intensidade do shake de câmera (deslocamento em unidades)
@export var camera_shake_roll: float = 0.006         ## Rotação (roll) máxima do shake em radianos
@export_range(0.0, 1.0, 0.01) var impact_flash_opacity: float = 0.10 ## Opacidade do clarão branco no impacto (menor = flash mais discreto)
@export_range(0.05, 1.0, 0.05) var explosion_brightness: float = 0.35 ## Brilho do núcleo da explosão na splash (menor = menos estourado)

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------
var _logo: Sprite3D = null
var _camera: Camera3D = null
var _camera_base_pos: Vector3 = Vector3.ZERO
var _flash_rect: ColorRect = null
var _sound_manager: Node = null

var _zoom_tween: Tween = null
var _flash_tween: Tween = null
var _missiles: Array[Dictionary] = []
var _chunks: Array[Dictionary] = []

var _shatter_instance: MultiMeshInstance3D = null
var _shatter_multimesh: MultiMesh = null
var _shatter_active: bool = false
var _shatter_elapsed: float = 0.0

var _shake_time: float = 0.0
var _shake_intensity: float = 0.0
var _is_transitioning: bool = false
var _prev_quit_on_go_back: bool = true


func _ready() -> void:
	Engine.max_fps = splash_fps
	_lock_inputs()
	_sound_manager = get_node_or_null("/root/SoundManager")
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera:
		_camera_base_pos = _camera.position

	_logo = get_node_or_null("Logo") as Sprite3D

	var flash_overlay := get_node_or_null("FlashOverlay")
	if flash_overlay:
		_flash_rect = flash_overlay.get_node_or_null("FlashRect") as ColorRect

	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)

	_apply_user_graphics_settings()
	_setup_logo()
	_setup_shatter_system()
	_run_sequence()


## Configura o tamanho e posicionamento do logo na distância especificada.
func _setup_logo() -> void:
	if not _logo:
		return
	_logo.position = Vector3(0.0, 0.0, -logo_distance)
	if _logo.texture and _camera:
		var screen_h := 2.0 * logo_distance * tan(deg_to_rad(_camera.fov * 0.5))
		var world_size := logo_screen_fraction * screen_h
		_logo.pixel_size = world_size / float(_logo.texture.get_height())


func _get_logo_half() -> float:
	if _logo and _logo.texture:
		return _logo.texture.get_height() * _logo.pixel_size * 0.5
	return 32.0


func _get_is_mobile() -> bool:
	if has_node("/root/GameConfig"):
		var gc = get_node("/root/GameConfig")
		return bool(gc.get("is_mobile"))
	return false


func _apply_user_graphics_settings() -> void:
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if not env_node or not env_node.environment:
		return
	if has_node("/root/UserSettings"):
		var us = get_node("/root/UserSettings")
		if us.has_method("get_glow"):
			env_node.environment.glow_enabled = us.get_glow()


## Constrói a malha e os dados do sistema de fragmentação 3D (MultiMeshInstance3D).
func _setup_shatter_system() -> void:
	if not _logo or not _logo.texture:
		return

	var is_mobile := _get_is_mobile()
	var grid: int = 14 if is_mobile else shatter_grid_size
	var total_instances: int = grid * grid

	var logo_w: float = _logo.texture.get_width() * _logo.pixel_size
	var logo_h: float = _logo.texture.get_height() * _logo.pixel_size
	var chunk_w: float = logo_w / float(grid)
	var chunk_h: float = logo_h / float(grid)
	var chunk_d: float = shatter_block_depth

	var box := BoxMesh.new()
	box.size = Vector3(chunk_w * 0.99, chunk_h * 0.99, chunk_d)

	# Shader espacial com depth prepass e mapeamento preciso por coordenadas de vértice
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D logo_texture : source_color, filter_linear_mipmap;
uniform vec3 box_size;

varying vec4 v_custom_data;
varying vec2 v_face_uv;
varying float v_is_front;
varying float v_is_back;

void vertex() {
	v_custom_data = INSTANCE_CUSTOM;
	v_face_uv = vec2((VERTEX.x / box_size.x) + 0.5, 0.5 - (VERTEX.y / box_size.y));
	v_is_front = NORMAL.z > 0.6 ? 1.0 : 0.0;
	v_is_back = NORMAL.z < -0.6 ? 1.0 : 0.0;
}

void fragment() {
	vec2 custom_uv = v_custom_data.xy + v_face_uv * v_custom_data.zw;
	vec4 tex = texture(logo_texture, custom_uv);
	if (tex.a * COLOR.a < 0.02) {
		discard;
	}
	if (v_is_front > 0.5) {
		ALBEDO = tex.rgb * COLOR.rgb;
		EMISSION = tex.rgb * 0.25 * COLOR.rgb;
		ROUGHNESS = 0.35;
		METALLIC = 0.15;
	} else if (v_is_back > 0.5) {
		ALBEDO = tex.rgb * 0.5 * COLOR.rgb;
		ROUGHNESS = 0.6;
		METALLIC = 0.2;
	} else {
		vec3 edge_col = mix(vec3(0.18, 0.20, 0.22), vec3(1.4, 0.65, 0.15), 0.4);
		ALBEDO = edge_col * COLOR.rgb;
		EMISSION = vec3(0.8, 0.3, 0.05) * 0.5 * COLOR.rgb;
		ROUGHNESS = 0.45;
		METALLIC = 0.5;
	}
	ALPHA = tex.a * COLOR.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("logo_texture", _logo.texture)
	mat.set_shader_parameter("box_size", box.size)
	box.material = mat

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = total_instances
	multimesh.mesh = box

	_shatter_multimesh = multimesh
	_shatter_instance = MultiMeshInstance3D.new()
	_shatter_instance.name = "ShatterMesh"
	_shatter_instance.multimesh = multimesh
	_shatter_instance.visible = false
	add_child(_shatter_instance)

	_chunks.clear()
	for r in range(grid):
		for c in range(grid):
			var idx: int = r * grid + c
			var u_off := float(c) / float(grid)
			var v_off := float(r) / float(grid)
			var u_sz := 1.0 / float(grid)
			var v_sz := 1.0 / float(grid)

			var local_x := -logo_w * 0.5 + (c + 0.5) * chunk_w
			var local_y := logo_h * 0.5 - (r + 0.5) * chunk_h

			_chunks.append({
				"index": idx,
				"local_pos": Vector3(local_x, local_y, 0.0),
				"pos": Vector3.ZERO,
				"vel": Vector3.ZERO,
				"rot": Basis(),
				"ang_axis": Vector3.UP,
				"ang_speed": 0.0,
				"scale": 1.0,
			})
			multimesh.set_instance_custom_data(idx, Color(u_off, v_off, u_sz, v_sz))
			multimesh.set_instance_color(idx, Color(1, 1, 1, 1))
			multimesh.set_instance_transform(idx, Transform3D(Basis(), Vector3(local_x, local_y, -logo_distance)))


# ---------------------------------------------------------------------------
# Sequência Principal
# ---------------------------------------------------------------------------

func _run_sequence() -> void:
	_start_continuous_zoom()

	var tree := get_tree()
	if not tree:
		return

	await tree.create_timer(delay_before_missiles).timeout
	if _is_transitioning or not is_inside_tree():
		return

	# Lançamento rápido em 1-2 (arcade staggered salvo)
	_launch_missile(0)
	_play_missile_sound(0.98)

	await tree.create_timer(missile_launch_stagger).timeout
	if _is_transitioning or not is_inside_tree():
		return

	_launch_missile(1)
	_play_missile_sound(1.06)


func _start_continuous_zoom() -> void:
	if not _logo:
		return
	var zoom_time := delay_before_missiles + missile_flight_duration + missile_impact_stagger
	_logo.scale = Vector3.ONE * logo_start_scale
	_logo.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(_logo, "scale", Vector3.ONE * logo_end_scale, zoom_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(_logo, "modulate:a", 1.0, logo_fade_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _launch_missile(index: int) -> void:
	var path := _compute_missile_path(index)
	var flight_duration := missile_flight_duration
	if index == 1:
		# Míssil 1 atinge o logo com o stagger programado
		flight_duration = (missile_flight_duration + missile_impact_stagger) - missile_launch_stagger

	var missile := MISSILE_SCENE.instantiate() as Node3D
	missile.set_script(null)
	var col := missile.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.disabled = true
	add_child(missile)
	missile.global_position = path["points"][0]

	_apply_splash_missile_look(missile)

	_missiles.append({
		"index": index,
		"node": missile,
		"points": path["points"],
		"arc_u": path["arc_u"],
		"arc_cum": path["arc_cum"],
		"p3": path["p3"],
		"t": 0.0,
		"flight_duration": flight_duration,
		"state": "flying",
	})


## Aplica o visual arcade e a esteira volumétrica de fumaça ao míssil.
func _apply_splash_missile_look(missile: Node3D) -> void:
	var is_mobile := _get_is_mobile()

	var body := missile.get_node_or_null("MissileBody") as Node3D
	if body:
		body.scale = Vector3.ONE * missile_scale

	var glow := missile.get_node_or_null("MissileBody/EngineGlowMesh") as MeshInstance3D
	if glow:
		glow.scale = Vector3.ONE * 1.5

	# Luz dinâmica de queima do motor (apenas em PC para máxima fidelidade)
	if not is_mobile:
		var light := OmniLight3D.new()
		light.name = "ThrusterLight"
		light.light_color = Color(1.0, 0.75, 0.35)
		light.light_energy = 5.0
		light.omni_range = 8.0
		missile.add_child(light)
		light.position = Vector3(0.0, 0.0, 1.2 * missile_scale)

	var smoke := missile.get_node_or_null("SmokeTrail") as CPUParticles3D
	if smoke:
		smoke.local_coords = false
		smoke.position = Vector3(0.0, 0.0, 1.0 * missile_scale)
		smoke.amount = int(missile_smoke_amount * 0.45) if is_mobile else missile_smoke_amount
		smoke.lifetime = missile_smoke_lifetime
		smoke.direction = Vector3(0.0, 0.0, 1.0)
		smoke.spread = missile_smoke_spread
		smoke.gravity = Vector3(0.0, 0.4, 0.0)
		smoke.initial_velocity_min = 1.5
		smoke.initial_velocity_max = 3.5
		smoke.scale_amount_min = 1.2 * missile_smoke_scale
		smoke.scale_amount_max = 2.4 * missile_smoke_scale

		var curve := Curve.new()
		var growth := maxf(missile_smoke_growth, 0.1)
		curve.add_point(Vector2(0.0, 0.12 * growth))
		curve.add_point(Vector2(0.15, 0.38 * growth))
		curve.add_point(Vector2(0.5, 0.69 * growth))
		curve.add_point(Vector2(1.0, growth))
		smoke.scale_amount_curve = curve

		var opacity := clampf(missile_smoke_opacity, 0.0, 1.0)
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.05, 0.15, 0.5, 0.8, 1.0])
		ramp.colors = PackedColorArray([
			Color(2.2, 1.4, 0.4, 0.95 * opacity),    # Chama inicial do propulsor
			Color(1.1, 0.7, 0.2, 0.85 * opacity),    # Borda incandescente
			Color(0.95, 0.95, 0.98, 0.85 * opacity), # Baforada branca densa
			Color(0.8, 0.82, 0.85, 0.65 * opacity),  # Nuvem volumétrica cinza
			Color(0.5, 0.52, 0.55, 0.35 * opacity),  # Fumaça dispersando
			Color(0.25, 0.26, 0.28, 0.0)             # Dissipação total
		])
		smoke.color_ramp = ramp

		_apply_smoke_proximity_fade(smoke)

		# Warm-up da esteira: o Godot só aquece o sistema quando ele (re)inicia com o
		# relógio interno zerado (cpu_particles_3d.cpp: _update_internal() roda
		# `todo = pre_process_time` apenas quando time == 0) e set_pre_process_time()
		# por si só não reinicia nada. Como o míssil já entrou na árvore emitindo com
		# preprocess = 0, o restart() é obrigatório para o warm-up realmente rodar.
		#
		# MEDIDO (PC, 1920x1080, frames congelados): o warm-up aquece o sistema na
		# posição ATUAL do emissor — no W0 isso é 16 m ATRÁS da câmera, fora de quadro.
		# Ele NÃO pré-preenche a esteira visível: os frames em t=2,62 s (míssil cruzando
		# a lente, ainda sem fumaça) e em t=3,00 s ficaram visualmente idênticos com
		# preprocess 0,0 / 0,18 / 4,0. A esteira visível é, por definição, o histórico das
		# posições do míssil À FRENTE da câmera. O parâmetro fica exposto para ajuste e
		# experimentação; para a fumaça "aparecer mais cedo" o que pesa é densidade
		# (missile_smoke_amount) e smoke_proximity_fade.
		smoke.preprocess = maxf(missile_smoke_preprocess, 0.0)
		if smoke.preprocess > 0.0:
			smoke.restart()


## Aplica "proximity fade" à fumaça da splash.
##
## A esteira fica ancorada no espaço do mundo (local_coords = false). Como os mísseis
## agora passam rente à câmera, as baforadas emitidas perto da lente crescem até ~6
## unidades e acabam "lavando" a tela inteira, escondendo o logo. O proximity fade
## desvanece apenas o que está colado na câmera, preservando a esteira em si.
##
## O material é duplicado (malha + material) para NÃO afetar o míssil de gameplay,
## que compartilha o mesmo recurso de cena.
func _apply_smoke_proximity_fade(smoke: CPUParticles3D) -> void:
	if smoke_proximity_fade <= 0.0 or not smoke.mesh:
		return

	var mesh_dup := smoke.mesh.duplicate() as PrimitiveMesh
	if not mesh_dup:
		return

	var mat := mesh_dup.material
	var mat_dup: StandardMaterial3D
	if mat:
		mat_dup = mat.duplicate() as StandardMaterial3D
	else:
		mat_dup = StandardMaterial3D.new()
	if not mat_dup:
		return
	mat_dup.proximity_fade_enabled = true
	mat_dup.proximity_fade_distance = smoke_proximity_fade
	mesh_dup.material = mat_dup
	smoke.mesh = mesh_dup


## Monta os 4 waypoints da rota do míssil e pré-calcula a tabela de comprimento de arco.
func _compute_missile_path(index: int) -> Dictionary:
	# Míssil 0: nasce atrás/baixo-esquerda  |  Míssil 1: nasce atrás/cima-direita
	var sign_x := -1.0 if index == 0 else 1.0
	var sign_y := -1.0 if index == 0 else 1.0
	var logo_half := _get_logo_half()

	# W0: nasce ATRÁS da câmera (z positivo), deslocado para fora do quadro.
	var w0 := Vector3(sign_x * spawn_side, sign_y * spawn_vertical, spawn_behind)

	# W1: rasante — passa raspando pela câmera, logo à frente da lente.
	var w1 := Vector3(sign_x * flyby_side, sign_y * flyby_vertical, -flyby_distance)

	var w2: Vector3
	var w3: Vector3

	if trajectory_mode == 0:
		# Modo 0: Flancos opostos (Inversão Rotacional)
		# O arco abre para FORA no eixo X e cruza a linha de centro no eixo Y,
		# fechando num gancho suave em direção ao logo (sem "mergulhar" abaixo).
		w2 = Vector3(sign_x * arc_flare_x, -sign_y * arc_flare_y, -arc_flare_z)
		w3 = Vector3(
			sign_x * (logo_half * impact_offset_x),
			-sign_y * (logo_half * impact_offset_y),
			-logo_distance
		)
	else:
		# Modo 1: Cruzamento Diagonal
		# Mesmo arco, porém cruzando já o eixo X no ápice.
		w2 = Vector3(-sign_x * arc_flare_x, -sign_y * arc_flare_y, -arc_flare_z)
		w3 = Vector3(
			-sign_x * (logo_half * impact_offset_x),
			-sign_y * (logo_half * impact_offset_y),
			-logo_distance
		)

	var points := PackedVector3Array([w0, w1, w2, w3])
	var arc := _build_arc_table(points, path_samples)
	return {"points": points, "arc_u": arc[0], "arc_cum": arc[1], "p3": w3}


## Pré-calcula t -> comprimento de arco acumulado, permitindo vôo em velocidade constante.
func _build_arc_table(points: PackedVector3Array, samples: int) -> Array:
	var total := maxi(samples, 8)
	var us := PackedFloat32Array()
	var cum := PackedFloat32Array()
	var prev := _catmull_rom(points, 0.0)
	us.append(0.0)
	cum.append(0.0)
	for i in range(1, total + 1):
		var u := float(i) / float(total)
		var p := _catmull_rom(points, u)
		us.append(u)
		cum.append(cum[cum.size() - 1] + prev.distance_to(p))
		prev = p
	return [us, cum]


## Converte o tempo normalizado (0..1) no parâmetro u da spline, por comprimento de arco.
func _arc_u_at(m: Dictionary, t: float) -> float:
	var cum: PackedFloat32Array = m["arc_cum"]
	var us: PackedFloat32Array = m["arc_u"]
	var last := cum.size() - 1
	var target := clampf(t, 0.0, 1.0) * cum[last]
	var lo := 0
	var hi := last
	while lo < hi - 1:
		var mid := int((lo + hi) * 0.5)
		if cum[mid] <= target:
			lo = mid
		else:
			hi = mid
	var span := cum[hi] - cum[lo]
	var w := 0.0 if span < 0.000001 else (target - cum[lo]) / span
	return lerpf(us[lo], us[hi], w)


## Spline Catmull-Rom centrípeta: passa exatamente por todos os waypoints da rota.
func _catmull_rom(points: PackedVector3Array, t: float) -> Vector3:
	var count := points.size()
	if count == 0:
		return Vector3.ZERO
	if count == 1:
		return points[0]

	var segments := count - 1
	var scaled := clampf(t, 0.0, 1.0) * float(segments)
	var seg := mini(int(scaled), segments - 1)
	var local := scaled - float(seg)

	var p0 := points[maxi(seg - 1, 0)]
	var p1 := points[seg]
	var p2 := points[seg + 1]
	var p3 := points[mini(seg + 2, count - 1)]
	return _catmull_rom_segment(p0, p1, p2, p3, local)


func _catmull_rom_segment(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# Nós centrípetos (alpha = 0.5): evita laços e overshoot quando os trechos
	# têm comprimentos muito diferentes (nascimento curto x arco longo).
	var t0 := 0.0
	var t1 := t0 + _knot_delta(p0, p1)
	var t2 := t1 + _knot_delta(p1, p2)
	var t3 := t2 + _knot_delta(p2, p3)
	var tt := t1 + (t2 - t1) * t
	var a1 := _knot_lerp(p0, p1, t0, t1, tt)
	var a2 := _knot_lerp(p1, p2, t1, t2, tt)
	var a3 := _knot_lerp(p2, p3, t2, t3, tt)
	var b1 := _knot_lerp(a1, a2, t0, t2, tt)
	var b2 := _knot_lerp(a2, a3, t1, t3, tt)
	return _knot_lerp(b1, b2, t1, t2, tt)


func _knot_delta(a: Vector3, b: Vector3) -> float:
	return maxf(sqrt(a.distance_to(b)), 0.000001)


func _knot_lerp(a: Vector3, b: Vector3, ta: float, tb: float, tt: float) -> Vector3:
	var span := tb - ta
	if absf(span) < 0.000001:
		return a
	return a * ((tb - tt) / span) + b * ((tt - ta) / span)


# ---------------------------------------------------------------------------
# Loop de Processamento
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_missiles(delta)
	_update_shatter(delta)
	_update_camera_shake(delta)


func _update_missiles(delta: float) -> void:
	for m in _missiles:
		if m["state"] == "flying":
			m["t"] += delta / m["flight_duration"]
			if m["t"] >= 1.0:
				m["t"] = 1.0
				_advance_missile(m)
				_on_missile_hit(m)
			else:
				_advance_missile(m)
		elif m["state"] == "dissipating":
			m["dissipate"] -= delta
			if m["dissipate"] <= 0.0:
				m["state"] = "gone"
				var node: Node3D = m["node"]
				if is_instance_valid(node):
					node.queue_free()


func _advance_missile(m: Dictionary) -> void:
	var t: float = m["t"]
	var points: PackedVector3Array = m["points"]

	var pos := _catmull_rom(points, _arc_u_at(m, t))

	var node: Node3D = m["node"]
	if not is_instance_valid(node):
		return

	node.global_position = pos

	# Tangente por diferença central no parâmetro da spline (estável nas pontas).
	var eps := 0.01
	var u_prev := _arc_u_at(m, maxf(t - eps, 0.0))
	var u_next := _arc_u_at(m, minf(t + eps, 1.0))
	var tangent := _catmull_rom(points, u_next) - _catmull_rom(points, u_prev)
	if not tangent.is_zero_approx():
		node.look_at(pos + tangent, Vector3.UP)
		var sign_x := -1.0 if m["index"] == 0 else 1.0
		# Banking roll aerodinâmico correto (inclina para o lado da curva)
		var roll := sign_x * deg_to_rad(bank_angle_degrees) * sin(t * PI)
		node.rotate_object_local(Vector3.FORWARD, roll)


# ---------------------------------------------------------------------------
# Impacto, Explosão & Despedaçamento Físico do Logo
# ---------------------------------------------------------------------------

func _on_missile_hit(m: Dictionary) -> void:
	if m["state"] != "flying":
		return

	m["state"] = "dissipating"
	m["dissipate"] = missile_smoke_lifetime + 0.5

	var node: Node3D = m["node"]
	if is_instance_valid(node):
		var body := node.get_node_or_null("MissileBody") as Node3D
		if body:
			body.visible = false
		var light := node.get_node_or_null("ThrusterLight") as OmniLight3D
		if light:
			light.visible = false
		var smoke := node.get_node_or_null("SmokeTrail") as CPUParticles3D
		if smoke:
			smoke.emitting = false

	var hit_pos: Vector3 = m["p3"]
	_spawn_explosion(hit_pos)

	if m["index"] == 0:
		# 1º Impacto: Despedaça o logo fisicamente
		_trigger_flash(Color(1.0, 0.98, 0.92, impact_flash_opacity), 0.22)
		_shake_time = 0.45
		_shake_intensity = camera_shake_intensity
		_play_sfx(SND_EXPLOSION_1, -1.0, 1.0)
		_trigger_shatter(hit_pos)
	else:
		# 2º Impacto: Adiciona impulso secundário violento a todos os blocos
		_trigger_flash(Color(1.0, 0.90, 0.75, impact_flash_opacity * 0.87), 0.20)
		_shake_time = 0.55
		_shake_intensity = camera_shake_intensity * 1.15
		_play_sfx(SND_EXPLOSION_2, -0.5, 1.05)
		_add_shatter_impulse(hit_pos)

	if _all_missiles_done():
		_schedule_finish()


func _trigger_shatter(hit_point: Vector3) -> void:
	if _shatter_active or not _shatter_multimesh or not _logo:
		return
	_shatter_active = true

	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()

	var current_scale := _logo.scale.x
	var logo_center := _logo.global_position
	_logo.visible = false
	_shatter_instance.visible = true

	var logo_half := _get_logo_half() * current_scale

	for chunk in _chunks:
		var initial_pos: Vector3 = logo_center + chunk["local_pos"] * current_scale
		chunk["pos"] = initial_pos
		chunk["rot"] = Basis()
		chunk["scale"] = current_scale

		var to_chunk: Vector3 = initial_pos - hit_point
		var dist: float = to_chunk.length()
		var dir_xy := Vector2(to_chunk.x, to_chunk.y)
		var dir_norm := dir_xy.normalized() if dir_xy.length_squared() > 0.001 else Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

		var proximity := clampf(1.0 - dist / (logo_half * 1.8), 0.25, 1.25)
		var rad_speed := randf_range(shatter_radial_speed_min, shatter_radial_speed_max) * proximity + randf_range(3.0, 9.0)

		# Velocidade para frente (+Z): blocos voam em direção à câmera passando raspando
		var forward_z := randf_range(shatter_forward_speed_min, shatter_forward_speed_max) * proximity + randf_range(-3.5, 6.0)

		chunk["vel"] = Vector3(
			dir_norm.x * rad_speed + randf_range(-2.5, 2.5),
			dir_norm.y * rad_speed + randf_range(-2.5, 2.5),
			forward_z
		)

		# Rodopio 3D suave (tumbling com velocidade suave)
		chunk["ang_axis"] = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		chunk["ang_speed"] = randf_range(shatter_tumble_speed_min, shatter_tumble_speed_max)

		# Queima incandescente e chamuscada nos fragmentos centrais
		var burn := clampf(1.0 - dist / (logo_half * 1.2), 0.0, 1.0)
		var chunk_color := Color(1.0 - burn * 0.35, 1.0 - burn * 0.55, 1.0 - burn * 0.65, 1.0)

		var xform := Transform3D(Basis().scaled(Vector3.ONE * current_scale), initial_pos)
		_shatter_multimesh.set_instance_transform(chunk["index"], xform)
		_shatter_multimesh.set_instance_color(chunk["index"], chunk_color)


func _add_shatter_impulse(hit_point: Vector3) -> void:
	if not _shatter_active:
		return

	var logo_half := _get_logo_half()
	for chunk in _chunks:
		var to_chunk: Vector3 = chunk["pos"] - hit_point
		var dist: float = to_chunk.length()
		var dir_xy := Vector2(to_chunk.x, to_chunk.y)
		var dir_norm := dir_xy.normalized() if dir_xy.length_squared() > 0.001 else Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

		var proximity := clampf(1.0 - dist / (logo_half * 1.8), 0.2, 1.0)
		# Impulso secundário proporcional às velocidades base, para que ajustar
		# shatter_*_speed_* no Inspetor continue escalando as duas detonações juntas.
		var impulse_radial := randf_range(shatter_radial_speed_min, shatter_radial_speed_max) * 0.60
		var impulse_forward := randf_range(shatter_forward_speed_min, shatter_forward_speed_max) * 0.55
		chunk["vel"].x += dir_norm.x * impulse_radial * proximity
		chunk["vel"].y += dir_norm.y * impulse_radial * proximity
		chunk["vel"].z += impulse_forward * proximity
		chunk["ang_speed"] += randf_range(shatter_tumble_speed_min, shatter_tumble_speed_max) * 0.65


func _update_shatter(delta: float) -> void:
	if not _shatter_active or not _shatter_multimesh:
		return

	_shatter_elapsed += delta
	var fade_start := post_explosion_delay * 0.55
	var fade_remaining := maxf(post_explosion_delay - fade_start, 0.1)
	var alpha := 1.0
	if _shatter_elapsed > fade_start:
		alpha = clampf(1.0 - (_shatter_elapsed - fade_start) / fade_remaining, 0.0, 1.0)

	var drag := 0.10
	for chunk in _chunks:
		chunk["pos"] += chunk["vel"] * delta
		chunk["vel"] *= (1.0 - drag * delta)
		chunk["rot"] = chunk["rot"].rotated(chunk["ang_axis"], chunk["ang_speed"] * delta).orthonormalized()

		var xform := Transform3D(chunk["rot"].scaled(Vector3.ONE * chunk["scale"]), chunk["pos"])
		_shatter_multimesh.set_instance_transform(chunk["index"], xform)
		_shatter_multimesh.set_instance_color(chunk["index"], Color(1, 1, 1, alpha))


func _all_missiles_done() -> bool:
	if _missiles.size() < 2:
		return false
	for m in _missiles:
		if m["state"] == "flying":
			return false
	return true


func _schedule_finish() -> void:
	if _is_transitioning:
		return
	var tree := get_tree()
	if tree:
		await tree.create_timer(post_explosion_delay).timeout
	if _is_transitioning or not is_inside_tree():
		return
	_is_transitioning = true
	_on_splash_finished()


# ---------------------------------------------------------------------------
# Flash & Shake de Câmera
# ---------------------------------------------------------------------------

func _trigger_flash(color: Color, duration: float) -> void:
	if not _flash_rect:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_flash_rect.color = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, duration) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _update_camera_shake(delta: float) -> void:
	if not _camera:
		return

	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var falloff := _shake_time / 0.55
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-0.5, 0.5)
		) * _shake_intensity * falloff
		_camera.position = _camera_base_pos + offset
		_camera.rotation.z = randf_range(-camera_shake_roll, camera_shake_roll) * falloff
	else:
		_camera.position = _camera_base_pos
		_camera.rotation.z = 0.0


# ---------------------------------------------------------------------------
# Explosão e Efeitos
# ---------------------------------------------------------------------------

func _spawn_explosion(pos: Vector3) -> void:
	var explosion: Node3D = ExplosionScript.new()
	var logo_half := _get_logo_half()
	explosion.set("size_scale", logo_half * 0.45)
	explosion.set("enable_flash", false)
	# O núcleo aditivo em HDR satura a tela inteira de branco; na splash ele é
	# atenuado para o clarão não "apagar" a logo no instante do impacto.
	explosion.set("brightness", explosion_brightness)
	add_child(explosion)
	explosion.global_position = pos


func _play_missile_sound(pitch: float = 1.0) -> void:
	_play_sfx(SND_MISSILE, -5.0, pitch)


func _play_sfx(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if _sound_manager and _sound_manager.has_method("play_sfx"):
		_sound_manager.play_sfx(stream, volume_db, pitch)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.bus = "Master"
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


# ---------------------------------------------------------------------------
# Bloqueio de Input & Transição para o Menu Principal
# ---------------------------------------------------------------------------

## A splashscreen é OBRIGATÓRIA: não existe skip. Consumimos TODO evento de input
## (teclado, mouse, toque, gamepad) aqui, antes que qualquer outro nó — inclusive
## Controles de UI — possa reagir e interromper a sequência.
func _input(_event: InputEvent) -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


## Bloqueia o encerramento da splash pelo botão/gesto "voltar" do Android.
## O valor original é restaurado ao sair, para não alterar o resto do jogo.
func _lock_inputs() -> void:
	var tree := get_tree()
	if tree:
		_prev_quit_on_go_back = tree.quit_on_go_back
		tree.quit_on_go_back = false


func _restore_inputs() -> void:
	var tree := get_tree()
	if tree:
		tree.quit_on_go_back = _prev_quit_on_go_back


func _exit_tree() -> void:
	# Rede de segurança: garante a restauração mesmo se a cena for trocada
	# por outro caminho que não seja _transition_to_main_menu().
	_restore_inputs()


func _on_splash_finished() -> void:
	splash_finished.emit()
	_transition_to_main_menu()


func _restore_engine_fps() -> void:
	if has_node("/root/GameConfig"):
		var gc = get_node("/root/GameConfig")
		var is_mobile = bool(gc.get("is_mobile"))
		Engine.max_fps = gc.get("MAX_FPS_MOBILE") if is_mobile else gc.get("MAX_FPS_PC")
	else:
		Engine.max_fps = 0


func _transition_to_main_menu() -> void:
	_restore_engine_fps()
	_restore_inputs()
	var tree := get_tree()
	if not tree:
		return
	tree.change_scene_to_file(MAIN_MENU_SCENE)
