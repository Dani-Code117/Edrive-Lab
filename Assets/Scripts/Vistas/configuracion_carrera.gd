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
@onready var lbl_aviso: Label = $Layout/Contenido/VBox/LblAviso
@onready var contenedor_tarjetas: HBoxContainer = $Layout/Contenido/VBox/Tarjetas


func _ready() -> void:
	btn_volver.pressed.connect(_on_volver_pressed)
	btn_iniciar.pressed.connect(_on_iniciar_pressed)

	var textura_coche := _obtener_textura_coche()
	var tarjetas := contenedor_tarjetas.get_children()

	for i in range(mini(tarjetas.size(), DatosSimulacion.config_vehiculos.size())):
		_configurar_tarjeta(tarjetas[i], i, textura_coche)


func _configurar_tarjeta(tarjeta: PanelContainer, indice: int, textura_coche: Texture2D) -> void:
	var cfg: Dictionary = DatosSimulacion.config_vehiculos[indice]
	var color_coche: Color = cfg["color"]

	var franja: ColorRect = tarjeta.get_node("VBox/FranjaColor")
	var lbl_nombre: Label = tarjeta.get_node("VBox/Margin/Cuerpo/Header/LblNombre")
	var preview_coche: TextureRect = tarjeta.get_node("VBox/Margin/Cuerpo/VistaPrevia/Centro/SpriteCoche")
	var box_atributos: VBoxContainer = tarjeta.get_node("VBox/Margin/Cuerpo/Atributos")
	var opt_ia: OptionButton = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/OptNivelIA")
	var lbl_desc_ia: Label = tarjeta.get_node("VBox/Margin/Cuerpo/SeccionIA/LblDescIA")

	franja.color = color_coche
	lbl_nombre.text = cfg["nombre"]
	lbl_nombre.add_theme_color_override("font_color", color_coche.lightened(0.25))

	preview_coche.texture = textura_coche
	preview_coche.modulate = color_coche

	# Limpiar y crear los 5 sliders físicos
	for hijo in box_atributos.get_children():
		hijo.queue_free()

	for atr in ATRIBUTOS_FISICOS:
		var clave: String = atr["clave"]
		var etiqueta: String = atr["etiqueta"]
		var valor_inicial: float = float(cfg.get(clave, 0.5))

		var fila := VBoxContainer.new()
		fila.add_theme_constant_override("separation", 4)

		var encabezado := HBoxContainer.new()
		var lbl_atr := Label.new()
		lbl_atr.text = etiqueta
		lbl_atr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_atr.add_theme_font_size_override("font_size", 13)

		var lbl_val := Label.new()
		lbl_val.text = "%d%%" % roundi(valor_inicial * 100.0)
		lbl_val.add_theme_font_size_override("font_size", 13)
		lbl_val.add_theme_color_override("font_color", color_coche.lightened(0.35))

		encabezado.add_child(lbl_atr)
		encabezado.add_child(lbl_val)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = valor_inicial
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slider.value_changed.connect(func(v: float):
			DatosSimulacion.config_vehiculos[indice][clave] = v
			lbl_val.text = "%d%%" % roundi(v * 100.0)
		)

		fila.add_child(encabezado)
		fila.add_child(slider)
		box_atributos.add_child(fila)

	# 6to atributo: Nivel de Inteligencia Artificial (1 a 10)
	opt_ia.clear()
	for info_ia in DatosSimulacion.NIVELES_IA:
		var texto := "Nivel %d — %s" % [info_ia["nivel"], info_ia["titulo"]]
		opt_ia.add_item(texto, info_ia["nivel"])

	var nivel_actual: int = clampi(int(cfg.get("nivel_ia", 5)), 1, 10)
	opt_ia.select(nivel_actual - 1)
	lbl_desc_ia.text = DatosSimulacion.NIVELES_IA[nivel_actual - 1]["desc"]

	opt_ia.item_selected.connect(func(idx: int):
		var nivel := opt_ia.get_item_id(idx)
		DatosSimulacion.config_vehiculos[indice]["nivel_ia"] = nivel
		lbl_desc_ia.text = DatosSimulacion.NIVELES_IA[nivel - 1]["desc"]
	)


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
	if ResourceLoader.exists(ESCENA_CARRERA):
		get_tree().change_scene_to_file(ESCENA_CARRERA)
	else:
		lbl_aviso.text = "Configuración guardada para los 3 vehículos. La Vista 4 (Carrera / Simulación) es el siguiente módulo."
		lbl_aviso.visible = true
