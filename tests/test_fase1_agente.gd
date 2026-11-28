extends SceneTree

## Pruebas automatizadas Fase 1: VehiculoAgente, sensores RayCast2D,
## físicas normalizadas, colisión con muros, anti-atasco (4.0s script / 8.0s escena),
## checkpoints secuenciales, sprites/capas, modo piloto humano (R3) y estela telemétrica (R4).

const RUTA_VEHICULO := "res://Assets/Escenas/Componentes/vehiculo_agente.tscn"
const RUTA_CHECKPOINT := "res://Assets/Escenas/Componentes/checkpoint.tscn"
const RUTA_SPRITE_COCHE := "res://Assets/Sprites/coche_base.png"
const RUTA_SPRITE_BANDERA := "res://Assets/Sprites/bandera_meta.png"


class MockCerebro:
	var acel: float = 0.0
	var giro: float = 0.0

	func _init(p_acel: float = 0.0, p_giro: float = 0.0) -> void:
		acel = p_acel
		giro = p_giro

	func evaluar(_sensores: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([acel, giro])


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


func _crear_muro(pos: Vector2, size: Vector2) -> StaticBody2D:
	var muro := StaticBody2D.new()
	muro.collision_layer = 1
	muro.collision_mask = 0
	muro.position = pos

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	muro.add_child(col)
	return muro


func _esperar_fisicas(frames: int) -> void:
	for _i in range(frames):
		await physics_frame


func _run_all() -> void:
	await physics_frame

	await _test_a_capas_escenas_y_sprites()
	await _test_b_lectura_normalizada_sensores()
	await _test_c_respuesta_fisica_modificadores()
	await _test_d_deteccion_choque_muro()
	await _test_e_temporizador_anti_atascos()
	await _test_f_checkpoints_y_vueltas_secuenciales()
	await _test_g_vehiculos_no_colisionan_entre_si()
	await _test_h_resistencia_nan_y_no_finitos()
	await _test_i_modo_piloto_humano()
	await _test_j_estela_telemetrica()

	_liberar_teclas_prueba()
	print("=== Resumen Fase 1: %d verificaciones, %d fallos ===" % [_total_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _simular_tecla(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _liberar_teclas_prueba() -> void:
	for kc: Key in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		_simular_tecla(kc, false)


func _test_a_capas_escenas_y_sprites() -> void:
	print("--- Test (a): Capas, escenas, hitbox, rayos y sprites ---")
	_assert_true(
		ProjectSettings.get_setting("layer_names/2d_physics/layer_1") == "Muros_Pasto",
		"Layer 1 debe llamarse Muros_Pasto"
	)
	_assert_true(
		ProjectSettings.get_setting("layer_names/2d_physics/layer_2") == "Vehiculos",
		"Layer 2 debe llamarse Vehiculos"
	)
	_assert_true(
		ProjectSettings.get_setting("layer_names/2d_physics/layer_3") == "Checkpoints",
		"Layer 3 debe llamarse Checkpoints"
	)

	var datos := root.get_node_or_null("DatosSimulacion")
	_assert_true(datos != null, "Autoload DatosSimulacion debe estar activo")
	if datos != null:
		_assert_true(datos.TAMANIO_CELDA == 16, "DatosSimulacion.TAMANIO_CELDA == 16")
		_assert_true(datos.ANCHO_GRID == 45, "DatosSimulacion.ANCHO_GRID == 45")
		_assert_true(datos.ALTO_GRID == 27, "DatosSimulacion.ALTO_GRID == 27")
		_assert_true(is_equal_approx(datos.ancho_pista, 48.0), "DatosSimulacion.ancho_pista == 48.0")
		var dummy_celdas: Dictionary = {Vector2i(1, 1): true}
		var dummy_cps: Array[Vector2i] = [Vector2i(1, 1)]
		datos.guardar_pista(dummy_celdas, Vector2i(1, 1), dummy_cps, 0.0)
		_assert_true(
			is_equal_approx(datos.ancho_pista, 48.0),
			"DatosSimulacion.guardar_pista() mantiene default nuevo_ancho == 48.0"
		)
		datos.limpiar_pista()

	_assert_true(ResourceLoader.exists(RUTA_SPRITE_COCHE), "Existe coche_base.png")
	_assert_true(ResourceLoader.exists(RUTA_SPRITE_BANDERA), "Existe bandera_meta.png")
	var tex_coche := load(RUTA_SPRITE_COCHE) as Texture2D
	var tex_bandera := load(RUTA_SPRITE_BANDERA) as Texture2D
	_assert_true(tex_coche != null and tex_coche.get_size() == Vector2(24, 14), "coche_base.png es 24x14 px")
	_assert_true(tex_bandera != null and tex_bandera.get_size() == Vector2(32, 32), "bandera_meta.png es 32x32 px")

	var mundo := Node2D.new()
	root.add_child(mundo)

	var car_script := VehiculoAgente.new()
	_assert_true(
		is_equal_approx(car_script.longitud_rayo, VehiculoAgente.LONGITUD_RAYO)
		and is_equal_approx(car_script.tiempo_max_sin_checkpoint, 4.0),
		"Defaults de script VehiculoAgente.new(): longitud_rayo=%.0f, tiempo_max_sin_checkpoint=4.0" % VehiculoAgente.LONGITUD_RAYO
	)
	car_script.free()

	var escena_car := load(RUTA_VEHICULO) as PackedScene
	var car := escena_car.instantiate() as VehiculoAgente
	mundo.add_child(car)
	await _esperar_fisicas(1)

	_assert_true(car.collision_layer == 2, "VehiculoAgente collision_layer == 2")
	_assert_true(car.collision_mask == 1, "VehiculoAgente collision_mask == 1")
	_assert_true(is_equal_approx(car.longitud_rayo, 300.0), "Escena vehiculo_agente.tscn longitud_rayo == 300.0")
	_assert_true(is_equal_approx(car.tiempo_max_sin_checkpoint, 8.0), "Escena vehiculo_agente.tscn tiempo_max_sin_checkpoint == 8.0")
	_assert_true(
		car.sprite.texture != null and car.sprite.texture.get_size() == Vector2(24, 14),
		"SpriteCoche carga textura 24x14"
	)
	_assert_true(
		car.sprite.scale.is_equal_approx(Vector2(8.0 / 24.0, 8.0 / 24.0)),
		"SpriteCoche escala a 8x4.67 px (8/24)"
	)

	var hitbox := car.get_node_or_null("Hitbox") as CollisionPolygon2D
	var hitbox_ok := hitbox != null and hitbox.polygon.size() >= 3
	if hitbox_ok:
		for v in hitbox.polygon:
			if v.x < -4.001 or v.x > 4.001 or v.y < -2.341 or v.y > 2.341:
				hitbox_ok = false
				break
	_assert_true(hitbox_ok, "Hitbox dentro de limites [-4, 4] x [-2.34, 2.34]")

	_assert_true(car._rayos.size() == 14, "VehiculoAgente tiene exactamente 14 RayCast2D")
	var angulos_esperados: Array[float] = [-90.0, -60.0, -40.0, -25.0, -12.0, 0.0, 12.0, 25.0, 40.0, 60.0, 90.0, -135.0, 180.0, 135.0]
	var long_esperada := car.longitud_rayo
	var rayos_ok := car._rayos.size() == 14
	if rayos_ok:
		for i in range(14):
			var rayo := car._rayos[i]
			var diff_ang := absf(angle_difference(rayo.target_position.angle(), deg_to_rad(angulos_esperados[i])))
			var diff_len := absf(rayo.target_position.length() - long_esperada)
			if not rayo.enabled or rayo.collision_mask != 1 or rayo.collide_with_areas or not rayo.collide_with_bodies or diff_ang >= 0.01 or diff_len >= 0.1:
				rayos_ok = false
				break
	_assert_true(rayos_ok, "14 RayCast2D (11 frontales + 3 traseros, %.0fpx, mask=1, bodies=true, areas=false)" % long_esperada)

	var escena_cp := load(RUTA_CHECKPOINT) as PackedScene
	var cp := escena_cp.instantiate() as CheckpointArea
	mundo.add_child(cp)
	await _esperar_fisicas(1)

	var cp_col := cp.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var cp_shape := cp_col.shape as CircleShape2D if cp_col != null else null
	_assert_true(not cp.visible, "CheckpointArea es invisible (visible == false)")
	_assert_true(cp.collision_layer == 4, "CheckpointArea collision_layer == 4")
	_assert_true(cp.collision_mask == 2, "CheckpointArea collision_mask == 2")
	_assert_true(cp.monitoring and not cp.monitorable, "CheckpointArea monitoring=true, monitorable=false")
	_assert_true(cp_shape != null and is_equal_approx(cp_shape.radius, 26.0), "CheckpointArea CircleShape2D radius == 26.0")

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_b_lectura_normalizada_sensores() -> void:
	print("--- Test (b): Lectura normalizada de sensores (0.0..1.0) ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	var muro := _crear_muro(Vector2(40, 0), Vector2(20, 200)) # Cara izquierda en x = 30
	mundo.add_child(muro)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	car.cerebro = MockCerebro.new(0.0, 0.0)
	await _esperar_fisicas(2)

	var dist_rayo := car.longitud_rayo
	var esperado_30px := 30.0 / dist_rayo
	_assert_true(
		absf(car.lecturas_sensores[5] - esperado_30px) <= 0.02,
		"Sensor frontal detecta muro a 30px -> ~%.3f (obtenido: %.3f)" % [esperado_30px, car.lecturas_sensores[5]]
	)
	_assert_true(
		is_equal_approx(car.lecturas_sensores[0], 1.0) and is_equal_approx(car.lecturas_sensores[10], 1.0),
		"Sensores laterales despejados (-90 y +90) retornan 1.0"
	)

	muro.position = Vector2(15, 0) # Cara izquierda en x = 5
	await _esperar_fisicas(2)
	_assert_true(
		car.lecturas_sensores[5] >= 0.0 and car.lecturas_sensores[5] < 0.10,
		"Sensor frontal cercano (5px) retorna valor proximo a 0.0 (obtenido: %.3f)" % car.lecturas_sensores[5]
	)

	muro.position = Vector2(dist_rayo + 50.0, 0) # Fuera de rango (dist_rayo + 40px > dist_rayo)
	await _esperar_fisicas(2)
	_assert_true(
		is_equal_approx(car.lecturas_sensores[5], 1.0),
		"Sensor frontal sin obstaculo en rango retorna 1.0"
	)

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_c_respuesta_fisica_modificadores() -> void:
	print("--- Test (c): Respuesta fisica a Velocidad, Control y Agarre ---")
	var escena_car := load(RUTA_VEHICULO) as PackedScene

	# 1. Velocidad maxima
	var mundo_vel := Node2D.new()
	root.add_child(mundo_vel)
	var car_fast := escena_car.instantiate() as VehiculoAgente
	var car_slow := escena_car.instantiate() as VehiculoAgente
	mundo_vel.add_child(car_fast)
	mundo_vel.add_child(car_slow)
	car_fast.configurar({"velocidad_maxima": 1.0, "aceleracion": 1.0, "frenado": 1.0, "control": 0.5, "agarre": 1.0})
	car_slow.configurar({"velocidad_maxima": 0.0, "aceleracion": 1.0, "frenado": 1.0, "control": 0.5, "agarre": 1.0})
	car_fast.reiniciar_estado(Vector2(0, 0), 0.0, 0)
	car_slow.reiniciar_estado(Vector2(0, 100), 0.0, 0)
	car_fast.cerebro = MockCerebro.new(1.0, 0.0)
	car_slow.cerebro = MockCerebro.new(1.0, 0.0)
	await _esperar_fisicas(90)

	_assert_true(
		car_fast.velocidad_actual > car_slow.velocidad_actual * 2.0 and car_fast.global_position.x > car_slow.global_position.x + 60.0,
		"Modificador Velocidad: vel_max=1.0 (%.1f) supera ampliamente vel_max=0.0 (%.1f)" % [car_fast.velocidad_actual, car_slow.velocidad_actual]
	)
	mundo_vel.queue_free()
	await _esperar_fisicas(1)

	# 2. Control (velocidad de giro)
	var mundo_ctrl := Node2D.new()
	root.add_child(mundo_ctrl)
	var car_agile := escena_car.instantiate() as VehiculoAgente
	var car_stiff := escena_car.instantiate() as VehiculoAgente
	mundo_ctrl.add_child(car_agile)
	mundo_ctrl.add_child(car_stiff)
	car_agile.configurar({"control": 1.0})
	car_stiff.configurar({"control": 0.0})
	car_agile.reiniciar_estado(Vector2(0, 0), 0.0, 0)
	car_stiff.reiniciar_estado(Vector2(0, 100), 0.0, 0)
	car_agile.cerebro = MockCerebro.new(1.0, 1.0)
	car_stiff.cerebro = MockCerebro.new(1.0, 1.0)
	await _esperar_fisicas(20)

	_assert_true(
		car_agile.rotation > car_stiff.rotation * 2.0,
		"Modificador Control: control=1.0 (%.3f rad) gira >2x control=0.0 (%.3f rad)" % [car_agile.rotation, car_stiff.rotation]
	)
	mundo_ctrl.queue_free()
	await _esperar_fisicas(1)

	# 3. Agarre (lerp lateral)
	var mundo_grip := Node2D.new()
	root.add_child(mundo_grip)
	var car_grip := escena_car.instantiate() as VehiculoAgente
	var car_drift := escena_car.instantiate() as VehiculoAgente
	mundo_grip.add_child(car_grip)
	mundo_grip.add_child(car_drift)
	car_grip.configurar({"agarre": 1.0, "aceleracion": 1.0, "velocidad_maxima": 1.0})
	car_drift.configurar({"agarre": 0.0, "aceleracion": 1.0, "velocidad_maxima": 1.0})
	car_grip.reiniciar_estado(Vector2(0, 0), 0.0, 0)
	car_drift.reiniciar_estado(Vector2(0, 200), 0.0, 0)
	car_grip.velocity = Vector2(0, 100)
	car_drift.velocity = Vector2(0, 100)
	car_grip.cerebro = MockCerebro.new(1.0, 0.0)
	car_drift.cerebro = MockCerebro.new(1.0, 0.0)
	await _esperar_fisicas(10)

	_assert_true(
		absf(car_grip.velocity.y) < absf(car_drift.velocity.y) * 0.5,
		"Modificador Agarre: agarre=1.0 corrige derrape lateral (|vy|=%.1f vs %.1f)" % [absf(car_grip.velocity.y), absf(car_drift.velocity.y)]
	)
	mundo_grip.queue_free()
	await _esperar_fisicas(1)


func _test_d_deteccion_choque_muro() -> void:
	print("--- Test (d): Deteccion de choque via move_and_slide() ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	var muro := _crear_muro(Vector2(50, 0), Vector2(20, 200)) # Cara en x = 40
	mundo.add_child(muro)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)
	car.configurar({"velocidad_maxima": 1.0, "aceleracion": 1.0, "agarre": 1.0})
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	car.cerebro = MockCerebro.new(1.0, 0.0)

	var estado_senal := {"recibida": false, "motivo": ""}
	car.chocado.connect(func(v: VehiculoAgente, m: String) -> void:
		if v == car:
			estado_senal["recibida"] = true
			estado_senal["motivo"] = m
	)

	for _i in range(120):
		await physics_frame
		if car.esta_chocado:
			break

	_assert_true(car.esta_chocado and car.motivo_choque == "Chocado", "Choque contra muro marca esta_chocado y motivo='Chocado'")
	_assert_true(estado_senal["recibida"] and estado_senal["motivo"] == "Chocado", "Senal chocado emitida con motivo='Chocado'")

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_e_temporizador_anti_atascos() -> void:
	print("--- Test (e): Temporizador anti-atascos (tiempo_max_sin_checkpoint) ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)
	car.reiniciar_estado(Vector2.ZERO, 0.0, 3)
	car.cerebro = MockCerebro.new(0.0, 0.0)

	var estado_atascado := {"recibida": false}
	car.chocado.connect(func(v: VehiculoAgente, m: String) -> void:
		if v == car and m == "Atascado":
			estado_atascado["recibida"] = true
	)

	var max_sin_cp := car.tiempo_max_sin_checkpoint
	var tps := Engine.physics_ticks_per_second
	var frames_antes := int(floor((max_sin_cp - 0.2) * tps))
	var frames_despues := int(ceil((max_sin_cp + 0.15) * tps)) - frames_antes

	await _esperar_fisicas(frames_antes)
	_assert_true(not car.esta_chocado, "A los %.1fs aun no activa anti-atasco" % (max_sin_cp - 0.2))

	await _esperar_fisicas(frames_despues)
	_assert_true(
		car.esta_chocado and car.motivo_choque == "Atascado" and estado_atascado["recibida"],
		"Tras superar %.1fs sin checkpoint activa motivo='Atascado' y senal chocado" % max_sin_cp
	)

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_f_checkpoints_y_vueltas_secuenciales() -> void:
	print("--- Test (f): Checkpoints y conteo secuencial de vueltas ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	var escena_cp := load(RUTA_CHECKPOINT) as PackedScene
	var posiciones_cp := [Vector2(0, 0), Vector2(200, 0), Vector2(400, 0)]
	for i in range(posiciones_cp.size()):
		var cp := escena_cp.instantiate() as CheckpointArea
		cp.id_checkpoint = i
		cp.position = posiciones_cp[i]
		mundo.add_child(cp)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	car.position = Vector2(-100, 0)
	mundo.add_child(car)

	# Seguridad con cant_checkpoints == 0
	car.reiniciar_estado(Vector2(-100, 0), 0.0, 0)
	car.registrar_checkpoint(0)
	_assert_true(
		car.ultimo_checkpoint == -1 and car.checkpoints_cruzados == 0 and car.vuelta_actual == 1,
		"cant_checkpoints == 0 ignora registrar_checkpoint() sin dividir por cero"
	)

	# Circuito de 3 checkpoints
	car.reiniciar_estado(Vector2(-100, 0), 0.0, 3)
	car.cerebro = MockCerebro.new(0.0, 0.0)
	var ultimo_evento := {}
	car.checkpoint_alcanzado.connect(func(v: VehiculoAgente, id_cp: int, vuelta: int) -> void:
		ultimo_evento["v"] = v
		ultimo_evento["id"] = id_cp
		ultimo_evento["vuelta"] = vuelta
	)
	await _esperar_fisicas(2)

	# CP 1 fuera de orden -> ignorado
	car.global_position = Vector2(200, 0)
	await _esperar_fisicas(2)
	_assert_true(
		car.ultimo_checkpoint == -1 and car.checkpoints_cruzados == 0 and car.vuelta_actual == 1,
		"CP 1 fuera de orden es ignorado (ultimo=%d, cruzados=%d, vuelta=%d)" % [car.ultimo_checkpoint, car.checkpoints_cruzados, car.vuelta_actual]
	)

	# CP 0 valido
	car.global_position = Vector2(-100, 0)
	await _esperar_fisicas(2)
	car.global_position = Vector2(0, 0)
	await _esperar_fisicas(2)
	_assert_true(
		car.ultimo_checkpoint == 0 and car.checkpoints_cruzados == 1 and car.vuelta_actual == 1,
		"CP 0 aceptado en orden (ultimo=%d, cruzados=%d, vuelta=%d)" % [car.ultimo_checkpoint, car.checkpoints_cruzados, car.vuelta_actual]
	)

	# CP 1 valido
	car.global_position = Vector2(200, 0)
	await _esperar_fisicas(2)
	_assert_true(
		car.ultimo_checkpoint == 1 and car.checkpoints_cruzados == 2 and car.vuelta_actual == 1,
		"CP 1 aceptado tras CP 0"
	)

	# Volver a CP 0 fuera de orden -> ignorado
	car.global_position = Vector2(0, 0)
	await _esperar_fisicas(2)
	_assert_true(
		car.ultimo_checkpoint == 1 and car.checkpoints_cruzados == 2,
		"CP 0 repetido fuera de orden es ignorado"
	)

	# CP 2 valido
	car.global_position = Vector2(400, 0)
	await _esperar_fisicas(2)
	_assert_true(
		car.ultimo_checkpoint == 2 and car.checkpoints_cruzados == 3 and car.vuelta_actual == 1,
		"CP 2 aceptado tras CP 1"
	)

	# Cierre de vuelta: CP 2 -> CP 0 incrementa vuelta_actual a 2
	car.global_position = Vector2(-100, 0)
	await _esperar_fisicas(2)
	car.global_position = Vector2(0, 0)
	await _esperar_fisicas(2)
	_assert_true(
		car.ultimo_checkpoint == 0 and car.checkpoints_cruzados == 4 and car.vuelta_actual == 2
		and ultimo_evento.get("v") == car and ultimo_evento.get("id") == 0 and ultimo_evento.get("vuelta") == 2,
		"Completar ciclo 0->1->2->0 incrementa vuelta_actual a 2 y emite checkpoint_alcanzado"
	)

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_g_vehiculos_no_colisionan_entre_si() -> void:
	print("--- Test (g): Dos VehiculoAgente se cruzan sin colisionar ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	var escena_car := load(RUTA_VEHICULO) as PackedScene
	var car1 := escena_car.instantiate() as VehiculoAgente
	var car2 := escena_car.instantiate() as VehiculoAgente
	mundo.add_child(car1)
	mundo.add_child(car2)

	car1.configurar({"velocidad_maxima": 1.0, "aceleracion": 1.0, "agarre": 1.0})
	car2.configurar({"velocidad_maxima": 1.0, "aceleracion": 1.0, "agarre": 1.0})
	car1.reiniciar_estado(Vector2(0, 0), 0.0, 0)
	car2.reiniciar_estado(Vector2(20, 0), PI, 0)
	car1.cerebro = MockCerebro.new(1.0, 0.0)
	car2.cerebro = MockCerebro.new(1.0, 0.0)

	await _esperar_fisicas(60)
	_assert_true(
		not car1.esta_chocado and not car2.esta_chocado
		and car1.global_position.x > 20.0 and car2.global_position.x < 0.0,
		"Dos VehiculoAgente se atraviesan sin chocar (x1=%.1f, x2=%.1f)" % [car1.global_position.x, car2.global_position.x]
	)

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_h_resistencia_nan_y_no_finitos() -> void:
	print("--- Test (h): Proteccion contra NaN e INF en cerebro y configurar() ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	# Muro en rango de sensor para ejercitar tambien _actualizar_sensores()
	var muro := _crear_muro(Vector2(60, 0), Vector2(20, 200))
	mundo.add_child(muro)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)

	# (h1) cerebro.evaluar() retornando [NAN, NAN] durante 8 frames
	car.reiniciar_estado(Vector2(10, 0), 0.25, 0)
	car.cerebro = MockCerebro.new(NAN, NAN)
	await _esperar_fisicas(8)

	_assert_true(
		is_finite(car.global_position.x) and is_finite(car.global_position.y)
		and is_finite(car.rotation)
		and is_finite(car.velocity.x) and is_finite(car.velocity.y)
		and is_finite(car.velocidad_actual),
		"Test (h1): cerebro [NAN, NAN] mantiene pos/rot/velocity/velocidad_actual finitos"
	)
	_assert_true(
		is_finite(car.ultima_aceleracion_ia) and is_finite(car.ultimo_giro_ia)
		and is_equal_approx(car.ultima_aceleracion_ia, 0.0) and is_equal_approx(car.ultimo_giro_ia, 0.0),
		"Test (h1): comandos de cerebro [NAN, NAN] se sanean a (0.0, 0.0)"
	)

	var sensores_ok := car.lecturas_sensores.size() == 14
	if sensores_ok:
		for s in car.lecturas_sensores:
			if not is_finite(s) or s < 0.0 or s > 1.0:
				sensores_ok = false
				break
	_assert_true(sensores_ok, "Test (h1): lecturas_sensores permanecen finitas en [0.0, 1.0]")

	# Tambien verificar [INF, -INF] desde cerebro
	car.cerebro = MockCerebro.new(INF, -INF)
	await _esperar_fisicas(5)
	_assert_true(
		is_finite(car.global_position.x) and is_finite(car.global_position.y)
		and is_finite(car.rotation)
		and is_finite(car.velocity.x) and is_finite(car.velocity.y)
		and is_finite(car.velocidad_actual),
		"Test (h1): cerebro [INF, -INF] mantiene estado fisico finito"
	)

	# (h2) configurar() con NAN en los 5 atributos normalizados
	car.configurar({
		"velocidad_maxima": NAN,
		"aceleracion": NAN,
		"frenado": NAN,
		"control": NAN,
		"agarre": NAN
	})
	var attrs_nan_ok := (
		is_finite(car.attr_velocidad_maxima) and is_equal_approx(car.attr_velocidad_maxima, 0.7)
		and is_finite(car.attr_aceleracion) and is_equal_approx(car.attr_aceleracion, 0.7)
		and is_finite(car.attr_frenado) and is_equal_approx(car.attr_frenado, 0.7)
		and is_finite(car.attr_control) and is_equal_approx(car.attr_control, 0.7)
		and is_finite(car.attr_agarre) and is_equal_approx(car.attr_agarre, 0.7)
	)
	_assert_true(attrs_nan_ok, "Test (h2): configurar() con NAN sanea los 5 attr_* a 0.7 finito")

	var fisicas_nan_ok := (
		is_finite(car.vel_max) and car.vel_max >= 65.0 and car.vel_max <= 180.0
		and is_finite(car.tasa_aceleracion) and car.tasa_aceleracion >= 60.0 and car.tasa_aceleracion <= 240.0
		and is_finite(car.tasa_frenado) and car.tasa_frenado >= 75.0 and car.tasa_frenado <= 310.0
		and is_finite(car.vel_rotacion) and car.vel_rotacion >= 2.0 and car.vel_rotacion <= 5.2
		and is_finite(car.factor_agarre) and car.factor_agarre >= 2.0 and car.factor_agarre <= 12.0
	)
	_assert_true(fisicas_nan_ok, "Test (h2): parametros fisicos derivados permanecen finitos y en rango")

	# Adicional: INF/-INF y valores no numericos en configurar()
	car.configurar({
		"velocidad_maxima": INF,
		"aceleracion": -INF,
		"frenado": NAN,
		"control": null,
		"agarre": "invalido"
	})
	var attrs_mix_ok := (
		is_finite(car.attr_velocidad_maxima) and car.attr_velocidad_maxima >= 0.0 and car.attr_velocidad_maxima <= 1.0
		and is_finite(car.attr_aceleracion) and car.attr_aceleracion >= 0.0 and car.attr_aceleracion <= 1.0
		and is_finite(car.attr_frenado) and car.attr_frenado >= 0.0 and car.attr_frenado <= 1.0
		and is_finite(car.attr_control) and car.attr_control >= 0.0 and car.attr_control <= 1.0
		and is_finite(car.attr_agarre) and car.attr_agarre >= 0.0 and car.attr_agarre <= 1.0
		and is_finite(car.vel_max) and is_finite(car.tasa_aceleracion)
		and is_finite(car.tasa_frenado) and is_finite(car.vel_rotacion) and is_finite(car.factor_agarre)
	)
	_assert_true(attrs_mix_ok, "Test (h2): configurar() con INF/-INF/null/String mantiene atributos y fisicas finitos")

	# (h3) configurar() con nivel_ia null, NAN y fuera de rango
	car.configurar({"color": Color.RED, "nivel_ia": null, "velocidad_maxima": 1.0})
	_assert_true(
		car.nivel_ia == 1
		and is_equal_approx(car.attr_velocidad_maxima, 1.0)
		and is_equal_approx(car.vel_max, 180.0)
		and car.color_vehiculo == Color.RED,
		"Test (h3): configurar() con nivel_ia=null sanea nivel_ia=1 y aplica atributos/color"
	)

	car.configurar({"nivel_ia": NAN})
	_assert_true(car.nivel_ia == 1, "Test (h3): configurar() con nivel_ia=NAN sanea nivel_ia=1")

	# (h4) _physics_process(NAN / -1.0) no envenena anti-atasco y corrupcion externa se recupera
	car.reiniciar_estado(Vector2.ZERO, 0.0, 3)
	car.cerebro = MockCerebro.new(0.0, 0.0)
	car._physics_process(NAN)
	car._physics_process(-1.0)
	_assert_true(
		is_finite(car.tiempo_sin_checkpoint) and car.tiempo_sin_checkpoint >= 0.0,
		"Test (h4): _physics_process(NAN/-1.0) no envenena tiempo_sin_checkpoint"
	)

	var pasos := int(ceil((car.tiempo_max_sin_checkpoint + 0.2) * 60.0))
	for _i in range(pasos):
		car._physics_process(1.0 / 60.0)
	_assert_true(
		car.esta_chocado and car.motivo_choque == "Atascado",
		"Test (h4): tras _physics_process(NAN/-1.0), %d pasos de 1/60s activan anti-atasco" % pasos
	)

	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	car.rotation = NAN
	car.global_position = Vector2(NAN, NAN)
	car._physics_process(1.0 / 60.0)
	_assert_true(
		is_finite(car.rotation) and is_finite(car.global_position.x) and is_finite(car.global_position.y),
		"Test (h4): rotation=NAN y global_position=(NAN,NAN) se recuperan a valores finitos"
	)

	# (h5) reiniciar_estado() limpia ultima_aceleracion_ia, ultimo_giro_ia y lecturas_sensores; tiempo_max_sin_checkpoint=NAN usa fallback 4.0s
	car.ultima_aceleracion_ia = 0.99
	car.ultimo_giro_ia = -0.88
	car.lecturas_sensores = PackedFloat64Array([0.1, 0.2, 0.3])
	car.reiniciar_estado(Vector2.ZERO, 0.0, 3)
	var sensores_reiniciados := car.lecturas_sensores.size() == 14
	if sensores_reiniciados:
		for s in car.lecturas_sensores:
			if not is_equal_approx(s, 1.0):
				sensores_reiniciados = false
				break
	_assert_true(
		is_equal_approx(car.ultima_aceleracion_ia, 0.0)
		and is_equal_approx(car.ultimo_giro_ia, 0.0)
		and sensores_reiniciados,
		"Test (h5): reiniciar_estado() reinicia ultima_aceleracion_ia, ultimo_giro_ia y 14 lecturas_sensores a 1.0"
	)

	car.tiempo_max_sin_checkpoint = NAN
	car.cerebro = MockCerebro.new(0.0, 0.0)
	car.reiniciar_estado(Vector2.ZERO, 0.0, 3)
	for _i in range(230):
		car._physics_process(1.0 / 60.0)
	_assert_true(
		not car.esta_chocado,
		"Test (h5): con tiempo_max_sin_checkpoint=NAN aun no choca a los 3.83s"
	)
	for _i in range(25):
		car._physics_process(1.0 / 60.0)
	_assert_true(
		car.esta_chocado and car.motivo_choque == "Atascado",
		"Test (h5): con tiempo_max_sin_checkpoint=NAN activa motivo='Atascado' al superar 4.0s"
	)
	car.tiempo_max_sin_checkpoint = 4.0

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_i_modo_piloto_humano() -> void:
	print("--- Test (i): Modo Piloto Humano (R3: sync, WASD/Flechas, cancelacion, entradas y fisicas) ---")
	_liberar_teclas_prueba()

	var mundo := Node2D.new()
	root.add_child(mundo)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)

	# 1. Sincronizacion bidireccional es_humano <-> control_manual y configurar() estricto
	car.es_humano = true
	var sync_a: bool = car.es_humano and car.control_manual
	car.control_manual = false
	var sync_b: bool = (not car.es_humano) and (not car.control_manual)
	car.configurar({"es_humano": true})
	var cfg_a: bool = car.es_humano and car.control_manual
	car.configurar({"control_manual": false})
	var cfg_b: bool = (not car.es_humano) and (not car.control_manual)
	car.configurar({"es_humano": "false"})
	var cfg_str_rechazada: bool = (not car.es_humano) and (not car.control_manual)
	_assert_true(
		sync_a and sync_b and cfg_a and cfg_b and cfg_str_rechazada,
		"es_humano y control_manual sincronizan bidireccionalmente y configurar() rechaza string 'false'"
	)

	# 2. WASD y Flechas + cancelacion opuesta simetrica
	car.configurar({"es_humano": true, "velocidad_maxima": 1.0, "aceleracion": 1.0, "frenado": 1.0, "control": 0.8, "agarre": 1.0})
	car.cerebro = null
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)

	_simular_tecla(KEY_W, true)
	await _esperar_fisicas(10)
	var w_ok: bool = is_equal_approx(car.ultima_aceleracion_ia, 1.0) and car.velocidad_actual > 10.0 and car.global_position.x > 1.0
	_simular_tecla(KEY_W, false)

	_simular_tecla(KEY_S, true)
	await _esperar_fisicas(25)
	var s_ok: bool = is_equal_approx(car.ultima_aceleracion_ia, -1.0) and car.velocidad_actual < -5.0
	_simular_tecla(KEY_S, false)

	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	_simular_tecla(KEY_UP, true)
	_simular_tecla(KEY_RIGHT, true)
	await _esperar_fisicas(10)
	var flechas_der_ok: bool = is_equal_approx(car.ultima_aceleracion_ia, 1.0) and is_equal_approx(car.ultimo_giro_ia, 1.0) and car.rotation > 0.05
	_simular_tecla(KEY_UP, false)
	_simular_tecla(KEY_RIGHT, false)

	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	_simular_tecla(KEY_DOWN, true)
	_simular_tecla(KEY_LEFT, true)
	await _esperar_fisicas(10)
	var flechas_izq_ok: bool = is_equal_approx(car.ultima_aceleracion_ia, -1.0) and is_equal_approx(car.ultimo_giro_ia, -1.0) and car.rotation < -0.05
	_simular_tecla(KEY_DOWN, false)
	_simular_tecla(KEY_LEFT, false)

	_assert_true(w_ok and s_ok and flechas_der_ok and flechas_izq_ok, "Piloto Humano responde a W/S y Flechas (aceleracion, reversa, giro izq/der)")

	# Cancelacion simetrica de teclas opuestas
	_simular_tecla(KEY_W, true)
	_simular_tecla(KEY_S, true)
	_simular_tecla(KEY_A, true)
	_simular_tecla(KEY_D, true)
	await _esperar_fisicas(3)
	var cancel_wasd := is_equal_approx(car.ultima_aceleracion_ia, 0.0) and is_equal_approx(car.ultimo_giro_ia, 0.0)
	_liberar_teclas_prueba()

	_simular_tecla(KEY_UP, true)
	_simular_tecla(KEY_DOWN, true)
	_simular_tecla(KEY_LEFT, true)
	_simular_tecla(KEY_RIGHT, true)
	await _esperar_fisicas(3)
	var cancel_flechas := is_equal_approx(car.ultima_aceleracion_ia, 0.0) and is_equal_approx(car.ultimo_giro_ia, 0.0)
	_liberar_teclas_prueba()
	_assert_true(cancel_wasd and cancel_flechas, "Teclas opuestas simultaneas (W+S, A+D, Arriba+Abajo, Izq+Der) cancelan a 0.0")

	# 3. ultimas_entradas_ia (18 floats) en Humano y en IA
	car.posiciones_checkpoints = PackedVector2Array([Vector2(150, 0)])
	car.reiniciar_estado(Vector2.ZERO, 0.0, 1)
	_simular_tecla(KEY_W, true)
	await _esperar_fisicas(6)
	var entradas_hum := car.ultimas_entradas_ia.duplicate()
	var ent_hum_ok := entradas_hum.size() == 18
	if ent_hum_ok:
		for v in entradas_hum:
			if not is_finite(v) or v < 0.0 or v > 1.0:
				ent_hum_ok = false
				break
	_liberar_teclas_prueba()
	_assert_true(
		ent_hum_ok and entradas_hum[16] > 0.51 and entradas_hum[17] > 0.90,
		"ultimas_entradas_ia (18 floats finitos en [0,1]) se actualiza cada tick en Piloto Humano"
	)

	car.es_humano = false
	car.cerebro = MockCerebro.new(0.6, -0.3)
	await _esperar_fisicas(3)
	var ent_ia_ok := car.ultimas_entradas_ia.size() == 18 and is_equal_approx(car.ultimas_entradas_ia[17], (0.6 + 1.0) * 0.5)
	_assert_true(ent_ia_ok, "ultimas_entradas_ia tambien se mantiene sincronizada en modo IA")

	# 4. Misma fisica: colision con muro y checkpoints en modo humano
	car.es_humano = true
	car.cerebro = null
	var escena_cp := load(RUTA_CHECKPOINT) as PackedScene
	var cp0 := escena_cp.instantiate() as CheckpointArea
	cp0.id_checkpoint = 0
	cp0.position = Vector2(24, 0)
	mundo.add_child(cp0)
	var muro := _crear_muro(Vector2(68, 0), Vector2(20, 200))
	mundo.add_child(muro)

	car.reiniciar_estado(Vector2.ZERO, 0.0, 1)
	_simular_tecla(KEY_W, true)
	for _i in range(90):
		await physics_frame
		if car.esta_chocado:
			break
	_liberar_teclas_prueba()
	_assert_true(
		car.checkpoints_cruzados >= 1 and car.esta_chocado and car.motivo_choque == "Chocado",
		"Piloto Humano comparte checkpoints secuenciales y colision contra muros (cps=%d, motivo='%s')" % [car.checkpoints_cruzados, car.motivo_choque]
	)

	# Anti-atasco compartido en modo humano
	car.tiempo_max_sin_checkpoint = 0.25
	car.reiniciar_estado(Vector2(-300, 0), 0.0, 2)
	await _esperar_fisicas(25)
	_assert_true(
		car.esta_chocado and car.motivo_choque == "Atascado",
		"Piloto Humano comparte temporizador anti-atasco (motivo='%s')" % car.motivo_choque
	)

	mundo.queue_free()
	await _esperar_fisicas(1)


func _test_j_estela_telemetrica() -> void:
	print("--- Test (j): EstelaTelemetrica (R4: nodo, capas, visibilidad, longitud, 3 colores, reinicio) ---")
	_liberar_teclas_prueba()

	var mundo := Node2D.new()
	root.add_child(mundo)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)
	await _esperar_fisicas(1)

	var estela := car.get_node_or_null("EstelaTelemetrica") as EstelaTelemetrica
	_assert_true(
		estela != null and estela.top_level and estela.z_index == 1 and not estela.z_as_relative,
		"EstelaTelemetrica existe en vehiculo_agente.tscn con top_level=true, z_index=1, z_as_relative=false"
	)

	# Clamp de longitud_maxima_estela [10, 600] y recorte de puntos
	car.longitud_maxima_estela = 3
	var clamp_min_ok: bool = car.longitud_maxima_estela == 10 and estela.longitud_maxima_estela == 10
	car.longitud_maxima_estela = 1500
	var clamp_max_ok: bool = car.longitud_maxima_estela == 600 and estela.longitud_maxima_estela == 600
	car.longitud_maxima_estela = 12

	car.configurar({"es_humano": false, "velocidad_maxima": 1.0, "aceleracion": 1.0, "frenado": 1.0, "agarre": 1.0})
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	car.cerebro = MockCerebro.new(1.0, 0.0)
	await _esperar_fisicas(20)
	var recorte_ok: bool = estela.obtener_puntos().size() == 12 and estela.obtener_colores().size() == 12
	_assert_true(clamp_min_ok and clamp_max_ok and recorte_ok, "longitud_maxima_estela clampa [10, 600] y recorta buffer")

	# Visibilidad sincronizada incluso cuando el vehiculo esta chocado
	car._marcar_chocado("Chocado")
	car.mostrar_estela = false
	var vis_off_ok: bool = not estela.visible
	car.mostrar_estela = true
	var vis_on_ok: bool = estela.visible
	_assert_true(vis_off_ok and vis_on_ok, "mostrar_estela sincroniza EstelaTelemetrica.visible incluso en coche chocado")

	# 3 colores longitudinales: Verde (acel > 0.05), Amarillo/Naranja (freno/coasting), Azul/Cian (reversa)
	car.longitud_maxima_estela = 120
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)
	_assert_true(
		estela.obtener_puntos().is_empty() and estela.obtener_colores().is_empty(),
		"reiniciar_estado() limpia los puntos y colores de EstelaTelemetrica"
	)

	car.cerebro = MockCerebro.new(1.0, 0.0) # Acelerando -> Verde
	await _esperar_fisicas(15)
	car.cerebro = MockCerebro.new(-1.0, 0.0) # Frenando en avance (vel > 5) y luego reversa (vel <= 5)
	await _esperar_fisicas(25)
	car.cerebro = MockCerebro.new(0.0, 0.0) # Sin acelerar -> Amarillo/Naranja
	await _esperar_fisicas(3)

	var tiene_verde := false
	var tiene_amarillo := false
	var tiene_azul := false
	for col: Color in estela.obtener_colores():
		if col.b > 0.50 and col.b > col.r + 0.15 and col.b >= col.g * 0.72:
			tiene_azul = true
		elif col.g > 0.45 and col.g > col.r + 0.15 and col.g > col.b + 0.15:
			tiene_verde = true
		elif col.r > 0.55 and col.g > 0.30 and col.b < 0.45 and col.r >= col.g - 0.10:
			tiene_amarillo = true

	_assert_true(
		tiene_verde and tiene_amarillo and tiene_azul,
		"EstelaTelemetrica registra verde (aceleracion), amarillo/naranja (freno/inercia) y azul/cian (reversa)"
	)

	mundo.queue_free()
	await _esperar_fisicas(1)
