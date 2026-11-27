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
	await _test_f_arquetipos_vehiculo(ds)
	await _test_g_modo_piloto_humano_y_exclusividad(ds)

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

	# Regresión Tier 5: lazos cerrados con espolones (derecha, izquierda, arriba, abajo) y meta en espolón
	var base_lazo: Dictionary = {}
	for x in range(8, 27):
		for y in range(5, 8):
			base_lazo[Vector2i(x, y)] = true
		for y in range(17, 20):
			base_lazo[Vector2i(x, y)] = true
	for y in range(5, 20):
		for x in range(8, 11):
			base_lazo[Vector2i(x, y)] = true
		for x in range(24, 27):
			base_lazo[Vector2i(x, y)] = true

	var espolones: Dictionary = {
		"derecha": [],
		"izquierda": [],
		"arriba": [],
		"abajo": [],
	}
	for x in range(27, 34):
		for y in range(11, 14):
			espolones["derecha"].append(Vector2i(x, y))
	for x in range(2, 8):
		for y in range(11, 14):
			espolones["izquierda"].append(Vector2i(x, y))
	for x in range(16, 19):
		for y in range(1, 5):
			espolones["arriba"].append(Vector2i(x, y))
	for x in range(16, 19):
		for y in range(20, 24):
			espolones["abajo"].append(Vector2i(x, y))

	for dir_nombre in espolones.keys():
		var celdas_esp: Dictionary = base_lazo.duplicate()
		for c_esp: Vector2i in espolones[dir_nombre]:
			celdas_esp[c_esp] = true
		var res_esp := GeneradorCheckpoints.validar_y_generar(celdas_esp, Vector2i(25, 8), true)
		_assert_true(
			res_esp.get("valido", false) and res_esp.get("checkpoints", []).size() >= 3,
			"Lazo cerrado con espolon %s valida correctamente (%d cps)" % [dir_nombre, res_esp.get("checkpoints", []).size()]
		)

	var celdas_meta_esp: Dictionary = base_lazo.duplicate()
	for c_esp: Vector2i in espolones["derecha"]:
		celdas_meta_esp[c_esp] = true
	var res_meta_esp := GeneradorCheckpoints.validar_y_generar(celdas_meta_esp, Vector2i(30, 12), true)
	_assert_true(
		not res_meta_esp.get("valido", true)
		and res_meta_esp.get("mensaje", "") == "Asegúrate de que la meta esté sobre el lazo cerrado del circuito.",
		"Meta colocada sobre espolon muerto falla con mensaje esperado"
	)

	# Regresión Tier 5 Cycle 2: mallas con múltiples huecos (grid6, grid8, swiss) y mancuerna (lóbulo vs puente)
	var grid6: Dictionary = {}
	for x in range(2, 39):
		for y in range(2, 5):
			grid6[Vector2i(x, y)] = true
		for y in range(12, 15):
			grid6[Vector2i(x, y)] = true
		for y in range(22, 25):
			grid6[Vector2i(x, y)] = true
	for y in range(2, 25):
		for x in range(2, 5):
			grid6[Vector2i(x, y)] = true
		for x in range(13, 16):
			grid6[Vector2i(x, y)] = true
		for x in range(25, 28):
			grid6[Vector2i(x, y)] = true
		for x in range(36, 39):
			grid6[Vector2i(x, y)] = true

	for meta_g6: Vector2i in [Vector2i(3, 8), Vector2i(3, 18)]:
		var res_g6 := GeneradorCheckpoints.validar_y_generar(grid6, meta_g6, true)
		var eje_g6: Array = res_g6.get("eje_central", [])
		var suma_cruz_g6 := _calcular_suma_cruz_horaria(eje_g6)
		_assert_true(
			res_g6.get("valido", false)
			and res_g6.get("checkpoints", []).size() >= 3
			and suma_cruz_g6 > 0.0,
			"grid6 con meta %s valida en sentido horario (%d cps, cruz=%.1f)" % [
				str(meta_g6), res_g6.get("checkpoints", []).size(), suma_cruz_g6
			]
		)

	var grid8: Dictionary = {}
	for x in range(2, 42):
		for y in range(2, 5):
			grid8[Vector2i(x, y)] = true
		for y in range(12, 15):
			grid8[Vector2i(x, y)] = true
		for y in range(22, 25):
			grid8[Vector2i(x, y)] = true
	for y in range(2, 25):
		for vx in [2, 12, 21, 30, 39]:
			for dx in range(3):
				grid8[Vector2i(vx + dx, y)] = true

	var res_g8 := GeneradorCheckpoints.validar_y_generar(grid8, Vector2i(3, 8), true)
	_assert_true(
		res_g8.get("valido", false) and res_g8.get("checkpoints", []).size() >= 3,
		"grid8 con meta (3, 8) valida correctamente (%d cps)" % res_g8.get("checkpoints", []).size()
	)

	var swiss: Dictionary = {}
	for x in range(1, 44):
		for y in range(1, 26):
			swiss[Vector2i(x, y)] = true
	for hx in range(4, 41, 4):
		for hy in range(4, 23, 3):
			swiss.erase(Vector2i(hx, hy))
			swiss.erase(Vector2i(hx + 1, hy))

	for meta_sw: Vector2i in [Vector2i(2, 2), Vector2i(15, 12)]:
		var res_sw := GeneradorCheckpoints.validar_y_generar(swiss, meta_sw, true)
		_assert_true(
			res_sw.get("valido", false) and res_sw.get("checkpoints", []).size() >= 3,
			"swiss_43x25_many_holes con meta %s valida correctamente (%d cps)" % [
				str(meta_sw), res_sw.get("checkpoints", []).size()
			]
		)

	# Mancuerna: lóbulo izquierdo + puente 3-celdas + lóbulo derecho
	var mancuerna: Dictionary = {}
	for x in range(4, 15):
		for y in range(5, 8):
			mancuerna[Vector2i(x, y)] = true
		for y in range(13, 16):
			mancuerna[Vector2i(x, y)] = true
	for y in range(5, 16):
		for x in range(4, 7):
			mancuerna[Vector2i(x, y)] = true
		for x in range(12, 15):
			mancuerna[Vector2i(x, y)] = true
	for x in range(15, 22):
		for y in range(9, 12):
			mancuerna[Vector2i(x, y)] = true
	for x in range(22, 33):
		for y in range(5, 8):
			mancuerna[Vector2i(x, y)] = true
		for y in range(13, 16):
			mancuerna[Vector2i(x, y)] = true
	for y in range(5, 16):
		for x in range(22, 25):
			mancuerna[Vector2i(x, y)] = true
		for x in range(30, 33):
			mancuerna[Vector2i(x, y)] = true

	var res_manc_lob := GeneradorCheckpoints.validar_y_generar(mancuerna, Vector2i(5, 10), true)
	_assert_true(
		res_manc_lob.get("valido", false) and res_manc_lob.get("checkpoints", []).size() >= 3,
		"Mancuerna con meta en lobulo izquierdo (5, 10) valida correctamente (%d cps)" % res_manc_lob.get("checkpoints", []).size()
	)
	var res_manc_puente := GeneradorCheckpoints.validar_y_generar(mancuerna, Vector2i(18, 10), true)
	_assert_true(
		not res_manc_puente.get("valido", true)
		and res_manc_puente.get("mensaje", "") == "Asegúrate de que la meta esté sobre el lazo cerrado del circuito.",
		"Mancuerna con meta en puente (18, 10) falla limpiamente con mensaje esperado"
	)

	# Regresión Tier 5 Cycle 3: circuitos con huecos 1x1 (swiss_1x1_stride4, asym_fig8 lobe) y anillo 4x4 aislado
	var swiss_1x1_s4: Dictionary = {}
	for x in range(1, 44):
		for y in range(1, 26):
			swiss_1x1_s4[Vector2i(x, y)] = true
	for hx in range(4, 41, 4):
		for hy in range(4, 23, 4):
			swiss_1x1_s4.erase(Vector2i(hx, hy))

	for meta_s4: Vector2i in [Vector2i(38, 4), Vector2i(39, 5)]:
		var res_s4 := GeneradorCheckpoints.validar_y_generar(swiss_1x1_s4, meta_s4, true)
		var eje_s4: Array = res_s4.get("eje_central", [])
		var cruz_s4 := _calcular_suma_cruz_horaria(eje_s4)
		_assert_true(
			res_s4.get("valido", false)
			and res_s4.get("checkpoints", []).size() >= 3
			and cruz_s4 > 0.0,
			"swiss_1x1_stride4 con meta %s valida en sentido horario (%d cps, cruz=%.1f)" % [
				str(meta_s4), res_s4.get("checkpoints", []).size(), cruz_s4
			]
		)

	var asym_fig8_lobe: Dictionary = {}
	for x in range(6, 20):
		for y in range(5, 8):
			asym_fig8_lobe[Vector2i(x, y)] = true
		for y in range(17, 20):
			asym_fig8_lobe[Vector2i(x, y)] = true
	for y in range(5, 20):
		for x in range(6, 9):
			asym_fig8_lobe[Vector2i(x, y)] = true
		for x in range(17, 20):
			asym_fig8_lobe[Vector2i(x, y)] = true
	for x in range(18, 24):
		for y in range(9, 16):
			asym_fig8_lobe[Vector2i(x, y)] = true
	asym_fig8_lobe.erase(Vector2i(20, 12))

	for meta_lobe: Vector2i in [Vector2i(21, 11), Vector2i(21, 12), Vector2i(21, 13)]:
		var res_lobe := GeneradorCheckpoints.validar_y_generar(asym_fig8_lobe, meta_lobe, true)
		var eje_lobe: Array = res_lobe.get("eje_central", [])
		var cruz_lobe := _calcular_suma_cruz_horaria(eje_lobe)
		_assert_true(
			res_lobe.get("valido", false)
			and res_lobe.get("checkpoints", []).size() >= 3
			and cruz_lobe > 0.0,
			"asym_fig8 lobe con hueco 1x1 y meta %s valida en sentido horario (%d cps, cruz=%.1f)" % [
				str(meta_lobe), res_lobe.get("checkpoints", []).size(), cruz_lobe
			]
		)

	var anillo_4x4: Dictionary = {}
	for x in range(4, 8):
		for y in range(4, 8):
			anillo_4x4[Vector2i(x, y)] = true
	anillo_4x4.erase(Vector2i(5, 5))
	var res_4x4 := GeneradorCheckpoints.validar_y_generar(anillo_4x4, Vector2i(4, 4), true)
	_assert_true(
		not res_4x4.get("valido", true)
		and res_4x4.get("mensaje", "") == "El circuito necesita ser un poco más largo para generar checkpoints.",
		"Anillo 4x4 aislado se rechaza limpiamente por falta de longitud para checkpoints"
	)


static func _calcular_suma_cruz_horaria(ciclo: Array) -> float:
	if ciclo.size() < 3:
		return 0.0
	var centroide := Vector2.ZERO
	for p in ciclo:
		centroide += Vector2(p)
	centroide /= float(ciclo.size())
	var suma := 0.0
	var n := ciclo.size()
	for i in range(n):
		var p1 := Vector2(ciclo[i]) - centroide
		var p2 := Vector2(ciclo[(i + 1) % n]) - centroide
		suma += p1.x * p2.y - p1.y * p2.x
	return suma


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

	# Regresión Tier 5: sanitización de NaN/INF/fuera de rango en DatosSimulacion.config_vehiculos al abrir Vista 3
	var cfg_backup: Array[Dictionary] = ds.config_vehiculos.duplicate(true)
	ds.config_vehiculos[0]["velocidad_maxima"] = NAN
	ds.config_vehiculos[0]["aceleracion"] = INF
	ds.config_vehiculos[0]["nivel_ia"] = -5

	var vp_nan := SubViewport.new()
	vp_nan.size = Vector2i(1280, 720)
	root.add_child(vp_nan)

	var vista_nan := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_nan.add_child(vista_nan)
	await _esperar_frames(3)

	var vel_cargada: Variant = ds.config_vehiculos[0]["velocidad_maxima"]
	var acel_cargada: Variant = ds.config_vehiculos[0]["aceleracion"]
	_assert_true(
		(vel_cargada is float or vel_cargada is int) and is_finite(float(vel_cargada))
		and float(vel_cargada) >= 0.0 and float(vel_cargada) <= 1.0
		and (acel_cargada is float or acel_cargada is int) and is_finite(float(acel_cargada))
		and float(acel_cargada) >= 0.0 and float(acel_cargada) <= 1.0,
		"Vista 3 sanea velocidad_maxima=NAN y aceleracion=INF a finitos en [0.0, 1.0] al cargar"
	)

	vista_nan._guardar_configuraciones()
	var vel_guardada: Variant = ds.config_vehiculos[0]["velocidad_maxima"]
	var ia_guardado: int = int(ds.config_vehiculos[0]["nivel_ia"])
	_assert_true(
		is_finite(float(vel_guardada)) and float(vel_guardada) >= 0.0 and float(vel_guardada) <= 1.0
		and ia_guardado >= 1 and ia_guardado <= 10,
		"Vista 3 _guardar_configuraciones() mantiene velocidad_maxima finita en [0,1] y nivel_ia en [1,10]"
	)

	vp_nan.queue_free()
	await _esperar_frames(2)
	ds.config_vehiculos = cfg_backup

	# Regresión Tier 5 Cycle 2: preservación exacta 0.83 (step=0.01) y saneamiento de color/nombre/nivel_ia al cargar
	var cfg_backup_c2: Array[Dictionary] = ds.config_vehiculos.duplicate(true)
	ds.config_vehiculos[0]["agarre"] = 0.83
	ds.config_vehiculos[1]["velocidad_maxima"] = 0.83

	var vp_083 := SubViewport.new()
	vp_083.size = Vector2i(1280, 720)
	root.add_child(vp_083)

	var vista_083 := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_083.add_child(vista_083)
	await _esperar_frames(3)

	var fila_agarre0: Node = vista_083.contenedor_tarjetas.get_child(0).get_node("VBox/Margin/Cuerpo/Atributos").get_child(4)
	var lbl_agarre0: Label = fila_agarre0.get_child(0).get_child(1)
	var slider_agarre0: HSlider = fila_agarre0.get_child(1)
	var fila_vel1: Node = vista_083.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/Atributos").get_child(0)
	var lbl_vel1: Label = fila_vel1.get_child(0).get_child(1)
	var slider_vel1: HSlider = fila_vel1.get_child(1)
	_assert_true(
		is_equal_approx(slider_agarre0.value, 0.83) and lbl_agarre0.text == "0.83"
		and is_equal_approx(slider_vel1.value, 0.83) and lbl_vel1.text == "0.83",
		"Vista 3 preserva 0.83 en slider y etiqueta sin cuantizar a 0.85 al cargar"
	)

	vista_083._guardar_configuraciones()
	_assert_true(
		is_equal_approx(float(ds.config_vehiculos[0]["agarre"]), 0.83)
		and is_equal_approx(float(ds.config_vehiculos[1]["velocidad_maxima"]), 0.83),
		"Vista 3 _guardar_configuraciones() preserva valores finitos 0.83 intactos"
	)

	vp_083.queue_free()
	await _esperar_frames(2)

	# Corrupt color/nombre/nivel_ia load sanitization
	ds.config_vehiculos = cfg_backup_c2.duplicate(true)
	ds.config_vehiculos[0]["color"] = null
	ds.config_vehiculos[1]["color"] = "rojo"
	ds.config_vehiculos[0]["nombre"] = null
	ds.config_vehiculos[0]["nivel_ia"] = "bad"
	ds.config_vehiculos[1]["nivel_ia"] = null

	var vp_corrupt := SubViewport.new()
	vp_corrupt.size = Vector2i(1280, 720)
	root.add_child(vp_corrupt)

	var vista_corrupt := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_corrupt.add_child(vista_corrupt)
	await _esperar_frames(3)

	_assert_true(
		ds.config_vehiculos[0]["color"] is Color
		and (ds.config_vehiculos[0]["color"] as Color).is_equal_approx(Color.WHITE)
		and ds.config_vehiculos[1]["color"] is Color
		and (ds.config_vehiculos[1]["color"] as Color).is_equal_approx(Color.WHITE)
		and ds.config_vehiculos[0]["nombre"] is String
		and not str(ds.config_vehiculos[0]["nombre"]).is_empty()
		and ds.config_vehiculos[0]["nivel_ia"] is int
		and ds.config_vehiculos[0]["nivel_ia"] == 5
		and ds.config_vehiculos[1]["nivel_ia"] is int
		and ds.config_vehiculos[1]["nivel_ia"] == 5,
		"Vista 3 sanea color/nombre/nivel_ia corruptos en DatosSimulacion inmediatamente al cargar"
	)

	vista_corrupt._guardar_configuraciones()
	_assert_true(
		ds.config_vehiculos[0]["nivel_ia"] is int and ds.config_vehiculos[0]["nivel_ia"] == 5
		and ds.config_vehiculos[1]["nivel_ia"] is int and ds.config_vehiculos[1]["nivel_ia"] == 5,
		"Vista 3 _guardar_configuraciones() mantiene nivel_ia saneado como int 5"
	)

	vp_corrupt.queue_free()
	await _esperar_frames(2)

	# Regresión Tier 5 Cycle 3: reparación al cargar de floats finitos fuera de rango (-5.0 -> 0.0, 99.0 -> 1.0) y nombre solo espacios
	ds.config_vehiculos = cfg_backup_c2.duplicate(true)
	ds.config_vehiculos[0]["velocidad_maxima"] = -5.0
	ds.config_vehiculos[0]["aceleracion"] = 99.0
	ds.config_vehiculos[0]["nombre"] = "   "

	var vp_rango := SubViewport.new()
	vp_rango.size = Vector2i(1280, 720)
	root.add_child(vp_rango)

	var vista_rango := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_rango.add_child(vista_rango)
	await _esperar_frames(3)

	_assert_true(
		is_equal_approx(float(ds.config_vehiculos[0]["velocidad_maxima"]), 0.0)
		and is_equal_approx(float(ds.config_vehiculos[0]["aceleracion"]), 1.0)
		and ds.config_vehiculos[0]["nombre"] == "Vehículo 1",
		"Vista 3 repara al cargar floats finitos fuera de rango (-5.0->0.0, 99.0->1.0) y nombre de solo espacios"
	)

	vp_rango.queue_free()
	await _esperar_frames(2)
	ds.config_vehiculos = cfg_backup_c2


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

		for escenario: Dictionary in [
			{"aviso": false, "humano": false, "etiqueta": "aviso=false, modo=IA"},
			{"aviso": true, "humano": false, "etiqueta": "aviso=true, modo=IA"},
			{"aviso": true, "humano": true, "etiqueta": "aviso=true, modo=mixto_humano"},
		]:
			vista.lbl_aviso.text = "Configuración guardada para los 3 vehículos. La Vista 4 (Carrera / Simulación) es el siguiente módulo."
			vista.lbl_aviso.visible = bool(escenario["aviso"])
			vista.establecer_modo_humano(0, bool(escenario["humano"]))
			await _esperar_frames(3)

			var problemas := _validar_geometria_vista(vista, res)
			var errores_botones := _validar_texto_botones_tarjetas(vista.contenedor_tarjetas)
			problemas.append_array(errores_botones)
			var scroll: ScrollContainer = vista.get_node("Layout/Contenido/ScrollArea")
			var vbar := scroll.get_v_scroll_bar()
			var sin_scroll := vbar.max_value <= scroll.size.y + 1.5
			_assert_true(
				problemas.is_empty() and sin_scroll,
				"Layout %dx%d (%s) sin recortes, sin solapamientos y sin overflow (vbar max=%.1f <= %.1f; errs=%s)" % [
					res.x, res.y, str(escenario["etiqueta"]), vbar.max_value, scroll.size.y, str(problemas)
				]
			)

		ds.establecer_humano_exclusivo(0, false)
		vp.queue_free()
		await _esperar_frames(2)


func _validar_texto_botones_tarjetas(tarjetas: Control) -> Array[String]:
	var errores: Array[String] = []
	for nodo in _obtener_todos_nodos(tarjetas):
		if not (nodo is Button) or (nodo is OptionButton):
			continue
		var btn := nodo as Button
		if not btn.is_visible_in_tree():
			continue
		if btn.clip_text:
			errores.append("Boton con clip_text=true: %s" % btn.name)
		var min_sz := btn.get_minimum_size()
		if btn.size.x + 0.5 < min_sz.x or btn.size.y + 0.5 < min_sz.y:
			errores.append("Boton %s menor que min_size (%s < %s)" % [btn.name, str(btn.size), str(min_sz)])
		var font := btn.get_theme_font("font")
		var fsize := btn.get_theme_font_size("font_size")
		if font != null:
			var text_w := font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			if text_w > btn.size.x - 4.0:
				errores.append("Texto recortado en %s (%.1f > %.1f)" % [btn.name, text_w, btn.size.x])
	return errores


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


func _test_f_arquetipos_vehiculo(ds: Node) -> void:
	print("--- Test (f): Arquetipos de vehiculo (Equilibrado, Velocista, Drift, Tecnico y Personalizado) ---")
	var cfg_backup: Array[Dictionary] = ds.config_vehiculos.duplicate(true)
	ds.restaurar_config_vehiculos_defecto()

	var esquema_ok: bool = ds.config_vehiculos.size() == 3
	for cfg: Dictionary in ds.config_vehiculos:
		if cfg.get("arquetipo", "") != "Personalizado" or cfg.get("es_humano", true) != false:
			esquema_ok = false
	_assert_true(esquema_ok, "restaurar_config_vehiculos_defecto() inicializa arquetipo='Personalizado' y es_humano=false")

	var perfiles_esperados: Dictionary = {
		"Equilibrado": {"velocidad_maxima": 0.50, "aceleracion": 0.50, "frenado": 0.50, "control": 0.50, "agarre": 0.50},
		"Velocista": {"velocidad_maxima": 0.95, "aceleracion": 0.85, "frenado": 0.55, "control": 0.40, "agarre": 0.40},
		"Drift": {"velocidad_maxima": 0.75, "aceleracion": 0.85, "frenado": 0.55, "control": 0.85, "agarre": 0.25},
		"Técnico": {"velocidad_maxima": 0.60, "aceleracion": 0.70, "frenado": 0.90, "control": 0.90, "agarre": 0.90},
	}

	# Validar relaciones de perfil físico
	_assert_true(
		float(perfiles_esperados["Velocista"]["velocidad_maxima"]) > float(perfiles_esperados["Técnico"]["velocidad_maxima"])
		and float(perfiles_esperados["Velocista"]["aceleracion"]) > float(perfiles_esperados["Equilibrado"]["aceleracion"])
		and float(perfiles_esperados["Velocista"]["control"]) < float(perfiles_esperados["Técnico"]["control"])
		and float(perfiles_esperados["Velocista"]["agarre"]) < float(perfiles_esperados["Técnico"]["agarre"])
		and float(perfiles_esperados["Drift"]["agarre"]) < float(perfiles_esperados["Velocista"]["agarre"])
		and float(perfiles_esperados["Velocista"]["agarre"]) < float(perfiles_esperados["Equilibrado"]["agarre"])
		and float(perfiles_esperados["Equilibrado"]["agarre"]) < float(perfiles_esperados["Técnico"]["agarre"])
		and float(perfiles_esperados["Técnico"]["frenado"]) > float(perfiles_esperados["Drift"]["frenado"])
		and float(perfiles_esperados["Técnico"]["control"]) >= float(perfiles_esperados["Drift"]["control"]),
		"Perfiles Equilibrado/Velocista/Drift/Tecnico mantienen invariantes fisicas coherentes"
	)

	var vp := SubViewport.new()
	vp.size = Vector2i(1440, 900)
	root.add_child(vp)

	var vista := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp.add_child(vista)
	await _esperar_frames(3)

	var card0: Node = vista.contenedor_tarjetas.get_child(0)
	var card1: Node = vista.contenedor_tarjetas.get_child(1)
	var card2: Node = vista.contenedor_tarjetas.get_child(2)

	var lbl_arq0: Label = card0.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var btns0: Dictionary = {
		"Equilibrado": card0.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqEquilibrado") as Button,
		"Velocista": card0.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqVelocista") as Button,
		"Drift": card0.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqDrift") as Button,
		"Técnico": card0.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqTecnico") as Button,
	}
	var box_atr0: VBoxContainer = card0.get_node("VBox/Margin/Cuerpo/Atributos")
	var claves := ["velocidad_maxima", "aceleracion", "frenado", "control", "agarre"]

	var vel_card1_inicial: float = float(ds.config_vehiculos[1]["velocidad_maxima"])
	var arq_card2_inicial: String = str(ds.config_vehiculos[2]["arquetipo"])

	# Probar cada arquetipo por botón (.pressed.emit y .button_pressed = true) y método público
	var presets_ui_ok := true
	for nombre_arq: String in ["Equilibrado", "Velocista", "Drift", "Técnico"]:
		var btn_target: Button = btns0[nombre_arq]
		if nombre_arq == "Velocista":
			btn_target.button_pressed = true # Emite toggled(true)
		elif nombre_arq == "Técnico":
			vista.aplicar_arquetipo(0, nombre_arq)
		else:
			btn_target.pressed.emit()
		await _esperar_frames(1)

		var perfil: Dictionary = perfiles_esperados[nombre_arq]
		if lbl_arq0.text != nombre_arq or ds.config_vehiculos[0]["arquetipo"] != nombre_arq:
			presets_ui_ok = false
		for k_btn: String in btns0.keys():
			if (btns0[k_btn] as Button).button_pressed != (k_btn == nombre_arq):
				presets_ui_ok = false
		for s_idx in range(5):
			var clave: String = claves[s_idx]
			var fila := box_atr0.get_child(s_idx)
			var lbl_val: Label = fila.get_child(0).get_child(1)
			var slider: HSlider = fila.get_child(1)
			var esperado := float(perfil[clave])
			if not is_equal_approx(slider.value, esperado) or lbl_val.text != ("%.2f" % esperado) or not is_equal_approx(float(ds.config_vehiculos[0][clave]), esperado):
				presets_ui_ok = false

	_assert_true(
		presets_ui_ok
		and is_equal_approx(float(ds.config_vehiculos[1]["velocidad_maxima"]), vel_card1_inicial)
		and ds.config_vehiculos[2]["arquetipo"] == arq_card2_inicial,
		"Los 4 arquetipos aplican valores exactos, resaltan su boton y mantienen independencia entre tarjetas"
	)

	# Intentar desmarcar botón ya activo (button_pressed = false) y re-clic mantiene el arquetipo activo
	(btns0["Técnico"] as Button).button_pressed = false
	await _esperar_frames(1)
	_assert_true(
		lbl_arq0.text == "Técnico"
		and ds.config_vehiculos[0]["arquetipo"] == "Técnico"
		and (btns0["Técnico"] as Button).button_pressed,
		"Regresion toggled(false) en BtnArq activo mantiene button_pressed=true, LblArquetipo y DatosSimulacion"
	)
	(btns0["Técnico"] as Button).pressed.emit()
	await _esperar_frames(1)
	_assert_true(
		lbl_arq0.text == "Técnico"
		and ds.config_vehiculos[0]["arquetipo"] == "Técnico"
		and (btns0["Técnico"] as Button).button_pressed,
		"Re-seleccionar el boton de arquetipo activo mantiene el arquetipo seleccionado"
	)

	# Mover un slider manualmente cambia indicador a Personalizado y persiste
	vista.aplicar_arquetipo(0, "Velocista")
	await _esperar_frames(1)
	var slider_agarre0: HSlider = box_atr0.get_child(4).get_child(1)
	slider_agarre0.value = 0.62
	await _esperar_frames(1)

	var botones_desmarcados := true
	for k_btn: String in btns0.keys():
		if (btns0[k_btn] as Button).button_pressed:
			botones_desmarcados = false
	_assert_true(
		lbl_arq0.text == "Personalizado"
		and ds.config_vehiculos[0]["arquetipo"] == "Personalizado"
		and is_equal_approx(float(ds.config_vehiculos[0]["agarre"]), 0.62)
		and botones_desmarcados,
		"Mover cualquier slider manualmente cambia indicador a 'Personalizado' y desmarca presets"
	)

	# Aplicar Drift en tarjeta 1 y Personalizado en tarjeta 0; verificar persistencia tras recarga
	vista.aplicar_arquetipo(1, "Drift")
	vista._guardar_configuraciones()
	vp.queue_free()
	await _esperar_frames(2)

	var vp_re := SubViewport.new()
	vp_re.size = Vector2i(1280, 720)
	root.add_child(vp_re)
	var vista_re := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_re.add_child(vista_re)
	await _esperar_frames(3)

	var lbl_arq_re0: Label = vista_re.contenedor_tarjetas.get_child(0).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var lbl_arq_re1: Label = vista_re.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var btn_drift_re1: Button = vista_re.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqDrift")
	_assert_true(
		lbl_arq_re0.text == "Personalizado"
		and ds.config_vehiculos[0]["arquetipo"] == "Personalizado"
		and is_equal_approx(float(ds.config_vehiculos[0]["agarre"]), 0.62)
		and lbl_arq_re1.text == "Drift"
		and ds.config_vehiculos[1]["arquetipo"] == "Drift"
		and btn_drift_re1.button_pressed,
		"Arquetipo seleccionado y cambio a Personalizado persisten tras recargar Vista 3"
	)
	vp_re.queue_free()
	await _esperar_frames(2)

	# Saneamiento de arquetipos corruptos al cargar Vista 3
	ds.config_vehiculos[0]["arquetipo"] = "Inexistente"
	ds.config_vehiculos[1]["arquetipo"] = null
	ds.config_vehiculos[2]["arquetipo"] = "Tecnico"

	var vp_corrupt := SubViewport.new()
	vp_corrupt.size = Vector2i(1280, 720)
	root.add_child(vp_corrupt)
	var vista_corrupt := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_corrupt.add_child(vista_corrupt)
	await _esperar_frames(3)

	var lbl_c0: Label = vista_corrupt.contenedor_tarjetas.get_child(0).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var lbl_c1: Label = vista_corrupt.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var lbl_c2: Label = vista_corrupt.contenedor_tarjetas.get_child(2).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var btn_tec_c2: Button = vista_corrupt.contenedor_tarjetas.get_child(2).get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqTecnico")
	_assert_true(
		ds.config_vehiculos[0]["arquetipo"] == "Personalizado" and lbl_c0.text == "Personalizado"
		and ds.config_vehiculos[1]["arquetipo"] == "Personalizado" and lbl_c1.text == "Personalizado"
		and ds.config_vehiculos[2]["arquetipo"] == "Técnico" and lbl_c2.text == "Técnico"
		and btn_tec_c2.button_pressed,
		"Vista 3 sanea arquetipos corruptos ('Inexistente'/null -> 'Personalizado', 'Tecnico' -> 'Técnico') al cargar"
	)

	vp_corrupt.queue_free()
	await _esperar_frames(2)
	ds.config_vehiculos = cfg_backup


func _test_g_modo_piloto_humano_y_exclusividad(ds: Node) -> void:
	print("--- Test (g): Selector IA / Piloto Humano, exclusividad max-1, controles y saneamiento ---")
	var cfg_backup: Array[Dictionary] = ds.config_vehiculos.duplicate(true)
	ds.restaurar_config_vehiculos_defecto()

	# Verificar sanitizar_es_humano estricto (nunca bool(String))
	_assert_true(
		ds.sanitizar_es_humano(true) == true
		and ds.sanitizar_es_humano(false) == false
		and ds.sanitizar_es_humano(1) == true
		and ds.sanitizar_es_humano(0) == false
		and ds.sanitizar_es_humano("false") == false
		and ds.sanitizar_es_humano("true") == false
		and ds.sanitizar_es_humano("bad") == false
		and ds.sanitizar_es_humano(null) == false
		and ds.sanitizar_es_humano(1.5) == false,
		"sanitizar_es_humano() aplica comprobacion estricta de tipo (rechaza String 'false'/'true' y null)"
	)

	var vp := SubViewport.new()
	vp.size = Vector2i(1440, 900)
	root.add_child(vp)

	var vista := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp.add_child(vista)
	await _esperar_frames(3)

	var btns_ia: Array[Button] = []
	var btns_hum: Array[Button] = []
	var opts_ia: Array[OptionButton] = []
	var lbls_estado: Array[Label] = []
	var lbls_desc: Array[Label] = []
	for i in range(3):
		var t: Node = vista.contenedor_tarjetas.get_child(i)
		btns_ia.append(t.get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoIA") as Button)
		btns_hum.append(t.get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoHumano") as Button)
		opts_ia.append(t.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA") as OptionButton)
		lbls_estado.append(t.get_node("VBox/Margin/Cuerpo/SeccionIA/LblEstadoIA") as Label)
		lbls_desc.append(t.get_node("VBox/Margin/Cuerpo/SeccionIA/LblDescIA") as Label)

	# Estado inicial: todos en IA
	var inicio_ia_ok: bool = ds.obtener_indice_humano() == -1
	for i in range(3):
		if ds.config_vehiculos[i]["es_humano"] != false or not btns_ia[i].button_pressed or btns_hum[i].button_pressed or opts_ia[i].disabled:
			inicio_ia_ok = false
	_assert_true(inicio_ia_ok, "Estado inicial de las 3 tarjetas es modo IA con OptNivelIA habilitado")

	# Activar Piloto Humano en tarjeta 0 por .pressed.emit()
	btns_hum[0].pressed.emit()
	await _esperar_frames(1)

	var t0_humano_ok: bool = (
		ds.obtener_indice_humano() == 0
		and ds.config_vehiculos[0]["es_humano"] == true
		and ds.config_vehiculos[1]["es_humano"] == false
		and ds.config_vehiculos[2]["es_humano"] == false
		and btns_hum[0].button_pressed and not btns_ia[0].button_pressed
		and not btns_hum[1].button_pressed and btns_ia[1].button_pressed
		and not btns_hum[2].button_pressed and btns_ia[2].button_pressed
		and opts_ia[0].disabled == true
		and opts_ia[1].disabled == false
		and opts_ia[2].disabled == false
		and lbls_estado[0].text.contains("Piloto Humano")
		and lbls_desc[0].text.contains("WASD")
		and lbls_desc[0].text.contains("Flechas")
	)
	_assert_true(t0_humano_ok, "Activar Piloto Humano en tarjeta 0 deshabilita OptNivelIA, actualiza etiquetas y mantiene tarjetas 1-2 en IA")

	# En Piloto Humano, arquetipos y sliders siguen activos y editables
	var card0: Node = vista.contenedor_tarjetas.get_child(0)
	var btn_drift0: Button = card0.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqDrift")
	var box_atr0: VBoxContainer = card0.get_node("VBox/Margin/Cuerpo/Atributos")
	var controles_activos_ok: bool = not btn_drift0.disabled
	btn_drift0.pressed.emit()
	await _esperar_frames(1)
	if not is_equal_approx(float(ds.config_vehiculos[0]["agarre"]), 0.25) or ds.config_vehiculos[0]["es_humano"] != true:
		controles_activos_ok = false
	for s_idx in range(5):
		var slider: HSlider = box_atr0.get_child(s_idx).get_child(1)
		if not slider.editable:
			controles_activos_ok = false
	var slider_vel0: HSlider = box_atr0.get_child(0).get_child(1)
	slider_vel0.value = 0.88
	await _esperar_frames(1)
	if not is_equal_approx(float(ds.config_vehiculos[0]["velocidad_maxima"]), 0.88) or ds.config_vehiculos[0]["arquetipo"] != "Personalizado":
		controles_activos_ok = false
	_assert_true(controles_activos_ok, "En modo Piloto Humano permanecen activos los presets de arquetipo y los 5 sliders fisicos")

	# Exclusividad max-1 al activar Piloto Humano en tarjeta 2 (.button_pressed = true -> toggled)
	btns_hum[2].button_pressed = true
	await _esperar_frames(1)
	var excl_2_ok: bool = (
		ds.obtener_indice_humano() == 2
		and ds.config_vehiculos[0]["es_humano"] == false
		and ds.config_vehiculos[1]["es_humano"] == false
		and ds.config_vehiculos[2]["es_humano"] == true
		and not btns_hum[0].button_pressed and btns_ia[0].button_pressed
		and btns_hum[2].button_pressed and not btns_ia[2].button_pressed
		and opts_ia[0].disabled == false
		and opts_ia[2].disabled == true
		and lbls_desc[0].text == ds.NIVELES_IA[int(ds.config_vehiculos[0]["nivel_ia"]) - 1]["desc"]
	)
	_assert_true(excl_2_ok, "Activar Piloto Humano en tarjeta 2 desactiva automaticamente tarjeta 0 y restaura su selector/descripcion IA")

	# Volver tarjeta 2 a IA por clic en BtnModoIA y probar API pública establecer_modo_humano
	btns_ia[2].pressed.emit()
	await _esperar_frames(1)
	var todo_ia_ok: bool = ds.obtener_indice_humano() == -1 and not opts_ia[2].disabled and btns_ia[2].button_pressed

	# Regresión toggled(false) en BtnModoIA activo: nunca pueden quedar ambos botones en false
	btns_ia[0].button_pressed = false
	await _esperar_frames(1)
	_assert_true(
		btns_ia[0].button_pressed
		and not btns_hum[0].button_pressed
		and ds.config_vehiculos[0]["es_humano"] == false,
		"Regresion toggled(false) en BtnModoIA activo mantiene BtnModoIA=true y BtnModoHumano=false"
	)

	vista.establecer_modo_humano(1, true)
	await _esperar_frames(1)
	var api_hum_ok: bool = (
		ds.obtener_indice_humano() == 1
		and ds.config_vehiculos[1]["es_humano"] == true
		and opts_ia[1].disabled == true
		and btns_hum[1].button_pressed
	)

	# Regresión re-clic real con ratón sobre BtnModoHumano ya activo: sin parpadeo transitorio a IA
	var flip_ia_transitorio := [false]
	var spy_ia := func(_pressed_val: bool): flip_ia_transitorio[0] = true
	btns_ia[1].toggled.connect(spy_ia)
	var centro_hum1 := btns_hum[1].get_global_rect().get_center()
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.pressed = true
	ev_down.position = centro_hum1
	vp.push_input(ev_down)
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.position = centro_hum1
	vp.push_input(ev_up)
	await _esperar_frames(1)
	btns_ia[1].toggled.disconnect(spy_ia)
	_assert_true(
		not flip_ia_transitorio[0]
		and ds.obtener_indice_humano() == 1
		and ds.config_vehiculos[1]["es_humano"] == true
		and btns_hum[1].button_pressed
		and not btns_ia[1].button_pressed
		and opts_ia[1].disabled,
		"Re-clic real sobre BtnModoHumano activo mantiene Piloto Humano sin cambio transitorio a IA"
	)

	btns_hum[1].button_pressed = false
	await _esperar_frames(1)
	var toggled_off_ok: bool = (
		ds.obtener_indice_humano() == -1
		and ds.config_vehiculos[1]["es_humano"] == false
		and not opts_ia[1].disabled
		and btns_ia[1].button_pressed
		and not btns_hum[1].button_pressed
	)
	_assert_true(todo_ia_ok and api_hum_ok and toggled_off_ok, "BtnModoIA, establecer_modo_humano() y toggled(false) alternan el modo limpiamente")

	# Persistencia de es_humano tras guardar y recargar Vista 3
	vista.establecer_modo_humano(1, true)
	vista._guardar_configuraciones()
	vp.queue_free()
	await _esperar_frames(2)

	var vp_re := SubViewport.new()
	vp_re.size = Vector2i(1280, 720)
	root.add_child(vp_re)
	var vista_re := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_re.add_child(vista_re)
	await _esperar_frames(3)

	var opt_re0: OptionButton = vista_re.contenedor_tarjetas.get_child(0).get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var opt_re1: OptionButton = vista_re.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var btn_hum_re1: Button = vista_re.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoHumano")
	_assert_true(
		ds.obtener_indice_humano() == 1
		and ds.config_vehiculos[1]["es_humano"] == true
		and opt_re1.disabled == true
		and btn_hum_re1.button_pressed
		and ds.config_vehiculos[0]["es_humano"] == false
		and opt_re0.disabled == false,
		"Modo Piloto Humano (es_humano) persiste tras guardar y recargar Vista 3"
	)
	vp_re.queue_free()
	await _esperar_frames(2)

	# Saneamiento al cargar cuando >1 vehículo tiene es_humano=true o tipos inválidos ('false' String / null)
	ds.config_vehiculos[0]["es_humano"] = true
	ds.config_vehiculos[1]["es_humano"] = true
	ds.config_vehiculos[2]["es_humano"] = true

	var vp_multi := SubViewport.new()
	vp_multi.size = Vector2i(1280, 720)
	root.add_child(vp_multi)
	var vista_multi := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_multi.add_child(vista_multi)
	await _esperar_frames(3)

	var cant_humanos := 0
	var tipos_bool_ok := true
	for cfg_m: Dictionary in ds.config_vehiculos:
		if not (cfg_m["es_humano"] is bool):
			tipos_bool_ok = false
		if cfg_m["es_humano"] == true:
			cant_humanos += 1
	var opt_m0: OptionButton = vista_multi.contenedor_tarjetas.get_child(0).get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var opt_m1: OptionButton = vista_multi.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var opt_m2: OptionButton = vista_multi.contenedor_tarjetas.get_child(2).get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	_assert_true(
		tipos_bool_ok and cant_humanos == 1 and ds.obtener_indice_humano() == 0
		and opt_m0.disabled and not opt_m1.disabled and not opt_m2.disabled,
		"Vista 3 sanea multiples es_humano=true al cargar imponiendo exclusividad max-1 (gana el primero)"
	)
	vp_multi.queue_free()
	await _esperar_frames(2)

	ds.config_vehiculos[0]["es_humano"] = "false"
	ds.config_vehiculos[1]["es_humano"] = null
	ds.config_vehiculos[2]["es_humano"] = "true"
	var vp_str := SubViewport.new()
	vp_str.size = Vector2i(1280, 720)
	root.add_child(vp_str)
	var vista_str := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_str.add_child(vista_str)
	await _esperar_frames(3)

	_assert_true(
		ds.obtener_indice_humano() == -1
		and ds.config_vehiculos[0]["es_humano"] is bool and ds.config_vehiculos[0]["es_humano"] == false
		and ds.config_vehiculos[1]["es_humano"] is bool and ds.config_vehiculos[1]["es_humano"] == false
		and ds.config_vehiculos[2]["es_humano"] is bool and ds.config_vehiculos[2]["es_humano"] == false,
		"Vista 3 sanea es_humano con Strings ('false'/'true') y null a bool false sin caer en bool(String)"
	)
	vp_str.queue_free()
	await _esperar_frames(2)

	# Regresión: normalización de arreglos cortos (1 y 2 entradas) y sobredimensionados (4 entradas con es_humano en índice 3)
	var solo_uno: Array[Dictionary] = [{"nombre": "SoloUno"}]
	ds.config_vehiculos = solo_uno
	var vp_1 := SubViewport.new()
	vp_1.size = Vector2i(1280, 720)
	root.add_child(vp_1)
	var vista_1 := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_1.add_child(vista_1)
	await _esperar_frames(3)

	var uno_ok: bool = ds.config_vehiculos.size() == 3 and ds.config_vehiculos[0]["nombre"] == "SoloUno"
	for i in range(3):
		var t1: Node = vista_1.contenedor_tarjetas.get_child(i)
		var opt1: OptionButton = t1.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
		var atr1: VBoxContainer = t1.get_node("VBox/Margin/Cuerpo/Atributos")
		if opt1.item_count != 10 or atr1.get_child_count() != 5:
			uno_ok = false
	var btn_hum_1: Button = vista_1.contenedor_tarjetas.get_child(1).get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoHumano")
	btn_hum_1.pressed.emit()
	await _esperar_frames(1)
	uno_ok = uno_ok and ds.obtener_indice_humano() == 1
	_assert_true(uno_ok, "Arreglo de 1 entrada se normaliza a 3 slots y configura las 3 tarjetas completas")
	vp_1.queue_free()
	await _esperar_frames(2)

	var dos_entradas: Array[Dictionary] = [{"nombre": "Uno"}, {"nombre": "Dos"}]
	ds.config_vehiculos = dos_entradas
	var vp_2 := SubViewport.new()
	vp_2.size = Vector2i(1280, 720)
	root.add_child(vp_2)
	var vista_2 := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_2.add_child(vista_2)
	await _esperar_frames(3)

	var dos_ok: bool = ds.config_vehiculos.size() == 3
	for i in range(3):
		var t2: Node = vista_2.contenedor_tarjetas.get_child(i)
		var opt2: OptionButton = t2.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
		var atr2: VBoxContainer = t2.get_node("VBox/Margin/Cuerpo/Atributos")
		if opt2.item_count != 10 or atr2.get_child_count() != 5:
			dos_ok = false
	_assert_true(dos_ok, "Arreglo de 2 entradas se normaliza a 3 slots y configura las 3 tarjetas completas")
	vp_2.queue_free()
	await _esperar_frames(2)

	var cuatro_entradas: Array[Dictionary] = [
		{"nombre": "V0", "es_humano": false},
		{"nombre": "V1", "es_humano": false},
		{"nombre": "V2", "es_humano": false},
		{"nombre": "V3", "es_humano": true},
	]
	ds.config_vehiculos = cuatro_entradas
	var vp_4 := SubViewport.new()
	vp_4.size = Vector2i(1280, 720)
	root.add_child(vp_4)
	var vista_4 := (load(RUTA_CONFIG) as PackedScene).instantiate() as Control
	vp_4.add_child(vista_4)
	await _esperar_frames(3)

	var cuatro_ok: bool = ds.config_vehiculos.size() == 3 and ds.obtener_indice_humano() == -1
	for i in range(3):
		var t4: Node = vista_4.contenedor_tarjetas.get_child(i)
		var opt4: OptionButton = t4.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
		var atr4: VBoxContainer = t4.get_node("VBox/Margin/Cuerpo/Atributos")
		var btn_ia4: Button = t4.get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoIA")
		if opt4.item_count != 10 or atr4.get_child_count() != 5 or opt4.disabled or not btn_ia4.button_pressed:
			cuatro_ok = false
	_assert_true(cuatro_ok, "Arreglo de 4 entradas (es_humano=true en indice 3) se recorta a 3 slots con obtener_indice_humano() == -1")
	vp_4.queue_free()
	await _esperar_frames(2)

	var cuatro_con_uno: Array[Dictionary] = [
		{"nombre": "V0", "es_humano": false},
		{"nombre": "V1", "es_humano": true},
		{"nombre": "V2", "es_humano": false},
		{"nombre": "V3", "es_humano": true},
	]
	ds.config_vehiculos = cuatro_con_uno
	ds.sanitizar_config_vehiculos()
	_assert_true(
		ds.config_vehiculos.size() == 3 and ds.obtener_indice_humano() == 1,
		"Arreglo de 4 entradas con es_humano=true en indice 1 y 3 mantiene max-1 dentro de 0..2"
	)

	ds.config_vehiculos = cfg_backup
