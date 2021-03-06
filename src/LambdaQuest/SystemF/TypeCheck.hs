module LambdaQuest.SystemF.TypeCheck where
import LambdaQuest.SystemF.Type
import LambdaQuest.Common.Type

-- replaces occurrences of TyRef j (j >= i) with TyRef (j + delta)
typeShift :: Int -> Int -> TypeT a -> TypeT a
typeShift delta i t = case t of
  TyPrim _ -> t
  TyArr u v -> TyArr (typeShift delta i u) (typeShift delta (i + 1) v)
  TyRef j name | j >= i, j + delta >= 0 -> TyRef (j + delta) name
               | j >= i, j + delta < 0 -> error "typeShift: negative index"
               | otherwise -> t
  TyAll n t -> TyAll n (typeShift delta (i + 1) t)
  TyExtra _ -> t
-- typeShift 0 i t == t

typeSubstD :: Int -> TypeT a -> Int -> TypeT a -> TypeT a
typeSubstD depth s i t = case t of
  TyPrim _ -> t
  TyArr u v -> TyArr (typeSubstD depth s i u) (typeSubstD (depth + 1) s (i + 1) v)
  TyRef j name | j == i -> typeShift depth 0 s
               | j > i -> TyRef (j - 1) name
               | otherwise -> t
  TyAll n t -> TyAll n (typeSubstD (depth + 1) s (i + 1) t)
  TyExtra _ -> t

-- replaces occurrences of TyRef j (j > i) with TyRef (j-1), and TyRef i with the given type
typeSubst = typeSubstD 0

primTypeOf :: PrimValue -> TypeT a
primTypeOf = genPrimTypeOf TyPrim TyArr

typeOf :: [Binding] -> Term -> Either String Type
typeOf ctx tm = case tm of
  TPrimValue primValue -> return (primTypeOf primValue)
  TAbs name argType body -> TyArr argType <$> typeOf (VarBind name argType : ctx) body
  TTyAbs name body -> TyAll name <$> typeOf (TyVarBind name : ctx) body
  TRef i name -> return $ typeShift (i + 1) 0 $ getTypeFromContext ctx i
  TApp f x -> do
    fnType <- typeOf ctx f
    actualArgType <- typeOf ctx x
    case fnType of
      TyArr expectedArgType retType | actualArgType == expectedArgType -> return $ typeShift (-1) 0 retType
                                    | otherwise -> Left ("type error (expected: " ++ show expectedArgType ++ ", got: " ++ show actualArgType ++ ")")
      _ -> Left ("invalid function application (expected function type, got: " ++ show fnType ++ ")")
  TTyApp f t -> do
    fnType <- typeOf ctx f
    case fnType of
      TyAll _name bodyType -> return (typeSubst t 0 bodyType)
      _ -> Left ("invalid type application (expected forall type, got: " ++ show fnType ++ ")")
  TLet name def body -> do
    definedType <- typeOf ctx def
    typeOf (VarBind name definedType : ctx) body
  TIf cond then_ else_ -> do
    condType <- typeOf ctx cond
    thenType <- typeOf ctx then_
    elseType <- typeOf ctx else_
    case condType of
      TyBool | thenType == elseType -> return thenType
             | otherwise -> Left "if-then-else: type mismatch"
      _ -> Left "if-then-else: conditon must be boolean"
