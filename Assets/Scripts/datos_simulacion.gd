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

const ARQUETIPO_PERSONALIZADO: String = "Personalizado"
const ORDEN_ARQUETIPOS: Array[String] = ["Equilibrado", "Velocista", "Drift", "Técnico"]
const CLAVES_ATRIBUTOS_VEHICULO: Array[String] = [
	"velocidad_maxima",
	"aceleracion",
	"frenado",
	"control",
	"agarre",
]

const ARQUETIPOS_VEHICULO: Dictionary = {
	"Equilibrado": {
		"velocidad_maxima": 0.50,
		"aceleracion": 0.50,
		"frenado": 0.50,
		"control": 0.50,
		"agarre": 0.50,
	},
	"Velocista": {
		"velocidad_maxima": 0.95,
		"aceleracion": 0.85,
		"frenado": 0.55,
		"control": 0.40,
		"agarre": 0.40,
	},
	"Drift": {
		"velocidad_maxima": 0.75,
		"aceleracion": 0.85,
		"frenado": 0.55,
		"control": 0.85,
		"agarre": 0.25,
	},
	"Técnico": {
		"velocidad_maxima": 0.60,
		"aceleracion": 0.70,
		"frenado": 0.90,
		"control": 0.90,
		"agarre": 0.90,
	},
}

## Configuración por defecto de los 3 vehículos competidores (Rojo, Azul, Verde).
var config_vehiculos: Array[Dictionary] = _crear_config_vehiculos_defecto()


static func _crear_config_vehiculos_defecto() -> Array[Dictionary]:
	return [
		{
			"nombre": "Coche Rojo",
			"color": Color(0.92, 0.24, 0.24, 1.0),
			"velocidad_maxima": 0.80,
			"aceleracion": 0.75,
			"frenado": 0.75,
			"control": 0.80,
			"agarre": 0.80,
			"nivel_ia": 10,
			"arquetipo": ARQUETIPO_PERSONALIZADO,
			"es_humano": false,
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
			"arquetipo": ARQUETIPO_PERSONALIZADO,
			"es_humano": false,
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
			"arquetipo": ARQUETIPO_PERSONALIZADO,
			"es_humano": false,
		},
	]


static func sanitizar_normalizado(valor: Variant, defecto: float = 0.5) -> float:
	var num := defecto
	if valor is float or valor is int:
		num = float(valor)
	elif valor is String and (valor as String).is_valid_float():
		num = float(valor)
	if not is_finite(num):
		num = defecto
	return clampf(num, 0.0, 1.0)


static func sanitizar_nivel_ia(valor: Variant, defecto: int = 5) -> int:
	var num := float(defecto)
	if valor is float or valor is int:
		num = float(valor)
	elif valor is String and (valor as String).is_valid_float():
		num = float(valor)
	if not is_finite(num):
		num = float(defecto)
	return clampi(int(roundf(num)), 1, 10)


static func sanitizar_arquetipo(valor: Variant) -> String:
	if not (valor is String):
		return ARQUETIPO_PERSONALIZADO
	var limpio := (valor as String).strip_edges()
	var lower := limpio.to_lower()
	if lower == "tecnico" or lower == "técnico":
		return "Técnico"
	for nombre: String in ORDEN_ARQUETIPOS:
		if lower == nombre.to_lower():
			return nombre
	return ARQUETIPO_PERSONALIZADO


static func sanitizar_es_humano(valor: Variant) -> bool:
	if valor is bool:
		return valor
	if valor is int:
		return valor != 0
	return false


func sanitizar_config_vehiculos() -> void:
	var defaults := _crear_config_vehiculos_defecto()
	if config_vehiculos.is_empty():
		config_vehiculos = defaults
		return

	while config_vehiculos.size() < defaults.size():
		var idx := config_vehiculos.size()
		config_vehiculos.append((defaults[idx] as Dictionary).duplicate(true))
	if config_vehiculos.size() > defaults.size():
		config_vehiculos.resize(defaults.size())

	var humano_encontrado := false
	for i in range(config_vehiculos.size()):
		var cfg: Dictionary = config_vehiculos[i]
		var raw_nombre: Variant = cfg.get("nombre", "")
		if raw_nombre == null or not (raw_nombre is String) or str(raw_nombre).strip_edges().is_empty():
			cfg["nombre"] = "Vehículo %d" % (i + 1)

		var raw_color: Variant = cfg.get("color", Color.WHITE)
		if not (raw_color is Color):
			cfg["color"] = Color.WHITE

		for clave: String in CLAVES_ATRIBUTOS_VEHICULO:
			cfg[clave] = sanitizar_normalizado(cfg.get(clave, 0.5), 0.5)

		cfg["nivel_ia"] = sanitizar_nivel_ia(cfg.get("nivel_ia", 5), 5)
		cfg["arquetipo"] = sanitizar_arquetipo(cfg.get("arquetipo", ARQUETIPO_PERSONALIZADO))

		var es_hum := sanitizar_es_humano(cfg.get("es_humano", false))
		if es_hum:
			if humano_encontrado:
				es_hum = false
			else:
				humano_encontrado = true
		cfg["es_humano"] = es_hum


func establecer_humano_exclusivo(indice: int, activar: bool) -> void:
	sanitizar_config_vehiculos()
	if indice >= 0 and indice < config_vehiculos.size():
		if activar:
			for i in range(config_vehiculos.size()):
				config_vehiculos[i]["es_humano"] = (i == indice)
		else:
			config_vehiculos[indice]["es_humano"] = false
	sanitizar_config_vehiculos()


func obtener_indice_humano() -> int:
	for i in range(config_vehiculos.size()):
		if sanitizar_es_humano(config_vehiculos[i].get("es_humano", false)):
			return i
	return -1


func restaurar_config_vehiculos_defecto() -> void:
	config_vehiculos = _crear_config_vehiculos_defecto()


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
