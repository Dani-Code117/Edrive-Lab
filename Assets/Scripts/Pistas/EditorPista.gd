extends Node2D

## Lienzo interactivo del Creador de Mapas (Vista 2).
## Gestiona el TileMapLayer 32x32, la brocha 3x3, el borrador, la meta
## y la validación continua del circuito cerrado.

signal pista_actualizada(es_valida: bool, mensaje_estado: String)

enum Herramienta { PINCEL, BORRADOR, META }

const TILE_PASTO := Vector2i(0, 0)
const TILE_ASFALTO := Vector2i(1, 0)

var herramienta_actual: Herramienta = Herramienta.PINCEL
var celdas_asfalto: Dictionary = {}
var celda_meta: Vector2i = Vector2i(-1, -1)
var tiene_meta: bool = false

var ultima_validacion: Dictionary = {
	"valido": false,
	"mensaje": "Dibuja un circuito cerrado con la brocha 3x3.",
	"checkpoints": [] as Array[Vector2i],
	"rotacion_salida": 0.0,
}

var _pintando: bool = false
var _borrando_rapido: bool = false
var _celda_hover: Vector2i = Vector2i(-1, -1)
var _ultima_celda_trazo: Vector2i = Vector2i(-1, -1)
var _interaccion_habilitada: bool = true

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var overlay: Node2D = $Overlay


func _ready() -> void:
	overlay.draw.connect(_on_overlay_draw)
	_configurar_tileset()
	_cargar_o_inicializar_pista()


func _configurar_tileset() -> void:
	if tile_map.tile_set != null:
		return

	var tam := DatosSimulacion.TAMANIO_CELDA
	var img := Image.create(tam * 2, tam, false, Image.FORMAT_RGBA8)

	# Tile (0, 0): Pasto exterior con textura sutil
	for x in range(tam):
		for y in range(tam):
			var ruido := ((x * 13 + y * 29) % 7) * 0.008
			var col_pasto := Color(0.16 + ruido, 0.34 + ruido, 0.18 + ruido * 0.5, 1.0)
			img.set_pixel(x, y, col_pasto)

	# Tile (1, 0): Asfalto oscuro
	for x in range(tam, tam * 2):
		for y in range(tam):
			var ruido := ((x * 17 + y * 31) % 5) * 0.006
			var col_asfalto := Color(0.18 + ruido, 0.19 + ruido, 0.22 + ruido, 1.0)
			img.set_pixel(x, y, col_asfalto)

	var tex := ImageTexture.create_from_image(img)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(tam, tam)
	atlas.create_tile(TILE_PASTO)
	atlas.create_tile(TILE_ASFALTO)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tam, tam)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1) # Layer 1: Muros_Pasto
	ts.add_source(atlas, 0)

	# Colisión completa en el tile de pasto
	var half := tam * 0.5
	var poly := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	var tile_data_pasto := atlas.get_tile_data(TILE_PASTO, 0)
	tile_data_pasto.add_collision_polygon(0)
	tile_data_pasto.set_collision_polygon_points(0, 0, poly)

	tile_map.tile_set = ts


func _cargar_o_inicializar_pista() -> void:
	_rellenar_pasto()
	if not DatosSimulacion.celdas_asfalto.is_empty():
		celdas_asfalto = DatosSimulacion.celdas_asfalto.duplicate()
		for c: Vector2i in celdas_asfalto.keys():
			tile_map.set_cell(c, 0, TILE_ASFALTO)
		if DatosSimulacion.tiene_meta and celdas_asfalto.has(DatosSimulacion.celda_meta):
			celda_meta = DatosSimulacion.celda_meta
			tiene_meta = true
	_revalidar_pista()


func _rellenar_pasto() -> void:
	tile_map.clear()
	for x in range(DatosSimulacion.ANCHO_GRID):
		for y in range(DatosSimulacion.ALTO_GRID):
			tile_map.set_cell(Vector2i(x, y), 0, TILE_PASTO)


func establecer_herramienta(h: Herramienta) -> void:
	herramienta_actual = h
	overlay.queue_redraw()


func limpiar_todo() -> void:
	celdas_asfalto.clear()
	celda_meta = Vector2i(-1, -1)
	tiene_meta = false
	DatosSimulacion.limpiar_pista()
	_rellenar_pasto()
	_revalidar_pista()
	overlay.queue_redraw()


func obtener_validacion() -> Dictionary:
	return ultima_validacion


func procesar_input_lienzo(event: InputEvent) -> void:
	if not _interaccion_habilitada:
		return

	if event is InputEventMouseMotion:
		var nueva_celda := _pos_local_a_celda(event.position)
		if nueva_celda != _celda_hover:
			_celda_hover = nueva_celda
			overlay.queue_redraw()
		if _pintando:
			_aplicar_trazo_interpolado(_ultima_celda_trazo, _celda_hover, false)
			_ultima_celda_trazo = _celda_hover
		elif _borrando_rapido:
			_aplicar_trazo_interpolado(_ultima_celda_trazo, _celda_hover, true)
			_ultima_celda_trazo = _celda_hover

	elif event is InputEventMouseButton:
		var celda := _pos_local_a_celda(event.position)
		_celda_hover = celda

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not _celda_en_tablero(celda):
					return
				if herramienta_actual == Herramienta.META:
					_colocar_meta(celda)
				else:
					_pintando = true
					_ultima_celda_trazo = celda
					_aplicar_herramienta_en_celda(celda, false)
					_revalidar_pista()
			else:
				if _pintando:
					_pintando = false
					_revalidar_pista()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if not _celda_en_tablero(celda):
					return
				_borrando_rapido = true
				_ultima_celda_trazo = celda
				_aplicar_herramienta_en_celda(celda, true)
				_revalidar_pista()
			else:
				if _borrando_rapido:
					_borrando_rapido = false
					_revalidar_pista()


func _pos_local_a_celda(pos_local: Vector2) -> Vector2i:
	return tile_map.local_to_map(pos_local)


func _celda_en_tablero(c: Vector2i) -> bool:
	return (
		c.x >= 0
		and c.x < DatosSimulacion.ANCHO_GRID
		and c.y >= 0
		and c.y < DatosSimulacion.ALTO_GRID
	)


func _aplicar_trazo_interpolado(desde: Vector2i, hasta: Vector2i, forzar_borrador: bool) -> void:
	if desde == Vector2i(-1, -1):
		_aplicar_herramienta_en_celda(hasta, forzar_borrador)
		return

	var pasos := maxi(absi(hasta.x - desde.x), absi(hasta.y - desde.y))
	if pasos == 0:
		_aplicar_herramienta_en_celda(hasta, forzar_borrador)
		return

	var hubo_cambio := false
	for i in range(1, pasos + 1):
		var t := float(i) / float(pasos)
		var interp := Vector2i(
			roundi(lerpf(desde.x, hasta.x, t)),
			roundi(lerpf(desde.y, hasta.y, t))
		)
		if _aplicar_herramienta_en_celda(interp, forzar_borrador):
			hubo_cambio = true

	if hubo_cambio:
		_revalidar_pista()


func _aplicar_herramienta_en_celda(centro: Vector2i, forzar_borrador: bool) -> bool:
	if not _celda_en_tablero(centro):
		return false

	var es_borrador := forzar_borrador or herramienta_actual == Herramienta.BORRADOR
	var cambio := false

	# Brocha 3x3 dejando margen mínimo de 1 celda de pasto en los bordes del lienzo
	var cx := clampi(centro.x, 2, DatosSimulacion.ANCHO_GRID - 3)
	var cy := clampi(centro.y, 2, DatosSimulacion.ALTO_GRID - 3)
	var centro_ajustado := Vector2i(cx, cy)

	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := centro_ajustado + Vector2i(dx, dy)
			if es_borrador:
				if celdas_asfalto.has(c):
					celdas_asfalto.erase(c)
					tile_map.set_cell(c, 0, TILE_PASTO)
					cambio = true
					if tiene_meta and c == celda_meta:
						tiene_meta = false
						celda_meta = Vector2i(-1, -1)
			else:
				if not celdas_asfalto.has(c):
					celdas_asfalto[c] = true
					tile_map.set_cell(c, 0, TILE_ASFALTO)
					cambio = true

	if cambio:
		overlay.queue_redraw()
	return cambio


func _colocar_meta(celda: Vector2i) -> void:
	if not celdas_asfalto.has(celda):
		ultima_validacion = {
			"valido": false,
			"mensaje": "La meta debe colocarse sobre una celda de asfalto.",
			"checkpoints": [] as Array[Vector2i],
			"rotacion_salida": 0.0,
		}
		pista_actualizada.emit(false, ultima_validacion["mensaje"])
		return

	celda_meta = celda
	tiene_meta = true
	_revalidar_pista()
	overlay.queue_redraw()


func _revalidar_pista() -> void:
	ultima_validacion = GeneradorCheckpoints.validar_y_generar(
		celdas_asfalto,
		celda_meta,
		tiene_meta,
		DatosSimulacion.TAMANIO_CELDA
	)
	pista_actualizada.emit(ultima_validacion["valido"], ultima_validacion["mensaje"])
	overlay.queue_redraw()


func _on_overlay_draw() -> void:
	var tam := float(DatosSimulacion.TAMANIO_CELDA)
	var ancho_px := DatosSimulacion.ANCHO_GRID * tam
	var alto_px := DatosSimulacion.ALTO_GRID * tam

	# 1. Cuadrícula sutil
	var col_grid := Color(1.0, 1.0, 1.0, 0.05)
	for x in range(DatosSimulacion.ANCHO_GRID + 1):
		overlay.draw_line(Vector2(x * tam, 0), Vector2(x * tam, alto_px), col_grid, 1.0)
	for y in range(DatosSimulacion.ALTO_GRID + 1):
		overlay.draw_line(Vector2(0, y * tam), Vector2(ancho_px, y * tam), col_grid, 1.0)

	# 2. Bordes de pista (pianitos blancos donde el asfalto toca pasto)
	var col_borde := Color(0.88, 0.88, 0.92, 0.65)
	for c: Vector2i in celdas_asfalto.keys():
		var p := Vector2(c) * tam
		if not celdas_asfalto.has(c + Vector2i(0, -1)):
			overlay.draw_line(p, p + Vector2(tam, 0), col_borde, 2.0)
		if not celdas_asfalto.has(c + Vector2i(0, 1)):
			overlay.draw_line(p + Vector2(0, tam), p + Vector2(tam, tam), col_borde, 2.0)
		if not celdas_asfalto.has(c + Vector2i(-1, 0)):
			overlay.draw_line(p, p + Vector2(0, tam), col_borde, 2.0)
		if not celdas_asfalto.has(c + Vector2i(1, 0)):
			overlay.draw_line(p + Vector2(tam, 0), p + Vector2(tam, tam), col_borde, 2.0)

	# 3. Previsualización de checkpoints generados si la pista es válida
	if ultima_validacion.get("valido", false):
		var cps: Array = ultima_validacion.get("checkpoints", [])
		for i in range(cps.size()):
			var centro_cp := Vector2(cps[i]) * tam + Vector2.ONE * (tam * 0.5)
			overlay.draw_circle(centro_cp, 4.0, Color(0.2, 0.85, 1.0, 0.75))

	# 4. Marcador de meta
	if tiene_meta:
		var pm := Vector2(celda_meta) * tam
		var cuadros := 4
		var sub := tam / float(cuadros)
		for ix in range(cuadros):
			for iy in range(cuadros):
				var es_blanco := (ix + iy) % 2 == 0
				var col_cuadro := Color(0.95, 0.95, 0.95, 0.9) if es_blanco else Color(0.1, 0.1, 0.1, 0.9)
				overlay.draw_rect(Rect2(pm + Vector2(ix * sub, iy * sub), Vector2(sub, sub)), col_cuadro)

		if ultima_validacion.get("valido", false):
			var rot: float = ultima_validacion.get("rotacion_salida", 0.0)
			var centro_m := pm + Vector2.ONE * (tam * 0.5)
			var dir := Vector2.RIGHT.rotated(rot)
			overlay.draw_line(centro_m, centro_m + dir * 24.0, Color(1.0, 0.85, 0.15, 0.95), 3.0)

	# 5. Previsualización de la brocha bajo el cursor
	if _celda_en_tablero(_celda_hover):
		if herramienta_actual == Herramienta.META:
			var rect_meta := Rect2(Vector2(_celda_hover) * tam, Vector2(tam, tam))
			overlay.draw_rect(rect_meta, Color(1.0, 0.85, 0.15, 0.35), true)
			overlay.draw_rect(rect_meta, Color(1.0, 0.85, 0.15, 0.95), false, 2.0)
		else:
			var cx := clampi(_celda_hover.x, 2, DatosSimulacion.ANCHO_GRID - 3)
			var cy := clampi(_celda_hover.y, 2, DatosSimulacion.ALTO_GRID - 3)
			var top_left := Vector2(cx - 1, cy - 1) * tam
			var rect_brocha := Rect2(top_left, Vector2(tam * 3, tam * 3))
			var col_preview := Color(0.95, 0.3, 0.3, 0.25) if herramienta_actual == Herramienta.BORRADOR else Color(0.3, 0.9, 0.45, 0.25)
			var col_linea := Color(0.95, 0.3, 0.3, 0.9) if herramienta_actual == Herramienta.BORRADOR else Color(0.3, 0.9, 0.45, 0.9)
			overlay.draw_rect(rect_brocha, col_preview, true)
			overlay.draw_rect(rect_brocha, col_linea, false, 2.0)
