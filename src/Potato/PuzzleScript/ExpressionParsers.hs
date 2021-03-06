{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}

module Potato.PuzzleScript.ExpressionParsers (
  parse_Object,
  parse_SingleObject,
  parse_ObjectExpr,
  parse_LegendExpr,
  parse_WinCondExpr,
  parse_Rule,
  parse_RuleGroup

) where

import Potato.PuzzleScript.Types
import qualified Potato.PuzzleScript.Token as PT
import Potato.PuzzleScript.ParserOutput

import qualified Data.Map as Map
import qualified Data.Text as T
import Data.Functor.Identity (Identity)
import Text.Parsec
import Text.Parsec.Expr

guardError :: Bool -> String -> PotatoParser ()
guardError b msg = if b then return () else fail msg

maybeParens :: PotatoParser a -> PotatoParser a
maybeParens p = PT.parens p <|> p

opTable_Boolean :: [[Operator T.Text Output Identity Boolean]]
opTable_Boolean =
  [[Prefix (PT.reserved "not" >> return (Boolean_Not))],
  [Infix (PT.reserved "and" >> return (Boolean_Bin And)) AssocLeft],
  [Infix (PT.reserved "or" >> return (Boolean_Bin Or)) AssocLeft]]

parse_Boolean_Input :: PotatoParser Boolean
parse_Boolean_Input = do
  enum <- choice $ map (\x -> PT.reserved (show x) >> return (show x)) allKeyboardInputs
  return $ Boolean_Input (read enum)

parse_Boolean_Term :: PotatoParser Boolean
parse_Boolean_Term =
  PT.parens parse_Boolean <|>
  parse_Boolean_Input <|>
  (PT.reserved "True" >> return Boolean_True) <|>
  (PT.reserved "False" >> return Boolean_False) <?>
  "valid Boolean expression"

parse_Boolean :: PotatoParser Boolean
parse_Boolean = buildExpressionParser opTable_Boolean parse_Boolean_Term <?> "Boolean"

parse_Command :: PotatoParser Command
parse_Command = parseMessage <|> parseRegular <?> "command" where
  parseMessage = do
    PT.reserved "Message"
    msg <- many $ noneOf "\n\r+"
    return $ Message msg
  parseRegular =
    (PT.reserved "Cancel" >> return Cancel) <|>
    (PT.reserved "Win" >> return Win)

parse_Object :: PotatoParser Object
parse_Object = do
  om <- getState >>= return . _objectList
  name <- PT.identifier
  guardError (Map.member name om) ("unknown object " ++ name)
  return name

--parse_SpaceModifier :: PotatoParser SpaceModifier
--parse_SpaceModifier = try (PT.symbol "Abs" >> return Abs) <|> try (PT.symbol "Rel" >> return Rel) <|> return Default

parse_Orientation :: PotatoParser Orientation
parse_Orientation = choice (map (\x -> do { PT.reserved x; return x}) (Map.keys knownOrientations))

parse_Velocity :: PotatoParser Velocity
parse_Velocity = do
  let vm = knownVelocities
  name <- PT.identifier <|> PT.operator
  guardError (Map.member name vm) ("unknown velocity " ++ name)
  return name

parse_SingleObject_Orientation :: PotatoParser SingleObject
parse_SingleObject_Orientation = do
  orient <- parse_Orientation
  obj <- parse_Object
  return $ SingleObject_Orientation orient obj

parse_SingleObject :: PotatoParser SingleObject
parse_SingleObject = (try (parse_Object >>= return . SingleObject) <|> parse_SingleObject_Orientation)


opTable_ObjectExpr :: [[Operator T.Text Output Identity ObjectExpr]]
opTable_ObjectExpr =
  [[Infix (PT.reserved "and" >> return (ObjectExpr_Bin And_Obj)) AssocLeft],
  [Infix (PT.reserved "or" >> return (ObjectExpr_Bin Or_Obj)) AssocLeft]]

parse_ObjectExpr_Term :: PotatoParser ObjectExpr
parse_ObjectExpr_Term = PT.parens parse_ObjectExpr <|> (parse_SingleObject >>= return . ObjectExpr_Single)

parse_ObjectExpr :: PotatoParser ObjectExpr
parse_ObjectExpr = buildExpressionParser opTable_ObjectExpr parse_ObjectExpr_Term <?> "ObjectExpr"

validate_LegendExpr :: LegendExpr -> Bool
validate_LegendExpr (LegendExpr _ x) =  checkObjExpr x where
  checkObjExpr = \case
    (ObjectExpr_Single _) -> True
    (ObjectExpr_Bin And_Obj x y) -> checkObjExpr x && checkObjExpr y

parse_LegendExpr :: PotatoParser LegendExpr
parse_LegendExpr = do
  (key:[]) <- try PT.identifier <|> try PT.operator <?> "unreserved char"
  PT.reservedOp "="
  value <- parse_ObjectExpr
  let r = LegendExpr key value
  guardError (validate_LegendExpr r) "invalid object expression in legend expression"
  return r

parse_WinUnOp :: PotatoParser WinUnOp
parse_WinUnOp =
  try (PT.reserved "All" >> return Win_All) <|>
  try (PT.reserved "Some" >> return Win_Some) <|>
  try (PT.reserved "No" >> return Win_No) <?>
  "valid win condition unary operator"

parse_WinBinOp :: PotatoParser WinBinOp
parse_WinBinOp = PT.reserved "on" >> return Win_On

parse_BasicWinCondExpr :: PotatoParser BasicWinCondExpr
parse_BasicWinCondExpr = do
  op <- parse_WinUnOp
  obj <- parse_SingleObject
  return $ BasicWinCondExpr op obj

parse_WinCondExprBinOp :: PotatoParser WinCondExpr
parse_WinCondExprBinOp = do
  exp1 <- parse_BasicWinCondExpr
  op <- parse_WinBinOp
  exp2 <- parse_SingleObject
  return $ WinCondExpr_Bin op exp1 exp2

parse_WinCondExpr :: PotatoParser WinCondExpr
parse_WinCondExpr = try parse_WinCondExprBinOp <|> (parse_BasicWinCondExpr >>= return . WinCondExpr_Basic)

parse_PatBinOp :: PotatoParser PatBinOp
parse_PatBinOp = do PT.reservedOp "|" >> return Pipe

parse_PatternObject_Velocity :: PotatoParser PatternObj
parse_PatternObject_Velocity = do
  v <- parse_Velocity
  obj <- parse_SingleObject
  return $ PatternObject_Velocity v obj

parse_PatternObj :: PotatoParser PatternObj
parse_PatternObj =
  try parse_PatternObject_Velocity <|>
  try (parse_ObjectExpr >>= return . PatternObject) <?>
  "PatternObj"

-- |
-- note this parser does not use lexeme
-- lexeme is added by parse_Patterns which uses parse_Pattern
parse_Pattern :: PotatoParser Pattern
parse_Pattern = PT.bracketsNoLexeme $ do
  first <- parse_PatternObj
  rest <- many $ do
    op <- parse_PatBinOp
    p <- parse_PatternObj
    return (op, p)
  return $ foldr (\(op, p) acc -> (\p' -> Pattern_Bin op p' (acc p))) Pattern_PatternObj rest $ first

parse_Patterns :: PotatoParser Patterns
parse_Patterns = do
  x <- parse_Pattern
  -- I don't understand why I need a `try` here
  -- TODO figure out why...
  xs <- many . try $ (many (char ' ' <|> char '\t') >> parse_Pattern )
  PT.whiteSpace
  return $ Patterns (x:xs)

parse_RuleArrow :: PotatoParser ()
parse_RuleArrow = PT.reservedOp "->"

-- TODO validate same num args
-- TODO validate elipses are in the same position
validate_PatternPair :: Pattern -> Pattern -> Maybe String
validate_PatternPair lhs rhs = Nothing

-- | validate_UnscopedRule_Patterns checks if an UnscopedRule is valid
-- returns Nothing if rule is valid
validate_UnscopedRule_Patterns :: UnscopedRule -> Maybe String
validate_UnscopedRule_Patterns (UnscopedRule_Patterns (Patterns []) (Patterns[])) = Nothing
validate_UnscopedRule_Patterns (UnscopedRule_Patterns _ (Patterns[])) = Just "Pattern count mismatch"
validate_UnscopedRule_Patterns (UnscopedRule_Patterns (Patterns[]) _) = Just "Pattern count mismatch"
validate_UnscopedRule_Patterns (UnscopedRule_Patterns (Patterns (x:xs)) (Patterns (y:ys))) = case validate_PatternPair x y of
  Nothing -> validate_UnscopedRule_Patterns (UnscopedRule_Patterns (Patterns xs) (Patterns ys))
  just -> just
validate_UnscopedRule_Patterns _ = Just "Not a pattern match rule"

parse_UnscopedRule_Patterns :: PotatoParser UnscopedRule
parse_UnscopedRule_Patterns = do
  p1 <- parse_Patterns
  parse_RuleArrow
  p2 <- parse_Patterns
  return $ UnscopedRule_Patterns p1 p2

parse_UnscopedRule_Rule :: PotatoParser UnscopedRule
parse_UnscopedRule_Rule = do
  p <- parse_Patterns
  parse_RuleArrow
  r <- parse_Rule
  return $ UnscopedRule_Rule p r

parse_UnscopedRule_Boolean :: PotatoParser UnscopedRule
parse_UnscopedRule_Boolean = do
  p <- parse_Boolean
  parse_RuleArrow
  r <- parse_Rule
  return $ UnscopedRule_Boolean p r

parse_UnscopedRule :: PotatoParser UnscopedRule
parse_UnscopedRule =
  try parse_UnscopedRule_Boolean <|>
  try parse_UnscopedRule_Rule <|>
  try parse_UnscopedRule_Patterns <?>
  "UnscopedRule"

parse_Rule_Scoped :: PotatoParser Rule
parse_Rule_Scoped = do
  -- TODO change to parse_Direction
  v <- parse_Velocity
  r <- parse_UnscopedRule
  return $ Rule_Scoped v r

--validate_Rule_Scoped :: Rule_Scoped
-- TODO check that velocity is Abs

parse_Rule :: PotatoParser Rule
parse_Rule =
  try parse_Rule_Scoped <|>
  try (parse_UnscopedRule >>= return . Rule) <|>
  try (parse_Command >>= return . Rule_Command) <?>
  "Rule"

validate_Late_Rule :: Rule -> Bool
validate_Late_Rule r = undefined

parse_RulePlus :: PotatoParser ()
parse_RulePlus = PT.reservedOp "+"

parse_RuleGroup :: PotatoParser RuleGroup
parse_RuleGroup = sepBy parse_Rule parse_RulePlus >>= return . RuleGroup


-- do we support multi nested loops?
--parse_Rule_Looped :: LookupMaps -> PotatoParser Rule
--parse_Rule_Looped lm = do
--  rules <- between (PT.reserved "startLoop") (PT.reserved "endLoop") parse_Rule
