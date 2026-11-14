module Motor.Mundo (
    leerMundo,
    formatearError
) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Control.Applicative ((<|>), empty)
import Data.Char (toLower, isSpace)
import Data.Maybe (mapMaybe)

import Motor.Tipos
import Motor.Reconocedor

-- | Par (numeroDeLinea, textoLimpioDeLaLinea)
type LineaNum = (Int, String)

-- UTILIDADES Y PRIMITIVAS DE IDENTIFICADORES

-- | Elimina espacios en blanco al inicio y al final de una cadena
limpiarEspacios :: String -> String
limpiarEspacios = reverse . dropWhile isSpace . reverse . dropWhile isSpace

-- | Verifica si una cadena comienza con el prefijo dado
tienePrefijo :: String -> String -> Bool
tienePrefijo pref str = take (length pref) str == pref

-- | Al menos un espacio en blanco
espacios1 :: Parser String
espacios1 = alMenosUno (satisfy isSpace)

-- | Caracteres permitidos en identificadores: minusculas (incluyendo acentos, ñ, ü), digitos y '_'
esCharId :: Char -> Bool
esCharId c = (c >= 'a' && c <= 'z')
          || (c >= '0' && c <= '9')
          || c == '_'
          || c `elem` "áéíóúñü"

-- | Reconoce un identificador valido
identificador :: Parser String
identificador = alMenosUno (satisfy esCharId)

-- PARSERS DE LÍNEAS INDIVIDUALES

-- | "MUNDO: <titulo>"
parsearLineaMundo :: Parser String
parsearLineaMundo = do
    _ <- cadena "MUNDO:"
    _ <- espacios
    texto <- restoLinea
    let limpio = limpiarEspacios texto
    if null limpio then empty else return limpio

-- | "INICIO: <id_sala>"
parsearLineaInicio :: Parser IdSala
parsearLineaInicio = do
    _   <- cadena "INICIO:"
    _   <- espacios1
    sId <- identificador
    return (IdSala sId)

-- | "META: llegar a <sala>" o "META: llevar <objeto> a <sala>"
parsearLineaMeta :: Parser Meta
parsearLineaMeta = do
    _ <- cadena "META:"
    _ <- espacios1
    parsearLlegar <|> parsearLlevar
  where
    parsearLlegar = do
        _   <- cadena "llegar"
        _   <- espacios1
        _   <- cadena "a"
        _   <- espacios1
        sId <- identificador
        return (LlegarA (IdSala sId))

    parsearLlevar = do
        _   <- cadena "llevar"
        _   <- espacios1
        oId <- identificador
        _   <- espacios1
        _   <- cadena "a"
        _   <- espacios1
        sId <- identificador
        return (LlevarA (IdObjeto oId) (IdSala sId))

-- | Direccion valida
parsearDireccion :: Parser Direccion
parsearDireccion = do
    dStr <- palabra
    case map toLower dStr of
        "norte"  -> return Norte
        "sur"    -> return Sur
        "este"   -> return Este
        "oeste"  -> return Oeste
        "arriba" -> return Arriba
        "abajo"  -> return Abajo
        _        -> empty

-- | "SALIDA: <dir> -> <sala>" o "SALIDA: <dir> -> <sala> requiere <objeto>"
parsearLineaSalida :: Parser Salida
parsearLineaSalida = do
    _    <- cadena "SALIDA:"
    _    <- espacios1
    dir  <- parsearDireccion
    _    <- espacios1
    _    <- cadena "->"
    _    <- espacios1
    dest <- identificador
    mReq <- (do
                _   <- espacios1
                _   <- cadena "requiere"
                _   <- espacios1
                req <- identificador
                return (Just (IdObjeto req))
            ) <|> return Nothing
    return (Salida dir (IdSala dest) mReq)

-- | "DESC: <texto libre>"
parsearLineaDesc :: Parser String
parsearLineaDesc = do
    _ <- cadena "DESC:"
    _ <- espacios
    texto <- restoLinea
    let limpio = limpiarEspacios texto
    if null limpio then empty else return limpio

-- | "OSCURA: si/no" o "LUZ: si/no"
parsearBooleano :: String -> Parser Bool
parsearBooleano etiqueta = do
    _   <- cadena etiqueta
    _   <- espacios1
    val <- palabra
    case map toLower val of
        "si" -> return True
        "no" -> return False
        _    -> empty

-- | "SALA: <id_sala>"
parsearEncabezadoSala :: Parser IdSala
parsearEncabezadoSala = do
    _   <- cadena "SALA:"
    _   <- espacios1
    sId <- identificador
    return (IdSala sId)

-- | "OBJETO: <id_objeto>"
parsearEncabezadoObjeto :: Parser IdObjeto
parsearEncabezadoObjeto = do
    _   <- cadena "OBJETO:"
    _   <- espacios1
    oId <- identificador
    return (IdObjeto oId)

-- AGRUPACIÓN Y RECONOCIMIENTO DE BLOQUES

-- | Parte las lineas en bloques usando "---" como separador
separarBloques :: [LineaNum] -> [[LineaNum]]
separarBloques [] = []
separarBloques lineas =
    let (bloque, resto) = break (\(_, texto) -> texto == "---") lineas
        restoSinGuion   = case resto of
                            []     -> []
                            (_:rs) -> rs
    in bloque : separarBloques restoSinGuion

-- | Reconoce el bloque de Cabecera (MUNDO, INICIO, META) acumulando todos los errores
parsearCabecera :: [LineaNum] -> Either [ErrorMundo] (String, IdSala, Meta)
parsearCabecera [] = Left [ErrorSintaxis 1 "Bloque de cabecera vacio"]
parsearCabecera lineas@((primeraLinea, _):_) =
    let (mundos, inicios, metas, errsLinea) = recolectar lineas [] [] [] []
        errsMundo  = verificarUnico primeraLinea "MUNDO" mundos
        errsInicio = verificarUnico primeraLinea "INICIO" inicios
        errsMeta   = verificarUnico primeraLinea "META" metas
        todosErrs  = errsLinea ++ errsMundo ++ errsInicio ++ errsMeta
    in case (todosErrs, mundos, inicios, metas) of
        ([], [(_, tit)], [(_, ini)], [(_, met)]) -> Right (tit, ini, met)
        _                                        -> Left todosErrs
  where
    recolectar [] ms is mts errs = (ms, is, mts, errs)
    recolectar ((n, l):ls) ms is mts errs
        | Just t <- parsear parsearLineaMundo l =
            recolectar ls (ms ++ [(n, t)]) is mts errs
        | Just i <- parsear parsearLineaInicio l =
            recolectar ls ms (is ++ [(n, i)]) mts errs
        | Just m <- parsear parsearLineaMeta l =
            recolectar ls ms is (mts ++ [(n, m)]) errs
        | otherwise =
            recolectar ls ms is mts (errs ++ [ErrorSintaxis n ("Linea invalida en cabecera: " ++ l)])

    verificarUnico nBase nombreCampo lista =
        let pref = nombreCampo ++ ":"
            habiaIntento = any (\(_, l) -> tienePrefijo pref l) lineas
        in case lista of
            [] | habiaIntento   -> []
               | otherwise      -> [ErrorSintaxis nBase ("Falta campo obligatorio " ++ nombreCampo ++ " en cabecera")]
            [_]                 -> []
            (_:(nDup, _):_)     -> [ErrorSintaxis nDup ("Campo repetido " ++ nombreCampo ++ " en cabecera")]

-- | Reconoce un bloque de SALA acumulando todos los errores de sus lineas
parsearBloqueSala :: [LineaNum] -> Either [ErrorMundo] Sala
parsearBloqueSala [] = Left [ErrorSintaxis 1 "Bloque de sala vacio"]
parsearBloqueSala ((numL, primera):resto) =
    case parsear parsearEncabezadoSala primera of
        Nothing ->
            Left [ErrorSintaxis numL ("Identificador de SALA invalido: " ++ primera)]
        Just sId ->
            let (descs, oscs, sals, objs, errsLinea) = recolectar resto [] [] [] [] []
                errsDesc = case descs of
                    [] | any (\(_, l) -> tienePrefijo "DESC:" l) resto -> []
                       | otherwise -> [ErrorSintaxis numL ("Falta campo obligatorio DESC en SALA " ++ unIdSala sId)]
                    [_]             -> []
                    (_:(nDup, _):_) -> [ErrorSintaxis nDup ("Campo DESC repetido en SALA " ++ unIdSala sId)]
                errsOsc = case oscs of
                    (_:(nDup, _):_) -> [ErrorSintaxis nDup ("Campo OSCURA repetido en SALA " ++ unIdSala sId)]
                    _               -> []
                todosErrs = errsLinea ++ errsDesc ++ errsOsc
                oscFinal  = case oscs of
                    [(_, b)] -> b
                    _        -> False
            in case (todosErrs, descs) of
                ([], [(_, d)]) -> Right (Sala sId (unIdSala sId) d oscFinal sals objs)
                _              -> Left todosErrs
  where
    recolectar [] ds os ss obs errs = (ds, os, ss, obs, errs)
    recolectar ((n, l):ls) ds os ss obs errs
        | Just d <- parsear parsearLineaDesc l =
            recolectar ls (ds ++ [(n, d)]) os ss obs errs
        | Just o <- parsear (parsearBooleano "OSCURA:") l =
            recolectar ls ds (os ++ [(n, o)]) ss obs errs
        | Just s <- parsear parsearLineaSalida l =
            recolectar ls ds os (ss ++ [s]) obs errs
        | Just objId <- parsear parsearEncabezadoObjeto l =
            recolectar ls ds os ss (obs ++ [objId]) errs
        | otherwise =
            recolectar ls ds os ss obs (errs ++ [ErrorSintaxis n ("Linea invalida en SALA: " ++ l)])

-- | Reconoce un bloque de OBJETO acumulando todos los errores de sus lineas
parsearBloqueObjeto :: [LineaNum] -> Either [ErrorMundo] Objeto
parsearBloqueObjeto [] = Left [ErrorSintaxis 1 "Bloque de objeto vacio"]
parsearBloqueObjeto ((numL, primera):resto) =
    case parsear parsearEncabezadoObjeto primera of
        Nothing ->
            Left [ErrorSintaxis numL ("Identificador de OBJETO invalido: " ++ primera)]
        Just oId ->
            let (descs, luces, errsLinea) = recolectar resto [] [] []
                errsDesc = case descs of
                    [] | any (\(_, l) -> tienePrefijo "DESC:" l) resto -> []
                       | otherwise -> [ErrorSintaxis numL ("Falta campo obligatorio DESC en OBJETO " ++ unIdObjeto oId)]
                    [_]             -> []
                    (_:(nDup, _):_) -> [ErrorSintaxis nDup ("Campo DESC repetido en OBJETO " ++ unIdObjeto oId)]
                errsLuz = case luces of
                    (_:(nDup, _):_) -> [ErrorSintaxis nDup ("Campo LUZ repetido en OBJETO " ++ unIdObjeto oId)]
                    _               -> []
                todosErrs = errsLinea ++ errsDesc ++ errsLuz
                luzFinal  = case luces of
                    [(_, b)] -> b
                    _        -> False
            in case (todosErrs, descs) of
                ([], [(_, d)]) -> Right (Objeto oId (unIdObjeto oId) d luzFinal)
                _              -> Left todosErrs
  where
    recolectar [] ds lzs errs = (ds, lzs, errs)
    recolectar ((n, l):ls) ds lzs errs
        | Just d <- parsear parsearLineaDesc l =
            recolectar ls (ds ++ [(n, d)]) lzs errs
        | Just lz <- parsear (parsearBooleano "LUZ:") l =
            recolectar ls ds (lzs ++ [(n, lz)]) errs
        | otherwise =
            recolectar ls ds lzs (errs ++ [ErrorSintaxis n ("Linea invalida en OBJETO: " ++ l)])

-- VALIDACION SEMANTICA

-- | Devuelve los elementos que aparecen mas de una vez en la lista
buscarDuplicados :: Ord a => [a] -> [a]
buscarDuplicados = reverse . snd . foldl paso (Set.empty, [])
    where
        paso (vistos, dups) x
            | Set.member x vistos =
                let dups' = if x `elem` dups then dups else x : dups
                in (vistos, dups')
            | otherwise = (Set.insert x vistos, dups)

-- | Dos salas o dos objetos con el mismo identificador
validarDuplicados :: [Sala] -> [Objeto] -> [ErrorMundo]
validarDuplicados salas objetos =
    let dupsSalas = [ IdentificadorDuplicado ("sala repetida: " ++ unIdSala sId)
            | sId <- buscarDuplicados (map idSala salas) ]
        dupsObjs = [ IdentificadorDuplicado ("objeto repetido: " ++ unIdObjeto oId)
            | oId <- buscarDuplicados (map idObjeto objetos) ]
    in dupsSalas ++ dupsObjs

-- | Validacion de todas las salidas de cada sala
validarSalidas :: Mundo -> [ErrorMundo] 
validarSalidas mundo = concatMap revisarSala (Map.elems (salasMundo mundo))
    where
        salas   = salasMundo mundo
        objs    = objetosMundo mundo
        revisarSala s =
            let sId = idSala s
                sals = salidasSala s
                errDest =   [ SalidaDestinoInexistente sId (dirSalida sal) (destinoSalida sal)
                            | sal <- sals
                            , not (Map.member (destinoSalida sal) salas) ]
                errObj  =   [ SalidaObjetoInexistente sId (dirSalida sal) req
                            | sal <- sals
                            , Just req <- [requiereItem sal]
                            , not (Map.member req objs) ]
                errDir  =   [ SalidaDireccionDuplicada sId d
                            | d <- buscarDuplicados (map dirSalida sals) ]
            in errDest ++ errObj ++ errDir

-- | Objetos en sala no definidos y ubicados multiples veces
validarObjetosEnSalas :: Mundo -> [ErrorMundo]
validarObjetosEnSalas mundo =
    let listaSalas      = Map.elems (salasMundo mundo)
        objs            = objetosMundo mundo
        errNoDef        =   [ ObjetoEnSalaNoDefinido (idSala s) oId 
                            | s <- listaSalas
                            , oId <- objsIniciales s
                            , not (Map.member oId objs) ]
        todosColocados  = concatMap objsIniciales listaSalas
        errMult         =   [ ObjetoUbicadoMultiplesVeces oId
                            | oId <- buscarDuplicados todosColocados ]
    in errNoDef ++ errMult

-- | INICIO o META con una sala o un objeto inexistente
validarInicioYMeta :: Mundo -> [ErrorMundo]
validarInicioYMeta mundo =
    let salas   = salasMundo mundo
        objs    = objetosMundo mundo
        errIni  =   if Map.member (inicioMundo mundo) salas
                    then []
                    else [InicioOMetaInexistente ("INICIO apunta a sala inexistente: " ++ unIdSala (inicioMundo mundo))]
        errMeta = case metaMundo mundo of
            LlegarA dest ->
                if Map.member dest salas
                then []
                else [InicioOMetaInexistente ("META apunta a sala inexistente: " ++ unIdSala dest)]
            LlevarA oId dest -> 
                let eObj    =   if Map.member oId objs
                                then []
                                else [InicioOMetaInexistente ("META requiere objeto inexistente: " ++ unIdObjeto oId)]
                    eSala   =   if Map.member dest salas
                                then []
                                else [InicioOMetaInexistente ("META apunta a sala inexistente: " ++ unIdSala dest)]
                in eObj ++ eSala
    in errIni ++ errMeta

-- | Salas no alcanzables desde INICIO siguiendo salidas (ignorando requisitos)
validarAlcanzabilidad :: Mundo -> [ErrorMundo]
validarAlcanzabilidad mundo =
    let salas = salasMundo mundo
        ini   = inicioMundo mundo
    in case Map.lookup ini salas of
        Nothing -> []
        Just _  ->
            let visitados = explorar (Set.singleton ini) [ini]
            in [ SalaInalcanzable sId
               | sId <- Map.keys salas
               , not (Set.member sId visitados) ]
  where
    explorar visitados [] = visitados
    explorar visitados (actual:cola) =
        let vecinos = case Map.lookup actual (salasMundo mundo) of
                Nothing -> []
                Just s  -> map destinoSalida (salidasSala s)
            nuevos = filter (\v -> Map.member v (salasMundo mundo) 
                            && not (Set.member v visitados)) vecinos
            visitados' = foldr Set.insert visitados nuevos
        in explorar visitados' (cola ++ nuevos)

-- | Objetos necesarios no colocados en ninguna sala
validarObjetosNecesarios :: Mundo -> [ErrorMundo]
validarObjetosNecesarios mundo =
    let objs      = objetosMundo mundo
        colocados = Set.fromList (concatMap objsIniciales (Map.elems (salasMundo mundo)))
        reqsMeta  = case metaMundo mundo of
            LlegarA _     -> []
            LlevarA oId _ -> [oId]
        reqsSal   = [ req
                    | s   <- Map.elems (salasMundo mundo)
                    , req <- mapMaybe requiereItem (salidasSala s) ]
        necesariosDefinidos = Set.toList $ Set.fromList $
            filter (\oId -> Map.member oId objs) (reqsMeta ++ reqsSal)
    in [ ObjetoNecesarioNoColocado oId
       | oId <- necesariosDefinidos
       , not (Set.member oId colocados) ]

-- | Ejecuta todas las validaciones semanticas acumulando todos los errores
validarMundo :: [Sala] -> [Objeto] -> Mundo -> [ErrorMundo]
validarMundo salas objetos mundo =
       validarDuplicados salas objetos
    ++ validarSalidas mundo
    ++ validarObjetosEnSalas mundo
    ++ validarInicioYMeta mundo
    ++ validarAlcanzabilidad mundo
    ++ validarObjetosNecesarios mundo

-- FUNCIÓN PRINCIPAL PURA: leerMundo

-- | Recibe el contenido del archivo de mundo, lo reconoce y valida
leerMundo :: String -> Either [ErrorMundo] Mundo
leerMundo contenido =
    let lineasNumeradas = [ (n, limpiarEspacios l) | (n, l) <- zip [(1 :: Int) ..] (lines contenido) ]
        esComentarioOVacia (_, "")      = True
        esComentarioOVacia (_, ('#':_)) = True
        esComentarioOVacia _            = False
        lineasLimpias = filter (not . esComentarioOVacia) lineasNumeradas
        bloques       = filter (not . null) (separarBloques lineasLimpias)
    in case bloques of
        [] -> Left [ErrorSintaxis 1 "El archivo de mundo esta vacio"]
        (bloqueCabecera : restoBloques) ->
            let resCabecera = parsearCabecera bloqueCabecera
                (salas, objetos, errsBloques) = procesarBloques restoBloques [] [] []
                errsCabecera = case resCabecera of
                    Left errs -> errs
                    Right _   -> []
                todosErroresSintaxis = errsCabecera ++ errsBloques
            in case (todosErroresSintaxis, resCabecera) of
                ([], Right (tit, ini, met)) ->
                    let mapaSalas   = Map.fromList [ (idSala s, s) | s <- salas ]
                        mapaObjetos = Map.fromList [ (idObjeto o, o) | o <- objetos ]
                        mundo       = Mundo tit ini met mapaSalas mapaObjetos
                        errsSem      = validarMundo salas objetos mundo
                    in  if null errsSem
                        then Right mundo
                        else Left errsSem
                _ -> Left todosErroresSintaxis
  where
    procesarBloques [] accSalas accObjs accErrs = (accSalas, accObjs, accErrs)
    procesarBloques (b:bs) accSalas accObjs accErrs =
        case b of
            [] -> procesarBloques bs accSalas accObjs accErrs
            ((n, primera):_)
                | tienePrefijo "SALA:" primera ->
                    case parsearBloqueSala b of
                        Left errs -> procesarBloques bs accSalas accObjs (accErrs ++ errs)
                        Right s   -> procesarBloques bs (accSalas ++ [s]) accObjs accErrs
                | tienePrefijo "OBJETO:" primera ->
                    case parsearBloqueObjeto b of
                        Left errs -> procesarBloques bs accSalas accObjs (accErrs ++ errs)
                        Right o   -> procesarBloques bs accSalas (accObjs ++ [o]) accErrs
                | otherwise ->
                    let err = ErrorSintaxis n ("Bloque desconocido que inicia con: " ++ primera)
                    in procesarBloques bs accSalas accObjs (accErrs ++ [err])

formatearError :: ErrorMundo -> String
formatearError err = case err of
    ErrorSintaxis n msg ->
        "Error: [Linea " ++ show n ++ "] " ++ msg 
    IdentificadorDuplicado info ->
        "Error: Identificador duplicado (" ++ info ++ ")"
    SalidaDestinoInexistente orig dir dest ->
        "Error: La salida " ++ show dir ++ " de la sala '" ++ unIdSala orig
        ++ "' apunta a una sala inexistente '" ++ unIdSala dest ++ "'"
    SalidaObjetoInexistente orig dir obj ->
        "Error: La salida " ++ show dir ++ " de la sala '" ++ unIdSala orig
        ++ "' requiere un objeto inexistente '" ++ unIdObjeto obj ++ "'"
    SalidaDireccionDuplicada sId dir ->
        "Error: La sala '" ++ unIdSala sId ++ "' tiene mas de una salida hacia " ++ show dir
    ObjetoEnSalaNoDefinido sId obj ->
        "Error: La sala '" ++ unIdSala sId ++ "' contiene un objeto no definido '" ++ unIdObjeto obj ++ "'"
    ObjetoUbicadoMultiplesVeces obj ->
        "Error: El objeto '" ++ unIdObjeto obj ++ "' esta colocado mas de una vez"
    InicioOMetaInexistente msg ->
        "Error: " ++ msg
    SalaInalcanzable sId ->
        "Error: La sala '" ++ unIdSala sId ++ "' no es alcanzable desde INICIO"
    ObjetoNecesarioNoColocado obj ->
        "Error: El objeto necesario '" ++ unIdObjeto obj ++ "' no esta colocado en ninguna sala"