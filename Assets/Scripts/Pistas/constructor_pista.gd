class_name ConstructorPista
extends RefCounted

## Construye la pista suavizada trazando los contornos reales (exterior e interior)
## de las celdas de asfalto y aplicando suavizado de Chaikin, evitando pliegues
## o auto-intersecciones sin importar el grosor o forma del circuito.

const RUTA_TILESET := "res://Assets/Sprites/tileset_pista.tres"
const PASOS_RELAJACION: int = 1
const ITERACIONES_CHAIKIN: int = 3
const VECINOS_4: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


static func construir_pista_suave(
	contenedor: Node2D,
	celdas_asfalto: Dictionary,
	generar_colisiones: bool = false,
	color_hueco: Color = Color(0.0823529, 0.101961, 0.141176, 1.0)
) -> void:
	if contenedor == null:
		return

	for hijo in contenedor.get_children():
		hijo.queue_free()

	if celdas_asfalto.size() < 4:
		return

	var tam := float(DatosSimulacion.TAMANIO_CELDA)
	var regiones := _obtener_exterior_e_interior(celdas_asfalto)
	var masa_total: Dictionary = regiones["masa_total"]
	var huecos: Array[Dictionary] = regiones["huecos"]

	var contornos_ext := _trazar_contornos_conjunto(masa_total, tam)
	if contornos_ext.is_empty():
		return

	var cuerpo_colision: StaticBody2D = null
	if generar_colisiones:
		cuerpo_colision = StaticBody2D.new()
		cuerpo_colision.name = "MurosPasto"
		cuerpo_colision.collision_layer = 1 # Layer 1: Muros_Pasto
		cuerpo_colision.collision_mask = 0
		contenedor.add_child(cuerpo_colision)

	# 1. Polígono exterior de asfalto + borde amarillo
	for i in range(contornos_ext.size()):
		var relajado_ext := _relajar_laplaciano_cerrado(contornos_ext[i], PASOS_RELAJACION)
		var suave_ext := _suavizar_chaikin_cerrado(relajado_ext, ITERACIONES_CHAIKIN)

		var poly_asfalto := Polygon2D.new()
		poly_asfalto.name = "AsfaltoExterior_%d" % i
		poly_asfalto.polygon = suave_ext
		poly_asfalto.color = Color(0.20, 0.25, 0.36, 1.0)
		contenedor.add_child(poly_asfalto)

		var linea_ext := Line2D.new()
		linea_ext.name = "BordeExterior_%d" % i
		linea_ext.points = suave_ext
		linea_ext.closed = true
		linea_ext.width = 4.0
		linea_ext.default_color = Color(0.95, 0.84, 0.22, 1.0)
		linea_ext.joint_mode = Line2D.LINE_JOINT_ROUND
		linea_ext.antialiased = true
		contenedor.add_child(linea_ext)

		if generar_colisiones and cuerpo_colision != null:
			var col := CollisionPolygon2D.new()
			col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
			col.polygon = suave_ext
			cuerpo_colision.add_child(col)

	# 2. Islas interiores (recorte visual + borde amarillo + muro interior)
	for h_idx in range(huecos.size()):
		var contornos_int := _trazar_contornos_conjunto(huecos[h_idx], tam)
		for j in range(contornos_int.size()):
			var relajado_int := _relajar_laplaciano_cerrado(contornos_int[j], PASOS_RELAJACION)
			var suave_int := _suavizar_chaikin_cerrado(relajado_int, ITERACIONES_CHAIKIN)

			var poly_hueco := Polygon2D.new()
			poly_hueco.name = "HuecoInterior_%d_%d" % [h_idx, j]
			poly_hueco.polygon = suave_int
			poly_hueco.color = color_hueco
			contenedor.add_child(poly_hueco)

			var linea_int := Line2D.new()
			linea_int.name = "BordeInterior_%d_%d" % [h_idx, j]
			linea_int.points = suave_int
			linea_int.closed = true
			linea_int.width = 4.0
			linea_int.default_color = Color(0.95, 0.84, 0.22, 1.0)
			linea_int.joint_mode = Line2D.LINE_JOINT_ROUND
			linea_int.antialiased = true
			contenedor.add_child(linea_int)

			if generar_colisiones and cuerpo_colision != null:
				var col := CollisionPolygon2D.new()
				col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
				col.polygon = suave_int
				cuerpo_colision.add_child(col)


static func _obtener_exterior_e_interior(celdas_asfalto: Dictionary) -> Dictionary:
	var min_x := 999999
	var max_x := -999999
	var min_y := 999999
	var max_y := -999999

	for c: Vector2i in celdas_asfalto.keys():
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)

	min_x -= 1
	max_x += 1
	min_y -= 1
	max_y += 1

	var inicio_ext := Vector2i(min_x, min_y)
	var exterior: Dictionary = {inicio_ext: true}
	var cola: Array[Vector2i] = [inicio_ext]
	var idx: int = 0

	while idx < cola.size():
		var actual := cola[idx]
		idx += 1
		for dir in VECINOS_4:
			var sig := actual + dir
			if sig.x < min_x or sig.x > max_x or sig.y < min_y or sig.y > max_y:
				continue
			if not celdas_asfalto.has(sig) and not exterior.has(sig):
				exterior[sig] = true
				cola.append(sig)

	var masa_total := celdas_asfalto.duplicate()
	var celdas_hueco: Dictionary = {}

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var p := Vector2i(x, y)
			if not celdas_asfalto.has(p) and not exterior.has(p):
				masa_total[p] = true
				celdas_hueco[p] = true

	var huecos := _agrupar_componentes(celdas_hueco)
	return {"masa_total": masa_total, "huecos": huecos}


static func _agrupar_componentes(celdas: Dictionary) -> Array[Dictionary]:
	var grupos: Array[Dictionary] = []
	var visitadas: Dictionary = {}

	for origen: Vector2i in celdas.keys():
		if visitadas.has(origen):
			continue
		var comp: Dictionary = {origen: true}
		visitadas[origen] = true
		var cola: Array[Vector2i] = [origen]
		var idx: int = 0
		while idx < cola.size():
			var actual := cola[idx]
			idx += 1
			for dir in VECINOS_4:
				var sig := actual + dir
				if celdas.has(sig) and not visitadas.has(sig):
					visitadas[sig] = true
					comp[sig] = true
					cola.append(sig)
		grupos.append(comp)

	return grupos


static func _trazar_contornos_conjunto(celdas: Dictionary, tam: float) -> Array[PackedVector2Array]:
	# Construye grafo dirigido de aristas frontera en sentido horario alrededor de `celdas`
	var salidas: Dictionary = {}

	for c: Vector2i in celdas.keys():
		if not celdas.has(c + Vector2i(0, -1)):
			_agregar_arista(salidas, c, c + Vector2i(1, 0))
		if not celdas.has(c + Vector2i(1, 0)):
			_agregar_arista(salidas, c + Vector2i(1, 0), c + Vector2i(1, 1))
		if not celdas.has(c + Vector2i(0, 1)):
			_agregar_arista(salidas, c + Vector2i(1, 1), c + Vector2i(0, 1))
		if not celdas.has(c + Vector2i(-1, 0)):
			_agregar_arista(salidas, c + Vector2i(0, 1), c)

	var contornos: Array[PackedVector2Array] = []
	while not salidas.is_empty():
		var inicio: Vector2i = salidas.keys()[0]
		var poligono := PackedVector2Array()
		var actual := inicio
		var dir_anterior := Vector2i.RIGHT
		var pasos := 0
		var max_pasos := 10000

		while salidas.has(actual) and pasos < max_pasos:
			pasos += 1
			var opciones: Array = salidas[actual]
			var elegido_idx := 0
			if opciones.size() > 1:
				elegido_idx = _elegir_giro_derecha(actual, dir_anterior, opciones)
			var siguiente: Vector2i = opciones[elegido_idx]
			opciones.remove_at(elegido_idx)
			if opciones.is_empty():
				salidas.erase(actual)

			poligono.append(Vector2(actual) * tam)
			dir_anterior = siguiente - actual
			actual = siguiente
			if actual == inicio:
				break

		if poligono.size() >= 3:
			contornos.append(poligono)

	return contornos


static func _agregar_arista(salidas: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not salidas.has(a):
		salidas[a] = []
	salidas[a].append(b)


static func _elegir_giro_derecha(actual: Vector2i, dir_anterior: Vector2i, opciones: Array) -> int:
	# En Godot 2D (+X derecha, +Y abajo), girar a la derecha desde dir_anterior es (-y, x)
	var derecha := Vector2i(-dir_anterior.y, dir_anterior.x)
	for i in range(opciones.size()):
		if (opciones[i] - actual) == derecha:
			return i
	return 0


static func _relajar_laplaciano_cerrado(puntos: PackedVector2Array, pasos: int) -> PackedVector2Array:
	var actual := puntos
	for _p in range(pasos):
		var n := actual.size()
		if n < 3:
			break
		var siguiente := PackedVector2Array()
		for i in range(n):
			var prev := actual[(i - 1 + n) % n]
			var curr := actual[i]
			var next := actual[(i + 1) % n]
			siguiente.append(prev * 0.25 + curr * 0.5 + next * 0.25)
		actual = siguiente
	return actual


static func _suavizar_chaikin_cerrado(puntos: PackedVector2Array, iteraciones: int) -> PackedVector2Array:
	var actual := puntos
	for _it in range(iteraciones):
		var n := actual.size()
		if n < 3:
			break
		var siguiente := PackedVector2Array()
		for i in range(n):
			var p0 := actual[i]
			var p1 := actual[(i + 1) % n]
			siguiente.append(p0.lerp(p1, 0.25))
			siguiente.append(p0.lerp(p1, 0.75))
		actual = siguiente
	return actual


static func construir_en_tilemap(tile_map: TileMapLayer, celdas_asfalto: Dictionary) -> void:
	if tile_map == null:
		return

	if tile_map.tile_set == null and ResourceLoader.exists(RUTA_TILESET):
		tile_map.tile_set = load(RUTA_TILESET)

	tile_map.clear()
	if celdas_asfalto.is_empty():
		return

	var celdas: Array[Vector2i] = []
	for c: Vector2i in celdas_asfalto.keys():
		celdas.append(c)

	tile_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if tile_map.tile_set != null and tile_map.tile_set.tile_size.x > 0:
		var factor := float(DatosSimulacion.TAMANIO_CELDA) / float(tile_map.tile_set.tile_size.x)
		tile_map.scale = Vector2(factor, factor)

	tile_map.set_cells_terrain_connect(celdas, 0, 0)
