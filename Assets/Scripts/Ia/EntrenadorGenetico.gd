class_name EntrenadorGenetico
extends SceneTree

## Herramienta de entrenamiento genético en 100% GDScript para generar
## los 10 niveles progresivos de IA (nivel_01.tres .. nivel_10.tres).
##
## IMPORTANTE: Cargar, instanciar o verificar este script NUNCA inicia entrenamiento.
## Para entrenar desde consola ejecute:
##   godot --headless --path . --script res://Assets/Scripts/Ia/EntrenadorGenetico.gd -- --entrenar

const RUTA_PRESETS := "res://Assets/Presets_ia"
const RUTA_VEHICULO := "res://Assets/Escenas/Componentes/vehiculo_agente.tscn"
const RUTA_CHECKPOINT := "res://Assets/Escenas/Componentes/checkpoint.tscn"
const NUM_GENES: int = 170 # 144 + 8 + 16 + 2

const NIVELES_DEFECTO: Array[Dictionary] = [
	{"nivel": 1, "titulo": "Novato Caótico", "desc": "Pesos sin refinar; acelera sin frenar y gira erráticamente."},
	{"nivel": 2, "titulo": "Primeros Reflejos", "desc": "Detecta el muro frontal tarde; intenta esquivar pero roza bordes."},
	{"nivel": 3, "titulo": "Cauteloso Lento", "desc": "Mantiene baja aceleración constante; supera curvas abiertas."},
	{"nivel": 4, "titulo": "Zig-Zag Nervioso", "desc": "Completa rectas y curvas suaves, pero oscila entre los bordes."},
	{"nivel": 5, "titulo": "Conductor Básico", "desc": "Completa circuitos sencillos a velocidad media sin chocar."},
	{"nivel": 6, "titulo": "Trazada Estable", "desc": "Estabiliza la dirección usando los sensores laterales de ±45°."},
	{"nivel": 7, "titulo": "Control de Frenada", "desc": "Reduce aceleración al detectar proximidad en sensores frontales."},
	{"nivel": 8, "titulo": "Piloto Ágil", "desc": "Aprovecha rectas a alta velocidad y anticipa giros cerrados."},
	{"nivel": 9, "titulo": "Ápice Óptimo", "desc": "Busca el interior de las curvas para minimizar distancia."},
	{"nivel": 10, "titulo": "Maestro Autónomo", "desc": "Conducción fluida, rápida y adaptable a cualquier circuito."},
]


func _init() -> void:
	# Nunca iniciar entrenamiento al cargar, compilar (--check-only) o hacer .new()
	pass


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--entrenar" in args or "--train" in args:
		call_deferred("_ejecutar_cli")
		return

	print("EntrenadorGenetico: Modo seguro (no se ejecutó entrenamiento).")
	print("Para entrenar y guardar nivel_01.tres..nivel_10.tres en %s ejecute:" % RUTA_PRESETS)
	print("  godot --headless --path . --script res://Assets/Scripts/Ia/EntrenadorGenetico.gd -- --entrenar")
	quit(0)


func _ejecutar_cli() -> void:
	var args := OS.get_cmdline_user_args()
	var opciones := {
		"tamano_poblacion": 60,
		"max_generaciones": 120,
		"max_ticks": 1800,
		"elitismo": 4,
		"guardar_en_disco": true,
		"semilla": 202611,
		"imprimir_progreso": true,
	}
	for arg in args:
		if arg.begins_with("--gen="):
			opciones["max_generaciones"] = maxi(1, int(arg.substr(6)))
		elif arg.begins_with("--pop="):
			opciones["tamano_poblacion"] = maxi(4, int(arg.substr(6)))
		elif arg.begins_with("--ticks="):
			opciones["max_ticks"] = maxi(60, int(arg.substr(8)))
		elif arg.begins_with("--seed="):
			opciones["semilla"] = int(arg.substr(7))

	print("EntrenadorGenetico: Iniciando entrenamiento genético (Niveles 1..10) | pop=%d gen=%d ticks=%d seed=%d..." % [
		int(opciones["tamano_poblacion"]),
		int(opciones["max_generaciones"]),
		int(opciones["max_ticks"]),
		int(opciones["semilla"]),
	])
	var resultados := await entrenar_en_arbol(self, RUTA_PRESETS, opciones)
	print("EntrenadorGenetico: Entrenamiento completado (%d niveles)." % resultados.size())
	quit(0)


func entrenar_todos_los_niveles(
	carpeta_salida: String = RUTA_PRESETS,
	arbol: SceneTree = null,
	opciones: Dictionary = {}
) -> Array[CerebroEntrenado]:
	var arbol_objetivo := arbol
	if arbol_objetivo == null:
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			arbol_objetivo = ml as SceneTree
		elif get_root() != null:
			arbol_objetivo = self
	return await entrenar_en_arbol(arbol_objetivo, carpeta_salida, opciones)


static func entrenar_en_arbol(
	arbol: SceneTree,
	carpeta_salida: String = RUTA_PRESETS,
	opciones: Dictionary = {}
) -> Array[CerebroEntrenado]:
	var resultados: Array[CerebroEntrenado] = []
	if arbol == null or arbol.root == null:
		push_error("EntrenadorGenetico: Se requiere un SceneTree activo con root.")
		return resultados

	var tamano_poblacion: int = maxi(4, int(opciones.get("tamano_poblacion", 60)))
	var max_generaciones: int = maxi(1, int(opciones.get("max_generaciones", 120)))
	var max_ticks: int = maxi(10, int(opciones.get("max_ticks", 1800)))
	var elitismo: int = clampi(int(opciones.get("elitismo", 4)), 1, tamano_poblacion)
	var guardar_en_disco: bool = bool(opciones.get("guardar_en_disco", true))
	var imprimir_progreso: bool = bool(opciones.get("imprimir_progreso", false))
	var semilla: int = int(opciones.get("semilla", 202611))

	var rng := RandomNumberGenerator.new()
	rng.seed = semilla

	var circuito_ovalo := crear_circuito_entrenamiento(ArquetiposPista.OVALO_CLASICO)
	var circuito_s := crear_circuito_entrenamiento(ArquetiposPista.S_ENLAZADAS)
	var circuito_horquilla := crear_circuito_entrenamiento(ArquetiposPista.HORQUILLA_TECNICA)
	if not circuito_ovalo.get("validacion", {}).get("valido", false):
		push_error("EntrenadorGenetico: Circuito Óvalo inválido.")
		return resultados
	if not circuito_s.get("validacion", {}).get("valido", false):
		push_error("EntrenadorGenetico: Circuito S-Enlazadas inválido.")
		return resultados
	if not circuito_horquilla.get("validacion", {}).get("valido", false):
		push_error("EntrenadorGenetico: Circuito Horquilla Técnica inválido.")
		return resultados

	var poblacion: Array[RedNeuronal] = []
	var inicio_sesgado := int(floor(float(tamano_poblacion) * 0.85))
	for i in range(tamano_poblacion):
		var red := RedNeuronal.new()
		if i < inicio_sesgado or max_generaciones < 10:
			red.inicializar_aleatorio(semilla + i * 17, 1.2)
		else:
			red.inicializar_aleatorio(semilla + i * 17, 0.55)
			red.sesgos_salida[0] = rng.randf_range(0.35, 0.90)
		poblacion.append(red)

	var capturas: Dictionary = {} # nivel (int) -> {"red": RedNeuronal, "fitness": float}

	# Guardar snapshot de Nivel 1 (Novato Caótico) desde la generación inicial sin refinar
	var novato := poblacion[0].clonar()
	capturas[1] = {"red": novato, "fitness": 0.0}

	var mejor_global_red: RedNeuronal = poblacion[0].clonar()
	var mejor_global_fitness: float = -1.0
	var hof_buckets: Dictionary = {0: [novato.clonar()]}

	var tps_orig := Engine.physics_ticks_per_second
	var scale_orig := Engine.time_scale
	var max_steps_orig := Engine.max_physics_steps_per_frame

	Engine.physics_ticks_per_second = 3600
	Engine.time_scale = 60.0
	Engine.max_physics_steps_per_frame = 240

	var umbrales := calcular_umbrales_curriculum(max_generaciones)
	var gen_s := int(umbrales["gen_s"])
	var gen_horquilla := int(umbrales["gen_horquilla"])

	for gen in range(max_generaciones):
		var stats_ovalo := await _evaluar_poblacion_en_pista(arbol, poblacion, circuito_ovalo, max_ticks, 0.70)
		var fitnesses := PackedFloat64Array()
		fitnesses.resize(tamano_poblacion)

		var eval_s := gen >= gen_s
		var stats_s: Array[Dictionary] = []
		if eval_s:
			stats_s = await _evaluar_poblacion_en_pista(arbol, poblacion, circuito_s, max_ticks, 0.70)

		var eval_horquilla := gen >= gen_horquilla
		var stats_horquilla: Array[Dictionary] = []
		if eval_horquilla:
			stats_horquilla = await _evaluar_poblacion_en_pista(arbol, poblacion, circuito_horquilla, max_ticks, 0.70)

		var todas_geometrias := eval_s and eval_horquilla
		var mejor_idx := 0
		var mejor_fit := -1.0
		var mejor_cps := 0
		var mejor_vueltas := 1
		var mejor_cps_ambas := 0
		var mejor_vueltas_ambas := 0
		var mejor_total_cps := 0

		for i in range(tamano_poblacion):
			var so: Dictionary = stats_ovalo[i]
			var fit_o: float = float(so["fitness"])
			var cps: int = int(so["checkpoints"])
			var vueltas: int = int(so["vueltas"])
			if cps == 0 and int(so["ticks_reversa"]) > int(so["ticks_vivos"]) * 0.5:
				fit_o *= 0.2
			if vueltas >= 2:
				fit_o += 300.0

			var fit := fit_o
			var total_cps_i := cps
			var cps_ambas := 0
			var vueltas_ambas := 0

			if eval_s and i < stats_s.size() and not eval_horquilla:
				var ss: Dictionary = stats_s[i]
				var fit_s := float(ss["fitness"])
				if int(ss["checkpoints"]) == 0 and int(ss["ticks_reversa"]) > int(ss["ticks_vivos"]) * 0.5:
					fit_s *= 0.2
				if int(ss["vueltas"]) >= 2:
					fit_s += 300.0
				fit = 0.40 * fit_o + 0.60 * fit_s
				total_cps_i += int(ss["checkpoints"])
			elif todas_geometrias and i < stats_s.size() and i < stats_horquilla.size():
				var ss: Dictionary = stats_s[i]
				var sh: Dictionary = stats_horquilla[i]
				var fit_s := float(ss["fitness"])
				var fit_h := float(sh["fitness"])
				if int(ss["checkpoints"]) == 0 and int(ss["ticks_reversa"]) > int(ss["ticks_vivos"]) * 0.5:
					fit_s *= 0.2
				if int(sh["checkpoints"]) == 0 and int(sh["ticks_reversa"]) > int(sh["ticks_vivos"]) * 0.5:
					fit_h *= 0.2
				if int(ss["vueltas"]) >= 2:
					fit_s += 300.0
				if int(sh["vueltas"]) >= 2:
					fit_h += 300.0
				fit = 0.25 * fit_o + 0.35 * fit_s + 0.40 * fit_h
				if vueltas >= 2 and int(ss["vueltas"]) >= 2 and int(sh["vueltas"]) >= 2:
					fit += 600.0
				cps_ambas = mini(cps, mini(int(ss["checkpoints"]), int(sh["checkpoints"])))
				vueltas_ambas = mini(vueltas, mini(int(ss["vueltas"]), int(sh["vueltas"])))
				total_cps_i += int(ss["checkpoints"]) + int(sh["checkpoints"])

			fitnesses[i] = fit
			if fit > mejor_fit:
				mejor_fit = fit
				mejor_idx = i
				mejor_cps = cps
				mejor_vueltas = vueltas
				mejor_cps_ambas = cps_ambas
				mejor_vueltas_ambas = vueltas_ambas
				mejor_total_cps = total_cps_i

		var campeon_gen := poblacion[mejor_idx].clonar()
		if mejor_fit > mejor_global_fitness:
			mejor_global_fitness = mejor_fit
			mejor_global_red = campeon_gen.clonar()

		_registrar_captura_progresiva(
			capturas,
			gen,
			max_generaciones,
			campeon_gen,
			mejor_fit,
			mejor_cps,
			mejor_vueltas,
			mejor_cps_ambas,
			mejor_vueltas_ambas,
			todas_geometrias
		)

		if max_generaciones >= 20:
			_acumular_candidatos_hof(hof_buckets, poblacion, fitnesses, mejor_idx, mejor_total_cps)

		if imprimir_progreso and (gen == 0 or (gen + 1) % 10 == 0 or gen == max_generaciones - 1):
			var msg_s := "-"
			var msg_h := "-"
			if eval_s and mejor_idx < stats_s.size():
				msg_s = "%dcp/v%d" % [int(stats_s[mejor_idx]["checkpoints"]), int(stats_s[mejor_idx]["vueltas"])]
			if eval_horquilla and mejor_idx < stats_horquilla.size():
				msg_h = "%dcp/v%d" % [int(stats_horquilla[mejor_idx]["checkpoints"]), int(stats_horquilla[mejor_idx]["vueltas"])]
			print("[Gen %3d/%3d] fit=%.1f | Ovalo=%dcp/v%d | S=%s | Horq=%s | Buckets=%d" % [
				gen + 1, max_generaciones, mejor_fit, mejor_cps, mejor_vueltas, msg_s, msg_h, hof_buckets.size()
			])

		if gen < max_generaciones - 1:
			var tasa_mut := lerpf(0.18, 0.08, float(gen) / float(maxi(1, max_generaciones - 1)))
			var int_mut := lerpf(0.32, 0.12, float(gen) / float(maxi(1, max_generaciones - 1)))
			if max_generaciones >= 20:
				poblacion = _evolucionar_neuro_avanzado(poblacion, fitnesses, rng, elitismo, tasa_mut, int_mut, semilla + (gen + 1) * 997)
			else:
				poblacion = evolucionar_generacion(poblacion, fitnesses, rng, elitismo, tasa_mut, int_mut)

	if max_generaciones >= 20:
		var hall_of_fame := _aplanar_hof_buckets(hof_buckets)
		await _seleccionar_niveles_desde_hof(
			arbol,
			hall_of_fame,
			capturas,
			circuito_ovalo,
			circuito_s,
			circuito_horquilla,
			maxi(1800, max_ticks),
			imprimir_progreso
		)

	# Restaurar reloj del motor siempre al finalizar
	Engine.physics_ticks_per_second = tps_orig
	Engine.time_scale = scale_orig
	Engine.max_physics_steps_per_frame = max_steps_orig

	# Asegurar niveles 1..10 completos
	for nivel in range(1, 11):
		var datos_cap: Dictionary = capturas.get(nivel, {"red": mejor_global_red, "fitness": mejor_global_fitness})
		var red_nivel: RedNeuronal = datos_cap["red"]
		var fit_nivel: float = float(datos_cap["fitness"])
		var recurso := crear_recurso_nivel(nivel, red_nivel, fit_nivel)
		resultados.append(recurso)

		if guardar_en_disco:
			_guardar_recurso_en_carpeta(recurso, carpeta_salida, nivel)

	return resultados


static func calcular_umbrales_curriculum(max_generaciones: int) -> Dictionary:
	var max_gen := maxi(1, max_generaciones)
	if max_gen <= 2:
		return {"gen_s": 0, "gen_horquilla": 0}
	if max_gen >= 100:
		return {"gen_s": 15, "gen_horquilla": 35}
	var gen_s := mini(15, maxi(1, int(floor(float(max_gen) * 0.15))))
	var gen_horquilla := mini(35, maxi(2, int(floor(float(max_gen) * 0.35))))
	return {"gen_s": gen_s, "gen_horquilla": gen_horquilla}


static func _registrar_captura_progresiva(
	capturas: Dictionary,
	gen: int,
	max_gen: int,
	campeon: RedNeuronal,
	fit: float,
	cps: int,
	vueltas: int,
	cps_ambas: int,
	vueltas_ambas: int,
	todas_geometrias: bool = true
) -> void:
	var umbrales := calcular_umbrales_curriculum(max_gen)
	var multi_geo_activa := todas_geometrias and gen >= int(umbrales["gen_s"]) and gen >= int(umbrales["gen_horquilla"])
	var cps_multi := cps_ambas if multi_geo_activa else 0
	var vueltas_multi := vueltas_ambas if multi_geo_activa else 0
	var prog := float(gen + 1) / float(maxi(1, max_gen))
	if not capturas.has(2) and (cps >= 3 or prog >= 0.05):
		capturas[2] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(3) and (cps >= 6 or prog >= 0.12):
		capturas[3] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(4) and (cps >= 13 or prog >= 0.20):
		capturas[4] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(5) and (vueltas >= 2 or prog >= 0.30):
		capturas[5] = {"red": campeon.clonar(), "fitness": fit}
	if multi_geo_activa:
		if not capturas.has(6) and (vueltas_multi >= 2 or (cps_multi >= 12 and prog >= 0.42)):
			capturas[6] = {"red": campeon.clonar(), "fitness": fit}
		if not capturas.has(7) and (vueltas_multi >= 3 or prog >= 0.55):
			capturas[7] = {"red": campeon.clonar(), "fitness": fit}
		if not capturas.has(8) and ((vueltas_multi >= 3 and prog >= 0.68) or prog >= 0.72):
			capturas[8] = {"red": campeon.clonar(), "fitness": fit}
		if not capturas.has(9) and (vueltas_multi >= 4 or prog >= 0.85):
			capturas[9] = {"red": campeon.clonar(), "fitness": fit}
	if gen == max_gen - 1:
		capturas[10] = {"red": campeon.clonar(), "fitness": fit}


static func _evaluar_poblacion_en_pista(
	arbol: SceneTree,
	poblacion: Array[RedNeuronal],
	circuito: Dictionary,
	max_ticks: int,
	perfil_fisico: float
) -> Array[Dictionary]:
	var resultados: Array[Dictionary] = []
	resultados.resize(poblacion.size())

	var validacion: Dictionary = circuito["validacion"]
	var cps: Array[Vector2i] = validacion["checkpoints"]
	var eje_activo: Array[Vector2i] = validacion.get("eje_central", [] as Array[Vector2i])
	var radios_activos: Array[float] = validacion.get("radios_eje", [] as Array[float])
	var ancho_activo: float = 48.0
	var tam: float = float(circuito["tam_celda"])
	var pos_salida := Vector2(circuito["celda_meta"]) * tam + Vector2.ONE * (tam * 0.5)
	var rot_salida := float(validacion["rotacion_salida"])
	if not cps.is_empty():
		var pos_cp0 := Vector2(cps[0]) * tam + Vector2.ONE * (tam * 0.5)
		rot_salida = (pos_cp0 - pos_salida).angle()

	var mundo := Node2D.new()
	mundo.name = "MundoEntrenamientoTemp"
	arbol.root.add_child(mundo)

	var pista_node := Node2D.new()
	pista_node.name = "PistaEntrenamiento"
	mundo.add_child(pista_node)
	ConstructorPista.construir_pista_suave(pista_node, circuito["celdas"], true)

	var escena_cp := ResourceLoader.load(RUTA_CHECKPOINT) as PackedScene
	var posiciones_cp: Array[Vector2] = []
	for i in range(cps.size()):
		var pos_cp := Vector2(cps[i]) * tam + Vector2.ONE * (tam * 0.5)
		posiciones_cp.append(pos_cp)
		var cp_node := escena_cp.instantiate() as CheckpointArea
		cp_node.id_checkpoint = i
		cp_node.position = pos_cp
		var idx_eje := eje_activo.find(cps[i])
		var radio_local := float(radios_activos[idx_eje]) if idx_eje >= 0 and idx_eje < radios_activos.size() else 0.0
		var radio_cp := clampf(maxf(radio_local, ancho_activo * 0.5) + 2.0, 16.0, 48.0)
		var col_shape := cp_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col_shape != null:
			var forma := CircleShape2D.new()
			forma.radius = radio_cp
			col_shape.shape = forma
		mundo.add_child(cp_node)

	var escena_car := ResourceLoader.load(RUTA_VEHICULO) as PackedScene
	var coches: Array[VehiculoAgente] = []
	var prev_pos: Array[Vector2] = []
	var prev_giro: PackedFloat64Array = PackedFloat64Array()
	prev_giro.resize(poblacion.size())
	prev_giro.fill(0.0)
	var suma_oscilacion: PackedFloat64Array = PackedFloat64Array()
	suma_oscilacion.resize(poblacion.size())
	suma_oscilacion.fill(0.0)
	var ticks_reversa: PackedInt32Array = PackedInt32Array()
	ticks_reversa.resize(poblacion.size())
	ticks_reversa.fill(0)
	var distancias: PackedFloat64Array = PackedFloat64Array()
	distancias.resize(poblacion.size())
	distancias.fill(0.0)
	var ticks_vivos: PackedInt32Array = PackedInt32Array()
	ticks_vivos.resize(poblacion.size())
	ticks_vivos.fill(0)

	var cfg := {
		"nombre": "AgenteEntrenamiento",
		"color": Color.CYAN,
		"velocidad_maxima": perfil_fisico,
		"aceleracion": perfil_fisico,
		"frenado": perfil_fisico,
		"control": perfil_fisico,
		"agarre": perfil_fisico,
		"nivel_ia": 1,
		"es_humano": false,
	}

	var cps_packed := PackedVector2Array(posiciones_cp)
	for i in range(poblacion.size()):
		var car := escena_car.instantiate() as VehiculoAgente
		car.mostrar_sensores = false
		car.mostrar_estela = false
		mundo.add_child(car)
		car.configurar(cfg)
		car.posiciones_checkpoints = cps_packed
		car.cerebro = poblacion[i]
		car.reiniciar_estado(pos_salida, rot_salida, cps.size())
		coches.append(car)
		prev_pos.append(pos_salida)

	var stepper := _StepperEvaluacion.new()
	stepper.inicializar(coches, prev_pos, max_ticks)
	mundo.add_child(stepper)

	if not stepper.terminado:
		await stepper.evaluacion_completada

	for i in range(coches.size()):
		var car := coches[i]
		var dist_i: float = stepper.distancias[i]
		var ticks_i: int = stepper.ticks_vivos[i]
		var osc_i: float = stepper.suma_oscilacion[i]
		var rev_i: int = stepper.ticks_reversa[i]
		var siguiente_cp := (car.ultimo_checkpoint + 1) % maxi(1, cps.size())
		var dist_sig := car.global_position.distance_to(posiciones_cp[siguiente_cp]) if not posiciones_cp.is_empty() else 0.0
		var progreso_cp := 1.0 - clampf(dist_sig / 200.0, 0.0, 1.0)
		var fit := calcular_fitness(
			car.checkpoints_cruzados,
			car.vuelta_actual,
			progreso_cp,
			dist_i,
			ticks_i,
			car.esta_chocado
		)
		var tv := maxi(1, ticks_i)
		var duracion_s := float(tv) / 60.0
		var vel_media := dist_i / duracion_s
		var osc_media := osc_i / float(tv)
		resultados[i] = {
			"fitness": fit,
			"checkpoints": car.checkpoints_cruzados,
			"vueltas": car.vuelta_actual,
			"distancia": dist_i,
			"ticks_vivos": ticks_i,
			"vel_media": vel_media,
			"oscilacion": osc_media,
			"ticks_reversa": rev_i,
			"chocado": car.esta_chocado,
			"motivo": car.motivo_choque,
		}

	if is_instance_valid(mundo):
		mundo.queue_free()
		await arbol.process_frame

	return resultados


static func _evolucionar_neuro_avanzado(
	poblacion: Array[RedNeuronal],
	fitnesses: PackedFloat64Array,
	rng: RandomNumberGenerator,
	elitismo: int,
	tasa_mut: float,
	int_mut: float,
	semilla_inm: int
) -> Array[RedNeuronal]:
	var n := poblacion.size()
	var nueva: Array[RedNeuronal] = []
	if n == 0:
		return nueva

	var indices: Array[int] = []
	for i in range(n):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var fa := fitnesses[a] if a < fitnesses.size() and is_finite(fitnesses[a]) else 0.0
		var fb := fitnesses[b] if b < fitnesses.size() and is_finite(fitnesses[b]) else 0.0
		return fa > fb
	)

	var num_elites := clampi(elitismo, 1, n)
	for e in range(num_elites):
		nueva.append(poblacion[indices[e]].clonar())

	var top_k := mini(8, n)
	var num_inm := mini(2, maxi(0, n - num_elites))
	var objetivo_mut := num_elites + int(floor(float(n - num_elites - num_inm) * 0.58))

	# 1) Clonacion mutada desde top_k (evita destruir topologia por competing conventions)
	while nueva.size() < objetivo_mut:
		var padre := poblacion[indices[rng.randi_range(0, top_k - 1)]].clonar()
		if nueva.size() % 2 == 0:
			padre.mutar(maxf(0.06, tasa_mut * 0.65), maxf(0.06, int_mut * 0.5), rng)
		else:
			padre.mutar(tasa_mut, int_mut, rng)
		nueva.append(padre)

	# 2) Cruce por torneo + mutacion suave
	while nueva.size() < n - num_inm:
		var pa := seleccion_torneo(poblacion, fitnesses, rng, mini(4, n))
		var pb := seleccion_torneo(poblacion, fitnesses, rng, mini(4, n))
		var hijo := RedNeuronal.cruzar(pa, pb, rng, 0.70)
		hijo.mutar(tasa_mut * 0.7, int_mut * 0.65, rng)
		nueva.append(hijo)

	# 3) Inmigrantes frescos para mantener diversidad
	for inm in range(num_inm):
		var red_inm := RedNeuronal.new()
		red_inm.inicializar_aleatorio(semilla_inm + inm * 37, 0.75)
		red_inm.sesgos_salida[0] = rng.randf_range(0.25, 0.85)
		nueva.append(red_inm)

	return nueva


static func _acumular_candidatos_hof(
	hof_buckets: Dictionary,
	poblacion: Array[RedNeuronal],
	fitnesses: PackedFloat64Array,
	mejor_idx: int,
	mejor_total_cps: int
) -> void:
	var indices: Array[int] = []
	for i in range(poblacion.size()):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return fitnesses[a] > fitnesses[b]
	)
	var muestras: Array[int] = [mejor_idx]
	for frac in [0.10, 0.25, 0.45, 0.65, 0.80]:
		var pos := clampi(int(floor(float(indices.size()) * frac)), 0, indices.size() - 1)
		if not (indices[pos] in muestras):
			muestras.append(indices[pos])

	var bucket_camp := mini(14, int(mejor_total_cps / 10))
	for m_pos in range(muestras.size()):
		var idx := muestras[m_pos]
		if idx < 0 or idx >= poblacion.size():
			continue
		var cand := poblacion[idx]
		var bucket := bucket_camp if m_pos == 0 else maxi(0, bucket_camp - m_pos)
		if not hof_buckets.has(bucket):
			hof_buckets[bucket] = [] as Array[RedNeuronal]
		var lista: Array = hof_buckets[bucket]
		var ya_esta := false
		for existente in lista:
			if _distancia_pesos(existente, cand) < 0.15:
				ya_esta = true
				break
		if not ya_esta:
			if lista.size() >= 10:
				lista.remove_at(0)
			lista.append(cand.clonar())


static func _aplanar_hof_buckets(hof_buckets: Dictionary) -> Array[RedNeuronal]:
	var resultado: Array[RedNeuronal] = []
	var claves := hof_buckets.keys()
	claves.sort()
	for k in claves:
		var lista: Array = hof_buckets[k]
		for r in lista:
			resultado.append((r as RedNeuronal).clonar())
	return resultado


static func _distancia_pesos(a: RedNeuronal, b: RedNeuronal) -> float:
	var suma := 0.0
	var n := mini(a.pesos_oculta.size(), b.pesos_oculta.size())
	for i in range(0, n, 4):
		suma += absf(a.pesos_oculta[i] - b.pesos_oculta[i])
	var m := mini(a.pesos_salida.size(), b.pesos_salida.size())
	for k in range(m):
		suma += absf(a.pesos_salida[k] - b.pesos_salida[k])
	return suma


static func _seleccionar_niveles_desde_hof(
	arbol: SceneTree,
	hof: Array[RedNeuronal],
	capturas: Dictionary,
	circuito_ovalo: Dictionary,
	circuito_s: Dictionary,
	circuito_horquilla: Dictionary,
	max_ticks: int,
	imprimir: bool
) -> void:
	# Incluir tambien capturas progresivas por si tienen mejores representantes intermedios
	var candidatos: Array[RedNeuronal] = []
	for r in hof:
		candidatos.append(r.clonar())
	for niv in range(1, 11):
		if capturas.has(niv):
			var r_cap: RedNeuronal = capturas[niv]["red"]
			var dup := false
			for c in candidatos:
				if _distancia_pesos(c, r_cap) < 0.05:
					dup = true
					break
			if not dup:
				candidatos.append(r_cap.clonar())

	if candidatos.size() < 10:
		return

	var so := await _evaluar_poblacion_en_pista(arbol, candidatos, circuito_ovalo, max_ticks, 0.70)
	var ss := await _evaluar_poblacion_en_pista(arbol, candidatos, circuito_s, max_ticks, 0.70)
	var sh := await _evaluar_poblacion_en_pista(arbol, candidatos, circuito_horquilla, max_ticks, 0.70)

	var fichas: Array[Dictionary] = []
	for i in range(candidatos.size()):
		var o := so[i]
		var s := ss[i]
		var h := sh[i]
		var cps_o := int(o["checkpoints"])
		var cps_s := int(s["checkpoints"])
		var cps_h := int(h["checkpoints"])
		var total_cps := cps_o + cps_s + cps_h
		var fit_total := (float(o["fitness"]) + float(s["fitness"]) + float(h["fitness"])) / 3.0
		var osc_total := (float(o["oscilacion"]) + float(s["oscilacion"]) + float(h["oscilacion"])) / 3.0
		var vel_total := (float(o["vel_media"]) + float(s["vel_media"]) + float(h["vel_media"])) / 3.0
		fichas.append({
			"idx": i,
			"red": candidatos[i],
			"cps_o": cps_o,
			"v_o": int(o["vueltas"]),
			"vel_o": float(o["vel_media"]),
			"osc_o": float(o["oscilacion"]),
			"ch_o": bool(o["chocado"]),
			"cps_s": cps_s,
			"v_s": int(s["vueltas"]),
			"cps_h": cps_h,
			"v_h": int(h["vueltas"]),
			"total_cps": total_cps,
			"fit": fit_total,
			"osc": osc_total,
			"vel": vel_total,
		})

	# Ordenar fichas de menor a mayor capacidad global (total_cps, luego fit)
	fichas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["total_cps"]) != int(b["total_cps"]):
			return int(a["total_cps"]) < int(b["total_cps"])
		return float(a["fit"]) < float(b["fit"])
	)

	var usados := {}
	var elegidos := {}

	# Nivel 1: Novato Caotico (primer candidato sin refinar, <= 3 CPs en Ovalo)
	var f1 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var bonus_gen0 := 5000.0 if int(f["idx"]) == 0 else 0.0
		var pen_alto := float(f["cps_o"]) * 900.0 + float(f["total_cps"]) * 250.0
		return bonus_gen0 - pen_alto - float(f["fit"]) * 0.05
	)
	elegidos[1] = f1

	# Nivel 10: Maestro Autonomo (el mejor absoluto en las 3 pistas)
	var f10 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var vueltas_tot := maxi(0, int(f["v_o"]) - 1) + maxi(0, int(f["v_s"]) - 1) + maxi(0, int(f["v_h"]) - 1)
		var bonus_3pistas := 8000.0 if (int(f["v_o"]) >= 2 and int(f["v_s"]) >= 2 and int(f["v_h"]) >= 2) else 0.0
		return bonus_3pistas + float(f["total_cps"]) * 120.0 + float(vueltas_tot) * 400.0 + float(f["fit"]) - float(f["osc"]) * 120.0
	)
	elegidos[10] = f10

	# Nivel 9: Apice Optimo (completa las 3 pistas con trazada limpia y menor oscilacion)
	var f9 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var bonus_3 := 6000.0 if (int(f["v_o"]) >= 2 and int(f["v_s"]) >= 2 and int(f["v_h"]) >= 2) else 0.0
		var pen_igual_10 := -500.0 if int(f["total_cps"]) > int(f10["total_cps"]) else 0.0
		return bonus_3 + pen_igual_10 + float(f["total_cps"]) * 60.0 - float(f["osc"]) * 1800.0 + float(f["fit"]) * 0.4
	)
	elegidos[9] = f9

	# Nivel 8: Piloto Agil (completa al menos 2 pistas y avanza/completa Horquilla)
	var f8 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var score := float(f["cps_h"]) * 50.0 + float(f["cps_s"]) * 15.0 + float(f["vel"]) * 2.0
		if int(f["v_o"]) >= 2 and int(f["v_s"]) >= 2:
			score += 2500.0
		if int(f["cps_h"]) >= 60:
			score += 2000.0
		if int(f["total_cps"]) > int(f9["total_cps"]):
			score -= 3000.0
		return score
	)
	elegidos[8] = f8

	# Nivel 7: Control de Frenada (domina Ovalo + S-Enlazadas, avanza bien en Horquilla)
	var f7 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var score := -absf(float(f["cps_h"]) - 42.0) * 60.0
		if int(f["v_o"]) >= 2:
			score += 1800.0
		if int(f["v_s"]) >= 2 or int(f["cps_s"]) >= 35:
			score += 2200.0
		if int(f["total_cps"]) >= int(f8["total_cps"]):
			score -= 3000.0
		return score
	)
	elegidos[7] = f7

	# Nivel 6: Trazada Estable (domina Ovalo y progresa fuerte en S-Enlazadas >= 20cp, falla en Horquilla)
	var f6 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var score := -absf(float(f["cps_s"]) - 40.0) * 65.0
		if int(f["cps_s"]) >= 18:
			score += 3200.0
		if int(f["v_o"]) >= 2:
			score += 1800.0
		if int(f["cps_h"]) > 35:
			score -= 1500.0
		if int(f["total_cps"]) >= int(f7["total_cps"]):
			score -= 3000.0
		score -= float(f["osc"]) * 400.0
		return score
	)
	elegidos[6] = f6

	# Nivel 5: Conductor Basico (completa vuelta en Ovalo, pero falla temprano en S-Enlazadas)
	var f5 := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
		var score := 0.0
		if int(f["v_o"]) >= 2:
			score += 3000.0
		elif int(f["cps_o"]) >= 28:
			score += 1500.0
		if int(f["cps_s"]) < 20:
			score += 1200.0
		score -= absf(float(f["total_cps"]) - lerpf(float(f1["total_cps"]), float(f6["total_cps"]), 0.72)) * 25.0
		if int(f["total_cps"]) >= int(f6["total_cps"]):
			score -= 3000.0
		return score
	)
	elegidos[5] = f5

	# Niveles 2, 3, 4: escalera entre Nivel 1 y Nivel 5
	var prev_cps := int(f1["total_cps"])
	var max_n5 := maxi(prev_cps + 4, int(f5["total_cps"]))
	for niv in [2, 3, 4]:
		var obj := lerpf(float(prev_cps), float(max_n5), float(niv - 1) / 4.0)
		var fniv := _tomar_candidato(fichas, usados, func(f: Dictionary) -> float:
			var score := -absf(float(f["total_cps"]) - obj) * 55.0
			if int(f["total_cps"]) < prev_cps:
				score -= 4000.0
			if int(f["total_cps"]) >= int(f5["total_cps"]):
				score -= 3000.0
			if niv == 2 and int(f["cps_o"]) > 8:
				score -= 1800.0
			if niv == 3:
				score -= float(f["vel_o"]) * 2.0
				if int(f["cps_o"]) < 8:
					score -= 1200.0
			if niv == 4:
				score += float(f["osc"]) * 450.0
				if int(f["cps_o"]) < 22:
					score -= 1200.0
			return score
		)
		elegidos[niv] = fniv
		prev_cps = maxi(prev_cps, int(fniv["total_cps"]))

	for niv in range(1, 11):
		var fe: Dictionary = elegidos[niv]
		capturas[niv] = {"red": (fe["red"] as RedNeuronal).clonar(), "fitness": float(fe["fit"])}
		if imprimir:
			print("  -> Nivel %02d | Ovalo=%2dcp(v%d, %.0fpx/s) | S=%2dcp(v%d) | Horq=%2dcp(v%d) | Total=%3dcp | osc=%.3f | fit=%.1f" % [
				niv,
				int(fe["cps_o"]), int(fe["v_o"]), float(fe["vel_o"]),
				int(fe["cps_s"]), int(fe["v_s"]),
				int(fe["cps_h"]), int(fe["v_h"]),
				int(fe["total_cps"]), float(fe["osc"]), float(fe["fit"]),
			])


static func _tomar_candidato(fichas: Array[Dictionary], usados: Dictionary, scorer: Callable) -> Dictionary:
	var mejor_idx := -1
	var mejor_score := -INF
	for i in range(fichas.size()):
		if usados.has(i):
			continue
		var s := float(scorer.call(fichas[i]))
		if s > mejor_score:
			mejor_score = s
			mejor_idx = i
	if mejor_idx < 0:
		mejor_idx = 0
	usados[mejor_idx] = true
	return fichas[mejor_idx]


static func calcular_fitness(
	checkpoints_cruzados: int,
	vuelta_actual: int,
	progreso_siguiente_cp: float,
	distancia_recorrida: float,
	ticks_vivo: int,
	esta_chocado: bool
) -> float:
	var cps := maxi(0, checkpoints_cruzados)
	var vueltas_completadas := maxi(0, vuelta_actual - 1)
	var prog := clampf(progreso_siguiente_cp, 0.0, 1.0) if is_finite(progreso_siguiente_cp) else 0.0
	var dist := maxf(0.0, distancia_recorrida) if is_finite(distancia_recorrida) else 0.0
	var ticks := maxi(0, ticks_vivo)

	var score := (
		float(cps) * 120.0
		+ float(vueltas_completadas) * 350.0
		+ prog * 60.0
		+ dist * 0.12
		+ float(ticks) * 0.05
	)
	if esta_chocado and cps == 0:
		score -= 20.0
	if not is_finite(score):
		return 0.0
	return maxf(0.0, score)


static func evolucionar_generacion(
	poblacion: Array[RedNeuronal],
	fitnesses: PackedFloat64Array,
	rng: RandomNumberGenerator,
	elitismo: int = 3,
	tasa_mutacion: float = 0.16,
	intensidad_mutacion: float = 0.35
) -> Array[RedNeuronal]:
	var n := poblacion.size()
	var nueva_poblacion: Array[RedNeuronal] = []
	if n == 0:
		return nueva_poblacion

	var indices: Array[int] = []
	for i in range(n):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var fa := fitnesses[a] if a < fitnesses.size() and is_finite(fitnesses[a]) else 0.0
		var fb := fitnesses[b] if b < fitnesses.size() and is_finite(fitnesses[b]) else 0.0
		return fa > fb
	)

	var num_elites := clampi(elitismo, 1, n)
	for e in range(num_elites):
		nueva_poblacion.append(poblacion[indices[e]].clonar())

	while nueva_poblacion.size() < n:
		var padre_a := seleccion_torneo(poblacion, fitnesses, rng, mini(3, n))
		var padre_b := seleccion_torneo(poblacion, fitnesses, rng, mini(3, n))
		var hijo := RedNeuronal.cruzar(padre_a, padre_b, rng, 0.75)
		hijo.mutar(tasa_mutacion, intensidad_mutacion, rng)
		nueva_poblacion.append(hijo)

	return nueva_poblacion


static func seleccion_torneo(
	poblacion: Array[RedNeuronal],
	fitnesses: PackedFloat64Array,
	rng: RandomNumberGenerator,
	k: int = 3
) -> RedNeuronal:
	var n := poblacion.size()
	if n == 0:
		return RedNeuronal.new()
	var gen := rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()

	var mejor_idx := gen.randi_range(0, n - 1)
	var mejor_fit := fitnesses[mejor_idx] if mejor_idx < fitnesses.size() and is_finite(fitnesses[mejor_idx]) else -INF
	for _i in range(maxi(1, k) - 1):
		var cand := gen.randi_range(0, n - 1)
		var fit := fitnesses[cand] if cand < fitnesses.size() and is_finite(fitnesses[cand]) else -INF
		if fit > mejor_fit:
			mejor_fit = fit
			mejor_idx = cand
	return poblacion[mejor_idx]


static func construir_celdas_trazo(waypoints: Array[Vector2i], radio_brocha: int = 1) -> Dictionary:
	return ArquetiposPista.construir_celdas_trazo(waypoints, radio_brocha)


static func crear_circuito_entrenamiento(indice: int = 0) -> Dictionary:
	var tam_celda := _obtener_tamanio_celda()
	var arq := ArquetiposPista.obtener_arquetipo(indice, tam_celda)
	return {
		"id": arq["id"],
		"clave": arq["clave"],
		"nombre": arq["nombre"],
		"celdas": arq["celdas"],
		"celda_meta": arq["celda_meta"],
		"tam_celda": arq["tam_celda"],
		"validacion": arq["validacion"],
	}


static func obtener_definiciones_niveles() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	var fuente: Array = NIVELES_DEFECTO

	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ds: Node = (ml as SceneTree).root.get_node_or_null("DatosSimulacion")
		if ds != null and "NIVELES_IA" in ds:
			var arr: Variant = ds.get("NIVELES_IA")
			if arr is Array and arr.size() == 10:
				fuente = arr

	for i in range(fuente.size()):
		var item: Dictionary = fuente[i]
		var niv := int(item.get("nivel", i + 1))
		var tit := str(item.get("titulo", ""))
		var desc := str(item.get("desc", ""))
		resultado.append({
			"nivel": niv,
			"titulo": tit,
			"titulo_completo": "Nivel %d — %s" % [niv, tit],
			"desc": desc,
		})
	return resultado


static func crear_recurso_nivel(
	p_nivel: int,
	red: RedNeuronal,
	fitness: float = 0.0
) -> CerebroEntrenado:
	var nivel_seguro := clampi(p_nivel, 1, 10)
	var defs := obtener_definiciones_niveles()
	var info: Dictionary = defs[nivel_seguro - 1]
	var red_fuente := red if red != null else RedNeuronal.new()
	return red_fuente.exportar_a_recurso(
		nivel_seguro,
		info["titulo_completo"],
		info["desc"],
		fitness
	)


static func _guardar_recurso_en_carpeta(
	recurso: CerebroEntrenado,
	carpeta_salida: String,
	nivel: int
) -> Error:
	var carpeta := carpeta_salida.trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(carpeta) if carpeta.begins_with("res://") or carpeta.begins_with("user://") else carpeta)
	var ruta := "%s/nivel_%02d.tres" % [carpeta, clampi(nivel, 1, 10)]
	return ResourceSaver.save(recurso, ruta)


static func _obtener_tamanio_celda() -> int:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ds: Node = (ml as SceneTree).root.get_node_or_null("DatosSimulacion")
		if ds != null and "TAMANIO_CELDA" in ds:
			return int(ds.get("TAMANIO_CELDA"))
	return 16


class _StepperEvaluacion extends Node:
	signal evaluacion_completada

	var coches: Array[VehiculoAgente] = []
	var prev_pos: Array[Vector2] = []
	var distancias: Array[float] = []
	var ticks_vivos: Array[int] = []
	var prev_giro: Array[float] = []
	var suma_oscilacion: Array[float] = []
	var ticks_reversa: Array[int] = []
	var max_ticks: int = 1800
	var tick_actual: int = 0
	var terminado: bool = false

	func inicializar(p_coches: Array[VehiculoAgente], p_prev_pos: Array[Vector2], p_max_ticks: int) -> void:
		coches = p_coches
		prev_pos = p_prev_pos
		max_ticks = p_max_ticks
		var n := coches.size()
		distancias.resize(n)
		distancias.fill(0.0)
		ticks_vivos.resize(n)
		ticks_vivos.fill(0)
		prev_giro.resize(n)
		prev_giro.fill(0.0)
		suma_oscilacion.resize(n)
		suma_oscilacion.fill(0.0)
		ticks_reversa.resize(n)
		ticks_reversa.fill(0)

	func _physics_process(_delta: float) -> void:
		if terminado:
			return
		tick_actual += 1
		var alguno_vivo := false
		for i in range(coches.size()):
			var car := coches[i]
			if not car.esta_chocado:
				alguno_vivo = true
				ticks_vivos[i] += 1
				var d := car.global_position.distance_to(prev_pos[i])
				if is_finite(d):
					distancias[i] += d
				prev_pos[i] = car.global_position
				suma_oscilacion[i] += absf(car.ultimo_giro_ia - prev_giro[i])
				prev_giro[i] = car.ultimo_giro_ia
				if car.ultima_aceleracion_ia < -0.05:
					ticks_reversa[i] += 1
		if not alguno_vivo or tick_actual >= max_ticks:
			terminado = true
			set_physics_process(false)
			evaluacion_completada.emit()
