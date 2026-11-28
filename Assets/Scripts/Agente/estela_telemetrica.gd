class_name EstelaTelemetrica
extends Node2D

## Estela telemétrica en espacio del mundo (top_level = true, z_index = 1)
## coloreada según la acción longitudinal aplicada en cada tick físico.

const COLOR_ACELERACION := Color(0.24, 0.90, 0.45, 0.92) # Verde: acelerando
const COLOR_FRENADO := Color(0.98, 0.68, 0.14, 0.92) # Amarillo/Naranja: frenando o sin acelerar
const COLOR_REVERSA := Color(0.10, 0.82, 0.98, 0.92) # Azul/Cian: reversa

const UMBRAL_ACEL: float = 0.05
const UMBRAL_VEL_REVERSA: float = 5.0
const MIN_LONGITUD: int = 10
const MAX_LONGITUD: int = 600
const GROSOR_ESTELA: float = 2.2
const DISTANCIA_MIN_PUNTO: float = 0.20

@export var mostrar_estela: bool = true:
	set(value):
		mostrar_estela = value
		visible = value
		if visible:
			queue_redraw()

@export_range(10, 600, 1) var longitud_maxima_estela: int = 120:
	set(value):
		longitud_maxima_estela = clampi(value, MIN_LONGITUD, MAX_LONGITUD)
		_recortar_a_limite()
		if visible:
			queue_redraw()

var _puntos: PackedVector2Array = PackedVector2Array()
var _colores: PackedColorArray = PackedColorArray()
var _pos_referencia: Vector2 = Vector2(INF, INF)


func _ready() -> void:
	top_level = true
	z_index = 1
	z_as_relative = false
	global_position = Vector2.ZERO
	global_rotation = 0.0
	global_scale = Vector2.ONE
	visible = mostrar_estela


static func calcular_color_accion(acel_cmd: float, velocidad_actual: float) -> Color:
	var acel := acel_cmd if is_finite(acel_cmd) else 0.0
	var vel := velocidad_actual if is_finite(velocidad_actual) else 0.0
	if acel > UMBRAL_ACEL:
		return COLOR_ACELERACION
	if acel < -UMBRAL_ACEL and vel <= UMBRAL_VEL_REVERSA:
		return COLOR_REVERSA
	return COLOR_FRENADO


func registrar_punto(pos_global: Vector2, acel_cmd: float, velocidad_actual: float) -> void:
	if not pos_global.is_finite():
		return
	if _puntos.is_empty():
		if _pos_referencia.is_finite() and pos_global.distance_to(_pos_referencia) < DISTANCIA_MIN_PUNTO:
			return
	elif pos_global.distance_to(_puntos[_puntos.size() - 1]) < DISTANCIA_MIN_PUNTO:
		return
	var col := calcular_color_accion(acel_cmd, velocidad_actual)
	_puntos.append(pos_global)
	_colores.append(col)
	_pos_referencia = pos_global
	_recortar_a_limite()
	if visible:
		queue_redraw()


func limpiar(pos_inicial: Vector2 = Vector2(INF, INF)) -> void:
	_puntos.clear()
	_colores.clear()
	_pos_referencia = pos_inicial if pos_inicial.is_finite() else Vector2(INF, INF)
	queue_redraw()


func obtener_puntos() -> PackedVector2Array:
	return _puntos.duplicate()


func obtener_colores() -> PackedColorArray:
	return _colores.duplicate()


func _recortar_a_limite() -> void:
	var limite := clampi(longitud_maxima_estela, MIN_LONGITUD, MAX_LONGITUD)
	while _puntos.size() > limite:
		_puntos.remove_at(0)
	while _colores.size() > limite:
		_colores.remove_at(0)


func _draw() -> void:
	if not visible or _puntos.is_empty():
		return
	if _puntos.size() == 1:
		var col0 := _colores[0] if not _colores.is_empty() else COLOR_FRENADO
		draw_circle(_puntos[0], GROSOR_ESTELA * 0.55, col0)
		return

	var total_seg := maxi(1, _puntos.size() - 1)
	for i in range(1, _puntos.size()):
		var col_seg := _colores[i] if i < _colores.size() else COLOR_FRENADO
		col_seg.a *= lerpf(0.20, 0.92, float(i) / float(total_seg))
		draw_line(_puntos[i - 1], _puntos[i], col_seg, GROSOR_ESTELA, true)
