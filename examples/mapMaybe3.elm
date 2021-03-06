applyFstToSnd [f,x] = f x

applyLens lens x = lens.apply x

mapMaybe default f mx =
  let lens = {
    apply [f, mx] =
      case mx of
        []  -> []
        [x] -> [f x]

    update {input = [f, mx], output} =
      case output of
        []  -> Ok (Inputs [[f, []]])
        [y] ->
          let x = case mx of [x] -> x; [] -> default in
          case Update.updateApp {fun = applyFstToSnd, input = [f, x], output = y} of
            Ok (InputsWithDiffs vds) ->
              Ok (InputsWithDiffs (
                List.map (\([f, newX], d) ->
                  ([f, [newX]],
                  case d of
                     Nothing -> Nothing
                     Just (VListDiffs funxdiffs) ->
                       Just (VListDiffs (funxdiffs |>
                         map (case of
                           [0, funDiff] -> [0, funDiff]
                           [  1, ListElemUpdate xDiff] ->
                             [1, ListElemUpdate (VListDiffs [[0,
                               case mx of
                                 [_] -> ListElemUpdate xDiff
                                 [] -> ListElemInsert 1
                             ]])]
                         ))))
                ) vds
              ))
  }
  in
  applyLens lens [f, mx]

main =
  h1 [] [] (toString (mapMaybe 0 (\n -> n + 1) []))