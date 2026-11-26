extends SceneTree

## Pruebas automatizadas Fase 2: CerebroEntrenado, RedNeuronal (7 -> 6 -> 2),
## integración con VehiculoAgente y preparación segura de EntrenadorGenetico.
## NOTA: Nunca ejecuta entrenamiento real ni escribe archivos .tres en res://Assets/Presets_ia/.

const RUTA_VEHICULO := "res://Assets/Escenas/Componentes/vehiculo_agente.tscn"
const RUTA_PRESETS_IA := "res://Assets/Presets_ia"

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
	print("--- Test (e): EntrenadorGenetico seguro y Assets/Presets_ia/ sin .tres ---")
	var ds := root.get_node_or_null("DatosSimulacion")
	_assert_true(ds != null, "Autoload DatosSimulacion presente")

	var celdas_antes: int = ds.celdas_asfalto.size() if ds != null else -1
	var meta_antes: bool = ds.tiene_meta if ds != null else false
	var cps_antes: int = ds.ruta_checkpoints.size() if ds != null else -1

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
	_assert_true(
		bool(c0["validacion"]["valido"]) and bool(c1["validacion"]["valido"]),
		"Circuitos de entrenamiento (Ovalo y Chicana) validan en sentido horario"
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

	# Verificación estricta: Assets/Presets_ia/ contiene UNICAMENTE .gitkeep (cero .tres)
	var dir := DirAccess.open(RUTA_PRESETS_IA)
	var archivos: Array[String] = []
	var tiene_gitkeep := false
	var tiene_tres := false
	if dir != null:
		dir.list_dir_begin()
		var item := dir.get_next()
		while item != "":
			if item != "." and item != "..":
				archivos.append(item)
				if item == ".gitkeep":
					tiene_gitkeep = true
				if item.ends_with(".tres"):
					tiene_tres = true
			item = dir.get_next()
		dir.list_dir_end()

	_assert_true(
		tiene_gitkeep and not tiene_tres and archivos.size() == 1,
		"Assets/Presets_ia/ contiene unicamente .gitkeep y cero .tres (archivos: %s)" % str(archivos)
	)
