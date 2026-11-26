class_name BotonAnimado
extends Button

## Botón reutilizable con animación suave de escala mediante Tween al pasar el cursor.

@export var escala_hover: Vector2 = Vector2(1.04, 1.04)
@export var escala_presionado: Vector2 = Vector2(0.97, 0.97)
@export var duracion_animacion: float = 0.14

var _tween: Tween
var _cursor_encima: bool = false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_actualizar_pivote)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	call_deferred("_actualizar_pivote")


func _actualizar_pivote() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	_cursor_encima = true
	if disabled:
		return
	_actualizar_pivote()
	_animar_escala(escala_hover)


func _on_mouse_exited() -> void:
	_cursor_encima = false
	_animar_escala(Vector2.ONE)


func _on_button_down() -> void:
	if disabled:
		return
	_actualizar_pivote()
	_animar_escala(escala_presionado)


func _on_button_up() -> void:
	if disabled:
		_animar_escala(Vector2.ONE)
		return
	_animar_escala(escala_hover if _cursor_encima else Vector2.ONE)


func _animar_escala(objetivo: Vector2) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", objetivo, duracion_animacion)
