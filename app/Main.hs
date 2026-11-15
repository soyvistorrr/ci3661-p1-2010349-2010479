module Main (main) where

import System.Environment (getArgs)
import System.Exit (ExitCode(ExitFailure), exitSuccess, exitWith)
import System.IO (hFlush, stdout)

import Motor.Tipos
import Motor.Mundo (formatearError)
import Motor.Comandos (leerComando)
import Motor.Nucleo (ejecutar, estadoInicial, verificarVictoria)
import Motor.Persistencia (cargarMundoArchivo, cargarPartida, guardarPartida)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["-validar", ruta] -> modoValidar ruta
    ["--validar", ruta] -> modoValidar ruta 
    [ruta]             -> modoJuego ruta
    _                  -> do
      putStrLn "Uso: aventura [--validar | -validar] <archivo-mundo>"
      exitWith (ExitFailure 1)

-- | Modo de validacion estatica del mundo (Seccion 6 del enunciado)
modoValidar :: FilePath -> IO ()
modoValidar path = do
  res <- cargarMundoArchivo path
  case res of
    Left errs -> do
      mapM_ (putStrLn . formatearError) errs
      exitWith (ExitFailure 1)
    Right _ -> do
      putStrLn "Mundo válido."
      exitSuccess

-- | Modo interactivo principal de la aventura
modoJuego :: FilePath -> IO ()
modoJuego path = do
  res <- cargarMundoArchivo path
  case res of
    Left errs -> do
      mapM_ (putStrLn . formatearError) errs
      exitWith (ExitFailure 1)
    Right mundo -> do
      let est0 = estadoInicial mundo
      putStrLn (tituloMundo mundo)
      let (msgs, _) = ejecutar Mirar est0
      mapM_ putStrLn msgs
      if verificarVictoria est0
        then do
          putStrLn "*** ¡Has ganado! ***"
          exitSuccess
        else do
          lineas <- lines <$> getContents
          bucleJuego est0 lineas

-- | Bucle principal de juego con Lazy I/O (ADR-08)
bucleJuego :: Estado -> [String] -> IO ()
bucleJuego est lineas = do
  putStr "> "
  hFlush stdout
  case lineas of
    [] -> exitSuccess
    (l : resto) -> case leerComando l of
      Nothing -> do
        putStrLn "Comando no reconocido. Escribe 'ayuda' para ver las opciones disponibles."
        bucleJuego est resto

      Just Salir -> do
        putStrLn "¡Gracias por jugar! Saliendo de la aventura..."
        exitSuccess

      Just (Guardar rutaG) -> do
        resG <- guardarPartida rutaG est
        case resG of
          Left err -> putStrLn err
          Right () -> putStrLn "Partida guardada."
        bucleJuego est resto

      Just (Cargar rutaC) -> do
        resC <- cargarPartida rutaC (mundoEstatico est)
        case resC of
          Left err -> do
            putStrLn err
            bucleJuego est resto
          Right nuevoEst -> do
            putStrLn "Partida cargada."
            let (msgs, _) = ejecutar Mirar nuevoEst
            mapM_ putStrLn msgs
            if verificarVictoria nuevoEst
              then do
                putStrLn "*** ¡Has ganado! ***"
                exitSuccess
              else bucleJuego nuevoEst resto

      Just cmd -> do
        let (msgs, nuevoEst) = ejecutar cmd est
        mapM_ putStrLn msgs
        if verificarVictoria nuevoEst
          then exitSuccess
          else bucleJuego nuevoEst resto
