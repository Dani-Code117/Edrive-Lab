extends Node

## Autoload global que transporta el circuito validado, los checkpoints horarios
## y la configuración de los 3 vehículos entre las vistas de EDrive Lab.

const TAMANIO_CELDA: int = 16
const ANCHO_GRID: int = 45
const ALTO_GRID: int = 27

## Diccionario { Vector2i: true } con todas las celdas de asfalto de la pista.
var celdas_asfalto: Dictionary = {}

## Celda donde se ubica la línea de salida / meta.
var celda_meta: Vector2i = Vector2i(-1, -1)
var tiene_meta: bool = false

## Secuencia ordenada en sentido horario de celdas centrales para los checkpoints.
var ruta_checkpoints: Array[Vector2i] = []
var eje_central: Array[Vector2i] = []
var radios_eje: Array[float] = []
var ancho_pista: float = 48.0
var posicion_salida: Vector2 = Vector2.ZERO
var rotacion_salida: float = 0.0

## Descripciones educativas de los 10 niveles de IA pre-entrenados.
const NIVELES_IA: Array[Dictionary] = [
	{"nivel": 1, "titulo": "Novato Caótico", "desc": "Pesos sin refinar; acelera sin frenar y gira erráticamente."},
	{"nivel": 2, "titulo": "Primeros Reflejos", "desc": "Detecta el muro frontal tarde; intenta esquivar pero roza bordes."},
	{"nivel": 3, "titulo": "Cauteloso Lento", "desc": "Mantiene baja aceleración constante; supera curvas abiertas."},
	{"nivel": 4, "titulo": "Zig-Zag Nervioso", "desc": "Completa rectas y curvas suaves, pero oscila entre los bordes."},
	{"nivel": 5, "titulo": "Conductor Básico", "desc": "Completa circuitos sencillos a velocidad media sin chocar."},
	{"nivel": 6, "titulo": "Trazada Estable", "desc": "Estabiliza la dirección usando los sensores laterales de ±45°."},
	{"nivel": 7, "titulo": "Control de Frenada", "desc": "Reduce aceleración al detectar proximidad en sensores frontales."},
	{"nivel": 8, "titulo": "Piloto Ágil", "desc": "Aprovecha rectas a alta velocidad y anticipa giros cerrados."},
	{"nivel": 9, "titulo": "Ápice Óptimo", "desc": "Busca el interior de las curvas para minimizar distancia."},
	{"nivel": 10, "titulo": "Maestro Autónomo", "desc": "Conducción fluida, rápida y adaptable a cualquier circuito."},
]

## Configuración por defecto de los 3 vehículos competidores (Rojo, Azul, Verde).
var config_vehiculos: Array[Dictionary] = [
	{
		"nombre": "Coche Rojo",
		"color": Color(0.92, 0.24, 0.24, 1.0),
		"velocidad_maxima": 0.80,
		"aceleracion": 0.75,
		"frenado": 0.75,
		"control": 0.80,
		"agarre": 0.80,
		"nivel_ia": 10,
	},
	{
		"nombre": "Coche Azul",
		"color": Color(0.24, 0.55, 0.96, 1.0),
		"velocidad_maxima": 0.65,
		"aceleracion": 0.65,
		"frenado": 0.65,
		"control": 0.70,
		"agarre": 0.70,
		"nivel_ia": 6,
	},
	{
		"nombre": "Coche Verde",
		"color": Color(0.22, 0.82, 0.42, 1.0),
		"velocidad_maxima": 0.55,
		"aceleracion": 0.55,
		"frenado": 0.60,
		"control": 0.60,
		"agarre": 0.60,
		"nivel_ia": 3,
	},
]


func limpiar_pista() -> void:
	celdas_asfalto.clear()
	celda_meta = Vector2i(-1, -1)
	tiene_meta = false
	ruta_checkpoints.clear()
	eje_central.clear()
	radios_eje.clear()
	ancho_pista = 48.0
	posicion_salida = Vector2.ZERO
	rotacion_salida = 0.0


func guardar_pista(
	nuevas_celdas: Dictionary,
	meta: Vector2i,
	checkpoints: Array[Vector2i],
	rot_salida: float,
	nuevo_eje: Array[Vector2i] = [],
	nuevos_radios: Array[float] = [],
	nuevo_ancho: float = 48.0
) -> void:
	celdas_asfalto = nuevas_celdas.duplicate()
	celda_meta = meta
	tiene_meta = true
	ruta_checkpoints = checkpoints.duplicate()
	eje_central = nuevo_eje.duplicate()
	radios_eje = nuevos_radios.duplicate()
	ancho_pista = nuevo_ancho
	posicion_salida = Vector2(meta) * TAMANIO_CELDA + Vector2.ONE * (TAMANIO_CELDA * 0.5)
	rotacion_salida = rot_salida
