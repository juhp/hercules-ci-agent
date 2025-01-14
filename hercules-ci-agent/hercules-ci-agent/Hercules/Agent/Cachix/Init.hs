{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}

module Hercules.Agent.Cachix.Init where

#if MIN_VERSION_cachix(0,7,0)
import Cachix.Client.Version (cachixVersion)
#else
import Cachix.Client.Env (cachixVersion)
#endif
import qualified Cachix.Client.Push as Cachix.Push
import qualified Cachix.Client.Secrets as Cachix.Secrets
import Cachix.Client.URI (defaultCachixBaseUrl)
import qualified Data.Map as M
import Hercules.Agent.Cachix.Env as Env
import qualified Hercules.Agent.Config as Config
import Hercules.CNix.Store (openStore)
import Hercules.Error
import qualified Hercules.Formats.CachixCache as CachixCache
import qualified Katip as K
import Network.HTTP.Client (ManagerSettings (managerModifyRequest, managerResponseTimeout), responseTimeoutNone)
import Network.HTTP.Client.TLS (newTlsManagerWith, tlsManagerSettings)
import Network.HTTP.Simple (setRequestHeader)
import Protolude
import qualified Servant.Auth.Client
import Servant.Client (mkClientEnv)

-- TODO use from lib after cachix >0.3.5 + https://github.com/cachix/cachix/pull/274
customManagerSettings :: ManagerSettings
customManagerSettings =
  tlsManagerSettings
    { managerResponseTimeout = responseTimeoutNone,
      -- managerModifyRequest :: Request -> IO Request
      managerModifyRequest = return . setRequestHeader "User-Agent" [encodeUtf8 cachixVersion]
    }

newEnv :: Config.FinalConfig -> Map Text CachixCache.CachixCache -> K.KatipContextT IO Env.Env
newEnv _config cks = do
  -- FIXME: sl doesn't work??
  K.katipAddContext (K.sl "caches" (M.keys cks)) $
    K.logLocM K.DebugS ("Cachix init " <> K.logStr (show (M.keys cks) :: Text))
  pcs <- liftIO $ toPushCaches cks
  store <- liftIO openStore
  httpManager <- newTlsManagerWith customManagerSettings
  pure
    Env.Env
      { pushCaches = pcs,
        netrcLines = toNetrcLines cks,
        cacheKeys = cks,
        nixStore = store,
        clientEnv = mkClientEnv httpManager defaultCachixBaseUrl
      }

toNetrcLines :: Map Text CachixCache.CachixCache -> [Text]
toNetrcLines = concatMap toNetrcLine . M.toList
  where
    toNetrcLine (name, keys) = do
      pt <- toList $ CachixCache.authToken keys
      pure $ "machine " <> name <> ".cachix.org" <> " login authtoken password " <> pt

toPushCaches :: Map Text CachixCache.CachixCache -> IO (Map Text PushCache)
toPushCaches = sequenceA . M.mapMaybeWithKey toPushCaches'
  where
    toPushCaches' name keys =
      let t = fromMaybe "" (CachixCache.authToken keys)
       in do
            sk <- head $ CachixCache.signingKeys keys
            Just $
              escalateAs FatalError $ do
                k' <- Cachix.Secrets.parseSigningKeyLenient sk
                pure
                  PushCache
                    { pushCacheName = name,
                      pushCacheSecret =
                        Cachix.Push.PushSigningKey
                          (Servant.Auth.Client.Token $ encodeUtf8 t)
                          k'
                    }
            <|> do
              token <- head $ CachixCache.authToken keys
              Just $
                pure
                  PushCache
                    { pushCacheName = name,
                      pushCacheSecret =
                        Cachix.Push.PushToken (Servant.Auth.Client.Token $ encodeUtf8 token)
                    }
