# Proyecto 1: Motor de Aventuras de Texto en Haskell (`aventura`)

**Universidad Simón Bolívar**  
**CI-3661 — Laboratorio de Lenguajes de Programación I (Sep–Dic 2026)**  
**Profesor:** Leonardo López Almazán  

### Integrantes
* **Víctor Hernández** — Carnet: `20-10349` (50%: `Motor.Tipos`, `Motor.Reconocedor`, `Motor.Mundo` — reconocedor sintáctico V1 y validadores semánticos V2–V10, pruebas de validación, ADRs D1, D3, D4)
* **Ángel Pacheco C.** — Carnet: `20-10479` (50%: `Motor.Comandos`, `Motor.Nucleo`, `Motor.Persistencia`, `app/Main.hs`, mundo y guion oficial, pruebas del núcleo/comandos, ADRs D2, D5, D6, D7)

---

## 1. Asignación y Cálculo de la Variante

De acuerdo con la regla de la Sección 7 del enunciado (suma de los carnets sin guion módulo 4):
$$\text{Suma de Carnets} = 2010349 + 2010479 = 4020828$$
$$4020828 \bmod 4 = 0 \longrightarrow \textbf{Variante 0: Oscuridad}$$

En esta variante:
* Las salas pueden declarar `OSCURA: si` y los objetos `LUZ: si`.
* Si una sala está oscura y el jugador no tiene una fuente de luz activa (ni en el inventario ni en el suelo), `mirar` no muestra objetos ni salidas y no se puede `tomar` ni `examinar` objetos de la sala.
* El jugador puede moverse a ciegas con `ir <dir>`: si la salida existe y no está bloqueada, avanza a tientas; si hay una pared o una puerta cerrada, recibe un mensaje de colisión y permanece en la sala.
* Soltar un objeto con `LUZ: si` en una sala oscura la mantiene iluminada desde el suelo.

---

## 2. Requisitos y Dependencias

El proyecto usa únicamente los paquetes permitidos por el enunciado:
* `base` (`>= 4.14 && < 5`)
* `containers` (`>= 0.6`)
* `directory` (`>= 1.3`)
* `filepath` (`>= 1.4`)
* `HUnit` (`>= 1.6`, exclusivo para la suite de pruebas)

No se utilizan bibliotecas externas de reconocimiento (`parsec`, `megaparsec`, `attoparsec`, `ReadP`, expresiones regulares ni `split`). Todos los combinadores fueron construidos manualmente sobre `ReadS` en `Motor.Reconocedor`.

---

## 3. Compilación y Construcción

El proyecto puede construirse con **Stack** o **Cabal**:

### Con Stack
```bash
# Compilar la biblioteca y el ejecutable
stack build

# Compilar incluyendo la suite de pruebas
stack build --test --no-run-tests
```

### Con Cabal
```bash
cabal build
```

---

## 4. Ejecución del Programa

El ejecutable se llama `aventura` y admite validación estática o partida interactiva / con guion redirigido:

### Modo 1: Validación Estática de Mundos (`--validar` / `-validar`)
Ejecuta el reconocedor sintáctico (V1) y la batería completa de validadores semánticos (V2–V10) sin iniciar el juego. Imprime `Mundo válido.` y termina con código `0`, o imprime cada error (empezando por `Error: `) y termina con código `1`:
```bash
# Usando Stack
stack run aventura -- --validar mundos/mundo.txt
stack run aventura -- -validar mundos/mundo.txt

# Usando Cabal
cabal run aventura -- --validar mundos/mundo.txt
cabal run aventura -- -validar mundos/mundo.txt
```

### Modo 2: Juego Interactivo
Carga el mundo, muestra su título y la descripción de la sala inicial, y entra en el ciclo con indicador `> `:
```bash
stack run aventura -- mundos/mundo.txt
# o con Cabal:
cabal run aventura -- mundos/mundo.txt
```

### Modo 3: Ejecución con Guion Redirigido
Consume los comandos de la entrada estándar mediante Lazy I/O y finaliza limpiamente con código `0` al alcanzar la meta o llegar al fin de archivo (EOF):
```bash
# Probar el mundo oficial con su guion ganador
stack run aventura -- mundos/mundo.txt < guiones/mundo.txt

# Probar el mundo de ejemplo del material del curso
stack run aventura -- ../material/mundos/entrega.txt < ../material/guiones/entrega.txt
```

---

## 5. Ejecución de Pruebas Unitarias

La suite de pruebas en `test/Spec.hs` verifica reconocimiento de comandos, movimiento, salidas bloqueadas, Variante 0 (Oscuridad), victoria y validación de mundos válidos e inválidos:

```bash
# Con Stack
stack test

# Con Cabal
cabal test
```

---

## 6. Estructura del Repositorio

* `src/Motor/Tipos.hs`: Tipos algebraicos del dominio (`IdSala`, `IdObjeto`, `Direccion`, `Salida`, `Sala`, `Objeto`, `Meta`, `Mundo`, `Ubicacion`, `Estado`, `Comando`, `ErrorMundo`).
* `src/Motor/Reconocedor.hs`: Tipo `Parser` sobre `ReadS`, instancias (`Functor`, `Applicative`, `Monad`, `Alternative`) y combinadores propios (`satisfy`, `char`, `cadena`, `muchos`, `alMenosUno`, `palabra`, `restoLinea`, `separadoPor`, `separadoPor1`).
* `src/Motor/Mundo.hs`: Parser sintáctico por bloques numerados (V1), validadores semánticos acumulativos (V2–V10), `leerMundo` y `formatearError`.
* `src/Motor/Comandos.hs`: Parser léxico de comandos del jugador (`leerComando`), abreviaturas y sinónimos.
* `src/Motor/Nucleo.hs`: Lógica pura de transición de estados y Variante 0 (`estadoInicial`, `ejecutar`, `estaIluminada`, `verificarVictoria`, `obtenerSalaActual`, `objetosEnSala`, `objetoEmiteLuz`).
* `src/Motor/Persistencia.hs`: Lectura de mundos y guardado/carga segura de partidas con `EstadoGuardado` y `readMaybe` (`cargarMundoArchivo`, `guardarPartida`, `cargarPartida`).
* `app/Main.hs`: Interfaz de línea de comandos (`--validar`/`-validar`) y bucle principal con Lazy I/O.
* `mundos/mundo.txt`: Mundo original *"El Enigma de los Sótanos de Sartenejas"* (9 salas, 7 objetos, 3 salidas bloqueadas y oscuridad).
* `guiones/mundo.txt`: Guion ganador para el mundo oficial.
* `mundos/invalidos/`: Mundos inválidos que cubren V1–V10 incluyendo claves de la Variante 0.
* `test/Spec.hs`: Suite de pruebas unitarias con `HUnit`.
* `DECISIONES.md` e `IA.md`: Registro de decisiones de arquitectura (ADRs) y declaración de uso de IA.
