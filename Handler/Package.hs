{-# LANGUAGE OverloadedStrings #-}

-- | Lists the package page similar to Hackage.

module Handler.Package where

import           Data.Char
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import           Data.Time (addUTCTime)
import           Database.Esqueleto ((^.), (&&.), Value (Value))
import qualified Database.Esqueleto as E
import           Formatting
import           Import
import           Text.Email.Validate
import           Text.Markdown

-- | Page metadata package.
getPackageR :: PackageName -> Handler Html
getPackageR pn = do
    let maxSnaps = 10
        asInt :: Int -> Int
        asInt = id
        haddocksLink ident version =
            HaddockR ident [concat [toPathPiece pn, "-", toPathPiece version]]
    (packages, downloads, recentDownloads, Entity _ metadata) <- runDB $ do
        packages <- fmap (map reformat) $ E.select $ E.from $ \(p, s) -> do
            E.where_ $ (p ^. PackageStackage E.==. s ^. StackageId)
                   &&. (p ^. PackageName' E.==. E.val pn)
                   &&. (s ^. StackageTitle `E.like` E.val "%, exclusive")
            E.orderBy [E.desc $ s ^. StackageUploaded]
            E.limit maxSnaps
            --selectList [PackageName' ==. pn] [LimitTo 10, Desc PackageStackage]
            return (p ^. PackageVersion, s ^. StackageTitle, s ^. StackageIdent, s ^. StackageHasHaddocks)
        downloads <- count [DownloadPackage ==. pn]
        now <- liftIO getCurrentTime
        let nowMinus30 = addUTCTime (-30 * 24 * 60 * 60) now
        recentDownloads <- count [DownloadPackage ==. pn, DownloadTimestamp >=. nowMinus30]
        metadata <- getBy404 (UniqueMetadata pn)
        return (packages, downloads, recentDownloads, metadata)
    readmeText <- return "TODO"
    let readmeHtml = markdown def readmeText
        deps = enumerate (metadataDeps metadata)
        authors = enumerate (parseIdentitiesLiberally (metadataAuthor metadata))
        maintainers = let ms = enumerate (parseIdentitiesLiberally (metadataMaintainer metadata))
                      in if ms == authors
                            then []
                            else ms
    defaultLayout $ do
        setTitle $ toHtml pn
        $(combineStylesheets 'StaticR
            [ css_bootstrap_css
            , css_bootstrap_responsive_css
            , css_font_awesome_min_css
            ])
        $(widgetFile "package")
  where enumerate = zip [0::Int ..]
        tags = ["web","framework","library","stable","maintained","potato"] :: [Text]

        reformat (Value version, Value title, Value ident, Value hasHaddocks) =
            (version,fromMaybe title (stripPrefix "Stackage build for " title),ident,hasHaddocks)

-- | An identifier specified in a package. Because this field has
-- quite liberal requirements, we often encounter various forms. A
-- name, a name and email, just an email, or maybe nothing at all.
data Identifier
  = EmailOnly !EmailAddress -- ^ An email only e.g. jones@example.com
  | Contact !Text
            !EmailAddress -- ^ A contact syntax, e.g. Dave Jones <jones@example.com>
  | PlainText !Text -- ^ Couldn't parse anything sensible, leaving as-is.
  deriving (Show,Eq)

-- | An author/maintainer field may contain a comma-separated list of
-- identifiers. It may be the case that a person's name is written as
-- "Einstein, Albert", but we only parse commas when there's an
-- accompanying email, so that would be:
--
--  Einstein, Albert <emc2@gmail.com>, Isaac Newton <falling@apple.com>
--
-- Whereas
--
-- Einstein, Albert, Isaac Newton
--
-- Will just be left alone. It's an imprecise parsing because the
-- input is wide open, but it's better than nothing:
--
-- λ> parseIdentitiesLiberally "Chris Done, Dave Jones <chrisdone@gmail.com>, Einstein, Albert, Isaac Newton, Michael Snoyman <michael@snoyman.com>"
-- [PlainText "Chris Done"
-- ,Contact "Dave Jones" "chrisdone@gmail.com"
-- ,PlainText "Einstein, Albert, Isaac Newton"
-- ,Contact "Michael Snoyman" "michael@snoyman.com"]
--
-- I think that is quite a predictable and reasonable result.
--
parseIdentitiesLiberally :: Text -> [Identifier]
parseIdentitiesLiberally =
  filter (not . empty) .
  map strip .
  concatPlains .
  map parseChunk .
  T.split (== ',')
  where empty (PlainText e) = T.null e
        empty _ = False
        strip (PlainText t) = PlainText (T.strip t)
        strip x = x
        concatPlains = go
          where go (PlainText x:PlainText y:xs) =
                  go (PlainText (x <> "," <> y) :
                      xs)
                go (x:xs) = x : go xs
                go [] = []

-- | Try to parse a chunk into an identifier.
--
-- 1. First tries to parse an \"email@domain.com\".
-- 2. Then tries to parse a \"Foo <email@domain.com>\".
-- 3. Finally gives up and returns a plain text.
--
-- λ> parseChunk "foo@example.com"
-- EmailOnly "foo@example.com"
-- λ> parseChunk "Dave Jones <dave@jones.com>"
-- Contact "Dave Jones" "dave@jones.com"
-- λ> parseChunk "<x>"
-- PlainText "<x>"
-- λ> parseChunk "Hello!"
-- PlainText "Hello!"
--
parseChunk :: Text -> Identifier
parseChunk chunk =
  case emailAddress (T.encodeUtf8 (T.strip chunk)) of
    Just email -> EmailOnly email
    Nothing ->
      case T.stripPrefix
             ">"
             (T.dropWhile isSpace
                          (T.reverse chunk)) of
        Just rest ->
          case T.span (/= '<') rest of
            (T.reverse -> emailStr,this) ->
              case T.stripPrefix "< " this of
                Just (T.reverse -> name) ->
                  case emailAddress (T.encodeUtf8 (T.strip emailStr)) of
                    Just email ->
                      Contact (T.strip name) email
                    _ -> plain
                _ -> plain
        _ -> plain
  where plain = PlainText chunk

-- | Render email to text.
renderEmail :: EmailAddress -> Text
renderEmail = T.decodeUtf8 . toByteString

-- | Format a number with commas nicely.
formatNum :: Int -> Text
formatNum = sformat commas
