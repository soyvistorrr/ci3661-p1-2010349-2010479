module Motor.Nucleo (
    -- * Inicializacion del estado
    estadoInicial,

    -- * Motor de ejecucion puro
    ejecutar,

    -- * Consultas de estado puras
    estaIluminada,
    verificarVictoria,
    obtenerSalaActual,
    objetosEnSala,
    objetoEmiteLuz
) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Char (toLower)
import Data.List (find, intercalate)

import Motor.Tipos (
    IdSala(..),
    IdObjeto(..),
    Salida(..),
    Sala(..),
    Objeto(..),
    Meta(..),
    Mundo(..),
    Ubicacion(..),
    Estado(..),
    Comando(..)
  )

-- | Construye el estado inicial del juego a partir del mundo inmutable cargado
estadoInicial :: Mundo -> Estado
estadoInicial mundo = Estado {
    mundoEstatico   = mundo,
    salaActual      = inicioMundo mundo,
    inventario      = Set.empty,
    ubicacionObjs   = Map.fromList paresUbicacion,
    puertasAbiertas = Set.empty
}
  where
    salas = Map.elems (salasMundo mundo)
    paresUbicacion = [ (obj, EnSala (idSala s))
                     | s <- salas
                     , obj <- objsIniciales s
                     ]

-- | Consulta la sala actual del jugador si existe en el grafo del mundo
obtenerSalaActual :: Estado -> Maybe Sala
obtenerSalaActual est = Map.lookup (salaActual est) (salasMundo (mundoEstatico est))

-- | Obtiene los identificadores de objetos presentes fisicamente en una sala
objetosEnSala :: IdSala -> Estado -> [IdObjeto]
objetosEnSala sId est =
  Map.keys (Map.filter (== EnSala sId) (ubicacionObjs est))

-- | Determina si un objeto emite luz consultando sus propiedades estaticas
objetoEmiteLuz :: Estado -> IdObjeto -> Bool
objetoEmiteLuz est oId =
  case Map.lookup oId (objetosMundo (mundoEstatico est)) of
    Just obj -> emiteLuz obj
    Nothing  -> False

-- | Variante 0: Comprueba si la sala actual cuenta con iluminacion activa
estaIluminada :: Estado -> Bool
estaIluminada est =
  case obtenerSalaActual est of
    Nothing   -> False
    Just sala -> not (esOscura sala) || luzEnInventario || luzEnSuelo
      where
        luzEnInventario = any (objetoEmiteLuz est) (Set.toList (inventario est))
        luzEnSuelo      = any (objetoEmiteLuz est) (objetosEnSala (salaActual est) est)

-- | Comprueba si el estado actual satisface la condicion de victoria del mundo
verificarVictoria :: Estado -> Bool
verificarVictoria est =
  case metaMundo (mundoEstatico est) of
    LlegarA salaMeta         -> salaActual est == salaMeta
    LlevarA objMeta salaMeta -> salaActual est == salaMeta && Set.member objMeta (inventario est)

-- | Funcion pura principal del motor: ejecuta un comando y produce mensajes y nuevo estado
ejecutar :: Comando -> Estado -> ([String], Estado)
ejecutar cmd est = case cmd of
  Mirar
    | not (estaIluminada est) ->
        (["Está demasiado oscuro para ver algo. Necesitas una fuente de luz."], est)
    | otherwise -> case obtenerSalaActual est of
        Nothing   -> (["Error: la sala actual no existe en el mapa."], est)
        Just sala ->
          let desc = [descSala sala]
              objs = objetosEnSala (salaActual est) est
              lineaObjs = if null objs
                          then []
                          else ["Objetos en el suelo: " ++ intercalate ", " (map unIdObjeto objs)]
              lineaSalidas = ["Salidas: " ++ intercalate ", " (map (map toLower . show . dirSalida) (salidasSala sala))]
          in (desc ++ lineaObjs ++ lineaSalidas, est)

  Examinar idObj
    | not (estaIluminada est) && not (Set.member idObj (inventario est)) ->
        (["Está demasiado oscuro para ver o examinar nada."], est)
    | not (Set.member idObj (inventario est)) && not (idObj `elem` objetosEnSala (salaActual est) est) ->
        (["No ves ese objeto aquí ni lo llevas en tu inventario."], est)
    | otherwise -> case Map.lookup idObj (objetosMundo (mundoEstatico est)) of
        Just obj -> ([descObjeto obj], est)
        Nothing  -> (["Error: objeto no encontrado en el mundo."], est)

  Inventario
    | Set.null (inventario est) ->
        (["Tu inventario está vacío."], est)
    | otherwise ->
        (["Llevas contigo: " ++ intercalate ", " (map unIdObjeto (Set.toList (inventario est)))], est)

  Ayuda ->
    (["Comandos disponibles: ir <dirección>, mirar, tomar <objeto>, soltar <objeto>, examinar <objeto>, inventario, guardar <archivo>, cargar <archivo>, ayuda, salir."], est)

  Salir ->
    (["¡Gracias por jugar! Saliendo de la aventura..."], est)

  Tomar idObj
    | not (estaIluminada est) ->
        (["Está demasiado oscuro para buscar y tomar objetos."], est)
    | not (idObj `elem` objetosEnSala (salaActual est) est) ->
        (["No ves ese objeto aquí."], est)
    | otherwise ->
        let nuevoEst = est {
              inventario = Set.insert idObj (inventario est),
              ubicacionObjs = Map.insert idObj EnInventario (ubicacionObjs est)
            }
            msgBase = ["Has tomado: " ++ unIdObjeto idObj ++ "."]
            msgs = if verificarVictoria nuevoEst
                   then msgBase ++ ["*** ¡Has ganado! ***"]
                   else msgBase
        in (msgs, nuevoEst)

  Soltar idObj
    | not (Set.member idObj (inventario est)) ->
        (["No tienes ese objeto en tu inventario."], est)
    | otherwise ->
        let nuevoEst = est {
              inventario = Set.delete idObj (inventario est),
              ubicacionObjs = Map.insert idObj (EnSala (salaActual est)) (ubicacionObjs est)
            }
        in (["Has dejado " ++ unIdObjeto idObj ++ " en el suelo."], nuevoEst)

  Ir dir -> case obtenerSalaActual est of
    Nothing -> (["Error: la sala actual no existe en el mapa."], est)
    Just sala -> case find (\s -> dirSalida s == dir) (salidasSala sala) of
      Nothing
        | not (estaIluminada est) ->
            (["¡Te golpeas contra una pared en la oscuridad!"], est)
        | otherwise ->
            (["No hay salida hacia el " ++ map toLower (show dir) ++ "."], est)

      Just sal -> case requiereItem sal of
        Nothing ->
          let nuevoEst = est { salaActual = destinoSalida sal }
              msgPenumbra = if not (estaIluminada est)
                            then ["Avanzas a tientas en la más absoluta oscuridad..."]
                            else []
              vista = fst (ejecutar Mirar nuevoEst)
              msgs = if verificarVictoria nuevoEst
                     then msgPenumbra ++ vista ++ ["*** ¡Has ganado! ***"]
                     else msgPenumbra ++ vista
          in (msgs, nuevoEst)

        Just objReq
          | Set.member (salaActual est, dir) (puertasAbiertas est) ->
              let nuevoEst = est { salaActual = destinoSalida sal }
                  msgPenumbra = if not (estaIluminada est)
                                then ["Avanzas a tientas en la más absoluta oscuridad..."]
                                else []
                  vista = fst (ejecutar Mirar nuevoEst)
                  msgs = if verificarVictoria nuevoEst
                         then msgPenumbra ++ vista ++ ["*** ¡Has ganado! ***"]
                         else msgPenumbra ++ vista
              in (msgs, nuevoEst)

          | not (estaIluminada est) ->
              (["¡Te golpeas contra una puerta cerrada en la oscuridad!"], est)

          | not (Set.member objReq (inventario est)) ->
              (["La salida hacia el " ++ map toLower (show dir) ++ " está bloqueada. Necesitas: " ++ unIdObjeto objReq ++ "."], est)

          | otherwise ->
              let nuevoEst = est {
                    salaActual = destinoSalida sal,
                    puertasAbiertas = Set.insert (salaActual est, dir) (puertasAbiertas est)
                  }
                  msgDesbloqueo = ["Usas tu " ++ unIdObjeto objReq ++ " para abrir el camino."]
                  vista = fst (ejecutar Mirar nuevoEst)
                  msgs = if verificarVictoria nuevoEst
                         then msgDesbloqueo ++ vista ++ ["*** ¡Has ganado! ***"]
                         else msgDesbloqueo ++ vista
              in (msgs, nuevoEst)

  Guardar _ -> (["Para guardar tu partida, usa el intérprete principal."], est)
  Cargar _  -> (["Para cargar una partida, usa el intérprete principal."], est)
