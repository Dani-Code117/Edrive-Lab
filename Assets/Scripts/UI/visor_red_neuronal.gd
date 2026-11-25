class_name VisorRedNeuronal
extends Control

## Visor en tiempo real de la red neuronal 7 -> 6 -> 2 del vehículo seleccionado.
## Dibuja conexiones ponderadas (pesos_oculta[j * 7 + i], pesos_salida[k * 6 + j])
## y activaciones en vivo desde RedNeuronal / VehiculoAgente usando _draw().

const NUM_ENTRADAS: int = 7
const NUM_OCULTA: int = 6
const NUM_SALIDA: int = 2
const ETIQUETAS_SENSORES: Array[String] = ["-90°", "-45°", "-15°", "0°", "+15°", "+45°", "+90°"]
const ETIQUETAS_SALIDAS: Array[String] = ["Acel", "Giro"]

const COLOR_FONDO := Color(0.045, 0.062, 0.092, 0.96)
const COLOR_BORDE := Color(0.165, 0.212, 0.282, 1.0)
const COLOR_POSITIVO := Color(0.0, 0.898, 1.0, 1.0)
const COLOR_VERDE := Color(0.24, 0.88, 0.48, 1.0)
const COLOR_NEGATIVO := Color(0.98, 0.34, 0.34, 1.0)
const COLOR_INACTIVO := Color(0.14, 0.19, 0.27, 1.0)
const COLOR_TEXTO := Color(0.84, 0.90, 0.96, 1.0)
const COLOR_TEXTO_TENUE := Color(0.56, 0.64, 0.74, 1.0)

var vehiculo_objetivo: VehiculoAgente = null


func _ready() -> void:
	clip_contents = true
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(300, 220)
	queue_redraw()


func _process(_delta: float) -> void:
	if visible and is_visible_in_tree() and vehiculo_objetivo != null and is_instance_valid(vehiculo_objetivo):
		actualizar_visor()


func establecer_vehiculo(vehiculo: VehiculoAgente) -> void:
	vehiculo_objetivo = vehiculo
	queue_redraw()


func actualizar_visor() -> void:
	queue_redraw()


func obtener_instantanea_segura() -> Dictionary:
	var entradas := PackedFloat64Array()
	entradas.resize(NUM_ENTRADAS)
	entradas.fill(0.0)

	var ocultas := PackedFloat64Array()
	ocultas.resize(NUM_OCULTA)
	ocultas.fill(0.0)

	var salidas := PackedFloat64Array()
	salidas.resize(NUM_SALIDA)
	salidas.fill(0.0)

	var pesos_oc := PackedFloat64Array()
	pesos_oc.resize(NUM_ENTRADAS * NUM_OCULTA)
	pesos_oc.fill(0.0)

	var pesos_sal := PackedFloat64Array()
	pesos_sal.resize(NUM_OCULTA * NUM_SALIDA)
	pesos_sal.fill(0.0)

	var tiene_vehiculo := vehiculo_objetivo != null and is_instance_valid(vehiculo_objetivo)
	var nombre_coche := "Sin vehículo seleccionado"
	var nivel_ia := 0
	var color_coche := COLOR_POSITIVO
	var tiene_red := false

	if tiene_vehiculo:
		nombre_coche = vehiculo_objetivo.nombre_vehiculo
		nivel_ia = vehiculo_objetivo.nivel_ia
		color_coche = vehiculo_objetivo.color_vehiculo

		var sensores: PackedFloat64Array = vehiculo_objetivo.lecturas_sensores
		for i in range(mini(NUM_ENTRADAS, sensores.size())):
			entradas[i] = _sanitizar_float(sensores[i], 0.0, 1.0, 0.0)

		var cer: Variant = vehiculo_objetivo.cerebro
		if cer != null and (cer is RedNeuronal or (cer is Object and "pesos_oculta" in cer and "pesos_salida" in cer)):
			tiene_red = true
			var u_ent: Variant = cer.get("ultimas_entradas")
			if u_ent is PackedFloat64Array and u_ent.size() >= NUM_ENTRADAS:
				for i in range(NUM_ENTRADAS):
					entradas[i] = _sanitizar_float(u_ent[i], 0.0, 1.0, entradas[i])

			var u_ocu: Variant = cer.get("ultimas_ocultas")
			if u_ocu is PackedFloat64Array:
				for j in range(mini(NUM_OCULTA, u_ocu.size())):
					ocultas[j] = _sanitizar_float(u_ocu[j], -1.0, 1.0, 0.0)

			var u_sal: Variant = cer.get("ultimas_salidas")
			if u_sal is PackedFloat64Array:
				if u_sal.size() > 0:
					salidas[0] = _sanitizar_float(u_sal[0], 0.0, 1.0, 0.0)
				if u_sal.size() > 1:
					salidas[1] = _sanitizar_float(u_sal[1], -1.0, 1.0, 0.0)

			var p_oc: Variant = cer.get("pesos_oculta")
			if p_oc is PackedFloat64Array:
				for idx in range(mini(pesos_oc.size(), p_oc.size())):
					pesos_oc[idx] = _sanitizar_float(p_oc[idx], -10.0, 10.0, 0.0)

			var p_sa: Variant = cer.get("pesos_salida")
			if p_sa is PackedFloat64Array:
				for idx in range(mini(pesos_sal.size(), p_sa.size())):
					pesos_sal[idx] = _sanitizar_float(p_sa[idx], -10.0, 10.0, 0.0)

	return {
		"tiene_vehiculo": tiene_vehiculo,
		"tiene_red": tiene_red,
		"nombre": nombre_coche,
		"nivel_ia": nivel_ia,
		"color": color_coche,
		"entradas": entradas,
		"ocultas": ocultas,
		"salidas": salidas,
		"pesos_oculta": pesos_oc,
		"pesos_salida": pesos_sal,
	}


func _draw() -> void:
	if size.x <= 8.0 or size.y <= 8.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_FONDO, true)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDE, false, 1.5)

	var datos := obtener_instantanea_segura()
	var entradas: PackedFloat64Array = datos["entradas"]
	var ocultas: PackedFloat64Array = datos["ocultas"]
	var salidas: PackedFloat64Array = datos["salidas"]
	var pesos_oc: PackedFloat64Array = datos["pesos_oculta"]
	var pesos_sal: PackedFloat64Array = datos["pesos_salida"]
	var tiene_vehiculo: bool = datos["tiene_vehiculo"]
	var tiene_red: bool = datos["tiene_red"]

	var fuente := get_theme_default_font()
	if fuente == null:
		fuente = ThemeDB.fallback_font

	# Encabezado compacto
	var pad_x := 10.0
	var header_h := 24.0
	var footer_h := 16.0
	if tiene_vehiculo:
		var col_titulo: Color = (datos["color"] as Color).lightened(0.28)
		var txt_izq := "%s (IA %d)" % [datos["nombre"], datos["nivel_ia"]]
		draw_string(fuente, Vector2(pad_x, 16.0), txt_izq, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.52, 12, col_titulo)
		var txt_der := "Acel %.2f | Giro %+.2f" % [salidas[0], salidas[1]]
		draw_string(fuente, Vector2(size.x * 0.45, 16.0), txt_der, HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.55 - pad_x, 11, COLOR_TEXTO)
	else:
		draw_string(fuente, Vector2(pad_x, 16.0), "Sin vehículo seleccionado", HORIZONTAL_ALIGNMENT_LEFT, size.x - pad_x * 2.0, 12, COLOR_TEXTO_TENUE)

	draw_line(Vector2(6.0, header_h), Vector2(size.x - 6.0, header_h), COLOR_BORDE, 1.0)

	# Posiciones de las 3 capas (7 -> 6 -> 2)
	var area_top := header_h + 14.0
	var area_bottom := size.y - footer_h - 14.0
	var area_h := maxf(area_bottom - area_top, 40.0)

	var x_in := clampf(size.x * 0.22, 46.0, 90.0)
	var x_hid := size.x * 0.53
	var x_out := minf(size.x * 0.80, size.x - 58.0)

	var pos_in: Array[Vector2] = []
	for i in range(NUM_ENTRADAS):
		var t := float(i) / float(NUM_ENTRADAS - 1)
		pos_in.append(Vector2(x_in, area_top + t * area_h))

	var pos_hid: Array[Vector2] = []
	for j in range(NUM_OCULTA):
		var t := (float(j) + 0.35) / float(NUM_OCULTA - 0.3)
		pos_hid.append(Vector2(x_hid, area_top + t * area_h))

	var pos_out: Array[Vector2] = [
		Vector2(x_out, area_top + area_h * 0.30),
		Vector2(x_out, area_top + area_h * 0.70),
	]

	# 1. Conexiones Entrada -> Oculta (pesos_oculta[j * 7 + i])
	for j in range(NUM_OCULTA):
		for i in range(NUM_ENTRADAS):
			var w := pesos_oc[j * NUM_ENTRADAS + i]
			var act_pre := clampf(entradas[i], 0.0, 1.0)
			_dibujar_conexion(pos_in[i], pos_hid[j], w, act_pre, tiene_red)

	# 2. Conexiones Oculta -> Salida (pesos_salida[k * 6 + j])
	for k in range(NUM_SALIDA):
		for j in range(NUM_OCULTA):
			var w := pesos_sal[k * NUM_OCULTA + j]
			var act_pre := clampf(absf(ocultas[j]), 0.0, 1.0)
			_dibujar_conexion(pos_hid[j], pos_out[k], w, act_pre, tiene_red)

	# 3. Nodos de Entrada (7 sensores)
	var r_in := clampf(area_h / 24.0, 5.0, 8.0)
	for i in range(NUM_ENTRADAS):
		var val := clampf(entradas[i], 0.0, 1.0)
		var col_relleno := COLOR_NEGATIVO.lerp(COLOR_POSITIVO, val) if tiene_vehiculo else COLOR_INACTIVO
		var alpha := 0.35 + 0.65 * val if tiene_vehiculo else 0.45
		col_relleno.a = alpha
		draw_circle(pos_in[i], r_in, COLOR_FONDO)
		draw_circle(pos_in[i], r_in - 1.0, col_relleno)
		var col_borde := Color(0.95, 0.98, 1.0, 0.85) if (tiene_vehiculo and val < 0.25) else COLOR_BORDE.lightened(0.35)
		draw_arc(pos_in[i], r_in, 0.0, TAU, 20, col_borde, 1.2)
		draw_string(fuente, Vector2(4.0, pos_in[i].y + 4.0), ETIQUETAS_SENSORES[i], HORIZONTAL_ALIGNMENT_RIGHT, x_in - r_in - 8.0, 10, COLOR_TEXTO_TENUE)

	# 4. Nodos Ocultos (6 neuronas tanh en [-1..1])
	var r_hid := clampf(area_h / 22.0, 6.0, 9.0)
	for j in range(NUM_OCULTA):
		var act := clampf(ocultas[j], -1.0, 1.0)
		var mag := absf(act)
		var base_col := COLOR_POSITIVO if act >= 0.0 else COLOR_NEGATIVO
		var col_relleno := COLOR_INACTIVO.lerp(base_col, mag) if tiene_red else COLOR_INACTIVO
		draw_circle(pos_hid[j], r_hid, COLOR_FONDO)
		draw_circle(pos_hid[j], r_hid - 1.0, col_relleno)
		draw_arc(pos_hid[j], r_hid, 0.0, TAU, 22, base_col if (tiene_red and mag > 0.25) else COLOR_BORDE.lightened(0.35), 1.3)

	# 5. Nodos de Salida (Acel [0..1], Giro [-1..1])
	var r_out := clampf(area_h / 18.0, 7.5, 11.0)
	# Aceleración
	var acel := clampf(salidas[0], 0.0, 1.0)
	var col_acel := COLOR_INACTIVO.lerp(COLOR_VERDE, acel) if tiene_red else COLOR_INACTIVO
	draw_circle(pos_out[0], r_out, COLOR_FONDO)
	draw_circle(pos_out[0], r_out - 1.2, col_acel)
	draw_arc(pos_out[0], r_out, 0.0, TAU, 24, COLOR_VERDE if (tiene_red and acel > 0.3) else COLOR_BORDE.lightened(0.4), 1.5)
	draw_string(fuente, Vector2(pos_out[0].x + r_out + 6.0, pos_out[0].y - 1.0), ETIQUETAS_SALIDAS[0], HORIZONTAL_ALIGNMENT_LEFT, 54.0, 11, COLOR_TEXTO)
	draw_string(fuente, Vector2(pos_out[0].x + r_out + 6.0, pos_out[0].y + 11.0), "%.2f" % acel, HORIZONTAL_ALIGNMENT_LEFT, 54.0, 10, COLOR_VERDE if tiene_red else COLOR_TEXTO_TENUE)

	# Giro
	var giro := clampf(salidas[1], -1.0, 1.0)
	var col_base_giro := COLOR_POSITIVO if giro >= 0.0 else COLOR_NEGATIVO
	var col_giro := COLOR_INACTIVO.lerp(col_base_giro, absf(giro)) if tiene_red else COLOR_INACTIVO
	draw_circle(pos_out[1], r_out, COLOR_FONDO)
	draw_circle(pos_out[1], r_out - 1.2, col_giro)
	draw_arc(pos_out[1], r_out, 0.0, TAU, 24, col_base_giro if (tiene_red and absf(giro) > 0.2) else COLOR_BORDE.lightened(0.4), 1.5)
	draw_string(fuente, Vector2(pos_out[1].x + r_out + 6.0, pos_out[1].y - 1.0), ETIQUETAS_SALIDAS[1], HORIZONTAL_ALIGNMENT_LEFT, 54.0, 11, COLOR_TEXTO)
	draw_string(fuente, Vector2(pos_out[1].x + r_out + 6.0, pos_out[1].y + 11.0), "%+.2f" % giro, HORIZONTAL_ALIGNMENT_LEFT, 54.0, 10, col_base_giro if tiene_red else COLOR_TEXTO_TENUE)

	# Etiquetas de columna en pie
	var y_pie := size.y - 4.0
	draw_string(fuente, Vector2(x_in - 32.0, y_pie), "Sensores", HORIZONTAL_ALIGNMENT_CENTER, 64.0, 10, COLOR_TEXTO_TENUE)
	draw_string(fuente, Vector2(x_hid - 32.0, y_pie), "Oculta", HORIZONTAL_ALIGNMENT_CENTER, 64.0, 10, COLOR_TEXTO_TENUE)
	draw_string(fuente, Vector2(x_out - 32.0, y_pie), "Salida", HORIZONTAL_ALIGNMENT_CENTER, 64.0, 10, COLOR_TEXTO_TENUE)


func _dibujar_conexion(p0: Vector2, p1: Vector2, peso: float, act_presinaptica: float, tiene_red: bool) -> void:
	if not tiene_red:
		draw_line(p0, p1, Color(0.28, 0.35, 0.45, 0.16), 1.0)
		return
	var mag := clampf(absf(peso) / 2.5, 0.0, 1.0)
	if mag < 0.02:
		draw_line(p0, p1, Color(0.35, 0.42, 0.52, 0.10), 1.0)
		return
	var alpha := clampf(0.10 + mag * (0.25 + 0.62 * act_presinaptica), 0.08, 0.90)
	var col := COLOR_POSITIVO if peso >= 0.0 else COLOR_NEGATIVO
	col.a = alpha
	var grosor := 0.9 + mag * (0.7 + 1.1 * act_presinaptica)
	draw_line(p0, p1, col, grosor)


func _sanitizar_float(valor: Variant, min_val: float, max_val: float, defecto: float) -> float:
	if valor is float or valor is int:
		var num := float(valor)
		if is_finite(num):
			return clampf(num, min_val, max_val)
	return clampf(defecto, min_val, max_val)
