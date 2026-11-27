class_name ArquetiposPista
extends RefCounted

## Biblioteca compartida de arquetipos de circuitos cerrados válidos (45x27, 16x16 px).
## Reutilizada por Vista 2 (Creador de Mapas) y EntrenadorGenetico.

const OVALO_CLASICO := 0
const S_ENLAZADAS := 1
const HORQUILLA_TECNICA := 2

const WAYPOINTS_OVALO: Array[Vector2i] = [
	Vector2i(10, 4),
	Vector2i(34, 4),
	Vector2i(39, 6),
	Vector2i(41, 10),
	Vector2i(41, 16),
	Vector2i(39, 20),
	Vector2i(34, 22),
	Vector2i(10, 22),
	Vector2i(5, 20),
	Vector2i(3, 16),
	Vector2i(3, 10),
	Vector2i(5, 6),
	Vector2i(10, 4),
]

const WAYPOINTS_S_ENLAZADAS: Array[Vector2i] = [
	Vector2i(7, 4),
	Vector2i(15, 4),
	Vector2i(19, 10),
	Vector2i(25, 10),
	Vector2i(29, 4),
	Vector2i(38, 4),
	Vector2i(41, 7),
	Vector2i(41, 19),
	Vector2i(38, 22),
	Vector2i(32, 22),
	Vector2i(28, 17),
	Vector2i(20, 17),
	Vector2i(16, 22),
	Vector2i(7, 22),
	Vector2i(4, 19),
	Vector2i(4, 7),
	Vector2i(7, 4),
]

const WAYPOINTS_HORQUILLA: Array[Vector2i] = [
	Vector2i(3, 3),
	Vector2i(41, 3),
	Vector2i(41, 24),
	Vector2i(31, 24),
	Vector2i(31, 10),
	Vector2i(23, 10),
	Vector2i(23, 24),
	Vector2i(3, 24),
	Vector2i(3, 17),
	Vector2i(16, 17),
	Vector2i(16, 10),
	Vector2i(3, 10),
	Vector2i(3, 3),
]


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


static func obtener_lista() -> Array[Dictionary]:
	return [
		{
			"id": OVALO_CLASICO,
			"clave": "ovalo_clasico",
			"nombre": "Óvalo Clásico",
			"descripcion": "Rectas largas y curvas amplias (ideal para velocidad pura y niveles 1–5).",
			"grosor_sugerido": 3,
		},
		{
			"id": S_ENLAZADAS,
			"clave": "s_enlazadas",
			"nombre": "S-Enlazadas",
			"descripcion": "Cambios continuos de dirección (ideal para agarre, control y estabilidad).",
			"grosor_sugerido": 3,
		},
		{
			"id": HORQUILLA_TECNICA,
			"clave": "horquilla_tecnica",
			"nombre": "Horquilla Técnica",
			"descripcion": "Rectas rápidas seguidas de giros cerrados (ideal para frenado, reversa y niveles 7–10).",
			"grosor_sugerido": 3,
		},
	]


static func obtener_arquetipo(indice_o_clave: Variant, tam_celda: int = 16) -> Dictionary:
	var id := _resolver_id(indice_o_clave)
	var lista := obtener_lista()
	var meta_info: Dictionary = lista[id]

	var waypoints: Array[Vector2i] = WAYPOINTS_OVALO
	var celda_meta := Vector2i(18, 4)

	if id == S_ENLAZADAS:
		waypoints = WAYPOINTS_S_ENLAZADAS
		celda_meta = Vector2i(10, 4)
	elif id == HORQUILLA_TECNICA:
		waypoints = WAYPOINTS_HORQUILLA
		celda_meta = Vector2i(12, 3)

	var grosor := int(meta_info["grosor_sugerido"])
	var radio_brocha := maxi(0, (grosor - 1) / 2)
	var celdas := construir_celdas_trazo(waypoints, radio_brocha)
	var validacion := GeneradorCheckpoints.validar_y_generar(celdas, celda_meta, true, tam_celda)

	return {
		"id": id,
		"clave": meta_info["clave"],
		"nombre": meta_info["nombre"],
		"descripcion": meta_info["descripcion"],
		"grosor_sugerido": grosor,
		"celdas": celdas,
		"celda_meta": celda_meta,
		"tam_celda": tam_celda,
		"validacion": validacion,
	}


static func _resolver_id(indice_o_clave: Variant) -> int:
	if indice_o_clave is int:
		var idx := int(indice_o_clave)
		if idx >= OVALO_CLASICO and idx <= HORQUILLA_TECNICA:
			return idx
		return OVALO_CLASICO

	if indice_o_clave is String:
		var clave := String(indice_o_clave).strip_edges().to_lower()
		for item in obtener_lista():
			if String(item["clave"]).to_lower() == clave or String(item["nombre"]).to_lower() == clave:
				return int(item["id"])
	return OVALO_CLASICO
