module Data.Maybe.Unsafe where

import Data.Maybe (Maybe(Just))

fromJust :: forall a. Maybe a -> a
fromJust (Just a) = a
