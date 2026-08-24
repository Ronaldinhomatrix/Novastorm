class_name ProceduralCloudSky
extends Node

## Gerador de Céu com Nuvens Estáticas de Ultra Alta Performance (GPU friendly).
## Gera uma imagem de céu + nuvens UMA ÚNICA VEZ em memória RAM ao carregar o nível no jogo.
## Custo por frame na GPU: Praticamente ZERO (apenas leitura de uma textura estática).

@export_category("Cores do Céu")
@export var sky_top_color: Color = Color(0.15, 0.45, 0.88, 1.0)
@export var sky_horizon_color: Color = Color(0.72, 0.85, 0.98, 1.0)
@export var ground_color: Color = Color(0.25, 0.2, 0.18, 1.0)

@export_category("Configuração das Nuvens")
@export_range(0.0, 1.0) var cloud_coverage: float = 0.45  ## Densidade/cobertura das nuvens
@export var cloud_color: Color = Color(0.98, 0.98, 1.0, 0.9)
@export var noise_frequency: float = 0.012  ## Escala/tamanho dos blocos de nuvem

@export_category("Resolução")
@export var texture_width: int = 1024
@export var texture_height: int = 512


func _ready() -> void:
	# Não executa no Editor para evitar salvar bytes binários de imagem no arquivo .tscn da cena
	if Engine.is_editor_hint():
		return

	var env_node := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if not env_node or not env_node.environment:
		return

	var env := env_node.environment
	apply_cloud_sky(env)


## Gera a textura estática de nuvens em memória RAM e aplica ao WorldEnvironment.
func apply_cloud_sky(env: Environment) -> void:
	if env == null:
		return

	# Herda automaticamente as cores do ProceduralSkyMaterial do nível se existente
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var proc_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_top_color = proc_mat.sky_top_color
		sky_horizon_color = proc_mat.sky_horizon_color
		ground_color = proc_mat.ground_bottom_color
		env.set_meta("original_sky_top_color", sky_top_color)
		env.set_meta("original_sky_horizon_color", sky_horizon_color)
		env.set_meta("original_ground_color", ground_color)
	elif env.has_meta("original_sky_top_color"):
		sky_top_color = env.get_meta("original_sky_top_color")
		sky_horizon_color = env.get_meta("original_sky_horizon_color")
		ground_color = env.get_meta("original_ground_color")

	# Tenta carregar textura pré-gerada para tempo zero de inicialização (0ms)
	var prebaked_path := "res://assets/textures/cloud_sky_panorama.png"
	var texture: Texture2D = null
	if ResourceLoader.exists(prebaked_path):
		texture = load(prebaked_path) as Texture2D

	if texture == null:
		var img := _generate_cloud_sky_image()
		texture = ImageTexture.create_from_image(img)

	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = texture

	var sky := Sky.new()
	sky.sky_material = sky_material

	env.background_mode = Environment.BG_SKY
	env.sky = sky


func _generate_cloud_sky_image() -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_frequency
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

	var img := Image.create(texture_width, texture_height, false, Image.FORMAT_RGBA8)

	var inv_w := 1.0 / float(texture_width)
	var inv_h := 1.0 / float(texture_height)
	var min_threshold := 1.0 - cloud_coverage

	for y in range(texture_height):
		var v := float(y) * inv_h
		
		var base_sky: Color
		if v < 0.5:
			var t := v * 2.0
			base_sky = sky_top_color.lerp(sky_horizon_color, t)
		else:
			var t := (v - 0.5) * 2.0
			base_sky = sky_horizon_color.lerp(ground_color, t)

		for x in range(texture_width):
			var u := float(x) * inv_w
			
			if v < 0.48:
				var angle := u * TAU
				var nx := cos(angle) * 150.0
				var ny := sin(angle) * 150.0
				var nz := v * 300.0
				
				var nval := (noise.get_noise_3d(nx, ny, nz) + 1.0) * 0.5
				
				var horizon_fade := clampf((0.48 - v) / 0.3, 0.0, 1.0)
				var cloud_alpha := smoothstep(min_threshold, 1.0, nval) * horizon_fade
				
				var final_color := base_sky.lerp(cloud_color, cloud_alpha * cloud_color.a)
				img.set_pixel(x, y, final_color)
			else:
				img.set_pixel(x, y, base_sky)

	return img
