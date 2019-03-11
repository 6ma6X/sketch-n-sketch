--------------------------------------------------------------------------------
-- Simple wrapper around List Monad for nondeterminism
--------------------------------------------------------------------------------

module NonDet exposing
  ( NonDet
  , none
  , fromList
  , toList
  , map
  , pure
  , andThen
  , do
  , concat
  , concatMap
  , oneOfEach
  , oneOfEachDict
  , collapseMaybe
  )

import Dict exposing (Dict)
import Utils

--------------------------------------------------------------------------------
-- Declarations
--------------------------------------------------------------------------------

type NonDet a =
  N (List a)

--------------------------------------------------------------------------------
-- Creation
--------------------------------------------------------------------------------

none : NonDet a
none =
  N []

fromList : List a -> NonDet a
fromList =
  N

--------------------------------------------------------------------------------
-- Collection
--------------------------------------------------------------------------------

toList : NonDet a -> List a
toList (N xs) =
  xs

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

map : (a -> b) -> NonDet a -> NonDet b
map f =
  toList >> List.map f >> fromList

pure : a -> NonDet a
pure =
  List.singleton >> fromList

andThen : (a -> NonDet b) -> NonDet a -> NonDet b
andThen f =
  toList >> List.map f >> concat

--------------------------------------------------------------------------------
-- Generic Library Functions
--------------------------------------------------------------------------------

do : NonDet a -> (a -> NonDet b) -> NonDet b
do =
  flip andThen

--------------------------------------------------------------------------------
-- Specific Library Functions
--------------------------------------------------------------------------------

concat : List (NonDet a) -> NonDet a
concat =
  List.map toList >> List.concat >> fromList

concatMap : (a -> NonDet b) -> List a -> NonDet b
concatMap f =
  List.map f >> concat

oneOfEach : List (NonDet a) -> NonDet (List a)
oneOfEach =
  List.map toList >> Utils.oneOfEach >> fromList

oneOfEachDict : Dict k (NonDet a) -> NonDet (Dict k a)
oneOfEachDict =
  Dict.toList
    >> List.map (\(h, nx) -> map ((,) h) nx)
    >> oneOfEach
    >> map Dict.fromList

collapseMaybe : NonDet (Maybe a) -> NonDet a
collapseMaybe =
  toList >> Utils.filterJusts >> fromList