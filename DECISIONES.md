# Registro de Decisiones de Arquitectura (ADRs) — Proyecto 1
**Universidad Simón Bolívar — CI-3661: Laboratorio de Lenguajes de Programación I**  
**Proyecto:** Motor de Aventuras de Texto en Haskell (`aventura`)  
**Equipo:** Víctor Hernández (`20-10349`) y Ángel Pacheco (`20-10479`)  
**Variante:** Variante 0: Oscuridad (`(2010349 + 2010479) mod 4 = 0`)

Este documento recopila las decisiones de diseño arquitectural adoptadas durante el desarrollo del motor, organizadas en formato ADR (*Architecture Decision Record*). Las decisiones fueron consensuadas por ambos integrantes y su redacción se repartió equitativamente (50% / 50%).

---

## D1. Representación del Mundo y de los Identificadores
* **Autor / Redactor:** Víctor Hernández (`20-10349`)

### Contexto
En los archivos de mundo (`mundo.txt`), tanto las salas como los objetos se identifican con palabras en minúsculas (`pasillo`, `carnet`, `linterna`), en espacios de nombres separados. En `Motor.Tipos` debíamos elegir cómo representar las colecciones de salas/objetos dentro de `Mundo` y qué garantías queríamos en tiempo de compilación frente a qué invariantes debían comprobarse en tiempo de carga.

### Opciones
1. **Listas de asociación con `String` crudos (`[(String, Sala)]` y `[(String, Objeto)]`):**
   * *Ventajas:* Directa de construir sin depender de estructuras adicionales; permite recorrer con `lookup` de `Prelude`.
   * *Desventajas:* Búsqueda lineal $O(n)$ en cada movimiento o consulta. Al usar `String` para todo, el compilador no detecta si se pasa por accidente un nombre de objeto donde se esperaba una sala.
2. **Mapas estrictos (`Data.Map.Strict`) con `newtype IdSala` e `IdObjeto` y sum type `Direccion`:**
   * *Ventajas:* Búsquedas en $O(\log n)$ en `salasMundo :: Map.Map IdSala Sala` y `objetosMundo :: Map.Map IdObjeto Objeto`. Al envolver las cadenas en `newtype IdSala` y `newtype IdObjeto` (junto con `Direccion` con exactamente 6 constructores), el sistema de tipos impide intercambiar salas por objetos sin costo en ejecución.
   * *Desventajas:* Obliga a envolver/desenvolver los constructores (`unIdSala`, `unIdObjeto`) al construir mensajes y convierte duplicados silenciosamente si se llama directo a `Map.fromList`.

### Decisión
Elegimos la **Opción 2** en `Motor.Tipos`: `Data.Map.Strict` indexado por `newtype IdSala` e `IdObjeto`, manteniendo en `Motor.Mundo` las listas crudas `[Sala]` y `[Objeto]` antes de armar los `Map` para detectar duplicados (V2) mediante `validarDuplicados`.

### Consecuencias
* **Invariantes que garantiza el tipo:** Imposibilidad de confundir un `IdSala` con un `IdObjeto` o de usar una `Direccion` fuera de las seis válidas (`Norte`, `Sur`, `Este`, `Oeste`, `Arriba`, `Abajo`), además de unicidad de claves dentro de `Map.Map`.
* **Invariantes que NO garantiza el tipo:** Existencia referencial (`destinoSalida`, `inicioMundo`, `metaMundo` u objetos requeridos), unicidad antes de construir el `Map`, alcanzabilidad del grafo ni unicidad de ubicación física de objetos. Todo ello queda garantizado por la función pura `leerMundo` en `Motor.Mundo` antes de entregar un `Right Mundo`.
* **Qué ganamos y qué perdimos:** Código seguro en tiempo de compilación y búsquedas rápidas en el motor, a cambio de validar explícitamente los identificadores duplicados sobre las listas previas al `Map.fromList` y usar `unIdSala`/`unIdObjeto` al imprimir.

---

## D2. Modelado de la Mutabilidad y Alcance del Estado del Juego
* **Autor / Redactor:** Ángel Pacheco (`20-10479`)

### Contexto
El motor debe implementar la función pura `ejecutar :: Comando -> Estado -> ([String], Estado)`. Cada turno puede cambiar la habitación del jugador, qué objetos lleva encima, cuáles quedaron en el suelo tras usar `soltar`, y qué salidas bloqueadas ya abrió. Dado que Haskell es inmutable, debíamos definir qué almacena `Estado`.

### Opciones
1. **Mundo monolítico mutable por copia (reescribir `Mundo` en cada turno):**
   * *Ventajas:* Un único registro contiene toda la partida; mover o soltar un objeto modifica directamente las listas de cada `Sala`.
   * *Desventajas:* Duplica descripciones estáticas largas en cada comando ejecutado y acopla textos inmutables del escenario con el progreso de la partida, dificultando guardar y cargar partidas limpiamente.
2. **Estado diferencial (Delta) con referencia al `Mundo` inmutable:**
   * *Ventajas:* En `Motor.Tipos`, `Estado` mantiene intacto `mundoEstatico :: Mundo` y guarda únicamente los cambios dinámicos: `salaActual :: IdSala`, `inventario :: Set.Set IdObjeto`, `ubicacionObjs :: Map.Map IdObjeto Ubicacion` y `puertasAbiertas :: Set.Set (IdSala, Direccion)`.
   * *Desventajas:* Consultar qué hay en una habitación requiere filtrar `ubicacionObjs` según el valor `Ubicacion` (`EnInventario` o `EnSala IdSala`).

### Decisión
Elegimos la **Opción 2**: **Estado Diferencial (Delta)** en `Motor.Tipos` y `Motor.Nucleo`. Los objetos iniciales se cargan en `estadoInicial` como `EnSala (idSala s)` dentro de `ubicacionObjs`; al ejecutar `Soltar idObj`, se elimina de `inventario` y se actualiza su entrada a `EnSala (salaActual est)`.

### Consecuencias
* *Qué ganamos:* Estados ligeros en cada turno, clara separación entre datos estáticos de diseño del mundo y deltas del jugador, y serialización mínima al guardar partidas.
* *Qué perdimos:* Necesidad de escribir funciones auxiliares puras (`objetosEnSala`, `obtenerSalaActual`) en `Motor.Nucleo` en lugar de leer directamente `objsIniciales` de cada sala.
* *Qué haríamos distinto:* Mantendríamos este diseño; facilita tanto el núcleo puro como la persistencia.

---

## D3. Estrategia de Validación y Acumulación de Todos los Errores (V1 a V10)
* **Autor / Redactor:** Víctor Hernández (`20-10349`)

### Contexto
La Sección 4 exige que `leerMundo` detecte **todos** los errores presentes en un archivo (sintácticos V1 y semánticos V2–V10) y los retorne juntos en `Left [ErrorMundo]`, sin abortar en el primer fallo.

### Opciones
1. **Encadenamiento monádico estándar sobre `Either ErrorMundo Mundo` (`do`):**
   * *Ventajas:* Sintaxis breve; cada comprobación falla rápido con `Left`.
   * *Desventajas:* En la mónada `Either e`, el primer `Left` corta inmediatamente el cómputo (`>>=`), haciendo imposible reportar el resto de errores del bloque o de las demás reglas del archivo en una sola ejecución.
2. **Acumulación explícita por bloque en V1 + batería concatenada en V2–V10:**
   * *Ventajas:*
     * En la fase sintáctica (V1), las funciones `recolectar` (en `parsearCabecera`, `parsearBloqueSala` y `parsearBloqueObjeto`) y `procesarBloques` (en `leerMundo`) devuelven listas acumuladas de `ErrorSintaxis` para todo el bloque y para todos los bloques del archivo, además de usar `tienePrefijo` (`habiaIntento`) para no duplicar un error de campo faltante cuando el campo sí estaba escrito con error de formato.
     * Solo cuando `todosErroresSintaxis` es `[]`, `validarMundo salas objetos mundo` concatena seis validadores puros independientes (`validarDuplicados salas objetos ++ validarSalidas mundo ++ validarObjetosEnSalas mundo ++ validarInicioYMeta mundo ++ validarAlcanzabilidad mundo ++ validarObjetosNecesarios mundo`), acumulando todos los errores V2–V10 juntos.
   * *Desventajas:* Recorre la estructura varias veces (una por grupo de reglas) y requiere listas de acumuladores explícitas en lugar de `>>=` con `Either`.

### Decisión
Elegimos la **Opción 2** en `Motor.Mundo`. Si hay errores de sintaxis V1 retorna `Left todosErroresSintaxis`; si la sintaxis es válida ejecuta `validarMundo` completa y retorna `Left errsSem` o `Right mundo`.

### Consecuencias
* *Qué ganamos:* Cumplimiento estricto del reporte acumulado en V1 y V2–V10, funciones pequeñas y testeables por separado, y eliminación de errores falsos duplicados cuando falta solo un parámetro de sintaxis en un campo obligatorio.
* *Qué perdimos:* Código algo más largo en la recolección de líneas frente a una notación `do` cortocircuitada.
* *Qué haríamos distinto:* Agregaríamos un `Applicative` acumulador tipo `Validation` solo si el número de campos creciera mucho; para tres tipos de bloque, `recolectar` y `validarMundo` son muy claros.

---

## D4. Diseño del Reconocedor Léxico/Sintáctico (`Motor.Reconocedor` y `Motor.Mundo`)
* **Autor / Redactor:** Víctor Hernández (`20-10349`)

### Contexto
El enunciado prohíbe usar `parsec`, `megaparsec`, `attoparsec`, `ReadP`, `Text.Read.Lex` y expresiones regulares, exigiendo construir combinadores propios sobre `ReadS` y reportar el **número de línea exacto** en cada `ErrorSintaxis`.

### Opciones
1. **Combinadores directos sin `newtype` sobre `ReadS a` (`String -> [(a, String)]`):**
   * *Ventajas:* No requiere envolver funciones en un tipo nuevo ni escribir instancias de clases estándar.
   * *Desventajas:* No se puede implementar `Functor`, `Applicative`, `Monad` ni `Alternative` propios sin caer en sinónimos de tipo conflictivos (`[(a, String)]`), perdiendo el uso de notación `do` y `<|>`.
2. **`newtype Parser a = Parser { runParser :: String -> [(a, String)] }` + preprocesamiento con líneas numeradas:**
   * *Representación:* Envuelve `ReadS a` en un `newtype` con instancias manuales de `Functor`, `Applicative`, `Monad` y `Alternative`.
   * *Manejo de ambigüedad (múltiples resultados):* En `Alternative`, `(p1 <|> p2)` es sesgado/determinista: si `p1` produce al menos un resultado no vacío conserva ese resultado y no evalúa `p2`. Al ejecutar un parser completo con `parsear :: Parser a -> String -> Maybe a`, se conservan únicamente las derivaciones que consumieron toda la línea (`all isSpace resto`) y se selecciona la primera coincidencia `(res:_) -> Just res`.
   * *Obtención del número de línea:* Antes de separar por `---` o ignorar comentarios, `leerMundo` convierte el texto mediante `zip [(1 :: Int) ..] (lines contenido)` al alias `type LineaNum = (Int, String)`. Así, aunque se filtren líneas vacías y comentarios `#`, cada línea conserva su número físico real para `ErrorSintaxis`.
   * *Desventajas:* Requiere escribir manualmente las cuatro instancias y primitivas (`satisfy`, `char`, `cadena`, `muchos`, `alMenosUno`, `palabra`, `restoLinea`).

### Decisión
Elegimos la **Opción 2** repartida entre `Motor.Reconocedor` (motor de combinadores) y `Motor.Mundo` (gramática del archivo y numeración `LineaNum`).

### Consecuencias
* *Qué ganamos:* Expresividad con `do` y `<|>` 100% propia sin dependencias externas prohibidas, rechazo automático de basura al final de línea mediante `all isSpace resto`, y numeración exacta de errores aun con comentarios y líneas en blanco intercaladas.
* *Qué perdimos:* Escribir explícitamente la base combinatoria en `Motor.Reconocedor`.
* *Qué haríamos distinto:* Mantendríamos exactamente este diseño modular; separar `Parser` de las reglas de negocio simplificó enormemente depurar la gramática.

---

## D5. Reglas de Juego para la Variante 0 (Oscuridad)
* **Autor / Redactor:** Ángel Pacheco (`20-10479`)

### Contexto
En nuestra Variante 0 (*Oscuridad*), cuando el jugador está en una sala `OSCURA: si` sin llevar un objeto con `LUZ: si`, `mirar` no muestra objetos ni salidas y no se puede tomar ni examinar nada de la sala. El enunciado deja abierta la decisión de si el jugador puede salir de una sala oscura a ciegas y qué ocurre al soltar una fuente de luz en el suelo.

### Opciones
1. **Bloqueo rígido del movimiento sin luz:**
   * *Ventajas:* Un simple chequeo en `Ir` impide moverse si `not (estaIluminada est)`.
   * *Desventajas:* Provoca callejones sin salida irremediables (*soft-lock*) si el jugador entra a una sala oscura por curiosidad antes de buscar la linterna, impidiéndole siquiera retroceder por donde vino.
2. **Movimiento a ciegas con colisiones físicas e iluminación desde el suelo:**
   * *Movimiento a ciegas:* En `Motor.Nucleo`, si `not (estaIluminada est)` y el jugador ejecuta `ir <dir>`, se evalúa el mapa: si existe salida abierta avanza a tientas (*"Avanzas a tientas en la más absoluta oscuridad..."*); si no hay camino o la puerta requiere llave, colisiona (*"¡Te golpeas contra una pared/puerta cerrada en la oscuridad!"*) y no se mueve.
   * *Iluminación ambiental:* `estaIluminada` considera iluminada una sala si `not (esOscura sala)` o si existe algún objeto con `emiteLuz` tanto en `inventario est` como en el suelo de la sala (`objetosEnSala (salaActual est) est`).
   * *Desventajas:* Añade ramas específicas para mensajes de penumbra en `Ir`, `Mirar`, `Tomar` y `Examinar`.

### Decisión
Elegimos la **Opción 2** en `Motor.Nucleo`.

### Consecuencias
* *Qué ganamos:* Evita bloqueos irrecuperables en salas oscuras, mantiene el desafío de no ver objetos/salidas ni poder cruzar puertas cerradas a ciegas, y da un comportamiento natural si el jugador suelta la linterna en el suelo.
* *Qué perdimos:* Lógica condicional adicional en `ejecutar`.
* *Qué haríamos distinto:* Nada; funciona de forma coherente tanto en juego manual como en guiones.

---

## D6. Interfaz de Comandos, Tolerancia Léxica y Salidas Bloqueadas
* **Autor / Redactor:** Ángel Pacheco (`20-10479`)

### Contexto
Debíamos decidir qué variantes de comandos acepta `leerComando :: String -> Maybe Comando` en `Motor.Comandos` y si una salida con `requiere <objeto>` permanece abierta permanentemente después de abrirla.

### Opciones
1. **Gramática estricta literal y chequeo constante de llave:**
   * *Ventajas:* `leerComando` solo acepta órdenes en minúsculas completas (`ir norte`, `tomar llave`) y `Ir` siempre verifica si la llave sigue en el inventario.
   * *Desventajas:* Penaliza la comodidad al jugar (obligando a escribir comandos largos y cargar objetos ya usados todo el tiempo).
2. **Abreviaturas/sinónimos normalizados, aridad fija para objetos y apertura permanente:**
   * *Comandos:* Se normalizan espacios y mayúsculas con `words` y `map toLower` (preservando el texto exacto de rutas en `guardar`/`cargar`). Se admiten abreviaturas de dirección con o sin `ir` (`n`, `s`, `e`, `o`, `arr`, `ab`), `m` para `mirar`, `inv`/`i` para `inventario` y el sinónimo `coger` para `tomar`. Para objetos (`tomar`, `coger`, `soltar`, `examinar`) se exigen exactamente 2 tokens (`verbo <id_objeto>`), rechazando artículos como `"tomar la linterna"` para evitar ambigüedades con identificadores.
   * *Puertas:* Al cruzar una salida con `requiereItem = Just objReq` llevando `objReq`, la pareja `(salaActual, dir)` se guarda en `puertasAbiertas` de `Estado`, quedando abierta para futuros pasos aunque el jugador luego suelte el objeto.
   * *Desventajas:* No tolera lenguaje natural libre con artículos ni objetos escritos con espacios.

### Decisión
Elegimos la **Opción 2** en `Motor.Comandos` y `Motor.Nucleo`.

### Consecuencias
* *Qué ganamos:* Comandos ágiles y predecibles (0 ambigüedad sobre identificadores con `_`), además de un progreso lógico de puertas desbloqueadas.
* *Qué perdimos:* Si alguien escribe `"tomar la llave"` recibe mensaje de comando no reconocido en lugar de ignorar `"la"`.
* *Qué haríamos distinto:* Es el equilibrio adecuado para la gramática del proyecto.

---

## D7. Estrategia de Persistencia de Partidas (Guardar y Cargar)
* **Autor / Redactor:** Ángel Pacheco (`20-10479`)

### Contexto
La Sección 6 exige que `guardar <archivo>` y `cargar <archivo>` nunca colapsen el programa si el archivo no existe, está corrupto o corresponde a otro mundo.

### Opciones
1. **Serializar el `Estado` entero (incluyendo `Mundo`) o crear un parser de texto ad-hoc:**
   * *Ventajas:* Un formato propio sería más legible para humanos; derivar `Read` en `Estado` completo evitaría cruzar con el mundo activo.
   * *Desventajas:* Duplica el `Mundo` estático en disco, congela descripciones viejas si el mundo cambia y multiplica el código de parsing susceptible a errores.
2. **Registro auxiliar `EstadoGuardado` (`Show, Read`) + `readMaybe` + validación de consistencia:**
   * En `Motor.Persistencia`, definimos `EstadoGuardado { egSalaActual, egInventario, egUbicacionObjs, egPuertasAbiertas }` derivando `Show` y `Read`.
   * Al cargar, verificamos primero `doesFileExist`, parseamos sin funciones parciales con `readMaybe` de `Text.Read`, y comprobamos `esConsistente eg` (que `egSalaActual` exista en `salasMundo` y todos los objetos en `egInventario` / `egUbicacionObjs` existan en `objetosMundo`). Si algo falla o el mundo cambió, devuelve `Left mensaje` y el juego sigue.
   * *Desventajas:* El archivo guardado expone la representación `Show` de Haskell y los cambios en `EstadoGuardado` asumen que las salas y objetos del mundo base siguen existiendo.

### Decisión
Elegimos la **Opción 2** en `Motor.Persistencia`.

### Consecuencias
* *Qué ganamos:* Cero excepciones al cargar archivos corruptos, faltantes o de otro mundo, y coherencia total con el `Estado` diferencial de D2.
* *Qué perdimos:* Dependencia de nombres de constructores Haskell en el archivo `.sav` (si cambia la estructura interna del mundo, la partida antigua se rechaza de forma segura).
* *Qué haríamos distinto:* Mantendríamos `EstadoGuardado` con `readMaybe`; es seguro y conciso.

---

## D8. Entrada/Salida en Terminal y Redirección de Guiones
* **Autor / Redactor:** Víctor Hernández (`20-10349`) y Ángel Pacheco (`20-10479`)

### Contexto
El ejecutable `aventura` debe funcionar tanto interactivamente en terminal con indicador `> ` como redirigido desde archivo (`aventura mundo.txt < guion.txt`), saliendo sin excepciones cuando termina la entrada.

### Opciones
1. **Lectura línea a línea con `getLine` y manejo imperativo de excepciones (`try`/`catch isEOFError`):**
   * *Ventajas:* Patrón directo en programación imperativa.
   * *Desventajas:* `getLine` lanza `EOFError` al terminar un archivo redirigido, obligando a envolver cada iteración en `Control.Exception` y mezclar manejo de excepciones impuras con la lógica del bucle.
2. **Evaluación perezosa (Lazy I/O) con `lines <$> getContents` y `hFlush stdout`:**
   * *Ventajas:* En `app/Main.hs`, `modoJuego` obtiene el flujo completo perezosamente con `lineas <- lines <$> getContents` y se lo entrega a `bucleJuego :: Estado -> [String] -> IO ()`. Gracias a la evaluación perezosa, solo se lee de la entrada estándar a medida que se consume el patrón `(l : resto)`; cuando el guion llega al fin de archivo, la lista termina en `[]` y `bucleJuego` finaliza limpiamente con `exitSuccess` sin excepciones. Antes de consumir el siguiente elemento se llama a `hFlush stdout` para que el prompt `> ` aparezca de inmediato sin quedar retenido en el búfer.
   * *Desventajas:* Requiere no re-leer `stdin` en otro sitio mientras `getContents` mantiene el handle abierto de forma perezosa y recordar `hFlush stdout` manualmente.

### Decisión
Elegimos la **Opción 2** en `app/Main.hs`.

### Consecuencias
* *Qué ganamos:* Un único bucle recursivo limpio que sirve igual para jugar en vivo y para ejecutar guiones automatizados sin excepciones por EOF.
* *Qué perdimos:* Dependencia del orden correcto entre `putStr "> " >> hFlush stdout` y el pattern matching sobre `lineas`.
* *Qué haríamos distinto:* Nada; aprovecha directamente la evaluación perezosa estudiada en clase.
