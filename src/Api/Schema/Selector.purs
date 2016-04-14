module Api.Schema.Selector where

import Prelude (pure, ($), (<*>), (<$>), bind)
import Data.Foreign.Class (class IsForeign, readProp)
import Optic.Core (LensP, lens, (..))
import Types (ModuleId, ConceptualModuleId, TaxonomyId, FrameworkId)

newtype Framework = Framework
  { frameworkId :: FrameworkId
  , frameworkLabel :: String
  , taxonomies :: Array Taxonomy
  }

_Framework :: LensP Framework _
_Framework = lens (\(Framework r) -> r) (\_ r -> Framework r)

_frameworkId :: LensP Framework FrameworkId
_frameworkId = _Framework .. lens _.frameworkId _{ frameworkId = _ }

_frameworkLabel :: LensP Framework String
_frameworkLabel = _Framework .. lens _.frameworkLabel _{ frameworkLabel = _ }

_taxonomies :: LensP Framework (Array Taxonomy)
_taxonomies = _Framework .. lens _.taxonomies _{ taxonomies = _ }

instance isForeignFramework :: IsForeign Framework where
  read json = do
    frm <- { frameworkId: _, frameworkLabel: _, taxonomies: _ }
      <$> readProp "id"         json
      <*> readProp "label"      json
      <*> readProp "taxonomies" json
    pure $ Framework frm

newtype Taxonomy = Taxonomy
  { taxonomyId :: TaxonomyId
  , taxonomyLabel :: String
  , conceptualModules :: Array ConceptualModule
  }

_Taxonomy :: LensP Taxonomy _
_Taxonomy = lens (\(Taxonomy r) -> r) (\_ r -> Taxonomy r)

_taxonomyId :: LensP Taxonomy TaxonomyId
_taxonomyId = _Taxonomy .. lens _.taxonomyId _{taxonomyId = _ }

_taxonomyLabel :: LensP Taxonomy String
_taxonomyLabel = _Taxonomy .. lens _.taxonomyLabel _{ taxonomyLabel = _ }

_conceptualModules :: LensP Taxonomy (Array ConceptualModule)
_conceptualModules = _Taxonomy .. lens _.conceptualModules _{ conceptualModules = _ }

instance isForeignTaxonomy :: IsForeign Taxonomy where
  read json = do
    tax <- { taxonomyId: _, taxonomyLabel: _, conceptualModules: _ }
      <$> readProp "id"       json
      <*> readProp "label"    json
      <*> readProp "concepts" json
    pure $ Taxonomy tax

newtype ConceptualModule = ConceptualModule
  { conceptId      :: ConceptualModuleId
  , conceptLabel   :: String
  , conceptAllowed :: Boolean
  , moduleEntries  :: Array ModuleEntry
  }

_ConceptualModule :: LensP ConceptualModule _
_ConceptualModule = lens (\(ConceptualModule r) -> r) (\_ r -> ConceptualModule r)

_conceptId :: LensP ConceptualModule ConceptualModuleId
_conceptId = _ConceptualModule .. lens _.conceptId _{conceptId = _ }

_conceptLabel :: LensP ConceptualModule String
_conceptLabel = _ConceptualModule .. lens _.conceptLabel _{ conceptLabel = _ }

_conceptAllowed :: LensP ConceptualModule Boolean
_conceptAllowed = _ConceptualModule .. lens _.conceptAllowed _{ conceptAllowed = _ }

_moduleEntries :: LensP ConceptualModule (Array ModuleEntry)
_moduleEntries = _ConceptualModule .. lens _.moduleEntries _{ moduleEntries = _ }

instance isForeignConceptualModule :: IsForeign ConceptualModule where
  read json = do
    con <- { conceptId: _
           , conceptLabel: _
           , conceptAllowed: _
           , moduleEntries: _
           }
      <$> readProp "id"      json
      <*> readProp "label"   json
      <*> readProp "allowed" json
      <*> readProp "modules" json
    pure $ ConceptualModule con

newtype ModuleEntry = ModuleEntry
  { moduleEntryId :: ModuleId
  , moduleEntryLabel :: String
  }

instance isForeignModuleEntry :: IsForeign ModuleEntry where
  read json = do
    mod <- { moduleEntryId: _, moduleEntryLabel: _ }
      <$> readProp "id" json
      <*> readProp "label" json
    pure $ ModuleEntry mod
