{-# LANGUAGE TemplateHaskell #-}
--{-# LANGUAGE OverlappingInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}


import Potato.Math.Integral.Rot
import Potato.Math.Integral.TR

import Linear.V3
import qualified Linear.Matrix as M

import Test.QuickCheck

import Debug.Trace

instance (Bounded a, Integral a) => Arbitrary (V3 a) where
  arbitrary :: Gen (V3 a)
  arbitrary = do
    x <- arbitrarySizedIntegral
    y <- arbitrarySizedIntegral
    z <- arbitrarySizedIntegral
    return (V3 x y z)
{-
instance (Bounded a, Integral a) => Arbitrary (M.M33 a) where
  arbitrary :: Gen (M.M33 a)
  arbitrary = do
    v1 <- arbitrary
    v2 <- arbitrary
    v3 <- arbitrary
    return (V3 v1 v2 v3)
-}
er :: Integral a => M.M33 a
er =   V3 (V3 1 0 0)
         (V3 0 1 0)
         (V3 0 0 1)

xr :: Integral a => M.M33 a
xr =   V3 (V3 1 0 0)
         (V3 0 0 (-1))
         (V3 0 1 0)

zr :: Integral a => M.M33 a
zr =   V3 (V3 0 (-1) 0)
         (V3 1 0 0)
         (V3 0 0 1)

yr :: Integral a => M.M33 a
yr =   V3 (V3 0 0 (-1))
         (V3 0 1 0)
         (V3 1 0 0)

newtype OrthogonalRotation a = OrthogonalRotation (M.M33 a)
instance (Integral a) => Arbitrary (OrthogonalRotation a) where
  arbitrary :: Gen (OrthogonalRotation a)
  arbitrary = do
    rotlist <- listOf $ elements [xr,yr,zr,er]
    return $ OrthogonalRotation (foldl (M.!*!) er rotlist)

instance Arbitrary TR where
  arbitrary :: Gen TR
  arbitrary = do
    trans <- arbitrary
    OrthogonalRotation rot <- arbitrary
    return (TR trans rot)

prop_invTR :: TR -> Bool
prop_invTR tr = (invTR tr) !*! tr == identity


--Template haskell nonsense to run all properties prefixed with "prop_" in this file
return []

main :: IO Bool
main = $quickCheckAll
--main = $verboseCheckAll
