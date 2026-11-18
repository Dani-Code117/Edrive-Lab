extends Control

const ESCENA_MENU := "res://Assets/Escenas/Vistas/menu_principal.tscn"
const ESCENA_CONFIGURACION := "res://Assets/Escenas/Vistas/configuracion_carrera.tscn"

@onready var lbl_estado: Label = $Layout/BarraSuperior/Margin/HBox/LblEstado
@onready var btn_volver: Button = $Layout/BarraSuperior/Margin/HBox/BtnVolver
@onready var btn_editar: Button = $Layout/BarraSuperior/Margin/HBox/BtnEditar
@onready var btn_confirmar: Button = $Layout/BarraSuperior/Margin/HBox/BtnConfirmar

@onready var panel_lateral: PanelContainer = $Layout/Cuerpo/PanelLateral

@onready var btn_pincel: Button = $Layout/Cuerpo/PanelLateral/Margin/VBox/BtnPincel
@onready var btn_borrador: Button = $Layout/Cuerpo/PanelLateral/Margin/VBox/BtnBorrador
@onready var btn_meta: Button = $Layout/Cuerpo/PanelLateral/Margin/VBox/BtnMeta
@onready var opt_grosor: OptionButton = $Layout/Cuerpo/PanelLateral/Margin/VBox/OptGrosor
@onready var btn_limpiar: Button = $Layout/Cuerpo/PanelLateral/Margin/VBox/BtnLimpiar

@onready var area_lienzo: Control = $Layout/Cuerpo/AreaLienzo
@onready var editor_pista: Node2D = $Layout/Cuerpo/AreaLienzo/EditorPista


var _en_vista_previa: bool = false


func _ready() -> void:
	var grupo := ButtonGroup.new()
	btn_pincel.button_group = grupo
	btn_borrador.button_group = grupo
	btn_meta.button_group = grupo

	_configurar_selector_grosor()

	btn_pincel.pressed.connect(func(): editor_pista.establecer_herramienta(editor_pista.Herramienta.PINCEL))
	btn_borrador.pressed.connect(func(): editor_pista.establecer_herramienta(editor_pista.Herramienta.BORRADOR))
	btn_meta.pressed.connect(func(): editor_pista.establecer_herramienta(editor_pista.Herramienta.META))
	opt_grosor.item_selected.connect(_on_grosor_seleccionado)
	btn_limpiar.pressed.connect(_on_limpiar_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)
	btn_editar.pressed.connect(_on_editar_pressed)
	btn_confirmar.pressed.connect(_on_confirmar_pressed)

	area_lienzo.gui_input.connect(editor_pista.procesar_input_lienzo)
	area_lienzo.resized.connect(_on_area_lienzo_resized)
	editor_pista.pista_actualizada.connect(_on_pista_actualizada)

	_on_area_lienzo_resized()
	var validacion: Dictionary = editor_pista.obtener_validacion()
	_on_pista_actualizada(validacion["valido"], validacion["mensaje"])


func _on_area_lienzo_resized() -> void:
	editor_pista.ajustar_a_contenedor(area_lienzo.size)


func _configurar_selector_grosor() -> void:
	opt_grosor.clear()
	opt_grosor.add_item("1x1 (Fino)", 1)
	opt_grosor.add_item("2x2", 2)
	opt_grosor.add_item("3x3 (Estándar)", 3)
	opt_grosor.add_item("4x4", 4)
	opt_grosor.add_item("5x5 (Ancho)", 5)
	opt_grosor.select(2) # 3x3 por defecto


func _on_grosor_seleccionado(index: int) -> void:
	var grosor := opt_grosor.get_item_id(index)
	editor_pista.establecer_grosor(grosor)


func _on_pista_actualizada(es_valida: bool, mensaje: String) -> void:
	btn_confirmar.disabled = not es_valida
	lbl_estado.text = mensaje
	lbl_estado.modulate = Color(0.45, 0.95, 0.55) if es_valida else Color(0.95, 0.78, 0.4)


func _on_limpiar_pressed() -> void:
	editor_pista.limpiar_todo()


func _on_volver_pressed() -> void:
	get_tree().change_scene_to_file(ESCENA_MENU)


func _on_editar_pressed() -> void:
	_en_vista_previa = false
	btn_editar.visible = false
	panel_lateral.visible = true
	btn_confirmar.text = "Confirmar Pista"
	editor_pista.volver_a_edicion()
	var validacion: Dictionary = editor_pista.obtener_validacion()
	_on_pista_actualizada(validacion["valido"], validacion["mensaje"])


func _on_confirmar_pressed() -> void:
	var validacion: Dictionary = editor_pista.obtener_validacion()
	if not validacion.get("valido", false):
		return

	if not _en_vista_previa:
		var eje: Array[Vector2i] = validacion.get("eje_central", [] as Array[Vector2i])
		var radios: Array[float] = validacion.get("radios_eje", [] as Array[float])
		var ancho := maxf(float(editor_pista.grosor_pincel * DatosSimulacion.TAMANIO_CELDA), 64.0)
		DatosSimulacion.guardar_pista(
			editor_pista.celdas_asfalto,
			editor_pista.celda_meta,
			validacion["checkpoints"],
			validacion["rotacion_salida"],
			eje,
			radios,
			ancho
		)
		_en_vista_previa = true
		panel_lateral.visible = false
		btn_editar.visible = true
		btn_confirmar.text = "Continuar →"
		editor_pista.mostrar_vista_previa_tilemap()
		lbl_estado.text = "¡Pista suavizada lista! (%d checkpoints)" % validacion["checkpoints"].size()
		lbl_estado.modulate = Color(0.45, 0.95, 0.55)
		return

	if ResourceLoader.exists(ESCENA_CONFIGURACION):
		get_tree().change_scene_to_file(ESCENA_CONFIGURACION)
	else:
		lbl_estado.text = "Pista guardada (%d checkpoints). Vista 3 (Configuración) pendiente." % validacion["checkpoints"].size()
		lbl_estado.modulate = Color(0.45, 0.85, 1.0)
