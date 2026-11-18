extends Node

## Autoload global que transporta el circuito validado, los checkpoints horarios
## y la configuración de los 3 vehículos entre las vistas de EDrive Lab.

const TAMANIO_CELDA: int = 32
const ANCHO_GRID: int = 30
const ALTO_GRID: int = 18

## Diccionario { Vector2i: true } con todas las celdas de asfalto de la pista.
var celdas_asfalto: Dictionary = {}

## Celda donde se ubica la línea de salida / meta.
var celda_meta: Vector2i = Vector2i(-1, -1)
var tiene_meta: bool = false

## Secuencia ordenada en sentido horario de celdas centrales para los checkpoints.
var ruta_checkpoints: Array[Vector2i] = []
var posicion_salida: Vector2 = Vector2.ZERO
var rotacion_salida: float = 0.0

## Configuración por defecto de los 3 vehículos competidores (Rojo, Azul, Verde).
var config_vehiculos: Array[Dictionary] = [
	{
		"nombre": "Coche Rojo",
		"color": Color(0.92, 0.24, 0.24, 1.0),
		"nivel_ia": 10,
		"velocidad": 0.75,
		"agarre": 0.80,
		"reaccion": 0.85,
	},
	{
		"nombre": "Coche Azul",
		"color": Color(0.24, 0.55, 0.96, 1.0),
		"nivel_ia": 6,
		"velocidad": 0.65,
		"agarre": 0.70,
		"reaccion": 0.70,
	},
	{
		"nombre": "Coche Verde",
		"color": Color(0.22, 0.82, 0.42, 1.0),
		"nivel_ia": 3,
		"velocidad": 0.55,
		"agarre": 0.60,
		"reaccion": 0.55,
	},
]


func limpiar_pista() -> void:
	celdas_asfalto.clear()
	celda_meta = Vector2i(-1, -1)
	tiene_meta = false
	ruta_checkpoints.clear()
	posicion_salida = Vector2.ZERO
	rotacion_salida = 0.0


func guardar_pista(
	nuevas_celdas: Dictionary,
	meta: Vector2i,
	checkpoints: Array[Vector2i],
	rot_salida: float
) -> void:
	celdas_asfalto = nuevas_celdas.duplicate()
	celda_meta = meta
	tiene_meta = true
	ruta_checkpoints = checkpoints.duplicate()
	posicion_salida = Vector2(meta) * TAMANIO_CELDA + Vector2.ONE * (TAMANIO_CELDA * 0.5)
	rotacion_salida = rot_salida
