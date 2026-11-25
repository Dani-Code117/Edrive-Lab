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
const NUM_GENES: int = 62 # 42 + 6 + 12 + 2

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
	print("EntrenadorGenetico: Iniciando entrenamiento genético (Niveles 1..10)...")
	var resultados := await entrenar_en_arbol(self, RUTA_PRESETS, {"guardar_en_disco": true})
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

	var tamano_poblacion: int = maxi(4, int(opciones.get("tamano_poblacion", 40)))
	var max_generaciones: int = maxi(1, int(opciones.get("max_generaciones", 100)))
	var max_ticks: int = maxi(10, int(opciones.get("max_ticks", 1800)))
	var elitismo: int = clampi(int(opciones.get("elitismo", 3)), 1, tamano_poblacion)
	var guardar_en_disco: bool = bool(opciones.get("guardar_en_disco", true))
	var semilla: int = int(opciones.get("semilla", 202611))

	var rng := RandomNumberGenerator.new()
	rng.seed = semilla

	var circuito_ovalo := crear_circuito_entrenamiento(0)
	var circuito_chicana := crear_circuito_entrenamiento(1)
	if not circuito_ovalo.get("validacion", {}).get("valido", false):
		push_error("EntrenadorGenetico: Circuito Óvalo inválido.")
		return resultados
	if not circuito_chicana.get("validacion", {}).get("valido", false):
		push_error("EntrenadorGenetico: Circuito Chicana inválido.")
		return resultados

	var poblacion: Array[RedNeuronal] = []
	for i in range(tamano_poblacion):
		var red := RedNeuronal.new()
		red.inicializar_aleatorio(semilla + i * 17, 1.2)
		poblacion.append(red)

	var capturas: Dictionary = {} # nivel (int) -> {"red": RedNeuronal, "fitness": float}

	# Guardar snapshot de Nivel 1 (Novato Caótico) desde la generación inicial sin refinar
	var novato := poblacion[0].clonar()
	capturas[1] = {"red": novato, "fitness": 0.0}

	var mejor_global_red: RedNeuronal = poblacion[0].clonar()
	var mejor_global_fitness: float = -1.0

	var tps_orig := Engine.physics_ticks_per_second
	var scale_orig := Engine.time_scale
	var max_steps_orig := Engine.max_physics_steps_per_frame

	Engine.physics_ticks_per_second = 2400
	Engine.time_scale = 40.0
	Engine.max_physics_steps_per_frame = 200

	for gen in range(max_generaciones):
		var stats_ovalo := await _evaluar_poblacion_en_pista(arbol, poblacion, circuito_ovalo, max_ticks, 0.75)
		var fitnesses := PackedFloat64Array()
		fitnesses.resize(tamano_poblacion)

		var eval_doble := gen >= 15 or max_generaciones <= 2
		var stats_chicana: Array[Dictionary] = []
		if eval_doble:
			stats_chicana = await _evaluar_poblacion_en_pista(arbol, poblacion, circuito_chicana, max_ticks, 0.75)

		var mejor_idx := 0
		var mejor_fit := -1.0
		var mejor_cps := 0
		var mejor_vueltas := 1
		var mejor_cps_ambas := 0
		var mejor_vueltas_ambas := 1

		for i in range(tamano_poblacion):
			var so: Dictionary = stats_ovalo[i]
			var fit: float = float(so["fitness"])
			var cps: int = int(so["checkpoints"])
			var vueltas: int = int(so["vueltas"])
			var cps_ambas := cps
			var vueltas_ambas := vueltas

			if eval_doble and i < stats_chicana.size():
				var sc: Dictionary = stats_chicana[i]
				fit = (fit + float(sc["fitness"])) * 0.5
				cps_ambas = mini(cps, int(sc["checkpoints"]))
				vueltas_ambas = mini(vueltas, int(sc["vueltas"]))

			fitnesses[i] = fit
			if fit > mejor_fit:
				mejor_fit = fit
				mejor_idx = i
				mejor_cps = cps
				mejor_vueltas = vueltas
				mejor_cps_ambas = cps_ambas
				mejor_vueltas_ambas = vueltas_ambas

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
			mejor_vueltas_ambas
		)

		if gen < max_generaciones - 1:
			poblacion = evolucionar_generacion(poblacion, fitnesses, rng, elitismo)

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


static func _registrar_captura_progresiva(
	capturas: Dictionary,
	gen: int,
	max_gen: int,
	campeon: RedNeuronal,
	fit: float,
	cps: int,
	vueltas: int,
	cps_ambas: int,
	vueltas_ambas: int
) -> void:
	var prog := float(gen + 1) / float(maxi(1, max_gen))
	if not capturas.has(2) and (cps >= 3 or prog >= 0.05):
		capturas[2] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(3) and (cps >= 6 or prog >= 0.12):
		capturas[3] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(4) and (cps >= 13 or prog >= 0.20):
		capturas[4] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(5) and (vueltas >= 2 or prog >= 0.30):
		capturas[5] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(6) and (vueltas_ambas >= 2 or (cps_ambas >= 12 and prog >= 0.42)):
		capturas[6] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(7) and (vueltas_ambas >= 3 or prog >= 0.55):
		capturas[7] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(8) and (vueltas_ambas >= 3 and prog >= 0.68 or prog >= 0.72):
		capturas[8] = {"red": campeon.clonar(), "fitness": fit}
	if not capturas.has(9) and (vueltas_ambas >= 4 or prog >= 0.85):
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
	var tam: float = float(circuito["tam_celda"])
	var pos_salida := Vector2(circuito["celda_meta"]) * tam + Vector2.ONE * (tam * 0.5)
	var rot_salida := float(validacion["rotacion_salida"])

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
		mundo.add_child(cp_node)

	var escena_car := ResourceLoader.load(RUTA_VEHICULO) as PackedScene
	var coches: Array[VehiculoAgente] = []
	var prev_pos: Array[Vector2] = []
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
	}

	for i in range(poblacion.size()):
		var car := escena_car.instantiate() as VehiculoAgente
		car.mostrar_sensores = false
		mundo.add_child(car)
		car.configurar(cfg)
		car.cerebro = poblacion[i]
		car.reiniciar_estado(pos_salida, rot_salida, cps.size())
		coches.append(car)
		prev_pos.append(pos_salida)

	for _tick in range(max_ticks):
		await arbol.physics_frame
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
		if not alguno_vivo:
			break

	for i in range(coches.size()):
		var car := coches[i]
		var siguiente_cp := (car.ultimo_checkpoint + 1) % maxi(1, cps.size())
		var dist_sig := car.global_position.distance_to(posiciones_cp[siguiente_cp]) if not posiciones_cp.is_empty() else 0.0
		var progreso_cp := 1.0 - clampf(dist_sig / 200.0, 0.0, 1.0)
		var fit := calcular_fitness(
			car.checkpoints_cruzados,
			car.vuelta_actual,
			progreso_cp,
			distancias[i],
			ticks_vivos[i],
			car.esta_chocado
		)
		resultados[i] = {
			"fitness": fit,
			"checkpoints": car.checkpoints_cruzados,
			"vueltas": car.vuelta_actual,
			"distancia": distancias[i],
			"chocado": car.esta_chocado,
		}

	if is_instance_valid(mundo):
		mundo.queue_free()
		await arbol.process_frame

	return resultados


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
	var celdas: Dictionary = {}
	if waypoints.size() < 2:
		return celdas

	for idx in range(waypoints.size() - 1):
		var a := waypoints[idx]
		var b := waypoints[idx + 1]
		var pasos := maxi(1, maxi(absi(b.x - a.x), absi(b.y - a.y)))
		for s in range(pasos + 1):
			var t := float(s) / float(pasos)
			var cx := roundi(lerpf(float(a.x), float(b.x), t))
			var cy := roundi(lerpf(float(a.y), float(b.y), t))
			for dx in range(-radio_brocha, radio_brocha + 1):
				for dy in range(-radio_brocha, radio_brocha + 1):
					celdas[Vector2i(cx + dx, cy + dy)] = true
	return celdas


static func crear_circuito_entrenamiento(indice: int = 0) -> Dictionary:
	var tam_celda := _obtener_tamanio_celda()
	var waypoints: Array[Vector2i]
	var celda_meta: Vector2i
	var nombre: String

	if indice == 1:
		nombre = "Chicana Asimétrica"
		waypoints = [
			Vector2i(8, 6),
			Vector2i(36, 6),
			Vector2i(36, 13),
			Vector2i(26, 13),
			Vector2i(22, 20),
			Vector2i(8, 20),
			Vector2i(8, 6),
		]
		celda_meta = Vector2i(14, 6)
	else:
		nombre = "Óvalo Técnico"
		waypoints = [
			Vector2i(7, 5),
			Vector2i(37, 5),
			Vector2i(37, 21),
			Vector2i(7, 21),
			Vector2i(7, 5),
		]
		celda_meta = Vector2i(14, 5)

	var celdas := construir_celdas_trazo(waypoints, 1)
	var validacion := GeneradorCheckpoints.validar_y_generar(celdas, celda_meta, true, tam_celda)
	return {
		"nombre": nombre,
		"celdas": celdas,
		"celda_meta": celda_meta,
		"tam_celda": tam_celda,
		"validacion": validacion,
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
