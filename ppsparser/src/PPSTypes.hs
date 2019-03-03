{-# LANGUAGE TemplateHaskell #-}

module PPSTypes(
  Header(..),
  headerStrings,
  Object,
  Color,
  ObjExpr(..),
  ObjBinOp(..),
  Output(..),
  title, author, homepage, headers, objectList, legend,
  emptyOutput,
  PotatoParser
) where

import qualified Data.Text as T
import qualified Data.Map as Map
import Text.Parsec

import Lens.Micro.Platform

data Header = OBJECTS | LEGEND | SOUNDS | COLLISIONLAYERS | RULES | WINCONDITIONS | LEVELS deriving (Read, Show)

headerStrings :: [String]
headerStrings = ["OBJECTS", "LEGEND", "SOUNDS", "COLLISIONLAYERS", "RULES", "WINCONDITIONS", "LEVELS"]

type Object = String
type Color = String

data ObjExpr = ObjConst Object | Not ObjExpr | ObjBin ObjBinOp ObjExpr ObjExpr deriving (Show)
data ObjBinOp = And | Or deriving (Show)

data Output = Output {
    _title :: String,
    _author :: String,
    _homepage :: String,
    _headers :: [Header],
    _objectList :: Map.Map Object Color,
    _legend :: Map.Map Char ObjExpr
} deriving (Show)

makeLenses ''Output

emptyOutput :: Output
emptyOutput = Output {
    _title = "",
    _author = "",
    _homepage = "",
    _headers = [],
    _objectList = Map.empty,
    _legend = Map.empty
  }

type PotatoParser = Parsec T.Text Output
