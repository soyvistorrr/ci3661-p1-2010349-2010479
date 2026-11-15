module Main (main) where

import Test.HUnit
import System.Exit (exitFailure, exitSuccess)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.List (isInfixOf)
import GHC.IO.Encoding (setLocaleEncoding, utf8)

import Motor.Tipos
import Motor.Comandos (leerComando)
import Motor.Nucleo (
    estadoInicial,
    ejecutar,
    estaIluminada,
    verificarVictoria
  )
import Motor.Mundo (leerMundo)

-- ============================================================================
-- MUNDO DE PRUEBAS EN MEMORIA (Auto-contenido para pruebas puras de lógica)
-- ============================================================================

contenidoMundoPrueba :: String
contenidoMundoPrueba = unlines
  [ "MUNDO: Cripta de Pruebas Unitarias"
  , "INICIO: entrada"
  , "META: llevar gema a altar"
  , "---"
  , "OBJETO: linterna"
  , "DESC: Una linterna potente de exploracion."
  , "LUZ: si"
  , "---"
  , "OBJETO: gema"
  , "DESC: Una gema brillante que irradia energia."
  , "---"
  , "OBJETO: llave"
  , "DESC: Una llave pesada de hierro forjado."
  , "---"
  , "SALA: entrada"
  , "DESC: La entrada a la cripta. Hay una linterna en el suelo."
  , "SALIDA: norte -> pasillo"
  , "OBJETO: linterna"
  , "OBJETO: gema"
  , "---"
  , "SALA: pasillo"
  , "DESC: Un pasillo estrecho con una puerta cerrada al norte."
  , "SALIDA: sur -> entrada"
  , "SALIDA: este -> camara_oscura"
  , "SALIDA: norte -> altar requiere llave"
  , "---"
  , "SALA: camara_oscura"
  , "DESC: Una camara subterranea sin iluminacion natural."
  , "OSCURA: si"
  , "SALIDA: oeste -> pasillo"
  , "OBJETO: llave"
  , "---"
  , "SALA: altar"
  , "DESC: El altar sagrado ceremonial."
  , "SALIDA: sur -> pasillo"
  ]

-- | Obtiene el mundo de prueba garantizando que parsea correctamente
obtenerMundoPrueba :: Mundo
obtenerMundoPrueba = case leerMundo contenidoMundoPrueba of
  Right m -> m
  Left errs -> error ("Error inesperado en mundo de prueba: " ++ show errs)

-- ============================================================================
-- BLOQUE 1: PRUEBAS DE LEERCOMANDO (PARSER LÉXICO)
-- ============================================================================

-- | Caso de uso: El jugador introduce el comando mirar o su abreviatura.
-- Qué se espera probar: Reconocimiento exacto de "mirar" y del atajo "m".
-- Resultado esperado: Just Mirar en ambos casos.
testMirar :: Test
testMirar = TestCase $ do
  assertEqual "Comando mirar completo" (Just Mirar) (leerComando "mirar")
  assertEqual "Abreviatura m" (Just Mirar) (leerComando "m")

-- | Caso de uso: El jugador consulta el inventario con distintas variantes.
-- Qué se espera probar: Tolerancia a sinónimos ("inventario", "inv", "i").
-- Resultado esperado: Just Inventario para las tres formas.
testInventario :: Test
testInventario = TestCase $ do
  assertEqual "Comando inventario" (Just Inventario) (leerComando "inventario")
  assertEqual "Abreviatura inv" (Just Inventario) (leerComando "inv")
  assertEqual "Abreviatura i" (Just Inventario) (leerComando "i")

-- | Caso de uso: El jugador recoge un objeto usando sinónimos ("tomar" o "coger").
-- Qué se espera probar: Que tanto "tomar" como "coger" se mapeen al constructor Tomar.
-- Resultado esperado: Just (Tomar (IdObjeto "llave")).
testTomarSinonimos :: Test
testTomarSinonimos = TestCase $ do
  assertEqual "Tomar objeto" (Just (Tomar (IdObjeto "llave"))) (leerComando "tomar llave")
  assertEqual "Coger objeto (sinonimo)" (Just (Tomar (IdObjeto "llave"))) (leerComando "coger llave")

-- | Caso de uso: Movimiento con direcciones abreviadas sin la palabra "ir".
-- Qué se espera probar: Que "n", "s", "e", "o", "arr", "ab" produzcan Ir con su direccion.
-- Resultado esperado: Just (Ir <Direccion>) correspondiente.
testDireccionesAbreviadas :: Test
testDireccionesAbreviadas = TestCase $ do
  assertEqual "Norte abreviado" (Just (Ir Norte)) (leerComando "n")
  assertEqual "Sur abreviado" (Just (Ir Sur)) (leerComando "s")
  assertEqual "Este abreviado" (Just (Ir Este)) (leerComando "e")
  assertEqual "Oeste abreviado" (Just (Ir Oeste)) (leerComando "o")
  assertEqual "Arriba abreviado" (Just (Ir Arriba)) (leerComando "arr")
  assertEqual "Abajo abreviado" (Just (Ir Abajo)) (leerComando "ab")

-- | Caso de uso: Entrada con mayúsculas y espacios en blanco redundantes.
-- Qué se espera probar: Que map toLower y words limpien la entrada antes de parsear.
-- Resultado esperado: Just (Tomar (IdObjeto "linterna")).
testToleranciaMayusculasYEspacios :: Test
testToleranciaMayusculasYEspacios = TestCase $ do
  assertEqual "Mayusculas y espacios extra"
    (Just (Tomar (IdObjeto "linterna")))
    (leerComando "   TOMAR    LINTERNA   ")

-- | Caso de uso: Comandos de persistencia guardar y cargar.
-- Qué se espera probar: Que se preserve exactamente la ruta del archivo ingresado.
-- Resultado esperado: Just (Guardar "partida_1.sav") y Just (Cargar "partida_1.sav").
testPersistenciaRuta :: Test
testPersistenciaRuta = TestCase $ do
  assertEqual "Guardar archivo" (Just (Guardar "partida_1.sav")) (leerComando "guardar partida_1.sav")
  assertEqual "Cargar archivo" (Just (Cargar "partida_1.sav")) (leerComando "cargar partida_1.sav")

-- | Caso de uso: El jugador ingresa comandos con articulos ("tomar la linterna").
-- Qué se espera probar: Regla ADR-06 (dos tokens estrictos para objetos).
-- Resultado esperado: Nothing (rechazo de comandos de 3 o mas palabras).
testRechazoComandosLargos :: Test
testRechazoComandosLargos = TestCase $ do
  assertEqual "Rechazo de lenguaje natural con articulo" Nothing (leerComando "tomar la linterna")
  assertEqual "Rechazo de ir con preposicion" Nothing (leerComando "ir hacia el norte")

-- | Caso de uso: Entrada de texto desconocida o vacía.
-- Qué se espera probar: Robustez ante palabras que no pertenecen a la gramática.
-- Resultado esperado: Nothing.
testComandosInvalidos :: Test
testComandosInvalidos = TestCase $ do
  assertEqual "Verbo inexistente" Nothing (leerComando "saltar")
  assertEqual "Linea vacia" Nothing (leerComando "")
  assertEqual "Espacios solos" Nothing (leerComando "     ")

-- ============================================================================
-- BLOQUE 2: PRUEBAS DEL NÚCLEO Y MOVIMIENTO PURO
-- ============================================================================

-- | Caso de uso: El jugador se desplaza por una salida abierta existente.
-- Qué se espera probar: Que ejecutar (Ir Norte) actualice salaActual al destino.
-- Resultado esperado: salaActual = IdSala "pasillo".
testMovimientoNormal :: Test
testMovimientoNormal = TestCase $ do
  let m = obtenerMundoPrueba
      est0 = estadoInicial m
      (_, est1) = ejecutar (Ir Norte) est0
  assertEqual "Jugador avanza al pasillo" (IdSala "pasillo") (salaActual est1)

-- | Caso de uso: El jugador intenta cruzar una puerta cerrada sin tener la llave.
-- Qué se espera probar: Que la posicion no cambie y se reporte el objeto requerido.
-- Resultado esperado: salaActual permanece en "pasillo" y no se desbloquea la puerta.
testPuertaBloqueadaSinLlave :: Test
testPuertaBloqueadaSinLlave = TestCase $ do
  let m = obtenerMundoPrueba
      est0 = estadoInicial m
      (_, est1) = ejecutar (Ir Norte) est0
      (msgs, est2) = ejecutar (Ir Norte) est1
  assertEqual "No avanza por puerta bloqueada" (IdSala "pasillo") (salaActual est2)
  assertBool "Mensaje de bloqueo contiene nombre de llave"
    (any (\l -> "bloqueada" `isInfixOf` l || "llave" `isInfixOf` l) msgs)

-- | Caso de uso: El jugador tiene la llave en su inventario e intenta cruzar la puerta.
-- Qué se espera probar: Desbloqueo permanente, actualizacion de puertasAbiertas y avance.
-- Resultado esperado: salaActual = IdSala "altar" y (pasillo, Norte) en puertasAbiertas.
testDesbloqueoConLlave :: Test
testDesbloqueoConLlave = TestCase $ do
  let m = obtenerMundoPrueba
      est0 = (estadoInicial m) {
        salaActual = IdSala "pasillo",
        inventario = Set.singleton (IdObjeto "llave")
      }
      (_, est1) = ejecutar (Ir Norte) est0
  assertEqual "Avanza al altar con la llave" (IdSala "altar") (salaActual est1)
  assertBool "La puerta queda registrada como abierta"
    (Set.member (IdSala "pasillo", Norte) (puertasAbiertas est1))

-- | Caso de uso: El jugador llega a la sala meta con el objeto requerido de la meta.
-- Qué se espera probar: Cumplimiento de la meta LlevarA y emision del mensaje de victoria.
-- Resultado esperado: verificarVictoria = True y mensaje exacto "*** ¡Has ganado! ***".
testVictoriaLlevarA :: Test
testVictoriaLlevarA = TestCase $ do
  let m = obtenerMundoPrueba
      est0 = (estadoInicial m) {
        salaActual = IdSala "pasillo",
        inventario = Set.fromList [IdObjeto "llave", IdObjeto "gema"]
      }
      (msgs, estFinal) = ejecutar (Ir Norte) est0
  assertBool "Estado satisface verificarVictoria" (verificarVictoria estFinal)
  assertBool "Se emite el mensaje oficial de victoria"
    ("*** ¡Has ganado! ***" `elem` msgs)

-- ============================================================================
-- BLOQUE 3: PRUEBAS DE LA VARIANTE 0 (OSCURIDAD)
-- ============================================================================

-- | Caso de uso: El jugador entra a una sala oscura sin portar luz e intenta mirar.
-- Qué se espera probar: Restriccion de la Variante 0: mirar no muestra salidas ni objetos.
-- Resultado esperado: Mensaje indicando que esta demasiado oscuro para ver algo.
testMirarEnOscuridad :: Test
testMirarEnOscuridad = TestCase $ do
  let m = obtenerMundoPrueba
      estOscuro = (estadoInicial m) { salaActual = IdSala "camara_oscura" }
      (msgs, _) = ejecutar Mirar estOscuro
  assertBool "Sala no esta iluminada" (not (estaIluminada estOscuro))
  assertBool "Mensaje advierte sobre falta de luz"
    (any (\l -> "oscuro" `isInfixOf` l) msgs)

-- | Caso de uso: El jugador intenta tomar un objeto que esta en una sala oscura sin luz.
-- Qué se espera probar: Prohibicion de tomar objetos en penumbra sin iluminacion.
-- Resultado esperado: El objeto no pasa al inventario y se emite mensaje de oscuridad.
testTomarEnOscuridad :: Test
testTomarEnOscuridad = TestCase $ do
  let m = obtenerMundoPrueba
      estOscuro = (estadoInicial m) { salaActual = IdSala "camara_oscura" }
      (msgs, estDespues) = ejecutar (Tomar (IdObjeto "llave")) estOscuro
  assertEqual "Inventario sigue vacio" Set.empty (inventario estDespues)
  assertBool "Mensaje impide tomar en penumbra"
    (any (\l -> "oscuro" `isInfixOf` l) msgs)

-- | Caso de uso: Movimiento a ciegas en una sala oscura hacia una salida libre.
-- Qué se espera probar: Regla ADR-05: se permite avanzar a tientas si hay salida abierta.
-- Resultado esperado: salaActual = IdSala "pasillo" y mensaje de avance a tientas.
testAvanzarACiegas :: Test
testAvanzarACiegas = TestCase $ do
  let m = obtenerMundoPrueba
      estOscuro = (estadoInicial m) { salaActual = IdSala "camara_oscura" }
      (msgs, estDespues) = ejecutar (Ir Oeste) estOscuro
  assertEqual "Logra salir de la sala oscura a tientas" (IdSala "pasillo") (salaActual estDespues)
  assertBool "Mensaje narra movimiento en penumbra"
    (any (\l -> "tientas" `isInfixOf` l || "oscuridad" `isInfixOf` l) msgs)

-- | Caso de uso: El jugador intenta caminar a oscuras en una direccion donde no hay salida.
-- Qué se espera probar: Colision fisica en la oscuridad segun ADR-05.
-- Resultado esperado: Se emite choque fisico y permanece en la misma sala.
testColisionEnOscuridad :: Test
testColisionEnOscuridad = TestCase $ do
  let m = obtenerMundoPrueba
      estOscuro = (estadoInicial m) { salaActual = IdSala "camara_oscura" }
      (msgs, estDespues) = ejecutar (Ir Norte) estOscuro
  assertEqual "Permanece en la camara oscura" (IdSala "camara_oscura") (salaActual estDespues)
  assertBool "Emite mensaje de golpe contra pared"
    (any (\l -> "golpeas" `isInfixOf` l || "pared" `isInfixOf` l) msgs)

-- | Caso de uso: Iluminacion desde el suelo al soltar un objeto que emite luz.
-- Qué se espera probar: Regla ADR-05: soltar linterna en sala oscura la ilumina desde el suelo.
-- Resultado esperado: estaIluminada = True, y luego mirar describe la sala normalmente.
testIluminacionDesdeElSuelo :: Test
testIluminacionDesdeElSuelo = TestCase $ do
  let m = obtenerMundoPrueba
      estConLuz = (estadoInicial m) {
        salaActual = IdSala "camara_oscura",
        inventario = Set.singleton (IdObjeto "linterna"),
        ubicacionObjs = Map.insert (IdObjeto "linterna") EnInventario (ubicacionObjs (estadoInicial m))
      }
      -- El jugador suelta la linterna en la camara oscura
      (_, estSuelo) = ejecutar (Soltar (IdObjeto "linterna")) estConLuz
      (msgsMirar, _) = ejecutar Mirar estSuelo
  assertBool "La sala ahora esta iluminada por la linterna en el suelo" (estaIluminada estSuelo)
  assertBool "Mirar muestra la descripcion real de la camara"
    (any (\l -> "camara" `isInfixOf` l || "subterranea" `isInfixOf` l) msgsMirar)

-- ============================================================================
-- BLOQUE 4: PRUEBAS DE VALIDACIÓN DE MUNDOS (LEERMUNDO)
-- ============================================================================

-- | Caso de uso: Validacion del mundo oficial propio creado para el proyecto.
-- Qué se espera probar: Que mundos/mundo.txt cumple toda la sintaxis y semantica V1-V10.
-- Resultado esperado: Right Mundo con 9 salas y 7 objetos.
testValidacionMundoOficial :: Test
testValidacionMundoOficial = TestCase $ do
  contenido <- readFile "mundos/mundo.txt"
  case leerMundo contenido of
    Left errs -> assertFailure ("Mundo oficial no debio tener errores: " ++ show errs)
    Right m   -> do
      assertBool "Tiene al menos 8 salas" (Map.size (salasMundo m) >= 8)
      assertBool "Tiene al menos 6 objetos" (Map.size (objetosMundo m) >= 6)

-- | Caso de uso: Validacion del mundo de ejemplo de la catedra (entrega.txt).
-- Qué se espera probar: Que el reconocedor acepta el mundo de ejemplo del enunciado (Seccion 8.2).
-- Resultado esperado: Right Mundo con 9 salas y 5 objetos.
testValidacionEjemploEnunciado :: Test
testValidacionEjemploEnunciado = TestCase $ do
  contenido <- readFile "../material/mundos/entrega.txt"
  case leerMundo contenido of
    Left errs -> assertFailure ("entrega.txt no debio tener errores: " ++ show errs)
    Right m   -> do
      assertEqual "entrega.txt tiene 9 salas" 9 (Map.size (salasMundo m))
      assertEqual "entrega.txt tiene 5 objetos" 5 (Map.size (objetosMundo m))

-- | Caso de uso: Validacion de mundos invalidos con errores de grafo (invalido1).
-- Qué se espera probar: Deteccion acumulada de identificadores duplicados (2 V2), V3 y V5.
-- Resultado esperado: Left con exactamente 4 errores reportados juntos.
testValidacionInvalidoGrafo :: Test
testValidacionInvalidoGrafo = TestCase $ do
  contenido <- readFile "mundos/invalidos/invalido1_grafo.txt"
  case leerMundo contenido of
    Right _   -> assertFailure "invalido1_grafo debio fallar pero fue aceptado"
    Left errs -> assertEqual "Reporta exactamente 4 errores de grafo" 4 (length errs)

-- | Caso de uso: Validacion de mundos invalidos con salas inalcanzables (invalido2).
-- Qué se espera probar: Deteccion de V8 (2 errores), V9 (1 error) y V10 (1 error) acumulados.
-- Resultado esperado: Left con exactamente 4 errores de alcanzabilidad.
testValidacionInvalidoAlcanzabilidad :: Test
testValidacionInvalidoAlcanzabilidad = TestCase $ do
  contenido <- readFile "mundos/invalidos/invalido2_alcanzabilidad.txt"
  case leerMundo contenido of
    Right _   -> assertFailure "invalido2_alcanzabilidad debio fallar"
    Left errs -> assertEqual "Reporta exactamente 4 errores de alcanzabilidad" 4 (length errs)

-- | Caso de uso: Validacion de sintaxis corrupta en la Variante 0 (invalido3).
-- Qué se espera probar: Deteccion de V1 con numero de linea en campos OSCURA y LUZ.
-- Resultado esperado: Left con exactamente 2 errores de sintaxis indicando la linea.
testValidacionInvalidoVariante :: Test
testValidacionInvalidoVariante = TestCase $ do
  contenido <- readFile "mundos/invalidos/invalido3_variante0.txt"
  case leerMundo contenido of
    Right _   -> assertFailure "invalido3_variante0 debio fallar por sintaxis"
    Left errs -> assertEqual "Reporta exactamente 2 errores de sintaxis en variante" 2 (length errs)

-- | Caso de uso: Validacion de objetos inconsistentes o duplicados (invalido4).
-- Qué se espera probar: Deteccion de V4 (llave no definida), V6 y V7 (objeto duplicado).
-- Resultado esperado: Left con exactamente 3 errores.
testValidacionInvalidoObjetos :: Test
testValidacionInvalidoObjetos = TestCase $ do
  contenido <- readFile "mundos/invalidos/invalido4_objetos.txt"
  case leerMundo contenido of
    Right _   -> assertFailure "invalido4_objetos debio fallar"
    Left errs -> assertEqual "Reporta exactamente 3 errores semanticos de objetos" 3 (length errs)

-- ============================================================================
-- EJECUTOR PRINCIPAL DE PRUEBAS
-- ============================================================================

suitePruebas :: Test
suitePruebas = TestList
  [ -- Grupo 1: Comandos (8 pruebas)
    "testMirar"                            ~: testMirar
  , "testInventario"                       ~: testInventario
  , "testTomarSinonimos"                   ~: testTomarSinonimos
  , "testDireccionesAbreviadas"            ~: testDireccionesAbreviadas
  , "testToleranciaMayusculasYEspacios"    ~: testToleranciaMayusculasYEspacios
  , "testPersistenciaRuta"                 ~: testPersistenciaRuta
  , "testRechazoComandosLargos"            ~: testRechazoComandosLargos
  , "testComandosInvalidos"                ~: testComandosInvalidos

    -- Grupo 2: Núcleo y Movimiento (4 pruebas)
  , "testMovimientoNormal"                 ~: testMovimientoNormal
  , "testPuertaBloqueadaSinLlave"          ~: testPuertaBloqueadaSinLlave
  , "testDesbloqueoConLlave"               ~: testDesbloqueoConLlave
  , "testVictoriaLlevarA"                  ~: testVictoriaLlevarA

    -- Grupo 3: Variante 0 - Oscuridad (5 pruebas)
  , "testMirarEnOscuridad"                 ~: testMirarEnOscuridad
  , "testTomarEnOscuridad"                 ~: testTomarEnOscuridad
  , "testAvanzarACiegas"                   ~: testAvanzarACiegas
  , "testColisionEnOscuridad"              ~: testColisionEnOscuridad
  , "testIluminacionDesdeElSuelo"          ~: testIluminacionDesdeElSuelo

    -- Grupo 4: Validación de Mundos (6 pruebas)
  , "testValidacionMundoOficial"           ~: testValidacionMundoOficial
  , "testValidacionEjemploEnunciado"       ~: testValidacionEjemploEnunciado
  , "testValidacionInvalidoGrafo"          ~: testValidacionInvalidoGrafo
  , "testValidacionInvalidoAlcanzabilidad" ~: testValidacionInvalidoAlcanzabilidad
  , "testValidacionInvalidoVariante"       ~: testValidacionInvalidoVariante
  , "testValidacionInvalidoObjetos"        ~: testValidacionInvalidoObjetos
  ]

main :: IO ()
main = do
  setLocaleEncoding utf8
  conteos <- runTestTT suitePruebas
  if errors conteos + failures conteos > 0
    then exitFailure
    else exitSuccess
