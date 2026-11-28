extends SceneTree

## Pruebas automatizadas Fase 2: CerebroEntrenado, RedNeuronal (18 -> 8 -> 2),
## integración con VehiculoAgente y preparación segura de EntrenadorGenetico.
## NOTA: Nunca ejecuta entrenamiento real ni escribe archivos .tres en res://Assets/Presets_ia/.

const RUTA_VEHICULO := "res://Assets/Escenas/Componentes/vehiculo_agente.tscn"
const RUTA_PRESETS_IA := "res://Assets/Presets_ia"
const RUTA_CREADOR := "res://Assets/Escenas/Vistas/creador_mapa.tscn"
const RUTA_TEMA_TELEMETRIA := "res://Assets/Temas/tema_telemetria.tres"

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


func _esperar_fisicas(frames: int) -> void:
	for _i in range(frames):
		await physics_frame


func _run_all() -> void:
	await physics_frame

	_test_a_cerebro_entrenado_esquema_y_roundtrip_temp()
	_test_b_red_neuronal_matematica_tanh_y_limites()
	_test_c_casos_borde_nan_inf_tamanos_y_operadores()
	await _test_d_integracion_vehiculo_agente()
	await _test_e_entrenador_genetico_y_presets_vacios()
	await _test_f_arquetipos_pista_y_creador_mapa()

	print("=== Resumen Fase 2: %d verificaciones, %d fallos ===" % [_total_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_a_cerebro_entrenado_esquema_y_roundtrip_temp() -> void:
	print("--- Test (a): CerebroEntrenado esquema 18->8->2 y round-trip en temp dir ---")
	var c := CerebroEntrenado.new()
	_assert_true(c.nivel == 1, "CerebroEntrenado.nivel por defecto == 1")
	_assert_true(c.num_entradas == 18 and c.num_oculta == 8 and c.num_salida == 2, "Topologia por defecto 18->8->2")
	_assert_true(
		c.pesos_oculta.size() == 144 and c.sesgos_oculta.size() == 8
		and c.pesos_salida.size() == 16 and c.sesgos_salida.size() == 2,
		"Tamanos por defecto 144/8/16/2 inicializados"
	)
	_assert_true(c.es_valido(), "CerebroEntrenado recien creado es valido")

	var props_esperadas := [
		"nivel", "titulo", "descripcion_educativa",
		"num_entradas", "num_oculta", "num_salida",
		"pesos_oculta", "sesgos_oculta", "pesos_salida", "sesgos_salida",
		"fitness_alcanzado",
	]
	var props_exportadas: Dictionary = {}
	for p in c.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_STORAGE) != 0:
			props_exportadas[p["name"]] = true
	var todas_exportadas := true
	for nombre in props_esperadas:
		if not props_exportadas.has(nombre):
			todas_exportadas = false
			break
	_assert_true(todas_exportadas, "Todas las propiedades @export de CerebroEntrenado tienen uso STORAGE")

	_assert_true(
		CerebroEntrenado.ruta_para_nivel(1) == "res://Assets/Presets_ia/nivel_01.tres"
		and CerebroEntrenado.ruta_para_nivel(10) == "res://Assets/Presets_ia/nivel_10.tres",
		"ruta_para_nivel(1..10) genera rutas nivel_01..10.tres"
	)

	# Validaciones negativas de es_valido()
	var c_bad_nivel := CerebroEntrenado.new()
	c_bad_nivel.nivel = 0
	var c_bad_topo := CerebroEntrenado.new()
	c_bad_topo.num_entradas = 5
	var c_bad_size := CerebroEntrenado.new()
	c_bad_size.pesos_oculta.resize(143)
	var c_bad_nan := CerebroEntrenado.new()
	c_bad_nan.pesos_oculta[10] = NAN
	var c_bad_inf := CerebroEntrenado.new()
	c_bad_inf.sesgos_salida[1] = INF
	_assert_true(
		not c_bad_nivel.es_valido()
		and not c_bad_topo.es_valido()
		and not c_bad_size.es_valido()
		and not c_bad_nan.es_valido()
		and not c_bad_inf.es_valido(),
		"es_valido() rechaza nivel fuera de rango, topologia erronea, tamano erroneo, NAN e INF"
	)

	# Round-trip .tres exclusivamente en OS.get_temp_dir() y limpieza inmediata
	var temp_dir := OS.get_temp_dir().path_join("edrive_test_fase2_%d" % Time.get_ticks_usec())
	var err_mkdir := DirAccess.make_dir_recursive_absolute(temp_dir)
	var ruta_temp := temp_dir.path_join("cerebro_roundtrip_test.tres")

	var orig := CerebroEntrenado.new()
	orig.nivel = 7
	orig.titulo = "Nivel 7 — Control de Frenada"
	orig.descripcion_educativa = "Prueba temporal de serialización"
	orig.fitness_alcanzado = 1234.5
	for i in range(144):
		orig.pesos_oculta[i] = float(i - 20) * 0.05
	for j in range(8):
		orig.sesgos_oculta[j] = float(j) * 0.1 - 0.25
	for k in range(16):
		orig.pesos_salida[k] = float(k - 5) * 0.08
	orig.sesgos_salida[0] = 0.3
	orig.sesgos_salida[1] = -0.4

	var err_save := ResourceSaver.save(orig, ruta_temp)
	var recargado := ResourceLoader.load(ruta_temp, "", ResourceLoader.CACHE_MODE_IGNORE) as CerebroEntrenado

	var roundtrip_ok := (
		err_mkdir == OK
		and err_save == OK
		and recargado != null
		and recargado.es_valido()
		and recargado.nivel == 7
		and recargado.titulo == orig.titulo
		and recargado.descripcion_educativa == orig.descripcion_educativa
		and is_equal_approx(recargado.fitness_alcanzado, 1234.5)
		and recargado.pesos_oculta.size() == 144
		and is_equal_approx(recargado.pesos_oculta[17], orig.pesos_oculta[17])
		and is_equal_approx(recargado.sesgos_salida[1], -0.4)
	)
	_assert_true(roundtrip_ok, "Round-trip .tres en OS.get_temp_dir() preserva esquema y pesos")

	# Eliminar archivo y carpeta temporal siempre
	if FileAccess.file_exists(ruta_temp):
		DirAccess.remove_absolute(ruta_temp)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	_assert_true(
		not FileAccess.file_exists(ruta_temp) and not DirAccess.dir_exists_absolute(temp_dir),
		"Archivo .tres y directorio temporal eliminados tras round-trip"
	)


func _test_b_red_neuronal_matematica_tanh_y_limites() -> void:
	print("--- Test (b): RedNeuronal matematica tanh() exacta, snapshots y limites ---")
	var red_cero := RedNeuronal.new()
	var sal_cero := red_cero.evaluar(PackedFloat64Array([0.5, 0.2, 0.8, 1.0, 0.0, 0.3, 0.7, 0.4, 0.6, 0.1, 0.9, 0.2, 0.5, 0.8, 1.0, 0.5, 0.5, 0.5]))
	_assert_true(
		sal_cero.size() == 2
		and is_equal_approx(sal_cero[0], 0.0)
		and is_equal_approx(sal_cero[1], 0.0),
		"Red con pesos 0 retorna [0.0, 0.0] exacto con tanh()"
	)

	# Verificación matemática exacta contra cálculo manual independiente
	var red := RedNeuronal.new()
	var entradas := PackedFloat64Array([0.2, 0.4, 0.6, 0.8, 0.1, 0.9, 0.3, 0.5, 0.7, 0.25, 0.85, 0.15, 0.65, 0.35, 0.9, 0.5, 0.5, 0.5])
	for j in range(8):
		red.sesgos_oculta[j] = 0.1 * float(j - 2)
		for i in range(18):
			red.pesos_oculta[j * 18 + i] = 0.05 * float((i + j) - 4)
	for k in range(2):
		red.sesgos_salida[k] = 0.2 if k == 0 else -0.15
		for j in range(8):
			red.pesos_salida[k * 8 + j] = (0.3 if k == 0 else -0.25) * float(j - 2)

	var h_esperada: Array[float] = []
	for j in range(8):
		var s := red.sesgos_oculta[j]
		for i in range(18):
			s += entradas[i] * red.pesos_oculta[j * 18 + i]
		h_esperada.append(tanh(s))

	var z0 := red.sesgos_salida[0]
	var z1 := red.sesgos_salida[1]
	for j in range(8):
		z0 += h_esperada[j] * red.pesos_salida[0 * 8 + j]
		z1 += h_esperada[j] * red.pesos_salida[1 * 8 + j]
	var acel_esperada := clampf(tanh(z0), -1.0, 1.0)
	var giro_esperado := clampf(tanh(z1), -1.0, 1.0)

	var salida := red.evaluar(entradas)
	var ocultas_ok := red.ultimas_ocultas.size() == 8
	if ocultas_ok:
		for j in range(8):
			if absf(red.ultimas_ocultas[j] - h_esperada[j]) > 1e-6:
				ocultas_ok = false
				break

	_assert_true(
		absf(salida[0] - acel_esperada) < 1e-6 and absf(salida[1] - giro_esperado) < 1e-6,
		"evaluar() coincide exactamente (<1e-6) con calculo manual tanh()"
	)
	_assert_true(
		red.ultimas_entradas.size() == 18
		and ocultas_ok
		and red.ultimas_salidas.size() == 2
		and is_equal_approx(red.ultimas_salidas[0], salida[0])
		and is_equal_approx(red.ultimas_salidas[1], salida[1]),
		"Instantaneas ultimas_entradas(18), ultimas_ocultas(8) y ultimas_salidas(2) sincronizadas"
	)

	# Copia fresca retornada (mutar salida no corrompe ultimas_salidas)
	salida[0] = 999.0
	_assert_true(
		is_equal_approx(red.ultimas_salidas[0], acel_esperada),
		"evaluar() retorna copia fresca independiente de ultimas_salidas"
	)

	# 120 pruebas aleatorias + valores extremos finitos (-1e6, 1e6, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 98765
	var todas_acotadas := true
	for idx in range(120):
		var r_test := RedNeuronal.new()
		r_test.inicializar_aleatorio(idx + 1, 4.0)
		var ent := PackedFloat64Array()
		ent.resize(18)
		for i in range(18):
			if idx % 10 == 0:
				ent[i] = -1e6 if i % 2 == 0 else 1e6
			elif idx % 10 == 1:
				ent[i] = 0.0
			else:
				ent[i] = rng.randf_range(-50.0, 50.0)
		var out := r_test.evaluar(ent)
		if out.size() != 2 or not is_finite(out[0]) or not is_finite(out[1]):
			todas_acotadas = false
			break
		if out[0] < -1.0 or out[0] > 1.0 or out[1] < -1.0 or out[1] > 1.0:
			todas_acotadas = false
			break
		for v in r_test.ultimas_ocultas:
			if not is_finite(v) or v < -1.0 or v > 1.0:
				todas_acotadas = false
				break
	_assert_true(todas_acotadas, "120 redes/entradas aleatorias y extremas (-1e6, 1e6, 0) producen salidas acotadas y finitas")


func _test_c_casos_borde_nan_inf_tamanos_y_operadores() -> void:
	print("--- Test (c): Casos borde NaN/INF, tamanos incorrectos y operadores ---")
	var red := RedNeuronal.new()
	red.inicializar_aleatorio(55, 1.5)

	# Entradas finitas extremas NO deben recortarse a [0, 1]
	var out_ext := red.evaluar(PackedFloat64Array([-1e6, 1e6, -500.0, 500.0, 0.0, 1.0, -1.0]))
	_assert_true(
		is_equal_approx(red.ultimas_entradas[0], -1e6)
		and is_equal_approx(red.ultimas_entradas[1], 1e6)
		and is_finite(out_ext[0]) and out_ext[0] >= -1.0 and out_ext[0] <= 1.0
		and is_finite(out_ext[1]) and out_ext[1] >= -1.0 and out_ext[1] <= 1.0,
		"Entradas finitas arbitrarias (-1e6, 1e6) pasan sin recorte a [0,1] y mantienen salidas acotadas"
	)

	# Arreglo vacío, corto y sobredimensionado
	var out_vacio := red.evaluar(PackedFloat64Array())
	var out_corto := red.evaluar(PackedFloat64Array([0.5, 0.8, 0.1]))
	var ent_largo := PackedFloat64Array()
	ent_largo.resize(25)
	ent_largo.fill(0.4)
	var out_largo := red.evaluar(ent_largo)
	_assert_true(
		out_vacio.size() == 2 and out_corto.size() == 2 and out_largo.size() == 2
		and is_equal_approx(red.ultimas_entradas[17], 0.4)
		and red.ultimas_entradas.size() == 18,
		"Entradas vacias, cortas (<18) y largas (>18) se normalizan a 18 entradas de forma segura"
	)

	# Entradas NaN, INF, -INF
	var out_nan := red.evaluar(PackedFloat64Array([NAN, INF, -INF, 0.5, NAN, INF, -INF]))
	_assert_true(
		is_equal_approx(red.ultimas_entradas[0], 0.0)
		and is_equal_approx(red.ultimas_entradas[1], 0.0)
		and is_equal_approx(red.ultimas_entradas[2], 0.0)
		and is_finite(out_nan[0]) and out_nan[0] >= -1.0 and out_nan[0] <= 1.0
		and is_finite(out_nan[1]) and out_nan[1] >= -1.0 and out_nan[1] <= 1.0,
		"Entradas NaN/INF/-INF se sanean a 0.0 y producen salidas finitas acotadas"
	)

	# Pesos corruptos directamente en memoria
	var red_corrupta := red.clonar()
	red_corrupta.pesos_oculta[0] = NAN
	red_corrupta.sesgos_oculta[0] = INF
	red_corrupta.pesos_salida[0] = -INF
	red_corrupta.sesgos_salida[1] = NAN
	var out_corrupta := red_corrupta.evaluar(PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]))
	_assert_true(
		is_finite(out_corrupta[0]) and out_corrupta[0] >= -1.0 and out_corrupta[0] <= 1.0
		and is_finite(out_corrupta[1]) and out_corrupta[1] >= -1.0 and out_corrupta[1] <= 1.0,
		"Pesos y sesgos corruptos (NaN/INF) en memoria no rompen evaluar()"
	)

	# cargar_desde_recurso con null e inválido no corrompe pesos válidos
	var peso_antes := red.pesos_oculta[3]
	var rec_invalido := CerebroEntrenado.new()
	rec_invalido.pesos_oculta[0] = NAN
	_assert_true(
		not red.cargar_desde_recurso(null)
		and not red.cargar_desde_recurso(rec_invalido)
		and is_equal_approx(red.pesos_oculta[3], peso_antes),
		"cargar_desde_recurso(null/invalido) retorna false sin corromper red"
	)

	# exportar_a_recurso, clonar, mutar, cruzar y fallback
	var rec_exp := red.exportar_a_recurso(4, "Nivel 4 — Zig-Zag Nervioso", "Desc", 500.0)
	_assert_true(
		rec_exp.es_valido() and red.cerebro == rec_exp and rec_exp.nivel == 4,
		"exportar_a_recurso() actualiza cerebro y produce recurso valido"
	)

	var clon := red.clonar()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	clon.mutar(1.0, 0.5, rng)
	var cambio := false
	for i in range(144):
		if not is_equal_approx(clon.pesos_oculta[i], red.pesos_oculta[i]):
			cambio = true
			break
	_assert_true(cambio, "clonar() + mutar() modifica la copia sin alterar el original")

	var hijo := RedNeuronal.cruzar(red, clon, rng, 1.0)
	var out_hijo := hijo.evaluar(PackedFloat64Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]))
	_assert_true(
		is_finite(out_hijo[0]) and is_finite(out_hijo[1]),
		"RedNeuronal.cruzar() genera descendiente funcional"
	)

	var fb := RedNeuronal.cargar_nivel_o_fallback(8)
	_assert_true(
		fb != null and fb.cerebro != null and fb.cerebro.es_valido() and fb.cerebro.nivel == 8,
		"cargar_nivel_o_fallback(8) construye respaldo valido en memoria sin .tres"
	)


func _test_d_integracion_vehiculo_agente() -> void:
	print("--- Test (d): Integracion RedNeuronal + VehiculoAgente ---")
	var mundo := Node2D.new()
	root.add_child(mundo)

	var muro := StaticBody2D.new()
	muro.collision_layer = 1
	muro.collision_mask = 0
	muro.position = Vector2(200, 0)
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	col.shape = rect
	muro.add_child(col)
	mundo.add_child(muro)

	var car := (load(RUTA_VEHICULO) as PackedScene).instantiate() as VehiculoAgente
	mundo.add_child(car)
	car.configurar({"velocidad_maxima": 0.8, "aceleracion": 0.9, "control": 0.8, "agarre": 0.8, "nivel_ia": 6})
	car.reiniciar_estado(Vector2.ZERO, 0.0, 0)

	var red := RedNeuronal.new()
	red.sesgos_salida[0] = 0.8 # aceleracion > 0.5
	red.sesgos_salida[1] = 0.2 # giro suave
	car.cerebro = red

	await _esperar_fisicas(10)

	var sensores_sincronizados := red.ultimas_entradas.size() == 18
	if sensores_sincronizados:
		for i in range(14):
			if absf(red.ultimas_entradas[i] - car.lecturas_sensores[i]) > 1e-6:
				sensores_sincronizados = false
				break

	_assert_true(
		not car.esta_chocado
		and car.global_position.x > 0.5
		and car.ultima_aceleracion_ia > 0.5 and car.ultima_aceleracion_ia <= 1.0
		and car.ultimo_giro_ia >= -1.0 and car.ultimo_giro_ia <= 1.0
		and sensores_sincronizados,
		"VehiculoAgente ejecuta red.evaluar(lecturas_sensores) y avanza de forma finita"
	)

	mundo.queue_free()
	await process_frame


func _test_e_entrenador_genetico_y_presets_vacios() -> void:
	print("--- Test (e): EntrenadorGenetico seguro y 10 presets entrenados en Assets/Presets_ia/ ---")
	var ds := root.get_node_or_null("DatosSimulacion")
	_assert_true(ds != null, "Autoload DatosSimulacion presente")

	var celdas_antes: int = ds.celdas_asfalto.size() if ds != null else -1
	var meta_antes: bool = ds.tiene_meta if ds != null else false
	var cps_antes: int = ds.ruta_checkpoints.size() if ds != null else -1
	var mtimes_antes := {}
	for niv in range(1, 11):
		var ruta_p := CerebroEntrenado.ruta_para_nivel(niv)
		if FileAccess.file_exists(ruta_p):
			mtimes_antes[niv] = FileAccess.get_modified_time(ruta_p)

	# Instanciar EntrenadorGenetico NO debe entrenar ni mutar DatosSimulacion
	var entrenador := EntrenadorGenetico.new()
	_assert_true(entrenador != null, "EntrenadorGenetico se instancia sin iniciar entrenamiento")
	entrenador.free()

	var defs := EntrenadorGenetico.obtener_definiciones_niveles()
	var defs_ok := defs.size() == 10
	if defs_ok and ds != null:
		for i in range(10):
			var d_ent: Dictionary = defs[i]
			var d_ds: Dictionary = ds.NIVELES_IA[i]
			if d_ent["nivel"] != d_ds["nivel"] or d_ent["titulo"] != d_ds["titulo"] or d_ent["desc"] != d_ds["desc"]:
				defs_ok = false
				break
	_assert_true(defs_ok, "EntrenadorGenetico expone los 10 niveles en espanol coincidentes con DatosSimulacion")

	var c0 := EntrenadorGenetico.crear_circuito_entrenamiento(0)
	var c1 := EntrenadorGenetico.crear_circuito_entrenamiento(1)
	var c2 := EntrenadorGenetico.crear_circuito_entrenamiento(2)
	var a0 := ArquetiposPista.obtener_arquetipo(0, 16)
	var a1 := ArquetiposPista.obtener_arquetipo(1, 16)
	var a2 := ArquetiposPista.obtener_arquetipo(2, 16)
	_assert_true(
		bool(c0["validacion"]["valido"])
		and bool(c1["validacion"]["valido"])
		and bool(c2["validacion"]["valido"])
		and c0["validacion"]["checkpoints"].size() >= 6
		and c1["validacion"]["checkpoints"].size() >= 6
		and c2["validacion"]["checkpoints"].size() >= 6
		and int(c0["tam_celda"]) == 16 and int(c1["tam_celda"]) == 16 and int(c2["tam_celda"]) == 16
		and _diccionarios_celdas_iguales(c0["celdas"], a0["celdas"])
		and _diccionarios_celdas_iguales(c1["celdas"], a1["celdas"])
		and _diccionarios_celdas_iguales(c2["celdas"], a2["celdas"])
		and not _diccionarios_celdas_iguales(c0["celdas"], c1["celdas"])
		and not _diccionarios_celdas_iguales(c0["celdas"], c2["celdas"])
		and not _diccionarios_celdas_iguales(c1["celdas"], c2["celdas"]),
		"Circuitos de entrenamiento (0, 1, 2) reutilizan ArquetiposPista y validan en sentido horario"
	)

	# Verificación rápida en memoria (1 generación, 6 agentes, 20 ticks, guardar_en_disco=false)
	var tps_prev := Engine.physics_ticks_per_second
	var scale_prev := Engine.time_scale
	var steps_prev := Engine.max_physics_steps_per_frame

	var niveles_sim := await EntrenadorGenetico.entrenar_en_arbol(self, RUTA_PRESETS_IA, {
		"tamano_poblacion": 6,
		"max_generaciones": 1,
		"max_ticks": 20,
		"guardar_en_disco": false,
		"semilla": 12345,
	})

	var niveles_validos := niveles_sim.size() == 10
	if niveles_validos:
		for i in range(10):
			if not niveles_sim[i].es_valido() or niveles_sim[i].nivel != i + 1:
				niveles_validos = false
				break

	_assert_true(niveles_validos, "Simulacion rapida 1-gen en memoria retorna 10 CerebroEntrenado validos sin escribir disco")
	_assert_true(
		Engine.physics_ticks_per_second == tps_prev
		and is_equal_approx(Engine.time_scale, scale_prev)
		and Engine.max_physics_steps_per_frame == steps_prev,
		"EntrenadorGenetico restaura Engine.physics_ticks_per_second, time_scale y max_physics_steps_per_frame"
	)

	if ds != null:
		_assert_true(
			ds.celdas_asfalto.size() == celdas_antes
			and ds.tiene_meta == meta_antes
			and ds.ruta_checkpoints.size() == cps_antes,
			"EntrenadorGenetico no muta el estado de DatosSimulacion"
		)

	# Verificación estricta: guardar_en_disco=false no altera disco y los 10 presets existen y son válidos
	var presets_ok := true
	var sin_modificar := true
	for niv in range(1, 11):
		var ruta_p := CerebroEntrenado.ruta_para_nivel(niv)
		if not ResourceLoader.exists(ruta_p):
			presets_ok = false
			break
		if mtimes_antes.has(niv) and FileAccess.get_modified_time(ruta_p) != int(mtimes_antes[niv]):
			sin_modificar = false
		var rec := ResourceLoader.load(ruta_p) as CerebroEntrenado
		if rec == null or not rec.es_valido() or rec.nivel != niv:
			presets_ok = false
			break

	_assert_true(
		presets_ok and sin_modificar,
		"Assets/Presets_ia/ contiene nivel_01..nivel_10.tres validos y guardar_en_disco=false no los sobreescribe"
	)

	# Regresion curriculum: umbrales proporcionales en 3..99 y compuerta multi-geometria para niveles 6..9
	var u1 := EntrenadorGenetico.calcular_umbrales_curriculum(1)
	var u2 := EntrenadorGenetico.calcular_umbrales_curriculum(2)
	var u3 := EntrenadorGenetico.calcular_umbrales_curriculum(3)
	var u20 := EntrenadorGenetico.calcular_umbrales_curriculum(20)
	var u100 := EntrenadorGenetico.calcular_umbrales_curriculum(100)
	_assert_true(
		int(u1["gen_s"]) == 0 and int(u1["gen_horquilla"]) == 0
		and int(u2["gen_s"]) == 0 and int(u2["gen_horquilla"]) == 0
		and int(u3["gen_s"]) == 1 and int(u3["gen_horquilla"]) == 2
		and int(u20["gen_s"]) == 3 and int(u20["gen_horquilla"]) == 7
		and int(u100["gen_s"]) == 15 and int(u100["gen_horquilla"]) == 35,
		"calcular_umbrales_curriculum escala proporcionalmente en [3..99] y preserva <=2 (0/0) y >=100 (15/35)"
	)

	var red_cap := RedNeuronal.new()
	var cap_gen10: Dictionary = {}
	EntrenadorGenetico._registrar_captura_progresiva(cap_gen10, 10, 100, red_cap, 1200.0, 50, 4, 50, 4)
	var cap_gen20: Dictionary = {}
	EntrenadorGenetico._registrar_captura_progresiva(cap_gen20, 20, 100, red_cap, 1200.0, 50, 4, 50, 4)
	var cap_gen35_sin_todas: Dictionary = {}
	EntrenadorGenetico._registrar_captura_progresiva(cap_gen35_sin_todas, 35, 100, red_cap, 1200.0, 50, 4, 50, 4, false)
	var cap_gen35_con_todas: Dictionary = {}
	EntrenadorGenetico._registrar_captura_progresiva(cap_gen35_con_todas, 35, 100, red_cap, 1200.0, 50, 4, 50, 4, true)
	_assert_true(
		cap_gen10.has(2) and cap_gen10.has(5)
		and not cap_gen10.has(6) and not cap_gen10.has(7) and not cap_gen10.has(8) and not cap_gen10.has(9)
		and not cap_gen20.has(6) and not cap_gen20.has(7) and not cap_gen20.has(8) and not cap_gen20.has(9)
		and not cap_gen35_sin_todas.has(6) and not cap_gen35_sin_todas.has(7)
		and cap_gen35_con_todas.has(6) and cap_gen35_con_todas.has(7) and cap_gen35_con_todas.has(9),
		"Niveles 6..9 no se capturan prematuramente antes de activar las 3 geometrias"
	)

	var niveles_3gen := await EntrenadorGenetico.entrenar_en_arbol(self, RUTA_PRESETS_IA, {
		"tamano_poblacion": 4,
		"max_generaciones": 3,
		"max_ticks": 10,
		"guardar_en_disco": false,
		"semilla": 54321,
	})
	var gen3_ok := niveles_3gen.size() == 10
	if gen3_ok:
		for i in range(10):
			if not niveles_3gen[i].es_valido() or niveles_3gen[i].nivel != i + 1:
				gen3_ok = false
				break
	_assert_true(
		gen3_ok
		and Engine.physics_ticks_per_second == tps_prev
		and is_equal_approx(Engine.time_scale, scale_prev)
		and Engine.max_physics_steps_per_frame == steps_prev,
		"entrenar_en_arbol con max_generaciones=3 recorre progresion 3-geometrias, retorna 10 niveles validos y restaura Engine"
	)


func _test_f_arquetipos_pista_y_creador_mapa() -> void:
	print("--- Test (f): ArquetiposPista, carga editable en Vista 2 y layout responsivo ---")
	var lista := ArquetiposPista.obtener_lista()
	_assert_true(
		lista.size() == 3
		and int(lista[0]["id"]) == ArquetiposPista.OVALO_CLASICO
		and int(lista[1]["id"]) == ArquetiposPista.S_ENLAZADAS
		and int(lista[2]["id"]) == ArquetiposPista.HORQUILLA_TECNICA,
		"ArquetiposPista.obtener_lista() expone los 3 arquetipos esperados"
	)

	var arqs_por_id: Array[Dictionary] = []
	var claves_esperadas := ["ovalo_clasico", "s_enlazadas", "horquilla_tecnica"]
	for i in range(3):
		var arq := ArquetiposPista.obtener_arquetipo(i, 16)
		var arq_clave := ArquetiposPista.obtener_arquetipo(claves_esperadas[i], 16)
		arqs_por_id.append(arq)

		var celdas: Dictionary = arq.get("celdas", {})
		var meta: Vector2i = arq.get("celda_meta", Vector2i(-1, -1))
		var val: Dictionary = arq.get("validacion", {})
		var eje: Array = val.get("eje_central", [])
		var cps: Array = val.get("checkpoints", [])

		var dentro_limites := not celdas.is_empty()
		for k in celdas.keys():
			if not (k is Vector2i):
				dentro_limites = false
				break
			var c: Vector2i = k
			if c.x < 1 or c.x > 43 or c.y < 1 or c.y > 25:
				dentro_limites = false
				break

		var suma_cruz := _calcular_suma_cruz_horaria(eje)
		_assert_true(
			bool(val.get("valido", false))
			and cps.size() >= 6
			and celdas.has(meta)
			and dentro_limites
			and suma_cruz > 0.0
			and _diccionarios_celdas_iguales(celdas, arq_clave.get("celdas", {})),
			"Arquetipo %d (%s) es valido, horario (cruz=%.1f), dentro de [1..43, 1..25] y lookup por clave coincide" % [
				i, str(arq.get("nombre", "")), suma_cruz
			]
		)

	_assert_true(
		not _diccionarios_celdas_iguales(arqs_por_id[0]["celdas"], arqs_por_id[1]["celdas"])
		and not _diccionarios_celdas_iguales(arqs_por_id[0]["celdas"], arqs_por_id[2]["celdas"])
		and not _diccionarios_celdas_iguales(arqs_por_id[1]["celdas"], arqs_por_id[2]["celdas"]),
		"Los 3 arquetipos tienen geometrias de celdas distintas entre si"
	)

	var ds := root.get_node_or_null("DatosSimulacion")
	_assert_true(ds != null, "DatosSimulacion disponible para pruebas de Vista 2")
	if ds == null:
		return

	# Guardar estado previo de DatosSimulacion para restaurar al finalizar
	var prev_celdas: Dictionary = ds.celdas_asfalto.duplicate()
	var prev_meta: Vector2i = ds.celda_meta
	var prev_tiene_meta: bool = ds.tiene_meta
	var prev_cps: Array[Vector2i] = ds.ruta_checkpoints.duplicate()
	var prev_eje: Array[Vector2i] = ds.eje_central.duplicate()
	var prev_radios: Array[float] = ds.radios_eje.duplicate()
	var prev_rot: float = ds.rotacion_salida
	var prev_ancho: float = ds.ancho_pista

	ds.limpiar_pista()

	var escena := load(RUTA_CREADOR) as PackedScene
	_assert_true(escena != null, "creador_mapa.tscn carga correctamente")
	if escena != null:
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)

		var vista := escena.instantiate() as Control
		vp.add_child(vista)
		await _esperar_process_frames(3)

		_assert_true(
			vista.theme != null and vista.theme.resource_path == RUTA_TEMA_TELEMETRIA,
			"creador_mapa.tscn usa tema_telemetria.tres"
		)

		var todos_botones_animados := true
		for nodo in _obtener_todos_nodos(vista):
			if nodo is Button and not (nodo is OptionButton):
				if not (nodo is BotonAnimado):
					todos_botones_animados = false
					break
		_assert_true(todos_botones_animados, "Todos los Button de creador_mapa.tscn (incluidos arquetipos) usan BotonAnimado")

		var editor := vista.get("editor_pista") as Node2D
		var btn_confirmar := vista.get("btn_confirmar") as Button
		var btn_editar := vista.get("btn_editar") as Button
		var panel_lateral := vista.get("panel_lateral") as Control
		var btn_arq_ovalo := vista.get("btn_arq_ovalo") as Button
		var btn_arq_enlazadas := vista.get("btn_arq_enlazadas") as Button
		var btn_arq_horquilla := vista.get("btn_arq_horquilla") as Button

		_assert_true(
			editor != null and btn_confirmar != null and btn_editar != null and panel_lateral != null
			and btn_arq_ovalo != null and btn_arq_enlazadas != null and btn_arq_horquilla != null,
			"creador_mapa expone editor_pista, botones de control y los 3 botones de arquetipo"
		)

		if editor != null and btn_arq_ovalo != null and btn_arq_enlazadas != null and btn_arq_horquilla != null:
			var botones_arq := [btn_arq_ovalo, btn_arq_enlazadas, btn_arq_horquilla]
			for idx in range(botones_arq.size()):
				botones_arq[idx].pressed.emit()
				await _esperar_process_frames(2)
				var val_ed: Dictionary = editor.obtener_validacion()
				_assert_true(
					editor.celdas_asfalto.size() > 0
					and editor.tiene_meta
					and bool(val_ed.get("valido", false))
					and not btn_confirmar.disabled
					and editor.tile_map.visible
					and not editor.tile_map_final.visible
					and ds.celdas_asfalto.is_empty()
					and not ds.tiene_meta,
					"Click en arquetipo %d carga circuito valido editable sin mutar DatosSimulacion" % idx
				)

			# Probar edicion antes de confirmar: pincel, borrador y meta
			var celda_libre := Vector2i(-1, -1)
			for x in range(2, 43):
				for y in range(2, 25):
					var cand := Vector2i(x, y)
					if not editor.celdas_asfalto.has(cand):
						celda_libre = cand
						break
				if celda_libre != Vector2i(-1, -1):
					break

			var antes_pincel: int = editor.celdas_asfalto.size()
			editor.establecer_herramienta(editor.Herramienta.PINCEL)
			editor.establecer_grosor(1)
			editor._aplicar_herramienta_en_celda(celda_libre, false)
			var tras_pincel: int = editor.celdas_asfalto.size()

			editor.establecer_herramienta(editor.Herramienta.BORRADOR)
			editor._aplicar_herramienta_en_celda(celda_libre, false)
			var tras_borrador: int = editor.celdas_asfalto.size()

			var otra_meta := Vector2i(-1, -1)
			for k in editor.celdas_asfalto.keys():
				if k is Vector2i and k != editor.celda_meta:
					otra_meta = k
					break
			editor.establecer_herramienta(editor.Herramienta.META)
			editor._colocar_meta(otra_meta)

			_assert_true(
				tras_pincel == antes_pincel + 1
				and tras_borrador == antes_pincel
				and editor.celda_meta == otra_meta
				and editor.tiene_meta
				and ds.celdas_asfalto.is_empty(),
				"Pincel, borrador y colocacion de meta editan el arquetipo cargado antes de confirmar"
			)

			# Probar salida limpia desde vista previa al cargar otro arquetipo
			btn_arq_ovalo.pressed.emit()
			await _esperar_process_frames(2)
			btn_confirmar.pressed.emit()
			await _esperar_process_frames(2)
			var entro_previa: bool = editor.tile_map_final.visible and not editor.tile_map.visible and not editor._interaccion_habilitada

			ds.limpiar_pista()
			btn_arq_enlazadas.pressed.emit()
			await _esperar_process_frames(2)
			var salio_previa: bool = (
				editor.tile_map.visible
				and not editor.tile_map_final.visible
				and editor._interaccion_habilitada
				and panel_lateral.visible
				and not btn_editar.visible
				and btn_confirmar.text == "Confirmar Pista"
				and ds.celdas_asfalto.is_empty()
			)
			_assert_true(entro_previa and salio_previa, "Cargar arquetipo en vista previa vuelve a modo edicion sin mutar DatosSimulacion")

			# Confirmar arquetipo valido persiste en DatosSimulacion
			btn_confirmar.pressed.emit()
			await _esperar_process_frames(2)
			_assert_true(
				ds.celdas_asfalto.size() == editor.celdas_asfalto.size()
				and ds.tiene_meta
				and ds.celda_meta == editor.celda_meta
				and ds.ruta_checkpoints.size() >= 3,
				"Confirmar Pista sobre arquetipo persiste pista y checkpoints en DatosSimulacion"
			)

		vp.queue_free()
		await _esperar_process_frames(2)

		# Pruebas de layout responsivo en 1280x720 y 1920x1080
		for res in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			var vp_res := SubViewport.new()
			vp_res.size = res
			vp_res.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp_res)

			var vista_res := escena.instantiate() as Control
			vp_res.add_child(vista_res)
			await _esperar_process_frames(3)
			var btn_h := vista_res.get("btn_arq_horquilla") as Button
			if btn_h != null:
				btn_h.pressed.emit()
				await _esperar_process_frames(2)

			var problemas := _validar_geometria_vista(vista_res, res)
			var scroll := vista_res.get_node_or_null("Layout/Cuerpo/PanelLateral/Margin/ScrollHerramientas") as ScrollContainer
			var sin_overflow := false
			var vbar_max := -1.0
			var scroll_h := -1.0
			if scroll != null:
				var vbar := scroll.get_v_scroll_bar()
				vbar_max = vbar.max_value
				scroll_h = scroll.size.y
				sin_overflow = vbar_max <= scroll_h + 1.5

			_assert_true(
				problemas.is_empty() and sin_overflow,
				"Layout creador_mapa %dx%d sin recortes, solapamientos ni overflow (vbar=%.1f <= %.1f; errs=%s)" % [
					res.x, res.y, vbar_max, scroll_h, str(problemas)
				]
			)
			vp_res.queue_free()
			await _esperar_process_frames(2)

	# Restaurar estado previo de DatosSimulacion
	if prev_tiene_meta and not prev_celdas.is_empty():
		ds.guardar_pista(prev_celdas, prev_meta, prev_cps, prev_rot, prev_eje, prev_radios, prev_ancho)
	else:
		ds.limpiar_pista()


func _esperar_process_frames(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _diccionarios_celdas_iguales(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or bool(a[k]) != bool(b[k]):
			return false
	return true


func _calcular_suma_cruz_horaria(ciclo: Array) -> float:
	if ciclo.size() < 3:
		return 0.0
	var cx := 0.0
	var cy := 0.0
	for p in ciclo:
		cx += float(p.x)
		cy += float(p.y)
	cx /= float(ciclo.size())
	cy /= float(ciclo.size())

	var suma := 0.0
	for i in range(ciclo.size()):
		var a: Vector2i = ciclo[i]
		var b: Vector2i = ciclo[(i + 1) % ciclo.size()]
		var ax := float(a.x) - cx
		var ay := float(a.y) - cy
		var bx := float(b.x) - cx
		var by := float(b.y) - cy
		suma += ax * by - ay * bx
	return suma


func _validar_geometria_vista(raiz: Control, res: Vector2i) -> Array[String]:
	var errores: Array[String] = []
	var rect_vp := Rect2(Vector2(-1.0, -1.0), Vector2(res) + Vector2(2.0, 2.0))

	var todos := _obtener_todos_nodos(raiz)
	for nodo in todos:
		if not (nodo is Control):
			continue
		var ctrl := nodo as Control
		if not ctrl.is_visible_in_tree():
			continue
		if ctrl is ScrollBar:
			continue
		var r := ctrl.get_global_rect()
		if r.size.x < 0.0 or r.size.y < 0.0 or not rect_vp.encloses(r):
			errores.append("Fuera de viewport: %s (%s)" % [ctrl.name, str(r)])

	for nodo in todos:
		if nodo is Control and (nodo as Control).is_visible_in_tree():
			var hijos_visibles: Array[Control] = []
			for ch in nodo.get_children():
				if ch is Control and (ch as Control).is_visible_in_tree():
					if ch.name == "Fondo" or ch is ScrollBar:
						continue
					hijos_visibles.append(ch as Control)
			for i in range(hijos_visibles.size()):
				for j in range(i + 1, hijos_visibles.size()):
					var r1 := hijos_visibles[i].get_global_rect()
					var r2 := hijos_visibles[j].get_global_rect()
					var inter := r1.intersection(r2)
					if inter.size.x > 1.0 and inter.size.y > 1.0:
						errores.append("Solapamiento %s vs %s (%s)" % [
							hijos_visibles[i].name, hijos_visibles[j].name, str(inter.size)
						])
	return errores


func _obtener_todos_nodos(raiz: Node) -> Array[Node]:
	var res: Array[Node] = [raiz]
	for ch in raiz.get_children():
		res.append_array(_obtener_todos_nodos(ch))
	return res
