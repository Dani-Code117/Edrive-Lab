extends SceneTree

## Pruebas automatizadas Fase 3: Vista 3 (Configuración de Carrera),
## flujo Vista 2 -> Vista 3, sincronización de tema, minimapa dinámico,
## tarjetas de vehículos, persistencia y layout responsivo sin solapamientos.

const RUTA_MENU := "res://Assets/Escenas/Vistas/menu_principal.tscn"
const RUTA_CREADOR := "res://Assets/Escenas/Vistas/creador_mapa.tscn"
const RUTA_CONFIG := "res://Assets/Escenas/Vistas/configuracion_carrera.tscn"
const RUTA_CARRERA := "res://Assets/Escenas/Vistas/vista_carrera.tscn"
const RUTA_TEMA_TELEMETRIA := "res://Assets/Temas/tema_telemetria.tres"
const RUTA_TEMA_EDRIVE := "res://Assets/Temas/tema_edrive.tres"
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


func _crear_circuito_prueba() -> Dictionary:
	# Circuito rectangular cerrado con ancho 3x3 en grilla 45x27
	var celdas: Dictionary = {}
	for x in range(8, 37):
		for dy in range(-1, 2):
			celdas[Vector2i(x, 6 + dy)] = true
			celdas[Vector2i(x, 20 + dy)] = true
	for y in range(6, 21):
		for dx in range(-1, 2):
			celdas[Vector2i(8 + dx, y)] = true
			celdas[Vector2i(36 + dx, y)] = true
	var meta := Vector2i(22, 6)
	var val := GeneradorCheckpoints.validar_y_generar(celdas, meta, true)
	return {"celdas": celdas, "meta": meta, "validacion": val}


func _run_all() -> void:
	await process_frame
	var ds := root.get_node_or_null("DatosSimulacion")
	_assert_true(ds != null, "Autoload DatosSimulacion disponible")
	if ds == null:
		quit(1)
		return

	var cfg_orig: Array[Dictionary] = ds.config_vehiculos.duplicate(true)

	await _test_a_checkpoints_escenas_y_tema(ds)
	await _test_b_minimapa_vacio_y_poblado(ds)
	await _test_c_tarjetas_sliders_e_ia(ds)
	await _test_d_persistencia_botones_y_presets(ds)
	await _test_e_layout_responsivo_sin_solapamientos(ds)

	# Restaurar estado limpio de DatosSimulacion
	ds.limpiar_pista()
	ds.config_vehiculos = cfg_orig

	print("=== Resumen Fase 3: %d verificaciones, %d fallos ===" % [_total_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_a_checkpoints_escenas_y_tema(ds: Node) -> void:
	print("--- Test (a): GeneradorCheckpoints 16px, escenas Vista 1-3 y tema_edrive.tres ---")
	var circuito := _crear_circuito_prueba()
	var val: Dictionary = circuito["validacion"]
	_assert_true(val.get("valido", false), "GeneradorCheckpoints.validar_y_generar sin 4to param valida circuito")

	var radios: Array = val.get("radios_eje", [])
	var max_radio := 0.0
	for r in radios:
		max_radio = maxf(max_radio, float(r))
	# En pista de grosor 3 (d_max = 2), radio con tamanio_celda=16 es (2 - 0.5) * 16 = 24.0 (con 32 seria 48.0)
	_assert_true(
		not radios.is_empty() and is_equal_approx(max_radio, 24.0),
		"GeneradorCheckpoints usa tamanio_celda=16 por defecto (radio eje %.1f == 24.0)" % max_radio
	)

	for ruta in [RUTA_MENU, RUTA_CREADOR, RUTA_CONFIG]:
		var ps := load(ruta) as PackedScene
		var inst := ps.instantiate() if ps != null else null
		var ok := ps != null and inst != null
		var botones_animados := true
		if inst != null:
			for n in _obtener_todos_nodos(inst):
				if n is Button and not (n is OptionButton):
					if not (n is BotonAnimado):
						botones_animados = false
						break
			inst.free()
		_assert_true(ok and botones_animados, "%s carga y todos sus Button usan BotonAnimado" % ruta.get_file())

	# Verificar sincronización tema_edrive.tres vs tema_telemetria.tres
	var t_tel := ResourceLoader.load(RUTA_TEMA_TELEMETRIA) as Theme
	var t_ed := ResourceLoader.load(RUTA_TEMA_EDRIVE) as Theme
	_assert_true(t_tel != null and t_ed != null, "Ambos temas cargan correctamente")
	if t_tel != null and t_ed != null:
		_assert_true(t_ed.default_font_size == 20 and t_tel.default_font_size == 20, "tema_edrive.tres default_font_size == 20")
		var sb_panel_ed := t_ed.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
		var sb_panel_tel := t_tel.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
		var sb_p_ed := t_ed.get_stylebox("panel", "Panel") as StyleBoxFlat
		var hover_ed := t_ed.get_color("font_hover_color", "Button")
		var label_ed := t_ed.get_color("font_color", "Label")
		var label_tel := t_tel.get_color("font_color", "Label")
		_assert_true(
			sb_panel_ed != null and sb_panel_tel != null and sb_p_ed != null
			and sb_panel_ed.bg_color.is_equal_approx(Color(0.071, 0.094, 0.133, 0.92))
			and sb_panel_ed.border_color.is_equal_approx(Color(0.165, 0.212, 0.282, 1.0))
			and sb_panel_ed.border_width_left == 2 and sb_panel_ed.corner_radius_top_left == 6
			and hover_ed.is_equal_approx(Color(0, 0.898, 1, 1))
			and label_ed.is_equal_approx(label_tel),
			"tema_edrive.tres sincronizado con tema_telemetria.tres (#121822 92%, #2A3648 2px, #00E5FF, radius 6)"
		)
	_assert_true(ds.TAMANIO_CELDA == 16, "DatosSimulacion.TAMANIO_CELDA == 16")


func _test_b_minimapa_vacio_y_poblado(ds: Node) -> void:
	print("--- Test (b): Minimapa Pista Confirmada (vacio y poblado) ---")
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	# 1. Pista vacía
	ds.limpiar_pista()
	var escena_vacia := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp.add_child(escena_vacia)
	await _esperar_frames(4)

	var resumen_vacio: Dictionary = escena_vacia.obtener_resumen_minimapa()
	_assert_true(
		escena_vacia.lbl_minimapa_vacio.visible
		and resumen_vacio["vacio"] == true
		and resumen_vacio["celdas"] == 0
		and resumen_vacio["checkpoints"] == 0
		and resumen_vacio["tiene_meta"] == false,
		"Minimapa vacio muestra LblMinimapaVacio y resumen vacio sin errores"
	)
	escena_vacia.queue_free()
	await _esperar_frames(2)

	# 2. Pista poblada
	var circuito := _crear_circuito_prueba()
	var val: Dictionary = circuito["validacion"]
	ds.guardar_pista(
		circuito["celdas"],
		circuito["meta"],
		val["checkpoints"],
		val["rotacion_salida"],
		val["eje_central"],
		val["radios_eje"],
		48.0
	)
	var escena_pob := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp.add_child(escena_pob)
	await _esperar_frames(4)

	var resumen_pob: Dictionary = escena_pob.obtener_resumen_minimapa()
	var lienzo: Control = escena_pob.lienzo_minimapa
	var rect_lienzo := Rect2(Vector2.ZERO, lienzo.size)
	var rect_pista: Rect2 = resumen_pob["rect_pista"]
	var rect_meta: Rect2 = resumen_pob["rect_meta"]
	_assert_true(
		not escena_pob.lbl_minimapa_vacio.visible
		and resumen_pob["vacio"] == false
		and resumen_pob["celdas"] == circuito["celdas"].size()
		and resumen_pob["checkpoints"] == val["checkpoints"].size()
		and resumen_pob["tiene_meta"] == true
		and rect_pista.size.x > 10.0 and rect_pista.size.y > 10.0
		and rect_lienzo.encloses(rect_pista)
		and rect_pista.encloses(rect_meta),
		"Minimapa poblado oculta aviso vacio, dibuja celdas/meta dentro de LienzoMinimapa"
	)
	_assert_true(
		escena_pob.lbl_stats_pista.text.contains(str(circuito["celdas"].size()))
		and escena_pob.lbl_stats_pista.text.contains(str(val["checkpoints"].size())),
		"LblStatsPista muestra cantidad real de celdas y checkpoints"
	)

	vp.queue_free()
	await _esperar_frames(2)


func _test_c_tarjetas_sliders_e_ia(ds: Node) -> void:
	print("--- Test (c): 3 tarjetas, coche_base.png, 5 sliders (0..1) y 10 niveles IA ---")
	var vp := SubViewport.new()
	vp.size = Vector2i(1440, 900)
	root.add_child(vp)

	var vista := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp.add_child(vista)
	await _esperar_frames(3)

	var tarjetas: Array = vista.contenedor_tarjetas.get_children()
	_assert_true(tarjetas.size() == 3, "Existen exactamente 3 tarjetas de vehiculos")

	var nombres_esperados := ["Coche Rojo", "Coche Azul", "Coche Verde"]
	var claves := ["velocidad_maxima", "aceleracion", "frenado", "control", "agarre"]
	var tarjetas_ok := true

	for i in range(tarjetas.size()):
		var t: PanelContainer = tarjetas[i]
		var lbl_nom: Label = t.get_node("VBox/Margin/Cuerpo/Header/LblNombre")
		var sprite: TextureRect = t.get_node("VBox/Margin/Cuerpo/VistaPrevia/Centro/SpriteCoche")
		var opt_ia: OptionButton = t.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
		var lbl_estado: Label = t.get_node("VBox/Margin/Cuerpo/SeccionIA/LblEstadoIA")
		var lbl_desc: Label = t.get_node("VBox/Margin/Cuerpo/SeccionIA/LblDescIA")
		var box_atr: VBoxContainer = t.get_node("VBox/Margin/Cuerpo/Atributos")

		if lbl_nom.text != nombres_esperados[i]:
			tarjetas_ok = false
		if sprite.texture == null or sprite.texture.get_size() != Vector2(24, 14):
			tarjetas_ok = false
		if not sprite.modulate.is_equal_approx(ds.config_vehiculos[i]["color"]):
			tarjetas_ok = false
		if opt_ia.item_count != 10:
			tarjetas_ok = false

		# Probar selección de nivel IA y manejo seguro de .tres ausente
		opt_ia.select(6)
		opt_ia.item_selected.emit(6)
		var ruta7 := CerebroEntrenado.ruta_para_nivel(7)
		if ResourceLoader.exists(ruta7):
			tarjetas_ok = false
		if lbl_desc.text != ds.NIVELES_IA[6]["desc"] or lbl_estado.text.is_empty():
			tarjetas_ok = false
		if ds.config_vehiculos[i]["nivel_ia"] != 7:
			tarjetas_ok = false

		# Verificar 5 sliders
		var filas := box_atr.get_children()
		if filas.size() != 5:
			tarjetas_ok = false
		else:
			for s_idx in range(5):
				var fila := filas[s_idx]
				var lbl_val: Label = fila.get_child(0).get_child(1)
				var slider: HSlider = fila.get_child(1)
				if not is_equal_approx(slider.min_value, 0.0) or not is_equal_approx(slider.max_value, 1.0):
					tarjetas_ok = false
				var nuevo_val := 0.25 + float(s_idx) * 0.15
				slider.value = nuevo_val
				if lbl_val.text != ("%.2f" % nuevo_val) or not is_equal_approx(ds.config_vehiculos[i][claves[s_idx]], nuevo_val):
					tarjetas_ok = false

	_assert_true(tarjetas_ok, "Todas las tarjetas validan sprite 24x14, color, 5 sliders 0..1 (%.2f), 10 niveles IA y estado sin .tres")

	vp.queue_free()
	await _esperar_frames(2)


func _test_d_persistencia_botones_y_presets(ds: Node) -> void:
	print("--- Test (d): Persistencia al iniciar, BtnVolver y Assets/Presets_ia/ ---")
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	root.add_child(vp)

	var vista := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp.add_child(vista)
	await _esperar_frames(3)

	# Cambiar OptNivelIA programáticamente SIN emitir item_selected (simula estado directo en UI)
	var opt_rojo: OptionButton = vista.contenedor_tarjetas.get_child(0).get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var slider_vel_azul: HSlider = vista.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/Atributos").get_child(0).get_child(1)
	opt_rojo.select(8) # Nivel 9
	slider_vel_azul.set_value_no_signal(0.95)

	if not ResourceLoader.exists(RUTA_CARRERA):
		vista._on_iniciar_pressed()
		_assert_true(
			ds.config_vehiculos[0]["nivel_ia"] == 9
			and is_equal_approx(ds.config_vehiculos[1]["velocidad_maxima"], 0.95)
			and vista.lbl_aviso.visible
			and not vista.lbl_aviso.text.is_empty(),
			"INICIAR SIMULACION persiste cambios programaticos y muestra LblAviso limpio si vista_carrera.tscn aun no existe"
		)
	else:
		vista._guardar_configuraciones()
		_assert_true(
			ds.config_vehiculos[0]["nivel_ia"] == 9
			and is_equal_approx(ds.config_vehiculos[1]["velocidad_maxima"], 0.95),
			"_guardar_configuraciones() persiste cambios programaticos antes de transicionar a Vista 4"
		)

	_assert_true(ResourceLoader.exists(vista.ESCENA_CREADOR), "Destino de BtnVolver (creador_mapa.tscn) existe")

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

	vp.queue_free()
	await _esperar_frames(2)


func _test_e_layout_responsivo_sin_solapamientos(ds: Node) -> void:
	print("--- Test (e): Layout responsivo sin solapamientos en 1920x1080, 1440x900, 1280x960, 1280x720 ---")
	var circuito := _crear_circuito_prueba()
	var val: Dictionary = circuito["validacion"]
	ds.guardar_pista(
		circuito["celdas"],
		circuito["meta"],
		val["checkpoints"],
		val["rotacion_salida"],
		val["eje_central"],
		val["radios_eje"],
		48.0
	)

	for res: Vector2i in RESOLUCIONES:
		var vp := SubViewport.new()
		vp.size = res
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)

		var vista := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
		vp.add_child(vista)
		await _esperar_frames(4)

		for estado_aviso in [false, true]:
			if estado_aviso:
				vista.lbl_aviso.text = "Configuración guardada para los 3 vehículos. La Vista 4 (Carrera / Simulación) es el siguiente módulo."
				vista.lbl_aviso.visible = true
				await _esperar_frames(3)

			var problemas := _validar_geometria_vista(vista, res)
			var scroll: ScrollContainer = vista.get_node("Layout/Contenido/ScrollArea")
			var vbar := scroll.get_v_scroll_bar()
			var sin_scroll := vbar.max_value <= scroll.size.y + 1.5
			_assert_true(
				problemas.is_empty() and sin_scroll,
				"Layout %dx%d (aviso=%s) sin recortes, sin solapamientos y sin overflow (vbar max=%.1f <= %.1f; errs=%s)" % [
					res.x, res.y, str(estado_aviso), vbar.max_value, scroll.size.y, str(problemas)
				]
			)

		vp.queue_free()
		await _esperar_frames(2)


func _validar_geometria_vista(raiz: Control, res: Vector2i) -> Array[String]:
	var errores: Array[String] = []
	var rect_vp := Rect2(Vector2(-1.0, -1.0), Vector2(res) + Vector2(2.0, 2.0))

	var todos := _obtener_todos_nodos(raiz)
	for nodo in todos:
		if not (nodo is Control):
			continue
		var ctrl := nodo as Control
		if not ctrl.is_visible_in_tree():
			continue
		# Ignorar scrollbars internos ocultos/automáticos
		if ctrl is ScrollBar:
			continue
		var r := ctrl.get_global_rect()
		if r.size.x < 0.0 or r.size.y < 0.0 or not rect_vp.encloses(r):
			errores.append("Fuera de viewport: %s (%s)" % [ctrl.name, str(r)])

	# Comprobar solapamientos entre hermanos visibles (excluyendo Fondo full-bleed)
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
