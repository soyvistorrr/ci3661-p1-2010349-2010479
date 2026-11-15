module Motor.Nucleo (
  estadoInicial
--  , ejecutar
--  , estaIluminada
--  , verificarVictoria
) where

import Data.Char (toLower) 
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Data.List (find, intercalate, filter, sortOn)
import Data.Maybe (fromMaybe, mapMaybe, catMaybes, isJust)

import Motor.Tipos (
    -- * Identificadores
    IdSala(..),
    IdObjeto(..),

    -- * Grafo del mundo
    Direccion(..),
    Salida(..),
    Sala(..),
    Objeto(..),
    Meta(..),
    Mundo(..),

    -- * Estado del juego (Delta)
    Ubicacion(..),
    Estado(..),

    -- * Comandos
    Comando(..),

    -- * Errores de validacion
    ErrorMundo(..))

import Motor.Reconocedor (
    -- * Tipo Parser principal
    Parser(..),
    parsear,

    -- * Primitivas elementales
    satisfy,
    char,
    anyChar,
    cadena,

    -- * Combinadores de repeticion y espacios
    muchos,
    alMenosUno,
    espacios,
    palabra,
    restoLinea,

    -- * Combinadores de separacion
    separadoPor,
    separadoPor1)

estadoInicial :: Mundo -> Estado
estadoInicial mundo = Estado mundo (inicioMundo mundo) Set.empty sala Set.empty
  where 
    ubi = Map.elems (salasMundo mundo)
    salas = [(idObj, EnSala (idSala s)) | s <- ubi, idObj <- objsIniciales s]
    sala = Map.fromList salas

obtenerSalaActual :: Estado -> Maybe Sala
obtenerSalaActual est = Map.lookup sala dicc 
  where 
    sala = salaActual est
    dicc = salasMundo (mundoEstatico est)

objetosEnSala :: IdSala -> Estado -> [IdObjeto]
objetosEnSala idBuscada est = Map.keys (Map.filter (== EnSala idBuscada) dicc)
  where
    dicc =  ubicacionObjs est

objetoEmiteLuz :: Estado -> IdObjeto -> Bool
objetoEmiteLuz est idObj = case Map.lookup idObj (objetosMundo (mundoEstatico est)) of
  Just obj -> emiteLuz obj
  Nothing -> False

estaIluminada :: Estado -> Bool
estaIluminada est = case obtenerSalaActual est of
  Nothing -> False
  Just sala -> not (esOscura sala) || objLumInv || objLumSuelo
    where
      objLumInv = any (objetoEmiteLuz est) (Set.toList (inventario est))
      objLumSuelo = any (objetoEmiteLuz est) (objetosEnSala (salaActual est) est)

verificarVictoria :: Estado -> Bool
verificarVictoria est = case metaMundo (mundoEstatico est) of
  LlegarA salaMeta -> salaActual est == salaMeta 
  LlevarA objMeta salaMeta -> salaActual est == salaMeta && Set.member objMeta (inventario est)

{-
ejecutar :: Comando -> Estado -> ([String], Estado)
ejecutar cmd est = case cmd of
  Mirar 
    | not (estaIluminada est) -> (["La sala esta oscura"], est)
    | otherwise -> case obtenerSalaActual est of 
      Nothing -> (["Error: sala no encontrada"], est)
      Just sala -> ([descSala sala, map unIdObjeto (objetosEnSala (salaActual est) est), map (show (dirSalida s)) salidasSala sala], est)
  Examinar ->
  Inventario ->
  Ayuda ->
  Salir ->
-}
