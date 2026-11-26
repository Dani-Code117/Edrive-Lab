class_name CerebroEntrenado
extends Resource

## Recurso serializable (.tres) que almacena los pesos, sesgos y metadatos
## educativos de una red neuronal entrenada (topología fija 18 -> 8 -> 2).

const RUTA_DIRECTORIO_PRESETS := "res://Assets/Presets_ia/"
const PATRON_RUTA_PRESET := "res://Assets/Presets_ia/nivel_%02d.tres"
const NUM_ENTRADAS_ESPERADO: int = 18
const NUM_OCULTA_ESPERADO: int = 8
const NUM_SALIDA_ESPERADO: int = 2
const TOTAL_PESOS_OCULTA: int = NUM_ENTRADAS_ESPERADO * NUM_OCULTA_ESPERADO # 144
const TOTAL_PESOS_SALIDA: int = NUM_OCULTA_ESPERADO * NUM_SALIDA_ESPERADO   # 16

@export_range(1, 10) var nivel: int = 1
@export var titulo: String = ""
@export_multiline var descripcion_educativa: String = ""
@export var num_entradas: int = NUM_ENTRADAS_ESPERADO
@export var num_oculta: int = NUM_OCULTA_ESPERADO
@export var num_salida: int = NUM_SALIDA_ESPERADO
@export var pesos_oculta: PackedFloat64Array = PackedFloat64Array()
@export var sesgos_oculta: PackedFloat64Array = PackedFloat64Array()
@export var pesos_salida: PackedFloat64Array = PackedFloat64Array()
@export var sesgos_salida: PackedFloat64Array = PackedFloat64Array()
@export var fitness_alcanzado: float = 0.0


func _init() -> void:
	inicializar_vacio()


func inicializar_vacio() -> void:
	num_entradas = NUM_ENTRADAS_ESPERADO
	num_oculta = NUM_OCULTA_ESPERADO
	num_salida = NUM_SALIDA_ESPERADO
	pesos_oculta = PackedFloat64Array()
	pesos_oculta.resize(TOTAL_PESOS_OCULTA)
	pesos_oculta.fill(0.0)
	sesgos_oculta = PackedFloat64Array()
	sesgos_oculta.resize(NUM_OCULTA_ESPERADO)
	sesgos_oculta.fill(0.0)
	pesos_salida = PackedFloat64Array()
	pesos_salida.resize(TOTAL_PESOS_SALIDA)
	pesos_salida.fill(0.0)
	sesgos_salida = PackedFloat64Array()
	sesgos_salida.resize(NUM_SALIDA_ESPERADO)
	sesgos_salida.fill(0.0)
	if not is_finite(fitness_alcanzado):
		fitness_alcanzado = 0.0


func es_valido() -> bool:
	if nivel < 1 or nivel > 10:
		return false
	if num_entradas != NUM_ENTRADAS_ESPERADO:
		return false
	if num_oculta != NUM_OCULTA_ESPERADO:
		return false
	if num_salida != NUM_SALIDA_ESPERADO:
		return false
	if pesos_oculta.size() != TOTAL_PESOS_OCULTA:
		return false
	if sesgos_oculta.size() != NUM_OCULTA_ESPERADO:
		return false
	if pesos_salida.size() != TOTAL_PESOS_SALIDA:
		return false
	if sesgos_salida.size() != NUM_SALIDA_ESPERADO:
		return false
	if not is_finite(fitness_alcanzado):
		return false

	return (
		_todos_finitos(pesos_oculta)
		and _todos_finitos(sesgos_oculta)
		and _todos_finitos(pesos_salida)
		and _todos_finitos(sesgos_salida)
	)


static func ruta_para_nivel(p_nivel: int) -> String:
	return PATRON_RUTA_PRESET % clampi(p_nivel, 1, 10)


static func _todos_finitos(arr: PackedFloat64Array) -> bool:
	for v in arr:
		if not is_finite(v):
			return false
	return true
