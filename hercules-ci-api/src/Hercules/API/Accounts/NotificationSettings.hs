{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}

module Hercules.API.Accounts.NotificationSettings where

import Hercules.API.Accounts.SimpleAccount (SimpleAccount)
import Hercules.API.Prelude
import Hercules.API.SourceHostingSite.SimpleSite (SimpleSite)

data NotificationLevel
  = Ignore
  | All
  deriving (Generic, Show, Eq, NFData, ToJSON, FromJSON, ToSchema)

data NotificationSetting = NotificationSetting
  { notificationLevel :: Maybe NotificationLevel,
    notificationEmail :: Maybe Text
  }
  deriving (Generic, Show, Eq, NFData, ToJSON, FromJSON, ToSchema)

data NotificationAccountOverride = NotificationSettingsOverride
  { account :: SimpleAccount,
    setting :: NotificationSetting
  }
  deriving (Generic, Show, Eq, NFData, ToJSON, FromJSON, ToSchema)

data AuthorizedEmail = AuthorizedEmail
  { address :: Text,
    isPrimary :: Bool,
    source :: Maybe SimpleSite
  }
  deriving (Generic, Show, Eq, NFData, ToJSON, FromJSON, ToSchema)

data NotificationSettings = NotificationSettings
  { authorizedEmails :: [AuthorizedEmail],
    defaultSetting :: Maybe NotificationSetting,
    accountOverrides :: [NotificationAccountOverride]
  }
  deriving (Generic, Show, Eq, NFData, ToJSON, FromJSON, ToSchema)