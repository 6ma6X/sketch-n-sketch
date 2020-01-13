module TSEFLLPPolys exposing (Poly(..), PixelPoly, polyBounds, polyPathSet, containsPoint, flatten, taggedStringToPixelPoly)

import Dict exposing (Dict)
import Set exposing (Set)

import BoundsUtils
import Lang
import LeoUnparser exposing (unparseType)
import Types2
import Utils

import TSEFLLPTypes exposing (..)


-- Zero based indexing here.

-- Our polygon shape is like so:
--
--          ██████
--    ████████████
--    ████████████
--    ████████████
--    ████
--
-- It's a rectangle of the bounding box
-- of the non-whitespace characters, with
-- a cutout from the top-left and bot-right
-- corners. These cutouts correspond either
-- to whitespace or to string regions not
-- associated with the poly.
--
-- Polygon region is bounds - startCutoutBounds - endCutoutBounds.
--
-- Encoding (0-based indexing):
--
--                    left                                     right (exclusive)
--                      ↓                                        ↓
--               top →      rightBotCornerOfLeftTopCutout↘︎███████
--                      █████████████████████████████████████████
--                      █████████████████████████████████████████
--                      █████████████████████████████████████████
--                      ████↖︎leftTopCornerOfRightBotCutout
--   bot (exclusive) →
--
--

type alias Properties = { bounds                        : (Int, Int, Int, Int)
                        , rightBotCornerOfLeftTopCutout : (Int, Int)
                        , leftTopCornerOfRightBotCutout : (Int, Int)
                        , pathSet                       : Set ProjectionPath
                        , children                      : List Poly
                        }

type Poly = Poly Properties

type alias PixelPoly    = Poly -- with units in pixels;     upper left is 0,0
type alias CharGridPoly = Poly -- with units in characters; upper left is 0,0


tabSize = 2


properties : Poly -> Properties
properties (Poly properties) = properties

-- Overall bounding box (left, top, right, bot) as in the diagram above.
polyBounds : Poly -> (Int, Int, Int, Int)
polyBounds = properties >> (.bounds)

polyRightBotCornerOfLeftTopCutout : Poly -> (Int, Int)
polyRightBotCornerOfLeftTopCutout = properties >> (.rightBotCornerOfLeftTopCutout)

polyLeftTopCornerOfRightBotCutout : Poly -> (Int, Int)
polyLeftTopCornerOfRightBotCutout = properties >> (.leftTopCornerOfRightBotCutout)

startCutoutBounds : Poly -> (Int, Int, Int, Int)
startCutoutBounds (Poly {bounds, rightBotCornerOfLeftTopCutout}) =
  let
    (left, top, _, _)      = bounds
    (startX, firstLineBot) = rightBotCornerOfLeftTopCutout
  in
  (left, top, startX, firstLineBot)

endCutoutBounds : Poly -> (Int, Int, Int, Int)
endCutoutBounds (Poly {bounds, leftTopCornerOfRightBotCutout}) =
  let
    (_, _, right, bot)  = bounds
    (endX, lastLineTop) = leftTopCornerOfRightBotCutout
  in
  (endX, lastLineTop, right, bot)

polyPathSet : Poly -> Set ProjectionPath
polyPathSet (Poly {pathSet}) = pathSet

flatten : Poly -> List Poly
flatten ((Poly {children}) as box) = box :: List.concatMap flatten children

containsPoint : (Int, Int) -> Poly -> Bool
containsPoint point poly =
  BoundsUtils.containsPoint (polyBounds poly) point &&
  not (BoundsUtils.containsPoint (startCutoutBounds poly) point) &&
  not (BoundsUtils.containsPoint (startCutoutBounds poly) point)

-- firstLineLeftTop : Poly -> (Int, Int)
-- firstLineLeftTop = startCutoutBounds >> (\(left, top, startX, firstLineBot) -> (startX, top))
--
-- lastLineRightBot : Poly -> (Int, Int)
-- lastLineRightBot = endCutoutBounds >> (\(endX, lastLineTop, right, bot) -> (endX, bot))


taggedStringToPixelPoly : Int -> Int -> StringTaggedWithProjectionPaths -> PixelPoly
taggedStringToPixelPoly charWidthPx charHeightPx taggedString =
  taggedString
  |> taggedStringToCharGridPoly
  |> charGridPolyToPixelPoly charWidthPx charHeightPx


taggedStringToCharGridPoly : StringTaggedWithProjectionPaths -> CharGridPoly
taggedStringToCharGridPoly taggedString =
  let
    nextLocation : (Int, Int) -> Char -> (Int, Int)
    nextLocation (x, y) char =
      if      char == '\n' then (0          , y + 1)
      else if char == '\t' then (x + tabSize, y    )
      else                      (x + 1      , y    )

    string = taggedStringToNormalString taggedString

    (_, charIToLocationDict) =
      Utils.strFoldLeftWithIndex
          ((0,0), Dict.empty)
          string
          (\(point, charIToLocationDict) charI char ->
            ( nextLocation point char
            , Dict.insert charI point charIToLocationDict
            )
          )

    charIToLocation : Int -> (Int, Int)
    charIToLocation charI = Dict.get charI charIToLocationDict |> Utils.fromJustLazy (\() -> "Expected to find char index " ++ toString charI ++ " among the " ++ toString (Dict.size charIToLocationDict) ++ " entries in the charIToLocationDict for \'" ++ string ++ "\'")
  in
  taggedStringToCharGridPoly_ charIToLocation taggedString 0


taggedStringToCharGridPoly_ : (Int -> (Int, Int)) -> StringTaggedWithProjectionPaths -> Int -> CharGridPoly
taggedStringToCharGridPoly_ charIToLocation taggedString charI =
  let recurse = taggedStringToCharGridPoly_ charIToLocation in
  case taggedString of
    TaggedString string pathSet ->
      let
        (defaultX, defaultY) = charIToLocation charI -- In case string is empty or all whitespace.
        allNonWhitespaceCharCorners =
          string
          |> String.toList
          |> Utils.mapi0 (\(localI, char) ->
            let (x, y) = charIToLocation (localI + charI) in
            if char /= ' ' && char /= '\n' && char /= '\t'
            then [(x, y), (x, y + 1), (x + 1, y), (x + 1, y + 1)] -- Four corners.
            else []
          )
          |> List.concat

        maybeBounds           = BoundsUtils.pointsToMaybeBounds allNonWhitespaceCharCorners
        maybeFirstLineLeftTop = allNonWhitespaceCharCorners |> Utils.minimumBy (\(x, y) -> (y, x))
        maybeLastLineRightBot = allNonWhitespaceCharCorners |> Utils.maximumBy (\(x, y) -> (y, x))

        ((left, top, right, bot) as bounds) = maybeBounds |> Maybe.withDefault (defaultX, defaultY, defaultX, defaultY + 1)  -- Defaults only triggered if all whitespace; 0-width
        rightBotCornerOfLeftTopCutout       = maybeFirstLineLeftTop |> Maybe.map (\(startX, _) -> (startX, top + 1)) |> Maybe.withDefault (left,  top + 1) -- Defaults only triggered if all whitespace; 0-width
        leftTopCornerOfRightBotCutout       = maybeLastLineRightBot |> Maybe.map (\(endX, _)   -> (endX, bot - 1))   |> Maybe.withDefault (right, bot - 1) -- Defaults only triggered if all whitespace; 0-width
      in
      Poly { bounds                        = bounds
           , rightBotCornerOfLeftTopCutout = rightBotCornerOfLeftTopCutout
           , leftTopCornerOfRightBotCutout = leftTopCornerOfRightBotCutout
           , pathSet                       = pathSet
           , children                      = []
           }

    TaggedStringAppend leftStr rightStr pathSet ->
      let
        leftChild  = recurse leftStr charI
        rightChild = recurse rightStr (charI + stringLength leftStr)
        children   = [leftChild, rightChild]

        -- Ignore empty (i.e. whitespace) boxes, but preserve the tree structure.
        nonZeroAreaChildren =
          children
          |> List.filter (polyBounds >> BoundsUtils.area >> (/=) 0)

        ((left, top, right, bot) as bounds) =
          nonZeroAreaChildren
          |> List.map polyBounds
          |> BoundsUtils.maybeEnclosureOfAllBounds
          |> Maybe.withDefault (polyBounds rightChild)

        rightBotCornerOfLeftTopCutout =
          nonZeroAreaChildren
          |> List.map polyRightBotCornerOfLeftTopCutout
          |> Utils.minimumBy (\(startX, firstLineBot) -> (firstLineBot, startX))
          |> Maybe.withDefault (left, top + 1)

        leftTopCornerOfRightBotCutout =
          nonZeroAreaChildren
          |> List.map polyLeftTopCornerOfRightBotCutout
          |> Utils.maximumBy (\(endX, lastLineTop) -> (lastLineTop, endX))
          |> Maybe.withDefault (right, bot - 1)
      in
      Poly { bounds                        = bounds
           , rightBotCornerOfLeftTopCutout = rightBotCornerOfLeftTopCutout
           , leftTopCornerOfRightBotCutout = leftTopCornerOfRightBotCutout
           , pathSet                       = pathSet
           , children                      = children
           }


charGridPolyToPixelPoly : Int -> Int -> CharGridPoly -> PixelPoly
charGridPolyToPixelPoly charWidthPx charHeightPx (Poly { bounds, rightBotCornerOfLeftTopCutout, leftTopCornerOfRightBotCutout, pathSet, children }) =
  let
    (charLeft, charTop, charRight, charBot) = bounds
    (charStartX, charFirstLineBot)          = rightBotCornerOfLeftTopCutout
    (charEndX,   charLastLineTop)           = leftTopCornerOfRightBotCutout
  in
  Poly { bounds                        = (charLeft*charWidthPx, charTop*charHeightPx, charRight*charWidthPx, charBot*charHeightPx)
       , rightBotCornerOfLeftTopCutout = (charStartX*charWidthPx, charFirstLineBot*charHeightPx)
       , leftTopCornerOfRightBotCutout = (charEndX*charWidthPx,   charLastLineTop*charHeightPx)
       , pathSet                       = pathSet
       , children                      = (List.map (charGridPolyToPixelPoly charWidthPx charHeightPx) children)
       }
