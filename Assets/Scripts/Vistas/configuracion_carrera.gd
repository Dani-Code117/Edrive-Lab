class_name ConfiguracionCarreraUI
extends Control

const ESCENA_CREADOR := "res://Assets/Escenas/Vistas/creador_mapa.tscn"
const ESCENA_CARRERA := "res://Assets/Escenas/Vistas/vista_carrera.tscn"
const RUTA_SPRITE_COCHE := "res://Assets/Sprites/coche_base.png"

const ATRIBUTOS_FISICOS: Array[Dictionary] = [
	{"clave": "velocidad_maxima", "etiqueta": "Velocidad Máxima"},
	{"clave": "aceleracion", "etiqueta": "Aceleración"},
	{"clave": "frenado", "etiqueta": "Frenado"},
	{"clave": "control", "etiqueta": "Control (Giro)"},
	{"clave": "agarre", "etiqueta": "Agarre"},
]

@onready var btn_volver: Button = $Layout/BarraSuperior/Margin/HBox/BtnVolver
@onready var btn_iniciar: Button = $Layout/BarraSuperior/Margin/HBox/BtnIniciar
@onready var lienzo_minimapa: Control = $Layout/Contenido/ScrollArea/CuerpoPrincipal/PanelMinimapa/VBox/Margin/Contenido/MarcoMinimapa/LienzoMinimapa
@onready var lbl_minimapa_vacio: Label = $Layout/Contenido/ScrollArea/CuerpoPrincipal/PanelMinimapa/VBox/Margin/Contenido/MarcoMinimapa/LienzoMinimapa/LblMinimapaVacio
@onready var lbl_stats_pista: Label = $Layout/Contenido/ScrollArea/CuerpoPrincipal/PanelMinimapa/VBox/Margin/Contenido/LblStatsPista
@onready var lbl_aviso: Label = $Layout/Contenido/ScrollArea/CuerpoPrincipal/PanelMinimapa/VBox/Margin/Contenido/LblAviso
@onready var contenedor_tarjetas: HBoxContainer = $Layout/Contenido/ScrollArea/CuerpoPrincipal/Tarjetas

var _controles_tarjetas: Array[Dictionary] = []
var _aplicando_arquetipo: Array[bool] = []
var _actualizando_ui: Array[bool] = []
var _click_humano_en_curso: Array[bool] = []


func _ready() -> void:
	DatosSimulacion.sanitizar_config_vehiculos()
	btn_volver.pressed.connect(_on_volver_pressed)
	btn_iniciar.pressed.connect(_on_iniciar_pressed)
	lienzo_minimapa.draw.connect(_on_minimapa_draw)
	lienzo_minimapa.resized.connect(lienzo_minimapa.queue_redraw)

	var textura_coche := _obtener_textura_coche()
	var tarjetas := contenedor_tarjetas.get_children()
	var cant := mini(tarjetas.size(), DatosSimulacion.config_vehiculos.size())
	_controles_tarjetas.clear()
	_aplicando_arquetipo.resize(cant)
	_actualizando_ui.resize(cant)
	_click_humano_en_curso.resize(cant)
	for i in range(cant):
		_aplicando_arquetipo[i] = false
		_actualizando_ui[i] = false
		_click_humano_en_curso[i] = false
		_configurar_tarjeta(tarjetas[i], i, textura_coche)

	_refrescar_modos_tarjetas()
	actualizar_minimapa()


func actualizar_minimapa() -> void:
	_actualizar_info_pista()
	if lienzo_minimapa != null:
		lienzo_minimapa.queue_redraw()


func _actualizar_info_pista() -> void:
	var cant_celdas := DatosSimulacion.celdas_asfalto.size()
	var cant_cps := DatosSimulacion.ruta_checkpoints.size()
	var tiene_meta := DatosSimulacion.tiene_meta and DatosSimulacion.celdas_asfalto.has(DatosSimulacion.celda_meta)

	if cant_celdas == 0:
		lbl_minimapa_vacio.visible = true
		lbl_stats_pista.text = "Celdas de asfalto: 0\nCheckpoints: 0\nMeta: No definida"
	else:
		lbl_minimapa_vacio.visible = false
		var texto_meta := "Confirmada (%d, %d)" % [DatosSimulacion.celda_meta.x, DatosSimulacion.celda_meta.y] if tiene_meta else "No definida"
		lbl_stats_pista.text = "Celdas de asfalto: %d\nCheckpoints: %d\nMeta: %s" % [cant_celdas, cant_cps, texto_meta]


func obtener_resumen_minimapa() -> Dictionary:
	var geo := _calcular_geometria_minimapa()
	var cant_celdas := DatosSimulacion.celdas_asfalto.size()
	var tiene_meta := DatosSimulacion.tiene_meta and DatosSimulacion.celda_meta != Vector2i(-1, -1) and DatosSimulacion.celdas_asfalto.has(DatosSimulacion.celda_meta)
	return {
		"vacio": cant_celdas == 0,
		"celdas": cant_celdas,
		"checkpoints": DatosSimulacion.ruta_checkpoints.size(),
		"tiene_meta": tiene_meta,
		"rect_pista": geo["rect_pista"],
		"rect_meta": geo["rect_meta"],
	}


func _calcular_geometria_minimapa() -> Dictionary:
	var sz := lienzo_minimapa.size if lienzo_minimapa != null else Vector2.ZERO
	if sz.x <= 0.0 or sz.y <= 0.0:
		return {
			"valido": false,
			"cell_px": 0.0,
			"origin": Vector2.ZERO,
			"grid_size": Vector2.ZERO,
			"rect_pista": Rect2(),
			"rect_meta": Rect2(),
		}

	var margen := 8.0
	var ancho_disp := maxf(sz.x - margen * 2.0, 1.0)
	var alto_disp := maxf(sz.y - margen * 2.0, 1.0)
	var cell_px := minf(
		ancho_disp / float(DatosSimulacion.ANCHO_GRID),
		alto_disp / float(DatosSimulacion.ALTO_GRID)
	)
	var grid_size := Vector2(DatosSimulacion.ANCHO_GRID, DatosSimulacion.ALTO_GRID) * cell_px
	var origin := (sz - grid_size) * 0.5

	var rect_pista := Rect2()
	if not DatosSimulacion.celdas_asfalto.is_empty():
		var min_x := 999999
		var max_x := -999999
		var min_y := 999999
		var max_y := -999999
		for c: Vector2i in DatosSimulacion.celdas_asfalto.keys():
			min_x = mini(min_x, c.x)
			max_x = maxi(max_x, c.x)
			min_y = mini(min_y, c.y)
			max_y = maxi(max_y, c.y)
		rect_pista = Rect2(
			origin + Vector2(min_x, min_y) * cell_px,
			Vector2(max_x - min_x + 1, max_y - min_y + 1) * cell_px
		)

	var rect_meta := Rect2()
	if DatosSimulacion.tiene_meta and DatosSimulacion.celda_meta != Vector2i(-1, -1):
		rect_meta = Rect2(
			origin + Vector2(DatosSimulacion.celda_meta) * cell_px,
			Vector2(cell_px, cell_px)
		)

	return {
		"valido": true,
		"cell_px": cell_px,
		"origin": origin,
		"grid_size": grid_size,
		"rect_pista": rect_pista,
		"rect_meta": rect_meta,
	}


func _on_minimapa_draw() -> void:
	var geo := _calcular_geometria_minimapa()
	if not geo["valido"]:
		return

	var cell_px: float = geo["cell_px"]
	var origin: Vector2 = geo["origin"]
	var grid_size: Vector2 = geo["grid_size"]

	# Fondo del tablero en el minimapa
	var rect_arena := Rect2(origin, grid_size)
	lienzo_minimapa.draw_rect(rect_arena, Color(0.055, 0.075, 0.11, 1.0), true)
	lienzo_minimapa.draw_rect(rect_arena, Color(0.165, 0.212, 0.282, 1.0), false, 1.5)

	if DatosSimulacion.celdas_asfalto.is_empty():
		return

	# Celdas de asfalto
	var col_asfalto := Color(0.22, 0.27, 0.38, 1.0)
	var col_borde := Color(0.95, 0.84, 0.22, 0.85)
	for c: Vector2i in DatosSimulacion.celdas_asfalto.keys():
		var p := origin + Vector2(c) * cell_px
		lienzo_minimapa.draw_rect(Rect2(p, Vector2(cell_px, cell_px)), col_asfalto, true)
		if not DatosSimulacion.celdas_asfalto.has(c + Vector2i(0, -1)):
			lienzo_minimapa.draw_line(p, p + Vector2(cell_px, 0.0), col_borde, 1.5)
		if not DatosSimulacion.celdas_asfalto.has(c + Vector2i(0, 1)):
			lienzo_minimapa.draw_line(p + Vector2(0.0, cell_px), p + Vector2(cell_px, cell_px), col_borde, 1.5)
		if not DatosSimulacion.celdas_asfalto.has(c + Vector2i(-1, 0)):
			lienzo_minimapa.draw_line(p, p + Vector2(0.0, cell_px), col_borde, 1.5)
		if not DatosSimulacion.celdas_asfalto.has(c + Vector2i(1, 0)):
			lienzo_minimapa.draw_line(p + Vector2(cell_px, 0.0), p + Vector2(cell_px, cell_px), col_borde, 1.5)

	# Checkpoints horarios
	var radio_cp := maxf(cell_px * 0.28, 2.0)
	for cp: Vector2i in DatosSimulacion.ruta_checkpoints:
		var centro_cp := origin + (Vector2(cp) + Vector2(0.5, 0.5)) * cell_px
		lienzo_minimapa.draw_circle(centro_cp, radio_cp, Color(0.0, 0.898, 1.0, 0.7))

	# Marcador de salida / meta + flecha de dirección
	if DatosSimulacion.tiene_meta and DatosSimulacion.celda_meta != Vector2i(-1, -1):
		var rect_meta: Rect2 = geo["rect_meta"]
		var sub := rect_meta.size.x * 0.5
		for ix in range(2):
			for iy in range(2):
				var es_blanco := (ix + iy) % 2 == 0
				var col_cuadro := Color(0.95, 0.95, 0.95, 0.95) if es_blanco else Color(0.1, 0.1, 0.12, 0.95)
				var pos_cuadro := rect_meta.position + Vector2(ix * sub, iy * sub)
				lienzo_minimapa.draw_rect(Rect2(pos_cuadro, Vector2(sub, sub)), col_cuadro, true)

		var centro_meta := rect_meta.get_center()
		var dir := Vector2.RIGHT.rotated(DatosSimulacion.rotacion_salida)
		lienzo_minimapa.draw_line(
			centro_meta,
			centro_meta + dir * maxf(cell_px * 1.4, 6.0),
			Color(1.0, 0.85, 0.15, 0.95),
			2.0
		)


func _configurar_tarjeta(tarjeta: PanelContainer, indice: int, textura_coche: Texture2D) -> void:
	var cfg: Dictionary = DatosSimulacion.config_vehiculos[indice]
	var raw_color: Variant = cfg.get("color", Color.WHITE)
	var color_coche: Color = raw_color if raw_color is Color else Color.WHITE
	if not (raw_color is Color):
		DatosSimulacion.config_vehiculos[indice]["color"] = color_coche

	var raw_nombre: Variant = cfg.get("nombre", "")
	var nombre_invalido := raw_nombre == null or not (raw_nombre is String) or str(raw_nombre).strip_edges().is_empty()
	var nombre_coche: String = "Vehículo %d" % (indice + 1) if nombre_invalido else str(raw_nombre)
	if nombre_invalido:
		DatosSimulacion.config_vehiculos[indice]["nombre"] = nombre_coche

	var franja: ColorRect = tarjeta.get_node("VBox/FranjaColor")
	var lbl_nombre: Label = tarjeta.get_node("VBox/Margin/Cuerpo/Header/LblNombre")
	var preview_coche: TextureRect = tarjeta.get_node("VBox/Margin/Cuerpo/VistaPrevia/Centro/SpriteCoche")
	var lbl_arquetipo: Label = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/HeaderArq/LblArquetipo")
	var btns_arquetipo: Dictionary = {
		"Equilibrado": tarjeta.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqEquilibrado"),
		"Velocista": tarjeta.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqVelocista"),
		"Drift": tarjeta.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqDrift"),
		"Técnico": tarjeta.get_node("VBox/Margin/Cuerpo/SeccionArquetipos/GridArquetipos/BtnArqTecnico"),
	}
	var box_atributos: VBoxContainer = tarjeta.get_node("VBox/Margin/Cuerpo/Atributos")
	var btn_modo_ia: Button = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoIA")
	var btn_modo_humano: Button = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/HBoxModo/BtnModoHumano")
	var opt_ia: OptionButton = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var lbl_estado_ia: Label = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/LblEstadoIA")
	var lbl_desc_ia: Label = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/LblDescIA")

	franja.color = color_coche
	lbl_nombre.text = nombre_coche
	lbl_nombre.add_theme_color_override("font_color", color_coche.lightened(0.25))

	preview_coche.texture = textura_coche
	preview_coche.modulate = color_coche

	# Limpiar y crear los 5 sliders físicos (normalizados 0.00 a 1.00)
	for hijo in box_atributos.get_children():
		hijo.queue_free()

	var sliders_tarjeta: Dictionary = {}
	var lbl_valores_tarjeta: Dictionary = {}

	for atr in ATRIBUTOS_FISICOS:
		var clave: String = atr["clave"]
		var etiqueta: String = atr["etiqueta"]
		var raw_val: Variant = cfg.get(clave, 0.5)
		var valor_inicial: float = _sanitizar_normalizado(raw_val, 0.5)
		if not (raw_val is float or raw_val is int) or not is_finite(float(raw_val)) or not is_equal_approx(float(raw_val), valor_inicial):
			DatosSimulacion.config_vehiculos[indice][clave] = valor_inicial

		var fila := VBoxContainer.new()
		fila.add_theme_constant_override("separation", 0)

		var encabezado := HBoxContainer.new()
		var lbl_atr := Label.new()
		lbl_atr.text = etiqueta
		lbl_atr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_atr.add_theme_font_size_override("font_size", 13)

		var lbl_val := Label.new()
		lbl_val.text = "%.2f" % valor_inicial
		lbl_val.add_theme_font_size_override("font_size", 13)
		lbl_val.add_theme_color_override("font_color", color_coche.lightened(0.35))

		encabezado.add_child(lbl_atr)
		encabezado.add_child(lbl_val)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = valor_inicial
		lbl_val.text = "%.2f" % slider.value
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slider.value_changed.connect(func(v: float):
			DatosSimulacion.config_vehiculos[indice][clave] = v
			lbl_val.text = "%.2f" % v
			if not _aplicando_arquetipo[indice]:
				_marcar_arquetipo_personalizado(indice)
		)

		fila.add_child(encabezado)
		fila.add_child(slider)
		box_atributos.add_child(fila)

		sliders_tarjeta[clave] = slider
		lbl_valores_tarjeta[clave] = lbl_val

	# Botones de arquetipo físico (2x2)
	var arquetipo_inicial := DatosSimulacion.sanitizar_arquetipo(
		cfg.get("arquetipo", DatosSimulacion.ARQUETIPO_PERSONALIZADO)
	)
	DatosSimulacion.config_vehiculos[indice]["arquetipo"] = arquetipo_inicial
	lbl_arquetipo.text = arquetipo_inicial

	for nombre_arq: String in btns_arquetipo.keys():
		var btn_arq: Button = btns_arquetipo[nombre_arq]
		btn_arq.set_pressed_no_signal(nombre_arq == arquetipo_inicial)
		btn_arq.pressed.connect(func():
			aplicar_arquetipo(indice, nombre_arq)
		)
		btn_arq.toggled.connect(func(presionado: bool):
			if _aplicando_arquetipo[indice]:
				return
			if presionado:
				aplicar_arquetipo(indice, nombre_arq)
			elif str(DatosSimulacion.config_vehiculos[indice].get("arquetipo", "")) == nombre_arq:
				btn_arq.set_pressed_no_signal(true)
		)

	# 6to atributo: Nivel de Inteligencia Artificial (1 a 10) + Selector IA / Piloto Humano
	opt_ia.clear()
	for info_ia in DatosSimulacion.NIVELES_IA:
		var texto := "Nivel %d — %s" % [info_ia["nivel"], info_ia["titulo"]]
		opt_ia.add_item(texto, info_ia["nivel"])

	var raw_nivel: Variant = cfg.get("nivel_ia", 5)
	var nivel_actual: int = _sanitizar_nivel_ia(raw_nivel, 5)
	if not (raw_nivel is int) or int(raw_nivel) != nivel_actual:
		DatosSimulacion.config_vehiculos[indice]["nivel_ia"] = nivel_actual
	opt_ia.select(nivel_actual - 1)
	_actualizar_estado_ia(nivel_actual, lbl_desc_ia, lbl_estado_ia)

	opt_ia.item_selected.connect(func(idx: int):
		var nivel := opt_ia.get_item_id(idx)
		DatosSimulacion.config_vehiculos[indice]["nivel_ia"] = nivel
		if not DatosSimulacion.sanitizar_es_humano(DatosSimulacion.config_vehiculos[indice].get("es_humano", false)):
			_actualizar_estado_ia(nivel, lbl_desc_ia, lbl_estado_ia)
	)

	btn_modo_ia.pressed.connect(func():
		if DatosSimulacion.sanitizar_es_humano(DatosSimulacion.config_vehiculos[indice].get("es_humano", false)):
			establecer_modo_humano(indice, false)
		elif not btn_modo_ia.button_pressed:
			btn_modo_ia.set_pressed_no_signal(true)
	)
	btn_modo_ia.toggled.connect(func(presionado: bool):
		if _actualizando_ui[indice]:
			return
		if presionado:
			establecer_modo_humano(indice, false)
		elif not DatosSimulacion.sanitizar_es_humano(DatosSimulacion.config_vehiculos[indice].get("es_humano", false)):
			btn_modo_ia.set_pressed_no_signal(true)
	)

	btn_modo_humano.button_down.connect(func():
		_click_humano_en_curso[indice] = true
	)
	btn_modo_humano.button_up.connect(func():
		_click_humano_en_curso[indice] = false
	)
	btn_modo_humano.pressed.connect(func():
		if not DatosSimulacion.sanitizar_es_humano(DatosSimulacion.config_vehiculos[indice].get("es_humano", false)):
			establecer_modo_humano(indice, true)
		elif not btn_modo_humano.button_pressed:
			btn_modo_humano.set_pressed_no_signal(true)
	)
	btn_modo_humano.toggled.connect(func(presionado: bool):
		if _actualizando_ui[indice]:
			return
		if presionado:
			establecer_modo_humano(indice, true)
		elif _click_humano_en_curso[indice] and DatosSimulacion.sanitizar_es_humano(DatosSimulacion.config_vehiculos[indice].get("es_humano", false)):
			btn_modo_humano.set_pressed_no_signal(true)
		else:
			establecer_modo_humano(indice, false)
	)

	_controles_tarjetas.append({
		"sliders": sliders_tarjeta,
		"lbl_valores": lbl_valores_tarjeta,
		"lbl_arquetipo": lbl_arquetipo,
		"btns_arquetipo": btns_arquetipo,
		"btn_modo_ia": btn_modo_ia,
		"btn_modo_humano": btn_modo_humano,
		"opt_ia": opt_ia,
		"lbl_estado_ia": lbl_estado_ia,
		"lbl_desc_ia": lbl_desc_ia,
	})


func aplicar_arquetipo(indice: int, nombre_arquetipo: String) -> void:
	if indice < 0 or indice >= _controles_tarjetas.size() or indice >= DatosSimulacion.config_vehiculos.size():
		return

	var clave_arq := DatosSimulacion.sanitizar_arquetipo(nombre_arquetipo)
	if clave_arq == DatosSimulacion.ARQUETIPO_PERSONALIZADO or not DatosSimulacion.ARQUETIPOS_VEHICULO.has(clave_arq):
		_marcar_arquetipo_personalizado(indice)
		return

	var ctrl: Dictionary = _controles_tarjetas[indice]
	var sliders: Dictionary = ctrl["sliders"]
	var lbl_valores: Dictionary = ctrl["lbl_valores"]
	var lbl_arquetipo: Label = ctrl["lbl_arquetipo"]
	var btns_arquetipo: Dictionary = ctrl["btns_arquetipo"]
	var perfil: Dictionary = DatosSimulacion.ARQUETIPOS_VEHICULO[clave_arq]

	_aplicando_arquetipo[indice] = true
	for atr in ATRIBUTOS_FISICOS:
		var clave: String = atr["clave"]
		var valor := DatosSimulacion.sanitizar_normalizado(perfil.get(clave, 0.5), 0.5)
		DatosSimulacion.config_vehiculos[indice][clave] = valor
		if sliders.has(clave):
			var slider: HSlider = sliders[clave]
			slider.set_value_no_signal(valor)
		if lbl_valores.has(clave):
			var lbl_val: Label = lbl_valores[clave]
			lbl_val.text = "%.2f" % valor

	DatosSimulacion.config_vehiculos[indice]["arquetipo"] = clave_arq
	lbl_arquetipo.text = clave_arq
	for nombre_btn: String in btns_arquetipo.keys():
		var btn: Button = btns_arquetipo[nombre_btn]
		btn.set_pressed_no_signal(nombre_btn == clave_arq)
	_aplicando_arquetipo[indice] = false


func _marcar_arquetipo_personalizado(indice: int) -> void:
	if indice < 0 or indice >= _controles_tarjetas.size() or indice >= DatosSimulacion.config_vehiculos.size():
		return
	var ctrl: Dictionary = _controles_tarjetas[indice]
	var lbl_arquetipo: Label = ctrl["lbl_arquetipo"]
	var btns_arquetipo: Dictionary = ctrl["btns_arquetipo"]

	DatosSimulacion.config_vehiculos[indice]["arquetipo"] = DatosSimulacion.ARQUETIPO_PERSONALIZADO
	lbl_arquetipo.text = DatosSimulacion.ARQUETIPO_PERSONALIZADO
	_aplicando_arquetipo[indice] = true
	for nombre_btn: String in btns_arquetipo.keys():
		var btn: Button = btns_arquetipo[nombre_btn]
		btn.set_pressed_no_signal(false)
	_aplicando_arquetipo[indice] = false


func establecer_modo_humano(indice: int, activar: bool) -> void:
	if indice < 0 or indice >= _controles_tarjetas.size():
		return
	DatosSimulacion.establecer_humano_exclusivo(indice, activar)
	_refrescar_modos_tarjetas()


func _refrescar_modos_tarjetas() -> void:
	for i in range(mini(_controles_tarjetas.size(), DatosSimulacion.config_vehiculos.size())):
		_actualizando_ui[i] = true
		var ctrl: Dictionary = _controles_tarjetas[i]
		var es_hum: bool = DatosSimulacion.sanitizar_es_humano(
			DatosSimulacion.config_vehiculos[i].get("es_humano", false)
		)
		var btn_ia: Button = ctrl["btn_modo_ia"]
		var btn_hum: Button = ctrl["btn_modo_humano"]
		var opt_ia: OptionButton = ctrl["opt_ia"]
		var lbl_estado_ia: Label = ctrl["lbl_estado_ia"]
		var lbl_desc_ia: Label = ctrl["lbl_desc_ia"]

		btn_ia.set_pressed_no_signal(not es_hum)
		btn_hum.set_pressed_no_signal(es_hum)
		opt_ia.disabled = es_hum

		if es_hum:
			_actualizar_estado_humano(lbl_desc_ia, lbl_estado_ia)
		else:
			var nivel := DatosSimulacion.sanitizar_nivel_ia(
				DatosSimulacion.config_vehiculos[i].get("nivel_ia", 5),
				5
			)
			_actualizar_estado_ia(nivel, lbl_desc_ia, lbl_estado_ia)
		_actualizando_ui[i] = false


func _actualizar_estado_humano(lbl_desc_ia: Label, lbl_estado_ia: Label) -> void:
	lbl_estado_ia.text = "Piloto Humano activo"
	lbl_estado_ia.add_theme_color_override("font_color", Color(0.0, 0.898, 1.0, 1.0))
	lbl_desc_ia.text = "Control manual con WASD o Flechas (acelerar, frenar, reversa y giro)."


func _actualizar_estado_ia(nivel: int, lbl_desc_ia: Label, lbl_estado_ia: Label) -> void:
	var idx_nivel := clampi(nivel, 1, DatosSimulacion.NIVELES_IA.size()) - 1
	lbl_desc_ia.text = DatosSimulacion.NIVELES_IA[idx_nivel]["desc"]

	var ruta := CerebroEntrenado.ruta_para_nivel(nivel)
	if ResourceLoader.exists(ruta):
		lbl_estado_ia.text = "Preset entrenado listo (%s)" % ruta.get_file()
		lbl_estado_ia.add_theme_color_override("font_color", Color(0.42, 0.90, 0.58, 1.0))
	else:
		lbl_estado_ia.text = "Sin entrenar (modelo base en memoria)"
		lbl_estado_ia.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35, 1.0))


func _guardar_configuraciones() -> void:
	for i in range(mini(_controles_tarjetas.size(), DatosSimulacion.config_vehiculos.size())):
		var ctrl: Dictionary = _controles_tarjetas[i]
		var sliders: Dictionary = ctrl["sliders"]
		var lbl_valores: Dictionary = ctrl["lbl_valores"]
		for atr in ATRIBUTOS_FISICOS:
			var clave: String = atr["clave"]
			if sliders.has(clave):
				var slider: HSlider = sliders[clave]
				var valor := _sanitizar_normalizado(slider.value, 0.5)
				DatosSimulacion.config_vehiculos[i][clave] = valor
				if lbl_valores.has(clave):
					var lbl_val: Label = lbl_valores[clave]
					lbl_val.text = "%.2f" % valor

		var opt_ia: OptionButton = ctrl["opt_ia"]
		if opt_ia.selected >= 0:
			var nivel := _sanitizar_nivel_ia(opt_ia.get_item_id(opt_ia.selected), 5)
			DatosSimulacion.config_vehiculos[i]["nivel_ia"] = nivel

		var lbl_arquetipo: Label = ctrl["lbl_arquetipo"]
		DatosSimulacion.config_vehiculos[i]["arquetipo"] = DatosSimulacion.sanitizar_arquetipo(lbl_arquetipo.text)

		var btn_hum: Button = ctrl["btn_modo_humano"]
		DatosSimulacion.config_vehiculos[i]["es_humano"] = btn_hum.button_pressed

	DatosSimulacion.sanitizar_config_vehiculos()
	_refrescar_modos_tarjetas()


static func _sanitizar_normalizado(valor: Variant, defecto: float = 0.5) -> float:
	return DatosSimulacion.sanitizar_normalizado(valor, defecto)


static func _sanitizar_nivel_ia(valor: Variant, defecto: int = 5) -> int:
	return DatosSimulacion.sanitizar_nivel_ia(valor, defecto)


func _obtener_textura_coche() -> Texture2D:
	if ResourceLoader.exists(RUTA_SPRITE_COCHE):
		return load(RUTA_SPRITE_COCHE)
	return _generar_textura_coche_base()


func _generar_textura_coche_base() -> ImageTexture:
	# Textura top-down en escala de grises/blanco (64x36) para modular limpiamente por color
	var w := 64
	var h := 36
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Llantas (4 rectángulos oscuros)
	_rellenar_rect(img, 10, 1, 14, 5, Color(0.14, 0.14, 0.16, 1.0))
	_rellenar_rect(img, 10, 30, 14, 5, Color(0.14, 0.14, 0.16, 1.0))
	_rellenar_rect(img, 42, 1, 14, 5, Color(0.14, 0.14, 0.16, 1.0))
	_rellenar_rect(img, 42, 30, 14, 5, Color(0.14, 0.14, 0.16, 1.0))

	# Carrocería principal
	_rellenar_rect(img, 6, 5, 52, 26, Color(0.92, 0.92, 0.92, 1.0))
	_rellenar_rect(img, 56, 8, 5, 20, Color(0.85, 0.85, 0.85, 1.0)) # Trompa delantera
	_rellenar_rect(img, 3, 7, 4, 22, Color(0.55, 0.55, 0.58, 1.0))  # Alerón trasero

	# Cabina / parabrisas
	_rellenar_rect(img, 20, 9, 22, 18, Color(0.22, 0.28, 0.36, 1.0))
	_rellenar_rect(img, 24, 11, 11, 14, Color(0.75, 0.78, 0.82, 1.0)) # Techo

	# Faros delanteros
	_rellenar_rect(img, 58, 8, 3, 4, Color(1.0, 0.96, 0.75, 1.0))
	_rellenar_rect(img, 58, 24, 3, 4, Color(1.0, 0.96, 0.75, 1.0))

	return ImageTexture.create_from_image(img)


func _rellenar_rect(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color) -> void:
	for x in range(x0, x0 + rw):
		for y in range(y0, y0 + rh):
			img.set_pixel(x, y, col)


func _on_volver_pressed() -> void:
	get_tree().change_scene_to_file(ESCENA_CREADOR)


func _on_iniciar_pressed() -> void:
	_guardar_configuraciones()
	if ResourceLoader.exists(ESCENA_CARRERA):
		get_tree().change_scene_to_file(ESCENA_CARRERA)
	else:
		lbl_aviso.text = "Configuración guardada para los 3 vehículos. La Vista 4 (Carrera / Simulación) es el siguiente módulo."
		lbl_aviso.visible = true
