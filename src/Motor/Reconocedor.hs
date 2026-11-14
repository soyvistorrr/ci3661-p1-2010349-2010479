module Motor.Reconocedor (
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
    separadoPor1
) where

import Control.Applicative (Alternative(..))
import Data.Char (isSpace)

-- | Tipo Parser funcional sobre ReadS
newtype Parser a = Parser { runParser :: String -> [(a, String)] }

-- | Ejecuta un parser sobre una cadena. Devuelve Just a si consumio todo con exito
parsear :: Parser a -> String -> Maybe a
parsear p input =
    case [ res | (res, resto) <- runParser p input, all isSpace resto ] of
        (res:_) -> Just res
        []      -> Nothing

instance Functor Parser where
    fmap f (Parser p) = Parser $ \input ->
        [ (f x, resto) | (x, resto) <- p input ]

instance Applicative Parser where
    pure x = Parser $ \input -> [(x, input)]
    (Parser pf) <*> (Parser px) = Parser $ \input ->
        [ (f x, resto2) | (f, resto1) <- pf input, (x, resto2) <- px resto1 ]

instance Monad Parser where
    (Parser p) >>= f = Parser $ \input ->
        concat [ runParser (f x) resto | (x, resto) <- p input ]

instance Alternative Parser where
    empty = Parser $ \_ -> []
    (Parser p1) <|> (Parser p2) = Parser $ \input ->
        case p1 input of
            []  -> p2 input             -- Si p1 falla, prueba con p2
            res -> res                  -- Si p1 tuvo exito, se conserva

-- | Consume un caracter si y solo si cumple la condicion dada
satisfy :: (Char -> Bool) -> Parser Char
satisfy condicion = Parser $ \input ->
    case input of
        (c:cs) | condicion c -> [(c, cs)]
        _               -> []

-- | Con satisfy podemos definir:
-- 1. 'char c': Lee exactamente el caracter c
char :: Char -> Parser Char
char c = satisfy (== c)

-- 2. 'anyChar': Lee cualquier caracter sin importar cual sea
anyChar :: Parser Char
anyChar = satisfy (const True)

-- | Reconoce una cadena de texto exacta
cadena :: String -> Parser String
cadena ""       = pure ""
cadena (c:cs)   = do
    _ <- char c
    _ <- cadena cs 
    return (c:cs)

-- | Reconoce cero o mas ocurrencias del parser p
muchos :: Parser a -> Parser [a]
muchos p = alMenosUno p <|> pure []

-- | Reconoce una o mas ocurrencias del parser p
alMenosUno :: Parser a -> Parser [a]
alMenosUno p = do
    x <- p
    xs <- muchos p
    return (x:xs)

-- | Consume cero o mas espacios blancos consecutivos
espacios :: Parser String
espacios = muchos (satisfy isSpace)

-- | Lee una palabra completa
palabra :: Parser String
palabra = alMenosUno (satisfy (not . isSpace))

-- | Lee todo lo que queda en la liena hasta encontrar un salto de linea '\n'
restoLinea :: Parser String
restoLinea = muchos (satisfy (/= '\n'))

-- | Reconoce elementos separados por un separador (cero o mas)
separadoPor :: Parser a -> Parser sep -> Parser [a]
separadoPor p sep = separadoPor1 p sep <|> pure []

-- | Reconoce elementos separados pro un separados (al menos uno)
separadoPor1 :: Parser a -> Parser sep -> Parser [a]
separadoPor1 p sep = do
    x <- p
    xs <- muchos (sep >> p)
    return (x:xs)