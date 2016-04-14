module Component.FileSelector where

import Prelude (class Ord, class Eq, ($), (<<<), (/=), flip, (#), (==), (&&), (<$>), (<>), show, unit, pure, bind, not, const, (<#>))

import Control.Monad (when)
import Control.Monad.Writer (tell, execWriter)

import Data.Array (length, filter, snoc, concat, cons, last)
import Data.List (fromList)
import Data.Map as M
import Data.Maybe (Maybe(Nothing, Just), fromMaybe, maybe)
import Data.Foldable (foldl, foldr, for_, find)
import Data.Tuple (Tuple(Tuple))
import Data.List (toList)
import Data.Functor.Coproduct (Coproduct())
import Data.Generic (class Generic, gEq, gCompare)

import Optic.Core (LensP, (%~), (..), lens, (.~), view)
import Optic.At (at)
import Optic.Refractor.Prism (_Just)
import Optic.Iso (non)

import Halogen (Peek, EvalParent, RenderParent, Component, ParentHTML, InstalledState, ChildF(ChildF), parentComponent', modify, liftEff', liftH, action)
import Halogen.HTML.Indexed as H
import Halogen.HTML.Properties.Indexed as P
import Halogen.HTML.Events.Indexed as E

import Component.File as F
import Component.Common (modal, toolButton)

import Api (deleteFile, apiCallParent, listFiles, uploadBaresto, uploadXbrl, listFrameworks)
import Api.Schema.Selector (ConceptualModule(ConceptualModule), Framework(Framework), ModuleEntry(ModuleEntry), Taxonomy(Taxonomy), _taxonomyId)
import Api.Schema.File (File(File))
import Api.Schema.Import (Warning(Warning), XbrlImportConf(XbrlImportConf))

import Types (TaxonomyId, Metrix, ConceptualModuleId, FrameworkId, ModuleId, UpdateId, FileId)
import Utils (cls, readId, getInputFileList)

data FileSlot = FileSlot FileId

derive instance genericFileSlot :: Generic FileSlot
instance eqFileSlot :: Eq FileSlot where eq = gEq
instance ordFileSlot :: Ord FileSlot where compare = gCompare

data SelectedNode
  = SelectedNone
  | SelectedFramework FrameworkId
  | SelectedTaxonomy FrameworkId TaxonomyId
  | SelectedConceptualModule TaxonomyId ConceptualModuleId
  | SelectedModule ModuleId

type StateInfo =
  { files :: Array File
  , frameworks :: Array Framework
  , openFramework :: M.Map FrameworkId Boolean
  , selectedTaxonomy :: M.Map FrameworkId TaxonomyId
  , openConceptualModule :: M.Map (Tuple TaxonomyId ConceptualModuleId) Boolean
  , selectedNode :: SelectedNode
  , newFileName :: String
  , xbrlImportResponse :: Maybe XbrlImportConf
  }

type State = Maybe StateInfo

_files :: LensP StateInfo (Array File)
_files = lens _.files _{ files = _ }

_openFramework :: LensP StateInfo (M.Map FrameworkId Boolean)
_openFramework = lens _.openFramework _{ openFramework = _ }

_selectedTaxonomy :: LensP StateInfo (M.Map FrameworkId TaxonomyId)
_selectedTaxonomy = lens _.selectedTaxonomy _{ selectedTaxonomy = _ }

_openConceptualModule :: LensP StateInfo (M.Map (Tuple TaxonomyId ConceptualModuleId) Boolean)
_openConceptualModule = lens _.openConceptualModule _{ openConceptualModule = _ }

_selectedNode :: LensP StateInfo SelectedNode
_selectedNode = lens _.selectedNode _{ selectedNode = _ }

_newFileName :: LensP StateInfo String
_newFileName = lens _.newFileName _{ newFileName = _ }

initialState :: State
initialState = Nothing

data Query a
  = Init a
  | UploadXbrl a
  | UploadXbrlCloseModal a
  | UploadXbrlOpenFile UpdateId a
  | UploadBaresto a
  | SetNewFileName String a
  | CreateFile ModuleId String a
  | ClickAll a
  | ClickFramework FrameworkId a
  | ClickTaxonomy FrameworkId TaxonomyId a
  | ClickConceptualModule TaxonomyId ConceptualModuleId a
  | ClickModule ModuleId a
  | ToggleFrameworkOpen FrameworkId a
  | SelectTaxonomy FrameworkId TaxonomyId a
  | ToggleConceptualModuleOpen TaxonomyId ConceptualModuleId a

type StateP = InstalledState State F.State Query F.Query Metrix FileSlot
type QueryP = Coproduct Query (ChildF FileSlot F.Query)
type ComponentHTMLP = ParentHTML F.State Query F.Query Metrix FileSlot

selector :: Component StateP QueryP Metrix
selector = parentComponent' render eval peek
  where

    render :: RenderParent State F.State Query F.Query Metrix FileSlot
    render st = H.div [ cls "container" ] $
      -- TODO report halogen issue about initializer
      [ H.span [ P.initializer \_ -> action Init ] []
      , H.div [ cls "toolbar" ] $
        [ H.div [ cls "tool tooldim-choose-file" ]
          [ H.p_
            [ H.text "Import file:" ]
          , H.input
            [ P.inputType P.InputFile
            , P.id_ "importFile"
            ]
          ]
        , toolButton "XBRL" "octicon octicon-arrow-up" "import-xbrl" UploadXbrl
        , toolButton "Baresto File" "octicon octicon-arrow-up" "import-baresto" UploadBaresto
        , H.div [ cls "toolsep tooldim-sep-xbrl" ] []
        , H.div [ cls "toolsep tooldim-sep-create" ] []
        ] <> (
          case st of
            Just st' -> case st'.selectedNode of
              SelectedModule mId ->
                [ H.div [ cls "tool tooldim-name-file" ]
                  [ H.p_
                    [ H.text "Name for new file:"
                    ]
                  , H.input
                    [ E.onValueChange $ E.input SetNewFileName
                    , P.value st'.newFileName
                    ]
                  ]
                , toolButton "Create" "octicon octicon-file-text" "create"
                             (CreateFile mId st'.newFileName)
                ]
              _ ->
                [ H.div [ cls "tool tooldim-name-file" ]
                  [ H.p_
                    [ H.text "Select a module to create a new file." ]
                  ]
                , H.div [ cls "tool tooldim-create" ] []
                ]
            _ ->
              []
        )
      , H.div [ cls "content" ] $ case st of
          Just st' ->
            [ renderFrameworks st'
            , renderFiles st'
            , renderXbrlImportResponse st'.xbrlImportResponse
            ]
          Nothing ->
            [ H.text ""
            ]
      ]

    eval :: EvalParent Query State F.State Query F.Query Metrix FileSlot
    eval (Init next) = do
      apiCallParent listFiles \files -> do
        apiCallParent listFrameworks \frameworks -> do
          let taxMap = frameworks <#> \(Framework f) ->
                Tuple f.frameworkId $ maybe 0 (view _taxonomyId) (last f.taxonomies)
          modify $ const $ Just
            { files: files
            , frameworks: frameworks
            , openFramework: (M.empty :: M.Map FrameworkId Boolean)
            , selectedTaxonomy: M.fromList $ toList taxMap
            , openConceptualModule: (M.empty :: M.Map (Tuple TaxonomyId ConceptualModuleId) Boolean)
            , selectedNode: SelectedNone
            , newFileName: ""
            , xbrlImportResponse: Nothing
            }
          pure unit
      pure next

    eval (UploadXbrl next) = do
      mFiles <- liftH $ liftEff' $ getInputFileList "importFile"
      case mFiles of
        Nothing -> pure unit
        Just files -> apiCallParent (uploadXbrl files) \resp ->
          modify $ _Just %~ _{ xbrlImportResponse = Just resp }
      pure next

    eval (UploadBaresto next) = do
      mFiles <- liftH $ liftEff' $ getInputFileList "importFile"
      case mFiles of
        Nothing -> pure unit
        Just files -> apiCallParent (uploadBaresto files) \file ->
          modify $ _Just .. _files %~ cons file
      pure next

    eval (UploadXbrlOpenFile _ next) =
      pure next

    eval (UploadXbrlCloseModal next) = do
      modify $ _Just %~ _{ xbrlImportResponse = Nothing }
      apiCallParent listFiles \files ->
        modify $ _Just .. _files .~ files
      pure next

    eval (SetNewFileName name next) = do
      modify $ _Just .. _newFileName .~ name
      pure next

    eval (CreateFile _ _ next) =
      pure next

    eval (ClickAll next) = do
      modify $ _Just .. _selectedNode .~ SelectedNone
      pure next

    eval (ClickFramework f next) = do
      modify $ _Just .. _selectedNode .~ SelectedFramework f
      pure next

    eval (ClickTaxonomy f t next) = do
      modify $ _Just .. _selectedNode .~ SelectedTaxonomy f t
      pure next

    eval (ClickConceptualModule t c next) = do
      modify $ _Just .. _selectedNode .~ SelectedConceptualModule t c
      pure next

    eval (ClickModule m next) = do
      modify $ _Just .. _selectedNode .~ SelectedModule m
      pure next

    eval (ToggleFrameworkOpen f next) = do
      modify $ _Just .. _openFramework .. at f .. non true %~ (not :: Boolean -> Boolean)
      pure next

    eval (SelectTaxonomy f t next) = do
      modify $ _Just .. _selectedTaxonomy .. at f .~ Just t
      modify $ _Just .. _selectedNode .~ SelectedTaxonomy f t
      pure next

    eval (ToggleConceptualModuleOpen t c next) = do
      modify $ _Just .. _openConceptualModule .. at (Tuple t c) .. non true %~ (not :: Boolean -> Boolean)
      pure next

    peek :: Peek (ChildF FileSlot F.Query) State F.State Query F.Query Metrix FileSlot
    peek (ChildF (FileSlot fileId) q) = case q of
      F.DeleteFileYes _ ->
        apiCallParent (deleteFile fileId) \_ -> do
          modify $ _Just .. _files %~ filter (\(File f) -> f.fileId /= fileId)
          pure unit
      _ -> pure unit

renderXbrlImportResponse :: Maybe XbrlImportConf -> ComponentHTMLP
renderXbrlImportResponse resp = case resp of
    Nothing -> H.div_ []
    Just (XbrlImportConf conf) -> modal "Import XBRL"
      [ H.p_ [ H.text "XBRL file successfully imported!" ]
      , H.h2_ [ H.text "Warnings:" ]
      , H.ul_ $ warning <$> conf.warnings
      ]
      [ H.button
        [ E.onClick $ E.input_ UploadXbrlCloseModal ]
        [ H.text "Close" ]
      , H.button
        [ E.onClick $ E.input_ (UploadXbrlOpenFile conf.updateId) ]
        [ H.text "Open File" ]
      ]
  where
    warning (Warning w) = H.li_
      [ H.b_ [ H.text "Message: " ]
      , H.text w.message
      , H.br_
      , H.b_ [ H.text "Context: " ]
      , H.text w.context
      ]

renderFrameworks :: StateInfo -> ComponentHTMLP
renderFrameworks st = H.div [ cls "panel-frameworklist" ]
    [ H.div [ cls "frame" ]
      [ H.ul [ cls "frameworks" ] $
        [ H.li
          [ cls $ "all" <> if selectedAll then " selected" else "" ]
          [ H.span
            [ cls "label"
            , E.onClick $ E.input_ $ ClickAll
            ]
            [ H.text "All"
            ]
          ]
        ] <> (concat $ renderFramework <$> st.frameworks)
      ]
    ]
  where
    selectedAll = case st.selectedNode of
      SelectedNone -> true
      _            -> false

    renderFramework :: Framework -> Array ComponentHTMLP
    renderFramework framework@(Framework f) =
        [ H.li
          [ cls $ "framework" <> if selected then " selected" else "" ]
          [ H.span
            [ cls $ "octicon octicon-chevron-" <> if open then "down" else "right"
            , E.onClick $ E.input_ (ToggleFrameworkOpen f.frameworkId)
            ] []
          , H.span
            [ cls "label"
            , E.onClick $ E.input_ (ClickFramework f.frameworkId)
            ]
            [ H.text f.frameworkLabel
            ]
          ]
        ] <> if open then renderTaxonomies framework else []
      where
        open = fromMaybe true $ M.lookup f.frameworkId st.openFramework
        selected = case st.selectedNode of
          SelectedFramework fId -> fId == f.frameworkId
          _                     -> false

    renderTaxonomies :: Framework -> Array ComponentHTMLP
    renderTaxonomies (Framework f) =
        [ H.li
          [ cls $ "taxonomy" <> if selected then " selected" else "" ]
          [ H.span
            [ cls "label"
            , E.onClick $ E.input_ (ClickTaxonomy f.frameworkId currentTaxonomyId)
            ]
            [ H.text "Taxonomy: "
            , H.select
              [ E.onValueChange $ E.input $ SelectTaxonomy f.frameworkId <<< readId
              ] $ taxonomyOption <$> f.taxonomies
            ]
          ]
        ] <> (
          case currentTaxonomy of
            Just (Taxonomy t) ->
              concat $ renderConceptualModule t.taxonomyId <$> t.conceptualModules
            Nothing ->
              []
        )
      where
        selected = case st.selectedNode of
          SelectedTaxonomy fId _ -> fId == f.frameworkId
          _                      -> false

        currentTaxonomyId = fromMaybe 0 $ M.lookup f.frameworkId st.selectedTaxonomy
        currentTaxonomy = find (\(Taxonomy t) -> t.taxonomyId == currentTaxonomyId) f.taxonomies

        taxonomyOption (Taxonomy t) = H.option
          [ P.selected $ t.taxonomyId == currentTaxonomyId
          , P.value $ show t.taxonomyId
          ]
          [ H.text t.taxonomyLabel
          ]

    renderConceptualModule :: TaxonomyId -> ConceptualModule -> Array ComponentHTMLP
    renderConceptualModule tId (ConceptualModule c) = if c.conceptAllowed
        then (
          [ H.li
            [ cls $ "conceptualModule" <> if selected then " selected" else "" ]
            [ H.span
              [ cls $ "octicon octicon-chevron-" <> if open then "down" else "right"
              , E.onClick $ E.input_ (ToggleConceptualModuleOpen tId c.conceptId)
              ] []
            , H.span
              [ cls "label"
              , E.onClick $ E.input_ (ClickConceptualModule tId c.conceptId)
              ]
              [ H.text c.conceptLabel
              ]
            ]
          ] <> if open then renderModuleEntry <$> c.moduleEntries else []
        )
        else (
          [ H.li
            [ cls "conceptualModule disabled" ]
            [ H.span
              [ cls "label"
              , P.title "Not available in the current licence."
              ]
              [ H.text c.conceptLabel ]
            ]
          ]
        )
      where
        open = fromMaybe true $ M.lookup (Tuple tId c.conceptId) st.openConceptualModule
        selected = case st.selectedNode of
          SelectedConceptualModule tId' cId -> tId' == tId && cId == c.conceptId
          _                                 -> false

    renderModuleEntry :: ModuleEntry -> ComponentHTMLP
    renderModuleEntry (ModuleEntry m) = H.li
        [ cls $ "module" <> if selected then " selected" else "" ]
        [ H.span
          [ cls $ "octicon octicon-package"
          ] []
        , H.span
          [ cls "label"
          , E.onClick $ E.input_ (ClickModule m.moduleEntryId)
          ]
          [ H.text m.moduleEntryLabel
          ]
        ]
      where
        selected = case st.selectedNode of
          SelectedModule mId -> mId == m.moduleEntryId
          _                  -> false

renderFiles :: StateInfo -> ComponentHTMLP
renderFiles st = H.div [ cls "panel-filelist" ]
    [ H.div [ cls "frame" ]
      [ H.ul [ cls "files" ] $ concat $ mod <$> arrangeFiles st
      ]
    ]
  where
    mod (ModWithFiles taxLabel (ModuleEntry m) files) =
        [ H.li [ cls "module" ]
          [ H.span
            [ cls "label octicon octicon-package"
            ] []
          , H.span
            [ cls "label"
            ]
            [ H.text $ taxLabel <> " — " <> m.moduleEntryLabel
            ]
          ]
        ] <> (renderFile <$> files)
      where
        renderFile file@(File f) =
          H.slot (FileSlot f.fileId) \_ ->
            { component: F.file
            , initialState: F.initialState file
            }

--

getModules :: StateInfo -> Array (Tuple String ModuleEntry)
getModules st = execWriter $
  for_ st.frameworks \(Framework f) ->
    for_ f.taxonomies \(Taxonomy t) ->
      for_ t.conceptualModules \(ConceptualModule c) ->
        for_ c.moduleEntries \(m@(ModuleEntry m')) ->
          let add = tell [Tuple t.taxonomyLabel m]
          in  case st.selectedNode of
                SelectedNone ->
                  add
                SelectedFramework fId ->
                  when (fId == f.frameworkId) $ add
                SelectedTaxonomy _ tId ->
                  when (tId == t.taxonomyId) $ add
                SelectedConceptualModule tId cId ->
                  when (tId == t.taxonomyId && cId == c.conceptId) $ add
                SelectedModule mId ->
                  when (mId == m'.moduleEntryId) $ add

data ModWithFiles = ModWithFiles String ModuleEntry (Array File)

_modFiles :: LensP ModWithFiles (Array File)
_modFiles = lens (\(ModWithFiles _ _ fs) -> fs) (\(ModWithFiles t m _) fs -> ModWithFiles t m fs)

arrangeFiles :: StateInfo -> Array ModWithFiles
arrangeFiles st = pruneEmpty <<< fromList <<< M.values <<< sortFiles <<< makeMap <<< getModules $ st
  where
    makeMap = foldr (\(Tuple tax (mod@(ModuleEntry m))) -> M.insert m.moduleEntryId (ModWithFiles tax mod [])) M.empty

    sortFiles modEntries = foldl go modEntries st.files
    go m file@(File f) = m # at' f.fileModuleId .. _Just .. _modFiles %~ flip snoc file

    pruneEmpty = filter (\(ModWithFiles _ _ files) -> length files /= 0)

    at' :: forall k v. (Ord k) => k -> LensP (M.Map k v) (Maybe v)
    at' k = at k
