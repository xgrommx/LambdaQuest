{-# LANGUAGE PatternSynonyms #-}
module LambdaQuest.SystemFsub.Type
  (Type(..,TyInt,TyReal,TyBool,TyUnit)
  ,Term(..)
  ,Binding(..)
  ,isValue
  ,getTypeFromContext
  ,getBoundFromContext
  ,typeShift
  ,typeSubstD
  ,typeSubst
  ,module LambdaQuest.Common.Type
  ) where
import LambdaQuest.Common.Type hiding (genPrimTypeOf)

data Type = TyPrim !PrimType
          | TyArr Type Type
          | TyRef !Int String       -- type variable (de Bruijn index)
          | TyAll String Type Type  -- bounded type abstraction (forall)
          | TyTop
          deriving (Show)

pattern TyInt = TyPrim PTyInt
pattern TyReal = TyPrim PTyReal
pattern TyBool = TyPrim PTyBool
pattern TyUnit = TyPrim PTyUnit

data Term = TPrimValue !PrimValue   -- primitive value
          | TAbs String Type Term   -- lambda abstraction
          | TTyAbs String Type Term -- bounded type abstraction
          | TRef !Int String        -- variable (de Bruijn index)
          | TApp Term Term          -- function application
          | TTyApp Term Type        -- type application
          | TLet String Term Term   -- let-in
          | TIf Term Term Term      -- if-then-else
          | TCoerce Term Type       -- type coercion
          deriving (Show)

data Binding = VarBind String Type   -- variable binding (name, type)
             | TyVarBind String Type -- type variable binding (name, upper bound)
             | AnonymousBind         -- placeholder for function type
             deriving (Eq,Show)

isValue :: Term -> Bool
isValue t = case t of
  TPrimValue _ -> True
  TAbs _ _ _ -> True
  TTyAbs _ _ _ -> True
  TApp (TPrimValue (PVBuiltinBinary _)) x -> isValue x -- partial application
  _ -> False

instance Eq Type where
  TyPrim p    == TyPrim p'     = p == p'
  TyArr s t   == TyArr s' t'   = s == s' && t == t'
  TyRef i _   == TyRef i' _    = i == i'
  TyAll _ b t == TyAll _ b' t' = b == b' && t == t' -- ignore type variable name
  TyTop       == TyTop         = True
  _           == _             = False

instance Eq Term where
  TPrimValue p == TPrimValue p'  = p == p'
  TAbs _ t x   == TAbs _ t' x'   = t == t' && x == x' -- ignore variable name
  TTyAbs _ b x == TTyAbs _ b' x' = x == x'            -- ignore type variable name
  TRef i _     == TRef i' _      = i == i'
  TApp s t     == TApp s' t'     = s == s' && t == t'
  TTyApp s t   == TTyApp s' t'   = s == s' && t == t'
  TLet _ s t   == TLet _ s' t'   = s == s' && t == t'
  TIf s t u    == TIf s' t' u'   = s == s' && t == t' && u == u'
  TCoerce x t  == TCoerce x' t'  = x == x' && t == t'
  _            == _              = False

-- replaces occurrences of TyRef j (j >= i) with TyRef (j + delta)
typeShift :: Int -> Int -> Type -> Type
typeShift delta i t = case t of
  TyPrim _ -> t
  TyTop -> t
  TyArr u v -> TyArr (typeShift delta i u) (typeShift delta (i + 1) v)
  TyRef j name | j >= i, j + delta >= 0 -> TyRef (j + delta) name
               | j >= i, j + delta < 0 -> error "typeShift: negative index"
               | otherwise -> t
  TyAll n b t -> TyAll n (typeShift delta i b) (typeShift delta (i + 1) t)
-- typeShift 0 i t == t
-- typeShift d1 i (typeShift d0 i t) == typeShift (d1 + d0) i t

typeSubstD :: Int -> Type -> Int -> Type -> Type
typeSubstD depth s i t = case t of
  TyPrim _ -> t
  TyTop -> t
  TyArr u v -> TyArr (typeSubstD depth s i u) (typeSubstD (depth + 1) s (i + 1) v)
  TyRef j name | j == i -> typeShift depth 0 s
               | j > i -> TyRef (j - 1) name
               | otherwise -> t
  TyAll n b t -> TyAll n (typeSubstD depth s i b) (typeSubstD (depth + 1) s (i + 1) t)

-- replaces occurrences of TyRef j (j > i) with TyRef (j-1), and TyRef i with the given type
typeSubst = typeSubstD 0

getTypeFromContext :: [Binding] -> Int -> Type
getTypeFromContext ctx i
  | i < length ctx = case ctx !! i of
                       VarBind _ t -> t
                       b -> error ("TRef: expected a variable binding, found " ++ show b)
  | otherwise = error "TRef: index out of bounds"

getBoundFromContext :: [Binding] -> Int -> Type
getBoundFromContext ctx i
  | i < length ctx = case ctx !! i of
                       TyVarBind _ b -> b
                       b -> error ("TyRef: expected a type variable binding, found " ++ show b)
  | otherwise = error "TyRef: index out of bounds"

