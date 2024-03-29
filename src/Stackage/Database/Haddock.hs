{-# LANGUAGE CPP #-}
{-# LANGUAGE NoImplicitPrelude #-}
module Stackage.Database.Haddock
    ( renderHaddock
    ) where

import ClassyPrelude.Conduit
import qualified Documentation.Haddock.Parser as Haddock
import Documentation.Haddock.Types (DocH(..), Example(..), Header(..),
                                    Hyperlink(..), MetaDoc(..), Picture(..),
                                    Table(..), TableCell(..), TableRow(..))
#if MIN_VERSION_haddock_library(1,10,0)
import Documentation.Haddock.Types (ModLink(modLinkName))
#endif
import Text.Blaze.Html (Html, toHtml)
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

renderHaddock :: String -> Html
renderHaddock = hToHtml . Haddock.toRegular . _doc . Haddock.parseParas Nothing

-- | Convert a Haddock doc to HTML.
hToHtml :: DocH String String -> Html
hToHtml =
    go
  where
    go :: DocH String String -> Html
    go DocEmpty = mempty
    go (DocAppend x y) = go x ++ go y
    go (DocString x) = toHtml x
    go (DocParagraph x) = H.p $ go x
    go (DocIdentifier s) = H.code $ toHtml s
    go (DocIdentifierUnchecked s) = H.code $ toHtml s
#if MIN_VERSION_haddock_library(1,10,0)
    go (DocModule modLink) = H.code $ toHtml $ modLinkName modLink
#else
    go (DocModule s) = H.code $ toHtml s
#endif
    go (DocWarning x) = H.span H.! A.class_ "warning" $ go x
    go (DocEmphasis x) = H.em $ go x
    go (DocMonospaced x) = H.code $ go x
    go (DocBold x) = H.strong $ go x
    go (DocUnorderedList xs) = H.ul $ foldMap (H.li . go) xs
#if MIN_VERSION_haddock_library(1,11,0)
    go (DocOrderedList xs) = H.ol $ foldMap (H.li . go . snd) xs
#else
    go (DocOrderedList xs) = H.ol $ foldMap (H.li . go) xs
#endif
    go (DocDefList xs) = H.dl $ flip foldMap xs $ \(x, y) ->
        H.dt (go x) ++ H.dd (go y)
    go (DocCodeBlock x) = H.pre $ H.code $ go x
    go (DocHyperlink (Hyperlink url mlabel)) =
        H.a H.! A.href (H.toValue url) $ maybe (toHtml url) (toHtml . go) mlabel
    go (DocPic (Picture url mtitle)) =
        H.img H.! A.src (H.toValue url) H.! A.title (H.toValue $ fromMaybe mempty mtitle)
    go (DocAName s) = H.div H.! A.id (H.toValue s) $ mempty
    go (DocProperty s) = H.pre $ H.code $ toHtml s
    go (DocExamples es) = flip foldMap es $ \(Example exp' ress) ->
        H.div H.! A.class_ "example" $ do
            H.pre H.! A.class_ "expression" $ H.code $ toHtml exp'
            flip foldMap ress $ \res ->
                H.pre H.! A.class_ "result" $ H.code $ toHtml res
    go (DocHeader (Header level content)) =
        wrapper level $ go content
      where
        wrapper 1 = H.h1
        wrapper 2 = H.h2
        wrapper 3 = H.h3
        wrapper 4 = H.h4
        wrapper 5 = H.h5
        wrapper _ = H.h6
    go (DocMathInline x) = H.pre $ H.code $ toHtml x
    go (DocMathDisplay x) = H.pre $ H.code $ toHtml x
    go (DocTable (Table header body)) = H.table $ do
      unless (null header) $ H.thead $ mapM_ goRow header
      unless (null body) $ H.tbody $ mapM_ goRow body

    goRow (TableRow cells) = H.tr $ forM_ cells $ \(TableCell colspan rowspan content) ->
      H.td
        H.! A.colspan (H.toValue colspan)
        H.! A.rowspan (H.toValue rowspan)
          $ go content
