-- Battle Factory Recomp dev.7.50-rotating-sold-fix.0
-- Standalone Pokemon Red sandbox prototype targeting gen1recomp 0.2.24.
-- The Factory room's 4x4 block layout is reconstructed from the supplied
-- Battle Factory ROM, while the challenge logic below is original Lua code.

local MAP = "BATTLE_FACTORY_RECOMP"
local DRAFT = "BattleFactoryDraft"
local DETAIL = "BattleFactoryRentalDetail"
local SWAP = "BattleFactorySwap"
local SWAP_DETAIL = "BattleFactorySwapDetail"
local DROP = "BattleFactoryDrop"
local BP_MENU = "BattleFactoryBPMenu"
local BP_ITEMS = "BattleFactoryBPItems"
local BP_MONS = "BattleFactoryBPMons"
local BP_ITEM_CONFIRM = "BattleFactoryBPItemConfirm"
local BP_MON_CONFIRM = "BattleFactoryBPMonConfirm"

local TRAINER = "BATTLE_FACTORY_RENTAL_TRAINER"

-- Regular Factory opponents use custom trainer records that borrow vanilla
-- trainer portraits. Factory Head portraits are deliberately absent so their
-- battle-7 appearances remain visually special.
local REGULAR_TRAINERS = {
  {id="BATTLE_FACTORY_TRAINER_YOUNGSTER",    pic="OPP_YOUNGSTER"},
  {id="BATTLE_FACTORY_TRAINER_BUG_CATCHER", pic="OPP_BUG_CATCHER"},
  {id="BATTLE_FACTORY_TRAINER_LASS",         pic="OPP_LASS"},
  {id="BATTLE_FACTORY_TRAINER_SAILOR",       pic="OPP_SAILOR"},
  {id="BATTLE_FACTORY_TRAINER_JR_M",         pic="OPP_JR_TRAINER_M"},
  {id="BATTLE_FACTORY_TRAINER_JR_F",         pic="OPP_JR_TRAINER_F"},
  {id="BATTLE_FACTORY_TRAINER_POKEMANIAC",   pic="OPP_POKEMANIAC"},
  {id="BATTLE_FACTORY_TRAINER_SUPER_NERD",   pic="OPP_SUPER_NERD"},
  {id="BATTLE_FACTORY_TRAINER_HIKER",        pic="OPP_HIKER"},
  {id="BATTLE_FACTORY_TRAINER_BIKER",        pic="OPP_BIKER"},
  {id="BATTLE_FACTORY_TRAINER_BURGLAR",      pic="OPP_BURGLAR"},
  {id="BATTLE_FACTORY_TRAINER_ENGINEER",     pic="OPP_ENGINEER"},
  {id="BATTLE_FACTORY_TRAINER_JUGGLER",      pic="OPP_JUGGLER"},
  {id="BATTLE_FACTORY_TRAINER_FISHER",       pic="OPP_FISHER"},
  {id="BATTLE_FACTORY_TRAINER_SWIMMER",      pic="OPP_SWIMMER"},
  {id="BATTLE_FACTORY_TRAINER_CUE_BALL",     pic="OPP_CUE_BALL"},
  {id="BATTLE_FACTORY_TRAINER_GAMBLER",      pic="OPP_GAMBLER"},
  {id="BATTLE_FACTORY_TRAINER_BEAUTY",       pic="OPP_BEAUTY"},
  {id="BATTLE_FACTORY_TRAINER_PSYCHIC",      pic="OPP_PSYCHIC_TR"},
  {id="BATTLE_FACTORY_TRAINER_ROCKER",       pic="OPP_ROCKER"},
  {id="BATTLE_FACTORY_TRAINER_TAMER",        pic="OPP_TAMER"},
  {id="BATTLE_FACTORY_TRAINER_BIRD_KEEPER",  pic="OPP_BIRD_KEEPER"},
  {id="BATTLE_FACTORY_TRAINER_BLACKBELT",    pic="OPP_BLACKBELT"},
  {id="BATTLE_FACTORY_TRAINER_GENTLEMAN",    pic="OPP_GENTLEMAN"},
  {id="BATTLE_FACTORY_TRAINER_CHANNELER",     pic="OPP_CHANNELER"},
  {id="BATTLE_FACTORY_TRAINER_SCIENTIST",    pic="OPP_SCIENTIST"},
  {id="BATTLE_FACTORY_TRAINER_ROCKET",       pic="OPP_ROCKET"},
  {id="BATTLE_FACTORY_TRAINER_COOL_M",       pic="OPP_COOLTRAINER_M"},
  {id="BATTLE_FACTORY_TRAINER_COOL_F",       pic="OPP_COOLTRAINER_F"},
}

local BOSS_TRAINERS = {
  BROCK="BATTLE_FACTORY_HEAD_BROCK",
  KOGA="BATTLE_FACTORY_HEAD_KOGA",
  BLAINE="BATTLE_FACTORY_HEAD_BLAINE",
  GIOVANNI="BATTLE_FACTORY_HEAD_GIOVANNI",
  LORELEI="BATTLE_FACTORY_HEAD_LORELEI",
  LANCE="BATTLE_FACTORY_HEAD_LANCE",
  OAK="BATTLE_FACTORY_HEAD_OAK",
}

local BF = {
  level = 50,
  draft = nil,
  selected = {},
  selectionOrder = {},
  playerSets = {},
  opponentSets = {},
  pendingTake = nil,
  transitioning = false,
  pendingBPItem = nil,
  pendingBPMon = nil,
  lastRegularTrainer = nil,
}

-- Battle Point economy.
BF.bpItems = {
  -- One-copy / finite TMs only. Anything renewable from Celadon Mart or the
  -- Game Corner is deliberately excluded. BP therefore acts as a way to buy
  -- replacement copies of moves Red normally gives you only once.
  {id="TM_WHIRLWIND",     label="WHIRLWIND",     cost=4,  unlock=1}, -- TM04
  {id="TM_WATER_GUN",     label="WATER GUN",     cost=4,  unlock=1}, -- TM12
  {id="TM_RAGE",          label="RAGE",          cost=4,  unlock=1}, -- TM20
  {id="TM_TELEPORT",      label="TELEPORT",      cost=4,  unlock=1}, -- TM30
  {id="TM_BIDE",          label="BIDE",          cost=4,  unlock=1}, -- TM34

  {id="TM_PAY_DAY",       label="PAY DAY",       cost=5,  unlock=2}, -- TM16
  {id="TM_SEISMIC_TOSS",  label="SEISMIC TOSS",  cost=5,  unlock=2}, -- TM19
  {id="TM_MIMIC",         label="MIMIC",         cost=5,  unlock=2}, -- TM31
  {id="TM_SWIFT",         label="SWIFT",         cost=5,  unlock=2}, -- TM39
  {id="TM_THUNDER_WAVE",  label="THUNDER WAVE",  cost=5,  unlock=2}, -- TM45

  {id="TM_DOUBLE_EDGE",    label="DOUBLE-EDGE",   cost=6,  unlock=3}, -- TM10
  {id="TM_BUBBLEBEAM",     label="BUBBLEBEAM",    cost=6,  unlock=3}, -- TM11
  {id="TM_COUNTER",        label="COUNTER",       cost=6,  unlock=3}, -- TM18
  {id="TM_MEGA_DRAIN",     label="MEGA DRAIN",    cost=6,  unlock=3}, -- TM21
  {id="TM_METRONOME",      label="METRONOME",     cost=6,  unlock=3}, -- TM35
  {id="TM_REST",           label="REST",          cost=6,  unlock=3}, -- TM44
  {id="TM_PSYWAVE",        label="PSYWAVE",       cost=6,  unlock=3}, -- TM46
  {id="TM_TRI_ATTACK",     label="TRI ATTACK",    cost=6,  unlock=3}, -- TM49

  {id="TM_BODY_SLAM",      label="BODY SLAM",     cost=7,  unlock=4}, -- TM08
  {id="TM_DIG",            label="DIG",           cost=7,  unlock=4}, -- TM28
  {id="TM_SELFDESTRUCT",   label="SELFDESTRUCT",  cost=7,  unlock=4}, -- TM36
  {id="TM_SKULL_BASH",     label="SKULL BASH",    cost=7,  unlock=4}, -- TM40
  {id="TM_SOFTBOILED",     label="SOFTBOILED",    cost=7,  unlock=4}, -- TM41
  {id="TM_DREAM_EATER",    label="DREAM EATER",   cost=7,  unlock=4}, -- TM42
  {id="TM_ROCK_SLIDE",     label="ROCK SLIDE",    cost=7,  unlock=4}, -- TM48

  {id="TM_TOXIC",          label="TOXIC",         cost=8,  unlock=5}, -- TM06
  {id="TM_SOLARBEAM",      label="SOLARBEAM",     cost=8,  unlock=5}, -- TM22
  {id="TM_THUNDER",        label="THUNDER",       cost=8,  unlock=5}, -- TM25
  {id="TM_SWORDS_DANCE",   label="SWORDS DANCE",  cost=10, unlock=5}, -- TM03
  {id="TM_ICE_BEAM",       label="ICE BEAM",      cost=10, unlock=5}, -- TM13
  {id="TM_FIRE_BLAST",     label="FIRE BLAST",    cost=10, unlock=5}, -- TM38

  {id="TM_BLIZZARD",       label="BLIZZARD",      cost=12, unlock=6}, -- TM14
  {id="TM_THUNDERBOLT",    label="THUNDERBOLT",   cost=12, unlock=6}, -- TM24
  {id="TM_EARTHQUAKE",     label="EARTHQUAKE",    cost=12, unlock=6}, -- TM26
  {id="TM_FISSURE",        label="FISSURE",       cost=10, unlock=6}, -- TM27
  {id="TM_PSYCHIC_M",      label="PSYCHIC",       cost=12, unlock=6}, -- TM29
  {id="TM_SKY_ATTACK",     label="SKY ATTACK",    cost=10, unlock=6}, -- TM43
  {id="TM_EXPLOSION",      label="EXPLOSION",     cost=12, unlock=6}, -- TM47
}

BF.bpPokemon = {
  -- Special one-off/non-wild Pokémon only. Ordinary wild and Safari species,
  -- starters, and generic rare encounters no longer appear here.
  {id="FARFETCHD",  cost=18, unlock=2},
  {id="MR_MIME",    cost=22, unlock=3},
  {id="JYNX",       cost=25, unlock=3},
  {id="LICKITUNG",  cost=25, unlock=4},

  -- One-time gifts / mutually-exclusive Fighting Dojo reward.
  {id="EEVEE",      cost=30, unlock=4},
  {id="HITMONLEE",  cost=35, unlock=5},
  {id="HITMONCHAN", cost=35, unlock=5},

  -- Rare Game Corner species retained as a premium special prize.
  {id="PORYGON",    cost=45, unlock=6},

  -- Champion-only prestige reward.
  {id="MEW",        cost=100, postgame=true},
}

local function bpBalance()
  return tonumber(mod.save:get("bp",0)) or 0
end

local function addBP(amount)
  local value=math.max(0,bpBalance()+(tonumber(amount) or 0))
  mod.save:set("bp",value)
  return value
end

local function highestClassCleared()
  return tonumber(mod.save:get("highest_class_cleared",0)) or 0
end

local function isChampion(game)
  return game and game.save and type(game.save.hallOfFame)=="table"
         and #game.save.hallOfFame>0
end

local function rewardName(game,id,kind)
  if kind=="item" then
    local d=game.data.items[id]
    return (d and d.name) or id
  end
  local d=game.data.pokemon[id]
  return (d and d.name) or id
end

local function giveBPItem(game,id)
  local Bag=require("src.inventory.Bag")
  return Bag.add(game.save,id,1,game.data)
end

local function giveBPPokemon(game,species)
  local Pokemon=require("src.pokemon.Pokemon")
  local Boxes=require("src.pokemon.Boxes")
  local mon=Pokemon.new(game.data,species,15)
  require("src.battle.BattleState").stampOT(game.save,mon)
  local boxNum=Boxes.deposit(game.save,mon)
  if not boxNum then return nil end
  if game.save.pokedex then
    game.save.pokedex.seen[species]=true
    game.save.pokedex.owned[species]=true
  end
  return boxNum
end


-- Force ordinary dialogue into readable two-line pages. This mirrors the
-- pacing rule used by PokeSurvive instead of letting long strings scroll
-- straight through the two-line Game Boy text window.
local function pacedDialogue(text)
  text=tostring(text or "")
  local TextBox=require("src.render.TextBox")
  local chunks={}
  for section in (text.."\f"):gmatch("(.-)\f") do
    section=section:gsub("\n"," "):gsub(" +"," ")
    section=section:gsub("^ +",""):gsub(" +$","")
    if section~="" then
      local pages=TextBox.paginate(section,18)
      for _,lines in ipairs(pages) do
        local i=1
        while i<=#lines do
          local chunk=lines[i]
          if lines[i+1] then chunk=chunk.."\n"..lines[i+1] end
          chunks[#chunks+1]=chunk
          i=i+2
        end
      end
    end
  end
  return table.concat(chunks,"\f")
end

-- Original Battle Factory rental classes 1-9 (authored species + movesets).
-- Class 8 source declares 32 but contains 34 rows; all authored rows are retained.
BF.classes = {
  [1] = {
    {"CATERPIE",{"TACKLE","STRING_SHOT"}},
    {"WEEDLE",{"POISON_STING","STRING_SHOT"}},
    {"MAGIKARP",{"TACKLE"}},
    {"ZUBAT",{"WING_ATTACK","CONFUSE_RAY","BITE","LEECH_LIFE"}},
    {"PIDGEY",{"WING_ATTACK","QUICK_ATTACK","MIRROR_MOVE","SAND_ATTACK"}},
    {"RATTATA",{"SUPER_FANG","QUICK_ATTACK","TAIL_WHIP"}},
    {"JIGGLYPUFF",{"POUND","SING","DISABLE","DEFENSE_CURL"}},
    {"DIGLETT",{"SCRATCH","SAND_ATTACK","GROWL"}},
    {"SPEAROW",{"PECK","MIRROR_MOVE","GROWL","LEER"}},
    {"NIDORAN_M",{"DOUBLE_KICK","HORN_DRILL","POISON_STING","LEER"}},
    {"EKANS",{"ACID","BITE","SCREECH","WRAP"}},
    {"NIDORAN_F",{"DOUBLE_KICK","POISON_STING","TAIL_WHIP","FURY_SWIPES"}},
    {"PARAS",{"SCRATCH","LEECH_LIFE","SPORE","GROWTH"}},
    {"DITTO",{"TRANSFORM"}},
    {"CHARMANDER",{"SCRATCH","RAGE","EMBER","LEER"}},
    {"VULPIX",{"FIRE_SPIN","CONFUSE_RAY","QUICK_ATTACK","TAIL_WHIP"}},
    {"SQUIRTLE",{"WATER_GUN","BITE","WITHDRAW","TAIL_WHIP"}},
    {"VENONAT",{"SLEEP_POWDER","POISONPOWDER","LEECH_LIFE","SUPERSONIC"}},
    {"MEOWTH",{"BITE","PAY_DAY","SCREECH","GROWL"}},
    {"DRATINI",{"SLAM","THUNDER_WAVE","LEER","WRAP"}},
    {"BULBASAUR",{"RAZOR_LEAF","LEECH_SEED","GROWTH","POISONPOWDER"}},
    {"ODDISH",{"ABSORB","ACID","POISONPOWDER","SLEEP_POWDER"}},
    {"CLEFAIRY",{"METRONOME","DOUBLESLAP","MINIMIZE","DEFENSE_CURL"}},
    {"PIKACHU",{"THUNDERSHOCK","QUICK_ATTACK","THUNDER_WAVE","TAIL_WHIP"}},
    {"SANDSHREW",{"SCRATCH","SAND_ATTACK","POISON_STING","DEFENSE_CURL"}},
    {"POLIWAG",{"WATER_GUN","HYPNOSIS","DOUBLESLAP","BUBBLE"}},
    {"BELLSPROUT",{"VINE_WHIP","GROWTH","WRAP","SLEEP_POWDER"}},
    {"GEODUDE",{"ROCK_THROW","TACKLE","DEFENSE_CURL","SELFDESTRUCT"}},
    {"CUBONE",{"BONE_CLUB","HEADBUTT","LEER","GROWL"}},
    {"HORSEA",{"WATER_GUN","SMOKESCREEN","BUBBLE","LEER"}},
    {"PSYDUCK",{"WATER_GUN","CONFUSION","DISABLE","SCRATCH"}},
    {"GROWLITHE",{"EMBER","BITE","LEER","ROAR"}},
  },
  [2] = {
    {"RATTATA",{"SUPER_FANG","HYPER_FANG","QUICK_ATTACK","TAIL_WHIP"}},
    {"DIGLETT",{"SLASH","DIG","SAND_ATTACK","GROWL"}},
    {"VULPIX",{"FLAMETHROWER","CONFUSE_RAY","QUICK_ATTACK","TAIL_WHIP"}},
    {"MANKEY",{"KARATE_CHOP","SEISMIC_TOSS","LEER","LOW_KICK"}},
    {"POLIWAG",{"WATER_GUN","BODY_SLAM","AMNESIA","HYPNOSIS"}},
    {"MACHOP",{"KARATE_CHOP","SEISMIC_TOSS","LEER","LOW_KICK"}},
    {"BELLSPROUT",{"SLAM","RAZOR_LEAF","ACID","WRAP"}},
    {"BELLSPROUT",{"RAZOR_LEAF","STUN_SPORE","SLEEP_POWDER","POISONPOWDER"}},
    {"GEODUDE",{"ROCK_THROW","EARTHQUAKE","HARDEN","SELFDESTRUCT"}},
    {"MAGNEMITE",{"THUNDERSHOCK","SWIFT","SUPERSONIC","SCREECH"}},
    {"CUBONE",{"BONE_CLUB","HEADBUTT","LEER","RAGE"}},
    {"HORSEA",{"WATER_GUN","SWIFT","SMOKESCREEN","LEER"}},
    {"SLOWPOKE",{"WATER_GUN","HEADBUTT","AMNESIA","DISABLE"}},
    {"DODUO",{"DRILL_PECK","FURY_ATTACK","GROWL","DOUBLE_TEAM"}},
    {"GRIMER",{"SLUDGE","POUND","POISON_GAS","DISABLE"}},
    {"GASTLY",{"HYPNOSIS","NIGHT_SHADE","CONFUSE_RAY","LICK"}},
    {"VOLTORB",{"SWIFT","SELFDESTRUCT","LIGHT_SCREEN","SCREECH"}},
    {"SANDSHREW",{"SLASH","POISON_STING","SAND_ATTACK","FURY_SWIPES"}},
    {"GROWLITHE",{"FLAMETHROWER","BITE","LEER","AGILITY"}},
    {"SEEL",{"AURORA_BEAM","HEADBUTT","REST","GROWL"}},
    {"SHELLDER",{"CLAMP","AURORA_BEAM","SUPERSONIC","WITHDRAW"}},
    {"EXEGGCUTE",{"SLEEP_POWDER","LEECH_SEED","BARRAGE","POISONPOWDER"}},
    {"EXEGGCUTE",{"SLEEP_POWDER","POISONPOWDER","LEECH_SEED","SOLARBEAM"}},
    {"EEVEE",{"BITE","QUICK_ATTACK","TAIL_WHIP","SAND_ATTACK"}},
    {"TENTACOOL",{"WATER_GUN","ACID","SUPERSONIC","SCREECH"}},
    {"DROWZEE",{"CONFUSION","HEADBUTT","DISABLE","HYPNOSIS"}},
    {"GOLDEEN",{"WATERFALL","HORN_DRILL","SUPERSONIC","TAIL_WHIP"}},
    {"STARYU",{"WATER_GUN","SWIFT","HARDEN","MINIMIZE"}},
    {"FARFETCH_D",{"SLASH","PECK","SWORDS_DANCE","LEER"}},
    {"KOFFING",{"SLUDGE","SMOKESCREEN","SELFDESTRUCT","TACKLE"}},
    {"KRABBY",{"STOMP","GUILLOTINE","BUBBLE","HARDEN"}},
    {"PSYDUCK",{"CONFUSION","WATER_GUN","DISABLE","FURY_SWIPES"}},
    {"PONYTA",{"EMBER","STOMP","TAIL_WHIP","GROWL"}},
    {"ABRA",{"PSYCHIC_M","SEISMIC_TOSS","REFLECT","FLASH"}},
    {"PARAS",{"SLASH","SPORE","LEECH_LIFE","GROWTH"}},
    {"VENONAT",{"CONFUSION","SLEEP_POWDER","POISONPOWDER","LEECH_LIFE"}},
    {"MEOWTH",{"BITE","PAY_DAY","SCREECH","FURY_SWIPES"}},
    {"PIKACHU",{"THUNDERBOLT","QUICK_ATTACK","THUNDER_WAVE","DOUBLE_TEAM"}},
    {"ODDISH",{"MEGA_DRAIN","ACID","SLEEP_POWDER","STUN_SPORE"}},
  },
  [3] = {
    {"JIGGLYPUFF",{"BODY_SLAM","SING","DISABLE","DEFENSE_CURL"}},
    {"SPEAROW",{"DRILL_PECK","MIRROR_MOVE","GROWL","LEER"}},
    {"CHARMANDER",{"FLAMETHROWER","SLASH","GROWL","LEER"}},
    {"SQUIRTLE",{"SURF","BITE","WITHDRAW","TAIL_WHIP"}},
    {"BULBASAUR",{"RAZOR_LEAF","MEGA_DRAIN","SLEEP_POWDER","POISONPOWDER"}},
    {"CLEFAIRY",{"METRONOME","BODY_SLAM","SING","MINIMIZE"}},
    {"PIKACHU",{"THUNDERBOLT","SLAM","THUNDER_WAVE","TAIL_WHIP"}},
    {"DIGLETT",{"SLASH","DIG","SAND_ATTACK","DOUBLE_TEAM"}},
    {"MAGNEMITE",{"THUNDERBOLT","SWIFT","SUPERSONIC","LIGHT_SCREEN"}},
    {"KRABBY",{"CRABHAMMER","GUILLOTINE","BUBBLEBEAM","HARDEN"}},
    {"KOFFING",{"SLUDGE","SMOKESCREEN","SELFDESTRUCT","TACKLE"}},
    {"OMANYTE",{"SPIKE_CANNON","BUBBLEBEAM","HORN_ATTACK","LEER"}},
    {"KABUTO",{"SLASH","BUBBLEBEAM","ABSORB","LEER"}},
    {"BUTTERFREE",{"CONFUSION","SLEEP_POWDER","POISONPOWDER","GUST"}},
    {"BEEDRILL",{"TWINEEDLE","SWIFT","TOXIC","FOCUS_ENERGY"}},
    {"NIDORINA",{"POISON_STING","BITE","DOUBLE_KICK","TAIL_WHIP"}},
    {"NIDORINO",{"POISON_STING","HORN_ATTACK","DOUBLE_KICK","FOCUS_ENERGY"}},
    {"LICKITUNG",{"SLAM","STOMP","SCREECH","DISABLE"}},
    {"PORYGON",{"RECOVER","PSYBEAM","REFLECT","MIMIC"}},
    {"RHYHORN",{"HORN_DRILL","HORN_ATTACK","STOMP","LEER"}},
    {"GROWLITHE",{"FLAMETHROWER","TAKE_DOWN","DOUBLE_TEAM","LEER"}},
    {"GASTLY",{"HYPNOSIS","NIGHT_SHADE","CONFUSE_RAY","LICK"}},
    {"KOFFING",{"SLUDGE","SMOKESCREEN","SELFDESTRUCT","TOXIC"}},
    {"STARYU",{"BUBBLEBEAM","SWIFT","RECOVER","MINIMIZE"}},
    {"SLOWPOKE",{"CONFUSION","HEADBUTT","AMNESIA","WATER_GUN"}},
    {"DODUO",{"DRILL_PECK","FURY_ATTACK","GROWL","DOUBLE_TEAM"}},
    {"FARFETCH_D",{"SLASH","PECK","SWORDS_DANCE","LEER"}},
    {"MACHOP",{"KARATE_CHOP","SUBMISSION","LEER","DOUBLE_TEAM"}},
    {"EEVEE",{"BODY_SLAM","SWIFT","TAIL_WHIP","SAND_ATTACK"}},
    {"EXEGGCUTE",{"SLEEP_POWDER","POISONPOWDER","LEECH_SEED","SOLARBEAM"}},
    {"IVYSAUR",{"RAZOR_LEAF","SLEEP_POWDER","LEECH_SEED","GROWTH"}},
    {"CHARMELEON",{"FLAMETHROWER","SLASH","SMOKESCREEN","LEER"}},
    {"WARTORTLE",{"SURF","BITE","WITHDRAW","BODY_SLAM"}},
    {"KADABRA",{"PSYBEAM","RECOVER","DISABLE","REFLECT"}},
    {"HAUNTER",{"HYPNOSIS","NIGHT_SHADE","CONFUSE_RAY","DREAM_EATER"}},
    {"GRAVELER",{"ROCK_THROW","EARTHQUAKE","HARDEN","SELFDESTRUCT"}},
    {"SCYTHER",{"SLASH","WING_ATTACK","DOUBLE_TEAM","LEER"}},
    {"PINSIR",{"SLASH","SEISMIC_TOSS","HARDEN","FOCUS_ENERGY"}},
  },
  [4] = {
    {"BUTTERFREE",{"PSYBEAM","SLEEP_POWDER","POISONPOWDER","GUST"}},
    {"LICKITUNG",{"BODY_SLAM","TAKE_DOWN","STOMP","DISABLE"}},
    {"PORYGON",{"RECOVER","PSYBEAM","TRI_ATTACK","MIMIC"}},
    {"SLOWPOKE",{"CONFUSION","HEADBUTT","AMNESIA","WATER_GUN"}},
    {"RHYHORN",{"HORN_DRILL","HORN_ATTACK","STOMP","LEER"}},
    {"GLOOM",{"PETAL_DANCE","ACID","SLEEP_POWDER","POISONPOWDER"}},
    {"IVYSAUR",{"RAZOR_LEAF","SLEEP_POWDER","GROWTH","LEECH_SEED"}},
    {"CHARMELEON",{"FLAMETHROWER","SLASH","LEER","DOUBLE_TEAM"}},
    {"WARTORTLE",{"SURF","BODY_SLAM","WITHDRAW","SKULL_BASH"}},
    {"KADABRA",{"PSYBEAM","RECOVER","DISABLE","CONFUSION"}},
    {"POLIWHIRL",{"SURF","MEGA_PUNCH","AMNESIA","HYPNOSIS"}},
    {"ONIX",{"SLAM","ROCK_SLIDE","HARDEN","SCREECH"}},
    {"MR_MIME",{"CONFUSION","LIGHT_SCREEN","BARRIER","SUBSTITUTE"}},
    {"JYNX",{"ICE_PUNCH","LICK","LOVELY_KISS","DOUBLE_TEAM"}},
    {"RATICATE",{"HYPER_FANG","QUICK_ATTACK","TAIL_WHIP","SUPER_FANG"}},
    {"PARASECT",{"SLASH","SPORE","LEECH_LIFE","STUN_SPORE"}},
    {"MACHOKE",{"KARATE_CHOP","SUBMISSION","LEER","DOUBLE_TEAM"}},
    {"WEEPINBELL",{"SLAM","RAZOR_LEAF","ACID","WRAP"}},
    {"WEEPINBELL",{"RAZOR_LEAF","STUN_SPORE","SLEEP_POWDER","POISONPOWDER"}},
    {"GRAVELER",{"ROCK_THROW","EARTHQUAKE","HARDEN","SELFDESTRUCT"}},
    {"PONYTA",{"TAKE_DOWN","EMBER","STOMP","DOUBLE_TEAM"}},
    {"MAROWAK",{"BONEMERANG","HEADBUTT","LEER","COUNTER"}},
    {"HITMONLEE",{"DOUBLE_KICK","JUMP_KICK","FOCUS_ENERGY","MEDITATE"}},
    {"HITMONCHAN",{"COMET_PUNCH","MEGA_PUNCH","DOUBLE_TEAM","COUNTER"}},
    {"WIGGLYTUFF",{"BODY_SLAM","SING","DISABLE","MIMIC"}},
    {"OMANYTE",{"SPIKE_CANNON","BUBBLEBEAM","HORN_ATTACK","LEER"}},
    {"KABUTO",{"SLASH","BUBBLEBEAM","ABSORB","LEER"}},
    {"PIDGEOTTO",{"WING_ATTACK","FLY","QUICK_ATTACK","SAND_ATTACK"}},
    {"PIDGEOTTO",{"WING_ATTACK","FLY","QUICK_ATTACK","DOUBLE_TEAM"}},
    {"DODUO",{"DRILL_PECK","TRI_ATTACK","DOUBLE_TEAM","FLY"}},
    {"GASTLY",{"HYPNOSIS","NIGHT_SHADE","CONFUSE_RAY","DREAM_EATER"}},
    {"GRIMER",{"SLUDGE","ACID_ARMOR","TOXIC","BODY_SLAM"}},
    {"GRIMER",{"SLUDGE","ACID_ARMOR","TOXIC","EXPLOSION"}},
    {"KRABBY",{"SURF","CRABHAMMER","STOMP","GUILLOTINE"}},
    {"HAUNTER",{"HYPNOSIS","NIGHT_SHADE","CONFUSE_RAY","DREAM_EATER"}},
    {"DRAGONAIR",{"DRAGON_RAGE","SLAM","THUNDER_WAVE","WRAP"}},
    {"SCYTHER",{"SLASH","SWORDS_DANCE","WING_ATTACK","DOUBLE_TEAM"}},
    {"PINSIR",{"SLASH","SWORDS_DANCE","SEISMIC_TOSS","HARDEN"}},
    {"KANGASKHAN",{"MEGA_PUNCH","DIZZY_PUNCH","LEER","COUNTER"}},
    {"TAUROS",{"BODY_SLAM","STOMP","LEER","REST"}},
    {"LAPRAS",{"SURF","AURORA_BEAM","CONFUSE_RAY","SING"}},
    {"SNORLAX",{"BODY_SLAM","REST","HEADBUTT","AMNESIA"}},
  },
  [5] = {
    {"POLIWHIRL",{"SURF","MEGA_PUNCH","AMNESIA","HYPNOSIS"}},
    {"JYNX",{"ICE_PUNCH","LICK","LOVELY_KISS","THRASH"}},
    {"IVYSAUR",{"RAZOR_LEAF","SLEEP_POWDER","GROWTH","MEGA_DRAIN"}},
    {"CHARMELEON",{"FLAMETHROWER","SLASH","LEER","DOUBLE_TEAM"}},
    {"WARTORTLE",{"SURF","BODY_SLAM","WITHDRAW","SKULL_BASH"}},
    {"RATICATE",{"HYPER_FANG","QUICK_ATTACK","TAIL_WHIP","SUPER_FANG"}},
    {"PARASECT",{"SLASH","SPORE","LEECH_LIFE","STUN_SPORE"}},
    {"MACHOKE",{"KARATE_CHOP","SUBMISSION","LEER","DOUBLE_TEAM"}},
    {"WEEPINBELL",{"SLAM","RAZOR_LEAF","ACID","WRAP"}},
    {"WEEPINBELL",{"RAZOR_LEAF","STUN_SPORE","SLEEP_POWDER","POISONPOWDER"}},
    {"GRAVELER",{"ROCK_THROW","EARTHQUAKE","HARDEN","SELFDESTRUCT"}},
    {"PONYTA",{"TAKE_DOWN","EMBER","STOMP","DOUBLE_TEAM"}},
    {"MAROWAK",{"BONEMERANG","HEADBUTT","LEER","COUNTER"}},
    {"HITMONLEE",{"DOUBLE_KICK","JUMP_KICK","FOCUS_ENERGY","MEDITATE"}},
    {"HITMONCHAN",{"COMET_PUNCH","MEGA_PUNCH","DOUBLE_TEAM","COUNTER"}},
    {"HITMONCHAN",{"THUNDERPUNCH","FIRE_PUNCH","ICE_PUNCH","COMET_PUNCH"}},
    {"WIGGLYTUFF",{"BODY_SLAM","SING","DISABLE","MIMIC"}},
    {"HAUNTER",{"HYPNOSIS","CONFUSE_RAY","NIGHT_SHADE","DREAM_EATER"}},
    {"HAUNTER",{"TOXIC","MEGA_DRAIN","HYPNOSIS","NIGHT_SHADE"}},
    {"DRAGONAIR",{"DRAGON_RAGE","SLAM","THUNDER_WAVE","TAKE_DOWN"}},
    {"DUGTRIO",{"EARTHQUAKE","SLASH","SAND_ATTACK","DOUBLE_TEAM"}},
    {"DUGTRIO",{"DIG","SLASH","SAND_ATTACK","DOUBLE_TEAM"}},
    {"ARBOK",{"ACID","GLARE","TAKE_DOWN","SCREECH"}},
    {"VENOMOTH",{"PSYWAVE","POISONPOWDER","LEECH_LIFE","SLEEP_POWDER"}},
    {"VENOMOTH",{"TOXIC","CONFUSION","LEECH_LIFE","SUPERSONIC"}},
    {"PERSIAN",{"SLASH","SCREECH","SWIFT","DOUBLE_TEAM"}},
    {"FEAROW",{"DRILL_PECK","FLY","MIRROR_MOVE","DOUBLE_TEAM"}},
    {"CLEFABLE",{"METRONOME","MEGA_PUNCH","SUBSTITUTE","SING"}},
    {"PRIMEAPE",{"THRASH","SEISMIC_TOSS","SCREECH","COUNTER"}},
    {"SEAKING",{"WATERFALL","HORN_DRILL","SUPERSONIC","FURY_ATTACK"}},
    {"GOLBAT",{"WING_ATTACK","CONFUSE_RAY","TOXIC","BITE"}},
    {"VILEPLUME",{"PETAL_DANCE","POISONPOWDER","MEGA_DRAIN","ACID"}},
    {"VENUSAUR",{"RAZOR_LEAF","LEECH_SEED","SLEEP_POWDER","MEGA_DRAIN"}},
    {"CHARIZARD",{"FLAMETHROWER","SLASH","FLY","BODY_SLAM"}},
    {"BLASTOISE",{"SURF","ICE_BEAM","BODY_SLAM","WITHDRAW"}},
    {"GENGAR",{"HYPNOSIS","DREAM_EATER","NIGHT_SHADE","CONFUSE_RAY"}},
    {"ALAKAZAM",{"PSYCHIC_M","RECOVER","REFLECT","DISABLE"}},
    {"MACHAMP",{"SUBMISSION","KARATE_CHOP","EARTHQUAKE","ROCK_SLIDE"}},
    {"GOLEM",{"EARTHQUAKE","ROCK_THROW","EXPLOSION","MEGA_PUNCH"}},
    {"STARMIE",{"SURF","PSYCHIC_M","THUNDER_WAVE","RECOVER"}},
    {"ARCANINE",{"FLAMETHROWER","TAKE_DOWN","DIG","LEER"}},
    {"EXEGGUTOR",{"PSYCHIC_M","MEGA_DRAIN","SLEEP_POWDER","EXPLOSION"}},
    {"GYARADOS",{"SURF","BODY_SLAM","DRAGON_RAGE","ICE_BEAM"}},
    {"LAPRAS",{"SURF","ICE_BEAM","CONFUSE_RAY","SING"}},
    {"TAUROS",{"BODY_SLAM","EARTHQUAKE","STRENGTH","LEER"}},
    {"SNORLAX",{"BODY_SLAM","REST","AMNESIA","HEADBUTT"}},
    {"NIDOKING",{"THRASH","EARTHQUAKE","THUNDERBOLT","TOXIC"}},
    {"NIDOQUEEN",{"BODY_SLAM","EARTHQUAKE","ICE_BEAM","DOUBLE_KICK"}},
  },
  [6] = {
    {"SLOWBRO",{"BUBBLEBEAM","HEADBUTT","AMNESIA","DISABLE"}},
    {"SLOWBRO",{"CONFUSION","HEADBUTT","AMNESIA","DISABLE"}},
    {"RAICHU",{"THUNDERBOLT","SWIFT","DOUBLE_TEAM","FLASH"}},
    {"MAGNETON",{"THUNDERBOLT","THUNDER_WAVE","SUPERSONIC","SCREECH"}},
    {"TANGELA",{"MEGA_DRAIN","SLEEP_POWDER","SLAM","GROWTH"}},
    {"TANGELA",{"MEGA_DRAIN","POISONPOWDER","SLAM","GROWTH"}},
    {"TANGELA",{"MEGA_DRAIN","STUN_SPORE","SLAM","GROWTH"}},
    {"SEADRA",{"SURF","SWIFT","DOUBLE_TEAM","SMOKESCREEN"}},
    {"ELECTABUZZ",{"THUNDERPUNCH","MEGA_PUNCH","LIGHT_SCREEN","SCREECH"}},
    {"MAGMAR",{"FLAMETHROWER","SMOG","SMOKESCREEN","CONFUSE_RAY"}},
    {"PIDGEOT",{"WING_ATTACK","QUICK_ATTACK","DOUBLE_TEAM","SAND_ATTACK"}},
    {"PIDGEOT",{"FLY","QUICK_ATTACK","MIRROR_MOVE","SAND_ATTACK"}},
    {"DODRIO",{"DRILL_PECK","TRI_ATTACK","DOUBLE_TEAM","GROWL"}},
    {"MUK",{"SLUDGE","TOXIC","ACID_ARMOR","MINIMIZE"}},
    {"MUK",{"BODY_SLAM","TOXIC","ACID_ARMOR","MINIMIZE"}},
    {"ELECTRODE",{"THUNDERBOLT","SWIFT","LIGHT_SCREEN","EXPLOSION"}},
    {"ELECTRODE",{"SWIFT","THUNDER_WAVE","LIGHT_SCREEN","EXPLOSION"}},
    {"SANDSLASH",{"SLASH","ROCK_SLIDE","POISON_STING","SAND_ATTACK"}},
    {"SANDSLASH",{"DIG","ROCK_SLIDE","POISON_STING","SAND_ATTACK"}},
    {"GOLDUCK",{"SURF","CONFUSION","DISABLE","SWIFT"}},
    {"ALAKAZAM",{"PSYBEAM","RECOVER","REFLECT","DISABLE"}},
    {"DEWGONG",{"AURORA_BEAM","TAKE_DOWN","REST","GROWL"}},
    {"NIDOQUEEN",{"BODY_SLAM","DOUBLE_KICK","POISON_STING","GROWL"}},
    {"NIDOKING",{"THRASH","DOUBLE_KICK","POISON_STING","TOXIC"}},
    {"VENOMOTH",{"PSYWAVE","POISONPOWDER","LEECH_LIFE","SLEEP_POWDER"}},
    {"VENOMOTH",{"TOXIC","PSYWAVE","LEECH_LIFE","SUPERSONIC"}},
    {"PERSIAN",{"SLASH","SCREECH","SWIFT","DOUBLE_TEAM"}},
    {"FEAROW",{"DRILL_PECK","FLY","MIRROR_MOVE","DOUBLE_TEAM"}},
    {"CLEFABLE",{"METRONOME","MEGA_PUNCH","SUBSTITUTE","SING"}},
    {"PRIMEAPE",{"THRASH","SEISMIC_TOSS","SCREECH","COUNTER"}},
    {"SEAKING",{"WATERFALL","HORN_DRILL","SUPERSONIC","FURY_ATTACK"}},
    {"GOLBAT",{"WING_ATTACK","CONFUSE_RAY","TOXIC","BITE"}},
    {"VILEPLUME",{"PETAL_DANCE","POISONPOWDER","MEGA_DRAIN","ACID"}},
    {"DUGTRIO",{"EARTHQUAKE","SLASH","SAND_ATTACK","DOUBLE_TEAM"}},
    {"DUGTRIO",{"DIG","SLASH","SAND_ATTACK","DOUBLE_TEAM"}},
  },
  [7] = {
    {"POLIWRATH",{"SURF","STRENGTH","HYPNOSIS","BODY_SLAM"}},
    {"HYPNO",{"PSYCHIC_M","POISON_GAS","HYPNOSIS","HEADBUTT"}},
    {"KANGASKHAN",{"MEGA_PUNCH","DIZZY_PUNCH","LEER","COUNTER"}},
    {"KANGASKHAN",{"TAKE_DOWN","EARTHQUAKE","LEER","STRENGTH"}},
    {"CHANSEY",{"POUND","SUBSTITUTE","SOFTBOILED","REST"}},
    {"CHANSEY",{"TOXIC","SUBSTITUTE","SOFTBOILED","REST"}},
    {"MACHAMP",{"SUBMISSION","KARATE_CHOP","FOCUS_ENERGY","LEER"}},
    {"VICTREEBEL",{"RAZOR_LEAF","ACID","CUT","STUN_SPORE"}},
    {"VICTREEBEL",{"MEGA_DRAIN","TOXIC","DOUBLE_TEAM","STUN_SPORE"}},
    {"GOLEM",{"EARTHQUAKE","ROCK_THROW","EXPLOSION","MEGA_PUNCH"}},
    {"RAPIDASH",{"FIRE_SPIN","TAKE_DOWN","SKULL_BASH","TAIL_WHIP"}},
    {"WEEZING",{"SLUDGE","TOXIC","HAZE","EXPLOSION"}},
    {"SCYTHER",{"SLASH","SWORDS_DANCE","WING_ATTACK","DOUBLE_TEAM"}},
    {"NINETALES",{"FIRE_BLAST","SKULL_BASH","DOUBLE_TEAM","SWIFT"}},
    {"VENUSAUR",{"RAZOR_LEAF","LEECH_SEED","SLEEP_POWDER","MEGA_DRAIN"}},
    {"VENUSAUR",{"SOLARBEAM","POISONPOWDER","LEECH_SEED","GROWTH"}},
    {"CHARIZARD",{"FLAMETHROWER","SLASH","LEER","CUT"}},
    {"CHARIZARD",{"FLY","EMBER","BODY_SLAM","LEER"}},
    {"BLASTOISE",{"SURF","BITE","ICE_BEAM","WITHDRAW"}},
    {"BLASTOISE",{"EARTHQUAKE","BUBBLEBEAM","WITHDRAW","REFLECT"}},
    {"GENGAR",{"HYPNOSIS","DREAM_EATER","NIGHT_SHADE","CONFUSE_RAY"}},
    {"GENGAR",{"TOXIC","DOUBLE_TEAM","MEGA_DRAIN","CONFUSE_RAY"}},
    {"KINGLER",{"CRABHAMMER","STOMP","HARDEN","LEER"}},
    {"KINGLER",{"BUBBLEBEAM","GUILLOTINE","HARDEN","LEER"}},
    {"OMASTAR",{"SURF","SPIKE_CANNON","LEER","WITHDRAW"}},
    {"PINSIR",{"SLASH","SWORDS_DANCE","SEISMIC_TOSS","HARDEN"}},
    {"MAGMAR",{"FLAMETHROWER","SMOG","SMOKESCREEN","CONFUSE_RAY"}},
    {"MAGMAR",{"PSYWAVE","FIRE_PUNCH","SMOKESCREEN","CONFUSE_RAY"}},
    {"PIDGEOT",{"WING_ATTACK","TAKE_DOWN","DOUBLE_TEAM","SAND_ATTACK"}},
    {"PIDGEOT",{"FLY","QUICK_ATTACK","MIRROR_MOVE","SAND_ATTACK"}},
    {"DODRIO",{"DRILL_PECK","TRI_ATTACK","DOUBLE_TEAM","GROWL"}},
    {"MUK",{"SLUDGE","TOXIC","ACID_ARMOR","MINIMIZE"}},
    {"MUK",{"BODY_SLAM","TOXIC","ACID_ARMOR","MINIMIZE"}},
    {"ELECTRODE",{"THUNDERBOLT","SWIFT","LIGHT_SCREEN","EXPLOSION"}},
    {"ELECTRODE",{"SWIFT","THUNDER_WAVE","LIGHT_SCREEN","EXPLOSION"}},
    {"SANDSLASH",{"SLASH","ROCK_SLIDE","POISON_STING","SAND_ATTACK"}},
    {"SANDSLASH",{"EARTHQUAKE","ROCK_SLIDE","POISON_STING","SAND_ATTACK"}},
    {"GOLDUCK",{"SURF","CONFUSION","DISABLE","SWIFT"}},
    {"GOLDUCK",{"SURF","ICE_BEAM","PSYCHIC_M","DISABLE"}},
    {"ALAKAZAM",{"PSYBEAM","RECOVER","REFLECT","DISABLE"}},
    {"DEWGONG",{"ICE_BEAM","TAKE_DOWN","REST","GROWL"}},
    {"NIDOQUEEN",{"BODY_SLAM","DOUBLE_KICK","POISON_STING","GROWL"}},
    {"NIDOQUEEN",{"BODY_SLAM","FISSURE","POISON_STING","GROWL"}},
    {"NIDOKING",{"THRASH","DOUBLE_KICK","POISON_STING","TOXIC"}},
    {"NIDOKING",{"THRASH","FISSURE","POISON_STING","TOXIC"}},
  },
  [8] = {
    {"VAPOREON",{"SURF","AURORA_BEAM","ACID_ARMOR","SUBSTITUTE"}},
    {"JOLTEON",{"THUNDERBOLT","PIN_MISSILE","DOUBLE_KICK","DOUBLE_TEAM"}},
    {"FLAREON",{"FLAMETHROWER","TAKE_DOWN","DOUBLE_TEAM","SMOG"}},
    {"KABUTOPS",{"SURF","SLASH","ABSORB","LEER"}},
    {"SNORLAX",{"REST","HEADBUTT","AMNESIA","BODY_SLAM"}},
    {"TENTACRUEL",{"SURF","TOXIC","BARRIER","SUPERSONIC"}},
    {"STARMIE",{"SURF","ICE_BEAM","SWIFT","HARDEN"}},
    {"STARMIE",{"THUNDER_WAVE","PSYCHIC_M","SWIFT","RECOVER"}},
    {"RHYDON",{"TAKE_DOWN","EARTHQUAKE","LEER","FIRE_BLAST"}},
    {"RHYDON",{"HORN_DRILL","ROCK_SLIDE","LEER","MEGA_PUNCH"}},
    {"AERODACTYL",{"WING_ATTACK","ROCK_SLIDE","TAKE_DOWN","SUPERSONIC"}},
    {"TAUROS",{"BODY_SLAM","STRENGTH","EARTHQUAKE","LEER"}},
    {"LAPRAS",{"SURF","ICE_BEAM","CONFUSE_RAY","SING"}},
    {"ARCANINE",{"TAKE_DOWN","FIRE_BLAST","SWIFT","LEER"}},
    {"EXEGGUTOR",{"MEGA_DRAIN","HYPNOSIS","EGG_BOMB","STOMP"}},
    {"CLOYSTER",{"ICE_BEAM","SURF","WITHDRAW","SPIKE_CANNON"}},
    {"GYARADOS",{"SURF","DRAGON_RAGE","STRENGTH","LEER"}},
    {"WEEZING",{"SLUDGE","TOXIC","HAZE","EXPLOSION"}},
    {"SCYTHER",{"SLASH","SWORDS_DANCE","WING_ATTACK","DOUBLE_TEAM"}},
    {"NINETALES",{"FIRE_BLAST","SKULL_BASH","DOUBLE_TEAM","SWIFT"}},
    {"VENUSAUR",{"RAZOR_LEAF","LEECH_SEED","SLEEP_POWDER","MEGA_DRAIN"}},
    {"VENUSAUR",{"SOLARBEAM","POISONPOWDER","LEECH_SEED","GROWTH"}},
    {"CHARIZARD",{"FLAMETHROWER","SLASH","LEER","CUT"}},
    {"CHARIZARD",{"FLY","EMBER","BODY_SLAM","LEER"}},
    {"BLASTOISE",{"SURF","BITE","ICE_BEAM","WITHDRAW"}},
    {"BLASTOISE",{"EARTHQUAKE","BUBBLEBEAM","WITHDRAW","REFLECT"}},
    {"GENGAR",{"HYPNOSIS","DREAM_EATER","NIGHT_SHADE","CONFUSE_RAY"}},
    {"GENGAR",{"TOXIC","DOUBLE_TEAM","MEGA_DRAIN","CONFUSE_RAY"}},
    {"KINGLER",{"CRABHAMMER","STOMP","HARDEN","LEER"}},
    {"KINGLER",{"BUBBLEBEAM","GUILLOTINE","HARDEN","LEER"}},
    {"OMASTAR",{"SURF","SPIKE_CANNON","LEER","WITHDRAW"}},
    {"PINSIR",{"SLASH","SWORDS_DANCE","SEISMIC_TOSS","HARDEN"}},
    {"CHANSEY",{"POUND","SUBSTITUTE","SOFTBOILED","REST"}},
    {"CHANSEY",{"TOXIC","SUBSTITUTE","SOFTBOILED","REST"}},
  },
  [9] = {
    {"DRAGONITE",{"HYPER_BEAM","SLAM","THUNDER_WAVE","THUNDERBOLT"}},
    {"DRAGONITE",{"HYPER_BEAM","BODY_SLAM","SURF","ICE_BEAM"}},
    {"DRAGONITE",{"THUNDERBOLT","FIRE_BLAST","ICE_BEAM","SURF"}},
    {"GYARADOS",{"HYPER_BEAM","SURF","STRENGTH","DOUBLE_TEAM"}},
    {"GYARADOS",{"HYPER_BEAM","TAKE_DOWN","THUNDERBOLT","ICE_BEAM"}},
    {"EXEGGUTOR",{"PSYCHIC_M","MEGA_DRAIN","LIGHT_SCREEN","SUBSTITUTE"}},
    {"EXEGGUTOR",{"PSYCHIC_M","MEGA_DRAIN","TOXIC","EXPLOSION"}},
    {"ARCANINE",{"TAKE_DOWN","FIRE_BLAST","SWIFT","LEER"}},
    {"ARCANINE",{"TAKE_DOWN","FIRE_BLAST","DIG","LEER"}},
    {"LAPRAS",{"SURF","ICE_BEAM","CONFUSE_RAY","SING"}},
    {"LAPRAS",{"SURF","BLIZZARD","CONFUSE_RAY","REST"}},
    {"LAPRAS",{"PSYWAVE","ICE_BEAM","THUNDERBOLT","SING"}},
    {"TAUROS",{"BODY_SLAM","STRENGTH","EARTHQUAKE","LEER"}},
    {"TAUROS",{"BODY_SLAM","SURF","DOUBLE_TEAM","TOXIC"}},
    {"AERODACTYL",{"WING_ATTACK","ROCK_SLIDE","TAKE_DOWN","SUPERSONIC"}},
    {"AERODACTYL",{"HYPER_BEAM","ROCK_SLIDE","TAKE_DOWN","SUPERSONIC"}},
    {"RHYDON",{"TAKE_DOWN","EARTHQUAKE","LEER","FIRE_BLAST"}},
    {"RHYDON",{"HORN_DRILL","ROCK_SLIDE","LEER","MEGA_PUNCH"}},
    {"STARMIE",{"SURF","ICE_BEAM","SWIFT","HARDEN"}},
    {"STARMIE",{"THUNDER_WAVE","PSYCHIC_M","SWIFT","RECOVER"}},
    {"STARMIE",{"PSYCHIC_M","SURF","THUNDERBOLT","RECOVER"}},
    {"TENTACRUEL",{"SURF","TOXIC","BARRIER","SUPERSONIC"}},
    {"TENTACRUEL",{"HYDRO_PUMP","BLIZZARD","SUBSTITUTE","SUPERSONIC"}},
    {"SNORLAX",{"REST","HEADBUTT","AMNESIA","BODY_SLAM"}},
    {"SNORLAX",{"HYPER_BEAM","HEADBUTT","AMNESIA","REST"}},
    {"SNORLAX",{"MEGA_KICK","HEADBUTT","AMNESIA","REFLECT"}},
    {"SNORLAX",{"ROCK_SLIDE","STRENGTH","AMNESIA","BUBBLEBEAM"}},
    {"KABUTOPS",{"SURF","SLASH","ABSORB","LEER"}},
    {"KABUTOPS",{"SURF","SUBMISSION","SWORDS_DANCE","SLASH"}},
    {"VAPOREON",{"SURF","ICE_BEAM","ACID_ARMOR","SUBSTITUTE"}},
    {"VAPOREON",{"SURF","BLIZZARD","REST","SUBSTITUTE"}},
    {"JOLTEON",{"THUNDERBOLT","PIN_MISSILE","DOUBLE_KICK","DOUBLE_TEAM"}},
    {"JOLTEON",{"THUNDERBOLT","PIN_MISSILE","DOUBLE_KICK","DOUBLE_TEAM"}},
    {"FLAREON",{"FLAMETHROWER","TAKE_DOWN","DOUBLE_TEAM","SMOG"}},
    {"VENUSAUR",{"RAZOR_LEAF","LEECH_SEED","SLEEP_POWDER","MEGA_DRAIN"}},
    {"VENUSAUR",{"SOLARBEAM","POISONPOWDER","LEECH_SEED","GROWTH"}},
    {"CHARIZARD",{"FLAMETHROWER","SLASH","LEER","CUT"}},
    {"CHARIZARD",{"FLY","FLAMETHROWER","BODY_SLAM","LEER"}},
    {"BLASTOISE",{"SURF","BITE","ICE_BEAM","WITHDRAW"}},
    {"BLASTOISE",{"EARTHQUAKE","BUBBLEBEAM","WITHDRAW","REFLECT"}},
    {"GENGAR",{"HYPNOSIS","DREAM_EATER","NIGHT_SHADE","CONFUSE_RAY"}},
    {"GENGAR",{"TOXIC","DOUBLE_TEAM","PSYCHIC_M","MEGA_DRAIN"}},
    {"CHANSEY",{"DOUBLE_EDGE","SUBSTITUTE","SOFTBOILED","REST"}},
    {"CHANSEY",{"TOXIC","SUBSTITUTE","SOFTBOILED","REST"}},
    {"CHANSEY",{"ICE_BEAM","THUNDERBOLT","SOFTBOILED","PSYCHIC_M"}},
    {"MACHAMP",{"SUBMISSION","KARATE_CHOP","MEGA_PUNCH","LEER"}},
    {"MACHAMP",{"SUBMISSION","KARATE_CHOP","EARTHQUAKE","ROCK_SLIDE"}},
    {"SCYTHER",{"SLASH","SWORDS_DANCE","WING_ATTACK","DOUBLE_TEAM"}},
    {"KANGASKHAN",{"MEGA_PUNCH","DIZZY_PUNCH","LEER","COUNTER"}},
    {"KANGASKHAN",{"TAKE_DOWN","EARTHQUAKE","LEER","STRENGTH"}},
    {"POLIWRATH",{"SURF","STRENGTH","HYPNOSIS","BODY_SLAM"}},
    {"POLIWRATH",{"SURF","SUBMISSION","HYPNOSIS","BODY_SLAM"}},
    {"ALAKAZAM",{"PSYCHIC_M","RECOVER","REFLECT","DISABLE"}},
    {"DEWGONG",{"ICE_BEAM","TAKE_DOWN","REST","GROWL"}},
    {"DEWGONG",{"BLIZZARD","SURF","REST","HORN_DRILL"}},
    {"NIDOQUEEN",{"BODY_SLAM","DOUBLE_KICK","POISON_STING","GROWL"}},
    {"NIDOQUEEN",{"BODY_SLAM","FISSURE","POISON_STING","GROWL"}},
    {"NIDOQUEEN",{"SURF","ICE_BEAM","SUBMISSION","DOUBLE_TEAM"}},
    {"NIDOKING",{"THRASH","DOUBLE_KICK","POISON_STING","TOXIC"}},
    {"NIDOKING",{"THRASH","FISSURE","POISON_STING","TOXIC"}},
    {"NIDOKING",{"SURF","FIRE_BLAST","ROCK_SLIDE","TOXIC"}},
    {"ARTICUNO",{"ICE_BEAM","FLY","SWIFT","DOUBLE_TEAM"}},
    {"ZAPDOS",{"THUNDERBOLT","DRILL_PECK","SWIFT","DOUBLE_TEAM"}},
    {"MOLTRES",{"FIRE_BLAST","SKY_ATTACK","SWIFT","DOUBLE_TEAM"}},
  },
}

-- Factory Head battles: battle 7 of Classes 3-9.
BF.bosses = {
  [3] = {name="BROCK", trainerId=BOSS_TRAINERS.BROCK, team={
    {"RHYHORN",{"HORN_DRILL","HORN_ATTACK","STOMP","LEER"}},
    {"GEODUDE",{"ROCK_THROW","EARTHQUAKE","HARDEN","SELFDESTRUCT"}},
    {"KABUTO",{"SLASH","BUBBLEBEAM","ABSORB","LEER"}},
  }},
  [4] = {name="KOGA", trainerId=BOSS_TRAINERS.KOGA, team={
    {"KOFFING",{"SLUDGE","SMOKESCREEN","SELFDESTRUCT","TOXIC"}},
    {"GOLBAT",{"WING_ATTACK","CONFUSE_RAY","BITE","TOXIC"}},
    {"WEEZING",{"SLUDGE","SMOKESCREEN","SELFDESTRUCT","TOXIC"}},
  }},
  [5] = {name="BLAINE", trainerId=BOSS_TRAINERS.BLAINE, team={
    {"NINETALES",{"FLAMETHROWER","CONFUSE_RAY","QUICK_ATTACK","TAIL_WHIP"}},
    {"RAPIDASH",{"FIRE_BLAST","STOMP","AGILITY","TAKE_DOWN"}},
    {"ARCANINE",{"TAKE_DOWN","FIRE_BLAST","DIG","LEER"}},
  }},
  [6] = {name="GIOVANNI", trainerId=BOSS_TRAINERS.GIOVANNI, team={
    {"NIDOQUEEN",{"BODY_SLAM","DOUBLE_KICK","POISON_STING","GROWL"}},
    {"NIDOKING",{"THRASH","DOUBLE_KICK","POISON_STING","TOXIC"}},
    {"RHYDON",{"TAKE_DOWN","EARTHQUAKE","LEER","FIRE_BLAST"}},
  }},
  [7] = {name="LORELEI", trainerId=BOSS_TRAINERS.LORELEI, team={
    {"DEWGONG",{"ICE_BEAM","TAKE_DOWN","REST","GROWL"}},
    {"CLOYSTER",{"CLAMP","ICE_BEAM","AURORA_BEAM","WITHDRAW"}},
    {"LAPRAS",{"SURF","ICE_BEAM","CONFUSE_RAY","SING"}},
  }},
  [8] = {name="LANCE", trainerId=BOSS_TRAINERS.LANCE, team={
    {"GYARADOS",{"HYPER_BEAM","SURF","STRENGTH","DOUBLE_TEAM"}},
    {"AERODACTYL",{"HYPER_BEAM","ROCK_SLIDE","TAKE_DOWN","SUPERSONIC"}},
    {"DRAGONITE",{"HYPER_BEAM","BODY_SLAM","SURF","ICE_BEAM"}},
  }},
  [9] = {name="PROF. OAK", trainerId=BOSS_TRAINERS.OAK, team={
    {"TAUROS",{"BODY_SLAM","STRENGTH","EARTHQUAKE","LEER"}},
    {"EXEGGUTOR",{"PSYCHIC_M","MEGA_DRAIN","TOXIC","EXPLOSION"}},
    {"BLASTOISE",{"SURF","BITE","ICE_BEAM","WITHDRAW"}},
  }},
}

function BF.battleNumber()
  local streak=tonumber(mod.save:get("streak",0)) or 0
  return (streak%7)+1
end

function BF.currentBoss()
  local class=BF.currentClass()
  if BF.battleNumber()==7 then return BF.bosses[class] end
  return nil
end

local function copySet(set)
  local moves={}
  for i,id in ipairs(set[2] or {}) do moves[i]=id end
  return {set[1],moves}
end

local function speciesName(game,id)
  local def=game.data.pokemon[id]
  return def and def.name or id
end

local function moveName(game,id)
  local def=game.data.moves[id]
  return def and def.name or id
end

local function randomizedLevelMoves(game,species,level)
  local def=game and game.data and game.data.pokemon
    and game.data.pokemon[species]
  if not def then return {} end
  local learned={}
  for _,id in ipairs(def.level1Moves or {}) do
    if id then learned[#learned+1]=id end
  end
  for _,entry in ipairs(def.learnset or {}) do
    if entry and entry.move
      and (tonumber(entry.level) or 999) <= (tonumber(level) or 1) then
      learned[#learned+1]=entry.move
    end
  end
  local out={}
  local first=math.max(1,#learned-3)
  for i=first,#learned do out[#out+1]=learned[i] end
  return out
end

local function makeRental(game,set)
  local Pokemon=require("src.pokemon.Pokemon")
  local mon=Pokemon.new(game.data,set[1],BF.level)
  local moveIds=set[2] or {}
  if game.save and game.save.pokesurvive_random_pokemon == true then
    moveIds=randomizedLevelMoves(game,set[1],BF.level)
  end
  if #moveIds>0 then
    mon.moves={}
    for _,id in ipairs(moveIds) do
      local def=game.data.moves[id]
      mon.moves[#mon.moves+1]={id=id,pp=def and def.pp or 0}
    end
  end
  mon._battleFactoryRental=true
  return mon
end

local function openNativeRentalSummary(game,set)
  if type(set)~="table" or not game.data.pokemon[set[1]] then return false end
  for _,id in ipairs(set[2] or {}) do
    if not game.data.moves[id] then return false end
  end

  -- SummaryMenu.new explicitly supports Pokémon tables supplied by mods.
  -- Pokemon.new gives the rental proper Level 50 DVs/stats/EXP; then we apply
  -- the Factory's authored moveset before opening the vanilla status screen.
  local mon=makeRental(game,set)
  local Screens=require("src.ui.Screens")
  Screens.push(game,"SummaryMenu",mon)
  return true
end

local function healRentals(game)
  local Pokemon=require("src.pokemon.Pokemon")
  for _,mon in ipairs(game.save.party or {}) do Pokemon.heal(mon) end
end

-- The player's adventure party is never used as Factory data. Before the
-- first three rentals replace it, copy the COMPLETE Pokémon records into the
-- mod's persistent save namespace. This preserves every field the engine has
-- attached to a mon (species, nickname/OT data, DVs, stat EXP, EXP, HP,
-- status, moves/PP/PP Ups, catch rate, etc.), including fields added later.
local function deepCopy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}
  if seen[value] then return seen[value] end
  local out={}
  seen[value]=out
  for k,v in pairs(value) do
    out[deepCopy(k,seen)]=deepCopy(v,seen)
  end
  return out
end

local function partyEscrowActive()
  return mod and mod.save:get("party_escrow_active",false)==true
end

local function escrowAdventureParty(game)
  if partyEscrowActive() then return true end
  local original=deepCopy(game.save.party or {})
  mod.save:set("adventure_party_backup",original)
  mod.save:set("party_escrow_active",true)
  -- Cross-mod integration marker. PokeSurvive uses this to suspend its
  -- out-of-battle permadeath scanner while temporary rentals occupy party.
  game.save.pokesurvive_factory_rentals=true
  return true
end

local function restoreAdventureParty(game)
  if not partyEscrowActive() then return false end
  local original=mod.save:get("adventure_party_backup",{})
  game.save.party=deepCopy(original or {})
  mod.save:set("adventure_party_backup",nil)
  mod.save:set("party_escrow_active",false)
  game.save.pokesurvive_factory_rentals=nil

  return true
end


local function selectedCount()
  return #(BF.selectionOrder or {})
end

local function removeSelectionIndex(index)
  for pos,value in ipairs(BF.selectionOrder or {}) do
    if value==index then
      table.remove(BF.selectionOrder,pos)
      return
    end
  end
end

local function randomUniqueSets(pool,count,blocked)
  local candidates={}
  blocked=blocked or {}
  for _,set in ipairs(pool) do
    if not blocked[set[1]] then candidates[#candidates+1]=set end
  end
  local out,used={},{ }
  while #out<count and #candidates>0 do
    local i=math.random(1,#candidates)
    local set=table.remove(candidates,i)
    if not used[set[1]] then
      used[set[1]]=true
      out[#out+1]=copySet(set)
    end
  end
  return out
end

function BF.currentClass()
  local streak=tonumber(mod.save:get("streak",0)) or 0
  return math.min(9,math.floor(streak/7)+1)
end

local function validRentalSet(game,set)
  if type(set)~="table" or not game.data.pokemon[set[1]] then return false end
  for _,move in ipairs(set[2] or {}) do
    if not game.data.moves[move] then return false end
  end
  return true
end

function BF.pool(game)
  local source=BF.classes[BF.currentClass()] or BF.classes[9]
  if not game then return source end

  -- Keep the authored tables untouched, but never hand the engine an entry
  -- whose species or move identifier does not exist in this recomp build.
  local valid={}
  for _,set in ipairs(source) do
    if validRentalSet(game,set) then valid[#valid+1]=set end
  end
  return valid
end

local function pokeSurviveRandomizerActive(game)
  return game and game.save
    and game.save.pokesurvive_random_pokemon == true
end

local function factorySeedHash(raw)
  raw=tostring(raw or "")
  local h=17
  for i=1,#raw do h=(h*131+raw:byte(i))%2147483647 end
  if h<=0 then h=1 end
  return h
end

local function factorySpeciesPool(game)
  local pool={}
  for id,def in pairs((game and game.data and game.data.pokemon) or {}) do
    local dex=tonumber(def and def.dex)
    if dex and dex>=1 and dex<=151
      and id~="ARTICUNO" and id~="ZAPDOS" and id~="MOLTRES"
      and id~="MEWTWO" and id~="MEW" and id~="SNORLAX" then
      pool[#pool+1]={id=id,dex=dex}
    end
  end
  table.sort(pool,function(a,b)
    if a.dex~=b.dex then return a.dex<b.dex end
    return tostring(a.id)<tostring(b.id)
  end)
  return pool
end

local function seededFactorySpecies(game,key,used,original)
  local pool=factorySpeciesPool(game)
  if #pool==0 then return original end
  local seed=tonumber(game.save.pokesurvive_run_seed) or 1
  local h=factorySeedHash(tostring(seed).."|factory|"..tostring(key))
  local first=(h%#pool)+1
  for offset=0,#pool-1 do
    local id=pool[((first-1+offset)%#pool)+1].id
    if (not used or not used[id]) and id~=original then return id end
  end
  return pool[first].id
end

local BP_ROTATION_STEPS=1000
local BP_ROTATION_SIZE=10

local function pokemonBST(game,id)
  local def=game and game.data and game.data.pokemon and game.data.pokemon[id]
  local st=def and def.baseStats
  if not st then return 0 end
  return (tonumber(st.hp) or 0)+(tonumber(st.attack) or 0)
    +(tonumber(st.defense) or 0)+(tonumber(st.speed) or 0)
    +(tonumber(st.special) or 0)
end

local function rotatingPrizeTier(game,id)
  local bst=pokemonBST(game,id)
  if bst<=300 then return 1,12 end
  if bst<=350 then return 2,16 end
  if bst<=400 then return 3,22 end
  if bst<=450 then return 4,28 end
  if bst<=500 then return 5,36 end
  if bst<=550 then return 6,45 end
  return 7,55
end

local function currentRotationEpoch(game)
  local steps=math.max(0,math.floor(
    tonumber(game and game.save and game.save.pokesurvive_world_steps or 0) or 0))
  return math.floor(steps/BP_ROTATION_STEPS),steps
end

local function rotatingStockSignature(game)
  local seed=tonumber(game and game.save and game.save.pokesurvive_run_seed) or 1
  local epoch=currentRotationEpoch(game)
  return tostring(seed).."|"..tostring(epoch),seed,epoch
end

local function clearRotatingStock()
  mod.save:set("bp_rotating_signature","")
  for i=1,BP_ROTATION_SIZE do
    mod.save:set("bp_rotating_mon_"..i,"")
    mod.save:set("bp_rotating_sold_"..i,false)
  end
end

local function ensureRotatingStock(game)
  local signature,seed,epoch=rotatingStockSignature(game)
  if tostring(mod.save:get("bp_rotating_signature","") or "")==signature then
    local ready=true
    for i=1,BP_ROTATION_SIZE do
      if tostring(mod.save:get("bp_rotating_mon_"..i,"") or "")=="" then
        ready=false;break
      end
    end
    if ready then return end
  end

  mod.log:info("Generating new BP rotating stock: %s",signature)
  clearRotatingStock()
  local pool=factorySpeciesPool(game)
  local available={}
  for _,entry in ipairs(pool) do available[#available+1]=entry.id end
  local used={}

  for slot=1,BP_ROTATION_SIZE do
    if #available==0 then break end
    local h=factorySeedHash(
      tostring(seed).."|bpstock|"..tostring(epoch).."|"..tostring(slot))
    local start=(h%#available)+1
    local chosenIndex=nil
    for offset=0,#available-1 do
      local idx=((start-1+offset)%#available)+1
      local id=available[idx]
      if not used[id] then chosenIndex=idx;break end
    end
    chosenIndex=chosenIndex or 1
    local id=table.remove(available,chosenIndex)
    used[id]=true
    mod.save:set("bp_rotating_mon_"..slot,id)
    mod.save:set("bp_rotating_sold_"..slot,false)
  end

  mod.save:set("bp_rotating_signature",signature)
end

local function rotatingPokemonRewards(game)
  ensureRotatingStock(game)
  local rewards={}
  for i=1,BP_ROTATION_SIZE do
    local id=tostring(mod.save:get("bp_rotating_mon_"..i,"") or "")
    if id~="" and game.data.pokemon[id] then
      local unlock,cost=rotatingPrizeTier(game,id)
      rewards[#rewards+1]={
        id=id,cost=cost,unlock=unlock,rotating=true,slot=i,
        sold=mod.save:get("bp_rotating_sold_"..i,false)==true,
      }
    end
  end
  return rewards
end

local function rotationStepsRemaining(game)
  local _,steps=currentRotationEpoch(game)
  local into=steps%BP_ROTATION_STEPS
  return BP_ROTATION_STEPS-into
end

local function randomizedFactorySets(game,sets,context)
  if not pokeSurviveRandomizerActive(game) then return sets end
  local out,used={},{}
  for i,set in ipairs(sets or {}) do
    local replacement=seededFactorySpecies(game,table.concat({
      tostring(context or "set"),tostring(BF.currentClass()),
      tostring(i),tostring(set[1])
    },"|"),used,set[1])
    used[replacement]=true
    out[#out+1]={replacement,{}}
  end
  return out
end

function BF.rollDraft(game)
  BF.draft=randomUniqueSets(BF.pool(game),6)
  BF.draft=randomizedFactorySets(
    game,BF.draft,
    "draft|"..tostring(mod.save:get("streak",0))
  )
  BF.selected={}
  BF.selectionOrder={}
end

function BF.commitPlayerParty(game)
  BF.playerSets={}
  -- The actual order the player rented the three Pokemon is the party order.
  -- First selection becomes the lead, second selection slot 2, third slot 3.
  for _,i in ipairs(BF.selectionOrder or {}) do
    if BF.selected[i] and BF.draft[i] then
      BF.playerSets[#BF.playerSets+1]=copySet(BF.draft[i])
    end
  end
  if #BF.playerSets~=3 then return false end

  -- Only the first Factory rental commit snapshots the adventure party.
  -- Class promotions and rerentals must NEVER overwrite that original backup
  -- with the temporary rental party.
  escrowAdventureParty(game)

  game.save.party={}
  for _,set in ipairs(BF.playerSets) do
    game.save.party[#game.save.party+1]=makeRental(game,set)
  end
  return true
end

local function isFactoryTrainer(id)
  if id==TRAINER then return true end
  for _,def in ipairs(REGULAR_TRAINERS) do
    if id==def.id then return true end
  end
  for _,bossId in pairs(BOSS_TRAINERS) do
    if id==bossId then return true end
  end
  return false
end

local function randomRegularTrainerId()
  if #REGULAR_TRAINERS==0 then return TRAINER end
  if #REGULAR_TRAINERS==1 then
    BF.lastRegularTrainer=REGULAR_TRAINERS[1].id
    return REGULAR_TRAINERS[1].id
  end

  local pick
  -- Re-roll a few times to avoid seeing the same portrait twice in a row.
  for _=1,8 do
    pick=REGULAR_TRAINERS[math.random(1,#REGULAR_TRAINERS)]
    if pick.id~=BF.lastRegularTrainer then break end
  end
  pick=pick or REGULAR_TRAINERS[1]
  BF.lastRegularTrainer=pick.id
  return pick.id
end

function BF.rollOpponent(game)
  local boss=BF.currentBoss()
  BF.activeBoss=boss
  if boss then
    BF.opponentSets={}
    for _,set in ipairs(boss.team) do
      if validRentalSet(game,set) then
        BF.opponentSets[#BF.opponentSets+1]=copySet(set)
      end
    end
    if #BF.opponentSets~=3 then
      BF.activeBoss=nil
      BF.opponentSets={}
    end
  end

  if not BF.activeBoss then
    local blocked={}
    for _,set in ipairs(BF.playerSets) do blocked[set[1]]=true end
    BF.opponentSets=randomUniqueSets(BF.pool(game),3,blocked)
  end

  BF.opponentSets=randomizedFactorySets(
    game,BF.opponentSets,
    (BF.activeBoss and ("head|"..tostring(BF.activeBoss.name))
      or ("opponent|"..tostring(mod.save:get("streak",0))))
  )

  local names={}
  for _,set in ipairs(BF.opponentSets) do names[#names+1]=set[1] end
  mod.save:set("last_battle_class",BF.currentClass())
  mod.save:set("last_battle_opp",table.concat(names," / "))
  mod.save:set("last_battle_boss",BF.activeBoss and BF.activeBoss.name or "")
end

function BF.resetRun(game)
  BF.draft=nil
  BF.selected={}
  BF.selectionOrder={}
  BF.playerSets={}
  BF.opponentSets={}
  BF.pendingTake=nil
  BF.activeBoss=nil
  BF.transitioning=false
  BF.lastRegularTrainer=nil
  game.save.party={}
  mod.save:set("streak",0)
  mod.save:set("adventure_party_backup",nil)
  mod.save:set("party_escrow_active",false)
end

local function clearFactoryRunState()
  BF.draft=nil
  BF.selected={}
  BF.selectionOrder={}
  BF.playerSets={}
  BF.opponentSets={}
  BF.pendingTake=nil
  BF.activeBoss=nil
  BF.transitioning=false
end

function BF.retireRun(game)
  mod.save:set("streak",0)
  restoreAdventureParty(game)
  clearFactoryRunState()
  game.stack:push(mod.ui.TextBox.new(game,
    pacedDialogue("Your Factory run has ended.")))
end

function BF.promptReady(game)
  local nextBattle=BF.battleNumber()

  -- Keep the question visible while the choice is active. The native TextBox
  -- choice renderer is also kept compact here: two rows, no oversized blank
  -- menu area.
  game.stack:push(mod.ui.TextBox.new(game,
    pacedDialogue("Ready for BATTLE "..tostring(nextBattle).."?"),
    nil,{
      choiceLabels={"YES","RETIRE"},
      -- Slightly wider and shifted left so RETIRE has full padding.
      choiceBox={tx=11,ty=8,tw=9,th=5,rowStep=2},
      choice=function(yes)
        if yes then
          BF.transitioning=true
          BF.startBattle(game)
        else
          BF.retireRun(game)
        end
      end,
    }))
end

function BF.promptSwap(game)
  game.stack:push(mod.ui.TextBox.new(game,
    pacedDialogue("Would you like to swap POKéMON?"),
    nil,{
      choice=function(yes)
        if yes then
          -- BF.opponentSets still contains the trainer just defeated. Do not
          -- roll the next opponent until after the swap decision is complete.
          mod.ui.push(game,SWAP)
        else
          BF.promptReady(game)
        end
      end,
    }))
end

function BF.afterSwap(game)
  if BF.transitioning then return end
  healRentals(game)

  -- Both NO SWAP and a completed DROP arrive here with the defeated-team
  -- screen on top. Remove it so the player is visibly back in the Factory
  -- overworld before the receptionist-style ready prompt appears.
  local top=game.stack:top()
  if top then game.stack:pop() end

  BF.promptReady(game)
end

function BF.startBattle(game)
  if not BF.transitioning then BF.transitioning=true end
  BF.rollOpponent(game)
  local WorldAPI=require("src.world.WorldAPI")
  local ow=WorldAPI.new(game,mod.id):overworld()
  if not ow then
    game.stack:push(mod.ui.TextBox.new(game,pacedDialogue("The Factory battle room isn't ready.")))
    return
  end

  local BattleState=require("src.battle.BattleState")
  local trainerId
  if BF.activeBoss then
    trainerId=BF.activeBoss.trainerId
  else
    trainerId=randomRegularTrainerId()
  end
  local battle=BattleState.newTrainer(game,trainerId,1,{playerPartyIndices={1,2,3}})
  battle.factoryBattle=true

  battle.openItems=function(self)
    self.phase="messages"
    self.afterQueue="menu"
    self:say("No items allowed\nin the FACTORY!")
  end

  battle.tryRun=function(self)
    self.phase="messages"
    self.afterQueue="menu"
    self:say("Can't run from a\nFACTORY match!")
  end

  -- Factory rules: the Bag and fleeing are unavailable. These overrides are
  -- local to this Factory battle instance and do not alter defeat handling.
  battle.openItems=function(self)
    self.phase="messages"
    self.afterQueue="menu"
    self:say("No items allowed\nin the FACTORY!")
  end

  battle.tryRun=function(self)
    self.phase="messages"
    self.afterQueue="menu"
    self:say("Can't run from a\nFACTORY match!")
  end
  if BF.activeBoss then
    battle.introText="FACTORY HEAD "..BF.activeBoss.name.."\nwants to fight!"
  else
    battle.introText="FACTORY TRAINER\nwants to fight!"
  end
  battle.onFinish=function(result)
    BF.transitioning=false
    require("src.core.Music").playMap(game.data,MAP,false,false)

    -- A rental faint is battle-local damage, never persistent party state.
    -- Restore the full rental trio before any overworld/input hooks can see
    -- fainted rentals. This also guarantees the next match always starts with
    -- the same three rentals fully healed.
    healRentals(game)

    if result=="win" then
      local streak=(tonumber(mod.save:get("streak",0)) or 0)+1
      mod.save:set("streak",streak)
      mod.save:set("best",math.max(streak,tonumber(mod.save:get("best",0)) or 0))
      local bpEarned=1
      addBP(1)
      if streak%7==0 then
        local cleared=math.min(9,math.floor((streak-1)/7)+1)
        local nextClass=BF.currentClass()

        -- Class-clear bonus.
        addBP(5)
        bpEarned=bpEarned+5

        -- First clear of each class gets an additional 5 BP and advances
        -- permanent reward unlocks.
        local highest=highestClassCleared()
        if cleared>highest then
          addBP(5)
          bpEarned=bpEarned+5
          mod.save:set("highest_class_cleared",cleared)
        end

        -- Class 9 is the capstone.
        if cleared>=9 then
          addBP(15)
          bpEarned=bpEarned+15
        end

        local msg
        local defeatedBoss=BF.activeBoss and BF.activeBoss.name or nil
        if cleared>=9 then
          msg=(defeatedBoss and ("FACTORY HEAD "..defeatedBoss.." defeated!\f") or "")..
              "CLASS 9 CLEARED!\fMASTER CLASS continues with the strongest rental pool."
        else
          msg=(defeatedBoss and ("FACTORY HEAD "..defeatedBoss.." defeated!\f") or "")..
              "CLASS "..tostring(cleared).." CLEARED!\fYou have been promoted to CLASS "..tostring(nextClass).."!"
        end
        msg=msg.."\fYou earned "..tostring(bpEarned).." BP.\fBP TOTAL "..tostring(bpBalance()).."."
        game.stack:push(mod.ui.TextBox.new(game,
          pacedDialogue(msg),
          function()
            BF.draft=nil
            BF.selected={}
            BF.selectionOrder={}
            BF.playerSets={}
            BF.opponentSets={}
            -- Keep the current rentals alive while the promotion draft is
            -- open. The replacement trio is installed only on BEGIN BATTLE.
            BF.rollDraft(game)
            mod.ui.push(game,DRAFT)
          end))
      else
        -- Normal post-win flow stays entirely on the Factory overworld until
        -- the player explicitly asks to inspect the defeated trainer's team.
        -- This prevents stale swap-screen art from sitting under dialogue.
        game.stack:push(mod.ui.TextBox.new(game,
          pacedDialogue("You earned 1 BP.\fYour rental POKéMON were fully restored."),
          function()
            BF.promptSwap(game)
          end))
      end
    else
      -- Keep the confirmed-stable dev.7.11 loss callback itself untouched:
      -- only reset the streak and show the run-ending TextBox while battle
      -- teardown completes.
      mod.save:set("streak",0)
      game.stack:push(mod.ui.TextBox.new(game,
        pacedDialogue("Your Factory streak ended.\fBack to the rental counter!"),
        function()
          -- TextBox pops itself BEFORE onDone, so this runs only after both
          -- the battle and the run-ending message have completely left the
          -- stack. This is the first truly safe boundary for post-loss cleanup.
          --
          -- Do not open another rental screen. Return directly to the lobby.
          -- The battle/blackout transition is completely finished here.
          -- Throw away the rentals and put the player's original adventure
          -- party back exactly as it was before entering the run.
          restoreAdventureParty(game)
          BF.draft=nil
          BF.selected={}
          BF.selectionOrder={}
          BF.playerSets={}
          BF.opponentSets={}
          BF.pendingTake=nil
          BF.activeBoss=nil
          BF.transitioning=false
        end))
    end
  end
  ow:pushBattle(battle)
end

return function(mod_)
  -- expose the loader-owned object to the helper functions above without
  -- creating a second private dependency surface.
  mod=mod_

  -- Dev.4.2 lobby: vanilla Pokemon Center architecture adapted as a
  -- Battle Factory test facility. The layout gives us a real counter,
  -- workstation area, and the familiar two-tile exit mat.
  mod.content.maps:register(MAP,{
    id=MAP,label="BattleFactoryRecomp",index=1001,
    tileset="POKECENTER",width=7,height=4,
    blocks={
      32,16, 1, 2,12,13,13,
      33, 4, 5, 7, 7,34,35,
       8,15,15,15,15,15,27,
      14,10,11,14,15,15,14,
    },
    borderBlock=0,
    warps={
      {x=3,y=7,destMap="SAFFRON_CITY",destWarp=9},
      {x=4,y=7,destMap="SAFFRON_CITY",destWarp=9},
    },
    signs={
      {x=0,y=4,text="TEXT_BF_TRAINER1"},
      {x=1,y=6,text="TEXT_BF_STREAK_SIGN"},
      {x=12,y=6,text="TEXT_BF_BEST_SIGN"},
    },
    objects={
      -- Oak uses the same overworld sprite as Red's Name Rater.
      {index=1,x=3,y=1,sprite="SPRITE_SILPH_PRESIDENT",movement="STAY",range="DOWN",
       text="TEXT_BF_BP_CLERK",name="BF_BP_CLERK"},

      -- The right counter uses the Gym Guide sprite for the rules attendant,
      -- with the receptionist standing in the open service gap.
      {index=2,x=8,y=1,sprite="SPRITE_GYM_GUIDE",movement="STAY",range="DOWN",
       text="TEXT_BF_SCIENTIST",name="BF_SCIENTIST"},
      {index=3,x=11,y=2,sprite="SPRITE_NURSE",movement="STAY",range="DOWN",
       text="TEXT_BF_RECEPTIONIST",name="BF_RECEPTIONIST"},

      -- The only floor competitor is placed directly below the far-right PC.
      {index=4,x=13,y=4,sprite="SPRITE_ROCKER",movement="STAY",range="UP",
       text="TEXT_BF_TRAINER2",name="BF_TRAINER2"},
    },
  })

  mod.content.map_songs:register(MAP,"Music_Celadon")

  -- Saffron City exterior integration test.
  --
  -- Keep the map on the REAL OVERWORLD tileset so Gen 1's normal Saffron
  -- colorization/palette rules remain intact. We append two custom blocks to
  -- OVERWORLD without changing any existing block IDs:
  --   1) original facade + only Silph Co's 16x16 door quadrant
  --   2) original facade + only Silph Co's actual sign quadrant
  do
    local saffron=mod.content.maps:get("SAFFRON_CITY")
    local overworld=mod.content.tilesets:get("OVERWORLD")
    if saffron and saffron.blocks and overworld and overworld.blocks then
      local mapBlocks={}
      for i,v in ipairs(saffron.blocks) do mapBlocks[i]=v end

      local tileBlocks={}
      for i,row in ipairs(overworld.blocks) do
        local copy={}
        for j,v in ipairs(row) do copy[j]=v end
        tileBlocks[i]=copy
      end

      local function blockAt(cellX,cellY)
        local bx=math.floor(cellX/2)
        local by=math.floor(cellY/2)
        return saffron.blocks[by*20+bx+1], by*20+bx+1
      end

      local function hybridQuadrant(baseId, donorId, donorX, donorY, targetX, targetY)
        local base=tileBlocks[baseId+1]
        local donor=tileBlocks[donorId+1]
        local out={}
        for i,v in ipairs(base) do out[i]=v end

        local dgx=(donorX%2)*2
        local dgy=(donorY%2)*2
        local tgx=(targetX%2)*2
        local tgy=(targetY%2)*2

        for dy=0,1 do
          for dx=0,1 do
            local src=(dgy+dy)*4+(dgx+dx)+1
            local dst=(tgy+dy)*4+(tgx+dx)+1
            out[dst]=donor[src]
          end
        end

        tileBlocks[#tileBlocks+1]=out
        return #tileBlocks-1
      end

      -- Door: borrow ONLY Silph Co's door cell at (18,21), then insert it
      -- into the chosen generic building at (30,21).
      local doorDonor=blockAt(18,21)
      local doorBase,doorMapIndex=blockAt(30,21)
      local doorBlock=hybridQuadrant(doorBase,doorDonor,18,21,30,21)
      mapBlocks[doorMapIndex]=doorBlock

      -- Sign: vanilla Saffron data confirms Silph Co's actual sign is
      -- bg_event (15,21). Copy that exact sign cell to (28,21), immediately
      -- left of the new Factory entrance.
      local signDonor=blockAt(15,21)
      local signBase,signMapIndex=blockAt(28,21)
      -- If door/sign share a map block in a future layout, build from the
      -- already-modified block. They do not in the current placement.
      local signBlock=hybridQuadrant(signBase,signDonor,15,21,28,21)
      mapBlocks[signMapIndex]=signBlock

      -- Override OVERWORLD with an exact clone plus our appended blocks.
      -- Existing block IDs/graphics remain byte-for-byte unchanged, while
      -- Saffron keeps tileset="OVERWORLD" and therefore its normal colors.
      mod.content.tilesets:override("OVERWORLD",{
        id=overworld.id or "OVERWORLD",
        image=overworld.image,
        imageWidth=overworld.imageWidth,
        imageHeight=overworld.imageHeight,
        tilesPerRow=overworld.tilesPerRow,
        blocks=tileBlocks,
        walkable=overworld.walkable,
        counterTiles=overworld.counterTiles,
        doorTiles=overworld.doorTiles,
        warpTiles=overworld.warpTiles,
        animation=overworld.animation,
        trueColor=overworld.trueColor,
      })

      mod.content.maps:patch("SAFFRON_CITY",{
        blocks=mapBlocks,

        -- Map list patches append by default, so use ordinary records here.
        -- The prior nested __append form drew the sign graphic but never
        -- created a usable signAt interaction entry.
        warps={__append={
          {x=30,y=21,destMap=MAP,destWarp=1},
        }},
        signs={__append={
          {x=28,y=21,text="TEXT_BF_SAFFRON_SIGN"},
        }},
      })
    end
  end

  mod.content.text:register("TEXT_BF_SAFFRON_SIGN",
    "BATTLE FACTORY@")

  mod.content.map_scripts:register("SAFFRON_CITY",{
    talk={
      TEXT_BF_SAFFRON_SIGN=function(game,ow,npc,done)
        game.stack:push(mod.ui.TextBox.new(game,
          pacedDialogue("BATTLE FACTORY\fTest your skill with rental\fPOKéMON!"),
          done))
      end,
    },
    priority=100,
  })


  -- Neutral fallback record plus a large pool of regular Factory challenger
  -- portraits. The trainer.party hook below supplies the actual rental team,
  -- so these records exist only to control battle portrait/name presentation.
  local placeholderParty={{
    {level=50,species="CATERPIE"},
    {level=50,species="WEEDLE"},
    {level=50,species="MAGIKARP"},
  }}

  mod.content.trainers:register(TRAINER,{
    id=TRAINER,name="FACTORY",basePic="OPP_COOLTRAINER_M",baseMoney=0,
    parties=placeholderParty,
  })

  for _,def in ipairs(REGULAR_TRAINERS) do
    mod.content.trainers:register(def.id,{
      id=def.id,name="FACTORY",basePic=def.pic,baseMoney=0,
      parties=placeholderParty,
    })
  end

  -- Dedicated Factory Head trainer records. These are NOT the vanilla trainer
  -- IDs, so defeating them cannot trigger gym/Elite Four victory rewards.
  -- basePic simply tells BattleState to reuse the real vanilla portrait.
  local bossTrainerDefs={
    {id=BOSS_TRAINERS.BROCK,    name="BROCK",    basePic="OPP_BROCK"},
    {id=BOSS_TRAINERS.KOGA,     name="KOGA",     basePic="OPP_KOGA"},
    {id=BOSS_TRAINERS.BLAINE,   name="BLAINE",   basePic="OPP_BLAINE"},
    {id=BOSS_TRAINERS.GIOVANNI, name="GIOVANNI", basePic="OPP_GIOVANNI"},
    {id=BOSS_TRAINERS.LORELEI,  name="LORELEI",  basePic="OPP_LORELEI"},
    {id=BOSS_TRAINERS.LANCE,    name="LANCE",    basePic="OPP_LANCE"},
    {id=BOSS_TRAINERS.OAK,      name="PROF.OAK", basePic="OPP_PROF_OAK"},
  }

  for _,def in ipairs(bossTrainerDefs) do
    mod.content.trainers:register(def.id,{
      id=def.id,name=def.name,basePic=def.basePic,baseMoney=0,
      parties={{
        {level=50,species="CATERPIE"},
        {level=50,species="WEEDLE"},
        {level=50,species="MAGIKARP"},
      }},
    })
  end

  -- Dynamic opponent roster. BattleState supports per-slot moves after the
  -- trainer.party hook, giving us faithful rental sets without generating
  -- dozens of disposable trainer records.
  mod.hooks:wrap("trainer.party",function(next_,oppClass,partyIndex,partyDef)
    local base=next_(oppClass,partyIndex,partyDef)
    if not isFactoryTrainer(oppClass) or #BF.opponentSets~=3 then return base end
    local rows={}
    local live=BF.liveGame
    for _,set in ipairs(BF.opponentSets) do
      local row={level=BF.level,species=set[1]}
      if pokeSurviveRandomizerActive(live) then
        row.moves=randomizedLevelMoves(live,set[1],BF.level)
      elseif #(set[2] or {})>0 then
        row.moves=set[2]
      end
      rows[#rows+1]=row
    end
    return rows
  end,100)

  -- Factory battles never award EXP.
  mod.hooks:wrap("battle.exp_award",function(next_,ctx)
    if ctx and ctx.battle and ctx.battle.factoryBattle then return end
    return next_(ctx)
  end,100)

  -- Party escrow safety net. Walking out of the Factory with an active
  -- rental run restores the adventure party before Saffron is loaded.
  -- This also means a player can never accidentally carry rentals into Kanto.
  BF.liveGame=nil
  mod.events:on("game.ready",function(ev)
    BF.liveGame=ev and ev.game or BF.liveGame
  end)

  mod.events:on("map.exited",function(ev)
    if ev and ev.mapId==MAP and BF.liveGame and partyEscrowActive() then
      mod.save:set("streak",0)
      restoreAdventureParty(BF.liveGame)
      BF.draft=nil
      BF.selected={}
      BF.selectionOrder={}
      BF.playerSets={}
      BF.opponentSets={}
      BF.pendingTake=nil
      BF.activeBoss=nil
      BF.transitioning=false
    end
  end)


  mod.content.screens:register(DRAFT,{
    new=function(game)
      if not BF.draft then BF.rollDraft(game) end

      local Font=mod.ui.Font
      local Theme=require("src.ui.Theme")
      local Menu=require("src.ui.Menu")

      local state={
        game=game,
        isOpaque=true,
        cursor=1,
        actionMenu=nil,
      }

      local function rowCount()
        local n=#(BF.draft or {})
        if selectedCount()==3 then n=n+1 end
        n=n+1
        return n
      end

      local function closeAction()
        state.actionMenu=nil
      end

      local function openAction(i)
        local items={}

        items[#items+1]={
          label="STATS",
          keepOpen=true,
          onSelect=function()
            openNativeRentalSummary(game,BF.draft[i])
          end,
        }

        if BF.selected[i] then
          items[#items+1]={
            label="RETURN",
            keepOpen=true,
            onSelect=function()
              BF.selected[i]=nil
              removeSelectionIndex(i)
              closeAction()
            end,
          }
        elseif selectedCount()<3 then
          items[#items+1]={
            label="CHOOSE",
            keepOpen=true,
            onSelect=function()
              BF.selected[i]=true
              BF.selectionOrder[#BF.selectionOrder+1]=i
              closeAction()
              if selectedCount()==3 then
                game.stack:push(mod.ui.TextBox.new(game,
                  pacedDialogue("Three rental POKéMON selected.")))
              end
            end,
          }
        else
          items[#items+1]={
            label="FULL",
            keepOpen=true,
            onSelect=function() end,
          }
        end

        items[#items+1]={
          label="BACK",
          keepOpen=true,
          onSelect=function() closeAction() end,
        }

        -- Native Gen-I menu: standard Font.drawBox border + Theme.cursor.
        -- 20x18 tile screen; this places the box in the lower-right corner.
        state.actionMenu=Menu.new(game,items,{
          tx=11,ty=9,tw=9,th=8,
          cancelable=false,
          rowStep=2,
        })
      end

      function state:update(dt)
        local input=game.input
        if not input then return end

        if self.actionMenu then
          -- Menu is embedded rather than pushed, so consume B ourselves.
          if input:wasPressed("b") then
            require("src.core.Sound").play(game.data,"Press_AB")
            closeAction()
            return
          end
          self.actionMenu:update(dt)
          return
        end

        -- B from the main rental roster cancels the uncommitted draft and
        -- returns to the Factory lobby. Previously only the small action popup
        -- handled B, leaving the main draft screen impossible to exit.
        if input:wasPressed("b") then
          require("src.core.Sound").play(game.data,"Press_AB")

          -- On the initial rental draft there is no escrow yet, so B is just
          -- a menu cancel. If this is a promotion draft during an active run,
          -- B means "end my Factory run": restore the real party first.
          if partyEscrowActive() then
            mod.save:set("streak",0)
            restoreAdventureParty(game)
          end

          BF.draft=nil
          BF.selected={}
          BF.selectionOrder={}
          BF.playerSets={}
          BF.opponentSets={}
          BF.pendingTake=nil
          BF.activeBoss=nil
          BF.transitioning=false
          game.stack:pop()
          return
        end

        local count=rowCount()
        if input:wasPressed("up") then
          self.cursor=self.cursor-1
          if self.cursor<1 then self.cursor=count end
        elseif input:wasPressed("down") then
          self.cursor=self.cursor+1
          if self.cursor>count then self.cursor=1 end
        elseif input:wasPressed("a") then
          require("src.core.Sound").play(game.data,"Press_AB")
          local draftCount=#BF.draft
          if self.cursor<=draftCount then
            openAction(self.cursor)
          else
            local offset=self.cursor-draftCount
            if selectedCount()==3 then
              if offset==1 then
                if not BF.transitioning and BF.commitPlayerParty(game) then
                  -- The rental draft is an opaque screen pushed over the
                  -- overworld. It MUST be removed before the battle is pushed.
                  -- Previously it remained underneath every battle, so when a
                  -- loss popped the battle the stale rental screen was exposed
                  -- again and later stack operations could crash.
                  BF.transitioning=true
                  game.stack:pop()
                  BF.startBattle(game)
                end
              elseif offset==2 then
                BF.rollDraft(game)
                self.cursor=1
              end
            elseif offset==1 then
              BF.rollDraft(game)
              self.cursor=1
            end
          end
        end
      end

      function state:draw()
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",0,0,160,144)
        love.graphics.setColor(0,0,0,1)

        Font.draw("RENT 3  ("..selectedCount().."/3)",8,6)

        local y=24
        for i,set in ipairs(BF.draft or {}) do
          if self.cursor==i and not self.actionMenu then
            Font.drawCode(Theme.cursor,8,y)
          end
          local suffix=BF.selected[i] and "  RENT" or ""
          Font.draw(speciesName(game,set[1])..suffix,16,y)
          y=y+14
        end

        local row=#BF.draft
        if selectedCount()==3 then
          row=row+1
          if self.cursor==row and not self.actionMenu then
            Font.drawCode(Theme.cursor,8,y)
          end
          Font.draw("BEGIN BATTLE",16,y)
          y=y+14
        end

        row=row+1
        if self.cursor==row and not self.actionMenu then
          Font.drawCode(Theme.cursor,8,y)
        end
        Font.draw("REROLL SIX",16,y)

        if self.actionMenu then self.actionMenu:draw() end
      end

      return state
    end,
  })

  mod.content.screens:register(SWAP,{
    new=function(game)
      local Font=mod.ui.Font
      local Theme=require("src.ui.Theme")
      local Menu=require("src.ui.Menu")

      -- Freeze what was actually used by the defeated trainer. BF.opponentSets
      -- is replaced immediately when the next battle is generated, and using
      -- it directly here made the visible roster briefly morph during the
      -- transition.
      local displayedSets={}
      for i,set in ipairs(BF.opponentSets or {}) do
        displayedSets[i]=copySet(set)
      end

      local state={
        game=game,
        isOpaque=true,
        cursor=1,
        actionMenu=nil,
      }

      local function closeAction()
        state.actionMenu=nil
      end

      local function openAction(i)
        local set=displayedSets[i]
        local items={
          {
            label="STATS",
            keepOpen=true,
            onSelect=function()
              openNativeRentalSummary(game,set)
            end,
          },
          {
            label="TAKE",
            keepOpen=true,
            onSelect=function()
              BF.pendingTake=i
              closeAction()
              mod.ui.push(game,DROP)
            end,
          },
          {
            label="BACK",
            keepOpen=true,
            onSelect=function() closeAction() end,
          },
        }

        state.actionMenu=Menu.new(game,items,{
          tx=11,ty=9,tw=9,th=8,
          cancelable=false,
          rowStep=2,
        })
      end

      function state:update(dt)
        local input=game.input
        if not input then return end

        if self.actionMenu then
          if input:wasPressed("b") then
            require("src.core.Sound").play(game.data,"Press_AB")
            closeAction()
            return
          end
          self.actionMenu:update(dt)
          return
        end

        local count=#displayedSets+1
        if input:wasPressed("up") then
          self.cursor=self.cursor-1
          if self.cursor<1 then self.cursor=count end
        elseif input:wasPressed("down") then
          self.cursor=self.cursor+1
          if self.cursor>count then self.cursor=1 end
        elseif input:wasPressed("b") then
          BF.afterSwap(game)
        elseif input:wasPressed("a") then
          require("src.core.Sound").play(game.data,"Press_AB")
          if self.cursor<=#displayedSets then
            openAction(self.cursor)
          else
            BF.afterSwap(game)
          end
        end
      end

      function state:draw()
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",0,0,160,144)
        love.graphics.setColor(0,0,0,1)

        Font.draw("DEFEATED TEAM",8,6)

        local y=28
        for i,set in ipairs(displayedSets) do
          if self.cursor==i and not self.actionMenu then
            Font.drawCode(Theme.cursor,8,y)
          end
          Font.draw(speciesName(game,set[1]),16,y)
          y=y+18
        end

        local noSwap=#displayedSets+1
        if self.cursor==noSwap and not self.actionMenu then
          Font.drawCode(Theme.cursor,8,y+6)
        end
        Font.draw("NO SWAP",16,y+6)

        if self.actionMenu then self.actionMenu:draw() end
      end

      return state
    end,
  })

  mod.content.screens:register(BP_MENU,{
    new=function(game)
      local items={
        {label="ITEMS",right=">",items=true},
        {label="POKéMON",right=">",mons=true},
        {label="NEVER MIND",right="<",back=true},
      }
      return mod.ui.ListMenu.new(game,"BP EXCHANGE  "..bpBalance().." BP",items,{
        onChoose=function(item,menu)
          -- Keep the parent BP Exchange screen on the stack while browsing a
          -- child prize list. Then B/Back in the child simply pops back here.
          if item.items then mod.ui.push(game,BP_ITEMS)
          elseif item.mons then mod.ui.push(game,BP_MONS)
          elseif item.back then menu:close() end
        end,
        onCancel=function() end,
      })
    end,
  })

  mod.content.screens:register(BP_ITEMS,{
    new=function(game)
      local Font=mod.ui.Font
      local Theme=require("src.ui.Theme")
      local Menu=require("src.ui.Menu")
      local highest=highestClassCleared()
      local rewards={}
      for _,reward in ipairs(BF.bpItems) do
        if game.data.items[reward.id] then rewards[#rewards+1]=reward end
      end

      local state={game=game,isOpaque=true,cursor=1,confirmMenu=nil}

      local function closeConfirm() state.confirmMenu=nil end
      local function openConfirm(r)
        state.confirmMenu=Menu.new(game,{
          {label="YES",keepOpen=true,onSelect=function()
            if bpBalance()<r.cost then
              closeConfirm()
              game.stack:push(mod.ui.TextBox.new(game,pacedDialogue("Not enough BP.")))
              return
            end
            if not giveBPItem(game,r.id) then
              closeConfirm()
              game.stack:push(mod.ui.TextBox.new(game,pacedDialogue("Your BAG is full.")))
              return
            end
            addBP(-r.cost)
            if r.rotating then
              local soldKey="bp_rotating_sold_"..tostring(r.slot)
              mod.save:set(soldKey,true)
              r.sold=true
              -- Defensive readback so a save-backend coercion problem is
              -- visible immediately rather than silently allowing duplicates.
              if mod.save:get(soldKey,false)~=true then
                mod.save:set(soldKey,true)
              end
            end
            closeConfirm()
            game.stack:push(mod.ui.TextBox.new(game,
              pacedDialogue("Received "..rewardName(game,r.id,"item").."!")))
          end},
          {label="NO",keepOpen=true,onSelect=function() closeConfirm() end},
        },{
          -- Small native bordered popup over the lower-right of the prize list.
          tx=11,ty=11,tw=8,th=6,cancelable=false,rowStep=2,
        })
      end

      function state:update(dt)
        local input=game.input
        if not input then return end
        if self.confirmMenu then
          if input:wasPressed("b") then
            require("src.core.Sound").play(game.data,"Press_AB")
            closeConfirm()
            return
          end
          self.confirmMenu:update(dt)
          return
        end

        local count=#rewards+1
        if input:wasPressed("up") then
          self.cursor=self.cursor-1
          if self.cursor<1 then self.cursor=count end
        elseif input:wasPressed("down") then
          self.cursor=self.cursor+1
          if self.cursor>count then self.cursor=1 end
        elseif input:wasPressed("b") then
          require("src.core.Sound").play(game.data,"Press_AB")
          game.stack:pop()
        elseif input:wasPressed("a") then
          require("src.core.Sound").play(game.data,"Press_AB")
          if self.cursor<=#rewards then
            local r=rewards[self.cursor]
            if highest<(r.unlock or 1) then
              game.stack:push(mod.ui.TextBox.new(game,
                pacedDialogue("Clear CLASS "..tostring(r.unlock).." to unlock this TM.")))
            else
              openConfirm(r)
            end
          else game.stack:pop() end
        end
      end

      function state:draw()
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",0,0,160,144)
        love.graphics.setColor(0,0,0,1)
        Font.draw("TM PRIZES",8,6)
        Font.draw(tostring(bpBalance()).." BP",116,6)
        local y=24
        for i,r in ipairs(rewards) do
          if i>=math.max(1,self.cursor-5) and i<=math.max(6,self.cursor) then
            local first=math.max(1,self.cursor-5)
            local yy=24+(i-first)*18
            if self.cursor==i and not self.confirmMenu then Font.drawCode(Theme.cursor,8,yy) end
            Font.draw(r.label or rewardName(game,r.id,"item"),16,yy)
            local right=(highest>=(r.unlock or 1))
              and (tostring(r.cost).."BP") or ("C"..tostring(r.unlock or 1))
            Font.draw(right,120,yy)
          end
        end
        if self.cursor==#rewards+1 and not self.confirmMenu then
          Font.drawCode(Theme.cursor,8,132)
          Font.draw("BACK",16,132)
        end
        if self.confirmMenu then self.confirmMenu:draw() end
      end
      return state
    end,
  })

  mod.content.screens:register(BP_MONS,{
    new=function(game)
      local Font=mod.ui.Font
      local Theme=require("src.ui.Theme")
      local Menu=require("src.ui.Menu")
      local highest=highestClassCleared()
      local rewards={}
      local rotating=pokeSurviveRandomizerActive(game)
      if rotating then
        rewards=rotatingPokemonRewards(game)
      else
        for _,r in ipairs(BF.bpPokemon) do
          if game.data.pokemon[r.id] and (not r.postgame or isChampion(game)) then
            rewards[#rewards+1]=r
          end
        end
      end
      local state={game=game,isOpaque=true,cursor=1,confirmMenu=nil}

      local function closeConfirm() state.confirmMenu=nil end
      local function openConfirm(r)
        state.confirmMenu=Menu.new(game,{
          {label="YES",keepOpen=true,onSelect=function()
            if r.rotating
              and mod.save:get("bp_rotating_sold_"..tostring(r.slot),false)==true then
              r.sold=true
              closeConfirm()
              game.stack:push(mod.ui.TextBox.new(game,
                pacedDialogue("That POKéMON is already SOLD.")))
              return
            end
            if bpBalance()<r.cost then
              closeConfirm();game.stack:push(mod.ui.TextBox.new(game,pacedDialogue("Not enough BP.")));return
            end
            local box=giveBPPokemon(game,r.id)
            if not box then
              closeConfirm();game.stack:push(mod.ui.TextBox.new(game,pacedDialogue("POKéMON BOXES are full.")));return
            end
            addBP(-r.cost)
            closeConfirm()
            game.stack:push(mod.ui.TextBox.new(game,
              pacedDialogue("Received "..rewardName(game,r.id,"pokemon").."!\fSent to BOX "..box..".")))
          end},
          {label="NO",keepOpen=true,onSelect=function() closeConfirm() end},
        },{tx=11,ty=11,tw=8,th=6,cancelable=false,rowStep=2})
      end

      function state:update(dt)
        local input=game.input;if not input then return end
        if self.confirmMenu then
          if input:wasPressed("b") then require("src.core.Sound").play(game.data,"Press_AB");closeConfirm();return end
          self.confirmMenu:update(dt);return
        end
        local count=#rewards+1
        if input:wasPressed("up") then self.cursor=self.cursor-1;if self.cursor<1 then self.cursor=count end
        elseif input:wasPressed("down") then self.cursor=self.cursor+1;if self.cursor>count then self.cursor=1 end
        elseif input:wasPressed("b") then require("src.core.Sound").play(game.data,"Press_AB");game.stack:pop()
        elseif input:wasPressed("a") then
          require("src.core.Sound").play(game.data,"Press_AB")
          if self.cursor<=#rewards then
            local r=rewards[self.cursor]
            local soldNow=r.rotating
              and mod.save:get("bp_rotating_sold_"..tostring(r.slot),false)==true
            if soldNow then
              r.sold=true
              game.stack:push(mod.ui.TextBox.new(game,
                pacedDialogue("That POKéMON is SOLD for this stock.")))
            elseif r.postgame then
              -- Postgame rewards are only added to this menu for Champion saves.
              openConfirm(r)
            elseif highest<r.unlock then
              game.stack:push(mod.ui.TextBox.new(game,pacedDialogue("Clear CLASS "..r.unlock.." to unlock this prize.")))
            else openConfirm(r) end
          else game.stack:pop() end
        end
      end

      function state:draw()
        love.graphics.setColor(1,1,1,1);love.graphics.rectangle("fill",0,0,160,144);love.graphics.setColor(0,0,0,1)
        Font.draw(rotating and "MON STOCK" or "MON PRIZES",8,6)
        Font.draw(tostring(bpBalance()).." BP",116,6)
        local first=math.max(1,self.cursor-5)
        for i=first,math.min(#rewards,first+5) do
          local r=rewards[i];local yy=24+(i-first)*18
          if self.cursor==i and not self.confirmMenu then Font.drawCode(Theme.cursor,8,yy) end
          Font.draw(rewardName(game,r.id,"pokemon"),16,yy)
          local right
          local soldNow=r.rotating
            and mod.save:get("bp_rotating_sold_"..tostring(r.slot),false)==true
          if soldNow then
            r.sold=true
            right="SOLD"
          elseif r.postgame then
            right=tostring(r.cost).."BP"
          elseif highest>=r.unlock then
            right=tostring(r.cost).."BP"
          else
            right="C"..tostring(r.unlock)
          end
          Font.draw(right,120,yy)
        end
        if self.cursor==#rewards+1 and not self.confirmMenu then
          Font.drawCode(Theme.cursor,8,132);Font.draw("BACK",16,132)
        elseif rotating and not self.confirmMenu then
          Font.draw("REFRESH "..tostring(rotationStepsRemaining(game)).." ST",8,132)
        end
        if self.confirmMenu then self.confirmMenu:draw() end
      end
      return state
    end,
  })

  mod.content.screens:register(DROP,{
    new=function(game)
      local items={}
      for i,set in ipairs(BF.playerSets) do
        items[#items+1]={label=speciesName(game,set[1]),right="DROP",drop=i}
      end
      items[#items+1]={label="BACK TO ENEMY",right="<",back=true}
      return mod.ui.ListMenu.new(game,"RETURN WHICH?",items,{
        onChoose=function(item,menu)
          if item.drop and BF.pendingTake then
            local replacement=copySet(BF.opponentSets[BF.pendingTake])
            BF.playerSets[item.drop]=replacement
            game.save.party[item.drop]=makeRental(game,replacement)
            BF.pendingTake=nil
            menu:close();BF.afterSwap(game)
          elseif item.back then
            BF.pendingTake=nil;menu:close();mod.ui.push(game,SWAP)
          end
        end,
        onCancel=function() BF.pendingTake=nil;mod.ui.push(game,SWAP) end,
      })
    end,
  })

  -- Receptionist and lobby flavor.
  mod.content.commands:register("battle_factory_recomp:open_bp_exchange",{
    foreground=true,
    fn=function(ctx)
      mod.ui.push(ctx.game,BP_MENU)
    end,
  })

  mod.content.commands:register("battle_factory_recomp:open_draft",{
    foreground=true,
    fn=function(ctx)
      BF.rollDraft(ctx.game)
      mod.ui.push(ctx.game,DRAFT)
    end,
  })

  mod.content.tokens:register("BF_BP",function() return tostring(bpBalance()) end)
  mod.content.tokens:register("BF_HIGHEST_CLASS",function() return tostring(highestClassCleared()) end)
  mod.content.tokens:register("BF_STREAK",function() return tostring(mod.save:get("streak",0) or 0) end)
  mod.content.tokens:register("BF_CLASS",function() return tostring(BF.currentClass()) end)
  mod.content.tokens:register("BF_BEST",function() return tostring(mod.save:get("best",0) or 0) end)
  mod.content.tokens:register("BF_LAST_CLASS",function()
    return tostring(mod.save:get("last_battle_class","-") or "-")
  end)
  mod.content.tokens:register("BF_LAST_OPP",function()
    return tostring(mod.save:get("last_battle_opp","NONE") or "NONE")
  end)

  mod.content.map_scripts:register(MAP,{
    talk={
      TEXT_BF_RECEPTIONIST={
        {"show_text",pacedDialogue(
          "Welcome to the BATTLE FACTORY!\f"
          .."Your current challenge is CLASS {BF_CLASS}.\f"
          .."Would you like to rent a team and begin?"
        )},
        {"choice",{"RENT POKéMON","NOT YET"}},
        {"jump_if_false","end"},
        {"battle_factory_recomp:open_draft"},
      },
      TEXT_BF_BP_CLERK={
        {"show_text",pacedDialogue("Welcome to the BP EXCHANGE!\fYou currently have {BF_BP} BP.\fTrade BP for rare TMs and POKéMON.")},
        {"battle_factory_recomp:open_bp_exchange"},
      },
      TEXT_BF_SCIENTIST={
        {"show_text",pacedDialogue(
          "Here are the BATTLE FACTORY rules.\f"
          .."First, you are shown six rental POKéMON. Choose three to form your team.\f"
          .."All FACTORY battles use those rentals. Their HP is restored after each victory.\f"
          .."After a win, you may exchange one of your rentals for one used by the defeated TRAINER.\f"
          .."Win seven battles in a row to clear a FACTORY CLASS and receive a new rental selection.\f"
          .."There are nine rental classes. Higher classes contain stronger POKéMON and movesets.\f"
          .."Lose a battle and your current winning streak ends."
        )},
      },
      TEXT_BF_TRAINER1={
        {"show_text",pacedDialogue("I'm comparing rental records. Don't judge a POKéMON by species alone. Check its moves before you rent it!")},
      },
      TEXT_BF_TRAINER2={
        {"show_text",pacedDialogue("These PCs keep Factory rental data. I always check my options before deciding what to swap.")},
      },
      TEXT_BF_STREAK_SIGN={{"show_text","CURRENT STREAK\\n{BF_STREAK}"}},
      TEXT_BF_BEST_SIGN={{"show_text",pacedDialogue("BEST STREAK {BF_BEST}\fLAST BATTLE C{BF_LAST_CLASS}\n{BF_LAST_OPP}")}},
    },
    onEnter=function(game,ow)
      require("src.core.Music").playMap(game.data,MAP,false,false)
    end,
  })

  mod.events:on("save.created",function()
    mod.save:set("streak",0)
    mod.save:set("best",0)
    mod.save:set("bp",100)
    mod.save:set("highest_class_cleared",0)
    mod.save:set("adventure_party_backup",nil)
    mod.save:set("party_escrow_active",false)
    BF.draft=nil;BF.selected={};BF.selectionOrder={};BF.playerSets={};BF.opponentSets={};BF.transitioning=false


  end)
end
