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
