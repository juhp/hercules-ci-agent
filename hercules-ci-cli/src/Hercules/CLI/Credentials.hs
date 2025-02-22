{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveAnyClass #-}

-- | Manages the ~/.config/hercules-ci/credentials.json
module Hercules.CLI.Credentials where

import Control.Lens ((^?))
import Control.Monad.Trans.Maybe (MaybeT (MaybeT, runMaybeT))
import Data.Aeson (FromJSON, ToJSON, eitherDecode)
import qualified Data.Aeson as A
import Data.Aeson.Lens (AsPrimitive (_String), key)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map as M
import qualified Data.Text as T
import Hercules.CLI.Client (determineDefaultApiBaseUrl)
import Hercules.CLI.JSON (writeJsonFile)
import Hercules.Error
import qualified Network.URI as URI
import Protolude
import System.Directory (XdgDirectory (XdgConfig), createDirectoryIfMissing, doesFileExist, getXdgDirectory)
import qualified System.Environment
import System.FilePath (takeDirectory, (</>))

data Credentials = Credentials
  { domains :: Map Text DomainCredentials
  }
  deriving (Eq, Generic, FromJSON, ToJSON)

data DomainCredentials = DomainCredentials
  { personalToken :: Text
  }
  deriving (Eq, Generic, FromJSON, ToJSON)

data CredentialsParsingException = CredentialsParsingException
  { filePath :: FilePath,
    message :: Text
  }
  deriving (Show, Eq)

instance Exception CredentialsParsingException where
  displayException e = "Could not parse credentials file " <> filePath e <> ": " <> toS (message e)

data NoCredentialException = NoCredentialException
  { noCredentialDomain :: Text
  }
  deriving (Show, Eq)

instance Exception NoCredentialException where
  displayException e = "Could not find credentials for domain " <> toS (noCredentialDomain e) <> ". Please run hci login."

data ApiBaseUrlParsingException = ApiBaseUrlParsingException
  { apiBaseUrlParsingMessage :: Text
  }
  deriving (Show, Eq)

instance Exception ApiBaseUrlParsingException where
  displayException e = "Could not parse the api domain: " <> toS (apiBaseUrlParsingMessage e) <> ". Please correct the HERCULES_CI_API_BASE_URL environment variable."

getCredentialsFilePath :: IO FilePath
getCredentialsFilePath = do
  dir <- getXdgDirectory XdgConfig "hercules-ci"
  pure $ dir </> "credentials.json"

readCredentials :: IO Credentials
readCredentials = do
  filePath_ <- getCredentialsFilePath
  doesFileExist filePath_ >>= \case
    False -> pure (Credentials mempty)
    True -> do
      bs <- BS.readFile filePath_
      escalate $ parseCredentials filePath_ bs

parseCredentials :: FilePath -> ByteString -> Either CredentialsParsingException Credentials
parseCredentials filePath_ bs =
  case eitherDecode (BL.fromStrict bs) of
    Right a -> Right a
    Left e -> Left (CredentialsParsingException {filePath = filePath_, message = toS e})

writeCredentials :: Credentials -> IO ()
writeCredentials credentials = do
  filePath_ <- getCredentialsFilePath
  createDirectoryIfMissing True (takeDirectory filePath_)
  writeJsonFile filePath_ credentials

urlDomain :: Text -> Either Text Text
urlDomain urlText = do
  uri <- maybeToEither "could not parse HERCULES_CI_API_BASE_URL" $ URI.parseAbsoluteURI (toS urlText)
  authority <- maybeToEither "HERCULES_CI_API_BASE_URL has no domain/authority part" $ URI.uriAuthority uri
  let name = URI.uriRegName authority
  maybeToEither "HERCULES_CI_API_BASE_URL domain name must not be empty" $ guard (name /= "")
  pure (toS name)

determineDomain :: IO Text
determineDomain = do
  baseUrl <- determineDefaultApiBaseUrl
  escalateAs ApiBaseUrlParsingException (urlDomain baseUrl)

writePersonalToken :: Text -> Text -> IO ()
writePersonalToken domain token = do
  creds <- readCredentials
  let creds' = creds {domains = domains creds & M.insert domain (DomainCredentials token)}
  writeCredentials creds'

readPersonalToken :: Text -> IO Text
readPersonalToken domain = do
  creds <- readCredentials
  case M.lookup domain (domains creds) of
    Nothing -> throwIO NoCredentialException {noCredentialDomain = domain}
    Just cred -> pure (personalToken cred)

-- | Try to get a token from the local environment.
--
-- 1. HERCULES_CI_API_TOKEN
-- 2. HERCULES_CI_SECRETS_JSON
tryReadEffectToken :: IO (Maybe Text)
tryReadEffectToken = runMaybeT $ tryReadEffectTokenFromEnv <|> tryReadEffectTokenFromFile

tryReadEffectTokenFromEnv :: MaybeT IO Text
tryReadEffectTokenFromEnv = T.pack <$> MaybeT (System.Environment.lookupEnv "HERCULES_CI_API_TOKEN")

tryReadEffectTokenFromFile :: MaybeT IO Text
tryReadEffectTokenFromFile = do
  inEffect <- MaybeT $ System.Environment.lookupEnv "IN_HERCULES_CI_EFFECT"
  guard $ inEffect == "true"
  secretsJsonPath <- MaybeT $ System.Environment.lookupEnv "HERCULES_CI_SECRETS_JSON"
  liftIO do
    bs <- BS.readFile secretsJsonPath
    json <- case eitherDecode (BL.fromStrict bs) of
      Right x -> pure (x :: A.Value)
      Left e -> throwIO $ FatalError $ "HERCULES_CI_SECRETS_JSON, " <> T.pack secretsJsonPath <> " has invalid JSON: " <> T.pack e
    case json ^? key "hercules-ci" . key "data" . key "token" . _String of
      Just x -> pure x
      Nothing -> throwIO $ FatalError $ "HERCULES_CI_SECRETS_JSON, " <> T.pack secretsJsonPath <> " doesn't have key hercules-ci.data.token"

readToken :: IO Text -> IO Text
readToken getDomain = do
  tryReadEffectToken >>= \case
    Just x -> pure x
    Nothing -> readPersonalToken =<< getDomain
