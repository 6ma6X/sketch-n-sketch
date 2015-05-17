module LangSvg (valToHtml, valToIndexedTree, printIndexedTree) where

import Html
import Svg
import Svg.Attributes as A
import VirtualDom

-- in Svg.elm:
--   type alias Svg = VirtualDom.Node
--   type alias Attribute = VirtualDom.Property

-- in Html.elm:
--   type alias Html = VirtualDom.Node

import Debug
import Set
import String
import Char
import Dict exposing (Dict)

import Lang exposing (..)
import Utils

------------------------------------------------------------------------------

-- TODO probably want to factor HTML attributes and SVG attributes into
-- records rather than lists of lists of ...

valToHtml : Int -> Int -> Val -> Html.Html
valToHtml w h (VList [VBase (String "svg"), VList vs1, VList vs2]) =
  let wh = [numAttrToVal "width" w, numAttrToVal "height" h] in
  let v' = VList [VBase (String "svg"), VList (wh ++ vs1), VList vs2] in
  valToNode v'
    -- NOTE: not checking if width/height already in vs1

valToNode : Val -> VirtualDom.Node
valToNode v = case v of
  VList [VBase (String "TEXT"), VBase (String s)] -> VirtualDom.text s
  VList [VBase (String f), VList vs1, VList vs2]  -> (svg f) (valsToAttrs vs1) (valsToNodes vs2)

valsToNodes = List.map valToNode
valsToAttrs = List.map valToAttr

numAttrToVal a i =
  VList [VBase (String a), VConst (toFloat i) dummyTrace]

valToAttr v =
  case v of
    VList [VBase (String a), VConst i _]       -> (attr a) (toString i)
    VList [VBase (String a), VBase (String s)] -> (attr a) s
    VList [VBase (String "points"), VList vs]  -> (attr "points") (valToPoints vs)
    VList [VBase (String "fill"), VList vs]    -> (attr "fill") (valToRgba vs)
    VList [VBase (String "stroke"), VList vs]  -> (attr "stroke") (valToRgba vs)
    VList [VBase (String "d"), VList vs]       -> (attr "d") (valToPath vs)

valToPoints = Utils.spaces << List.map valToPoint

valToPoint (VList [VConst x _, VConst y _]) =
  toString x ++ "," ++ toString y

valToRgba v = case v of
  [VConst r _, VConst g _, VConst b _, VConst a _] ->
    "rgba" ++ Utils.parens (Utils.commas (List.map toString [r,g,b,a]))

-- https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths
-- http://www.w3schools.com/svg/svg_path.asp
--
-- NOTES:
--  . using different representation of points in d than in points
--    to make it less verbose and easier to copy-and-paste raw SVG examples
--  . looks like commas are optional

valToPath = Utils.spaces << valToPath_

valToPath_ vs =
  let pt i j = toString i ++ " " ++ toString j in
  case vs of
    [] -> []
    VBase (String cmd) :: vs' ->
      if | matchCmd cmd "Z" -> cmd :: valToPath_ vs'
         | matchCmd cmd "MLT" ->
             let ([sx,sy],vs'') = projConsts 2 vs' in
             cmd :: pt sx sy :: valToPath_ vs''
         | matchCmd cmd "HV" ->
             let ([i],vs'') = projConsts 1 vs' in
             cmd :: toString i :: valToPath_ vs''
         | matchCmd cmd "C" ->
             let ([x1,y1,x2,y2,x,y],vs'') = projConsts 6 vs' in
             let pts = String.join " , " [pt x1 y1, pt x2 y2, pt x y] in
             cmd :: pts :: valToPath_ vs''
         | matchCmd cmd "SQ" ->
             let ([x1,y1,x,y],vs'') = projConsts 4 vs' in
             let pts = String.join " , " [pt x1 y1, pt x y] in
             cmd :: pts :: valToPath_ vs''
         | matchCmd cmd "A" ->
             let (ns,vs'') = projConsts 7 vs' in
             let blah = Utils.spaces (List.map toString ns) in
             cmd :: blah :: valToPath_ vs'' -- not worrying about commas

projConsts k vs =
  if k == 0 then ([], vs)
  else case vs of
         VConst i _ ::vs' ->
           let (l1,l2) = projConsts (k-1) vs' in
           (i::l1, l2)

matchCmd cmd s =
  let [c] = String.toList cmd in
  let cs  = String.toList s in
  List.member c (cs ++ List.map Char.toLower cs)


------------------------------------------------------------------------------

funcsSvg = [
    ("circle", Svg.circle)
  , ("ellipse", Svg.ellipse)
  , ("g", Svg.g)
  , ("line", Svg.line)
  , ("path", Svg.path)
  , ("polygon", Svg.polygon)
  , ("polyline", Svg.polyline)
  , ("rect", Svg.rect)
  , ("svg", Svg.svg)
  , ("text", Svg.text)
  , ("tspan", Svg.tspan)
  ]

funcsAttr = [
    ("cx", A.cx)
  , ("cy", A.cy)
  , ("d", A.d)
  , ("fill", A.fill)
  , ("height", A.height)
  , ("opacity", A.opacity)
  , ("points", A.points)
  , ("r", A.r)
  , ("rx", A.rx)
  , ("ry", A.ry)
  , ("stroke", A.stroke)
  , ("stroke-width", A.strokeWidth)
  , ("strokeWidth", A.strokeWidth)
  , ("style", A.style)
  , ("transform", A.transform)
  , ("viewbox", A.viewBox)
  , ("viewBox", A.viewBox)
  , ("width", A.width)
  , ("x", A.x)
  , ("x1", A.x1)
  , ("x2", A.x2)
  , ("y", A.y)
  , ("y1", A.y1)
  , ("y2", A.y2)
  ]

find d s =
  case Utils.maybeFind s d of
    Just f  -> f
    Nothing -> Debug.crash <| "MainSvg.find: " ++ s

attr = find funcsAttr
svg  = find funcsSvg


------------------------------------------------------------------------------

type alias ShapeKind = String

type alias NodeId = Int
type alias IndexedTree = Dict NodeId IndexedTreeNode
type IndexedTreeNode
  = TextNode String
  | SvgNode ShapeKind (List Val) (List NodeId)

children n = case n of {TextNode _ -> []; SvgNode _ _ l -> l}

valToIndexedTree : Val -> IndexedTree
valToIndexedTree = snd << flip valToIndexedTree_ (1, Dict.empty)

valToIndexedTree_ v (nextId, d) = case v of

  VList [VBase (String "TEXT"), VBase (String s)] ->
    (1 + nextId, Dict.insert nextId (TextNode s) d)

  VList [VBase (String kind), VList vs1, VList vs2] ->
    let processChild vi (a_nextId, a_graph , a_children) =
      let (a_nextId',a_graph') = valToIndexedTree_ vi (a_nextId, a_graph) in
      let a_children'          = (a_nextId' - 1) :: a_children in
      (a_nextId', a_graph', a_children') in
    let (nextId',d',children) = List.foldl processChild (nextId,d,[]) vs2 in
    let node = SvgNode kind vs1 (List.reverse children) in
    (1 + nextId', Dict.insert nextId' node d')

printIndexedTree : Val -> String
printIndexedTree = valToIndexedTree >> strEdges

strEdges : IndexedTree -> String
strEdges =
     Dict.toList
  >> List.map (\(i,n) ->
       let l = List.map toString (children n) in
       toString i ++ " " ++ Utils.braces (Utils.spaces l))
  >> Utils.lines

