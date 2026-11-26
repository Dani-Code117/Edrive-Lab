extends Control

const ESCENA_CREADOR_MAPA := "res://Assets/Escenas/Vistas/creador_mapa.tscn"

@onready var btn_iniciar: Button = $MarginContainer/CenterContainer/PanelCard/CardMargin/VBoxPrincipal/Botones/BtnIniciar
@onready var btn_salir: Button = $MarginContainer/CenterContainer/PanelCard/CardMargin/VBoxPrincipal/Botones/BtnSalir


func _ready() -> void:
	btn_iniciar.pressed.connect(_on_btn_iniciar_pressed)
	btn_salir.pressed.connect(_on_btn_salir_pressed)
	btn_iniciar.grab_focus()


func _on_btn_iniciar_pressed() -> void:
	if ResourceLoader.exists(ESCENA_CREADOR_MAPA):
		get_tree().change_scene_to_file(ESCENA_CREADOR_MAPA)
	else:
		print("Edrive-Lab: La escena '%s' aún no está implementada." % ESCENA_CREADOR_MAPA)


func _on_btn_salir_pressed() -> void:
	get_tree().quit()
