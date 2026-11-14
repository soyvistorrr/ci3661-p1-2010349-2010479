module Motor.Tipos (
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
    ErrorMundo(..)
) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

-- | Identificador unico de una sala (newtype para Type Safety)
newtype IdSala = IdSala { unIdSala :: String }
    deriving (Eq, Ord, Show, Read)

-- | Identificador unico de un objeto
newtype IdObjeto = IdObjeto { unIdObjeto :: String }
    deriving (Eq, Ord, Show, Read)

-- | Direcciones cardinales y verticales soportadas
data Direccion = Norte | Sur | Este | Oeste | Arriba | Abajo
    deriving (Eq, Ord, Show, Read, Enum, Bounded)

-- | Conexion saliente desde una sala hacia otra
data Salida = Salida {
    dirSalida       :: Direccion,
    destinoSalida   :: IdSala,
    requiereItem    :: Maybe IdObjeto -- Nothing si abierta, Just item si cerrada
} deriving (Eq, Show, Read)

-- | Sala estatica del mundo
data Sala = Sala {
    idSala          :: IdSala,
    nombreSala      :: String,
    descSala        :: String,
    esOscura        :: Bool,        -- Variante 0: Oscuridad
    salidasSala     :: [Salida],
    objsIniciales   :: [IdObjeto]
} deriving (Eq, Show, Read)

-- | Objeto estatico del mundo
data Objeto = Objeto {
    idObjeto        :: IdObjeto,
    nombreObjeto    :: String,
    descObjeto      :: String,
    emiteLuz        :: Bool         -- Variante 0: LUZ: si / no
} deriving (Eq, Show, Read)

-- | Condicion de victoria
data Meta = LlegarA IdSala
          | LlevarA IdObjeto IdSala
    deriving (Eq, Show, Read)

-- | Estructura fija e inmutable del mundo cargado
data Mundo = Mundo {
    tituloMundo     :: String,
    inicioMundo     :: IdSala,
    metaMundo       :: Meta,
    salasMundo      :: Map.Map IdSala Sala,
    objetosMundo    :: Map.Map IdObjeto Objeto
} deriving (Eq, Show)

-- | Ubicacion dinamica de un objeto durante la partida
data Ubicacion = EnInventario | EnSala IdSala
    deriving (Eq, Ord, Show, Read)

-- | Estado dinamico y ligero (Delta)
data Estado = Estado {
    mundoEstatico   :: Mundo,
    salaActual      :: IdSala,
    inventario      :: Set.Set IdObjeto,
    ubicacionObjs   :: Map.Map IdObjeto Ubicacion,
    puertasAbiertas :: Set.Set (IdSala, Direccion)
} deriving (Show)

-- | Comandos que el jugador puede introducir
data Comando = Ir Direccion
             | Mirar
             | Tomar IdObjeto
             | Soltar IdObjeto
             | Examinar IdObjeto
             | Inventario
             | Guardar FilePath
             | Cargar FilePath
             | Ayuda
             | Salir
    deriving (Eq, Show)

-- | Errores de sintaxis y validacion semantica
data ErrorMundo
    = ErrorSintaxis Int String                         -- V1: linea y detalle
    | IdentificadorDuplicado String                    -- V2: dos salas o dos objetos con el mismo ID
    | SalidaDestinoInexistente IdSala Direccion IdSala -- V3: salida hacia una sala que no existe
    | SalidaObjetoInexistente IdSala Direccion IdObjeto-- V4: salida que requiere un objeto que no existe
    | SalidaDireccionDuplicada IdSala Direccion        -- V5: dos salidas en la misma direccion en una sala
    | ObjetoEnSalaNoDefinido IdSala IdObjeto           -- V6: sala contiene un objeto no definido
    | ObjetoUbicadoMultiplesVeces IdObjeto             -- V7: objeto en mas de una sala o repetido en la misma
    | InicioOMetaInexistente String                    -- V8: INICIO o META con sala u objeto inexistente
    | SalaInalcanzable IdSala                          -- V9: sala no alcanzable desde INICIO
    | ObjetoNecesarioNoColocado IdObjeto               -- V10: objeto necesario no colocado en ninguna sala
    deriving (Eq, Show)