# Declaración de Uso de Asistentes de Inteligencia Artificial (IA)
**Universidad Simón Bolívar — CI-3661: Laboratorio de Lenguajes de Programación I**  
**Proyecto 1:** Motor de Aventuras de Texto en Haskell (`aventura`)  
**Integrantes:** Víctor Hernández (`20-10349`) y Ángel Pacheco (`20-10479`)  

En cumplimiento con lo estipulado en la **Sección 8.4** del enunciado del proyecto, declaramos de forma transparente las herramientas de IA empleadas durante el desarrollo, los propósitos para los que fueron consultadas y ejemplos concretos donde sus sugerencias fueron rechazadas o corregidas tras nuestra revisión.

---

## 1. Herramientas Utilizadas y Propósito

Durante el desarrollo utilizamos el asistente **Antigravity (Google DeepMind)** principalmente para:

1. **Comprensión de tipos, instancias y combinadores en Haskell:**
   * Explicación línea por línea del funcionamiento de `newtype Parser` sobre `ReadS`, las instancias `Functor`, `Applicative`, `Monad` y `Alternative`, tipos algebraicos (`data` / `newtype`) y el uso seguro de `readMaybe` en lugar de funciones parciales.
2. **Convenciones de estilo y diagnóstico de advertencias del compilador:**
   * Resolución de advertencias estrictas bajo `-Wall`, `-Wcompat`, `-Wincomplete-record-updates`, `-Wincomplete-uni-patterns` y `-Wredundant-constraints` (por ejemplo, sombreado de nombres como `pred` en `satisfy`, patrones incompletos y organización de layouts `let`/`where`/`case`).
3. **Planificación equitativa (50% / 50%) y documentación:**
   * Estructuración inicial de la división de módulos entre ambos integrantes y revisión de redacción/formato de [README.md](README.md), [DECISIONES.md](DECISIONES.md) y [IA.md](IA.md) para asegurar consistencia con el código implementado.
4. **Organización de pruebas unitarias y casos borde:**
   * Estructuración de bloques en [test/Spec.hs](test/Spec.hs) e identificación de casos borde como preservación de rutas en `guardar`/`cargar`, rechazo de artículos (`"tomar la linterna"`), colisiones a ciegas e iluminación desde el suelo en salas oscuras.

---

## 2. Sugerencias Rechazadas o Corregidas por el Equipo

Documentamos cuatro casos concretos donde revisamos y rechazamos o corregimos propuestas iniciales generadas por la IA:

### Caso 1: Uso de bibliotecas externas (`parsec` y `split`) — Rechazada
* **Sugerencia inicial:** Utilizar paquetes externos como `parsec` o `Data.List.Split` para reconocer el formato del mundo.
* **Razón del rechazo:** El enunciado prohíbe explícitamente en la Sección 5 usar librerías externas de parsing fuera de `base`, `containers`, `directory`, `filepath` y `HUnit`.
* **Solución aplicada:** Rechazamos esa vía e implementamos desde cero nuestros combinadores monádicos sobre `ReadS` en `Motor.Reconocedor` junto con funciones puras estándar de `Data.List` y `Data.Char`.

### Caso 2: Error doble fantasma en campos obligatorios mal escritos (`Motor.Mundo`) — Corregida
* **Sugerencia inicial:** En los bloques de cabecera, `SALA` y `OBJETO`, `verificarUnico` reportaba `"Falta campo obligatorio X"` cada vez que la lista de campos válidos recolectados (`metas`, `descs`, etc.) quedaba vacía.
* **Razón de la corrección:** Al probar el archivo oficial `invalido_sintaxis.txt` (donde la línea 4 dice `META: llegar cuarto`, sin la palabra `"a"`), ese diseño generaba **dos errores para la misma línea**: primero reportaba la línea 4 como inválida y luego añadía un segundo error falso en la línea 2 diciendo que faltaba `META`, elevando el conteo a 5 errores en lugar de los 4 reales.
* **Solución aplicada:** Incorporamos `tienePrefijo` y la verificación `habiaIntento` en `parsearCabecera`, `parsearBloqueSala` y `parsearBloqueObjeto` para que solo se reporte ausencia de campo cuando ninguna línea del bloque comenzó con esa etiqueta, reportando exactamente los 4 errores en líneas 4, 8, 9 y 11.

### Caso 3: Derivar `Read` directamente sobre `Mundo` para persistencia — Rechazada
* **Sugerencia inicial:** Agregar `deriving (Read)` al tipo completo `Mundo` y serializarlo entero al ejecutar `guardar`.
* **Razón del rechazo:** Duplica textos estáticos inmutables en disco y acopla la partida guardada a versiones viejas de las descripciones si el archivo base `.txt` se corrige (ADR D2 y D7). Además, un borrador previo del ADR D1 mencionaba incorrectamente `Map.fromListWith` en lugar de `validarDuplicados`, lo cual también corregimos al auditar el documento frente al código real.
* **Solución aplicada:** Definimos `EstadoGuardado` en `Motor.Persistencia` únicamente para el delta dinámico (`egSalaActual`, `egInventario`, `egUbicacionObjs`, `egPuertasAbiertas`), validado con `readMaybe` y `esConsistente` contra el `Mundo` activo.

### Caso 4: Bucle con `getLine` y excepciones de EOF (`app/Main.hs`) — Corregida
* **Sugerencia inicial:** Escribir el bucle principal con `getLine` dentro de bloques `try`/`catch` para atrapar `isEOFError` cuando termina un guion redirigido.
* **Razón de la corrección:** Mezcla control de flujo con excepciones impuras en lugar de aprovechar el modelo perezoso del lenguaje (ADR D8).
* **Solución aplicada:** Usamos Lazy I/O mediante `lines <$> getContents` y recursión estructural sobre la lista en `bucleJuego`, terminando naturalmente con `exitSuccess` al alcanzar `[]` (EOF).

---

## 3. Declaración de Autoría

Confirmamos que todo el código fuente, tipos, combinadores, validadores, núcleo del juego, pruebas unitarias y archivos de mundo fueron escritos, comprendidos, probados y verificados por nosotros dos, asumiendo plena responsabilidad sobre su funcionamiento.
