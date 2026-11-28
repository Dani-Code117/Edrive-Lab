# Documento de Diseño Técnico (TDD) — EDrive Lab

**Proyecto:** Laboratorio Interactivo Educativo de Simulación Automotriz (IA / Machine Learning)  
**Motor:** Godot Engine 4.7+ (2D, GL Compatibility)  
**Lenguaje Principal:** 100% GDScript (sin dependencias externas ni C#)  
**Licencia:** MIT License (Repositorio público educativo: `edrive-lab`)  

---

## 1. Resumen Ejecutivo y Propósito Educativo

**EDrive Lab** es un laboratorio interactivo diseñado para enseñar de forma visual y experimental cómo funcionan las **Redes Neuronales Artificiales (RNA)**, la **Neuroevolución** y la interacción física vehículo-circuito aplicadas a la conducción autónoma y manual.

En lugar de obligar al usuario a esperar decenas de generaciones de entrenamiento desde cero, el sistema ofrece un **Modo Laboratorio Comparativo**:
* En la **Vista 2 (Creador de Mapa)**, el usuario puede dibujar su propio circuito cerrado o cargar al instante cualquiera de los **3 arquetipos de pista preconstruidos** (*Óvalo Clásico*, *S-Enlazadas* y *Horquilla Técnica*) sobre el lienzo editable (`45 x 27`, `16 x 16` px) con la meta ya ubicada.
* En la **Vista 3 (Configuración de Carrera)**, configura **3 vehículos competidores simultáneos** (*Coche Rojo*, *Coche Azul* y *Coche Verde*) eligiendo entre **4 arquetipos físicos rápidos** (*Equilibrado*, *Velocista*, *Drift*, *Técnico*) o el perfil *Personalizado* mediante sus **5 atributos físicos** (`Velocidad Máxima`, `Aceleración`, `Frenado`, `Control (Giro)`, `Agarre`), asignándoles niveles de IA pre-entrenada (**Nivel 1: Novato Caótico** hasta **Nivel 10: Maestro Autónomo**) o activando el **Modo Piloto Humano** exclusivo (máximo **1 vehículo humano** a la vez controlado con `WASD` o Flechas bajo la misma física, colisiones, checkpoints y telemetría que las IAs).
* En la **Vista 4 (Carrera en Vivo)**, observa la simulación física junto con el visor `VisorRedNeuronal` (`18 → 8 → 2` o *"Control Manual"* con 18 entradas y 2 comandos en vivo) y la **Estela Telemétrica** (`EstelaTelemetrica`) detrás de cada coche, coloreada en tiempo real según la acción longitudinal aplicada (aceleración, frenado/desaceleración o reversa).

*(Nota de alcance: El entrenamiento genético masivo en vivo se ejecuta de forma offline/headless mediante `EntrenadorGenetico.gd -- --entrenar` reutilizando las **3 geometrías** de `ArquetiposPista` —Óvalo Clásico, S-Enlazadas y Horquilla Técnica— para generar `nivel_01.tres` a `nivel_10.tres` en `res://Assets/Presets_ia/`. En el repositorio base, `res://Assets/Presets_ia/` se mantiene limpio únicamente con `.gitkeep` para que el usuario pueda ejecutar el entrenamiento cuando lo desee, operando la aplicación mientras tanto con el fallback seguro en memoria).*

---

## 2. Flujo de Pantallas y Arquitectura de Vistas (4 Vistas)

La aplicación se estructura en cuatro escenas principales conectadas mediante un **Autoload (Singleton)** llamado `DatosSimulacion` (`res://Assets/Scripts/datos_simulacion.gd`) que transporta la pista (`celdas_asfalto`, `celda_meta`, `ruta_checkpoints`, `eje_central`, `radios_eje`, `ancho_pista`, `posicion_salida`, `rotacion_salida`) y `config_vehiculos` (3 vehículos con sus 5 atributos físicos, `nivel_ia`, `arquetipo` y `es_humano`) entre escenas.

Las **4 vistas** utilizan el tema oscuro de telemetría `res://Assets/Temas/tema_telemetria.tres` (mantenido sincronizado con `res://Assets/Temas/tema_edrive.tres`), contenedores responsivos verificados sin solapamientos ni recortes entre **`1280x720`** y **`1920x1080`**, y micro-animaciones **`BotonAnimado`** (`boton_animado.gd`) en los **43 botones (`Button`)** no-`OptionButton` de todo el proyecto.

```text
[1. Menú Principal] ──> [2. Creador de Mapa] ──> [3. Configuración de Carrera] ──> [4. Carrera / Simulación]
```

### Vista 1: Menú Principal (`res://Assets/Escenas/Vistas/menu_principal.tscn`)
* **Script:** `res://Assets/Scripts/Vistas/menu_principal.gd`
* **Función:** Pantalla de presentación del proyecto educativo **EDrive Lab** (`run/main_scene`).
* **Elementos UI:** Tarjeta central responsiva con tema oscuro de telemetría (`tema_telemetria.tres`, sincronizado con `tema_edrive.tres`), título, descripción breve del objetivo de aprendizaje, botón **"Iniciar Laboratorio"** (`BtnIniciar`, lleva a Vista 2) y botón **"Salir"** (`BtnSalir`), ambos con `BotonAnimado` (`boton_animado.gd` con `Tween`).

### Vista 2: Creador de Mapa (`res://Assets/Escenas/Vistas/creador_mapa.tscn`)
* **Scripts:** `creador_mapa.gd`, `EditorPista.gd`, `constructor_pista.gd`, `GeneradorCheckpoints.gd`, `arquetipos_pista.gd`
* **Función:** Lienzo interactivo (`45 x 27` celdas de `16 x 16` px) donde el usuario diseña o adapta el circuito.
* **Herramientas y Selector Rápido:**
  * **Pincel de Asfalto (`BtnPincel`):** Pinta bloques con grosor seleccionable en `OptGrosor` (`1x1`, `2x2`, `3x3 Estándar` por defecto = `48 px` de ancho, `4x4`, `5x5`).
  * **Borrador (`BtnBorrador`):** Elimina celdas de asfalto y recalcula los bordes vecinos.
  * **Colocar Meta / Salida (`BtnMeta`):** Sitúa el punto de partida sobre cualquier celda de asfalto válida.
  * **Selector Rápido de Arquetipos:** Botones **`BtnArqOvalo`** (*Óvalo Clásico*), **`BtnArqEnlazadas`** (*S-Enlazadas*) y **`BtnArqHorquilla`** (*Horquilla Técnica*), todos con `BotonAnimado`. Al pulsar cualquiera, `creador_mapa.gd` llama a `cargar_arquetipo_pista()` → `EditorPista.cargar_arquetipo()`, sincroniza `OptGrosor` a `3x3`, sale de vista previa si estaba activa y carga el circuito cerrado válido + su meta directamente sobre el lienzo editable sin mutar `DatosSimulacion` hasta confirmar.
  * **Limpiar Todo (`BtnLimpiar`):** Reinicia el lienzo y las validaciones.
* **Validación y Flujo de Confirmación en 2 Pasos:** El botón **`BtnConfirmar`** (*"Confirmar Pista"*) permanece deshabilitado hasta que `GeneradorCheckpoints` verifica que el circuito forma un **lazo cerrado** alrededor de un área interior y tiene una meta sobre el ciclo principal. Al pulsarlo por primera vez, guarda la pista en `DatosSimulacion`, oculta el panel lateral, muestra la vista previa suavizada en `TileMapFinal`, habilita **`BtnEditar`** (*"Editar Pista"*) para volver al lienzo si se desea modificar algo y cambia el texto de `BtnConfirmar` a **"Continuar →"** para avanzar a la Vista 3.

### Vista 3: Configuración de Carrera / Personalización (`res://Assets/Escenas/Vistas/configuracion_carrera.tscn`)
* **Script:** `res://Assets/Scripts/Vistas/configuracion_carrera.gd` (`class_name ConfiguracionCarreraUI`)
* **Función:** Panel de parametrización previa a la simulación.
* **Elementos UI:**
  * **Minimapa ("Pista Confirmada"):** Vista previa renderizada dinámicamente a partir de `DatosSimulacion.celdas_asfalto` y `DatosSimulacion.celda_meta`, acompañada de estadísticas (celdas de asfalto, checkpoints y coordenadas de meta).
  * **3 Tarjetas de Vehículos (`Coche Rojo`, `Coche Azul`, `Coche Verde`):** Cada tarjeta contiene:
    * Vista previa del sprite del coche modulado con su color.
    * **Arquetipos de Vehículo (`SeccionArquetipos`):** Encabezado con `LblArquetipo` y rejilla `2x2` (`GridArquetipos`) con los botones toggle **`BtnArqEquilibrado`**, **`BtnArqVelocista`**, **`BtnArqDrift`** y **`BtnArqTecnico`** (`BotonAnimado`). Al pulsar un preset (`aplicar_arquetipo()`), rellena los 5 sliders sin disparar eventos falsos; al mover manualmente cualquier `HSlider`, el indicador cambia automáticamente a **`"Personalizado"`**. El perfil elegido persiste en `DatosSimulacion.config_vehiculos[i]["arquetipo"]`.
    * **5 deslizadores (`HSlider`) normalizados (`0.0` a `1.0`, `step = 0.01`)** con etiquetas de valor en tiempo real:
      1. **Velocidad Máxima (`velocidad_maxima`)**
      2. **Aceleración (`aceleracion`)**
      3. **Frenado (`frenado`)**
      4. **Control (Giro) (`control`)**
      5. **Agarre (`agarre`)**
    * **Selector de Modo (`SeccionIA/HBoxModo`) y Nivel de IA (`OptNivelIA`):** Botones toggle **`BtnModoIA`** (*"IA"*) y **`BtnModoHumano`** (*"Piloto Humano"*), ambos `BotonAnimado`. Garantiza **exclusividad estricta de máximo 1 vehículo humano a la vez** mediante `establecer_modo_humano()` y `DatosSimulacion.establecer_humano_exclusivo()`: activar *Piloto Humano* en una tarjeta desactiva automáticamente el modo humano en las demás, deshabilita su `OptNivelIA` (`disabled = true`) manteniendo activos los arquetipos físicos y los 5 sliders, actualiza `LblEstadoIA` (`"Piloto Humano activo"`) y `LblDescIA` (controles `WASD` o Flechas), y persiste `"es_humano"` en `DatosSimulacion.config_vehiculos[i]`. En modo IA, `OptNivelIA` permite elegir **`Nivel 1`** hasta **`Nivel 10`** (cargando `.tres` si existen o fallback en memoria).
  * **Botones de Navegación:** **`"← Editar Mapa"`** (`BtnVolver`) y **`"INICIAR SIMULACIÓN →"`** (`BtnIniciar`), que sanitiza y persiste las 3 configuraciones en `DatosSimulacion.config_vehiculos` y cambia a la Vista 4.

### Vista 4: Carrera en Vivo (`res://Assets/Escenas/Vistas/vista_carrera.tscn`)
* **Script:** `res://Assets/Scripts/Vistas/vista_carrera.gd` (`class_name VistaCarreraUI`)
* **Función:** Ejecución física continua de la carrera y visualización educativa en tiempo real.
* **Elementos:**
  * **Mundo Aislado (`SubViewport` + `Camera2D`):** Mantiene el escenario físico sin escalado (`scale = Vector2.ONE`) para conservar la precisión 1:1 de colisiones y `RayCast2D`, mientras la `Camera2D` adapta el encuadre al contenedor.
  * **Reconstrucción de Pista y Meta:** Reconstruye el `TileMapLayer` (colisiones Layer 1), el trazado visual suave (`ConstructorPista.construir_pista_suave`), la línea de meta a cuadros y `BanderaMeta` (`bandera_meta.png`).
  * **Checkpoints e Instanciación:** Instancia los `Area2D` invisibles en sentido horario e instancia los 3 coches en la línea de salida orientados hacia `checkpoint[0]`. Si el vehículo tiene `es_humano == true`, su `cerebro` permanece en `null` y recibe entradas del jugador (`WASD` o Flechas) con idéntica física, colisiones, checkpoints y telemetría.
  * **HUD Educativo en vivo:**
    * **Tarjetas de telemetría por coche:** Muestran **`"Piloto Humano"`** (en color cian) cuando `es_humano` está activo o **`"Nivel X — Título"`** cuando lo controla la IA, además de Vuelta actual, Checkpoints alcanzados, Estado (*Corriendo / Chocado / Atascado*) y botón **"Inspeccionar / Inspeccionando"**.
    * **Zoom y Seguimiento de Cámara:** Al pulsar **Inspeccionar** en una tarjeta, la `Camera2D` hace zoom (`3.0x`) y sigue suavemente (`lerp`) al vehículo seleccionado; al desactivar la inspección, regresa suavemente a la vista de pista completa.
    * **Visor en Vivo (`visor_red_neuronal.tscn` / `VisorRedNeuronal` + `LblSeccionVisor`):** El título de sección cambia dinámicamente entre **`"RED NEURONAL EN VIVO (18 → 8 → 2)"`** (modo IA) y **`"CONTROL MANUAL EN VIVO"`** (modo Piloto Humano). En modo IA dibuja mediante `_draw()` conexiones ponderadas y activaciones `18 → 8 → 2`; en modo Piloto Humano muestra el encabezado `"(Control Manual)"`, el distintivo central **`"Control Manual"`**, las **18 entradas en vivo** (`ultimas_entradas_ia`) y los **2 comandos manuales aplicados** (`ultima_aceleracion_ia` y `ultimo_giro_ia`).
    * **Controles de Barra Superior:** Selector de velocidad (`BtnVel1x`, `BtnVel2x`, `BtnVel4x` con `Engine.time_scale`), toggle **Rayos: ON/OFF** (`BtnRayos`, `RayCast2D` con degradado verde a rojo según proximidad), toggle **Estela: ON/OFF** (`BtnEstela`, `toggle_mode = true`, `BotonAnimado`, que controla `mostrar_estela` de todos los vehículos sin añadir controles extra de longitud en la UI), **Reiniciar Carrera** (`BtnReiniciar`), **← Volver a Configuración** (`BtnVolverConfig`) y **Editar Mapa** (`BtnEditarMapa`).

---

## 3. Especificaciones Técnicas por Módulo

### 3.1. Módulo de Entorno y TileSet (`TileMapLayer`)
* **Grid Base:** `45 x 27` celdas (`ANCHO_GRID = 45`, `ALTO_GRID = 27`).
* **Dimensiones de Tile:** `16 x 16` píxeles (`TAMANIO_CELDA = 16`).
* **Configuración de Terreno:** `TileSet` (`res://Assets/Sprites/tileset_pista.tres`) con soporte de autotiling para rectas, bordes y curvas de asfalto, complementado con `ConstructorPista.construir_pista_suave` para el renderizado visual continuo de la pista.
* **Capas de Física (2D Physics Layers en `project.godot`):**
  * **Layer 1 (`Muros_Pasto`):** Asignada a los tiles fuera del asfalto. Causa la eliminación del vehículo al contacto.
  * **Layer 2 (`Vehiculos`):** Asignada a los `CharacterBody2D` de los coches (`collision_layer = 2`, `collision_mask = 1`). Los coches **no colisionan entre sí**.
  * **Layer 3 (`Checkpoints`):** Asignada a los `Area2D` invisibles (`checkpoint.tscn`, `CheckpointArea`).

### 3.2. Algoritmo de Validación de Circuito y Checkpoints Invisibles
Al confirmar la pista, `GeneradorCheckpoints.gd` ejecuta de forma automática:

1. **Verificación de Conectividad y Lazo Cerrado (BFS / Flood Fill):**
   * Verifica conectividad en un solo componente desde `celda_meta` (`_bfs_conectividad`) y confirma la existencia de un hueco interior rodeado de asfalto (`_tiene_hueco_interior`).
2. **Extracción del Eje Central y Poda de Espolones:**
   * Calcula la distancia al pasto mediante Distance Transform y adelgazamiento (`_extraer_eje_central`) y poda ramas muertas (`_podar_espolones`).
   * Verifica que la meta pertenezca al lazo cerrado y traza el ciclo (`_trazar_ciclo`) con fallback planar/BFS para circuitos con múltiples huecos.
3. **Ordenamiento Estricto en Sentido Horario:**
   * Evalúa la orientación en coordenadas 2D de Godot ($+X$ derecha, $+Y$ abajo) para garantizar un recorrido estrictamente **horario** (`_asegurar_sentido_horario`), invirtiendo el arreglo si fuera antihorario.
4. **Instanciación Oculta:**
   * Toma 1 de cada `PASO_CHECKPOINT = 3` celdas del ciclo ordenado e instancia `checkpoint.tscn` (`visible = false`) con su `CircleShape2D` ajustado al radio local de la pista y su `id_checkpoint` secuencial (`0, 1, 2, ...`).
   * Orienta la rotación inicial (`rotation`) de los 3 vehículos hacia `checkpoint[0]`.

### 3.3. Arquetipos de Pistas (`arquetipos_pista.gd`)
* **Clase:** `class_name ArquetiposPista extends RefCounted` (`res://Assets/Scripts/Pistas/arquetipos_pista.gd`).
* **Constantes:** `OVALO_CLASICO = 0`, `S_ENLAZADAS = 1`, `HORQUILLA_TECNICA = 2`, más los arreglos `WAYPOINTS_OVALO`, `WAYPOINTS_S_ENLAZADAS` y `WAYPOINTS_HORQUILLA`.
* **API estática:**
  * `construir_celdas_trazo(waypoints: Array[Vector2i], radio_brocha: int = 1) -> Dictionary`: traza segmentos interpolados entre waypoints con brocha `(2 * radio_brocha + 1)` sobre el grid `45 x 27` (`16 x 16` px).
  * `obtener_lista() -> Array[Dictionary]`: devuelve metadatos (`id`, `clave`, `nombre`, `descripcion`, `grosor_sugerido`).
  * `obtener_arquetipo(indice_o_clave: Variant, tam_celda: int = 16) -> Dictionary`: resuelve por índice (`0..2`), clave o nombre y retorna `{id, clave, nombre, descripcion, grosor_sugerido, celdas, celda_meta, tam_celda, validacion}` validado con `GeneradorCheckpoints.validar_y_generar(celdas, celda_meta, true, tam_celda)`.
* **Geometrías incluidas** (todas dentro de `x ∈ [1, 43]`, `y ∈ [1, 25]`, `grosor_sugerido = 3`):
  1. **Óvalo Clásico (`"ovalo_clasico"`, `meta = Vector2i(18, 4)`):** Rectas largas y curvas amplias (ideal para velocidad pura y niveles 1–5).
  2. **S-Enlazadas (`"s_enlazadas"`, `meta = Vector2i(10, 4)`):** Chicana con cambios continuos de dirección (ideal para evaluar `Agarre`, `Control` y estabilidad lateral).
  3. **Horquilla Técnica (`"horquilla_tecnica"`, `meta = Vector2i(12, 3)`):** Rectas rápidas seguidas de giros cerrados en horquilla (ideal para `Frenado`, reversa y niveles 7–10).

### 3.4. Estado Compartido y Arquetipos de Vehículo (`datos_simulacion.gd`)
* **Autoload:** `DatosSimulacion` (`res://Assets/Scripts/datos_simulacion.gd`).
* **Estructura de `config_vehiculos[i]`:** Cada una de las 3 entradas del arreglo mantiene las claves `"nombre"`, `"color"`, `"velocidad_maxima"`, `"aceleracion"`, `"frenado"`, `"control"`, `"agarre"`, `"nivel_ia"`, `"arquetipo"` y `"es_humano"`.
* **Perfiles balanceados (`ARQUETIPOS_VEHICULO`):**

| Arquetipo | `velocidad_maxima` | `aceleracion` | `frenado` | `control` | `agarre` | Notas |
|---|---:|---:|---:|---:|---:|---|
| **Equilibrado** | `0.50` | `0.50` | `0.50` | `0.50` | `0.50` | Perfil base simétrico |
| **Velocista** | `0.95` | `0.85` | `0.55` | `0.40` | `0.40` | Máxima punta/empuje, menor giro/agarre |
| **Drift** | `0.75` | `0.85` | `0.55` | `0.85` | `0.25` | Bajo agarre lateral con alto control y aceleración |
| **Técnico** | `0.60` | `0.70` | `0.90` | `0.90` | `0.90` | Máximo frenado, control y agarre para curvas cerradas |
| **Personalizado** | Manual | Manual | Manual | Manual | Manual | Valor por defecto (`ARQUETIPO_PERSONALIZADO`) y al editar sliders |

* **Sanitización y exclusividad humana:** Expone `sanitizar_normalizado()`, `sanitizar_nivel_ia()`, `sanitizar_arquetipo()`, `sanitizar_es_humano()` (estricto `bool`/`int`, evitando que strings no vacíos activen humano), `sanitizar_config_vehiculos()` (garantiza 3 ranuras válidas y máximo un `es_humano == true`), `establecer_humano_exclusivo()`, `obtener_indice_humano()` y `restaurar_config_vehiculos_defecto()`.

### 3.5. Especificaciones del Agente y Estela Telemétrica (`vehiculo_agente.gd` y `estela_telemetrica.gd`)
* **Jerarquía de Nodos (`res://Assets/Escenas/Componentes/vehiculo_agente.tscn`):**
  * `VehiculoAgente` (`CharacterBody2D`, Layer 2, Mask 1, `motion_mode = 1`; escena configura `longitud_rayo = 300.0` [por defecto en script `160.0`] y `tiempo_max_sin_checkpoint = 8.0` [por defecto en script `4.0`])
    * `EstelaTelemetrica` (`Node2D`, script `res://Assets/Scripts/Agente/estela_telemetrica.gd`, `top_level = true`, `z_index = 1`, `z_as_relative = false`)
    * `SpriteCoche` (`Sprite2D`, textura `coche_base.png` 24x14 px, escala `1/3`, modulada por color)
    * `Hitbox` (`CollisionPolygon2D`, ajustado al chasis)
    * `Sensores` (`Node2D`) con **14 hijos `RayCast2D`** (`Ray0`..`Ray13`, mask Layer 1):
      * **11 frontales:** $-90^\circ, -60^\circ, -40^\circ, -25^\circ, -12^\circ, 0^\circ, +12^\circ, +25^\circ, +40^\circ, +60^\circ, +90^\circ$.
      * **3 traseros:** $-135^\circ, 180^\circ, +135^\circ$.
    * `DibujoSensores` (`Node2D`, `z_index = 2`) para renderizar los rayos en vivo con degradado verde-rojo.
* **Vector de Entradas (`NUM_ENTRADAS_IA = 18`):**
  * `entradas[0..13]`: Distancia normalizada de los 14 `RayCast2D` (`0.0` impacto inminente a `1.0` libre hasta `longitud_rayo`).
  * `entradas[14..15]`: Brújula relativa hacia el siguiente checkpoint: `((cos(ang_rel) + 1.0) * 0.5, (sin(ang_rel) + 1.0) * 0.5)`.
  * `entradas[16]`: Velocidad actual con signo normalizada a `[0.0, 1.0]`: `(velocidad_actual / maxf(vel_max, 1.0) + 1.0) * 0.5` (`0.5` en reposo, `> 0.5` avance, `< 0.5` reversa).
  * `entradas[17]`: Memoria de la última aceleración comandada en `[0.0, 1.0]`: `(ultima_aceleracion_ia + 1.0) * 0.5`.
  * Tanto en modo IA como en **Modo Piloto Humano**, cada tick físico actualiza `ultimas_entradas_ia` (18 floats), `ultima_aceleracion_ia` y `ultimo_giro_ia`.
* **Modo Piloto Humano (`es_humano` / `control_manual`):**
  * Propiedades `@export var es_humano: bool` y `@export var control_manual: bool` sincronizadas bidireccionalmente (y aceptadas en `configurar(cfg)`).
  * En `_obtener_comandos()`, cuando está activo el modo humano lee simétricamente `W/S`, `↑/↓` y `ui_up`/`ui_down` para el comando longitudinal en `[-1.0, 1.0]`, y `A/D`, `←/→` y `ui_left`/`ui_right` para el giro en `[-1.0, 1.0]`, ejecutando exactamente la misma integración física, colisiones, checkpoints y telemetría que las IAs.
* **Físicas y Modificadores (`_physics_process`):**
  * Los 5 atributos normalizados (`0.0..1.0`) se mapean a:
    * `vel_max = lerpf(65.0, 180.0, attr_velocidad_maxima)`
    * `tasa_aceleracion = lerpf(60.0, 240.0, attr_aceleracion)`
    * `tasa_frenado = lerpf(75.0, 310.0, attr_frenado)`
    * `vel_rotacion = lerpf(2.0, 5.2, attr_control)`
    * `factor_agarre = lerpf(2.0, 12.0, attr_agarre)`
  * Soporta aceleración hacia adelante (`acel_cmd > 0.05`), desaceleración y **reversa suave** (`acel_cmd < -0.05`, hasta `0.4 * vel_max`).
  * **Agarre (Inercia/Derrape):** `velocity = velocity.lerp(transform.x * velocidad_actual, clampf(factor_agarre * delta, 0.0, 1.0))`.
  * **Colisión:** Tras `move_and_slide()`, si `get_slide_collision_count() > 0`, se marca `esta_chocado = true` (`motivo_choque = "Chocado"`), detiene su física y emite la señal `chocado`.
  * **Anti-atascos y Vueltas:** Temporizador `tiempo_max_sin_checkpoint` (`4.0 s` por defecto en script, `8.0 s` configurado en escena). Si se supera sin alcanzar el siguiente checkpoint esperado, se elimina con motivo `"Atascado"`. Al cruzar `id_cp == (ultimo_checkpoint + 1) % total_checkpoints`, reinicia el temporizador y suma vuelta al volver a `id_cp == 0` (incluyendo guardia post-reinicio en los primeros `1..2` frames físicos para descartar solapamientos rezagados de `PhysicsServer2D` tras teletransportar a la salida).
* **Estela Telemétrica (`EstelaTelemetrica` — `res://Assets/Scripts/Agente/estela_telemetrica.gd`):**
  * `class_name EstelaTelemetrica extends Node2D`, configurada en `_ready()` con `top_level = true`, `z_index = 1`, `z_as_relative = false`, `global_position = Vector2.ZERO`, `global_rotation = 0.0` y `global_scale = Vector2.ONE`.
  * Propiedades exportadas sincronizadas desde `VehiculoAgente`: `@export var mostrar_estela: bool = true` y `@export_range(10, 600, 1) var longitud_maxima_estela: int = 120` (acotada en `[10, 600]`, configurable únicamente en código/inspector sin controles adicionales en la UI).
  * En cada tick registra la posición global (`DISTANCIA_MIN_PUNTO = 0.20`) y clasifica el color por acción longitudinal mediante `calcular_color_accion(acel_cmd, velocidad_actual)`:
    * **Verde (`COLOR_ACELERACION = Color(0.24, 0.90, 0.45, 0.92)`):** `acel_cmd > 0.05`.
    * **Amarillo / Naranja (`COLOR_FRENADO = Color(0.98, 0.68, 0.14, 0.92)`):** `-0.05 <= acel_cmd <= 0.05` o frenado en avance (`acel_cmd < -0.05` con `velocidad_actual > 5.0`).
    * **Azul / Cian (`COLOR_REVERSA = Color(0.10, 0.82, 0.98, 0.92)`):** `acel_cmd < -0.05` con `velocidad_actual <= 5.0`.
  * Se vacía limpiamente mediante `limpiar(global_position)` dentro de `VehiculoAgente.reiniciar_estado()`.

### 3.6. Arquitectura de la Red Neuronal y Visor (`RedNeuronal.gd` y `visor_red_neuronal.gd`)
* **Topología Feedforward:** **`18 -> 8 -> 2`**
  * **Capa de Entrada:** `18` neuronas (`14` sensores `RayCast2D` + `2` brújula de checkpoint + `2` estado/memoria).
  * **Capa Oculta:** `8` neuronas (`144` pesos en `pesos_oculta` + `8` sesgos en `sesgos_oculta`).
  * **Capa de Salida:** `2` neuronas (`16` pesos en `pesos_salida` + `2` sesgos en `sesgos_salida`):
    * `output[0]`: Aceleración / Frenado / Reversa en **`[-1.0, 1.0]`**.
    * `output[1]`: Dirección del volante (giro) en **`[-1.0, 1.0]`**.
* **Función de Activación:** Tangente hiperbólica nativa `tanh()` en la capa oculta y en la capa de salida, con sanitización de preactivaciones y pesos en `PackedFloat64Array` (`170` genes totales).
* **Instantáneas en Vivo y Modo Control Manual (`VisorRedNeuronal`):** `RedNeuronal` expone `ultimas_entradas`, `ultimas_ocultas` y `ultimas_salidas`. Por su parte, `VisorRedNeuronal.obtener_instantanea_segura()` devuelve un diccionario unificado (`tiene_vehiculo`, `tiene_red`, `es_humano`, `modo_texto`, `nombre`, `nivel_ia`, `color`, `entradas`, `ocultas`, `salidas`, `pesos_oculta`, `pesos_salida`):
  * Cuando `es_humano` es `true`, fija `tiene_red = false`, `modo_texto = "Control Manual"`, lee las **18 entradas** desde `vehiculo_objetivo.ultimas_entradas_ia` y las **2 salidas** desde `ultima_aceleracion_ia` / `ultimo_giro_ia`, dibujando las neuronas ocultas atenuadas con el distintivo central `"Control Manual"` mientras mantiene vivos los 18 nodos de entrada y los 2 nodos de salida (`Acel`, `Giro`).

### 3.7. Sistema de 10 Niveles Pre-entrenados (`CerebroEntrenado.gd` y `EntrenadorGenetico.gd`)
Los cerebros se almacenan como recursos nativos de Godot (`.tres`) dentro de `res://Assets/Presets_ia/` (`nivel_01.tres` a `nivel_10.tres`) heredando de `Resource`:

```gdscript
class_name CerebroEntrenado
extends Resource

@export_range(1, 10) var nivel: int = 1
@export var titulo: String = ""
@export_multiline var descripcion_educativa: String = ""
@export var num_entradas: int = 18
@export var num_oculta: int = 8
@export var num_salida: int = 2
@export var pesos_oculta: PackedFloat64Array
@export var sesgos_oculta: PackedFloat64Array
@export var pesos_salida: PackedFloat64Array
@export var sesgos_salida: PackedFloat64Array
@export var fitness_alcanzado: float = 0.0
```

#### Entrenamiento Genético Offline con Currículum de 3 Geometrías (`EntrenadorGenetico.gd`)
* Opera en modo seguro por defecto (cargar o verificar el script nunca dispara entrenamiento).
* Reutiliza directamente `ArquetiposPista` en `crear_circuito_entrenamiento()` y `entrenar_en_arbol()` para evaluar **3 geometrías progresivas**:
  1. **Óvalo Clásico (`OVALO_CLASICO`):** Evaluado desde la generación `0`.
  2. **S-Enlazadas (`S_ENLAZADAS`):** Incorporado a partir de la generación `15` (o desde el inicio cuando `max_generaciones <= 2`).
  3. **Horquilla Técnica (`HORQUILLA_TECNICA`):** Incorporado a partir de la generación `35` (o desde el inicio cuando `max_generaciones <= 2`).
  El fitness de cada individuo se promedia entre las pistas activas de la generación.
* Para generar `nivel_01.tres` a `nivel_10.tres` en consola headless cuando el usuario decida ejecutar el entrenamiento:
  ```powershell
  godot --headless --path . --script res://Assets/Scripts/Ia/EntrenadorGenetico.gd -- --entrenar
  ```
* `res://Assets/Presets_ia/` permanece en el repositorio solo con `.gitkeep` hasta que el usuario ejecute `-- --entrenar`; mientras no existan archivos `.tres` entrenados, `RedNeuronal.cargar_nivel_o_fallback(nivel)` provee una red válida de respaldo para evitar errores en ejecución.

#### Progresión Educativa de los 10 Presets:
1. **Nivel 1 — Novato Caótico:** Pesos sin refinar; acelera sin frenar y gira erráticamente.
2. **Nivel 2 — Primeros Reflejos:** Detecta el muro frontal tarde; intenta esquivar pero roza bordes.
3. **Nivel 3 — Cauteloso Lento:** Mantiene baja aceleración constante; supera curvas abiertas.
4. **Nivel 4 — Zig-Zag Nervioso:** Completa rectas y curvas suaves, pero oscila entre los bordes.
5. **Nivel 5 — Conductor Básico:** Completa circuitos sencillos a velocidad media sin chocar.
6. **Nivel 6 — Trazada Estable:** Estabiliza la dirección usando los sensores laterales de ±45°.
7. **Nivel 7 — Control de Frenada:** Reduce aceleración al detectar proximidad en sensores frontales.
8. **Nivel 8 — Piloto Ágil:** Aprovecha rectas a alta velocidad y anticipa giros cerrados.
9. **Nivel 9 — Ápice Óptimo:** Busca el interior de las curvas para minimizar distancia.
10. **Nivel 10 — Maestro Autónomo:** Conducción fluida, rápida y adaptable a cualquier circuito.

---

## 4. Estructura de Carpetas del Proyecto (`EDrive Lab`)

```text
res://
├── .editorconfig
├── .gitignore
├── .gitattributes
├── .mcp.json                           # Configuración MCP local (protegida)
├── project.godot
├── LICENSE
├── TDD_EDrive_Lab.md
├── addons/
│   └── godot_mcp_toolkit/              # Plugin toolkit MCP en editor (protegido)
├── App/
│   ├── Dupster Studio.png              # Splash / identidad local (+ .import)
│   └── icon.svg                        # Icono de aplicación (+ .import)
├── Assets/
│   ├── Escenas/
│   │   ├── Componentes/
│   │   │   ├── checkpoint.tscn
│   │   │   ├── vehiculo_agente.tscn
│   │   │   └── visor_red_neuronal.tscn
│   │   └── Vistas/
│   │       ├── menu_principal.tscn
│   │       ├── creador_mapa.tscn
│   │       ├── configuracion_carrera.tscn
│   │       └── vista_carrera.tscn
│   ├── Presets_ia/
│   │   ├── .gitkeep                    # Carpeta limpia hasta ejecutar --entrenar
│   │   └── (nivel_01.tres .. nivel_10.tres al ejecutar entrenamiento)
│   ├── Scripts/
│   │   ├── datos_simulacion.gd         # Autoload: DatosSimulacion
│   │   ├── Agente/
│   │   │   ├── estela_telemetrica.gd   # class_name EstelaTelemetrica
│   │   │   └── vehiculo_agente.gd      # class_name VehiculoAgente
│   │   ├── Ia/
│   │   │   ├── CerebroEntrenado.gd     # class_name CerebroEntrenado
│   │   │   ├── RedNeuronal.gd          # class_name RedNeuronal
│   │   │   └── EntrenadorGenetico.gd   # Herramienta CLI headless (--entrenar)
│   │   ├── Pistas/
│   │   │   ├── arquetipos_pista.gd     # class_name ArquetiposPista
│   │   │   ├── checkpoint.gd           # class_name CheckpointArea
│   │   │   ├── constructor_pista.gd    # class_name ConstructorPista
│   │   │   ├── EditorPista.gd
│   │   │   └── GeneradorCheckpoints.gd # class_name GeneradorCheckpoints
│   │   ├── UI/
│   │   │   ├── boton_animado.gd        # class_name BotonAnimado
│   │   │   └── visor_red_neuronal.gd   # class_name VisorRedNeuronal
│   │   └── Vistas/
│   │       ├── menu_principal.gd
│   │       ├── creador_mapa.gd
│   │       ├── configuracion_carrera.gd # class_name ConfiguracionCarreraUI
│   │       └── vista_carrera.gd         # class_name VistaCarreraUI
│   ├── Sprites/
│   │   ├── bandera_meta.png            # (+ .import)
│   │   ├── coche_base.png              # (+ .import)
│   │   ├── tileset_pista.png           # (+ .import)
│   │   └── tileset_pista.tres
│   └── Temas/
│       ├── tema_edrive.tres            # Sincronizado con tema_telemetria.tres
│       └── tema_telemetria.tres        # Tema activo en las 4 vistas
├── Temporales/
│   └── icon.svg                        # Recurso auxiliar (+ .import)
└── tests/
    ├── test_fase1_agente.gd
    ├── test_fase2_ia.gd
    ├── test_fase3_vista3.gd
    └── test_fase4_carrera.gd
```

*(Nota: Godot 4.7+ genera además archivos auxiliares `.uid` junto a los `.gd` y `.import` junto a las texturas para el registro de recursos en el proyecto).*

---

## 5. Pruebas Automatizadas y Verificación

El proyecto incluye **4 suites de pruebas automatizadas** con un total de **252 verificaciones** ejecutables en Godot headless:

```powershell
godot --headless --path . --script res://tests/<archivo>.gd
```

* `tests/test_fase1_agente.gd` (**74 verificaciones**): Capas y escena de `VehiculoAgente`, 14 sensores `RayCast2D` y normalización, física de los 5 atributos, colisión con muros, no colisión entre vehículos, temporizador anti-atascos, conteo de vueltas/checkpoints, resistencia a `NaN`/`INF`, **Modo Piloto Humano** (`es_humano` ↔ `control_manual`, entradas `WASD`/Flechas, física compartida y `ultimas_entradas_ia`) y **`EstelaTelemetrica`** (`top_level`, `z_index = 1`, colores verde/amarillo-naranja/azul-cian, longitud configurable `[10..600]` y limpieza en reinicio).
* `tests/test_fase2_ia.gd` (**50 verificaciones**): Topología `18 -> 8 -> 2`, inferencia feedforward con `tanh()`, serialización y round-trip temporal de `CerebroEntrenado`, casos borde `NaN`/`INF`, integración con `VehiculoAgente`, modo seguro de `EntrenadorGenetico` con evaluación sobre las **3 geometrías** (`Assets/Presets_ia/` solo con `.gitkeep`), y **`ArquetiposPista` + Vista 2** (`creador_mapa.tscn`, carga editable de los 3 circuitos, layout `1280x720`/`1920x1080`, `BotonAnimado` y `tema_telemetria.tres`).
* `tests/test_fase3_vista3.gd` (**78 verificaciones**): `GeneradorCheckpoints` (celdas `16 px` y regresión topológica), escenas Vista 1–3 (`BotonAnimado` y paridad `tema_edrive.tres`/`tema_telemetria.tres`), minimapa dinámico, 3 tarjetas/5 sliders/10 niveles IA, sanitización y persistencia en `DatosSimulacion`, layout multi-resolución (`1920x1080`, `1440x900`, `1280x960`, `1280x720`), **arquetipos de vehículo** (`Equilibrado`, `Velocista`, `Drift`, `Técnico`, `Personalizado`) y **selector `IA / Piloto Humano`** (exclusividad máx-1, `OptNivelIA.disabled`, regresiones de estado y normalización `1/2/4` ranuras).
* `tests/test_fase4_carrera.gd` (**50 verificaciones**): `VisorRedNeuronal` (`18 -> 8 -> 2` y modo `"Control Manual"`), aislamiento sin `DatosSimulacion`, reconstrucción Layer 1 y checkpoints dinámicos, simulación, zoom/seguimiento de cámara, toggle de rayos, escala de tiempo `1x/2x/4x`, reinicio (incluyendo regresión borde `Checkpoint_0`), layout multi-resolución, flujo E2E Vista 1→4 con `Assets/Presets_ia/` limpio (`.gitkeep`), invarianza de resolución, **Piloto Humano en Vista 4** (etiqueta `"Piloto Humano"`, `cerebro = null`, visor en vivo) y **`EstelaTelemetrica` + toggle `Estela: ON/OFF`** sin controles extra de longitud en la UI.
