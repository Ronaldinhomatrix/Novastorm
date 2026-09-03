class_name PathSpeedZone
extends Resource

## Define um trecho entre dois pontos da curva Path3D com velocidade personalizada.
## Exemplo: Ponto 13 ao 18 com velocidade 150.0 m/s (ou speed_multiplier 0.5)

@export_range(0, 500, 1) var start_point: int = 13  ## Ponto onde a alteracao de velocidade comeca
@export_range(0, 500, 1) var end_point: int = 18    ## Ponto onde a alteracao de velocidade termina

@export_group("Configuracao de Velocidade")
## Se > 0, usa esta velocidade absoluta (ex: 150.0 u/s). Se for 0, usa o multiplicador abaixo.
@export var target_speed: float = 0.0
## Multiplicador em relacao a forward_speed base (ex: 0.5 = metade, 1.5 = +50%, 2.0 = dobro).
## Usado apenas se target_speed for 0.0.
@export_range(0.1, 5.0, 0.05) var speed_multiplier: float = 1.0

@export_group("Transicao Suave")
## Distancia (em metros/unidades ao longo da curva) para acelerar/desacelerar suavemente nas bordas.
@export_range(0.0, 2000.0, 50.0) var blend_distance: float = 300.0
