extends Control

const ESCENA_MENU := "res://escenas/menu_principal.tscn"
const ESCENA_CONFIGURACION := "res://Assets/Escenas/Vistas/03_configuracion_carrera.tscn"

@onready var btn_pincel: Button = $Layout/BarraHerramientas/Margin/HBox/BtnPincel
@onready var btn_borrador: Button = $Layout/BarraHerramientas/Margin/HBox/BtnBorrador
@onready var btn_meta: Button = $Layout/BarraHerramientas/Margin/HBox/BtnMeta
@onready var btn_limpiar: Button = $Layout/BarraHerramientas/Margin/HBox/BtnLimpiar
@onready var lbl_estado: Label = $Layout/BarraHerramientas/Margin/HBox/LblEstado
@onready var btn_volver: Button = $Layout/BarraHerramientas/Margin/HBox/BtnVolver
@onready var btn_confirmar: Button = $Layout/BarraHerramientas/Margin/HBox/BtnConfirmar
@onready var area_lienzo: Control = $Layout/AreaLienzo
@onready var editor_pista: Node2D = $Layout/AreaLienzo/EditorPista


func _ready() -> void:
	var grupo := ButtonGroup.new()
	btn_pincel.button_group = grupo
	btn_borrador.button_group = grupo
	btn_meta.button_group = grupo

	btn_pincel.pressed.connect(func(): editor_pista.establecer_herramienta(editor_pista.Herramienta.PINCEL))
	btn_borrador.pressed.connect(func(): editor_pista.establecer_herramienta(editor_pista.Herramienta.BORRADOR))
	btn_meta.pressed.connect(func(): editor_pista.establecer_herramienta(editor_pista.Herramienta.META))
	btn_limpiar.pressed.connect(_on_limpiar_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)
	btn_confirmar.pressed.connect(_on_confirmar_pressed)

	area_lienzo.gui_input.connect(editor_pista.procesar_input_lienzo)
	editor_pista.pista_actualizada.connect(_on_pista_actualizada)

	var validacion: Dictionary = editor_pista.obtener_validacion()
	_on_pista_actualizada(validacion["valido"], validacion["mensaje"])


func _on_pista_actualizada(es_valida: bool, mensaje: String) -> void:
	btn_confirmar.disabled = not es_valida
	lbl_estado.text = mensaje
	lbl_estado.modulate = Color(0.45, 0.95, 0.55) if es_valida else Color(0.95, 0.78, 0.4)


func _on_limpiar_pressed() -> void:
	editor_pista.limpiar_todo()


func _on_volver_pressed() -> void:
	get_tree().change_scene_to_file(ESCENA_MENU)


func _on_confirmar_pressed() -> void:
	var validacion: Dictionary = editor_pista.obtener_validacion()
	if not validacion.get("valido", false):
		return

	DatosSimulacion.guardar_pista(
		editor_pista.celdas_asfalto,
		editor_pista.celda_meta,
		validacion["checkpoints"],
		validacion["rotacion_salida"]
	)

	if ResourceLoader.exists(ESCENA_CONFIGURACION):
		get_tree().change_scene_to_file(ESCENA_CONFIGURACION)
	else:
		lbl_estado.text = "Pista guardada en DatosSimulacion (%d checkpoints). Vista 3 pendiente." % validacion["checkpoints"].size()
		lbl_estado.modulate = Color(0.45, 0.85, 1.0)
