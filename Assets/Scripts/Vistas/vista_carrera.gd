class_name VistaCarreraUI
extends Control

## Vista 4: Carrera en vivo, reconstrucción de pista y colisiones Layer 1,
## checkpoints horarios invisibles, HUD de telemetría y VisorRedNeuronal.

const ESCENA_CONFIGURACION := "res://Assets/Escenas/Vistas/configuracion_carrera.tscn"
const ESCENA_CREADOR := "res://Assets/Escenas/Vistas/creador_mapa.tscn"
const ESCENA_VEHICULO := "res://Assets/Escenas/Componentes/vehiculo_agente.tscn"
const ESCENA_CHECKPOINT := "res://Assets/Escenas/Componentes/checkpoint.tscn"
const RUTA_BANDERA_META := "res://Assets/Sprites/bandera_meta.png"
const RUTA_SPRITE_COCHE := "res://Assets/Sprites/coche_base.png"
const FACTOR_ZOOM_INSPECCION: float = 3.0
const VEL_SUAVIZADO_CAMARA: float = 10.0

@onready var btn_vel_1x: Button = $Layout/BarraSuperior/Margin/HBox/ControlesVelocidad/BtnVel1x
@onready var btn_vel_2x: Button = $Layout/BarraSuperior/Margin/HBox/ControlesVelocidad/BtnVel2x
@onready var btn_vel_4x: Button = $Layout/BarraSuperior/Margin/HBox/ControlesVelocidad/BtnVel4x
@onready var btn_rayos: Button = $Layout/BarraSuperior/Margin/HBox/BtnRayos
@onready var btn_estela: Button = $Layout/BarraSuperior/Margin/HBox/BtnEstela
@onready var btn_reiniciar: Button = $Layout/BarraSuperior/Margin/HBox/BtnReiniciar
@onready var btn_volver_config: Button = $Layout/BarraSuperior/Margin/HBox/BtnVolverConfig
@onready var btn_editar_mapa: Button = $Layout/BarraSuperior/Margin/HBox/BtnEditarMapa

@onready var area_pista: Control = $Layout/Cuerpo/AreaPista
@onready var viewport_pista: SubViewportContainer = $Layout/Cuerpo/AreaPista/ViewportPista
@onready var sub_viewport_pista: SubViewport = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista
@onready var camara_pista: Camera2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/CamaraPista
@onready var escenario: Node2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario
@onready var tile_map_pista: TileMapLayer = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario/TileMapPista
@onready var pista_visual: Node2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario/PistaVisual
@onready var linea_meta: Node2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario/LineaMeta
@onready var bandera_meta: Sprite2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario/BanderaMeta
@onready var nodo_checkpoints: Node2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario/Checkpoints
@onready var nodo_vehiculos: Node2D = $Layout/Cuerpo/AreaPista/ViewportPista/SubViewportPista/Escenario/Vehiculos

@onready var contenedor_tarjetas: VBoxContainer = $Layout/Cuerpo/PanelHUD/MarginHUD/ScrollHUD/VBoxHUD/TarjetasTelemetria
@onready var lbl_seccion_visor: Label = $Layout/Cuerpo/PanelHUD/MarginHUD/ScrollHUD/VBoxHUD/LblSeccionVisor
@onready var visor_red: VisorRedNeuronal = $Layout/Cuerpo/PanelHUD/MarginHUD/ScrollHUD/VBoxHUD/VisorRed

var _celdas_activas: Dictionary = {}
var _meta_activa: Vector2i = Vector2i(-1, -1)
var _checkpoints_activos: Array[Vector2i] = []
var _eje_activo: Array[Vector2i] = []
var _radios_activos: Array[float] = []
var _ancho_activo: float = 48.0
var _pos_salida_activa: Vector2 = Vector2.ZERO
var _rot_salida_activa: float = 0.0
var _usando_circuito_fallback: bool = false

var _vehiculos: Array[VehiculoAgente] = []
var _checkpoints: Array[CheckpointArea] = []
var _tarjetas_ui: Array[Dictionary] = []
var _indice_inspeccionado: int = -1
var _mostrar_sensores_activo: bool = true
var _mostrar_estela_activo: bool = true
var _cam_pos_completa: Vector2 = Vector2.ZERO
var _cam_zoom_completo: float = 1.0
var _estilo_tarjeta_normal: StyleBoxFlat = null
var _estilo_tarjeta_activa: StyleBoxFlat = null


func _ready() -> void:
	Engine.time_scale = 1.0
	if sub_viewport_pista != null:
		sub_viewport_pista.world_2d = World2D.new()
		sub_viewport_pista.transparent_bg = true
		sub_viewport_pista.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if camara_pista != null:
		camara_pista.enabled = true
		camara_pista.make_current()
	if escenario != null:
		escenario.position = Vector2.ZERO
		escenario.scale = Vector2.ONE

	_preparar_estilos_tarjetas()
	_conectar_controles_barra()

	area_pista.resized.connect(_ajustar_escenario)
	if viewport_pista != null:
		viewport_pista.resized.connect(_ajustar_escenario)
	linea_meta.draw.connect(_on_linea_meta_draw)

	_cargar_datos_circuito()
	_reconstruir_pista()
	_instanciar_checkpoints()
	_configurar_meta_visual()
	DatosSimulacion.sanitizar_config_vehiculos()
	_instanciar_vehiculos()
	_configurar_tarjetas_hud()
	_seleccionar_vehiculo_inspeccion(-1)
	_establecer_velocidad(1.0)
	_actualizar_boton_rayos()
	_actualizar_boton_estela()

	_ajustar_escenario()
	call_deferred("_ajustar_escenario")


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	_actualizar_telemetria_hud()
	_actualizar_camara(delta)


func obtener_vehiculos() -> Array[VehiculoAgente]:
	return _vehiculos


func obtener_checkpoints() -> Array[CheckpointArea]:
	return _checkpoints


func obtener_indice_inspeccionado() -> int:
	return _indice_inspeccionado


func usando_circuito_fallback() -> bool:
	return _usando_circuito_fallback


func _preparar_estilos_tarjetas() -> void:
	_estilo_tarjeta_normal = StyleBoxFlat.new()
	_estilo_tarjeta_normal.bg_color = Color(0.071, 0.094, 0.133, 0.92)
	_estilo_tarjeta_normal.border_color = Color(0.165, 0.212, 0.282, 1.0)
	_estilo_tarjeta_normal.set_border_width_all(2)
	_estilo_tarjeta_normal.set_corner_radius_all(6)
	_estilo_tarjeta_normal.set_content_margin_all(1.0)

	_estilo_tarjeta_activa = _estilo_tarjeta_normal.duplicate() as StyleBoxFlat
	_estilo_tarjeta_activa.bg_color = Color(0.082, 0.125, 0.185, 0.96)
	_estilo_tarjeta_activa.border_color = Color(0.0, 0.898, 1.0, 1.0)


func _conectar_controles_barra() -> void:
	btn_vel_1x.pressed.connect(func(): _establecer_velocidad(1.0))
	btn_vel_2x.pressed.connect(func(): _establecer_velocidad(2.0))
	btn_vel_4x.pressed.connect(func(): _establecer_velocidad(4.0))
	btn_rayos.toggled.connect(_on_rayos_toggled)
	if btn_estela != null:
		btn_estela.toggled.connect(_on_estela_toggled)
	btn_reiniciar.pressed.connect(_on_reiniciar_pressed)
	btn_volver_config.pressed.connect(_on_volver_config_pressed)
	btn_editar_mapa.pressed.connect(_on_editar_mapa_pressed)


func _cargar_datos_circuito() -> void:
	var tiene_datos := (
		not DatosSimulacion.celdas_asfalto.is_empty()
		and DatosSimulacion.tiene_meta
		and DatosSimulacion.celdas_asfalto.has(DatosSimulacion.celda_meta)
		and not DatosSimulacion.ruta_checkpoints.is_empty()
	)

	var tam := float(DatosSimulacion.TAMANIO_CELDA)
	if tiene_datos:
		_usando_circuito_fallback = false
		_celdas_activas = DatosSimulacion.celdas_asfalto.duplicate()
		_meta_activa = DatosSimulacion.celda_meta
		_checkpoints_activos = DatosSimulacion.ruta_checkpoints.duplicate()
		_eje_activo = DatosSimulacion.eje_central.duplicate()
		_radios_activos = DatosSimulacion.radios_eje.duplicate()
		_ancho_activo = DatosSimulacion.ancho_pista if DatosSimulacion.ancho_pista > 0.0 else 48.0
		_pos_salida_activa = (
			DatosSimulacion.posicion_salida
			if DatosSimulacion.posicion_salida != Vector2.ZERO
			else Vector2(_meta_activa) * tam + Vector2.ONE * (tam * 0.5)
		)
		_rot_salida_activa = DatosSimulacion.rotacion_salida
	else:
		# Circuito local determinista 45x27 cuando se abre Vista 4 aislada, sin mutar DatosSimulacion
		_usando_circuito_fallback = true
		var fb_celdas: Dictionary = {}
		for x in range(8, 37):
			for dy in range(-1, 2):
				fb_celdas[Vector2i(x, 6 + dy)] = true
				fb_celdas[Vector2i(x, 20 + dy)] = true
		for y in range(6, 21):
			for dx in range(-1, 2):
				fb_celdas[Vector2i(8 + dx, y)] = true
				fb_celdas[Vector2i(36 + dx, y)] = true

		var fb_meta := Vector2i(22, 6)
		var val := GeneradorCheckpoints.validar_y_generar(fb_celdas, fb_meta, true, DatosSimulacion.TAMANIO_CELDA)
		_celdas_activas = fb_celdas
		_meta_activa = fb_meta
		_checkpoints_activos = val.get("checkpoints", [] as Array[Vector2i])
		_eje_activo = val.get("eje_central", [] as Array[Vector2i])
		_radios_activos = val.get("radios_eje", [] as Array[float])
		_ancho_activo = 48.0
		_pos_salida_activa = Vector2(_meta_activa) * tam + Vector2.ONE * (tam * 0.5)
		_rot_salida_activa = float(val.get("rotacion_salida", 0.0))

	if not _checkpoints_activos.is_empty():
		var pos_cp0 := Vector2(_checkpoints_activos[0]) * tam + Vector2.ONE * (tam * 0.5)
		_rot_salida_activa = (pos_cp0 - _pos_salida_activa).angle()


func _reconstruir_pista() -> void:
	for hijo in pista_visual.get_children():
		pista_visual.remove_child(hijo)
		hijo.queue_free()

	ConstructorPista.construir_en_tilemap(tile_map_pista, _celdas_activas)
	tile_map_pista.visible = false
	ConstructorPista.construir_pista_suave(pista_visual, _celdas_activas, true)


func _instanciar_checkpoints() -> void:
	for hijo in nodo_checkpoints.get_children():
		nodo_checkpoints.remove_child(hijo)
		hijo.queue_free()
	_checkpoints.clear()

	if not ResourceLoader.exists(ESCENA_CHECKPOINT):
		return

	var ps_cp := load(ESCENA_CHECKPOINT) as PackedScene
	if ps_cp == null:
		return

	var tam := float(DatosSimulacion.TAMANIO_CELDA)
	for i in range(_checkpoints_activos.size()):
		var cp_celda := _checkpoints_activos[i]
		var cp := ps_cp.instantiate() as CheckpointArea
		if cp == null:
			continue
		cp.name = "Checkpoint_%d" % i
		cp.id_checkpoint = i
		cp.visible = false
		cp.position = Vector2(cp_celda) * tam + Vector2.ONE * (tam * 0.5)

		var idx_eje := _eje_activo.find(cp_celda)
		var radio_local := float(_radios_activos[idx_eje]) if idx_eje >= 0 and idx_eje < _radios_activos.size() else 0.0
		var radio_cp := clampf(maxf(radio_local, _ancho_activo * 0.5) + 2.0, 16.0, 48.0)

		var col_shape := cp.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col_shape != null:
			var forma := CircleShape2D.new()
			forma.radius = radio_cp
			col_shape.shape = forma

		nodo_checkpoints.add_child(cp)
		_checkpoints.append(cp)


func _configurar_meta_visual() -> void:
	if bandera_meta != null:
		if ResourceLoader.exists(RUTA_BANDERA_META):
			bandera_meta.texture = load(RUTA_BANDERA_META)
		bandera_meta.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bandera_meta.scale = Vector2(0.55, 0.55)
		bandera_meta.position = _pos_salida_activa
		bandera_meta.offset = Vector2(0.0, -8.0)
	if linea_meta != null:
		linea_meta.queue_redraw()


func _on_linea_meta_draw() -> void:
	if _meta_activa == Vector2i(-1, -1):
		return
	var tam := float(DatosSimulacion.TAMANIO_CELDA)
	var pm := Vector2(_meta_activa) * tam
	var cuadros := 4
	var sub := tam / float(cuadros)
	for ix in range(cuadros):
		for iy in range(cuadros):
			var es_blanco := (ix + iy) % 2 == 0
			var col := Color(0.95, 0.95, 0.95, 0.72) if es_blanco else Color(0.10, 0.10, 0.12, 0.72)
			linea_meta.draw_rect(Rect2(pm + Vector2(ix * sub, iy * sub), Vector2(sub, sub)), col, true)


func _instanciar_vehiculos() -> void:
	for hijo in nodo_vehiculos.get_children():
		nodo_vehiculos.remove_child(hijo)
		hijo.queue_free()
	_vehiculos.clear()

	if not ResourceLoader.exists(ESCENA_VEHICULO):
		return
	var ps_coche := load(ESCENA_VEHICULO) as PackedScene
	if ps_coche == null:
		return

	var cant_cps := _checkpoints_activos.size()
	var pos_cps := PackedVector2Array()
	for cp_node in _checkpoints:
		pos_cps.append(cp_node.global_position)
	var pos_global := escenario.to_global(_pos_salida_activa)
	for i in range(mini(3, DatosSimulacion.config_vehiculos.size())):
		var cfg: Dictionary = DatosSimulacion.config_vehiculos[i]
		var coche := ps_coche.instantiate() as VehiculoAgente
		if coche == null:
			continue
		coche.name = "Vehiculo_%d" % i
		nodo_vehiculos.add_child(coche)
		coche.configurar(cfg)
		coche.posiciones_checkpoints = pos_cps
		if coche.es_humano or coche.control_manual:
			coche.cerebro = null
		else:
			coche.cerebro = RedNeuronal.cargar_nivel_o_fallback(coche.nivel_ia)
		coche.mostrar_sensores = _mostrar_sensores_activo
		coche.mostrar_estela = _mostrar_estela_activo
		coche.reiniciar_estado(pos_global, _rot_salida_activa, cant_cps)
		coche.position = _pos_salida_activa
		coche.chocado.connect(_on_vehiculo_chocado)
		coche.checkpoint_alcanzado.connect(_on_vehiculo_checkpoint)
		_vehiculos.append(coche)


func _configurar_tarjetas_hud() -> void:
	_tarjetas_ui.clear()
	var textura_coche: Texture2D = load(RUTA_SPRITE_COCHE) if ResourceLoader.exists(RUTA_SPRITE_COCHE) else null
	var tarjetas := contenedor_tarjetas.get_children()

	for i in range(tarjetas.size()):
		var tarjeta := tarjetas[i] as PanelContainer
		if tarjeta == null:
			continue
		if i >= _vehiculos.size():
			tarjeta.visible = false
			continue

		tarjeta.visible = true
		var coche := _vehiculos[i]
		var franja: ColorRect = tarjeta.get_node("VBox/FranjaColor")
		var icono: TextureRect = tarjeta.get_node("VBox/Margin/Col/TopRow/IconoCoche")
		var lbl_nombre: Label = tarjeta.get_node("VBox/Margin/Col/TopRow/LblNombre")
		var lbl_estado: Label = tarjeta.get_node("VBox/Margin/Col/TopRow/LblEstado")
		var lbl_nivel: Label = tarjeta.get_node("VBox/Margin/Col/MidRow/LblNivelIA")
		var btn_insp: Button = tarjeta.get_node("VBox/Margin/Col/MidRow/BtnInspeccionar")
		var lbl_vuelta: Label = tarjeta.get_node("VBox/Margin/Col/StatsRow/LblVuelta")
		var lbl_cps: Label = tarjeta.get_node("VBox/Margin/Col/StatsRow/LblCheckpoints")

		franja.color = coche.color_vehiculo
		if textura_coche != null:
			icono.texture = textura_coche
		icono.modulate = coche.color_vehiculo

		lbl_nombre.text = coche.nombre_vehiculo
		lbl_nombre.add_theme_color_override("font_color", coche.color_vehiculo.lightened(0.28))

		if coche.es_humano or coche.control_manual:
			lbl_nivel.text = "Piloto Humano"
			lbl_nivel.add_theme_color_override("font_color", Color(0.0, 0.898, 1.0, 1.0))
		else:
			var titulo_ia := _obtener_titulo_nivel(coche.nivel_ia)
			lbl_nivel.text = "Nivel %d — %s" % [coche.nivel_ia, titulo_ia]
			lbl_nivel.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88, 1.0))

		var idx_local := i
		for con in btn_insp.pressed.get_connections():
			btn_insp.pressed.disconnect(con["callable"])
		btn_insp.pressed.connect(func(): _alternar_inspeccion(idx_local))

		_tarjetas_ui.append({
			"panel": tarjeta,
			"lbl_estado": lbl_estado,
			"lbl_vuelta": lbl_vuelta,
			"lbl_cps": lbl_cps,
			"btn_insp": btn_insp,
		})

	_actualizar_telemetria_hud()


func _obtener_titulo_nivel(nivel: int) -> String:
	var idx := clampi(nivel - 1, 0, DatosSimulacion.NIVELES_IA.size() - 1)
	if idx >= 0 and idx < DatosSimulacion.NIVELES_IA.size():
		return str(DatosSimulacion.NIVELES_IA[idx].get("titulo", "IA"))
	return "IA"


func _alternar_inspeccion(indice: int) -> void:
	if indice == _indice_inspeccionado:
		_seleccionar_vehiculo_inspeccion(-1)
	else:
		_seleccionar_vehiculo_inspeccion(indice)


func _seleccionar_vehiculo_inspeccion(indice: int) -> void:
	if _vehiculos.is_empty() or indice < 0 or indice >= _vehiculos.size():
		_indice_inspeccionado = -1
		if visor_red != null:
			visor_red.establecer_vehiculo(null)
	else:
		_indice_inspeccionado = indice
		var coche_sel := _vehiculos[_indice_inspeccionado]
		if coche_sel == null or not is_instance_valid(coche_sel):
			coche_sel = null
			_indice_inspeccionado = -1
		if visor_red != null:
			visor_red.establecer_vehiculo(coche_sel)

	for i in range(_tarjetas_ui.size()):
		var ui: Dictionary = _tarjetas_ui[i]
		var panel: PanelContainer = ui["panel"]
		var btn: Button = ui["btn_insp"]
		var activo := (i == _indice_inspeccionado)
		if panel != null:
			panel.add_theme_stylebox_override("panel", _estilo_tarjeta_activa if activo else _estilo_tarjeta_normal)
		if btn != null:
			btn.text = "Inspeccionando" if activo else "Inspeccionar"

	_actualizar_titulo_visor()


func _actualizar_titulo_visor() -> void:
	if lbl_seccion_visor == null:
		return
	var obj: VehiculoAgente = visor_red.vehiculo_objetivo if visor_red != null else null
	var es_hum := obj != null and is_instance_valid(obj) and (obj.es_humano or obj.control_manual)
	var texto_objetivo := "CONTROL MANUAL EN VIVO" if es_hum else "RED NEURONAL EN VIVO (18 → 8 → 2)"
	if lbl_seccion_visor.text != texto_objetivo:
		lbl_seccion_visor.text = texto_objetivo


func _actualizar_telemetria_hud() -> void:
	var cant_cps := _checkpoints_activos.size()
	for i in range(mini(_vehiculos.size(), _tarjetas_ui.size())):
		var coche := _vehiculos[i]
		if coche == null or not is_instance_valid(coche):
			continue
		var ui: Dictionary = _tarjetas_ui[i]
		var lbl_estado: Label = ui["lbl_estado"]
		var lbl_vuelta: Label = ui["lbl_vuelta"]
		var lbl_cps: Label = ui["lbl_cps"]

		if coche.esta_chocado:
			var motivo := coche.motivo_choque if not coche.motivo_choque.is_empty() else "Chocado"
			lbl_estado.text = motivo
			lbl_estado.add_theme_color_override("font_color", Color(0.98, 0.36, 0.36, 1.0))
		else:
			lbl_estado.text = "Corriendo"
			lbl_estado.add_theme_color_override("font_color", Color(0.32, 0.92, 0.56, 1.0))

		lbl_vuelta.text = "Vuelta: %d" % coche.vuelta_actual
		lbl_cps.text = "Checkpoints: %d (%d/vta)" % [coche.checkpoints_cruzados, cant_cps]

	_actualizar_titulo_visor()


func _on_vehiculo_chocado(_vehiculo: VehiculoAgente, _motivo: String) -> void:
	_actualizar_telemetria_hud()


func _on_vehiculo_checkpoint(_vehiculo: VehiculoAgente, _id_cp: int, _vuelta: int) -> void:
	_actualizar_telemetria_hud()


func _establecer_velocidad(escala: float) -> void:
	Engine.time_scale = escala
	if btn_vel_1x != null:
		btn_vel_1x.set_pressed_no_signal(is_equal_approx(escala, 1.0))
	if btn_vel_2x != null:
		btn_vel_2x.set_pressed_no_signal(is_equal_approx(escala, 2.0))
	if btn_vel_4x != null:
		btn_vel_4x.set_pressed_no_signal(is_equal_approx(escala, 4.0))


func _on_rayos_toggled(activo: bool) -> void:
	_mostrar_sensores_activo = activo
	for coche in _vehiculos:
		if coche != null and is_instance_valid(coche):
			coche.mostrar_sensores = activo
			if coche.dibujo_sensores != null:
				coche.dibujo_sensores.visible = activo
				coche.dibujo_sensores.queue_redraw()
	_actualizar_boton_rayos()


func _actualizar_boton_rayos() -> void:
	if btn_rayos != null:
		btn_rayos.set_pressed_no_signal(_mostrar_sensores_activo)
		btn_rayos.text = "Rayos: ON" if _mostrar_sensores_activo else "Rayos: OFF"


func _on_estela_toggled(activo: bool) -> void:
	_mostrar_estela_activo = activo
	for coche in _vehiculos:
		if coche != null and is_instance_valid(coche):
			coche.mostrar_estela = activo
	_actualizar_boton_estela()


func _actualizar_boton_estela() -> void:
	if btn_estela != null:
		btn_estela.set_pressed_no_signal(_mostrar_estela_activo)
		btn_estela.text = "Estela: ON" if _mostrar_estela_activo else "Estela: OFF"


func _on_reiniciar_pressed() -> void:
	var cant_cps := _checkpoints_activos.size()
	var pos_global := escenario.to_global(_pos_salida_activa)
	for coche in _vehiculos:
		if coche != null and is_instance_valid(coche):
			coche.reiniciar_estado(pos_global, _rot_salida_activa, cant_cps)
			coche.position = _pos_salida_activa
			coche.mostrar_sensores = _mostrar_sensores_activo
			coche.mostrar_estela = _mostrar_estela_activo
			if coche.cerebro is RedNeuronal:
				(coche.cerebro as RedNeuronal)._reiniciar_instantaneas()
	_actualizar_telemetria_hud()
	if visor_red != null:
		visor_red.actualizar_visor()


func _on_volver_config_pressed() -> void:
	Engine.time_scale = 1.0
	if ResourceLoader.exists(ESCENA_CONFIGURACION):
		get_tree().change_scene_to_file(ESCENA_CONFIGURACION)


func _on_editar_mapa_pressed() -> void:
	Engine.time_scale = 1.0
	if ResourceLoader.exists(ESCENA_CREADOR):
		get_tree().change_scene_to_file(ESCENA_CREADOR)


func _ajustar_escenario() -> void:
	if area_pista == null or escenario == null:
		return
	escenario.position = Vector2.ZERO
	escenario.scale = Vector2.ONE

	var tam_contenedor := area_pista.size
	if viewport_pista != null and viewport_pista.size.x > 0.0 and viewport_pista.size.y > 0.0:
		tam_contenedor = viewport_pista.size
	var ancho_mapa := float(DatosSimulacion.ANCHO_GRID * DatosSimulacion.TAMANIO_CELDA)
	var alto_mapa := float(DatosSimulacion.ALTO_GRID * DatosSimulacion.TAMANIO_CELDA)
	if ancho_mapa <= 0.0 or alto_mapa <= 0.0 or tam_contenedor.x <= 0.0 or tam_contenedor.y <= 0.0:
		return

	if sub_viewport_pista != null and (viewport_pista == null or not viewport_pista.stretch):
		var tam_vp := Vector2i(maxi(int(round(tam_contenedor.x)), 1), maxi(int(round(tam_contenedor.y)), 1))
		if sub_viewport_pista.size != tam_vp:
			sub_viewport_pista.size = tam_vp

	var escala := minf(tam_contenedor.x / ancho_mapa, tam_contenedor.y / alto_mapa)
	if escala <= 0.01:
		return

	_cam_pos_completa = Vector2(ancho_mapa * 0.5, alto_mapa * 0.5)
	_cam_zoom_completo = escala
	_actualizar_camara(0.0, true)


func _actualizar_camara(delta: float, inmediato: bool = false) -> void:
	if camara_pista == null:
		return
	camara_pista.enabled = true

	var objetivo_pos := _cam_pos_completa
	var objetivo_zoom := Vector2(_cam_zoom_completo, _cam_zoom_completo)

	if _indice_inspeccionado >= 0:
		if _indice_inspeccionado < _vehiculos.size() and is_instance_valid(_vehiculos[_indice_inspeccionado]):
			objetivo_pos = _vehiculos[_indice_inspeccionado].position
			var zoom_insp := _cam_zoom_completo * FACTOR_ZOOM_INSPECCION
			objetivo_zoom = Vector2(zoom_insp, zoom_insp)
		else:
			_seleccionar_vehiculo_inspeccion(-1)

	if inmediato:
		camara_pista.position = objetivo_pos
		camara_pista.zoom = objetivo_zoom
	else:
		var t := clampf(delta * VEL_SUAVIZADO_CAMARA, 0.0, 1.0)
		camara_pista.position = camara_pista.position.lerp(objetivo_pos, t)
		camara_pista.zoom = camara_pista.zoom.lerp(objetivo_zoom, t)
