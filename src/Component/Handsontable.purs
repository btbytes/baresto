module Component.Handsontable where

import Prelude (Unit, ($), pure, show, (<>), bind, unit, (<$>), (>), const)
import Data.Array (length)
import Data.Foldable (for_)
import Data.Tuple (Tuple(Tuple))
import Data.Maybe (Maybe(Nothing, Just))
import DOM.HTML.Types (HTMLElement())

import Halogen (ComponentDSL, Eval, Render, Component, action, eventSource_, subscribe, liftEff', eventSource, modify, get, component)
import Halogen.HTML.Indexed as H
import Halogen.HTML.Properties.Indexed as P
import Handsontable (populateFromArray, handsontableNode, destroy) as Hot
import Handsontable.Types (Handsontable, ChangeSource(ChangeSpliceRow, ChangeSpliceCol, ChangePaste, ChangeAutofill, ChangeLoadData, ChangePopulateFromArray, ChangeEdit, ChangeEmpty, ChangeAlter), Direction(DirectionDown), PopulateMethod(Overwrite)) as Hot
import Handsontable.Hooks (onAfterRender, onAfterChange) as Hot
import Utils (getIndices, initClipboard, cls)
import Types (Metrix)
import Api.Schema.Table (Table(Table), YAxis(YAxisCustom, YAxisClosed))
import Lib.Table
import Lib.BusinessData (BusinessData, getCustomYMembersBySheet, getFactTable)

import Component.Handsontable.Options (tableOptions)
import Component.Handsontable.Utils (attachClickHandler, forceString, fromHotCoords, toHotCoords)

type State =
  { hotInstance :: Maybe (Hot.Handsontable String)
  , hotRoot :: Maybe HTMLElement
  }

initialState :: State
initialState =
  { hotInstance: Nothing
  , hotRoot: Nothing
  }

type Changes = Array (Tuple Coord String)

data Query a
  = Init HTMLElement a
  | Edit Changes a
  | AddRow a
  | DeleteRow Int a
  | Rebuild S Table BusinessData a

handsontable :: S -> Table -> BusinessData -> Component State Query Metrix
handsontable propS propTable propBusinessData = component render eval
  where

    render :: Render State Query
    render = const $ H.div
      [ cls "hotContainer"
      , P.initializer \el -> action (Init el)
      ] []

    eval :: Eval Query State Query Metrix
    eval (Init el next) = do
      modify _{ hotRoot = Just el }
      build propS propTable propBusinessData
      pure next

    eval (Edit changes next) = do
      pure next

    eval (AddRow next) = do
      pure next

    eval (DeleteRow index next) = do
      pure next

    eval (Rebuild s table bd next) = do
      build s table bd
      pure next

build :: S -> Table -> BusinessData -> ComponentDSL State Query Metrix Unit
build s table@(Table tbl) bd = do
  st <- get
  case st.hotRoot of
    Nothing -> pure unit
    Just el -> do
      case st.hotInstance of
        Nothing -> pure unit
        Just hot -> liftEff' $ Hot.destroy hot

      hot <- liftEff' $ Hot.handsontableNode el (tableOptions s table bd)
      modify _{ hotInstance = Just hot }

      case getFactTable s table bd of
        Just vals | length vals > 0 -> do
          liftEff' $ Hot.populateFromArray (toHotCoords table 0 0) vals Nothing Nothing Hot.Overwrite Hot.DirectionDown [] hot
          pure unit
        _ -> pure unit

      subscribe $ eventSource (\cb -> Hot.onAfterChange hot (\c s -> cb (Tuple c s))) \(Tuple changes source) -> do
        let procChange change = let coord = fromHotCoords table change.col change.row
                                in  Tuple (Coord (C coord.col) (R coord.row) s) (forceString change.new)
            go = pure $ action $ Edit $ procChange <$> changes
            no = pure $ action $ Edit []
        case source of
          Hot.ChangeAlter             -> no
          Hot.ChangeEmpty             -> no
          Hot.ChangeEdit              -> go
          Hot.ChangePopulateFromArray -> no
          Hot.ChangeLoadData          -> no
          Hot.ChangeAutofill          -> go
          Hot.ChangePaste             -> go
          Hot.ChangeSpliceCol         -> no
          Hot.ChangeSpliceRow         -> no

      case tbl.tableYAxis of
        YAxisClosed _ _ -> pure unit
        YAxisCustom axId _ -> do
          liftEff' $ Hot.onAfterRender hot \_ -> initClipboard ".clipboard"
          subscribe $ eventSource_ (attachClickHandler hot "#newCustomY") do
            pure $ action AddRow
          for_ (getIndices $ getCustomYMembersBySheet axId s table bd) \i ->
            subscribe $ eventSource_ (attachClickHandler hot ("#delCustomY" <> show i)) do
              pure $ action $ DeleteRow i

  -- TODO: adjust resize

-- resize :: Eff _ Unit
-- resize = do
--   body <- DOM.document DOM.globalWindow >>= DOM.body
--   w <- DOM.innerWidth DOM.globalWindow
--   h <- DOM.innerHeight DOM.globalWindow
--   els <- DOM.nodeListToArray =<< DOM.querySelectorAll ".hotContainer" body
--   for_ els \el -> do
--     DOM.setStyleAttr "width" (show (w - 20.0) <> "px") el
--     DOM.setStyleAttr "height" (show (h - 300.0) <> "px") el
