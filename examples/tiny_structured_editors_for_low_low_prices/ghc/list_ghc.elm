-- Dynamic dispatch names: toString, showsPrecFlip

-- Any functions with defined non-default instances
-- need to be dynamic.
--
-- In this case: "showsPrec"
-- But we can only be dynamic in the first argument,
-- so we'll flip the argument order "showsPrecFlip"


-- List definition, for reference. The Sketch-n-Sketch
-- surface language Leo treats lists as a separate type
-- (not a datatype), so the following is actually ignored
-- and we have to bake the List datatype definition into
-- the core language.
type List a = Nil
            | Cons a (List a)


-- From GHC repo at 8.6.5 release. ghc/libraries/base/GHC/Show.hs
--
-- type ShowS = String -> String
--
-- class  Show a  where
--     {-# MINIMAL showsPrec | show #-}
--
--     -- | Convert a value to a readable 'String'.
--     --
--     -- 'showsPrec' should satisfy the law
--     --
--     -- > showsPrec d x r ++ s  ==  showsPrec d x (r ++ s)
--     --
--     -- Derived instances of 'Text.Read.Read' and 'Show' satisfy the following:
--     --
--     -- * @(x,\"\")@ is an element of
--     --   @('Text.Read.readsPrec' d ('showsPrec' d x \"\"))@.
--     --
--     -- That is, 'Text.Read.readsPrec' parses the string produced by
--     -- 'showsPrec', and delivers the value that 'showsPrec' started with.
--
--     showsPrec :: Int    -- ^ the operator precedence of the enclosing
--                         -- context (a number from @0@ to @11@).
--                         -- Function application has precedence @10@.
--               -> a      -- ^ the value to be converted to a 'String'
--               -> ShowS
--
--     -- | A specialised variant of 'showsPrec', using precedence context
--     -- zero, and returning an ordinary 'String'.
--     show      :: a   -> String
--
--     -- | The method 'showList' is provided to allow the programmer to
--     -- give a specialised way of showing lists of values.
--     -- For example, this is used by the predefined 'Show' instance of
--     -- the 'Char' type, where values of type 'String' should be shown
--     -- in double quotes, rather than between square brackets.
--     showList  :: [a] -> ShowS
--
--     showsPrec _ x s = show x ++ s
--     show x          = shows x ""
--     showList ls   s = showList__ shows ls s
--
-- showList__ :: (a -> ShowS) ->  [a] -> ShowS
-- showList__ _     []     s = "[]" ++ s
-- showList__ showx (x:xs) s = '[' : showx x (showl xs)
--   where
--     showl []     = ']' : s
--     showl (y:ys) = ',' : showx y (showl ys)
--
-- -- | equivalent to 'showsPrec' with a precedence of 0.
-- shows           :: (Show a) => a -> ShowS
-- shows           =  showsPrec 0
--
-- -- | @since 2.01
-- instance Show a => Show [a]  where
--   {-# SPECIALISE instance Show [String] #-}
--   {-# SPECIALISE instance Show [Char] #-}
--   {-# SPECIALISE instance Show [Int] #-}
--   showsPrec _         = showList
--
--
-- -- | @since 2.01
-- instance Show Int where
--     showsPrec = showSignedInt
--



-- Evaluation order:
--
-- show [1, 2, 3] hits Show class default show implementation =>
-- shows [1, 2, 3] "" hits top level shows implementation =>
-- showsPrec 0 [1, 2, 3] "" hits Show a => Show [a] instance showsPrec implementation =>
-- showList [1, 2, 3] "" hits Show class default ShowList implementation =>
-- showList__ shows [1, 2, 3] "" hits top level showList__ implementation; shows is top level =>
-- '[' : shows 1 (showl [2, 3]) hits top level shows implmentation =>
-- '[' : showsPrec 0 1 (showl [2, 3]) hits Int instance showSignedInt, which for our purpose might as well be built-in toString =>
-- '[' : '1' : (showl [2, 3]) hits showList__ showl, wherein showx is still top level shows =>
-- '[' : '1' : ',' : showx 2 (showl [3]) =>
-- '[' : '1' : ',' : shows 2 (showl [3]) =>
-- '[' : '1' : ',' : showsPrec 0 2 (showl [3]) hits Int instance showSignedInt, which for our purpose might as well be built-in toString =>
-- '[' : '1' : ',' : '2' : (showl [3]) etc...



-- Okay, and now the translation to our language.
--
-- Any functions with defined non-default instances
-- need to be dynamic.
--
-- In this case: "showsPrec"
-- But we can only be dynamic in the first argument,
-- so we'll flip the argument order "showsPrecFlip"
--
--
--
-- type ShowS = String -> String
--
-- class  Show a  where
--     {-# MINIMAL showsPrec | show #-}
--
--     -- | Convert a value to a readable 'String'.
--     --
--     -- 'showsPrec' should satisfy the law
--     --
--     -- > showsPrec d x r ++ s  ==  showsPrec d x (r ++ s)
--     --
--     -- Derived instances of 'Text.Read.Read' and 'Show' satisfy the following:
--     --
--     -- * @(x,\"\")@ is an element of
--     --   @('Text.Read.readsPrec' d ('showsPrec' d x \"\"))@.
--     --
--     -- That is, 'Text.Read.readsPrec' parses the string produced by
--     -- 'showsPrec', and delivers the value that 'showsPrec' started with.
--
--     showsPrec :: Int    -- ^ the operator precedence of the enclosing
--                         -- context (a number from @0@ to @11@).
--                         -- Function application has precedence @10@.
--               -> a      -- ^ the value to be converted to a 'String'
--               -> ShowS
--
--     -- | A specialised variant of 'showsPrec', using precedence context
--     -- zero, and returning an ordinary 'String'.
--     show      :: a   -> String
--
--     -- | The method 'showList' is provided to allow the programmer to
--     -- give a specialised way of showing lists of values.
--     -- For example, this is used by the predefined 'Show' instance of
--     -- the 'Char' type, where values of type 'String' should be shown
--     -- in double quotes, rather than between square brackets.
--     showList  :: [a] -> ShowS
--
--     showsPrec _ x s = show x ++ s
--     show x          = shows x ""
show x = shows x ""
--     showList ls   s = showList__ shows ls s
showList ls s = showList__ shows ls s
--
-- showList__ :: (a -> ShowS) ->  [a] -> ShowS
-- showList__ _     []     s = "[]" ++ s
-- showList__ showx (x:xs) s = '[' : showx x (showl xs)
--   where
--     showl []     = ']' : s
--     showl (y:ys) = ',' : showx y (showl ys)
showList__ showx list s = case list of
  Nil       -> "[]" + s
  Cons x xs ->
    let showl list = case list of
      Nil       -> "]" + s
      Cons y ys -> "," + showx y (showl ys)
    in
    "[" + showx x (showl xs)
--
-- -- | equivalent to 'showsPrec' with a precedence of 0.
-- shows           :: (Show a) => a -> ShowS
-- shows           =  showsPrec 0
shows = showsPrec 0

showsPrec precN a = showsPrecFlip a precN
--
-- -- | @since 2.01
-- instance Show a => Show [a]  where
--   {-# SPECIALISE instance Show [String] #-}
--   {-# SPECIALISE instance Show [Char] #-}
--   {-# SPECIALISE instance Show [Int] #-}
--   showsPrec _         = showList
showsPrecFlip : List a -> Num -> String -> String
showsPrecFlip list _ = showList list
--
--
-- -- | @since 2.01
-- instance Show Int where
--     showsPrec = showSignedInt
showsPrecFlip : Num -> Num -> String -> String
showsPrecFlip num _ s = numToStringBuiltin num + s




toString : a -> String
toString = show

-- The desugaring step turns this into Cons's and Nil's
([1, 2, 3] : List Num)