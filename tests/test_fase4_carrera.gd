extends SceneTree

## Pruebas automatizadas Fase 4: VisorRedNeuronal (7->6->2), VistaCarreraUI
## (reconstruccion de pista y muros Layer 1, TileMapLayer, checkpoints dinamicos,
## 3 vehiculos hacia CP0, aislamiento sin DatosSimulacion, telemetria, rayos,
## velocidades 1x/2x/4x, reinicio, navegacion, auditoria multi-resolucion y flujo E2E).

const RUTA_MENU := "res://Assets/Escenas/Vistas/menu_principal.tscn"
const RUTA_CREADOR := "res://Assets/Escenas/Vistas/creador_mapa.tscn"
const RUTA_CONFIG := "res://Assets/Escenas/Vistas/configuracion_carrera.tscn"
const RUTA_CARRERA := "res://Assets/Escenas/Vistas/vista_carrera.tscn"
const RUTA_VISOR := "res://Assets/Escenas/Componentes/visor_red_neuronal.tscn"
const RUTA_VEHICULO := "res://Assets/Escenas/Componentes/vehiculo_agente.tscn"
const RUTA_PRESETS_IA := "res://Assets/Presets_ia"

const RESOLUCIONES := [
	Vector2i(1920, 1080),
	Vector2i(1440, 900),
	Vector2i(1280, 960),
	Vector2i(1280, 720),
]

var _total_checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_all")


func _assert_true(cond: bool, msg: String) -> void:
	_total_checks += 1
	if cond:
		print("[PASS] %s" % msg)
	else:
		_failures += 1
		printerr("[FAIL] %s" % msg)


func _esperar_frames(n: int = 3) -> void:
	for _i in range(n):
		await process_frame


func _esperar_fisica(n: int = 4) -> void:
	for _i in range(n):
		await physics_frame


func _crear_circuito(grosor: int) -> Dictionary:
	var celdas: Dictionary = {}
	var off_min := -floori((grosor - 1) / 2.0)
	var off_max := off_min + grosor - 1
	for x in range(8, 37):
		for dy in range(off_min, off_max + 1):
			celdas[Vector2i(x, 6 + dy)] = true
			celdas[Vector2i(x, 20 + dy)] = true
	for y in range(6, 21):
		for dx in range(off_min, off_max + 1):
			celdas[Vector2i(8 + dx, y)] = true
			celdas[Vector2i(36 + dx, y)] = true
	var meta := Vector2i(22, 6)
	var val := GeneradorCheckpoints.validar_y_generar(celdas, meta, true, DatosSimulacion.TAMANIO_CELDA)
	var ancho := maxf(float(grosor * DatosSimulacion.TAMANIO_CELDA), 32.0)
	return {"celdas": celdas, "meta": meta, "validacion": val, "ancho": ancho}


func _cargar_pista_en_ds(ds: Node, circuito: Dictionary) -> void:
	var val: Dictionary = circuito["validacion"]
	ds.guardar_pista(
		circuito["celdas"],
		circuito["meta"],
		val["checkpoints"],
		val["rotacion_salida"],
		val["eje_central"],
		val["radios_eje"],
		circuito["ancho"]
	)


func _run_all() -> void:
	await process_frame
	var ds := root.get_node_or_null("DatosSimulacion")
	_assert_true(ds != null, "Autoload DatosSimulacion disponible")
	if ds == null:
		quit(1)
		return

	var cfg_orig: Array[Dictionary] = ds.config_vehiculos.duplicate(true)

	await _test_a_visor_red_neuronal()
	await _test_b_aislamiento_datos_vacios(ds)
	await _test_c_reconstruccion_y_radios_dinamicos(ds)
	await _test_d_simulacion_telemetria_y_controles(ds)
	await _test_e_layout_multiresolucion(ds)
	await _test_f_flujo_completo_e2e_y_presets(ds)
	await _test_g_invarianza_colisiones_y_seguridad(ds)

	# Restaurar estado limpio
	Engine.time_scale = 1.0
	ds.limpiar_pista()
	ds.config_vehiculos = cfg_orig

	print("=== Resumen Fase 4: %d verificaciones, %d fallos ===" % [_total_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_a_visor_red_neuronal() -> void:
	print("--- Test (a): VisorRedNeuronal (null, pre-tick, NaN/INF, indexacion 7-6-2) ---")
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 260)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var ps_visor := load(RUTA_VISOR) as PackedScene
	_assert_true(ps_visor != null, "visor_red_neuronal.tscn carga correctamente")
	var visor := ps_visor.instantiate() as Control
	vp.add_child(visor)
	await _esperar_frames(3)

	_assert_true(
		visor.clip_contents and visor.custom_minimum_size.x >= 300.0 and visor.custom_minimum_size.y >= 220.0,
		"VisorRedNeuronal tiene clip_contents=true y custom_minimum_size >= (300, 220)"
	)

	var snap_null: Dictionary = visor.call("obtener_instantanea_segura")
	_assert_true(
		snap_null["tiene_vehiculo"] == false and snap_null["entradas"].size() == 7
		and snap_null["ocultas"].size() == 6 and snap_null["salidas"].size() == 2,
		"VisorRedNeuronal maneja vehiculo_objetivo == null sin errores"
	)

	var coche := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	vp.add_child(coche)
	coche.set_physics_process(false)
	coche.configurar({"nombre": "TestNet", "color": Color(0.9, 0.2, 0.2), "nivel_ia": 5})
	var red := RedNeuronal.cargar_nivel_o_fallback(5)
	coche.cerebro = red
	visor.call("establecer_vehiculo", coche)
	await _esperar_frames(2)

	# Pre-tick safety (ultimas_entradas aun en 0, lecturas_sensores en 1)
	var snap_pre: Dictionary = visor.call("obtener_instantanea_segura")
	_assert_true(
		snap_pre["tiene_vehiculo"] and snap_pre["tiene_red"]
		and snap_pre["pesos_oculta"].size() == 42 and snap_pre["pesos_salida"].size() == 12,
		"VisorRedNeuronal enlaza vehiculo pre-tick con buffers 7-6-2 completos"
	)

	# Verificar indexacion exacta j*7+i y k*6+j + sanitizacion de NaN/INF
	red.pesos_oculta[3 * 7 + 5] = 2.75
	red.pesos_salida[1 * 6 + 4] = -1.85
	red.evaluar(PackedFloat64Array([0.1, 0.2, 0.3, 0.8, 0.5, 0.6, 0.9]))
	red.ultimas_entradas[2] = NAN
	red.ultimas_ocultas[1] = INF
	red.ultimas_salidas[0] = -INF
	visor.call("actualizar_visor")
	await _esperar_frames(2)

	var snap_nan: Dictionary = visor.call("obtener_instantanea_segura")
	var todo_finito := true
	for v in snap_nan["entradas"]:
		if not is_finite(v):
			todo_finito = false
	for v in snap_nan["ocultas"]:
		if not is_finite(v):
			todo_finito = false
	for v in snap_nan["salidas"]:
		if not is_finite(v):
			todo_finito = false

	_assert_true(
		todo_finito
		and is_equal_approx(snap_nan["pesos_oculta"][3 * 7 + 5], 2.75)
		and is_equal_approx(snap_nan["pesos_salida"][1 * 6 + 4], -1.85)
		and is_equal_approx(snap_nan["entradas"][3], 0.8),
		"VisorRedNeuronal sanitiza NaN/INF y conserva indexacion exacta j*7+i y k*6+j"
	)

	vp.queue_free()
	await _esperar_frames(2)


func _test_b_aislamiento_datos_vacios(ds: Node) -> void:
	print("--- Test (b): VistaCarreraUI aislada con DatosSimulacion vacio ---")
	ds.limpiar_pista()
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var vista := (load(RUTA_CARRERA) as PackedScene).instantiate() as Control
	vp.add_child(vista)
	await _esperar_frames(4)

	var pista_vis: Node2D = vista.get("pista_visual")
	var muros := pista_vis.get_node_or_null("MurosPasto") as StaticBody2D
	var cps_fb: Array = vista.call("obtener_checkpoints")
	var vehs_fb: Array = vista.call("obtener_vehiculos")
	_assert_true(
		bool(vista.call("usando_circuito_fallback"))
		and muros != null and muros.collision_layer == 1
		and cps_fb.size() >= 3
		and vehs_fb.size() == 3
		and ds.celdas_asfalto.is_empty() and not ds.tiene_meta,
		"VistaCarreraUI aislada construye circuito fallback local sin corromper DatosSimulacion"
	)

	vp.queue_free()
	await _esperar_frames(2)


func _test_c_reconstruccion_y_radios_dinamicos(ds: Node) -> void:
	print("--- Test (c): Reconstruccion Track/TileMap/Muros y radios de checkpoints (32px, 48px, 80px) ---")
	var esperados := {2: 18.0, 3: 26.0, 5: 42.0}
	for grosor in [2, 3, 5]:
		var circuito := _crear_circuito(grosor)
		_cargar_pista_en_ds(ds, circuito)

		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)

		var vista := (load(RUTA_CARRERA) as PackedScene).instantiate() as Control
		vp.add_child(vista)
		# Pausar fisica de los coches recien spawneados para verificar orientacion inicial hacia CP0
		var coches_init: Array = vista.call("obtener_vehiculos")
		for c_var in coches_init:
			(c_var as Node).set_physics_process(false)
		await _esperar_frames(3)

		var pista_vis: Node2D = vista.get("pista_visual")
		var muros := pista_vis.get_node_or_null("MurosPasto") as StaticBody2D
		var cps: Array = vista.call("obtener_checkpoints")
		var coches: Array = vista.call("obtener_vehiculos")
		var tam := float(DatosSimulacion.TAMANIO_CELDA)
		var pos_salida: Vector2 = ds.posicion_salida
		var pos_cp0 := Vector2(ds.ruta_checkpoints[0]) * tam + Vector2.ONE * (tam * 0.5)
		var dir_cp0: Vector2 = (pos_cp0 - pos_salida).normalized()

		var radios_ok: bool = cps.size() >= 3
		var shapes_unicas := true
		var primer_shape: Shape2D = null
		for i in range(cps.size()):
			var cp: CheckpointArea = cps[i]
			var col := cp.get_node_or_null("CollisionShape2D") as CollisionShape2D
			var shape := col.shape as CircleShape2D if col != null else null
			if shape == null or cp.visible or cp.collision_layer != 4 or cp.collision_mask != 2 or cp.id_checkpoint != i:
				radios_ok = false
			if shape != null:
				if i == 0:
					primer_shape = shape
				elif shape == primer_shape:
					shapes_unicas = false
				if not is_equal_approx(shape.radius, esperados[grosor]):
					radios_ok = false

		var coches_ok: bool = coches.size() == 3
		for c_var in coches:
			var c: VehiculoAgente = c_var
			var forward := Vector2.RIGHT.rotated(c.rotation)
			if forward.dot(dir_cp0) < 0.99 or not (c.cerebro is RedNeuronal):
				coches_ok = false

		var bandera: Sprite2D = vista.get("bandera_meta")
		var tm_pista: TileMapLayer = vista.get("tile_map_pista")
		var celdas_circuito: Dictionary = circuito["celdas"]
		var usadas := tm_pista.get_used_cells() if tm_pista != null else []
		var todas_en_tm := true
		for c_key: Vector2i in celdas_circuito.keys():
			if tm_pista.get_cell_source_id(c_key) == -1:
				todas_en_tm = false
				break
		var tm_ok: bool = tm_pista != null and not tm_pista.visible and usadas.size() >= celdas_circuito.size() and todas_en_tm

		_assert_true(
			not bool(vista.call("usando_circuito_fallback"))
			and muros != null and muros.collision_layer == 1
			and tm_ok and radios_ok and shapes_unicas and coches_ok
			and bandera != null and bandera.texture != null and bandera.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			and bandera.position.distance_to(ds.posicion_salida) < 1.0,
			"Grosor %dx%d (%.0fpx): MurosPasto L1, TileMap oculto (%d celdas), checkpoints (r=%.1f, shapes unicas), bandera y 3 coches hacia CP0" % [
				grosor, grosor, circuito["ancho"], usadas.size(), esperados[grosor]
			]
		)

		# Verificar todos los Button usan BotonAnimado
		var botones_ok := true
		for n in _obtener_todos_nodos(vista):
			if n is Button and not (n is OptionButton) and not (n is BotonAnimado):
				botones_ok = false
		_assert_true(botones_ok, "Todos los Button en VistaCarreraUI (%dx%d) usan BotonAnimado" % [grosor, grosor])

		vp.queue_free()
		await _esperar_frames(2)


func _test_d_simulacion_telemetria_y_controles(ds: Node) -> void:
	print("--- Test (d): Simulacion en vivo, telemetria, rayos, 1x/2x/4x, reinicio y navegacion ---")
	var circuito := _crear_circuito(3)
	_cargar_pista_en_ds(ds, circuito)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var vista := (load(RUTA_CARRERA) as PackedScene).instantiate() as Control
	vp.add_child(vista)
	await _esperar_frames(3)
	await _esperar_fisica(12)
	await _esperar_frames(2)

	var coches: Array = vista.call("obtener_vehiculos")
	var se_movieron := false
	for c_var in coches:
		var c: VehiculoAgente = c_var
		if c.global_position.distance_to(ds.posicion_salida) > 1.0:
			se_movieron = true

	var red0: RedNeuronal = (coches[0] as VehiculoAgente).cerebro as RedNeuronal
	_assert_true(
		se_movieron and red0 != null and red0.ultimas_salidas[0] > 0.0,
		"Vehiculos avanzan en simulacion en vivo y actualizan instantaneas de RedNeuronal"
	)

	# Cambio de inspeccion (0 -> 1 -> 2)
	var cont_tarjetas: VBoxContainer = vista.get("contenedor_tarjetas")
	var visor_red: Control = vista.get("visor_red")
	var btn_insp1: Button = cont_tarjetas.get_child(1).get_node("VBox/Margin/Col/MidRow/BtnInspeccionar")
	var btn_insp2: Button = cont_tarjetas.get_child(2).get_node("VBox/Margin/Col/MidRow/BtnInspeccionar")
	btn_insp1.pressed.emit()
	await _esperar_frames(2)
	var ok_insp1: bool = visor_red.get("vehiculo_objetivo") == coches[1] and int(vista.call("obtener_indice_inspeccionado")) == 1
	btn_insp2.pressed.emit()
	await _esperar_frames(2)
	var ok_insp2: bool = visor_red.get("vehiculo_objetivo") == coches[2] and int(vista.call("obtener_indice_inspeccionado")) == 2
	_assert_true(ok_insp1 and ok_insp2, "Botones Inspeccionar cambian el vehiculo objetivo del VisorRedNeuronal")

	# Toggle de rayos
	var btn_rayos: Button = vista.get("btn_rayos")
	btn_rayos.button_pressed = false
	await _esperar_frames(1)
	var rayos_off: bool = (not coches[0].mostrar_sensores) and (not coches[1].mostrar_sensores) and (not coches[2].mostrar_sensores)
	btn_rayos.button_pressed = true
	await _esperar_frames(1)
	var rayos_on: bool = coches[0].mostrar_sensores and coches[1].mostrar_sensores and coches[2].mostrar_sensores
	_assert_true(rayos_off and rayos_on, "BtnRayos alterna mostrar_sensores en los 3 coches")

	# Velocidades 1x / 2x / 4x y reset en _exit_tree
	var btn_vel_1x: Button = vista.get("btn_vel_1x")
	var btn_vel_2x: Button = vista.get("btn_vel_2x")
	var btn_vel_4x: Button = vista.get("btn_vel_4x")
	btn_vel_2x.pressed.emit()
	var ok_2x := is_equal_approx(Engine.time_scale, 2.0)
	btn_vel_4x.pressed.emit()
	var ok_4x := is_equal_approx(Engine.time_scale, 4.0)
	btn_vel_1x.pressed.emit()
	var ok_1x := is_equal_approx(Engine.time_scale, 1.0)
	btn_vel_4x.pressed.emit()
	_assert_true(ok_2x and ok_4x and ok_1x, "Selector de velocidad actualiza Engine.time_scale (1x/2x/4x)")

	# Telemetria al chocar y al reiniciar
	coches[0]._marcar_chocado("Chocado")
	await _esperar_frames(2)
	var lbl_est0: Label = cont_tarjetas.get_child(0).get_node("VBox/Margin/Col/TopRow/LblEstado")
	var muestra_chocado := lbl_est0.text == "Chocado"

	var btn_reiniciar: Button = vista.get("btn_reiniciar")
	btn_reiniciar.pressed.emit()
	await _esperar_frames(2)
	var reiniciado_ok: bool = (
		not coches[0].esta_chocado
		and coches[0].vuelta_actual == 1
		and coches[0].checkpoints_cruzados == 0
		and lbl_est0.text == "Corriendo"
	)
	_assert_true(muestra_chocado and reiniciado_ok, "Telemetria refleja Chocado y Reiniciar Carrera restaura estado a Corriendo")

	# Destinos de navegacion y reset de Engine.time_scale en _exit_tree()
	_assert_true(
		ResourceLoader.exists(vista.get("ESCENA_CONFIGURACION")) and ResourceLoader.exists(vista.get("ESCENA_CREADOR")),
		"Escenas destino Volver a Configuracion y Editar Mapa existen"
	)

	vp.queue_free()
	await _esperar_frames(3)
	_assert_true(is_equal_approx(Engine.time_scale, 1.0), "_exit_tree() restablece Engine.time_scale = 1.0")


func _test_e_layout_multiresolucion(ds: Node) -> void:
	print("--- Test (e): Auditoria layout multi-resolucion (1920x1080, 1440x900, 1280x960, 1280x720) ---")
	var circuito := _crear_circuito(3)
	_cargar_pista_en_ds(ds, circuito)

	for res: Vector2i in RESOLUCIONES:
		var vp := SubViewport.new()
		vp.size = res
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)

		var vista := (load(RUTA_CARRERA) as PackedScene).instantiate() as Control
		vp.add_child(vista)
		# Pausar fisica de los coches recien spawneados para verificar orientacion inicial hacia CP0
		var coches_init: Array = vista.call("obtener_vehiculos")
		for c_var in coches_init:
			(c_var as Node).set_physics_process(false)
		await _esperar_frames(3)

		var problemas := _validar_geometria_vista(vista, res)
		var scroll := vista.get_node("Layout/Cuerpo/PanelHUD/MarginHUD/ScrollHUD") as ScrollContainer
		var vbar := scroll.get_v_scroll_bar()
		var sin_overflow := vbar.max_value <= scroll.size.y + 1.5
		var visor_tam: Vector2 = (vista.get("visor_red") as Control).size
		var area_tam: Vector2 = (vista.get("area_pista") as Control).size
		_assert_true(
			problemas.is_empty() and sin_overflow and visor_tam.x >= 280.0 and visor_tam.y >= 200.0 and area_tam.x > 400.0,
			"Layout %dx%d sin recortes, sin solapamientos y VisorRed visible (%s, area=%s, err=%s)" % [
				res.x, res.y, str(visor_tam), str(area_tam), str(problemas)
			]
		)

		vp.queue_free()
		await _esperar_frames(2)


func _test_f_flujo_completo_e2e_y_presets(ds: Node) -> void:
	print("--- Test (f): Flujo E2E menu -> creador -> configuracion -> carrera -> regreso + Presets_ia ---")
	var circuito := _crear_circuito(3)

	# 1. Menu -> Creador
	change_scene_to_file(RUTA_MENU)
	await _esperar_frames(4)
	_assert_true(current_scene != null and current_scene.scene_file_path == RUTA_MENU, "Vista 1 menu_principal carga en SceneTree")

	(current_scene.get("btn_iniciar") as Button).pressed.emit()
	await _esperar_frames(4)
	_assert_true(current_scene != null and current_scene.scene_file_path == RUTA_CREADOR, "Transicion Vista 1 -> Vista 2 creador_mapa exitosa")

	# 2. Creador -> Configuracion (poblando pista valida en editor_pista)
	var editor: Node = current_scene.get("editor_pista")
	var celdas_fb: Dictionary = circuito["celdas"]
	editor.set("celdas_asfalto", celdas_fb.duplicate())
	editor.set("celda_meta", circuito["meta"])
	editor.set("tiene_meta", true)
	editor.call("_revalidar_pista")
	(current_scene.get("btn_confirmar") as Button).pressed.emit() # Paso 1: confirmar y vista previa
	await _esperar_frames(2)
	(current_scene.get("btn_confirmar") as Button).pressed.emit() # Paso 2: continuar a Vista 3
	await _esperar_frames(4)
	_assert_true(current_scene != null and current_scene.scene_file_path == RUTA_CONFIG, "Transicion Vista 2 -> Vista 3 configuracion_carrera exitosa")

	# 3. Configuracion -> Vista Carrera
	(current_scene.get("btn_iniciar") as Button).pressed.emit()
	await _esperar_frames(5)
	_assert_true(current_scene != null and current_scene.scene_file_path == RUTA_CARRERA, "Transicion Vista 3 -> Vista 4 vista_carrera exitosa")

	# 4. Velocidad 4x -> Volver a Configuracion debe resetear time_scale = 1.0
	var carrera: Control = current_scene as Control
	(carrera.get("btn_vel_4x") as Button).pressed.emit()
	(carrera.get("btn_volver_config") as Button).pressed.emit()
	await _esperar_frames(4)
	_assert_true(
		current_scene != null and current_scene.scene_file_path == RUTA_CONFIG and is_equal_approx(Engine.time_scale, 1.0),
		"Volver a Configuracion cambia a Vista 3 y resetea Engine.time_scale = 1.0"
	)

	# 5. Configuracion -> Carrera -> Editar Mapa debe resetear time_scale = 1.0
	(current_scene.get("btn_iniciar") as Button).pressed.emit()
	await _esperar_frames(5)
	carrera = current_scene as Control
	(carrera.get("btn_vel_2x") as Button).pressed.emit()
	(carrera.get("btn_editar_mapa") as Button).pressed.emit()
	await _esperar_frames(4)
	_assert_true(
		current_scene != null and current_scene.scene_file_path == RUTA_CREADOR and is_equal_approx(Engine.time_scale, 1.0),
		"Editar Mapa cambia a Vista 2 y resetea Engine.time_scale = 1.0"
	)

	# Limpiar current_scene para evitar fugas antes de salir
	if current_scene != null:
		current_scene.queue_free()
		await _esperar_frames(2)

	# Verificar Assets/Presets_ia/ contiene UNICAMENTE .gitkeep
	var dir := DirAccess.open(RUTA_PRESETS_IA)
	var archivos: Array[String] = []
	if dir != null:
		dir.list_dir_begin()
		var item := dir.get_next()
		while item != "":
			if item != "." and item != "..":
				archivos.append(item)
			item = dir.get_next()
		dir.list_dir_end()
	_assert_true(archivos.size() == 1 and archivos[0] == ".gitkeep", "Assets/Presets_ia/ contiene unicamente .gitkeep (archivos: %s)" % str(archivos))


func _test_g_invarianza_colisiones_y_seguridad(ds: Node) -> void:
	print("--- Test (g): Invarianza de sensores/fisica por resolucion, reinicio, colisiones reales y coche liberado ---")
	var circuito := _crear_circuito(3)
	_cargar_pista_en_ds(ds, circuito)

	var snapshots := {}
	for res: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		var vp := SubViewport.new()
		vp.size = res
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)

		var vista := (load(RUTA_CARRERA) as PackedScene).instantiate() as Control
		vp.add_child(vista)
		var coches_init: Array = vista.call("obtener_vehiculos")
		for c_var in coches_init:
			(c_var as Node).set_physics_process(false)
		await _esperar_frames(4)

		var esc: Node2D = vista.get("escenario")
		var area_pista: Control = vista.get("area_pista")
		var sub_vp: SubViewport = vista.get("sub_viewport_pista")
		var cam: Camera2D = vista.get("camara_pista")
		_assert_true(
			esc.scale == Vector2.ONE and esc.position == Vector2.ZERO
			and sub_vp != null and sub_vp.size == Vector2i(int(round(area_pista.size.x)), int(round(area_pista.size.y)))
			and cam != null and cam.enabled and cam.zoom.x > 1.0,
			"SubViewportPista (%dx%d): Escenario sin escala (1,1)/(0,0), SubViewport=%s, Camara zoom=%s" % [
				res.x, res.y, str(sub_vp.size if sub_vp != null else Vector2i.ZERO), str(cam.zoom if cam != null else Vector2.ZERO)
			]
		)

		# Sincronizar PhysicsServer2D y medir sensores exactos en spawn antes de avanzar
		await _esperar_fisica(2)
		var c0 := coches_init[0] as VehiculoAgente
		c0.call("_actualizar_sensores")
		var sensores_spawn := c0.lecturas_sensores.duplicate()

		# Avanzar exactamente 20 ticks de fisica
		await physics_frame
		for c_var in coches_init:
			(c_var as Node).set_physics_process(true)
		await _esperar_fisica(21)
		for c_var in coches_init:
			(c_var as Node).set_physics_process(false)

		var pos_20 := c0.position
		var bandera: Sprite2D = vista.get("bandera_meta")
		var desp_20 := pos_20.distance_to(bandera.position)

		# Probar Reiniciar Carrera despues de mover y chocar los 3 coches
		for idx in range(coches_init.size()):
			var ci := coches_init[idx] as VehiculoAgente
			ci.position = Vector2(50.0 + float(idx) * 20.0, 50.0)
			ci.call("_marcar_chocado", "Chocado")
		(vista.get("btn_reiniciar") as Button).pressed.emit()
		await _esperar_frames(2)

		var reinicio_pos_ok := true
		for c_var in coches_init:
			var ci := c_var as VehiculoAgente
			if ci.position.distance_to(bandera.position) >= 1.0 or ci.esta_chocado:
				reinicio_pos_ok = false
		_assert_true(
			reinicio_pos_ok,
			"Reiniciar Carrera (%dx%d) alinea los 3 coches en bandera_meta (< 1.0 px)" % [res.x, res.y]
		)

		snapshots[res] = {
			"sensores_spawn": sensores_spawn,
			"pos_20": pos_20,
			"desp_20": desp_20,
		}

		vp.queue_free()
		await _esperar_frames(2)

	var s_1080: Dictionary = snapshots[Vector2i(1920, 1080)]
	var s_720: Dictionary = snapshots[Vector2i(1280, 720)]
	var sens_1080: PackedFloat64Array = s_1080["sensores_spawn"]
	var sens_720: PackedFloat64Array = s_720["sensores_spawn"]
	var max_diff_sens := 0.0
	for i in range(7):
		max_diff_sens = maxf(max_diff_sens, absf(sens_1080[i] - sens_720[i]))
	var diff_pos := (s_1080["pos_20"] as Vector2).distance_to(s_720["pos_20"] as Vector2)
	var diff_desp := absf(float(s_1080["desp_20"]) - float(s_720["desp_20"]))
	_assert_true(
		max_diff_sens < 0.01 and diff_pos < 0.01 and diff_desp < 0.01 and float(s_1080["desp_20"]) > 5.0,
		"Invarianza 1920x1080 vs 1280x720: max_diff_sens=%.5f, diff_pos=%.5f, desp=%.2f px" % [
			max_diff_sens, diff_pos, float(s_1080["desp_20"])
		]
	)

	# Verificar colision real con CheckpointArea, colision real con MurosPasto L1 y liberacion segura
	var vp_col := SubViewport.new()
	vp_col.size = Vector2i(1280, 720)
	vp_col.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp_col)

	var vista_col := (load(RUTA_CARRERA) as PackedScene).instantiate() as Control
	vp_col.add_child(vista_col)
	await _esperar_frames(4)

	var coches_col: Array = vista_col.call("obtener_vehiculos")
	var cps_col: Array = vista_col.call("obtener_checkpoints")
	var cont_tarjetas: VBoxContainer = vista_col.get("contenedor_tarjetas")
	var lbl_cps0: Label = cont_tarjetas.get_child(0).get_node("VBox/Margin/Col/StatsRow/LblCheckpoints")
	var lbl_est0: Label = cont_tarjetas.get_child(0).get_node("VBox/Margin/Col/TopRow/LblEstado")
	var c_test := coches_col[0] as VehiculoAgente
	(coches_col[1] as Node).set_physics_process(false)
	(coches_col[2] as Node).set_physics_process(false)

	# 1) Overlap real de CheckpointArea (CP 0)
	var cp0 := cps_col[0] as CheckpointArea
	var esc_col: Node2D = vista_col.get("escenario")
	var dir_a_cp0 := (cp0.position - c_test.position).normalized()
	if dir_a_cp0 == Vector2.ZERO:
		dir_a_cp0 = Vector2.RIGHT
	c_test.reiniciar_estado(esc_col.to_global(cp0.position - dir_a_cp0 * 12.0), dir_a_cp0.angle(), cps_col.size())
	c_test.velocidad_actual = 120.0
	for _f in range(18):
		await physics_frame
		if c_test.checkpoints_cruzados >= 1:
			break
	await _esperar_frames(2)
	_assert_true(
		c_test.checkpoints_cruzados >= 1 and lbl_cps0.text.begins_with("Checkpoints: 1"),
		"Overlap real CheckpointArea (CP0): cps=%d, Lbl='%s'" % [c_test.checkpoints_cruzados, lbl_cps0.text]
	)

	# 2) Colision real contra MurosPasto Layer 1
	var bandera_col: Sprite2D = vista_col.get("bandera_meta")
	c_test.reiniciar_estado(esc_col.to_global(bandera_col.position), -PI * 0.5, cps_col.size())
	c_test.velocidad_actual = 140.0
	for _f in range(30):
		await physics_frame
		if c_test.esta_chocado:
			break
	await _esperar_frames(2)
	_assert_true(
		c_test.esta_chocado and c_test.motivo_choque == "Chocado" and lbl_est0.text == "Chocado",
		"Colision real MurosPasto Layer 1: chocado=%s, motivo='%s', LblEstado='%s'" % [
			str(c_test.esta_chocado), c_test.motivo_choque, lbl_est0.text
		]
	)

	# 3) Seguridad al liberar vehiculo inspeccionado (VistaCarreraUI._actualizar_telemetria_hud + VisorRed)
	var visor_col: Control = vista_col.get("visor_red")
	visor_col.call("establecer_vehiculo", c_test)
	c_test.queue_free()
	await _esperar_frames(4)
	await _esperar_fisica(2)
	var snap_freed: Dictionary = visor_col.call("obtener_instantanea_segura")
	_assert_true(
		snap_freed["tiene_vehiculo"] == false,
		"Liberar vehiculo inspeccionado no falla en VistaCarreraUI ni en VisorRedNeuronal"
	)

	vp_col.queue_free()
	await _esperar_frames(2)


func _validar_geometria_vista(raiz: Control, res: Vector2i) -> Array[String]:
	var errores: Array[String] = []
	var rect_vp := Rect2(Vector2(-1.0, -1.0), Vector2(res) + Vector2(2.0, 2.0))

	var todos := _obtener_todos_nodos(raiz)
	for nodo in todos:
		if not (nodo is Control):
			continue
		var ctrl := nodo as Control
		if not ctrl.is_visible_in_tree() or ctrl is ScrollBar:
			continue
		var r := ctrl.get_global_rect()
		if r.size.x < 0.0 or r.size.y < 0.0 or not rect_vp.encloses(r):
			errores.append("Fuera de viewport: %s (%s)" % [ctrl.name, str(r)])

	for nodo in todos:
		if nodo is Control and (nodo as Control).is_visible_in_tree():
			var hijos_visibles: Array[Control] = []
			for ch in nodo.get_children():
				if ch is Control and (ch as Control).is_visible_in_tree():
					if ch.name == "Fondo" or ch is ScrollBar:
						continue
					hijos_visibles.append(ch as Control)
			for i in range(hijos_visibles.size()):
				for j in range(i + 1, hijos_visibles.size()):
					var r1 := hijos_visibles[i].get_global_rect()
					var r2 := hijos_visibles[j].get_global_rect()
					var inter := r1.intersection(r2)
					if inter.size.x > 1.0 and inter.size.y > 1.0:
						errores.append("Solapamiento %s vs %s (%s)" % [
							hijos_visibles[i].name, hijos_visibles[j].name, str(inter.size)
						])

	return errores


func _obtener_todos_nodos(raiz: Node) -> Array[Node]:
	var res: Array[Node] = [raiz]
	for ch in raiz.get_children():
		res.append_array(_obtener_todos_nodos(ch))
	return res
