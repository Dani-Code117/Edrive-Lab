class_name VehiculoAgente
extends CharacterBody2D

## Agente vehículo con 7 sensores RayCast2D, físicas personalizables
## (velocidad máxima, aceleración, frenado, control y agarre) y control de vueltas.

signal chocado(vehiculo: VehiculoAgente, motivo: String)
signal checkpoint_alcanzado(vehiculo: VehiculoAgente, id_checkpoint: int, vuelta: int)

const ANGULOS_SENSORES: Array[float] = [-90.0, -45.0, -15.0, 0.0, 15.0, 45.0, 90.0]
const LONGITUD_RAYO: float = 80.0
const RUTA_SPRITE_COCHE := "res://Assets/Sprites/coche_base.png"

@export var control_manual: bool = false
@export var mostrar_sensores: bool = true
@export var tiempo_max_sin_checkpoint: float = 4.0

var nombre_vehiculo: String = "Vehículo"
var color_vehiculo: Color = Color.WHITE
var nivel_ia: int = 1

# Atributos normalizados (0.0 a 1.0)
var attr_velocidad_maxima: float = 0.7
var attr_aceleracion: float = 0.7
var attr_frenado: float = 0.7
var attr_control: float = 0.7
var attr_agarre: float = 0.7

# Parámetros físicos derivados
var vel_max: float = 260.0
var tasa_aceleracion: float = 320.0
var tasa_frenado: float = 400.0
var vel_rotacion: float = 3.6
var factor_agarre: float = 7.0

# Estado en carrera
var esta_chocado: bool = false
var motivo_choque: String = ""
var velocidad_actual: float = 0.0
var ultimo_checkpoint: int = -1
var total_checkpoints: int = 0
var checkpoints_cruzados: int = 0
var vuelta_actual: int = 1
var tiempo_sin_checkpoint: float = 0.0

var lecturas_sensores: PackedFloat64Array = PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
var ultima_aceleracion_ia: float = 0.0
var ultimo_giro_ia: float = 0.0

## Opcional: instancia de RedNeuronal asignada en Fase 4.
var cerebro: Variant = null

@onready var sprite: Sprite2D = $SpriteCoche
@onready var nodo_sensores: Node2D = $Sensores
@onready var dibujo_sensores: Node2D = $DibujoSensores
var _rayos: Array[RayCast2D] = []


func _ready() -> void:
	_configurar_sprite()
	_configurar_rayos()
	_recalcular_fisicas()
	dibujo_sensores.draw.connect(_on_dibujo_sensores_draw)


func configurar(cfg: Dictionary) -> void:
	nombre_vehiculo = str(cfg.get("nombre", "Vehículo"))
	var raw_color: Variant = cfg.get("color", Color.WHITE)
	color_vehiculo = raw_color if raw_color is Color else Color.WHITE
	nivel_ia = int(roundf(_sanitizar_float(cfg.get("nivel_ia", 1), 1.0, 10.0, 1.0)))

	attr_velocidad_maxima = _sanitizar_float(cfg.get("velocidad_maxima", 0.7), 0.0, 1.0, 0.7)
	attr_aceleracion = _sanitizar_float(cfg.get("aceleracion", 0.7), 0.0, 1.0, 0.7)
	attr_frenado = _sanitizar_float(cfg.get("frenado", 0.7), 0.0, 1.0, 0.7)
	attr_control = _sanitizar_float(cfg.get("control", 0.7), 0.0, 1.0, 0.7)
	attr_agarre = _sanitizar_float(cfg.get("agarre", 0.7), 0.0, 1.0, 0.7)

	_recalcular_fisicas()
	if is_node_ready() and sprite != null:
		sprite.modulate = color_vehiculo


func reiniciar_estado(pos: Vector2, rot: float, cant_checkpoints: int = 0) -> void:
	global_position = pos if pos.is_finite() else Vector2.ZERO
	rotation = rot if is_finite(rot) else 0.0
	velocity = Vector2.ZERO
	velocidad_actual = 0.0
	esta_chocado = false
	motivo_choque = ""
	ultimo_checkpoint = -1
	total_checkpoints = cant_checkpoints
	checkpoints_cruzados = 0
	vuelta_actual = 1
	tiempo_sin_checkpoint = 0.0
	ultima_aceleracion_ia = 0.0
	ultimo_giro_ia = 0.0
	if lecturas_sensores.size() != 7:
		lecturas_sensores.resize(7)
	lecturas_sensores.fill(1.0)
	if sprite != null:
		sprite.modulate = color_vehiculo


func registrar_checkpoint(id_cp: int) -> void:
	if esta_chocado or total_checkpoints <= 0:
		return

	var esperado := (ultimo_checkpoint + 1) % total_checkpoints
	if id_cp == esperado:
		if id_cp == 0 and ultimo_checkpoint != -1:
			vuelta_actual += 1
		ultimo_checkpoint = id_cp
		checkpoints_cruzados += 1
		tiempo_sin_checkpoint = 0.0
		checkpoint_alcanzado.emit(self, id_cp, vuelta_actual)


func _recalcular_fisicas() -> void:
	vel_max = lerpf(65.0, 180.0, attr_velocidad_maxima)
	tasa_aceleracion = lerpf(60.0, 240.0, attr_aceleracion)
	tasa_frenado = lerpf(75.0, 310.0, attr_frenado)
	vel_rotacion = lerpf(2.0, 5.2, attr_control)
	factor_agarre = lerpf(2.0, 12.0, attr_agarre)


func _configurar_sprite() -> void:
	if ResourceLoader.exists(RUTA_SPRITE_COCHE):
		sprite.texture = load(RUTA_SPRITE_COCHE)
	elif sprite.texture == null:
		sprite.texture = _generar_textura_coche()
	sprite.scale = Vector2(8.0 / 24.0, 8.0 / 24.0)
	sprite.modulate = color_vehiculo


func _configurar_rayos() -> void:
	_rayos.clear()
	for hijo in nodo_sensores.get_children():
		if hijo is RayCast2D:
			_rayos.append(hijo)

	if _rayos.is_empty():
		for i in range(ANGULOS_SENSORES.size()):
			var rayo := RayCast2D.new()
			rayo.name = "Ray%d" % i
			rayo.target_position = Vector2.RIGHT.rotated(deg_to_rad(ANGULOS_SENSORES[i])) * LONGITUD_RAYO
			nodo_sensores.add_child(rayo)
			_rayos.append(rayo)

	for rayo in _rayos:
		rayo.enabled = true
		rayo.collision_mask = 1 # Layer 1: Muros_Pasto
		rayo.collide_with_areas = false
		rayo.collide_with_bodies = true


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return

	if not global_position.is_finite():
		global_position = Vector2.ZERO
	if not is_finite(rotation):
		rotation = 0.0
	if not is_finite(velocidad_actual):
		velocidad_actual = 0.0
	if not velocity.is_finite():
		velocity = Vector2.ZERO

	_actualizar_sensores()

	if mostrar_sensores:
		dibujo_sensores.visible = true
		dibujo_sensores.queue_redraw()
	else:
		dibujo_sensores.visible = false

	if esta_chocado:
		return

	if total_checkpoints > 0:
		if not is_finite(tiempo_sin_checkpoint) or tiempo_sin_checkpoint < 0.0:
			tiempo_sin_checkpoint = 0.0
		tiempo_sin_checkpoint += delta
		var max_sin_cp := tiempo_max_sin_checkpoint if (is_finite(tiempo_max_sin_checkpoint) and tiempo_max_sin_checkpoint >= 0.0) else 4.0
		if tiempo_sin_checkpoint >= max_sin_cp:
			_marcar_chocado("Atascado")
			return

	var comandos := _obtener_comandos()
	var acel_cmd: float = comandos.x
	var giro_cmd: float = comandos.y
	ultima_aceleracion_ia = acel_cmd
	ultimo_giro_ia = giro_cmd

	if acel_cmd > 0.05:
		velocidad_actual = move_toward(velocidad_actual, acel_cmd * vel_max, tasa_aceleracion * delta)
	elif acel_cmd < -0.05:
		# Frenado activo / reversa suave en modo manual
		velocidad_actual = move_toward(velocidad_actual, acel_cmd * vel_max * 0.4, tasa_frenado * delta)
	else:
		velocidad_actual = move_toward(velocidad_actual, 0.0, tasa_frenado * delta)

	rotation += giro_cmd * vel_rotacion * delta

	var vel_objetivo := transform.x * velocidad_actual
	velocity = velocity.lerp(vel_objetivo, clampf(factor_agarre * delta, 0.0, 1.0))

	move_and_slide()
	if get_slide_collision_count() > 0:
		_marcar_chocado("Chocado")


func _actualizar_sensores() -> void:
	for i in range(mini(_rayos.size(), 7)):
		var rayo := _rayos[i]
		rayo.force_raycast_update()
		if rayo.is_colliding():
			var dist := global_position.distance_to(rayo.get_collision_point())
			lecturas_sensores[i] = _sanitizar_float(dist / LONGITUD_RAYO, 0.0, 1.0, 1.0)
		else:
			lecturas_sensores[i] = 1.0


func _obtener_comandos() -> Vector2:
	if control_manual:
		var acel := Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
		if Input.is_key_pressed(KEY_W):
			acel = 1.0
		elif Input.is_key_pressed(KEY_S):
			acel = -1.0

		var giro := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
		if Input.is_key_pressed(KEY_D):
			giro = 1.0
		elif Input.is_key_pressed(KEY_A):
			giro = -1.0
		return Vector2(_sanitizar_float(acel, -1.0, 1.0, 0.0), _sanitizar_float(giro, -1.0, 1.0, 0.0))

	if cerebro != null and cerebro.has_method("evaluar"):
		var salida: Variant = cerebro.evaluar(lecturas_sensores)
		if (salida is PackedFloat64Array or salida is PackedFloat32Array or salida is Array) and salida.size() >= 2:
			return Vector2(
				_sanitizar_float(salida[0], 0.0, 1.0, 0.0),
				_sanitizar_float(salida[1], -1.0, 1.0, 0.0)
			)

	return Vector2.ZERO


func _sanitizar_float(valor: Variant, min_val: float, max_val: float, defecto: float) -> float:
	var num := defecto
	if valor is float or valor is int:
		num = float(valor)
	elif valor is String and valor.is_valid_float():
		num = float(valor)
	else:
		return clampf(defecto, min_val, max_val)

	if not is_finite(num):
		return clampf(defecto, min_val, max_val)
	return clampf(num, min_val, max_val)


func _marcar_chocado(motivo: String) -> void:
	if esta_chocado:
		return
	esta_chocado = true
	motivo_choque = motivo
	velocity = Vector2.ZERO
	velocidad_actual = 0.0
	if sprite != null:
		sprite.modulate = color_vehiculo.darkened(0.55)
	chocado.emit(self, motivo)


func _on_dibujo_sensores_draw() -> void:
	if not mostrar_sensores or esta_chocado:
		return
	for i in range(mini(_rayos.size(), 7)):
		var norm := _sanitizar_float(lecturas_sensores[i], 0.0, 1.0, 1.0)
		var dir := Vector2.RIGHT.rotated(deg_to_rad(ANGULOS_SENSORES[i]))
		var fin := dir * (norm * LONGITUD_RAYO)
		var col := Color(1.0 - norm, norm, 0.2, 0.75)
		dibujo_sensores.draw_line(Vector2.ZERO, fin, col, 1.5)
		if norm < 0.99:
			dibujo_sensores.draw_circle(fin, 2.5, col)


func _generar_textura_coche() -> ImageTexture:
	var w := 24
	var h := 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Llantas
	_pintar_rect(img, 3, 0, 5, 2, Color(0.12, 0.12, 0.14, 1.0))
	_pintar_rect(img, 3, 12, 5, 2, Color(0.12, 0.12, 0.14, 1.0))
	_pintar_rect(img, 16, 0, 5, 2, Color(0.12, 0.12, 0.14, 1.0))
	_pintar_rect(img, 16, 12, 5, 2, Color(0.12, 0.12, 0.14, 1.0))

	# Carrocería
	_pintar_rect(img, 2, 2, 20, 10, Color(0.92, 0.92, 0.92, 1.0))
	_pintar_rect(img, 22, 3, 2, 8, Color(0.84, 0.84, 0.84, 1.0))
	_pintar_rect(img, 7, 4, 8, 6, Color(0.20, 0.26, 0.34, 1.0)) # Cabina

	return ImageTexture.create_from_image(img)


func _pintar_rect(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color) -> void:
	for x in range(x0, x0 + rw):
		for y in range(y0, y0 + rh):
			img.set_pixel(x, y, col)
