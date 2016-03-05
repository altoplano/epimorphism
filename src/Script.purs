module Script where

import Prelude
import Data.Array (index, length, elemIndex, foldM, updateAt) as A
import Data.Complex
import Data.Either (Either(..))
import Data.Foldable (or)
import Data.Maybe
import Data.StrMap (StrMap, keys, lookup, insert, fromFoldable, union, member, delete)
import Data.String (trim)
import Data.Tuple (Tuple(..))
import Data.Traversable (traverse)
import Control.Monad (unless)
import Control.Monad.ST
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except.Trans (lift)

import Config
import System (loadLib)
import Util (lg, tLg, numFromStringE, intFromStringE, gmod, rndstr)
import Pattern (purgeScript, replaceModule, importScript)

-- PUBLIC

-- execute all scripts & script pool
runScripts :: forall eff h. STRef h (SystemST h) -> Number -> EpiS eff h Boolean
runScripts ssRef t = do
  systemST <- lift $ readSTRef ssRef
  res <- traverse (handle ssRef t) (keys systemST.scriptRefPool)
  return $ or res
  where
    handle :: forall eff h. STRef h (SystemST h) -> Number -> String -> EpiS eff h Boolean
    handle ssRef t n = do
      systemST <- lift $ readSTRef ssRef
      case (member n systemST.scriptRefPool) of
        true -> do
          sRef <- loadLib n systemST.scriptRefPool "runScripts"
          scr <- lift $ readSTRef sRef
          fn <- lookupScriptFN scr.fn
          case scr.mid of
            Nothing -> throwError $ "No module when running script: " ++ scr.fn
            Just mid -> fn ssRef n t mid sRef
        false -> do
          let g = lg "script removed" -- ghetto
          return false

-- SCRIPT FUNCTIONS

-- dont do anything.  is this necessary?
nullS :: forall eff h. ScriptFn eff h
nullS ssRef self t mid sRef = do
  return false


-- move par[par] around on a path
ppath :: forall eff h. ScriptFn eff h
ppath ssRef self t mid sRef = do
  systemST <- lift $ readSTRef ssRef
  scr <- lift $ readSTRef sRef
  let dt = scr.dt

  -- get data
  spd <- (loadLib "spd" dt "ppath spd") >>= numFromStringE
  par <-  loadLib "par" dt "ppath par"
  phs <- (loadLib "phase" dt "ppath phase") >>= numFromStringE
  pathN <- loadLib "path" dt "ppath path"
  mRef <- loadLib mid systemST.moduleRefPool "ppath module"
  m <- lift $ readSTRef mRef

  -- lookup path function
  fn <- case pathN of
    "linear" -> return $ \t -> t
    _ -> throwError $ "Unknown par path : " ++ pathN

  -- execute
--  let g = lg (t - phs)
  let val = fn ((t - phs) * spd)

  -- modify data
  let par' = insert par val m.par
  lift $ modifySTRef mRef (\m -> m {par = par'})

  return false


-- move zn[idx] around on a path
zpath :: forall eff h. ScriptFn eff h
zpath ssRef self t mid sRef = do
  systemST <- lift $ readSTRef ssRef
  scr <- lift $ readSTRef sRef
  let dt = scr.dt

  -- get data
  spd <- (loadLib "spd" dt "zpath spd") >>= numFromStringE
  idx <- (loadLib "idx" dt "zpath idx") >>= intFromStringE
  pathN <- loadLib "path" dt "zpath path"
  mRef <- loadLib mid systemST.moduleRefPool "zpath module"
  m <- lift $ readSTRef mRef

  -- lookup path function
  fn <- case pathN of
    "rlin" -> return $ \t ->
      outCartesian $ Cartesian t 0.0
    "circle" -> return $ \t ->
      outPolar $ Polar t 1.0
    _ -> throwError $ "Unknown z path : " ++ pathN

  -- execute
  let z' = fn (t * spd)

  -- modify data
  case (A.updateAt idx z' m.zn) of
    (Just zn') -> lift $ modifySTRef mRef (\m -> m {zn = zn'})
    _ -> throwError $ "zn idx out of bound : " ++ (show idx) ++ " : in zpath"

  return false




-- interpolate between two modules
blendModule :: forall eff h. ScriptFn eff h
blendModule ssRef self t mid sRef = do

    -- do thing
--  let sub' = insert subN nxtVal m.sub
  --lift $ modifySTRef mRef (\m -> m {sub = sub'})

  return false


-- PRIVATE

-- find script fuction given name
lookupScriptFN :: forall eff h. String -> EpiS eff h (ScriptFn eff h)
lookupScriptFN n = case n of
  "null"  -> return nullS
  "ppath" -> return ppath
  "zpath" -> return zpath
--  "incIdx" -> return incIdx
-- "blendSub" -> return blendSub
  "blendModule" -> return blendModule
  _       -> throwError $ "script function not found: " ++ n


-- create a script dynamically
createScript :: forall eff h. STRef h (SystemST h) -> String -> String -> String -> StrMap String -> EpiS eff h String
createScript ssRef mid parent fn dt = do
  systemST <- lift $ readSTRef ssRef
  scr <- loadLib parent systemST.scriptLib "create script"

  let scr' = scr {fn = fn, dt = union dt scr.dt}
  importScript ssRef (Left scr') mid
