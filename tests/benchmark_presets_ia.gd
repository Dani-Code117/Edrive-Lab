extends SceneTree

## Benchmark educativo de los 10 presets IA (nivel_01.tres .. nivel_10.tres).
## Mide hasta donde llega cada nivel sobre los 3 arquetipos oficiales y un
## 4to circuito inedito para verificar progresion educativa y generalizacion.

const RUTA_PRESETS := "res://Assets/Presets_ia"
const TICKS_EVAL: int = 1800 # 30 s reales a 60 Hz

const WAYPOINTS_INEDITO: Array[Vector2i] = [
	Vector2i(5, 4),
	Vector2i(22, 4),
	Vector2i(26, 9),
	Vector2i(39, 9),
	Vector2i(41, 13),
	Vector2i(41, 22),
	Vector2i(25, 22),
	Vector2i(21, 17),
	Vector2i(14, 22),
	Vector2i(5, 22),
	Vector2i(3, 18),
	Vector2i(3, 8),
	Vector2i(5, 4),
]

var _total_checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _assert_true(cond: bool, msg: String) -> void:
	_total_checks += 1
	if cond:
		print("[PASS] %s" % msg)
	else:
		_failures += 1
		printerr("[FAIL] %s" % msg)


func _crear_circuito_inedito() -> Dictionary:
	var celdas := ArquetiposPista.construir_celdas_trazo(WAYPOINTS_INEDITO, 1)
	var meta := Vector2i(13, 4)
	var val := GeneradorCheckpoints.validar_y_generar(celdas, meta, true, 16)
	return {
		"id": 99,
		"clave": "inedito_l_chicana",
		"nombre": "Circuito Inédito",
		"celdas": celdas,
		"celda_meta": meta,
		"tam_celda": 16,
		"validacion": val,
	}


func _run_benchmark() -> void:
	await process_frame

	var tps_orig := Engine.physics_ticks_per_second
	var scale_orig := Engine.time_scale
	var max_steps_orig := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 3600
	Engine.time_scale = 60.0
	Engine.max_physics_steps_per_frame = 240

	var redes: Array[RedNeuronal] = []
	var recursos: Array[CerebroEntrenado] = []
	var carga_ok := true
	for niv in range(1, 11):
		var ruta := CerebroEntrenado.ruta_para_nivel(niv)
		if not ResourceLoader.exists(ruta):
			carga_ok = false
			break
		var rec := ResourceLoader.load(ruta) as CerebroEntrenado
		if rec == null or not rec.es_valido() or rec.nivel != niv:
			carga_ok = false
			break
		recursos.append(rec)
		redes.append(RedNeuronal.new(rec))

	_assert_true(carga_ok and redes.size() == 10, "Los 10 presets nivel_01.tres..nivel_10.tres cargan y son validos")
	if not carga_ok:
		Engine.physics_ticks_per_second = tps_orig
		Engine.time_scale = scale_orig
		Engine.max_physics_steps_per_frame = max_steps_orig
		quit(1)
		return

	# Verificar pesos distintos entre los 10 presets
	var distintos := true
	for i in range(10):
		for j in range(i + 1, 10):
			if EntrenadorGenetico._distancia_pesos(redes[i], redes[j]) < 0.05:
				distintos = false
				break
	_assert_true(distintos, "Los 10 presets poseen pesos neuronales distintos entre si")

	var c_ovalo := EntrenadorGenetico.crear_circuito_entrenamiento(ArquetiposPista.OVALO_CLASICO)
	var c_s := EntrenadorGenetico.crear_circuito_entrenamiento(ArquetiposPista.S_ENLAZADAS)
	var c_horq := EntrenadorGenetico.crear_circuito_entrenamiento(ArquetiposPista.HORQUILLA_TECNICA)
	var c_ined := _crear_circuito_inedito()
	_assert_true(bool(c_ined["validacion"].get("valido", false)), "Circuito Inedito de evaluacion valida correctamente")

	var so := await EntrenadorGenetico._evaluar_poblacion_en_pista(self, redes, c_ovalo, TICKS_EVAL, 0.70)
	var ss := await EntrenadorGenetico._evaluar_poblacion_en_pista(self, redes, c_s, TICKS_EVAL, 0.70)
	var sh := await EntrenadorGenetico._evaluar_poblacion_en_pista(self, redes, c_horq, TICKS_EVAL, 0.70)
	var si := await EntrenadorGenetico._evaluar_poblacion_en_pista(self, redes, c_ined, TICKS_EVAL, 0.70)
	var so_eq := await EntrenadorGenetico._evaluar_poblacion_en_pista(self, redes, c_ovalo, TICKS_EVAL, 0.50)

	Engine.physics_ticks_per_second = tps_orig
	Engine.time_scale = scale_orig
	Engine.max_physics_steps_per_frame = max_steps_orig

	print("\n=== BENCHMARK EDUCATIVO PRESETS IA (30s @ 60Hz, perfil 0.70) ===")
	print("Niv | Titulo                   | Ovalo (CP/Vta/Est/Vel)       | S-Enlazadas (CP/Vta/Est)   | Horquilla (CP/Vta/Est)     | Inedito (CP/Vta/Est)       | Osc   | FitProm")
	print("----+--------------------------+------------------------------+----------------------------+----------------------------+----------------------------+-------+--------")

	var totales_cps: Array[int] = []
	var fits_prom: Array[float] = []
	for i in range(10):
		var o := so[i]
		var s := ss[i]
		var h := sh[i]
		var ind := si[i]
		var total_cp := int(o["checkpoints"]) + int(s["checkpoints"]) + int(h["checkpoints"])
		var fit_prom := (float(o["fitness"]) + float(s["fitness"]) + float(h["fitness"])) / 3.0
		var osc_prom := (float(o["oscilacion"]) + float(s["oscilacion"]) + float(h["oscilacion"])) / 3.0
		totales_cps.append(total_cp)
		fits_prom.append(fit_prom)

		var est_o := str(o["motivo"]) if bool(o["chocado"]) else "Corriendo"
		var est_s := str(s["motivo"]) if bool(s["chocado"]) else "Corriendo"
		var est_h := str(h["motivo"]) if bool(h["chocado"]) else "Corriendo"
		var est_i := str(ind["motivo"]) if bool(ind["chocado"]) else "Corriendo"

		print("%2d  | %-24s | %3dcp v%d %-9s %5.1fpx/s | %3dcp v%d %-9s        | %3dcp v%d %-9s        | %3dcp v%d %-9s        | %.3f | %7.1f" % [
			i + 1,
			recursos[i].titulo.left(24),
			int(o["checkpoints"]), int(o["vueltas"]), est_o, float(o["vel_media"]),
			int(s["checkpoints"]), int(s["vueltas"]), est_s,
			int(h["checkpoints"]), int(h["vueltas"]), est_h,
			int(ind["checkpoints"]), int(ind["vueltas"]), est_i,
			osc_prom,
			fit_prom,
		])

	# Criterios objetivos educativos
	_assert_true(int(so[0]["checkpoints"]) <= 3 and bool(so[0]["chocado"]), "Nivel 1 (Novato Caotico) choca temprano (<= 3 CPs en Ovalo)")
	_assert_true(int(so[3]["checkpoints"]) > int(so[0]["checkpoints"]), "Nivel 4 supera claramente a Nivel 1 en Ovalo")
	_assert_true(int(so[4]["vueltas"]) >= 2 or int(so[4]["checkpoints"]) >= 18, "Nivel 5 (Conductor Basico) completa al menos 1 vuelta en Ovalo")
	_assert_true(int(ss[5]["checkpoints"]) >= 12 or int(ss[5]["vueltas"]) >= 2, "Nivel 6 (Trazada Estable) progresa o completa S-Enlazadas")
	_assert_true(int(sh[7]["vueltas"]) >= 2 or int(sh[8]["vueltas"]) >= 2 or int(sh[9]["vueltas"]) >= 2, "Niveles avanzados (8-10) completan vuelta en Horquilla Tecnica")
	_assert_true(
		int(so[9]["vueltas"]) >= 2 and int(ss[9]["vueltas"]) >= 2 and int(sh[9]["vueltas"]) >= 2,
		"Nivel 10 (Maestro Autonomo) completa vueltas en los 3 arquetipos oficiales"
	)
	_assert_true(int(si[9]["checkpoints"]) >= 12, "Nivel 10 generaliza al Circuito Inedito (>= 12 CPs)")
	_assert_true(int(so_eq[9]["vueltas"]) >= 2 or int(so_eq[9]["checkpoints"]) >= 16, "Nivel 10 mantiene conduccion estable con perfil Equilibrado (0.50)")
	_assert_true(
		totales_cps[9] > totales_cps[6] and totales_cps[6] > totales_cps[3] and totales_cps[3] > totales_cps[0],
		"Progresion clara por bloques en checkpoints totales (N1 < N4 < N7 < N10)"
	)

	print("=== Resumen Benchmark: %d verificaciones, %d fallos ===" % [_total_checks, _failures])
	quit(0 if _failures == 0 else 1)