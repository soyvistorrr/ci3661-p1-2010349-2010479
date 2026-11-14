module Motor.Comandos (
    leerComando
) where

import Motor.Tipos (
    -- * Identificadores
    IdObjeto(..),

    -- * Grafo del mundo
    Direccion(..),
    
    -- * Comandos
    Comando(..))

import Data.Char (toLower)

parserDireccion :: String -> Maybe Comando
parserDireccion str = case str of
    "norte"  -> Just (Ir Norte)
    "n"      -> Just (Ir Norte)
    "sur"    -> Just (Ir Sur)
    "s"      -> Just (Ir Sur)
    "este"   -> Just (Ir Este)
    "e"      -> Just (Ir Este)
    "oeste"  -> Just (Ir Oeste)
    "o"      -> Just (Ir Oeste)
    "arriba" -> Just (Ir Arriba)
    "arr"    -> Just (Ir Arriba)
    "abajo"  -> Just (Ir Abajo)
    "ab"     -> Just (Ir Abajo)
    _        -> Nothing

leerComando :: String -> Maybe Comando
leerComando str = case words str of
    [v, ruta] | map toLower v == "guardar" -> Just (Guardar ruta)
              | map toLower v == "cargar"  -> Just (Cargar ruta)

    tokens -> case map (map toLower) tokens of
        ["mirar"]         -> Just Mirar
        ["m"]             -> Just Mirar
        ["inventario"]    -> Just Inventario
        ["inv"]           -> Just Inventario
        ["i"]             -> Just Inventario
        ["ayuda"]         -> Just Ayuda
        ["salir"]         -> Just Salir
        ["ir", dir]       -> parserDireccion dir
        ["tomar", obj]    -> Just (Tomar (IdObjeto obj))
        ["coger", obj]    -> Just (Tomar (IdObjeto obj))
        ["soltar", obj]   -> Just (Soltar (IdObjeto obj))
        ["examinar", obj] -> Just (Examinar (IdObjeto obj))
        [dir]             -> parserDireccion dir
        _                 -> Nothing
