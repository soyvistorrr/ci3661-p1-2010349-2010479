module Motor.Persistencia (
    -- * Tipo serializable de partida
    EstadoGuardado(..),

    -- * Carga de mundos y persistencia de partidas
    cargarMundoArchivo,
    guardarPartida,
    cargarPartida
) where

import System.Directory (doesFileExist)
import Text.Read (readMaybe)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Motor.Tipos
import Motor.Mundo (leerMundo)

-- | Representacion serializable del estado dinamico (Deltas del jugador)
-- No incluye 'Mundo' para evitar duplicacion de datos inmutables y permitir
-- derivar 'Read' de forma segura y portable.
data EstadoGuardado = EstadoGuardado {
    egSalaActual      :: IdSala,
    egInventario      :: Set.Set IdObjeto,
    egUbicacionObjs   :: Map.Map IdObjeto Ubicacion,
    egPuertasAbiertas :: Set.Set (IdSala, Direccion)
} deriving (Eq, Show, Read)

-- | Lee un archivo de mundo desde disco y lo valida sintactica y semanticamente
cargarMundoArchivo :: FilePath -> IO (Either [ErrorMundo] Mundo)
cargarMundoArchivo path = do
  existe <- doesFileExist path
  if not existe
    then return (Left [ErrorSintaxis 0 ("El archivo no existe: " ++ path)])
    else do
      contenido <- readFile path
      return (leerMundo contenido)

-- | Guarda el estado actual de la partida serializando el delta en disco
guardarPartida :: FilePath -> Estado -> IO (Either String ())
guardarPartida path est = do
  let eg = EstadoGuardado
        { egSalaActual      = salaActual est
        , egInventario      = inventario est
        , egUbicacionObjs   = ubicacionObjs est
        , egPuertasAbiertas = puertasAbiertas est
        }
  writeFile path (show eg)
  return (Right ())

-- | Carga y valida de forma segura una partida guardada contra el mundo activo
cargarPartida :: FilePath -> Mundo -> IO (Either String Estado)
cargarPartida path mundo = do
  existe <- doesFileExist path
  if not existe
    then return (Left "Error: El archivo de guardado no existe.")
    else do
      contenido <- readFile path
      case (readMaybe contenido :: Maybe EstadoGuardado) of
        Nothing -> return (Left "Error: El archivo de guardado está corrupto o tiene formato inválido.")
        Just eg
          | esConsistente eg -> return (Right (construirEstado eg))
          | otherwise        -> return (Left "Error: La partida guardada corresponde a otro mundo o estructura incompatible.")
  where
    esConsistente eg =
      Map.member (egSalaActual eg) (salasMundo mundo)
        && all (\oId -> Map.member oId (objetosMundo mundo)) (Set.toList (egInventario eg))
        && all (\oId -> Map.member oId (objetosMundo mundo)) (Map.keys (egUbicacionObjs eg))

    construirEstado eg = Estado
      { mundoEstatico   = mundo
      , salaActual      = egSalaActual eg
      , inventario      = egInventario eg
      , ubicacionObjs   = egUbicacionObjs eg
      , puertasAbiertas = egPuertasAbiertas eg
      }
