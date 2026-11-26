class_name GeneradorCheckpoints
extends RefCounted

## Valida que el circuito dibujado sea un lazo cerrado con meta y genera
## los checkpoints invisibles ordenados estrictamente en sentido horario.

const PASO_CHECKPOINT: int = 3
const MIN_CELDAS_CIRCUITO: int = 8

const VECINOS_4: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const VECINOS_8: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
]


static func validar_y_generar(
	celdas_asfalto: Dictionary,
	celda_meta: Vector2i,
	tiene_meta: bool,
	tamanio_celda: int = 16
) -> Dictionary:
	if celdas_asfalto.size() < 9:
		return _error("Dibuja un circuito cerrado con la brocha 3x3.")

	if not tiene_meta or not celdas_asfalto.has(celda_meta):
		return _error("Coloca la línea de meta sobre una celda de asfalto.")

	# 1. Verificar que todo el asfalto esté conectado en un solo componente.
	var visitadas := _bfs_conectividad(celdas_asfalto, celda_meta)
	if visitadas.size() != celdas_asfalto.size():
		return _error("Toda la pista debe estar conectada en un solo circuito.")

	# 2. Verificar lazo cerrado mediante flood fill del pasto exterior.
	if not _tiene_hueco_interior(celdas_asfalto):
		return _error("El circuito debe formar un lazo cerrado alrededor de un área interior.")

	# 3. Extraer eje central (Distance Transform + adelgazamiento) y podar espolones muertos.
	var eje_bruto := _extraer_eje_central(celdas_asfalto)
	var eje_central := _podar_espolones(eje_bruto)
	if eje_central.size() < MIN_CELDAS_CIRCUITO:
		return _error("El circuito es demasiado pequeño o estrecho.")

	# 4. Trazar ciclo desde la celda central más cercana a la meta.
	var inicio_bruto := _celda_mas_cercana(eje_bruto, celda_meta)
	var inicio := _celda_mas_cercana(eje_central, celda_meta)
	var dist_bruto := Vector2(celda_meta).distance_squared_to(Vector2(inicio_bruto))
	var dist_poda := Vector2(celda_meta).distance_squared_to(Vector2(inicio))
	if dist_poda > dist_bruto:
		return _error("Asegúrate de que la meta esté sobre el lazo cerrado del circuito.")

	var ciclo := _trazar_ciclo(eje_central, inicio)
	if ciclo.size() < MIN_CELDAS_CIRCUITO:
		return _error("Asegúrate de que la meta esté sobre el lazo cerrado del circuito.")

	# 5. Ordenar estrictamente en sentido horario (producto cruzado positivo en Godot 2D).
	ciclo = _asegurar_sentido_horario(ciclo)

	# 6. Calcular el radio local de pista en cada punto del eje central.
	var radios_eje := _calcular_radios_eje(celdas_asfalto, ciclo, tamanio_celda)

	# 7. Seleccionar 1 de cada N celdas para los checkpoints (empezando adelante de la meta).
	var checkpoints := _submuestrear_checkpoints(ciclo, PASO_CHECKPOINT)
	if checkpoints.size() < 3:
		return _error("El circuito necesita ser un poco más largo para generar checkpoints.")

	var pos_meta := Vector2(celda_meta) * tamanio_celda + Vector2.ONE * (tamanio_celda * 0.5)
	var pos_cp0 := Vector2(checkpoints[0]) * tamanio_celda + Vector2.ONE * (tamanio_celda * 0.5)
	var rotacion_salida := (pos_cp0 - pos_meta).angle()

	return {
		"valido": true,
		"mensaje": "¡Pista válida! (%d checkpoints en sentido horario)" % checkpoints.size(),
		"checkpoints": checkpoints,
		"eje_central": ciclo,
		"radios_eje": radios_eje,
		"rotacion_salida": rotacion_salida,
	}


static func _error(msg: String) -> Dictionary:
	return {
		"valido": false,
		"mensaje": msg,
		"checkpoints": [] as Array[Vector2i],
		"eje_central": [] as Array[Vector2i],
		"radios_eje": [] as Array[float],
		"rotacion_salida": 0.0,
	}


static func _bfs_conectividad(celdas: Dictionary, origen: Vector2i) -> Dictionary:
	var visitadas: Dictionary = {origen: true}
	var cola: Array[Vector2i] = [origen]
	var idx: int = 0

	while idx < cola.size():
		var actual := cola[idx]
		idx += 1
		for dir in VECINOS_4:
			var sig := actual + dir
			if celdas.has(sig) and not visitadas.has(sig):
				visitadas[sig] = true
				cola.append(sig)

	return visitadas


static func _tiene_hueco_interior(celdas_asfalto: Dictionary) -> bool:
	var min_x := 999999
	var max_x := -999999
	var min_y := 999999
	var max_y := -999999

	for c: Vector2i in celdas_asfalto.keys():
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)

	min_x -= 1
	max_x += 1
	min_y -= 1
	max_y += 1

	var inicio_ext := Vector2i(min_x, min_y)
	var exterior: Dictionary = {inicio_ext: true}
	var cola: Array[Vector2i] = [inicio_ext]
	var idx: int = 0

	while idx < cola.size():
		var actual := cola[idx]
		idx += 1
		for dir in VECINOS_4:
			var sig := actual + dir
			if sig.x < min_x or sig.x > max_x or sig.y < min_y or sig.y > max_y:
				continue
			if not celdas_asfalto.has(sig) and not exterior.has(sig):
				exterior[sig] = true
				cola.append(sig)

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var p := Vector2i(x, y)
			if not celdas_asfalto.has(p) and not exterior.has(p):
				return true

	return false


static func _calcular_radios_eje(
	celdas_asfalto: Dictionary,
	ciclo: Array[Vector2i],
	tamanio_celda: int
) -> Array[float]:
	var distancias: Dictionary = {}
	var cola: Array[Vector2i] = []

	for c: Vector2i in celdas_asfalto.keys():
		var toca_pasto := false
		for dir in VECINOS_8:
			if not celdas_asfalto.has(c + dir):
				toca_pasto = true
				break
		if toca_pasto:
			distancias[c] = 1
			cola.append(c)

	var idx: int = 0
	while idx < cola.size():
		var actual := cola[idx]
		idx += 1
		var d: int = distancias[actual]
		for dir in VECINOS_8:
			var sig := actual + dir
			if celdas_asfalto.has(sig) and not distancias.has(sig):
				distancias[sig] = d + 1
				cola.append(sig)

	var radios: Array[float] = []
	for c in ciclo:
		var d: int = distancias.get(c, 1)
		radios.append((float(d) - 0.5) * float(tamanio_celda))
	return radios


static func _extraer_eje_central(celdas_asfalto: Dictionary) -> Dictionary:
	return _adelgazar_esqueleto(celdas_asfalto)


static func _adelgazar_esqueleto(celdas: Dictionary) -> Dictionary:
	var res := celdas.duplicate()
	var cambio := true
	var iter := 0

	while cambio and iter < 20:
		cambio = false
		iter += 1
		for paso in [0, 1]:
			var a_borrar: Array[Vector2i] = []
			for p: Vector2i in res.keys():
				if _puede_adelgazar(res, p, paso):
					a_borrar.append(p)
			if a_borrar.size() > 0:
				cambio = true
				for p in a_borrar:
					res.erase(p)

	return res


static func _podar_espolones(eje: Dictionary) -> Dictionary:
	var res := eje.duplicate()
	var cambio := true
	while cambio:
		cambio = false
		var a_borrar: Array[Vector2i] = []
		for p: Vector2i in res.keys():
			var vecinos := 0
			for dir in VECINOS_8:
				if res.has(p + dir):
					vecinos += 1
			if vecinos <= 1:
				a_borrar.append(p)
		if not a_borrar.is_empty():
			cambio = true
			for p in a_borrar:
				res.erase(p)
	return res


static func _puede_adelgazar(celdas: Dictionary, p: Vector2i, paso: int) -> bool:
	# Vecinos en orden horario empezando desde arriba (N, NE, E, SE, S, SO, O, NO)
	var v: Array[int] = []
	var negros := 0
	for dir in VECINOS_8:
		var ocupado := 1 if celdas.has(p + dir) else 0
		v.append(ocupado)
		negros += ocupado

	if negros < 2 or negros > 6:
		return false

	# Transiciones 0 -> 1 alrededor del píxel
	var transiciones := 0
	for i in range(8):
		if v[i] == 0 and v[(i + 1) % 8] == 1:
			transiciones += 1
	if transiciones != 1:
		return false

	# v[0]=N, v[2]=E, v[4]=S, v[6]=O
	if paso == 0:
		if v[0] * v[2] * v[4] != 0:
			return false
		if v[2] * v[4] * v[6] != 0:
			return false
	else:
		if v[0] * v[2] * v[6] != 0:
			return false
		if v[0] * v[4] * v[6] != 0:
			return false

	return true


static func _celda_mas_cercana(celdas: Dictionary, objetivo: Vector2i) -> Vector2i:
	var mejor := objetivo
	var mejor_dist := INF
	for c: Vector2i in celdas.keys():
		var d := Vector2(c).distance_squared_to(Vector2(objetivo))
		if d < mejor_dist:
			mejor_dist = d
			mejor = c
	return mejor


static func _trazar_ciclo(eje: Dictionary, inicio: Vector2i) -> Array[Vector2i]:
	if not eje.has(inicio):
		return []

	var min_largo_cps := maxi(MIN_CELDAS_CIRCUITO, PASO_CHECKPOINT * 3 + 1)
	var ruta: Array[Vector2i] = [inicio]
	var visitadas: Dictionary = {inicio: true}
	var pasos_restantes := [maxi(eje.size() * 16, 512)]
	if _dfs_ciclo(eje, inicio, inicio, ruta, visitadas, pasos_restantes, min_largo_cps):
		return ruta

	# Fallback determinista O(|V|) para mallas con múltiples huecos donde el DFS agota pasos.
	var ciclo_planar := _trazar_ciclo_planar(eje, inicio, min_largo_cps)
	if ciclo_planar.size() >= min_largo_cps:
		return ciclo_planar

	var ciclo_bfs := _trazar_ciclo_bfs(eje, inicio, min_largo_cps)
	if ciclo_bfs.size() >= min_largo_cps:
		return ciclo_bfs

	if not ciclo_planar.is_empty():
		return ciclo_planar
	return ciclo_bfs


static func _dfs_ciclo(
	eje: Dictionary,
	inicio: Vector2i,
	actual: Vector2i,
	ruta: Array[Vector2i],
	visitadas: Dictionary,
	pasos_restantes: Array,
	min_largo: int = MIN_CELDAS_CIRCUITO
) -> bool:
	if pasos_restantes[0] <= 0:
		return false
	pasos_restantes[0] -= 1

	# Cerrar el ciclo si volvemos a estar adyacentes al inicio tras avanzar lo suficiente
	if ruta.size() >= min_largo:
		var dist_inicio := actual - inicio
		if absi(dist_inicio.x) <= 1 and absi(dist_inicio.y) <= 1:
			return true

	# Priorizar vecinos ortogonales (4-conectados) antes que diagonales
	var candidatos: Array[Vector2i] = []
	for dir in VECINOS_4:
		var cand := actual + dir
		if eje.has(cand) and not visitadas.has(cand):
			candidatos.append(cand)
	for dir in VECINOS_8:
		var cand := actual + dir
		if eje.has(cand) and not visitadas.has(cand) and not candidatos.has(cand):
			candidatos.append(cand)

	for cand in candidatos:
		ruta.append(cand)
		visitadas[cand] = true
		if _dfs_ciclo(eje, inicio, cand, ruta, visitadas, pasos_restantes, min_largo):
			return true
		visitadas.erase(cand)
		ruta.pop_back()

	return false


static func _arista_valida_eje(eje: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if not eje.has(b):
		return false
	var d := b - a
	if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
		return false
	# Evitar atajos diagonales cuando existe una esquina ortogonal en el esqueleto
	if d.x != 0 and d.y != 0:
		if eje.has(Vector2i(a.x, b.y)) or eje.has(Vector2i(b.x, a.y)):
			return false
	return true


static func _trazar_ciclo_planar(eje: Dictionary, inicio: Vector2i, min_largo: int) -> Array[Vector2i]:
	var vecinos_ini: Array[Vector2i] = []
	for dir in VECINOS_4:
		var c := inicio + dir
		if _arista_valida_eje(eje, inicio, c):
			vecinos_ini.append(c)
	for dir in VECINOS_8:
		var c := inicio + dir
		if _arista_valida_eje(eje, inicio, c) and not vecinos_ini.has(c):
			vecinos_ini.append(c)

	var mejor_corto: Array[Vector2i] = []
	var max_pasos := eje.size() + 2
	for nxt in vecinos_ini:
		for sentido in [1, -1]:
			var ruta: Array[Vector2i] = [inicio, nxt]
			var visitadas: Dictionary = {inicio: true, nxt: true}
			var prev := inicio
			var curr := nxt
			for _step in range(max_pasos):
				if ruta.size() >= min_largo and _arista_valida_eje(eje, curr, inicio):
					return ruta
				var back_idx := VECINOS_8.find(prev - curr)
				if back_idx == -1:
					break
				var elegido := Vector2i.ZERO
				var encontro := false
				for k in range(1, 8):
					var dir := VECINOS_8[(back_idx + sentido * k + 8) % 8]
					var cand := curr + dir
					if not _arista_valida_eje(eje, curr, cand):
						continue
					if cand == inicio and ruta.size() >= min_largo:
						return ruta
					if not visitadas.has(cand):
						elegido = cand
						encontro = true
						break
				if not encontro:
					break
				prev = curr
				curr = elegido
				ruta.append(curr)
				visitadas[curr] = true
			if ruta.size() >= MIN_CELDAS_CIRCUITO and _arista_valida_eje(eje, curr, inicio):
				if mejor_corto.is_empty():
					mejor_corto = ruta
	return mejor_corto


static func _trazar_ciclo_bfs(eje: Dictionary, inicio: Vector2i, min_largo: int) -> Array[Vector2i]:
	var vecinos_ini: Array[Vector2i] = []
	for dir in VECINOS_4:
		var c := inicio + dir
		if _arista_valida_eje(eje, inicio, c):
			vecinos_ini.append(c)
	for dir in VECINOS_8:
		var c := inicio + dir
		if _arista_valida_eje(eje, inicio, c) and not vecinos_ini.has(c):
			vecinos_ini.append(c)
	if vecinos_ini.size() < 2:
		return []

	var es_vecino_ini: Dictionary = {}
	for v in vecinos_ini:
		es_vecino_ini[v] = true

	var bloqueadas: Dictionary = {}
	var mejor_corto := _bfs_ciclo_con_bloqueo(eje, inicio, vecinos_ini, es_vecino_ini, min_largo, bloqueadas)
	if mejor_corto.size() >= min_largo:
		return mejor_corto

	if not mejor_corto.is_empty():
		var largo := _buscar_ciclo_largo_bfs(eje, inicio, vecinos_ini, es_vecino_ini, min_largo, mejor_corto, bloqueadas, 3)
		if largo.size() >= min_largo:
			return largo

	return mejor_corto


static func _clave_arista(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


static func _bfs_ciclo_con_bloqueo(
	eje: Dictionary,
	inicio: Vector2i,
	vecinos_ini: Array[Vector2i],
	es_vecino_ini: Dictionary,
	min_largo: int,
	aristas_bloqueadas: Dictionary
) -> Array[Vector2i]:
	var mejor_corto: Array[Vector2i] = []
	for s in vecinos_ini:
		if aristas_bloqueadas.has(_clave_arista(inicio, s)):
			continue
		var padre: Dictionary = {s: inicio}
		var dist: Dictionary = {s: 1}
		var cola: Array[Vector2i] = [s]
		var idx := 0
		while idx < cola.size():
			var u := cola[idx]
			idx += 1
			var d: int = dist[u]
			if u != s and es_vecino_ini.has(u) and d + 1 >= MIN_CELDAS_CIRCUITO:
				var ciclo := _reconstruir_ciclo_bfs(padre, u, inicio)
				if ciclo.size() >= min_largo:
					return ciclo
				if mejor_corto.is_empty():
					mejor_corto = ciclo
			for dir in VECINOS_4:
				var v := u + dir
				if v == inicio or not _arista_valida_eje(eje, u, v):
					continue
				if aristas_bloqueadas.has(_clave_arista(u, v)):
					continue
				if not dist.has(v):
					dist[v] = d + 1
					padre[v] = u
					cola.append(v)
			for dir in VECINOS_8:
				var v := u + dir
				if v == inicio or not _arista_valida_eje(eje, u, v):
					continue
				if aristas_bloqueadas.has(_clave_arista(u, v)):
					continue
				if not dist.has(v):
					dist[v] = d + 1
					padre[v] = u
					cola.append(v)
	return mejor_corto


static func _buscar_ciclo_largo_bfs(
	eje: Dictionary,
	inicio: Vector2i,
	vecinos_ini: Array[Vector2i],
	es_vecino_ini: Dictionary,
	min_largo: int,
	ciclo_corto: Array[Vector2i],
	aristas_bloqueadas: Dictionary,
	prof_restante: int
) -> Array[Vector2i]:
	if prof_restante <= 0:
		return []
	for i in range(1, ciclo_corto.size() - 1):
		var k := _clave_arista(ciclo_corto[i], ciclo_corto[i + 1])
		if aristas_bloqueadas.has(k):
			continue
		aristas_bloqueadas[k] = true
		var cand := _bfs_ciclo_con_bloqueo(eje, inicio, vecinos_ini, es_vecino_ini, min_largo, aristas_bloqueadas)
		if cand.size() >= min_largo:
			aristas_bloqueadas.erase(k)
			return cand
		if not cand.is_empty() and prof_restante > 1:
			var mas_largo := _buscar_ciclo_largo_bfs(
				eje, inicio, vecinos_ini, es_vecino_ini, min_largo, cand, aristas_bloqueadas, prof_restante - 1
			)
			if mas_largo.size() >= min_largo:
				aristas_bloqueadas.erase(k)
				return mas_largo
		aristas_bloqueadas.erase(k)
	return []


static func _reconstruir_ciclo_bfs(padre: Dictionary, fin: Vector2i, inicio: Vector2i) -> Array[Vector2i]:
	var rev: Array[Vector2i] = []
	var cur := fin
	while cur != inicio and padre.has(cur):
		rev.append(cur)
		cur = padre[cur]
	rev.append(inicio)
	rev.reverse()
	return rev


static func _asegurar_sentido_horario(ciclo: Array[Vector2i]) -> Array[Vector2i]:
	if ciclo.size() < 3:
		return ciclo

	var centroide := Vector2.ZERO
	for p in ciclo:
		centroide += Vector2(p)
	centroide /= float(ciclo.size())

	var suma_cruz := 0.0
	var n := ciclo.size()
	for i in range(n):
		var p1 := Vector2(ciclo[i]) - centroide
		var p2 := Vector2(ciclo[(i + 1) % n]) - centroide
		suma_cruz += p1.x * p2.y - p1.y * p2.x

	# En Godot 2D (+X derecha, +Y abajo), producto cruzado positivo = sentido horario.
	if suma_cruz < 0.0:
		var invertido: Array[Vector2i] = [ciclo[0]]
		for i in range(n - 1, 0, -1):
			invertido.append(ciclo[i])
		return invertido

	return ciclo


static func _submuestrear_checkpoints(ciclo: Array[Vector2i], paso: int) -> Array[Vector2i]:
	var resultado: Array[Vector2i] = []
	var n := ciclo.size()
	var i := paso
	while i < n:
		resultado.append(ciclo[i])
		i += paso
	if resultado.is_empty() and n >= 3:
		resultado.append(ciclo[n / 2])
	return resultado
