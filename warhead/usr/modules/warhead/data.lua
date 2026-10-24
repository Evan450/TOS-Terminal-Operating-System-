












local D = {}

D.SOURCE = "NTM-CE 1.12.2-2.5.0.5"







D.CONFIG = {
  gadgetRadius    = 150,  boyRadius       = 120,  manRadius       = 175,
  mikeRadius      = 250,  tsarRadius      = 500,  prototypeRadius = 150,
  fleijaRadius    = 50,   missileRadius   = 100,  mirvRadius      = 70,
  aSchrabRadius   = 20,   soliniumRadius  = 150,  n2Radius        = 200,
  maxCustomTNTRadius   = 150, maxCustomNukeRadius  = 200,
  maxCustomHydroRadius = 350, maxCustomDirtyRadius = 200,
  maxCustomBaleRadius  = 350, maxCustomSchrabRadius = 250,
  maxCustomSolRadius   = 350, maxCustomEuphLvl     = 20,
  falloutRange    = 100,  
  disableNuclear  = false, 
  explosionAlgorithm = 2, 
}

D.CONFIG_BOOL = { disableNuclear = true }




D.STAGES = { "TNT", "NUKE", "HYDRO", "BALE", "DIRTY", "SCHRAB", "SOL", "EUPH" }
D.STAGE_NAME = {
  TNT = "TNT", NUKE = "Nuclear", HYDRO = "Hydrogen", BALE = "Balefire",
  DIRTY = "Salted", SCHRAB = "Schrabidium", SOL = "Solinium", EUPH = "Anti Mass",
}


D.STAGE_CAP = {
  TNT = "maxCustomTNTRadius", NUKE = "maxCustomNukeRadius",
  HYDRO = "maxCustomHydroRadius", BALE = "maxCustomBaleRadius",
  DIRTY = "maxCustomDirtyRadius", SCHRAB = "maxCustomSchrabRadius",
  SOL = "maxCustomSolRadius", EUPH = "maxCustomEuphLvl",
}












local function I(key, id, dmg, name, stage, v, m)
  return { key = key, id = id, dmg = dmg, name = name, stage = stage, v = v, m = m or false }
end
D.INGREDIENTS = {
  I("gunpowder",       "minecraft:gunpowder",      nil, "Gunpowder",                    "TNT", 0.8),
  I("tnt",             "minecraft:tnt",            nil, "TNT (block)",                  "TNT", 4.0),
  I("det_cord",        "hbm:det_cord",             nil, "Det Cord",                     "TNT", 1.5),
  I("semtex",          "hbm:ingot_semtex",         nil, "Bar of Semtex",                "TNT", 8.0),
  I("c4",              "hbm:ingot_c4",             nil, "Bar of Composition C-4",       "TNT", 10.0),
  I("dynamite",        "hbm:ball_dynamite",        nil, "Dynamite",                     "TNT", 4.0),
  I("ball_tnt",        "hbm:ball_tnt",             nil, "TNT (HBM item)",               "TNT", 6.0),
  I("det_charge",      "hbm:det_charge",           nil, "Explosive Charge",             "TNT", 15.0),
  I("canister_diesel", "hbm:canister_fuel",        20,  "Diesel Canister",              "TNT", 0.5),
  I("napalm",          "hbm:canister_napalm",      nil, "Napalm B",                     "TNT", 2.5),
  I("canister_kerosene", "hbm:canister_fuel",      22,  "Kerosene Canister",            "TNT", 0.8),
  I("red_barrel",      "hbm:red_barrel",           nil, "Explosive Barrel",             "TNT", 2.5),
  I("pink_barrel",     "hbm:pink_barrel",          nil, "Kerosene Barrel",              "TNT", 4.0),
  I("custom_tnt",      "hbm:custom_tnt",           nil, "Custom Nuke Explosive Charge", "TNT", 10.0),
  I("n2_charge",       "hbm:n2_charge",            nil, "Large Explosive Charge",       "TNT", 1.25, true),
  I("redstone",        "minecraft:redstone",       nil, "Redstone",                     "TNT", 1.05, true),
  I("redstone_block",  "minecraft:redstone_block", nil, "Block of Redstone",            "TNT", 1.5, true),

  I("u235",            "hbm:ingot_u235",           nil, "Uranium-235 Ingot",            "NUKE", 15.0),
  I("pu239",           "hbm:ingot_pu239",          nil, "Plutonium-239 Ingot",          "NUKE", 25.0),
  I("neptunium",       "hbm:ingot_neptunium",      nil, "Neptunium Ingot",              "NUKE", 30.0),
  I("nugget_u235",     "hbm:nugget_u235",          nil, "Uranium-235 Nugget",           "NUKE", 1.5),
  I("nugget_pu239",    "hbm:nugget_pu239",         nil, "Plutonium-239 Nugget",         "NUKE", 2.5),
  I("nugget_neptunium", "hbm:nugget_neptunium",    nil, "Neptunium Nugget",             "NUKE", 3.0),
  I("powder_neptunium", "hbm:powder_neptunium",    nil, "Neptunium Powder",             "NUKE", 30.0),
  I("custom_nuke",     "hbm:custom_nuke",          nil, "Custom Nuke Nuclear Rod",      "NUKE", 30.0),
  I("uranium",         "hbm:ingot_uranium",        nil, "Uranium Ingot",                "NUKE", 1.05, true),
  I("plutonium",       "hbm:ingot_plutonium",      nil, "Plutonium Ingot",              "NUKE", 1.15, true),
  I("u238",            "hbm:ingot_u238",           nil, "Uranium-238 Ingot",            "NUKE", 1.1, true),
  I("pu238",           "hbm:ingot_pu238",          nil, "Plutonium-238 Ingot",          "NUKE", 1.15, true),
  I("nugget_uranium",  "hbm:nugget_uranium",       nil, "Uranium Nugget",               "NUKE", 1.005, true),
  I("nugget_plutonium", "hbm:nugget_plutonium",    nil, "Plutonium Nugget",             "NUKE", 1.15, true),
  I("nugget_u238",     "hbm:nugget_u238",          nil, "Uranium-238 Nugget",           "NUKE", 1.01, true),
  I("nugget_pu238",    "hbm:nugget_pu238",         nil, "Plutonium-238 Nugget",         "NUKE", 1.015, true),
  I("powder_uranium",  "hbm:powder_uranium",       nil, "Uranium Powder",               "NUKE", 1.05, true),
  I("powder_plutonium", "hbm:powder_plutonium",    nil, "Plutonium Powder",             "NUKE", 1.15, true),

  I("cell_deuterium",  "hbm:cell",                 8,   "Deuterium Cell",               "HYDRO", 20.0),
  I("cell_tritium",    "hbm:cell",                 9,   "Tritium Cell",                 "HYDRO", 30.0),
  I("lithium",         "hbm:lithium",              nil, "Lithium Cube",                 "HYDRO", 20.0),
  I("td_cake",         "hbm:tritium_deuterium_cake", nil, "Tritium-Deuterium-Cake",     "HYDRO", 200.0),
  I("custom_hydro",    "hbm:custom_hydro",         nil, "Custom Nuke Hydrogen Rod",     "HYDRO", 30.0),

  I("cell_antimatter", "hbm:cell",                 33,  "Antimatter Cell",              "BALE", 5.0),
  I("custom_amat",     "hbm:custom_amat",          nil, "Custom Nuke Antimatter Rod",   "BALE", 15.0),
  I("balefire_shard",  "hbm:egg_balefire_shard",   nil, "Balefire Shard",               "BALE", 15.0),
  I("balefire_egg",    "hbm:egg_balefire",         nil, "Balefire Egg",                 "BALE", 150.0),

  I("tungsten",        "hbm:ingot_tungsten",       nil, "Tungsten Ingot",               "DIRTY", 1.0),
  I("custom_dirty",    "hbm:custom_dirty",         nil, "Custom Nuke Dirty Rod",        "DIRTY", 10.0),
  I("pu240",           "hbm:ingot_pu240",          nil, "Plutonium-240 Ingot",          "DIRTY", 1.05, true),
  I("nuclear_waste",   "hbm:nuclear_waste",        nil, "Nuclear Waste",                "DIRTY", 1.025, true),
  I("block_waste",     "hbm:block_waste",          nil, "Block of Nuclear Waste",       "DIRTY", 1.25, true),
  I("yellow_barrel",   "hbm:yellow_barrel",        nil, "Radioactive Barrel",           "DIRTY", 1.2, true),

  I("schrabidium",     "hbm:ingot_schrabidium",    nil, "Schrabidium Ingot",            "SCHRAB", 5.0),
  I("block_schrabidium", "hbm:block_schrabidium",  nil, "Block of Schrabidium",         "SCHRAB", 50.0),
  I("nugget_schrabidium", "hbm:nugget_schrabidium", nil, "Schrabidium Nugget",          "SCHRAB", 0.5),
  I("powder_schrabidium", "hbm:powder_schrabidium", nil, "Schrabidium Powder",          "SCHRAB", 5.0),
  I("cell_sas3",       "hbm:cell",                 31,  "SAS3 Cell",                    "SCHRAB", 7.5),
  I("cell_aschrab",    "hbm:cell",                 34,  "Antischrabidium Cell",         "SCHRAB", 15.0),
  I("custom_schrab",   "hbm:custom_schrab",        nil, "Custom Nuke Schrabidium Rod",  "SCHRAB", 15.0),

  I("solinium_core",   "hbm:solinium_core",        nil, "Semi-Stable Solinium Core",    "SOL", 20.0),
  I("nugget_solinium", "hbm:nugget_solinium",      nil, "Solinium Nugget",              "SOL", 0.5),
  I("solinium",        "hbm:ingot_solinium",       nil, "Solinium Ingot",               "SOL", 5.0),
  I("billet_solinium", "hbm:billet_solinium",      nil, "Solinium Billet",              "SOL", 3.0),
  I("block_solinium",  "hbm:block_solinium",       nil, "Block of Solinium",            "SOL", 50.0),
  I("custom_sol",      "hbm:custom_sol",           nil, "Custom Nuke Solinium Rod",     "SOL", 15.0),

  I("nugget_euphemium", "hbm:nugget_euphemium",    nil, "Euphemium Nugget",             "EUPH", 1.0),
  I("euphemium",       "hbm:ingot_euphemium",      nil, "Euphemium Ingot",              "EUPH", 1.0),
}



D.DROP_UPGRADE = { key = "custom_fall", id = "hbm:custom_fall", name = "Custom Nuke Drop Upgrade" }
D.CUSTOM_SLOTS = 27







local LENS1 = "hbm:gadget_explosive8"   
local LENS2 = "hbm:man_explosive8"      
D.PART_NAME = {
  ["hbm:gadget_wireing"] = "Wiring", [LENS1] = "Array of First-Generation High-Explosive Lenses",
  ["hbm:gadget_core"] = "Large Plutonium Core",
  ["hbm:boy_shielding"] = "Neutron Shielding", ["hbm:boy_target"] = "Subcritical U235 Target",
  ["hbm:boy_bullet"] = "U235 Projectile", ["hbm:boy_propellant"] = "Propellant",
  ["hbm:boy_igniter"] = "Bomb Igniter",
  ["hbm:man_igniter"] = "Bomb Firing Unit", ["hbm:man_core"] = "Plutonium Core",
  [LENS2] = "Bundle of Implosion Propellant",
  ["hbm:mike_core"] = "Uranium Coated Deuterium Tank", ["hbm:mike_deut"] = "Deuterium Tank",
  ["hbm:mike_cooling_unit"] = "Deuterium Cooling Unit", ["hbm:tsar_core"] = "Tsar Bomba Core",
  ["hbm:cell#31"] = "SAS3 Cell",
  ["hbm:rod_quad#14"] = "Quad Rod (Uranium)", ["hbm:rod_quad#13"] = "Quad Rod (Lead)",
  ["hbm:rod_quad#7"] = "Quad Rod (Neptunium-237)",
  ["hbm:fleija_igniter"] = "Pulse Igniter", ["hbm:fleija_propellant"] = "Schrabidium Propellant",
  ["hbm:fleija_core"] = "F.L.E.I.J.A. Uranium 235 Charge",
  ["hbm:solinium_igniter"] = "SOL Pulse Igniter", ["hbm:solinium_propellant"] = "SOL Compression Charge",
  ["hbm:solinium_core"] = "Semi-Stable Solinium Core",
  ["hbm:n2_charge"] = "Large Explosive Charge", ["hbm:egg_balefire"] = "Balefire Egg",
  ["hbm:battery_spark"] = "Spark Battery", ["hbm:battery_trixite"] = "Off-Brand Spark Battery",
}





D.BOMBS = {
  { key = "gadget", name = "The Gadget", block = "hbm:nuke_gadget", slots = 6,
    engine = "mk5", radius = "gadgetRadius",
    parts = { "hbm:gadget_wireing", LENS1, LENS1, LENS1, LENS1, "hbm:gadget_core" } },
  { key = "boy", name = "Little Boy", block = "hbm:nuke_boy", slots = 5,
    engine = "mk5", radius = "boyRadius",
    parts = { "hbm:boy_shielding", "hbm:boy_target", "hbm:boy_bullet",
              "hbm:boy_propellant", "hbm:boy_igniter" } },
  { key = "man", name = "Fat Man", block = "hbm:nuke_man", slots = 6,
    engine = "mk5", radius = "manRadius",
    parts = { "hbm:man_igniter", LENS1, LENS1, LENS1, LENS1, "hbm:man_core" } },
  { key = "mike", name = "Ivy Mike", block = "hbm:nuke_mike", slots = 8,
    engine = "mk5", radius = "mikeRadius", fizzle = "manRadius",
    parts = { LENS2, LENS2, LENS2, LENS2, "hbm:man_core" },
    filled = { [6] = "hbm:mike_core", [7] = "hbm:mike_deut", [8] = "hbm:mike_cooling_unit" } },
  { key = "tsar", name = "Tsar Bomba", block = "hbm:nuke_tsar", slots = 6,
    engine = "mk5", radius = "tsarRadius", fizzle = "manRadius",
    parts = { LENS2, LENS2, LENS2, LENS2, "hbm:man_core" },
    filled = { [6] = "hbm:tsar_core" } },
  { key = "prototype", name = "The Prototype", block = "hbm:nuke_prototype", slots = 14,
    engine = "fleija", radius = "prototypeRadius",
    parts = { "hbm:cell#31", "hbm:cell#31", "hbm:rod_quad#14", "hbm:rod_quad#14",
              "hbm:rod_quad#13", "hbm:rod_quad#13", "hbm:rod_quad#7", "hbm:rod_quad#7",
              "hbm:rod_quad#13", "hbm:rod_quad#13", "hbm:rod_quad#14", "hbm:rod_quad#14",
              "hbm:cell#31", "hbm:cell#31" } },
  { key = "fleija", name = "F.L.E.I.J.A.", block = "hbm:nuke_fleija", slots = 11,
    engine = "fleija", radius = "fleijaRadius",
    parts = { "hbm:fleija_igniter", "hbm:fleija_igniter", "hbm:fleija_propellant",
              "hbm:fleija_propellant", "hbm:fleija_propellant", "hbm:fleija_core",
              "hbm:fleija_core", "hbm:fleija_core", "hbm:fleija_core", "hbm:fleija_core",
              "hbm:fleija_core" } },
  { key = "solinium", name = "The Blue Rinse", block = "hbm:nuke_solinium", slots = 9,
    engine = "solinium", radius = "soliniumRadius",
    parts = { "hbm:solinium_igniter", "hbm:solinium_propellant", "hbm:solinium_propellant",
              "hbm:solinium_igniter", "hbm:solinium_core", "hbm:solinium_igniter",
              "hbm:solinium_propellant", "hbm:solinium_propellant", "hbm:solinium_igniter" } },
  
  
  { key = "n2", name = "N\194\178 Mine", block = "hbm:nuke_n2", slots = 12,
    engine = "mk5", fallout = false, radius = "n2Radius", perCharge = "hbm:n2_charge" },
  
  
  { key = "balefire", name = "Balefire Bomb", block = "hbm:nuke_fstbmb", slots = 2,
    engine = "balefire", fixed = 250,
    parts = { "hbm:egg_balefire", { "hbm:battery_spark", "hbm:battery_trixite" } } },
}




D.MISSILES = {
  { key = "m_nuclear", name = "Nuclear Missile", item = "hbm:missile_nuclear",
    engine = "mk5", radius = "missileRadius" },
  { key = "m_thermo", name = "Thermonuclear Missile", item = "hbm:missile_nuclear_cluster",
    engine = "mk5", radius = "missileRadius", mult = 2 },
  { key = "m_doomsday", name = "Doomsday Missile", item = "hbm:missile_doomsday",
    engine = "mk5", radius = "missileRadius", falloutAdd = 100 },
  { key = "m_doomsday_rusted", name = "Damaged Doomsday Missile", item = "hbm:missile_doomsday_rusted",
    engine = "mk5", radius = "missileRadius", falloutAdd = 100 },
  { key = "m_n2", name = "N\194\178 Missile", item = "hbm:missile_n2",
    engine = "mk5", fallout = false, radius = "n2Radius", div = 12, mult = 5 },
  { key = "m_schrab", name = "Schrabidium Missile", item = "hbm:missile_schrabidium",
    engine = "fleija", radius = "aSchrabRadius" },
}





D.WARHEADS = {
  { key = "w10_nuclear", name = "Size 10 Micro Nuclear Warhead", item = "hbm:mp_warhead_10_nuclear", engine = "mk5", strength = 35 },
  { key = "w10_nuclear_large", name = "Size 10 Nuclear Warhead", item = "hbm:mp_warhead_10_nuclear_large", engine = "mk5", strength = 75 },
  { key = "w15_nuclear", name = "Size 15 Nuclear Warhead", item = "hbm:mp_warhead_15_nuclear", engine = "mk5", strength = 125 },
  { key = "w15_thermo", name = "Size 15 Thermonuclear Warhead", item = "hbm:mp_warhead_15_thermo", engine = "mk5", strength = 250 },
  { key = "w15_boxcar", name = "Size 15 Boxcar?", item = "hbm:mp_warhead_15_boxcar", engine = "mk5", strength = 500 },
  { key = "w15_mirv", name = "Size 15 MIRV Warhead", item = "hbm:mp_warhead_15_mirv", engine = "mk5", radius = "mirvRadius" },
  { key = "w15_n2", name = "Size 15 N\194\178 Mine", item = "hbm:mp_warhead_15_n2", engine = "mk5", fallout = false, strength = 100 },
  { key = "w15_balefire", name = "Size 15 BF Warhead", item = "hbm:mp_warhead_15_balefire", engine = "balefire", strength = 100 },
  { key = "w10_he", name = "Size 10 HE Warhead", item = "hbm:mp_warhead_10_he", engine = "large", strength = 15 },
  { key = "w15_he", name = "Size 15 HE Warhead", item = "hbm:mp_warhead_15_he", engine = "large", strength = 50 },
}










local function MAT(key, name, nuke, rad) return { key = key, name = name, nuke = nuke, rad = rad or nuke } end
D.MATERIALS = {
  MAT("water",     "Water / lava",            0.1, 100),
  MAT("dirt",      "Dirt / sand",             0.5),
  MAT("grass",     "Grass / gravel",          0.6),
  MAT("planks",    "Wood planks",             3),
  MAT("sandstone", "Sandstone",               4, 0.8),
  MAT("stone",     "Stone / cobble / bricks", 6),
  MAT("endstone",  "End stone",               9),
  MAT("obsidian",  "Obsidian",                18, 1200),
  MAT("rstone",    "Reinforced Stone",        60),
  MAT("brick_obs", "Obsidian Bricks (HBM)",   72),
  MAT("concrete",  "Concrete",                84),
  MAT("brick_con", "Concrete Bricks",         96),
  MAT("rebar",     "Rebar Reinforced Concrete", 144),
  MAT("rbrick",    "Reinforced Bricks",       180),
  MAT("compound",  "Compound Bricks",         240),
  MAT("ducrete",   "Ducrete",                 300),
  MAT("super",     "Super Concrete",          600),
  MAT("rducrete",  "Reinforced Ducrete",      600),
  MAT("bedrock",   "Bedrock",                 3600000),
}




D.RAD_SICK  = 200
D.RAD_DEATH = 1000


D.PLAYER_HP = 20

return D
