module EvalUpdate exposing (..)
{-
Everything from LangTools that depended on the prelude is in this file now.
Eval.run has become EvalUpdate.run, because it depends on the prelude and on the Update module.
-}
import Update exposing (update)
import UpdateStack exposing (UpdateStack, updateContext, UpdatedExp)
import UpdatedEnv exposing (UpdatedEnv)
import UpdateUtils
import Eval exposing (eval)
import Lang exposing (..)
import HTMLValParser
import LangUtils exposing (..)
import Utils
import Syntax exposing (Syntax)
import ElmParser as Parser
import Results exposing (Results(..), ok1)
import LazyList exposing (LazyList)
import LangTools exposing (..)
import ImpureGoodies
import Set exposing (Set)
import Dict exposing (Dict)
import ValUnparser exposing (strVal_, strOp, strLoc)
import ParserUtils

builtinEnv =
  [ ("error", builtinVal "Eval.error" <| VFun "error" ["msg"] (\args ->
    case args of
      [arg] -> case arg.v_ of
        VBase (VString s) -> Err s
        _ -> Err <| valToString arg
      _ -> Err <| "error requires 1 argument, was given " ++ toString (List.length args)
    ) Nothing)
  , ("parseHTML", HTMLValParser.htmlValParser)
   -- TODO: This && evaluates both sides, can we have something that does less?
  , ("&&", builtinVal "Eval.&&" <| VFun "&&" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case left.v_ of
           VBase (VBool True) -> Ok (right, [])
           VBase (VBool False) -> Ok (left, [])
           _ -> Err <| "&& expects two booleans, got " ++ valToString left
       _ -> Err <| "&& expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , ("||", builtinVal "Eval.||" <| VFun "||" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case left.v_ of
           VBase (VBool True) -> Ok (left, [])
           VBase (VBool False) -> Ok (right, [])
           _ -> Err <| "|| expects two booleans, got " ++ valToString left
       _ -> Err <| "|| expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , ("<=", builtinVal "Eval.<=" <| VFun "<=" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case (left.v_, right.v_) of
           (VConst _ (n1, _), VConst _ (n2, _))  -> Ok (replaceV_ left <| VBase (VBool (n1 <= n2)), [])
           _ -> Err <| "<= expects two numbers, got " ++ valToString left ++ " and " ++ valToString right
       _ -> Err <| "<= expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , (">=", builtinVal "Eval.>=" <| VFun ">=" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case (left.v_, right.v_) of
           (VConst _ (n1, _), VConst _ (n2, _))  -> Ok (replaceV_ left <| VBase (VBool (n1 >= n2)), [])
           _ -> Err <| ">= expects two numbers, got " ++ valToString left ++ " and " ++ valToString right
       _ -> Err <| ">= expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , (">", builtinVal "Eval.>" <| VFun ">" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case (left.v_, right.v_) of
           (VConst _ (n1, _), VConst _ (n2, _))  -> Ok (replaceV_ left <| VBase (VBool (n1 > n2)), [])
           _ -> Err <| "> expects two numbers, got " ++ valToString left ++ " and " ++ valToString right
       _ -> Err <| "> expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , ("/=", builtinVal "Eval./=" <| VFun "/=" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case (left.v_, right.v_) of
           (VConst _ (n1, _), VConst _ (n2, _))  -> Ok (replaceV_ left <| VBase (VBool (n1 /= n2)), [])
           _ -> Err <| "/= expects two numbers, got " ++ valToString left ++ " and " ++ valToString right
       _ -> Err <| "/= expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , ("%", builtinVal "Eval.%" <| VFun "%" ["left", "right"] (\args ->
     case args of
       [left, right] ->
         case (left.v_, right.v_) of
           (VConst x (n1, y), VConst _ (n2, _))  ->
             if n2 == 0 then
               Err "Modulo by zero"
             else
               Ok (replaceV_ left <| VConst x (toFloat (truncate n1 % truncate n2), y), [])
           _ -> Err <| "% expects two numbers, got " ++ valToString left ++ " and " ++ valToString right
       _ -> Err <| "% expects 2 arguments, got " ++ (toString <| List.length args)
     ) Nothing)
  , ("evaluate", builtinVal "Eval.evaluate" <| VFun "evaluate" ["program"] (\args ->
      case args of
        [program] -> case program.v_ of
          VBase (VString s) ->
            Syntax.parser Syntax.Elm s
            |> Result.mapError (ParserUtils.showError)
            |> Result.andThen (\prog ->
                Eval.doEval Syntax.Elm builtinEnv prog
              )
            |> Result.map Tuple.first
          _ -> Err <| "evaluate expects one string, got " ++ LangUtils.valToString  program
        _ -> Err <| "evaluate expects 1 arguments, got " ++ (toString <| List.length args)
    ) (Just <| \args oldVal newVal ->
      case args of
        [oldProgram] ->
          case oldProgram.v_ of
            VBase (VString s) ->
              let res: Results String (List Val)
                  res=
                   Syntax.parser Syntax.Elm s
                |> Result.mapError (ParserUtils.showError)
                |> Results.fromResult
                |> Results.andThen (\prog ->
                    -- update = UpdateStack -> LazyList NextAction -> Results (UpdatedEnv, UpdatedExp)
                    UpdateUtils.defaultVDiffs oldVal newVal
                    |> Results.fromResult
                    |> Results.andThen (\mbDiff ->
                      case mbDiff of
                        Nothing -> ok1 [oldProgram]
                        Just d -> -- Hack to avoid mutual recursion.
                             Update.update (UpdateStack.updateContext "Eval.update" builtinEnv prog oldVal newVal d) LazyList.Nil
                          |> Results.map Tuple.second
                          |> Results.map .val
                          |> Results.map (Syntax.unparser Syntax.Elm)
                          |> Results.map (\x -> [replaceV_ oldProgram <| VBase <| VString x])
                    )
                )
              in
              res
            _ -> Errs <| "evaluate expects one string, got " ++ LangUtils.valToString oldProgram
        _ -> Errs <| "evaluate expects 1 arguments, got " ++ (toString <| List.length args)
    ))
  ]

preludeEnvRes = Result.map Tuple.second <| (eval Syntax.Little builtinEnv [] Parser.prelude)
preludeEnv = Utils.fromOk "Eval.preludeEnv" <| preludeEnvRes

run : Syntax -> Exp -> Result String (Val, Widgets)
run syntax e =
-- doEval syntax initEnv e |> Result.map Tuple.first
  ImpureGoodies.logTimedRun "Eval.run" (\() ->
    Eval.doEval syntax preludeEnv e |> Result.map Tuple.first
  )

doUpdate : Exp -> Val -> Result String Val -> Results String (UpdatedEnv, UpdatedExp)
doUpdate oldExp oldVal newValResult =
  newValResult
    --|> Result.map (\x -> let _ = Debug.log "#1" () in x)
    |> Results.fromResult
    |> Results.andThen (\out ->
      case ImpureGoodies.logTimedRun "UpdateUtils.defaultVDiffs (doUpdate) " <| \_ -> UpdateUtils.defaultVDiffs oldVal out of
        Err msg -> Errs msg
        Ok Nothing -> ok1 (UpdatedEnv.original preludeEnv, UpdatedExp oldExp Nothing)
        Ok (Just diffs) ->
          ImpureGoodies.logTimedRun "Update.update (doUpdate) " <| \_ ->
          update (updateContext "initial update" preludeEnv oldExp oldVal out diffs) LazyList.Nil)

-- Deprecated
parseAndRun : String -> String
parseAndRun = valToString << Tuple.first << Utils.fromOk_ << run Syntax.Little << Utils.fromOkay "parseAndRun" << Parser.parse

parseAndRun_ = strVal_ True << Tuple.first << Utils.fromOk_ << run Syntax.Little << Utils.fromOkay "parseAndRun_" << Parser.parse

preludeIdentifiers = preludeEnv |> List.map Tuple.first |> Set.fromList

identifiersSetPlusPrelude : Exp -> Set.Set Ident
identifiersSetPlusPrelude exp =
  Set.union (identifiersSet exp) preludeIdentifiers


assignUniqueNames : Exp -> (Exp, Dict Ident Ident)
assignUniqueNames program =
  let initialUsedNames =
    -- Want to rename _everything_ so that there's multiple options for how to rename back to the originals
    identifiersSetPlusPrelude program
  in
  let (newProgram, usedNames, newNameToOldName) =
    assignUniqueNames_ program initialUsedNames Dict.empty
  in
  (newProgram, newNameToOldName)


assignUniqueNames_ : Exp -> Set.Set Ident -> Dict Ident Ident -> (Exp, Set.Set Ident, Dict Ident Ident)
assignUniqueNames_ exp usedNames oldNameToNewName =
  let recurse = assignUniqueNames_ in
  let recurseExps es =
    es
    |> List.foldl
        (\e (newEs, usedNames, newNameToOldName) ->
          let (newE, usedNames_, newNameToOldName_) = recurse e usedNames oldNameToNewName in
          (newEs ++ [newE], usedNames_, Dict.union newNameToOldName_ newNameToOldName)
        )
        ([], usedNames, Dict.empty)
  in
  let recurseExp e =
    let (newEs, usedNames, newNameToOldName) = recurseExps [e] in
    (Utils.head "assignUniqueNames_ head1" newEs, usedNames, newNameToOldName)
  in
  let assignUniqueNamesToPat_ pat usedNames =
    identifiersListInPat pat
    |> List.foldl
        (\name (pat, usedNames, oldNameToNewName) ->
          if Set.member name usedNames then
            let newName = nonCollidingName name 2 usedNames in
            (renameIdentifierInPat name newName pat, Set.insert newName usedNames, Dict.insert name newName oldNameToNewName)
          else
            (pat, Set.insert name usedNames, oldNameToNewName)
        )
        (pat, usedNames, Dict.empty)
  in
  let leafUnchanged = (exp, usedNames, Dict.empty) in
  case exp.val.e__ of
    EConst _ _ _ _  -> leafUnchanged
    EBase _ _       -> leafUnchanged
    EVar ws oldName ->
      case Dict.get oldName oldNameToNewName of
        Just newName  -> (replaceE__ exp (EVar ws newName), usedNames, Dict.empty)
        Nothing       -> leafUnchanged

    EFun ws1 ps e ws2 ->
      let (newPs, usedNames_, oldNameToNewNameAdditions) =
        ps
        |> List.foldl
            (\p (newPs, usedNames, oldNameToNewNameAdditions) ->
              let (newPat, usedNames_, oldNameToNewNameAdditions_) = assignUniqueNamesToPat_ p usedNames in
              (newPs ++ [newPat], usedNames_, Dict.union oldNameToNewNameAdditions_ oldNameToNewNameAdditions)
            )
            ([], usedNames, Dict.empty)
      in
      let (newBody, usedNames__, newNameToOldName) = recurse e usedNames_ (Dict.union oldNameToNewNameAdditions oldNameToNewName) in
      let newNameToOldName_ = Dict.union (Utils.flipDict oldNameToNewNameAdditions) newNameToOldName in
      ( replaceE__ exp (EFun ws1 newPs newBody ws2)
      , usedNames__
      , newNameToOldName_
      )

    EOp ws1 op es ws2 ->
      let (newEs, usedNames_, newNameToOldName) = recurseExps es in
      ( replaceE__ exp (EOp ws1 op newEs ws2)
      , usedNames_
      , newNameToOldName
      )

    EList ws1 es ws2 Nothing ws3 ->
      let (newEs, usedNames_, newNameToOldName) = recurseExps (Utils.listValues es) in
      ( replaceE__ exp (EList ws1 (Utils.listValuesMake es newEs) ws2 Nothing ws3)
      , usedNames_
      , newNameToOldName
      )

    EList ws1 es ws2 (Just tail) ws3 ->
      let (newEs, usedNames_, newNameToOldName) = recurseExps (Utils.listValues es ++ [tail]) in
      let (newHeads, newTail) = (Utils.removeLastElement newEs, Utils.last "assignUniqueNames_" newEs) in
      ( replaceE__ exp (EList ws1 (Utils.listValuesMake es newHeads) ws2 (Just newTail) ws3)
      , usedNames_
      , newNameToOldName
      )

    ERecord ws1 Nothing es ws2 ->
      let (newEs, usedNames_, newNameToOldName) = recurseExps (Utils.recordValues es) in
      ( replaceE__ exp (ERecord ws1 Nothing (Utils.recordValuesMake es newEs) ws2)
      , usedNames_
      , newNameToOldName
      )

    ERecord ws1 (Just (init, wsi)) es ws2 ->
      let (newEs, usedNames_, newNameToOldName) = recurseExps (Utils.recordValues es ++ [init]) in
      let (newFields, newInit) = (Utils.removeLastElement newEs, Utils.last "assignUniqueNames_" newEs) in
      ( replaceE__ exp (ERecord ws1 (Just (newInit, wsi)) (Utils.recordValuesMake es newFields) ws2)
      , usedNames_
      , newNameToOldName
      )

    ESelect ws0 e1 ws1 ws2 s ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
       ( replaceE__ exp (ESelect ws0 newE1 ws1 ws2 s)
       , usedNames_
       , newNameToOldName
       )

    EIf ws1 e1 ws2 e2 ws3 e3 ws4 ->
      let (newEs, usedNames_, newNameToOldName) = recurseExps [e1, e2, e3] in
      case newEs of
        [newE1, newE2, newE3] ->
          ( replaceE__ exp (EIf ws1 newE1 ws2 newE2 ws3 newE3 ws4)
          , usedNames_
          , newNameToOldName
          )

        _ ->
          Debug.crash "assignUniqueNames_ EIf"

    ECase ws1 e1 bs ws2 ->
      let (newScrutinee, usedNames_, newNameToOldName) = recurse e1 usedNames oldNameToNewName in
      let (newBranches, usedNames__, newNameToOldName_) =
        bs
        |> List.foldl
            (\branch (newBranches, usedNames, newNameToOldName) ->
              let (Branch_ bws1 bPat bExp bws2) = branch.val in
              let (newPat, usedNames_, oldNameToNewNameAdditions) = assignUniqueNamesToPat_ bPat usedNames in
              let (newBody, usedNames__, newNameToOldName_) = recurse bExp usedNames_ (Dict.union oldNameToNewNameAdditions oldNameToNewName) in
              let newBranch = { branch | val = Branch_ bws1 newPat newBody bws2 } in
              (newBranches ++ [newBranch], usedNames__, Dict.union (Utils.flipDict oldNameToNewNameAdditions) (Dict.union newNameToOldName_ newNameToOldName))
            )
            ([], usedNames_, newNameToOldName)
      in
      ( replaceE__ exp (ECase ws1 newScrutinee newBranches ws2)
      , usedNames__
      , newNameToOldName_
      )

    ETypeCase ws1 e1 tbs ws2 ->
      let (newScrutinee, usedNames_, newNameToOldName) = recurse e1 usedNames oldNameToNewName in
      let (newTBranches, usedNames__, newNameToOldName_) =
        tbs
        |> List.foldl
            (\tbranch (newTBranches, usedNames, newNameToOldName) ->
              let (TBranch_ bws1 bType bExp bws2) = tbranch.val in
              let (newBody, usedNames_, newNameToOldName_) = recurse bExp usedNames oldNameToNewName in
              let newTBranch = { tbranch | val = TBranch_ bws1 bType newBody bws2 } in
              (newTBranches ++ [newTBranch], usedNames_, Dict.union newNameToOldName_ newNameToOldName)
            )
            ([], usedNames_, newNameToOldName)
      in
      ( replaceE__ exp (ETypeCase ws1 newScrutinee newTBranches ws2)
      , usedNames__
      , newNameToOldName_
      )

    EApp ws1 e1 es appType ws2 ->
      let (newE1AndEs, usedNames_, newNameToOldName) = recurseExps (e1::es) in
      let (newE1, newEs) = (Utils.head "assignUniqueNames_ head" newE1AndEs, Utils.tail "assignUniqueNames_ tail" newE1AndEs) in
      ( replaceE__ exp (EApp ws1 newE1 newEs appType ws2)
      , usedNames_
      , newNameToOldName
      )

    ELet ws1 kind isRec p ws2 e1 ws3 e2 ws4 ->
      let (newPat, usedNames_, oldNameToNewNameAdditions) = assignUniqueNamesToPat_ p usedNames in
      let oldNameToNewNameWithAdditions = Dict.union oldNameToNewNameAdditions oldNameToNewName in
      let oldNameToNewNameForBoundExp =
        if isRec then
          oldNameToNewNameWithAdditions
        else
          oldNameToNewName
      in
      let (newE1, usedNames__, newNameToOldName)   = recurse e1 usedNames_ oldNameToNewNameForBoundExp in
      let (newE2, usedNames___, newNameToOldName_) = recurse e2 usedNames__ oldNameToNewNameWithAdditions in
      let newNameToOldName__ = Dict.union (Utils.flipDict oldNameToNewNameAdditions) (Dict.union newNameToOldName_ newNameToOldName) in
      ( replaceE__ exp (ELet ws1 kind isRec newPat ws2 newE1 ws3 newE2 ws4)
      , usedNames___
      , newNameToOldName__
      )

    EComment ws s e1 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (EComment ws s newE1)
      , usedNames_
      , newNameToOldName
      )

    EOption ws1 s1 ws2 s2 e1 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (EOption ws1 s1 ws2 s2 newE1)
      , usedNames_
      , newNameToOldName
      )

    ETyp ws1 pat tipe e1 ws2 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (ETyp ws1 pat tipe newE1 ws2)
      , usedNames_
      , newNameToOldName
      )

    EColonType ws1 e1 ws2 tipe ws3 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (EColonType ws1 newE1 ws2 tipe ws3)
      , usedNames_
      , newNameToOldName
      )

    ETypeAlias ws1 pat tipe e1 ws2 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (ETypeAlias ws1 pat tipe newE1 ws2)
      , usedNames_
      , newNameToOldName
      )

    ETypeDef ws1 ident vars ws2 dcs e1 ws3 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (ETypeDef ws1 ident vars ws2 dcs newE1 ws3)
      , usedNames_
      , newNameToOldName
      )

    EParens ws1 e1 pStyle ws2 ->
      let (newE1, usedNames_, newNameToOldName) = recurseExp e1 in
      ( replaceE__ exp (EParens ws1 newE1 pStyle ws2)
      , usedNames_
      , newNameToOldName
      )

    EHole _ _ -> leafUnchanged


-- What variable names are in use at any of the given locations?
-- For help finding unused names during synthesis.
visibleIdentifiersAtEIds : Exp -> Set.Set EId -> Set.Set Ident
visibleIdentifiersAtEIds program eids =
  let programIdents = visibleIdentifiersAtPredicateNoPrelude program (\exp -> Set.member exp.val.eid eids) in
  Set.union programIdents preludeIdentifiers


newVariableVisibleTo : EId -> Ident -> Int -> Exp -> List EId -> Exp -> (Ident, Exp)
newVariableVisibleTo insertedLetEId suggestedName startingNumberForNonCollidingName boundExp observerEIds program =
  let
    newName =
      nonCollidingName suggestedName startingNumberForNonCollidingName (visibleIdentifiersAtEIds program (Set.fromList observerEIds))
    eidToWrap =
      deepestCommonAncestorWithNewline program (\exp -> List.member exp.val.eid observerEIds) |> .val |> .eid
    newProgram =
      program
      |> mapExpNode
          eidToWrap
          (\expToWrap ->
            newLetFancyWhitespace insertedLetEId False (pVar newName) boundExp expToWrap program
          )
  in
  (newName, newProgram)


identifiersVisibleAtProgramEnd : Exp -> Set.Set Ident
identifiersVisibleAtProgramEnd program =
  let lastEId = (lastExp program).val.eid in
  visibleIdentifiersAtEIds program (Set.singleton lastEId)

-- External API
evaluate: String -> Result String Val
evaluate s =
  Syntax.parser Syntax.Elm s
  |> Result.mapError ParserUtils.showError
  |> Result.andThen (\exp ->
    run Syntax.Elm exp
  ) |> Result.map Tuple.first

valToString: Val -> String
valToString v = LangUtils.valToString v