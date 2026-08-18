-- ============================================================================================================
-- _G.petBuildModel -- pet thumbnails for the Candy realm's panels (crates, trade, collection book).
-- ============================================================================================================
-- WHY THIS EXISTS. Every panel that draws a pet picture calls _G.petBuildModel. In realm 1 that comes from
-- PetFollow, and in Space from FtFClientBridge. Candy has PetFollow too -- but Candy has NO pet SERVER, so
-- PetFollow stalls waiting on remotes that never arrive and never reaches the line (2972) where it would
-- publish the builder. The symptom was every crate cell showing a paw placeholder instead of the pet, with:
--
--     [SkinCrate] _G.petBuildModel never appeared -- pet thumbnails stay as placeholders
--
-- Waiting longer would not have helped: the builder was never coming. So this is Space's approach instead --
-- a tiny standalone script whose ONLY job is to clone a template. It depends on nothing but ReplicatedStorage,
-- so it cannot be blocked by a pet system this realm does not have.
--
-- The templates are already here: FoodPetTemplates and DinoPetTemplates both build into ReplicatedStorage at
-- boot ("[DinoRealm FoodPetTemplates] all pet templates ready in ReplicatedStorage"). This only clones them.
--
-- If PetFollow ever does come up in this realm it publishes the same global later and simply wins; both
-- builders return an equivalent model, so which one answers does not matter.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Species -> the template FoodPetTemplates / DinoPetTemplates parent into ReplicatedStorage. Kept in step with
-- PetFollow's own PET_TEMPLATE_NAME; a species missing here just falls back to the placeholder, never errors.
local TEMPLATE_NAME = {
	-- food pets (FoodPetTemplates.server.luau)
	BeanBuddy        = "BeanBuddyTemplate",
	PizzaDragon      = "PizzaDragonTemplate",
	BroccoliPet      = "BroccoliBunnyTemplate",
	CoconutCrab      = "CoconutCrabTemplate",
	PopcornSheep     = "PopcornSheepTemplate",
	ButterDuck       = "ButterDuckTemplate",
	BurritoArmadillo = "BurritoArmadilloTemplate",
	SunflowerBee     = "SunflowerBeeTemplate",
	MapleFox         = "MapleFoxTemplate",
	FrostPenguin     = "FrostPenguinTemplate",
	BlossomBunny     = "BlossomBunnyTemplate",
	MoltenBean       = "MoltenBeanTemplate",
	VoidDragon       = "VoidDragonTemplate",
	PrismFox         = "PrismFoxTemplate",
	-- dino pets (DinoPetTemplates.server.luau)
	Stegosaurus      = "StegosaurusTemplate",
	Velociraptor     = "VelociraptorTemplate",
	Shark            = "SharkTemplate",
	Triceratops      = "TriceratopsTemplate",
	Spinosaurus      = "SpinosaurusTemplate",
	Tyrannosaurus    = "TyrannosaurusTemplate",
}

-- Only claim the global if nothing better already owns it -- PetFollow's builder is richer (it has client-side
-- fallbacks for species with no template), so if it ever does publish first, leave it alone.
if _G.petBuildModel then
	print("[PetModelBridge] _G.petBuildModel already published -- leaving it alone")
	return
end

_G.petBuildModel = function(petId)
	local tname = TEMPLATE_NAME[petId]
	if not tname then return nil end
	-- FindFirstChild, never WaitForChild: this runs inside the crate's preview worker, one cell per frame. A
	-- species whose template has not replicated yet must return nil IMMEDIATELY rather than stall the whole
	-- queue behind a multi-second wait per cell. The templates build within a few seconds of join, and the
	-- panel rebuilds whenever it is reopened, so a cell that misses early fills in on the next open.
	local template = ReplicatedStorage:FindFirstChild(tname)
	if not template or not template:IsA("Model") then return nil end
	local clone = template:Clone()
	clone.Parent = nil -- the caller parents it into its own ViewportFrame
	return clone
end

print("[PetModelBridge] ready -- _G.petBuildModel clones ReplicatedStorage pet templates (crate/trade thumbnails)")
