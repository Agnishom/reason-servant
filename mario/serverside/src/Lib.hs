{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Lib where

import Data.Text (Text)
import Servant
import Data.Aeson
import Data.Aeson.Types
import GHC.Generics
import Data.Typeable
import Data.Acid
import Data.SafeCopy

import Data.Set (Set)
import qualified Data.Set as Set

import Control.Monad.State
import Control.Monad.Reader
import Control.Monad.Trans.Either

import Data.UUID (UUID)
import qualified Data.UUID.V4 as Uuid

data Account = Account {
  uid :: UUID
, username :: Text
, score :: Int
} deriving (Eq, Show, Ord, Generic, Typeable)

instance ToJSON Account

data AccountsState = AccountsState (Set Account)
  deriving (Eq, Show, Typeable)

$(deriveSafeCopy 0 'base ''UUID)
$(deriveSafeCopy 0 'base ''Account)
$(deriveSafeCopy 0 'base ''AccountsState)

addUser :: Account -> Update AccountsState ()
addUser user = do AccountsState state <- get
                  put . AccountsState $ Set.insert user state

queryState :: Query AccountsState (Set Account)
queryState = do AccountsState accounts <- ask
                return accounts

updateUser :: Account -> Account -> Update AccountsState ()
updateUser oldV newV = do
  AccountsState state <- get 
  let state' = Set.delete oldV state
  put . AccountsState $ Set.insert newV state'

$(makeAcidic ''AccountsState ['addUser, 'queryState, 'updateUser])

data AccountReq = AccountReq { username :: Text }
  deriving (Eq, Show, Generic)

instance FromJSON AccountReq

data ScoreUpdate = ScoreUpdate {
  newScore :: Int
} deriving (Eq, Show, Generic)

instance FromJSON ScoreUpdate

type API = "register" :> ReqBody '[JSON] AccountReq :> Post '[JSON] Account
      :<|> "users" :> Get '[JSON] (Set Account)
      :<|> "score" :> Capture "uuid" UUID 
                   :> ReqBody '[JSON] ScoreUpdate 
                   :> Put '[JSON] ()

-- TODO: 
-- - add websocket communication
-- - bind the frontend to that communication
-- - set up a working copy on a subdomain with an oncommit reload hook

server :: AcidState AccountsState -> Server API
server state = register :<|> users :<|> score
  where register :: AccountReq -> Handler Account
        register (AccountReq uname) = do
          uuid <- liftIO Uuid.nextRandom
          let newAccount = Account uuid uname 0

          liftIO $ update state (AddUser newAccount)
          return newAccount

        users :: Handler (Set Account)
        users = liftIO $ query state QueryState

        score :: UUID -> ScoreUpdate -> Handler ()
        score uuid (ScoreUpdate newScore) = do
          users <- liftIO $ query state QueryState
          case filter ((==) uuid . uid) $ Set.toList users of
            [] -> return ()
            user:xs -> do
              liftIO $ update state (UpdateUser user (user { score = newScore }))
              return ()


api :: Proxy API
api = Proxy

app :: AcidState AccountsState -> Application
app acid = serve api (server acid)

someFunc :: IO ()
someFunc = putStrLn "someFunc"

-- TODO:
-- POST /register
-- GET /players
-- PUT /score/:id
-- WS loop endpoint

-- keep the state in ACID-state
