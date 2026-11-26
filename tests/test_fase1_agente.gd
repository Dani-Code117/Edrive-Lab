extends SceneTree

## Pruebas automatizadas Fase 1: VehiculoAgente, sensores RayCast2D,
## físicas normalizadas, colisión con muros, anti-atasco (4.0s),
## checkpoints secuenciales y sprites/capas del proyecto.

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

	print("=== Resumen Fase 1: %d verificaciones, %d fallos ===" % [_total_checks, _failures])
	quit(0 if _failures == 0 else 1)


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

	var escena_car := load(RUTA_VEHICULO) as PackedScene
	var car := escena_car.instantiate() as VehiculoAgente
	mundo.add_child(car)
	await _esperar_fisicas(1)

	_assert_true(car.collision_layer == 2, "VehiculoAgente collision_layer == 2")
	_assert_true(car.collision_mask == 1, "VehiculoAgente collision_mask == 1")
	_assert_true(is_equal_approx(car.tiempo_max_sin_checkpoint, 4.0), "tiempo_max_sin_checkpoint == 4.0")
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
	var rayos_ok := car._rayos.size() == 14
	if rayos_ok:
		for i in range(14):
			var rayo := car._rayos[i]
			var diff_ang := absf(angle_difference(rayo.target_position.angle(), deg_to_rad(angulos_esperados[i])))
			var diff_len := absf(rayo.target_position.length() - VehiculoAgente.LONGITUD_RAYO)
			if not rayo.enabled or rayo.collision_mask != 1 or rayo.collide_with_areas or not rayo.collide_with_bodies or diff_ang >= 0.01 or diff_len >= 0.1:
				rayos_ok = false
				break
	_assert_true(rayos_ok, "14 RayCast2D (11 frontales + 3 traseros, %.0fpx, mask=1, bodies=true, areas=false)" % VehiculoAgente.LONGITUD_RAYO)

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

	var esperado_30px := 30.0 / VehiculoAgente.LONGITUD_RAYO
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

	muro.position = Vector2(200, 0) # Fuera de rango (190px > 160px)
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
	print("--- Test (e): Temporizador anti-atascos (4.0s sin checkpoint) ---")
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

	var tps := Engine.physics_ticks_per_second
	var frames_antes := int(floor(3.8 * tps))
	var frames_despues := int(ceil(4.1 * tps)) - frames_antes

	await _esperar_fisicas(frames_antes)
	_assert_true(not car.esta_chocado, "A los 3.8s aun no activa anti-atasco")

	await _esperar_fisicas(frames_despues)
	_assert_true(
		car.esta_chocado and car.motivo_choque == "Atascado" and estado_atascado["recibida"],
		"Tras superar 4.0s sin checkpoint activa motivo='Atascado' y senal chocado"
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

	for _i in range(250):
		car._physics_process(1.0 / 60.0)
	_assert_true(
		car.esta_chocado and car.motivo_choque == "Atascado",
		"Test (h4): tras _physics_process(NAN/-1.0), 250 pasos de 1/60s activan anti-atasco"
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
