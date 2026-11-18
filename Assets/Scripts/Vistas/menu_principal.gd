extends Control

const ESCENA_SIGUIENTE := "res://Assets/Escenas/Vistas/creador_mapa.tscn"

@onready var btn_iniciar: Button = $CenterContainer/VBoxContainer/Botones/BtnIniciar
@onready var btn_salir: Button = $CenterContainer/VBoxContainer/Botones/BtnSalir


func _ready() -> void:
	btn_iniciar.pressed.connect(_on_btn_iniciar_pressed)
	btn_salir.pressed.connect(_on_btn_salir_pressed)
	btn_iniciar.grab_focus()


func _on_btn_iniciar_pressed() -> void:
	if ResourceLoader.exists(ESCENA_SIGUIENTE):
		get_tree().change_scene_to_file(ESCENA_SIGUIENTE)
	else:
		print("Edrive-Lab: La escena '%s' aún no está implementada." % ESCENA_SIGUIENTE)


func _on_btn_salir_pressed() -> void:
	get_tree().quit()
