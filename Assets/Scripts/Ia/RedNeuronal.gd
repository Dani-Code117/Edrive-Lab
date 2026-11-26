class_name RedNeuronal
extends RefCounted

## Red neuronal feedforward 18 -> 8 -> 2 con activación tanh() para VehiculoAgente.
## Entradas: 14 RayCast2D (11 frontales + 3 traseros) + 2 Brújula CP + 2 Estado/Memoria.
## Salidas: aceleración [-1.0, 1.0] (incluye reversa) y giro [-1.0, 1.0].

const NUM_ENTRADAS: int = 18
const NUM_OCULTA: int = 8
const NUM_SALIDA: int = 2
const TOTAL_PESOS_OCULTA: int = NUM_ENTRADAS * NUM_OCULTA        # 144
const TOTAL_PESOS_SALIDA: int = NUM_OCULTA * NUM_SALIDA          # 16
const LIMITE_PESO: float = 10.0
const LIMITE_PREACTIVACION: float = 50.0

var num_entradas: int = NUM_ENTRADAS
var num_oculta: int = NUM_OCULTA
var num_salida: int = NUM_SALIDA

var pesos_oculta: PackedFloat64Array = PackedFloat64Array()
var sesgos_oculta: PackedFloat64Array = PackedFloat64Array()
var pesos_salida: PackedFloat64Array = PackedFloat64Array()
var sesgos_salida: PackedFloat64Array = PackedFloat64Array()

## Instantáneas públicas para Fase 4 (VisorRedNeuronal).
var ultimas_entradas: PackedFloat64Array = PackedFloat64Array()
var ultimas_ocultas: PackedFloat64Array = PackedFloat64Array()
var ultimas_salidas: PackedFloat64Array = PackedFloat64Array()
var cerebro: CerebroEntrenado = null


func _init(recurso: CerebroEntrenado = null) -> void:
	_inicializar_buffers()
	if recurso != null:
		cargar_desde_recurso(recurso)


func _inicializar_buffers() -> void:
	pesos_oculta.resize(TOTAL_PESOS_OCULTA)
	pesos_oculta.fill(0.0)
	sesgos_oculta.resize(NUM_OCULTA)
	sesgos_oculta.fill(0.0)
	pesos_salida.resize(TOTAL_PESOS_SALIDA)
	pesos_salida.fill(0.0)
	sesgos_salida.resize(NUM_SALIDA)
	sesgos_salida.fill(0.0)
	_reiniciar_instantaneas()


func _reiniciar_instantaneas() -> void:
	ultimas_entradas.resize(NUM_ENTRADAS)
	ultimas_entradas.fill(0.0)
	ultimas_ocultas.resize(NUM_OCULTA)
	ultimas_ocultas.fill(0.0)
	ultimas_salidas.resize(NUM_SALIDA)
	ultimas_salidas.fill(0.0)


func evaluar(entradas: PackedFloat64Array) -> PackedFloat64Array:
	if ultimas_entradas.size() != NUM_ENTRADAS:
		ultimas_entradas.resize(NUM_ENTRADAS)
	if ultimas_ocultas.size() != NUM_OCULTA:
		ultimas_ocultas.resize(NUM_OCULTA)
	if ultimas_salidas.size() != NUM_SALIDA:
		ultimas_salidas.resize(NUM_SALIDA)

	# 1. Sanitizar entradas sin recortar valores finitos (admite cualquier rango finito;
	#    rellena con 0.0 si faltan elementos o si hay NaN/INF, y trunca si sobran).
	var tam_ent := entradas.size()
	for i in range(NUM_ENTRADAS):
		var v: float = entradas[i] if i < tam_ent else 0.0
		if not is_finite(v):
			v = 0.0
		ultimas_entradas[i] = v

	# 2. Capa oculta (6 neuronas): tanh(dot + bias)
	for j in range(NUM_OCULTA):
		var suma: float = _leer_param_seguro(sesgos_oculta, j)
		var base_idx := j * NUM_ENTRADAS
		for i in range(NUM_ENTRADAS):
			suma += ultimas_entradas[i] * _leer_param_seguro(pesos_oculta, base_idx + i)
		suma = _sanitizar_preactivacion(suma)
		var act := clampf(tanh(suma), -1.0, 1.0)
		ultimas_ocultas[j] = act if is_finite(act) else 0.0

	# 3. Capa de salida (2 neuronas):
	#    aceleracion = clampf((tanh(raw_0) + 1.0) * 0.5, 0.0, 1.0)
	#    giro = clampf(tanh(raw_1), -1.0, 1.0)
	var raw_salidas: Array[float] = [0.0, 0.0]
	for k in range(NUM_SALIDA):
		var suma_sal: float = _leer_param_seguro(sesgos_salida, k)
		var base_sal := k * NUM_OCULTA
		for j in range(NUM_OCULTA):
			suma_sal += ultimas_ocultas[j] * _leer_param_seguro(pesos_salida, base_sal + j)
		raw_salidas[k] = _sanitizar_preactivacion(suma_sal)

	var t0 := tanh(raw_salidas[0])
	var t1 := tanh(raw_salidas[1])
	var aceleracion: float = clampf(t0, -1.0, 1.0) if is_finite(t0) else 0.0
	var giro: float = clampf(t1, -1.0, 1.0) if is_finite(t1) else 0.0

	ultimas_salidas[0] = aceleracion
	ultimas_salidas[1] = giro

	# Retornar copia fresca para evitar mutación externa de ultimas_salidas.
	return PackedFloat64Array([aceleracion, giro])


func cargar_desde_recurso(recurso: CerebroEntrenado) -> bool:
	if recurso == null or not recurso.es_valido():
		return false

	pesos_oculta = _copiar_sanitizado(recurso.pesos_oculta, TOTAL_PESOS_OCULTA)
	sesgos_oculta = _copiar_sanitizado(recurso.sesgos_oculta, NUM_OCULTA)
	pesos_salida = _copiar_sanitizado(recurso.pesos_salida, TOTAL_PESOS_SALIDA)
	sesgos_salida = _copiar_sanitizado(recurso.sesgos_salida, NUM_SALIDA)
	cerebro = recurso
	_reiniciar_instantaneas()
	return true


func exportar_a_recurso(
	nivel: int = 1,
	titulo: String = "",
	desc: String = "",
	fitness: float = 0.0
) -> CerebroEntrenado:
	var recurso := CerebroEntrenado.new()
	recurso.nivel = clampi(nivel, 1, 10)
	recurso.titulo = titulo
	recurso.descripcion_educativa = desc
	recurso.num_entradas = NUM_ENTRADAS
	recurso.num_oculta = NUM_OCULTA
	recurso.num_salida = NUM_SALIDA
	recurso.pesos_oculta = _copiar_sanitizado(pesos_oculta, TOTAL_PESOS_OCULTA)
	recurso.sesgos_oculta = _copiar_sanitizado(sesgos_oculta, NUM_OCULTA)
	recurso.pesos_salida = _copiar_sanitizado(pesos_salida, TOTAL_PESOS_SALIDA)
	recurso.sesgos_salida = _copiar_sanitizado(sesgos_salida, NUM_SALIDA)
	recurso.fitness_alcanzado = fitness if is_finite(fitness) else 0.0
	cerebro = recurso
	return recurso


func inicializar_aleatorio(semilla: int = -1, rango: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	if semilla >= 0:
		rng.seed = int(semilla)
	else:
		rng.randomize()

	var amp := clampf(absf(rango), 0.0, LIMITE_PESO) if is_finite(rango) else 1.0
	_inicializar_buffers()

	for i in range(TOTAL_PESOS_OCULTA):
		pesos_oculta[i] = rng.randf_range(-amp, amp)
	for j in range(NUM_OCULTA):
		sesgos_oculta[j] = rng.randf_range(-amp * 0.5, amp * 0.5)
	for k in range(TOTAL_PESOS_SALIDA):
		pesos_salida[k] = rng.randf_range(-amp, amp)
	for m in range(NUM_SALIDA):
		sesgos_salida[m] = rng.randf_range(-amp * 0.5, amp * 0.5)


func clonar() -> RedNeuronal:
	var copia := RedNeuronal.new()
	copia.pesos_oculta = _copiar_sanitizado(pesos_oculta, TOTAL_PESOS_OCULTA)
	copia.sesgos_oculta = _copiar_sanitizado(sesgos_oculta, NUM_OCULTA)
	copia.pesos_salida = _copiar_sanitizado(pesos_salida, TOTAL_PESOS_SALIDA)
	copia.sesgos_salida = _copiar_sanitizado(sesgos_salida, NUM_SALIDA)
	copia.cerebro = cerebro
	return copia


func mutar(
	tasa_mutacion: float = 0.15,
	intensidad: float = 0.35,
	rng: RandomNumberGenerator = null
) -> void:
	var gen := rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()

	var tasa := clampf(tasa_mutacion, 0.0, 1.0) if is_finite(tasa_mutacion) else 0.15
	var sigma := absf(intensidad) if is_finite(intensidad) else 0.35

	_mutar_arreglo(pesos_oculta, TOTAL_PESOS_OCULTA, tasa, sigma, gen)
	_mutar_arreglo(sesgos_oculta, NUM_OCULTA, tasa, sigma, gen)
	_mutar_arreglo(pesos_salida, TOTAL_PESOS_SALIDA, tasa, sigma, gen)
	_mutar_arreglo(sesgos_salida, NUM_SALIDA, tasa, sigma, gen)


static func cruzar(
	padre_a: RedNeuronal,
	padre_b: RedNeuronal,
	rng: RandomNumberGenerator = null,
	prob_cruce: float = 0.75
) -> RedNeuronal:
	if padre_a == null and padre_b == null:
		return RedNeuronal.new()
	if padre_a == null:
		return padre_b.clonar()
	if padre_b == null:
		return padre_a.clonar()

	var gen := rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()

	var prob := clampf(prob_cruce, 0.0, 1.0) if is_finite(prob_cruce) else 0.75
	if gen.randf() > prob:
		return padre_a.clonar()

	var hijo := RedNeuronal.new()
	_cruzar_arreglo(padre_a.pesos_oculta, padre_b.pesos_oculta, hijo.pesos_oculta, TOTAL_PESOS_OCULTA, gen)
	_cruzar_arreglo(padre_a.sesgos_oculta, padre_b.sesgos_oculta, hijo.sesgos_oculta, NUM_OCULTA, gen)
	_cruzar_arreglo(padre_a.pesos_salida, padre_b.pesos_salida, hijo.pesos_salida, TOTAL_PESOS_SALIDA, gen)
	_cruzar_arreglo(padre_a.sesgos_salida, padre_b.sesgos_salida, hijo.sesgos_salida, NUM_SALIDA, gen)
	return hijo


static func cargar_nivel_o_fallback(p_nivel: int) -> RedNeuronal:
	var nivel_seguro := clampi(p_nivel, 1, 10)
	var ruta := CerebroEntrenado.ruta_para_nivel(nivel_seguro)
	if ResourceLoader.exists(ruta):
		var recurso := ResourceLoader.load(ruta) as CerebroEntrenado
		if recurso != null and recurso.es_valido():
			return RedNeuronal.new(recurso)

	# Respaldo determinista en memoria cuando aún no existen .tres entrenados (nunca escribe en disco).
	var red := RedNeuronal.new()
	red.inicializar_aleatorio(1000 + nivel_seguro * 37, 0.15 if nivel_seguro > 1 else 0.85)

	# Inyectar una respuesta base diferenciada según nivel (sensores 0..4 izq, 5 frente, 6..10 der, 11..13 atrás, 14..15 CP, 16..17 estado)
	var ganancia_giro := lerpf(0.25, 1.4, float(nivel_seguro - 1) / 9.0)
	var ganancia_vel := lerpf(0.3, 1.3, float(nivel_seguro - 1) / 9.0)
	if nivel_seguro > 1:
		# Neurona oculta 0: evasión de muros + orientación hacia checkpoint (entrada 15 = sin_rel)
		red.pesos_oculta[0 * NUM_ENTRADAS + 1] = -ganancia_giro * 0.5
		red.pesos_oculta[0 * NUM_ENTRADAS + 2] = -ganancia_giro * 0.8
		red.pesos_oculta[0 * NUM_ENTRADAS + 3] = -ganancia_giro
		red.pesos_oculta[0 * NUM_ENTRADAS + 4] = -ganancia_giro * 0.6
		red.pesos_oculta[0 * NUM_ENTRADAS + 6] = ganancia_giro * 0.6
		red.pesos_oculta[0 * NUM_ENTRADAS + 7] = ganancia_giro
		red.pesos_oculta[0 * NUM_ENTRADAS + 8] = ganancia_giro * 0.8
		red.pesos_oculta[0 * NUM_ENTRADAS + 9] = ganancia_giro * 0.5
		red.pesos_oculta[0 * NUM_ENTRADAS + 15] = ganancia_giro * 0.9
		red.sesgos_oculta[0] = -ganancia_giro * 0.45

		# Neurona oculta 1: avance si el frente (5) está libre; reversa si el frente está bloqueado y atrás (12) libre
		red.pesos_oculta[1 * NUM_ENTRADAS + 5] = ganancia_vel * 2.2
		red.pesos_oculta[1 * NUM_ENTRADAS + 12] = -0.35
		red.pesos_oculta[1 * NUM_ENTRADAS + 17] = 0.65
		red.sesgos_oculta[1] = -0.45

		# Salida 0 (aceleración [-1..1]) desde oculta 1
		red.pesos_salida[0 * NUM_OCULTA + 1] = 1.6
		red.sesgos_salida[0] = 0.25
		# Salida 1 (giro [-1..1]) desde oculta 0
		red.pesos_salida[1 * NUM_OCULTA + 0] = 1.4

	var info := _obtener_info_nivel_fallback(nivel_seguro)
	red.exportar_a_recurso(
		nivel_seguro,
		"Nivel %d — %s" % [nivel_seguro, info["titulo"]],
		info["desc"],
		0.0
	)
	return red


static func _obtener_info_nivel_fallback(nivel_seguro: int) -> Dictionary:
	var niveles_def := [
		{"titulo": "Novato Caótico", "desc": "Pesos sin refinar; acelera sin frenar y gira erráticamente."},
		{"titulo": "Primeros Reflejos", "desc": "Detecta el muro frontal tarde; intenta esquivar pero roza bordes."},
		{"titulo": "Cauteloso Lento", "desc": "Mantiene baja aceleración constante; supera curvas abiertas."},
		{"titulo": "Zig-Zag Nervioso", "desc": "Completa rectas y curvas suaves, pero oscila entre los bordes."},
		{"titulo": "Conductor Básico", "desc": "Completa circuitos sencillos a velocidad media sin chocar."},
		{"titulo": "Trazada Estable", "desc": "Estabiliza la dirección usando los sensores laterales de ±45°."},
		{"titulo": "Control de Frenada", "desc": "Reduce aceleración al detectar proximidad en sensores frontales."},
		{"titulo": "Piloto Ágil", "desc": "Aprovecha rectas a alta velocidad y anticipa giros cerrados."},
		{"titulo": "Ápice Óptimo", "desc": "Busca el interior de las curvas para minimizar distancia."},
		{"titulo": "Maestro Autónomo", "desc": "Conducción fluida, rápida y adaptable a cualquier circuito."},
	]
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ds: Node = (ml as SceneTree).root.get_node_or_null("DatosSimulacion")
		if ds != null and "NIVELES_IA" in ds:
			var arr: Variant = ds.get("NIVELES_IA")
			if arr is Array and nivel_seguro - 1 < arr.size():
				var entry: Dictionary = arr[nivel_seguro - 1]
				return {
					"titulo": str(entry.get("titulo", "")),
					"desc": str(entry.get("desc", "")),
				}
	var idx := clampi(nivel_seguro - 1, 0, niveles_def.size() - 1)
	return niveles_def[idx]


static func _leer_param_seguro(arr: PackedFloat64Array, idx: int) -> float:
	if idx < 0 or idx >= arr.size():
		return 0.0
	var v := arr[idx]
	return v if is_finite(v) else 0.0


static func _sanitizar_preactivacion(suma: float) -> float:
	if is_nan(suma):
		return 0.0
	if not is_finite(suma):
		return LIMITE_PREACTIVACION if suma > 0.0 else -LIMITE_PREACTIVACION
	return clampf(suma, -LIMITE_PREACTIVACION, LIMITE_PREACTIVACION)


static func _copiar_sanitizado(origen: PackedFloat64Array, tam_esperado: int) -> PackedFloat64Array:
	var copia := PackedFloat64Array()
	copia.resize(tam_esperado)
	var tam_orig := origen.size()
	for i in range(tam_esperado):
		var v: float = origen[i] if i < tam_orig else 0.0
		copia[i] = v if is_finite(v) else 0.0
	return copia


static func _mutar_arreglo(
	arr: PackedFloat64Array,
	tam_esperado: int,
	tasa: float,
	sigma: float,
	gen: RandomNumberGenerator
) -> void:
	if arr.size() != tam_esperado:
		arr.resize(tam_esperado)
	for i in range(tam_esperado):
		var base := arr[i] if is_finite(arr[i]) else 0.0
		if gen.randf() < tasa:
			var delta := gen.randfn(0.0, sigma)
			if is_finite(delta):
				base += delta
		arr[i] = clampf(base, -LIMITE_PESO, LIMITE_PESO)


static func _cruzar_arreglo(
	a: PackedFloat64Array,
	b: PackedFloat64Array,
	destino: PackedFloat64Array,
	tam: int,
	gen: RandomNumberGenerator
) -> void:
	destino.resize(tam)
	for i in range(tam):
		var va := _leer_param_seguro(a, i)
		var vb := _leer_param_seguro(b, i)
		var elegido := va if gen.randf() < 0.5 else vb
		destino[i] = clampf(elegido, -LIMITE_PESO, LIMITE_PESO)
