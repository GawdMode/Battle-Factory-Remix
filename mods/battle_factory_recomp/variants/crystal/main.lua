-- Battle Factory Remix
-- Native escorted Battle Tower route.
--
-- BATTLE FACTORY at receptionist ->
--   party escrow + rentals ->
--   vanilla receptionist challenge flow ->
--   attendant escort to elevator ->
--   Battle Tower hallway ->
--   Battle Tower battle room ->
--   Factory opponent + Factory battle ->
--   native exit back to lobby.
--
-- This pass keeps one fixed battle. Rental selection / multi-battle flow comes next.

return function(mod)
  local Vm=require("src.script.gen2.Vm")
  local Specials=require("src.script.gen2.Specials")
  local Strings=require("src.core.Strings")
  local Mon=require("src.battle.gen2.Mon")
  local Battle=require("src.battle.gen2.Battle")
  local Prize=require("src.battle.gen2.Prize")
  local BattleTower=require("src.core.gen2.BattleTower")
  local Music=require("src.core.Music")
  local Bag=require("src.inventory.Bag")
  local ScriptMenu=require("src.ui.gen2.ScriptMenu")
  local Boxes=require("src.pokemon.Boxes")

  -- gen1recomp 0.2.29 carries Gen 2 animation/AI metadata for these effects
  -- but no primary battle-effect runner, so random Factory moves can expose
  -- them as apparent no-ops. Fill those engine gaps here.
  mod.content.move_effects:patch("EFFECT_BELLY_DRUM",{
    kind="primary",
    run=function(battle,attacker,defender,def,moveId)
      local maxHp=attacker.maxHp or (attacker.stats and attacker.stats.hp) or 1
      local cost=math.floor(maxHp/2)
      local side=battle:sideOf(attacker)
      local stages=battle.stages and battle.stages[side]
      local attackStage=(stages and stages.attack) or 0
      if (attacker.hp or 0)<=cost or attackStage>=6 then
        battle:markMissed()
        battle:emit({kind="message",text="But it failed!"})
        return
      end
      attacker.hp=attacker.hp-cost
      battle:emit({kind="damage",side=side,amount=cost,hp=attacker.hp,anim=false})
      battle:changeStage(attacker,"attack",6-attackStage)
    end,
  })

  -- Gen II Mimic is also missing from the current Gen 2 primary-effect
  -- runner.  Crystal's Mimic copies the foe's LAST used move, gives the
  -- temporary copy exactly 5 PP, and restores the original Mimic slot when
  -- the user leaves the field or the battle ends.  It fails for Sketch,
  -- Transform, Struggle, Metronome, or a move the user already knows.
  local function restoreCrystalMimic(mon)
    local state=mon and mon.volatile
    local r=state and state.bfMimicRestore
    if not r then return false end
    local slot=mon.moves and mon.moves[r.slot]
    if slot then
      slot.id=r.id
      slot.pp=r.pp
      slot.maxPp=r.maxPp
      slot.ppUps=r.ppUps
      slot.mimic=nil
    end
    state.bfMimicRestore=nil
    return true
  end

  if not Battle._battleFactoryCrystalMimicRestorePatched then
    Battle._battleFactoryCrystalMimicRestorePatched=true
    local oldClearVolatile=Battle.clearVolatile
    Battle.clearVolatile=function(self,mon,...)
      restoreCrystalMimic(mon)
      return oldClearVolatile(self,mon,...)
    end
    local oldEndBattle=Battle.endBattle
    Battle.endBattle=function(self,outcome,...)
      restoreCrystalMimic(self and self.player)
      restoreCrystalMimic(self and self.enemy)
      return oldEndBattle(self,outcome,...)
    end
  end

  mod.content.move_effects:patch("EFFECT_MIMIC",{
    kind="primary",
    run=function(battle,attacker,defender,def,moveId)
      local copied=battle:volatile(defender).lastMove
      local forbidden={
        SKETCH=true,TRANSFORM=true,STRUGGLE=true,METRONOME=true,
      }
      local invalid=(not copied) or forbidden[copied]
      if not invalid then
        for _,own in ipairs(attacker.moves or {}) do
          if own.id==copied then invalid=true break end
        end
      end
      local copiedDef=(not invalid) and battle:moveDef(copied) or nil
      local slotIndex,slot
      for i,own in ipairs(attacker.moves or {}) do
        if own.id==moveId then slotIndex,slot=i,own break end
      end
      if invalid or not copiedDef or not slot then
        battle:markMissed()
        battle:emit({kind="message",text="But it failed!"})
        return
      end
      local state=battle:volatile(attacker)
      -- Only one Mimic copy can be live at a time on the cart.  Keep the true
      -- pre-copy slot so switch/end restoration cannot leak the copied move
      -- into the rental's persistent moveset.
      if not state.bfMimicRestore then
        state.bfMimicRestore={
          slot=slotIndex,id=slot.id,pp=slot.pp,maxPp=slot.maxPp,ppUps=slot.ppUps,
        }
      end
      slot.id=copied
      slot.pp=5
      slot.maxPp=5
      slot.ppUps=0
      slot.mimic=true
      battle:emit({kind="message",
        text=battle:monName(attacker).." learned "..tostring(copiedDef.name or copied).."!"})
    end,
  })

  mod.content.move_effects:patch("EFFECT_SKETCH",{
    kind="primary",
    run=function(battle,attacker,defender,def,moveId)
      local copied=battle:volatile(defender).lastMove
      local invalid=(not copied) or copied=="SKETCH" or copied=="STRUGGLE"
      if not invalid then
        for _,own in ipairs(attacker.moves or {}) do
          if own.id==copied then invalid=true break end
        end
      end
      local copiedDef=(not invalid) and battle:moveDef(copied) or nil
      local slot=battle:findMove(attacker,moveId)
      if invalid or not copiedDef or not slot then
        battle:markMissed()
        battle:emit({kind="message",text="But it failed!"})
        return
      end
      slot.id=copied
      slot.maxPp=copiedDef.pp or slot.maxPp or 0
      slot.pp=slot.maxPp
      slot.ppUps=0
      battle:emit({kind="message",
        text=battle:monName(attacker).." sketched "..tostring(copiedDef.name or copied).."!"})
    end,
  })

  mod.content.move_effects:patch("EFFECT_DESTINY_BOND",{
    kind="primary",
    run=function(battle,attacker,defender,def,moveId)
      -- Gen II: Destiny Bond marks the user until it takes its next action.
      -- If an opposing move directly KOs it first, the attacker is taken down.
      battle:volatile(attacker).destinyBond=true
    end,
  })

  -- Clear an old Destiny Bond when its owner begins a later action. Reusing
  -- Destiny Bond immediately renews it instead.
  mod.events:on("battle.move_used",function(ev)
    local battle=ev and ev.battle
    local user=ev and ev.user
    if not (battle and user) then return end
    local state=battle:volatile(user)
    if state.destinyBond and ev.moveId~="DESTINY_BOND" then
      state.destinyBond=nil
    end
  end)

  -- Only direct move damage can trigger Destiny Bond. Residual/status damage,
  -- recoil-like bookkeeping without an opposing move, and self-KOs do not.
  mod.events:on("battle.damage_dealt",function(ev)
    local battle=ev and ev.battle
    local user=ev and ev.user
    local target=ev and ev.target
    if not (battle and user and target and ev.moveId) then return end
    if user==target or (target.hp or 0)>0 then return end
    local state=battle:volatile(target)
    if not state.destinyBond then return end
    state.destinyBond=nil
    if (user.hp or 0)<=0 then return end
    local lost=user.hp or 0
    user.hp=0
    battle:emit({kind="message",
      text=battle:monName(user).." was taken down\\nwith it!"})
    battle:emit({kind="damage",side=battle:sideOf(user),
      amount=lost,hp=0,anim=false})
  end)

  local S=Specials.shared
  local liveGame=nil
  local activeFactoryBattleVm=nil
  local factoryDialogueMode=false

  -- Hard Factory pacing rule: no dialogue page may contain more than two
  -- visible lines. TextBox.paginate performs the same 18-character wrapping
  -- the Game Boy dialogue window uses; we then insert a real page break after
  -- every pair of wrapped lines so a button press is mandatory.
  local function paceFactoryText(text)
    text=tostring(text or ""):gsub("\r","")
    local TextBox=require("src.render.TextBox")
    local pages={}
    for section in (text.."\f"):gmatch("(.-)\f") do
      if section~="" then
        local allLines={}
        -- Explicit newlines are authored layout decisions. Preserve them,
        -- while still wrapping any individual authored line that is too wide.
        for authored in (section.."\n"):gmatch("(.-)\n") do
          if authored=="" then
            allLines[#allLines+1]=""
          else
            local wrapped=TextBox.paginate(authored,18)
            for _,chunk in ipairs(wrapped or {}) do
              for _,line in ipairs(chunk or {}) do
                allLines[#allLines+1]=tostring(line or "")
              end
            end
          end
        end
        local i=1
        while i<=#allLines do
          local page=allLines[i] or ""
          if allLines[i+1]~=nil then
            page=page.."\n"..(allLines[i+1] or "")
          end
          pages[#pages+1]=page
          i=i+2
        end
      end
    end
    return table.concat(pages,"\f")
  end

  local ROWS={
    Strings.source("BATTLE TOWER"),
    Strings.source("BATTLE FACTORY"),
    Strings.source("EXPLANATION"),
    Strings.source("CANCEL"),
  }
  local FLAGS=0x80+0x20

  -- Factory script menus can exceed the physical Game Boy window. Crystal's
  -- generic ScriptMenu does not scroll, so opt our long menus into a compact
  -- scrolling window without touching vanilla menus elsewhere in the game.
  if not ScriptMenu._battleFactoryScrollPatched then
    ScriptMenu._battleFactoryScrollPatched=true
    local originalNew=ScriptMenu.new
    local originalNav=ScriptMenu.nav
    local originalDrawPanel=ScriptMenu.drawPanel

    ScriptMenu.new=function(game,opts)
      local self=originalNew(game,opts)
      local h=self.header or {}
      if h.factoryScrollable then
        self.factoryMaxVisible=math.max(1,math.floor(tonumber(h.factoryMaxVisible) or 7))
        self.factoryScroll=0
      end
      return self
    end

    local function clampFactoryScroll(self)
      if not self.factoryMaxVisible then return end
      local maxVisible=self.factoryMaxVisible
      if self.row<self.factoryScroll+1 then
        self.factoryScroll=self.row-1
      elseif self.row>self.factoryScroll+maxVisible then
        self.factoryScroll=self.row-maxVisible
      end
      local maxScroll=math.max(0,self.rows-maxVisible)
      self.factoryScroll=math.max(0,math.min(maxScroll,self.factoryScroll or 0))
    end

    ScriptMenu.nav=function(self,dir)
      originalNav(self,dir)
      clampFactoryScroll(self)
    end

    ScriptMenu.drawPanel=function(self)
      if not self.factoryMaxVisible then
        return originalDrawPanel(self)
      end

      local Chrome=require("src.ui.gen2.Chrome")
      self:drawBalance()
      local h=self.header or {}
      local left,top=h.left or 0,h.top or 0
      Chrome.box(left,top,(h.right or left)-left+1,(h.bottom or top)-top+1)

      local first=(self.factoryScroll or 0)+1
      local last=math.min(#self.items,first+self.factoryMaxVisible-1)
      local y0=self.textY
      local right=(h.right or 19)-1
      for index=first,last do
        local label=tostring(self.items[index] or "")
        local row=index-first
        local y=y0+row*2

        -- Factory BP rows carry a tab separator so their unlock/cost column can
        -- line up flush-right instead of wobbling after different item names.
        local lhs,rhs=label:match("^(.-)\t(.+)$")
        if lhs then
          Chrome.print(lhs,self.textX,y)
          local Font=require("src.render.Font")
          local width=#Font.split(rhs)
          Chrome.print(rhs,math.max(self.textX,right-width+1),y)
        else
          Chrome.print(label,self.textX,y)
        end
      end

      if self.showCursor then
        local selected=(self.row-1)*self.cols+self.col
        if selected>=first and selected<=last then
          local y=y0+(selected-first)*2
          Chrome.cursor(self.textX-1,y)
        end
      end

      -- Make hidden rows obvious.  The normal Gen 2 scrolling lists use the
      -- same solid ▼ glyph; only show it while more entries exist below the
      -- visible window so players never mistake a long Factory list for done.
      if last<#self.items then
        Chrome.print("▼",math.max(left+1,(h.right or 19)-1),(h.bottom or 17)-1)
      end
      love.graphics.setColor(1,1,1,1)
    end
  end

  local function deepCopy(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {}
    if seen[value] then return seen[value] end
    local out={}
    seen[value]=out
    for k,v in pairs(value) do out[deepCopy(k,seen)]=deepCopy(v,seen) end
    return out
  end

  -- Rentals never progress.
  if not Battle._battleFactoryCrystalNoExpPatched then
    Battle._battleFactoryCrystalNoExpPatched=true
    local original=Battle.giveExperiencePass
    Battle.giveExperiencePass=function(self,...)
      -- Neither vanilla Battle Tower nor Battle Factory battles should award
      -- progression. This suppresses EXP, stat EXP, level-ups, happiness from
      -- leveling, move learning, and the EXP text for every Tower-mode battle.
      if self and (self.inBattleTowerBattle==true
        or (self.save and self.save.pokesurvive_factory_rentals==true)) then
        return
      end
      return original(self,...)
    end
  end

  -- Factory victories pay BP, never normal adventure money. Suppress both the
  -- trainer-prize award/text and PAY DAY payouts while a Factory battle is live.
  if not Battle._battleFactoryCrystalNoMoneyPatched then
    Battle._battleFactoryCrystalNoMoneyPatched=true
    local originalAwardPrizeMoney=Battle.awardPrizeMoney
    Battle.awardPrizeMoney=function(self,...)
      if self and self.inBattleTowerBattle==true
        and self.save and self.save.pokesurvive_factory_rentals==true then
        self.prize=nil
        return nil
      end
      return originalAwardPrizeMoney(self,...)
    end
  end

  if not Prize._battleFactoryCrystalNoPayDayPatched then
    Prize._battleFactoryCrystalNoPayDayPatched=true
    local originalPayDay=Prize.payDay
    Prize.payDay=function(save,amount,amuletCoin)
      if activeFactoryBattleVm and save
        and save.pokesurvive_factory_rentals==true then
        return nil
      end
      return originalPayDay(save,amount,amuletCoin)
    end
  end

  -- Run-scoped Factory typing: species keep this rolled type for one active
  -- rental challenge, then normal game data is restored when the run ends.
  local FACTORY_TYPES={"NORMAL","FIGHTING","FLYING","POISON","GROUND","ROCK","BUG","GHOST","STEEL","FIRE","WATER","GRASS","ELECTRIC","PSYCHIC_TYPE","ICE","DRAGON","DARK"}
  -- Two middle GBC sprite colours for each type.  Dual types use one colour
  -- from each type so the rental's palette gives a visual clue to both rolls.
  local FACTORY_TYPE_COLORS={
    NORMAL={{238,218,190},{166,142,118}},
    FIGHTING={{238,112,88},{164,56,48}},
    FLYING={{174,206,255},{104,142,214}},
    POISON={{210,126,230},{132,66,160}},
    GROUND={{226,190,112},{156,116,62}},
    ROCK={{206,186,118},{132,112,58}},
    BUG={{190,218,78},{112,146,38}},
    GHOST={{158,136,214},{82,64,142}},
    STEEL={{210,220,230},{126,142,158}},
    FIRE={{255,160,82},{210,70,38}},
    WATER={{112,190,255},{50,108,210}},
    GRASS={{130,222,104},{54,148,62}},
    ELECTRIC={{255,232,92},{210,166,28}},
    PSYCHIC_TYPE={{255,136,196},{202,62,132}},
    ICE={{174,244,246},{78,174,194}},
    DRAGON={{164,126,255},{88,58,190}},
    DARK={{142,126,132},{70,58,68}},
  }
  local factoryTypeOriginals={}
  local factoryPaletteOriginals={}
  local pendingFactoryTypeMap=nil
  local function copyTypes(v) local o={} for i,x in ipairs(v or {}) do o[i]=x end return o end
  local function copyRgb(c) return c and {c[1],c[2],c[3]} or nil end
  local function copyMonPalette(entry)
    if type(entry)~="table" then return entry end
    local out={}
    for k,v in pairs(entry) do
      if (k=="normal" or k=="shiny") and type(v)=="table" then
        out[k]={copyRgb(v[1]),copyRgb(v[2])}
      else out[k]=v end
    end
    return out
  end
  local function factoryPaletteFor(types)
    local a=FACTORY_TYPE_COLORS[types and types[1]] or FACTORY_TYPE_COLORS.NORMAL
    local b=FACTORY_TYPE_COLORS[types and types[2]]
    if b then return {copyRgb(a[1]),copyRgb(b[2])} end
    return {copyRgb(a[1]),copyRgb(a[2])}
  end
  local function applyFactoryPalette(game,species,types)
    local palettes=game and game.data and game.data.gen2Palettes
    local pokemon=palettes and palettes.pokemon
    local entry=pokemon and pokemon[species]
    if type(entry)~="table" then return end
    if factoryPaletteOriginals[species]==nil then factoryPaletteOriginals[species]=copyMonPalette(entry) end
    local pair=factoryPaletteFor(types)
    entry.normal={copyRgb(pair[1]),copyRgb(pair[2])}
    -- Factory rentals are normally non-shiny, but keep shinies type-readable too.
    entry.shiny={copyRgb(pair[2]),copyRgb(pair[1])}
  end
  local function restoreFactoryTypeDefs(game)
    if game and game.data and game.data.pokemon then for id,t in pairs(factoryTypeOriginals) do if game.data.pokemon[id] then game.data.pokemon[id].types=copyTypes(t) end end end
    if game and game.data and game.data.gen2Palettes and game.data.gen2Palettes.pokemon then
      for id,pal in pairs(factoryPaletteOriginals) do game.data.gen2Palettes.pokemon[id]=copyMonPalette(pal) end
    end
    factoryTypeOriginals={}
    factoryPaletteOriginals={}
  end
  local function rollFactoryTypes()
    local a=FACTORY_TYPES[math.random(#FACTORY_TYPES)]; local o={a}
    if math.random(100)<=60 then local b=a while b==a do b=FACTORY_TYPES[math.random(#FACTORY_TYPES)] end o[2]=b end
    return o
  end
  local function activeFactoryTypeMap(game)
    local save=game and game.save
    if save and save.battle_factory_crystal_mode==true and type(save.battle_factory_crystal_type_map)=="table" then return save.battle_factory_crystal_type_map end
    return pendingFactoryTypeMap
  end
  local function assignFactoryTypes(game,mon)
    if not (game and mon and mon.species and game.data and game.data.pokemon and game.data.pokemon[mon.species]) then return mon end
    local map=activeFactoryTypeMap(game); if type(map)~="table" then pendingFactoryTypeMap={} map=pendingFactoryTypeMap end
    local def=game.data.pokemon[mon.species]
    if not factoryTypeOriginals[mon.species] then factoryTypeOriginals[mon.species]=copyTypes(def.types) end
    if type(map[mon.species])~="table" then map[mon.species]=rollFactoryTypes() end
    def.types=copyTypes(map[mon.species]); mon.types=copyTypes(map[mon.species]); mon.battleFactoryTypes=copyTypes(map[mon.species])
    applyFactoryPalette(game,mon.species,map[mon.species])
    return mon
  end
  local function reapplyFactoryTypeMap(game)
    local map=game and game.save and game.save.battle_factory_crystal_type_map
    if type(map)~="table" or not (game.data and game.data.pokemon) then return end
    for id,t in pairs(map) do local def=game.data.pokemon[id]; if def then if not factoryTypeOriginals[id] then factoryTypeOriginals[id]=copyTypes(def.types) end def.types=copyTypes(t); applyFactoryPalette(game,id,t) end end
  end

  local function makeMon(game,species,level)
    local mon=Mon.new(game.data,species,level)
    if mon then Mon.stampOT(game.save,mon) end
    return mon
  end

  local function healParty(party)
    for _,mon in ipairs(party or {}) do
      if mon then
        mon.hp=mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
        mon.status=nil
        mon.statusTurns=nil
        mon.volatile=nil
        -- Factory rentals begin every match completely refreshed, including PP.
        -- This matters especially for low-PP moves that would otherwise be
        -- slowly exhausted across a seven-battle class.
        for _,slot in ipairs(mon.moves or {}) do
          if slot then
            slot.pp=slot.maxPp or slot.pp
          end
        end
      end
    end
  end



  local DRAFT_SCREEN="BattleFactoryCrystalDraft"
  local SWAP_SCREEN="BattleFactoryCrystalSwap"

  local CLASS_POOLS={
    [1]={"CATERPIE","WEEDLE","PIDGEY","RATTATA","SPEAROW","ZUBAT","ODDISH","PARAS","VENONAT","DIGLETT","MEOWTH","PSYDUCK","POLIWAG","BELLSPROUT","GEODUDE","MAGNEMITE","FARFETCHD","DODUO"},
    [2]={"PIKACHU","SANDSHREW","NIDORAN_F","NIDORAN_M","CLEFAIRY","VULPIX","JIGGLYPUFF","ZUBAT","ODDISH","PARAS","MANKEY","ABRA","MACHOP","SLOWPOKE","DROWZEE","CUBONE","HORSEA","GOLDEEN"},
    [3]={"IVYSAUR","CHARMELEON","WARTORTLE","RATICATE","FEAROW","ARBOK","RAICHU","SANDSLASH","NIDORINA","NIDORINO","GLOOM","PERSIAN","GROWLITHE","POLIWHIRL","KADABRA","MACHOKE","GRAVELER","HAUNTER"},
    [4]={"BAYLEEF","QUILAVA","CROCONAW","FURRET","NOCTOWL","LEDIAN","ARIADOS","CROBAT","LANTURN","TOGETIC","NATU","FLAAFFY","MARILL","SUDOWOODO","SKIPLOOM","AIPOM","YANMA","WOOPER"},
    [5]={"JUMPLUFF","QUAGSIRE","MURKROW","MISDREAVUS","GIRAFARIG","PINECO","DUNSPARCE","GLIGAR","QWILFISH","SNEASEL","TEDDIURSA","SLUGMA","SWINUB","CORSOLA","REMORAID","DELIBIRD","MANTINE","PHANPY"},
    [6]={"VENUSAUR","CHARIZARD","BLASTOISE","NIDOQUEEN","NIDOKING","CLEFABLE","NINETALES","VILEPLUME","GOLDUCK","PRIMEAPE","ARCANINE","POLIWRATH","ALAKAZAM","MACHAMP","GOLEM","RAPIDASH","MAGNETON","GENGAR"},
    [7]={"MEGANIUM","TYPHLOSION","FERALIGATR","AMPHAROS","BELLOSSOM","AZUMARILL","POLITOED","ESPEON","UMBREON","FORRETRESS","STEELIX","SCIZOR","HERACROSS","URSARING","PILOSWINE","OCTILLERY","SKARMORY","HOUNDOOM"},
    [8]={"EXEGGUTOR","STARMIE","SCYTHER","PINSIR","TAUROS","GYARADOS","LAPRAS","VAPOREON","JOLTEON","FLAREON","PORYGON","AERODACTYL","SNORLAX","DRAGONAIR","KINGDRA","DONPHAN","PORYGON2","TYRANITAR"},
    [9]={"VENUSAUR","CHARIZARD","BLASTOISE","ALAKAZAM","MACHAMP","GENGAR","EXEGGUTOR","STARMIE","GYARADOS","LAPRAS","SNORLAX","DRAGONITE","MEGANIUM","TYPHLOSION","FERALIGATR","ESPEON","UMBREON","AMPHAROS","SCIZOR","HERACROSS","STEELIX","KINGDRA","HOUNDOOM","TYRANITAR"},
  }

  local function factoryStreak(game)
    return math.max(0,math.floor(tonumber(game and game.save
      and game.save.battle_factory_crystal_streak) or 0))
  end

  local function factoryClass(game)
    return math.min(9,math.floor(factoryStreak(game)/7)+1)
  end

  -- Red's authored Factory sets deliberately introduced stronger attacks
  -- over time. Crystal's prototype was simply using each Lv50 species' last
  -- four natural moves, which could hand Class 1 late-game attacks immediately.
  local MOVE_POWER_CAP={60,80,95,100,110,120,130,140,255}

  -- Power alone cannot rate status/variable-power moves, so gate the most
  -- battle-warping effects explicitly. Unlisted status moves remain legal.
  local MOVE_MIN_CLASS={
    FLAMETHROWER=2, THUNDERBOLT=2, ICE_BEAM=2, PSYCHIC_M=2,
    SURF=2, RAZOR_LEAF=2, DRILL_PECK=2,
    -- Signature/high-end attacks should never leak into the rookie pool even
    -- if another mod changes their metadata or injects them into a learnset.
    AEROBLAST=3, SACRED_FIRE=3, CROSS_CHOP=3,
    SLEEP_POWDER=2, HYPNOSIS=2, THUNDER_WAVE=2,
    SELFDESTRUCT=3, SPORE=3, SWORDS_DANCE=3, CURSE=3,
    RECOVER=3, SUBSTITUTE=3, DREAM_EATER=3,
    BELLY_DRUM=4, DESTINY_BOND=4, REVERSAL=4, FLAIL=4,
    PERISH_SONG=5, HORN_DRILL=5, FISSURE=5, GUILLOTINE=5,
    EXPLOSION=5, MEAN_LOOK=5,
    HYPER_BEAM=6,
  }

  local function moveAllowedInClass(game,moveId,classNo)
    local def=game and game.data and game.data.moves
      and game.data.moves[moveId]
    if not def then return false end
    classNo=math.max(1,math.min(9,math.floor(tonumber(classNo) or 1)))
    local minClass=MOVE_MIN_CLASS[moveId] or 1
    if classNo<minClass then return false end
    local power=tonumber(def.power) or 0
    -- Zero-power moves are status or variable-power effects; their dangerous
    -- cases are handled by MOVE_MIN_CLASS above.
    if power>0 and power>(MOVE_POWER_CAP[classNo] or 255) then return false end
    return true
  end

  -- Factory sets should stay surprising, but never be nonsense.  Build them
  -- from the live (and therefore PokeSurvive-compatible) learnset with a small
  -- amount of strategy awareness: an offensive floor, STAB preference, and
  -- dependency checks for combo moves such as Dream Eater or Sleep Talk.
  local OPPONENT_SLEEP={
    HYPNOSIS=true,SLEEP_POWDER=true,SPORE=true,SING=true,LOVELY_KISS=true,
  }
  local NEEDS_OPPONENT_SLEEP={DREAM_EATER=true,NIGHTMARE=true}
  local NEEDS_REST={SLEEP_TALK=true,SNORE=true}
  local NEEDS_ENDURE={REVERSAL=true,FLAIL=true}
  local SETUP_MOVES={
    SWORDS_DANCE=true,GROWTH=true,MEDITATE=true,AGILITY=true,AMNESIA=true,
    CURSE=true,BELLY_DRUM=true,HARDEN=true,DEFENSE_CURL=true,
  }

  local function moveIsDamage(game,id)
    local md=game and game.data and game.data.moves and game.data.moves[id]
    return md and (tonumber(md.power) or 0)>0
  end

  local function moveIsSTAB(game,def,id)
    local md=game and game.data and game.data.moves and game.data.moves[id]
    if not (md and md.type and def and def.types) then return false end
    for _,t in ipairs(def.types) do if t==md.type then return true end end
    return false
  end

  local function hasId(list,id)
    for _,v in ipairs(list) do if v==id then return true end end
    return false
  end

  local function randomFrom(list)
    if #list==0 then return nil end
    return list[math.random(1,#list)]
  end

  local function curateFactoryMoves(game,mon,classNo)
    if not (game and mon and mon.species) then return mon end
    local def=game.data and game.data.pokemon and game.data.pokemon[mon.species]
    if not def then return mon end

    -- Gather every legal move this Lv50 rental can actually know.  Randomized
    -- PokeSurvive learnsets are already reflected in def.levelMoves here.
    local candidates={}
    local function addCandidate(id)
      if not id or hasId(candidates,id) or not moveAllowedInClass(game,id,classNo) then return end
      candidates[#candidates+1]=id
    end
    for _,entry in ipairs(def.levelMoves or {}) do
      if (tonumber(entry.level) or 999)<=50 then addCandidate(entry.move) end
    end
    for _,slot in ipairs(mon.moves or {}) do addCandidate(slot.id) end

    -- Feed the smart builder several class-legal attacks matching the freshly
    -- rolled Factory types, even when this species could not learn them in
    -- ordinary Crystal. Natural moves still provide the wildcard half.
    local wanted={} for _,t in ipairs(mon.types or def.types or {}) do wanted[t]=true end
    local typed={}
    for id,md in pairs(game.data and game.data.moves or {}) do if type(id)=="string" and type(md)=="table" and wanted[md.type] and (tonumber(md.power) or 0)>0 and moveAllowedInClass(game,id,classNo) then typed[#typed+1]=id end end
    for _=1,math.min(6,#typed) do local i=math.random(#typed); addCandidate(table.remove(typed,i)) end

    local selected={}
    local function add(id)
      if id and #selected<4 and not hasId(selected,id) then
        selected[#selected+1]=id
        return true
      end
      return false
    end

    -- 1) Give almost every rental a real offensive backbone. Prefer one STAB
    -- attack, then a differently typed/wild-card damaging move where possible.
    local stabDamage,damage={},{ }
    for _,id in ipairs(candidates) do
      if moveIsDamage(game,id) then
        damage[#damage+1]=id
        if moveIsSTAB(game,def,id) then stabDamage[#stabDamage+1]=id end
      end
    end
    add(randomFrom(stabDamage))
    local second={}
    for _,id in ipairs(damage) do if not hasId(selected,id) then second[#second+1]=id end end
    add(randomFrom(second))

    -- 2) Occasionally seed a complete strategy package. Never add the payoff
    -- without its enabler; this eliminates Dream Eater/Nightmare with no sleep,
    -- Sleep Talk/Snore with no Rest, and Reversal/Flail with no Endure.
    local packages={}
    local sleepers={}
    for _,id in ipairs(candidates) do if OPPONENT_SLEEP[id] then sleepers[#sleepers+1]=id end end
    if #sleepers>0 then
      for _,payoff in ipairs({'DREAM_EATER','NIGHTMARE'}) do
        if hasId(candidates,payoff) then packages[#packages+1]={randomFrom(sleepers),payoff} end
      end
    end
    if hasId(candidates,'REST') then
      for _,payoff in ipairs({'SLEEP_TALK','SNORE'}) do
        if hasId(candidates,payoff) then packages[#packages+1]={'REST',payoff} end
      end
    end
    if hasId(candidates,'ENDURE') then
      for _,payoff in ipairs({'REVERSAL','FLAIL'}) do
        if hasId(candidates,payoff) then packages[#packages+1]={'ENDURE',payoff} end
      end
    end
    if hasId(candidates,'DEFENSE_CURL') and hasId(candidates,'ROLLOUT') then
      packages[#packages+1]={'DEFENSE_CURL','ROLLOUT'}
    end
    -- Weather and control packages are only offered when both halves exist.
    -- They remain optional so the Factory keeps its wildcard personality.
    if hasId(candidates,'RAIN_DANCE') then
      if hasId(candidates,'THUNDER') then packages[#packages+1]={'RAIN_DANCE','THUNDER'} end
    end
    if hasId(candidates,'SUNNY_DAY') and hasId(candidates,'SOLARBEAM') then
      packages[#packages+1]={'SUNNY_DAY','SOLARBEAM'}
    end
    if hasId(candidates,'TOXIC') and hasId(candidates,'PROTECT') then
      packages[#packages+1]={'TOXIC','PROTECT'}
    end
    if hasId(candidates,'LEECH_SEED') and hasId(candidates,'PROTECT') then
      packages[#packages+1]={'LEECH_SEED','PROTECT'}
    end
    if hasId(candidates,'BATON_PASS') then
      for _,setup in ipairs(candidates) do
        if SETUP_MOVES[setup] then packages[#packages+1]={setup,'BATON_PASS'}; break end
      end
    end
    -- Higher classes are more likely to complete a combo, but even Class 1 can
    -- occasionally produce a clever set when its legal move pool supports one.
    if #packages>0 and #selected<=2 then
      local chance=35+math.min(45,(classNo-1)*6)
      if math.random(1,100)<=chance then
        local pkg=randomFrom(packages)
        for _,id in ipairs(pkg) do add(id) end
      end
    end

    -- 3) Fill remaining slots from legal moves, rejecting orphaned combo pieces.
    local function dependencyOK(id)
      if NEEDS_OPPONENT_SLEEP[id] then
        for _,x in ipairs(selected) do if OPPONENT_SLEEP[x] then return true end end
        return false
      end
      if NEEDS_REST[id] then return hasId(selected,'REST') end
      if NEEDS_ENDURE[id] then return hasId(selected,'ENDURE') end
      if id=='BATON_PASS' then
        for _,x in ipairs(selected) do if SETUP_MOVES[x] then return true end end
        return false
      end
      return true
    end
    local fill={}
    for _,id in ipairs(candidates) do
      if not hasId(selected,id) and dependencyOK(id) then fill[#fill+1]=id end
    end
    while #selected<4 and #fill>0 do
      local i=math.random(1,#fill)
      add(table.remove(fill,i))
    end

    -- If the learnset was extremely shallow, prefer another legal attack before
    -- falling back to the harmless starter moves used by earlier builds.
    if #selected<2 then
      for _,id in ipairs(damage) do add(id) end
    end
    if #selected==0 then
      for _,id in ipairs({'TACKLE','POUND','SCRATCH','QUICK_ATTACK'}) do
        if game.data.moves[id] and moveAllowedInClass(game,id,classNo) then add(id); break end
      end
    end

    mon.moves={}
    for _,id in ipairs(selected) do
      local md=game.data.moves[id]
      local pp=md and md.pp or 0
      mon.moves[#mon.moves+1]={id=id,pp=pp,maxPp=pp}
    end
    return mon
  end

  local function factoryBP(game)
    return math.max(0,math.floor(tonumber(game and game.save
      and game.save.battle_factory_crystal_bp) or 0))
  end

  local function firstClearRewards(game)
    local save=game and game.save
    if not save then return {} end
    if type(save.battle_factory_crystal_first_clear_rewards)~="table" then
      save.battle_factory_crystal_first_clear_rewards={}
    end
    return save.battle_factory_crystal_first_clear_rewards
  end

  local function addFactoryBP(game,amount)
    local save=game and game.save
    if not save then return 0 end
    amount=math.max(0,math.floor(tonumber(amount) or 0))
    save.battle_factory_crystal_bp=factoryBP(game)+amount
    return save.battle_factory_crystal_bp
  end

  local function highestClassCleared(game)
    return math.max(0,math.floor(tonumber(game and game.save
      and game.save.battle_factory_crystal_highest_class_cleared) or 0))
  end

  -- Highest class cleared is permanent progression for shop unlocks. The
  -- current Factory rank is separate run-state progression: a class clear
  -- advances it, while any loss/retirement resets it to CLASS 1.
  local function currentFactoryRank(game)
    local save=game and game.save
    return math.max(1,math.min(9,math.floor(tonumber(save and
      save.battle_factory_crystal_current_class) or 1)))
  end

  local function speciesBST(def)
    local s=def and def.baseStats or {}
    return (tonumber(s.hp) or 0)+(tonumber(s.attack) or 0)
      +(tonumber(s.defense) or 0)+(tonumber(s.speed) or 0)
      +(tonumber(s.specialAttack) or 0)+(tonumber(s.specialDefense) or 0)
  end

  -- Battle Point shop. Stock expands as Factory classes are cleared.
  -- Economy target: a normal seven-win class pays 12 BP (17 on its first
  -- clear), so common utility rewards are roughly half a class while premium
  -- held items/TMs and strong daily Pokémon ask for one to two class clears.
  -- The special PokeSurvive Holon/colour reroll items will be added later.
  local BP_SHOP={
    held={
      {id="QUICK_CLAW",   label="QUICK CLAW",   cost=8,  unlock=1},
      {id="KINGS_ROCK",   label="KING'S ROCK",  cost=10, unlock=2},
      {id="BRIGHTPOWDER", label="BRIGHTPOWDER", cost=12, unlock=2},
      {id="FOCUS_BAND",   label="FOCUS BAND",   cost=14, unlock=3},
      {id="SCOPE_LENS",   label="SCOPE LENS",   cost=14, unlock=3},
      {id="LEFTOVERS",    label="LEFTOVERS",    cost=24, unlock=5},
    },
    evolution={
      {id="MOON_STONE",    label="MOON STONE",    cost=6, unlock=1},
      {id="FIRE_STONE",    label="FIRE STONE",    cost=7, unlock=1},
      {id="THUNDERSTONE",  label="THUNDERSTONE",  cost=7, unlock=1},
      {id="WATER_STONE",   label="WATER STONE",   cost=7, unlock=1},
      {id="LEAF_STONE",    label="LEAF STONE",    cost=7, unlock=1},
      {id="SUN_STONE",     label="SUN STONE",     cost=10, unlock=2},
      {id="METAL_COAT",    label="METAL COAT",    cost=12, unlock=3},
      {id="DRAGON_SCALE",  label="DRAGON SCALE",  cost=12, unlock=3},
      {id="UP_GRADE",      label="UP-GRADE",      cost=12, unlock=3},
      {id="KINGS_ROCK",    label="KING'S ROCK",   cost=10, unlock=3},
    },
    vitamins={
      {id="HP_UP",   label="HP UP",   cost=6, unlock=2},
      {id="PROTEIN", label="PROTEIN", cost=6, unlock=2},
      {id="IRON",    label="IRON",    cost=6, unlock=2},
      {id="CARBOS",  label="CARBOS",  cost=6, unlock=2},
      {id="CALCIUM", label="CALCIUM", cost=6, unlock=2},
    },
    -- Only TMs that Crystal does not offer as a repeatable purchase/prize.
    -- The point of this section is to make otherwise finite-use TMs renewable
    -- through Factory play, not to duplicate the department/game-corner shops.
    tms={
      {id="TM_DYNAMICPUNCH",  label="TM DYNAMICPUNCH", cost=10,  unlock=2},
      {id="TM_CURSE",         label="TM CURSE",        cost=10,  unlock=2},
      {id="TM_ROLLOUT",       label="TM ROLLOUT",      cost=8,  unlock=2},
      {id="TM_ROAR",          label="TM ROAR",         cost=8,  unlock=2},
      {id="TM_TOXIC",         label="TM TOXIC",        cost=16, unlock=4},
      {id="TM_ZAP_CANNON",    label="TM ZAP CANNON",   cost=14,  unlock=4},
      {id="TM_SWEET_SCENT",   label="TM SWEET SCENT",  cost=6,  unlock=2},
      {id="TM_ICY_WIND",      label="TM ICY WIND",     cost=10,  unlock=2},
      {id="TM_GIGA_DRAIN",    label="TM GIGA DRAIN",   cost=12,  unlock=3},
      {id="TM_ENDURE",        label="TM ENDURE",       cost=10,  unlock=3},
      {id="TM_SOLARBEAM",     label="TM SOLARBEAM",    cost=16, unlock=4},
      {id="TM_IRON_TAIL",     label="TM IRON TAIL",    cost=14,  unlock=3},
      {id="TM_DRAGONBREATH",  label="TM DRAGONBREATH", cost=14,  unlock=4},
      {id="TM_EARTHQUAKE",    label="TM EARTHQUAKE",   cost=24, unlock=6},
      {id="TM_DIG",           label="TM DIG",          cost=12,  unlock=3},
      {id="TM_SHADOW_BALL",   label="TM SHADOW BALL",  cost=16, unlock=4},
      {id="TM_MUD_SLAP",      label="TM MUD-SLAP",     cost=8,  unlock=2},
      {id="TM_SWAGGER",       label="TM SWAGGER",      cost=8,  unlock=3},
      {id="TM_SLEEP_TALK",    label="TM SLEEP TALK",   cost=10,  unlock=3},
      {id="TM_SLUDGE_BOMB",   label="TM SLUDGE BOMB",  cost=16, unlock=4},
      {id="TM_SWIFT",         label="TM SWIFT",        cost=10,  unlock=3},
      {id="TM_DEFENSE_CURL",  label="TM DEFENSE CURL", cost=6,  unlock=2},
      {id="TM_DREAM_EATER",   label="TM DREAM EATER",  cost=14,  unlock=4},
      {id="TM_DETECT",        label="TM DETECT",       cost=12,  unlock=4},
      {id="TM_REST",          label="TM REST",         cost=12,  unlock=3},
      {id="TM_ATTRACT",       label="TM ATTRACT",      cost=8,  unlock=2},
      {id="TM_THIEF",         label="TM THIEF",        cost=10,  unlock=3},
      {id="TM_FURY_CUTTER",   label="TM FURY CUTTER",  cost=8,  unlock=2},
      {id="TM_NIGHTMARE",     label="TM NIGHTMARE",    cost=12,  unlock=4},
    },
  }

  local function bpShopRows(game,key)
    local out={}
    for _,entry in ipairs(BP_SHOP[key] or {}) do
      if game and game.data and game.data.items
        and game.data.items[entry.id] then
        out[#out+1]=entry
      end
    end
    return out
  end

  local function bpConfirm(vm,text)
    vm:showRaw(text)
    local h=S.hooks(vm)
    local choice=Specials.block(vm,function(done)
      if not h.scriptMenu then return done(2) end
      h.scriptMenu({
        items={Strings.source("YES"),Strings.source("NO")},
        left=0,top=0,right=8,bottom=5,
        dataFlags=FLAGS,cursor=1,
      },done)
    end)
    return math.floor(tonumber(choice) or 2)==1
  end

  local function runBPItemList(game,vm,key)
    local h=S.hooks(vm)
    while true do
      local stock=bpShopRows(game,key)
      if #stock==0 then
        vm:showRaw("No stock unlocked\nin this section.")
        return
      end
      local rows={}
      local cleared=highestClassCleared(game)
      for _,entry in ipairs(stock) do
        local right=(cleared>=entry.unlock)
          and (tostring(entry.cost).."BP")
          or ("C"..tostring(entry.unlock))
        rows[#rows+1]=Strings.source(("%s\t%s"):format(entry.label,right))
      end
      rows[#rows+1]=Strings.source("BACK")
      local choice=Specials.block(vm,function(done)
        if not h.scriptMenu then return done(#rows) end
        h.scriptMenu({
          items=rows,left=0,top=0,right=18,bottom=17,
          dataFlags=FLAGS,cursor=1,
          factoryScrollable=true,factoryMaxVisible=7,
        },done)
      end)
      choice=math.floor(tonumber(choice) or #rows)
      if choice<1 or choice>#stock then return end

      local entry=stock[choice]
      local balance=factoryBP(game)
      local cleared=highestClassCleared(game)
      if cleared<entry.unlock then
        vm:showRaw(("Clear CLASS %d\nto unlock this."):format(entry.unlock))
      elseif balance<entry.cost then
        vm:showRaw(("Need %d BP.\nYou have %d BP."):format(entry.cost,balance))
      elseif bpConfirm(vm,("Buy %s?\nCost: %d BP."):format(entry.label,entry.cost)) then
        if Bag.add(game.save,entry.id,1,game.data) then
          game.save.battle_factory_crystal_bp=balance-entry.cost
          vm:showRaw(("Received %s.\nBP left: %d."):format(
            entry.label,factoryBP(game)))
        else
          vm:showRaw("Your PACK has\nno room.")
        end
      end
    end
  end

  local DAILY_POKEMON_COUNT=5
  local DAILY_POKEMON_LEVEL=15

  local function hashDailyText(text,seed)
    local h=math.floor(tonumber(seed) or 2166136261)%2147483647
    for i=1,#text do
      h=(h*131+text:byte(i))%2147483647
    end
    return h
  end

  local function dailyPokemonKey(game)
    -- Crystal's clock advances with the host RTC, so the local calendar day is
    -- the stable day boundary the in-game clock rolls over on as well.
    return os.date("%Y-%j")
  end

  local function ensurePokemonShopSeed(game)
    local save=game and game.save
    if not save then return 1 end
    local seed=tonumber(save.battle_factory_crystal_pokemon_seed)
    if not seed then
      -- Deliberately independent of PokeSurvive's randomizer seed.  Persist it
      -- once, then derive each day's five offers from this private shop seed.
      local playerId=tonumber(save.player and save.player.id) or 0
      seed=(math.floor(os.time())+playerId*7919+104729)%2147483647
      if seed<=0 then seed=1 end
      save.battle_factory_crystal_pokemon_seed=seed
    end
    return seed
  end

  local function nextDailyRand(state,limit)
    state.value=(state.value*48271)%2147483647
    if not limit or limit<=1 then return 1 end
    return (state.value%limit)+1
  end

  local function pokemonShopEligible(game)
    local defs=game and game.data and game.data.pokemon or {}
    local rows={}
    for id,def in pairs(defs) do
      if type(id)=="string" and type(def)=="table" and def.baseStats then
        rows[#rows+1]={id=id,dex=tonumber(def.dex) or 9999,bst=speciesBST(def)}
      end
    end
    table.sort(rows,function(a,b)
      if a.dex~=b.dex then return a.dex<b.dex end
      return a.id<b.id
    end)
    return rows
  end

  local function pokemonShopCost(bst)
    bst=math.floor(tonumber(bst) or 300)
    if bst<350 then return 12 end
    if bst<450 then return 15 end
    if bst<525 then return 18 end
    if bst<580 then return 22 end
    return 28
  end

  local function dailyPokemonStock(game)
    local save=game and game.save
    if not save then return {},"" end
    local key=dailyPokemonKey(game)
    local base=ensurePokemonShopSeed(game)
    local pool=pokemonShopEligible(game)
    local state={value=hashDailyText(key,base)}
    if state.value<=0 then state.value=1 end

    local stock={}
    local candidates={}
    for i,row in ipairs(pool) do candidates[i]=row end
    for slot=1,math.min(DAILY_POKEMON_COUNT,#candidates) do
      local pick=nextDailyRand(state,#candidates)
      local row=table.remove(candidates,pick)
      stock[#stock+1]={id=row.id,bst=row.bst,cost=pokemonShopCost(row.bst),slot=slot}
    end

    if save.battle_factory_crystal_pokemon_day~=key then
      save.battle_factory_crystal_pokemon_day=key
      save.battle_factory_crystal_pokemon_bought={}
    elseif type(save.battle_factory_crystal_pokemon_bought)~="table" then
      save.battle_factory_crystal_pokemon_bought={}
    end
    return stock,key
  end

  local function activeBoxHasRoom(save)
    local box=Boxes.active(save)
    return type(box)=="table" and #box<(Boxes.CAPACITY or 20),box
  end

  local function runBPPokemonShop(game,vm)
    local h=S.hooks(vm)
    while true do
      local stock=dailyPokemonStock(game)
      local bought=game.save.battle_factory_crystal_pokemon_bought or {}
      local rows={}
      for i,entry in ipairs(stock) do
        local def=game.data and game.data.pokemon and game.data.pokemon[entry.id]
        local name=tostring((def and def.name) or entry.id):upper()
        local suffix=bought[i] and "SOLD" or (tostring(entry.cost).."BP")
        rows[#rows+1]=Strings.source(("%-12s\t%s"):format(name,suffix))
      end
      rows[#rows+1]=Strings.source("BACK")

      local choice=Specials.block(vm,function(done)
        if not h.scriptMenu then return done(#rows) end
        h.scriptMenu({
          items=rows,left=0,top=0,right=18,bottom=15,
          dataFlags=FLAGS,cursor=1,
          factoryScrollable=true,factoryMaxVisible=6,
        },done)
      end)
      choice=math.floor(tonumber(choice) or #rows)
      if choice<1 or choice>#stock then return end

      local entry=stock[choice]
      local def=game.data and game.data.pokemon and game.data.pokemon[entry.id]
      local name=tostring((def and def.name) or entry.id):upper()
      if bought[choice] then
        vm:showRaw("That POKéMON was\nalready claimed today.")
      else
        local room,box=activeBoxHasRoom(game.save)
        local balance=factoryBP(game)
        if not room then
          vm:showRaw("Your current BOX\nis full.")
        elseif balance<entry.cost then
          vm:showRaw(("Need %d BP.\nYou have %d BP."):format(entry.cost,balance))
        elseif bpConfirm(vm,("Buy %s?\nLv15 - %d BP."):format(name,entry.cost)) then
          local mon=makeMon(game,entry.id,DAILY_POKEMON_LEVEL)
          if not mon then
            vm:showRaw("That POKéMON could\nnot be prepared.")
          else
            table.insert(box,mon)
            game.save.battle_factory_crystal_bp=balance-entry.cost
            bought[choice]=true
            game.save.battle_factory_crystal_pokemon_bought=bought
            vm:showRaw(("%s was sent\nto BOX %d."):format(
              name,math.floor(tonumber(game.save.currentBox) or 1)))
            vm:showRaw(("BP left: %d."):format(factoryBP(game)))
          end
        end
      end
    end
  end

  local function runBPShop(game,vm)
    if not (game and game.save) then return end
    factoryDialogueMode=true
    local h=S.hooks(vm)
    vm:showRaw(("Welcome to the\nBP SHOP!"))
    vm:showRaw(("You have %d BP."):format(factoryBP(game)))

    while true do
      local rows={
        Strings.source("HELD ITEMS"),
        Strings.source("EVOLUTION"),
        Strings.source("VITAMINS"),
        Strings.source("TMs"),
        Strings.source("POKéMON"),
        Strings.source("CHECK BP"),
        Strings.source("CANCEL"),
      }
      local choice=Specials.block(vm,function(done)
        if not h.scriptMenu then return done(7) end
        h.scriptMenu({
          items=rows,left=0,top=0,right=14,bottom=13,
          dataFlags=FLAGS,cursor=1,
          factoryScrollable=true,factoryMaxVisible=5,
        },done)
      end)
      choice=math.floor(tonumber(choice) or 7)

      if choice==1 then
        runBPItemList(game,vm,"held")
      elseif choice==2 then
        runBPItemList(game,vm,"evolution")
      elseif choice==3 then
        runBPItemList(game,vm,"vitamins")
      elseif choice==4 then
        runBPItemList(game,vm,"tms")
      elseif choice==5 then
        runBPPokemonShop(game,vm)
      elseif choice==6 then
        vm:showRaw(("You have %d BP."):format(factoryBP(game)))
      else
        vm:showRaw("Come back anytime!")
        factoryDialogueMode=false
        return
      end
    end
  end

  local function evolutionStages(game)
    local defs=game and game.data and game.data.pokemon or {}
    local hasPrevo,hasEvo={},{}
    for id,def in pairs(defs) do
      for _,evo in ipairs(def.evolutions or {}) do
        local into=evo.into or evo.species or evo.target
        if into and defs[into] then
          hasEvo[id]=true
          hasPrevo[into]=true
        end
      end
    end
    local stage={}
    for id,_ in pairs(defs) do
      if not hasPrevo[id] then
        stage[id]=0 -- first-stage OR single-stage
      elseif hasEvo[id] then
        stage[id]=1 -- middle evolution
      else
        stage[id]=2 -- final evolution
      end
    end
    return stage,hasEvo,hasPrevo
  end

  local function validClassPool(game,classNo)
    local defs=game and game.data and game.data.pokemon or {}
    local stages,hasEvo=evolutionStages(game)
    local ranked={}
    for id,def in pairs(defs) do
      if type(id)=="string" and type(def)=="table" and def.baseStats then
        local bst=speciesBST(def)
        local stage=stages[id] or 0
        -- Evolution maturity matters in addition to raw BST. This prevents
        -- compact but fully evolved lines (NIDOKING etc.) from leaking into
        -- beginner classes simply because their numerical BST sorts nearby.
        local maturityPenalty=(stage==1 and 115) or (stage==2 and 210) or 0
        -- Strong single-stage species are still governed by BST.
        local score=bst+maturityPenalty
        ranked[#ranked+1]={id=id,bst=bst,stage=stage,score=score,
          dex=tonumber(def.dex) or 999}
      end
    end
    table.sort(ranked,function(a,c)
      if a.score~=c.score then return a.score<c.score end
      if a.bst~=c.bst then return a.bst<c.bst end
      return a.dex<c.dex
    end)
    if #ranked==0 then return {} end

    classNo=math.max(1,math.min(9,math.floor(tonumber(classNo) or 1)))
    -- Large class ecosystems: roughly 72 eligible species per tier. Adjacent
    -- classes intentionally overlap so progression feels gradual rather than
    -- replacing the entire roster every seven wins.
    local width=math.min(72,#ranked)
    local maxStart=math.max(1,#ranked-width+1)
    local startIndex=1+math.floor((classNo-1)*(maxStart-1)/8)

    local out={}
    for i=startIndex,math.min(#ranked,startIndex+width-1) do
      local row=ranked[i]
      -- Class 1 is deliberately a rookie tier: no middle/final evolutions.
      -- It consists of first-stage Pokémon plus lower-power single-stage mons.
      -- Evolution-stage guardrails make the nine classes visibly mature.
      -- The sliding strength window still supplies most of the progression;
      -- these rules only stop an unusually low-BST final evolution from
      -- sneaking several classes earlier than it feels appropriate.
      local allowed=false
      if classNo==1 then
        local isSingle=(not hasEvo[row.id])
        allowed=(row.stage==0) and ((not isSingle) or row.bst<=420)
      elseif classNo==2 then
        allowed=row.stage<=1
      elseif classNo==3 then
        allowed=(row.stage<=1) or (row.stage==2 and row.bst<=430)
      elseif classNo==4 then
        allowed=(row.stage<=1) or (row.stage==2 and row.bst<=470)
      elseif classNo==5 then
        allowed=(row.stage<=1) or (row.stage==2 and row.bst<=500)
      else
        allowed=true
      end
      if allowed then out[#out+1]=row.id end
    end

    -- If the strict Class-1 filter made the window too small, continue down
    -- the ranked list collecting only legitimate rookie-stage choices.
    if classNo==1 and #out<54 then
      local seen={}
      for _,id in ipairs(out) do seen[id]=true end
      for i=startIndex+width,#ranked do
        local row=ranked[i]
        if row.stage==0 and not seen[row.id] then
          -- Base-stage evolutionary Pokémon are always valid rookie material.
          -- Single-stage species are only admitted here while their raw BST is
          -- still in a rookie-friendly band.
          local isSingle=(not hasEvo[row.id])
          if (not isSingle) or row.bst<=420 then
            out[#out+1]=row.id; seen[row.id]=true
            if #out>=72 then break end
          end
        end
      end
    end
    return out
  end

  -- Factory Heads mirror Red: battle 7 of Classes 3-9.
  -- Crystal-native trainer classes are preferred for presentation. Where Red's
  -- exact character has no Crystal class, a presentation fallback is used but
  -- the Factory Head's displayed name remains the intended character.
  local FACTORY_HEADS={
    [3]={name="BROCK", classIds={"BROCK"}, team={"ONIX","GRAVELER","OMASTAR"}},
    [4]={name="KOGA", classIds={"KOGA"}, team={"ARIADOS","MUK","CROBAT"}},
    [5]={name="BLAINE", classIds={"BLAINE"}, team={"NINETALES","RAPIDASH","MAGCARGO"}},
    [6]={name="GIOVANNI", classIds={"BLUE","BROCK"}, team={"NIDOQUEEN","NIDOKING","RHYDON"}},
    [7]={name="LORELEI", classIds={"WILL","KAREN"}, team={"DEWGONG","CLOYSTER","LAPRAS"}},
    [8]={name="LANCE", classIds={"CHAMPION","CLAIR"}, team={"GYARADOS","AERODACTYL","DRAGONITE"}},
    [9]={name="PROF.OAK", classIds={"POKEMON_PROF","RED","CHAMPION"}, team={"TAUROS","EXEGGUTOR","BLASTOISE"}},
  }

  local function battleNumber(game)
    return (factoryStreak(game)%7)+1
  end

  local function currentFactoryHead(game)
    if battleNumber(game)~=7 then return nil end
    return FACTORY_HEADS[factoryClass(game)]
  end

  local function resolveHeadClass(game,head,fallback)
    local classes=game and game.data and game.data.trainers
      and game.data.trainers.classes or {}
    for _,id in ipairs(head and head.classIds or {}) do
      if classes[id] then return id end
    end
    return fallback
  end

  local function evolutionFamilyKeys(game)
    local defs=game and game.data and game.data.pokemon or {}
    local parent={}
    local function find(x)
      parent[x]=parent[x] or x
      if parent[x]~=x then parent[x]=find(parent[x]) end
      return parent[x]
    end
    local function union(a,c)
      if not (defs[a] and defs[c]) then return end
      a,c=find(a),find(c)
      if a~=c then parent[c]=a end
    end
    for id,_ in pairs(defs) do parent[id]=id end
    for id,def in pairs(defs) do
      for _,evo in ipairs(def.evolutions or {}) do
        local target=evo.species or evo.target or evo.into
        if target then union(id,target) end
      end
    end
    local keys={}
    for id,_ in pairs(defs) do keys[id]=find(id) end
    return keys
  end

  local function chooseUniqueSpecies(game,classNo,count,blocked,familyUnique)
    local pool=validClassPool(game,classNo)
    local candidates={}
    blocked=blocked or {}
    for _,id in ipairs(pool) do
      if not blocked[id] then candidates[#candidates+1]=id end
    end
    local families=familyUnique and evolutionFamilyKeys(game) or nil
    local usedFamilies={}
    local out={}
    while #out<count and #candidates>0 do
      local i=math.random(1,#candidates)
      local id=table.remove(candidates,i)
      local family=families and families[id]
      if not family or not usedFamilies[family] then
        out[#out+1]=id
        if family then usedFamilies[family]=true end
      end
    end
    return out
  end

  local function rentalPool(game)
    local classNo=factoryClass(game)
    local pool={}
    for _,id in ipairs(chooseUniqueSpecies(game,classNo,6)) do
      local mon=makeMon(game,id,50)
      if mon then
        assignFactoryTypes(game,mon)
        curateFactoryMoves(game,mon,classNo)
        mon.battleFactoryRental=true
        mon.battleFactoryClass=classNo
        pool[#pool+1]=mon
      end
    end
    return pool
  end

  -- Crystal counterpart to Red's rental draft screen:
  -- roster stays visible, each mon has STATS / CHOOSE(or RETURN) / BACK,
  -- and selecting three does NOT immediately launch the run.
  mod.content.screens:register(DRAFT_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local Font=mod.ui.Font
      local Theme=require("src.ui.Theme")
      local Menu=require("src.ui.Menu")
      local SummaryMenu=require("src.ui.gen2.SummaryMenu")

      local pool=opts.pool or {}
      local selected={}
      local order={}
      local state={
        game=game,isOpaque=true,cursor=1,actionMenu=nil,readyMenu=nil,
      }

      local function selectedCount() return #order end

      local function isSelected(i)
        return selected[i]==true
      end

      local function removeSelected(i)
        selected[i]=nil
        for pos,v in ipairs(order) do
          if v==i then table.remove(order,pos) break end
        end
      end

      local function refreshPool()
        local fresh=rentalPool(game)
        if type(fresh)~="table" or #fresh~=6 then return false end
        pool=fresh
        selected={}
        order={}
        state.cursor=1
        state.actionMenu=nil
        state.readyMenu=nil
        return true
      end

      local function closeAction() state.actionMenu=nil end

      local function openStats(i)
        local mon=pool[i]
        if not mon then return end
        -- Moves are curated exactly once when this rental pool is generated.
        -- Re-curating here made merely viewing STATS consume RNG and rewrite
        -- the rental's moves every time the summary screen was opened.
        game.stack:push(SummaryMenu.new(game,{
          mon=mon,
          save=game.save,
          onClose=function()
            if game.stack and game.stack:top() then
              game.stack:pop()
            end
          end,
        }))
      end

      local function openAction(i)
        local items={
          {
            label="STATS",
            keepOpen=true,
            onSelect=function() openStats(i) end,
          },
        }

        if isSelected(i) then
          items[#items+1]={
            label="RETURN",
            keepOpen=true,
            onSelect=function()
              removeSelected(i)
              closeAction()
            end,
          }
        elseif selectedCount()<3 then
          items[#items+1]={
            label="CHOOSE",
            keepOpen=true,
            onSelect=function()
              selected[i]=true
              order[#order+1]=i
              closeAction()
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
          label="BACK",keepOpen=true,
          onSelect=function() closeAction() end,
        }

        state.actionMenu=Menu.new(game,items,{
          tx=11,ty=9,tw=9,th=8,cancelable=false,rowStep=2,
        })
      end

      local function finishReady()
        local out={}
        for _,i in ipairs(order) do out[#out+1]=pool[i] end
        game.stack:pop()
        if opts.onDone then opts.onDone(out) end
      end

      local function openReadyConfirm()
        local items={
          {
            label="READY UP",
            keepOpen=true,
            onSelect=function()
              state.readyMenu=nil
              finishReady()
            end,
          },
          {
            label="KEEP CHOOSING",
            keepOpen=true,
            onSelect=function() state.readyMenu=nil end,
          },
        }
        state.readyMenu=Menu.new(game,items,{
          tx=3,ty=10,tw=14,th=6,cancelable=false,rowStep=2,
        })
      end

      local function rowCount()
        -- Six rentals, REFRESH, optional READY UP, BACK.
        return #pool + 2 + (selectedCount()==3 and 1 or 0)
      end

      function state:update(dt)
        local input=game.input
        if not input then return end

        if self.readyMenu then
          if input:wasPressed("b") then
            self.readyMenu=nil
            return
          end
          self.readyMenu:update(dt)
          return
        end

        if self.actionMenu then
          if input:wasPressed("b") then
            closeAction()
            return
          end
          self.actionMenu:update(dt)
          return
        end

        if input:wasPressed("b") then
          game.stack:pop()
          if opts.onDone then opts.onDone(nil) end
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
          local n=#pool
          if self.cursor<=n then
            openAction(self.cursor)
          else
            local off=self.cursor-n
            if off==1 then
              -- Red Factory parity: unlimited free rerolls of the current
              -- class draft. Any partial selections are intentionally cleared.
              refreshPool()
            elseif selectedCount()==3 and off==2 then
              openReadyConfirm()
            else
              -- BACK is offset 2 without READY, offset 3 with READY.
              game.stack:pop()
              if opts.onDone then opts.onDone(nil) end
            end
          end
        end
      end

      function state:draw()
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",0,0,160,144)
        love.graphics.setColor(0,0,0,1)

        Font.draw("CLASS "..tostring(factoryClass(game)).."  RENT 3",8,6)

        local y=24
        for i,mon in ipairs(pool) do
          if self.cursor==i and not self.actionMenu and not self.readyMenu then
            Font.drawCode(Theme.cursor,8,y)
          end
          local name=tostring(mon.name or mon.species or "POKéMON")
          local suffix=isSelected(i) and "  RENT" or ""
          Font.draw(name..suffix,16,y)
          y=y+14
        end

        local row=#pool+1
        if self.cursor==row and not self.actionMenu and not self.readyMenu then
          Font.drawCode(Theme.cursor,8,y)
        end
        Font.draw("REFRESH",16,y)
        y=y+14

        if selectedCount()==3 then
          row=row+1
          if self.cursor==row and not self.actionMenu and not self.readyMenu then
            Font.drawCode(Theme.cursor,8,y)
          end
          Font.draw("READY UP",16,y)
          y=y+14
        end

        row=row+1
        if self.cursor==row and not self.actionMenu and not self.readyMenu then
          Font.drawCode(Theme.cursor,8,y)
        end
        Font.draw("BACK",16,y)

        if self.actionMenu then self.actionMenu:draw() end
        if self.readyMenu then self.readyMenu:draw() end
      end

      return state
    end,
  })

  local function selectThreeRentals(game,vm)
    restoreFactoryTypeDefs(game); pendingFactoryTypeMap={}
    local pool=rentalPool(game)
    if #pool~=6 then restoreFactoryTypeDefs(game); pendingFactoryTypeMap=nil; return nil end
    local h=S.hooks(vm)
    return Specials.block(vm,function(done)
      local function finish(result) if not result then restoreFactoryTypeDefs(game); pendingFactoryTypeMap=nil end done(result) end
      if not h.pushScreen then return finish(nil) end
      local ok=h.pushScreen(DRAFT_SCREEN,{pool=pool,onDone=finish})
      if not ok then finish(nil) end
    end)
  end

  -- Red-style post-win swap flow. The defeated trainer's actual three
  -- Pokémon are frozen before battle and passed into this screen.
  mod.content.screens:register(SWAP_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local Font=mod.ui.Font
      local Theme=require("src.ui.Theme")
      local Menu=require("src.ui.Menu")
      local SummaryMenu=require("src.ui.gen2.SummaryMenu")

      local enemy=opts.enemy or {}
      local player=game.save and game.save.party or {}
      local state={
        game=game,isOpaque=true,cursor=1,actionMenu=nil,
        phase="enemy",pendingTake=nil,
      }

      local function closeAction() state.actionMenu=nil end

      local function openStats(mon)
        if not mon then return end
        game.stack:push(SummaryMenu.new(game,{
          mon=mon,
          save=game.save,
          onClose=function()
            if game.stack and game.stack:top() then game.stack:pop() end
          end,
        }))
      end

      local function complete(result)
        game.stack:pop()
        if opts.onDone then opts.onDone(result) end
      end

      local function openEnemyAction(i)
        local mon=enemy[i]
        local items={
          {
            label="STATS",
            keepOpen=true,
            onSelect=function() openStats(mon) end,
          },
          {
            label="TAKE",
            keepOpen=true,
            onSelect=function()
              state.pendingTake=i
              state.phase="player"
              state.cursor=1
              closeAction()
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
          cancelable=false,rowStep=2,
        })
      end

      local function openPlayerAction(i)
        local mon=player[i]
        local items={
          {
            label="STATS",
            keepOpen=true,
            onSelect=function() openStats(mon) end,
          },
          {
            label="RETURN",
            keepOpen=true,
            onSelect=function()
              local take=state.pendingTake and enemy[state.pendingTake]
              if not take then
                state.phase="enemy"
                state.pendingTake=nil
                state.cursor=1
                closeAction()
                return
              end

              -- The mon object itself is the Factory configuration that was
              -- just fought. Heal it before it becomes the player's rental.
              local replacement=deepCopy(take)
              replacement.battleFactoryRental=true
              replacement.hp=replacement.maxHp
                or (replacement.stats and replacement.stats.hp)
                or replacement.hp
              replacement.status=nil
              replacement.statusTurns=nil
              replacement.volatile=nil

              player[i]=replacement
              game.save.party=player
              closeAction()
              complete({
                swapped=true,
                taken=replacement.species,
                returned=i,
              })
            end,
          },
          {
            label="BACK",
            keepOpen=true,
            onSelect=function()
              state.phase="enemy"
              state.pendingTake=nil
              state.cursor=1
              closeAction()
            end,
          },
        }
        state.actionMenu=Menu.new(game,items,{
          tx=11,ty=9,tw=9,th=8,
          cancelable=false,rowStep=2,
        })
      end

      function state:update(dt)
        local input=game.input
        if not input then return end

        if self.actionMenu then
          if input:wasPressed("b") then
            closeAction()
            return
          end
          self.actionMenu:update(dt)
          return
        end

        if self.phase=="enemy" then
          local count=#enemy+1
          if input:wasPressed("up") then
            self.cursor=self.cursor-1
            if self.cursor<1 then self.cursor=count end
          elseif input:wasPressed("down") then
            self.cursor=self.cursor+1
            if self.cursor>count then self.cursor=1 end
          elseif input:wasPressed("b") then
            complete({swapped=false})
          elseif input:wasPressed("a") then
            if self.cursor<=#enemy then
              openEnemyAction(self.cursor)
            else
              complete({swapped=false})
            end
          end
        else
          local count=#player+1
          if input:wasPressed("up") then
            self.cursor=self.cursor-1
            if self.cursor<1 then self.cursor=count end
          elseif input:wasPressed("down") then
            self.cursor=self.cursor+1
            if self.cursor>count then self.cursor=1 end
          elseif input:wasPressed("b") then
            self.phase="enemy"
            self.pendingTake=nil
            self.cursor=1
          elseif input:wasPressed("a") then
            if self.cursor<=#player then
              openPlayerAction(self.cursor)
            else
              self.phase="enemy"
              self.pendingTake=nil
              self.cursor=1
            end
          end
        end
      end

      function state:draw()
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",0,0,160,144)
        love.graphics.setColor(0,0,0,1)

        if self.phase=="enemy" then
          Font.draw("DEFEATED TEAM",8,6)
          local y=28
          for i,mon in ipairs(enemy) do
            if self.cursor==i and not self.actionMenu then
              Font.drawCode(Theme.cursor,8,y)
            end
            Font.draw(tostring(mon.name or mon.species or "POKéMON"),16,y)
            y=y+18
          end
          local noSwap=#enemy+1
          if self.cursor==noSwap and not self.actionMenu then
            Font.drawCode(Theme.cursor,8,y+6)
          end
          Font.draw("NO SWAP",16,y+6)
        else
          Font.draw("RETURN WHICH?",8,6)
          local y=28
          for i,mon in ipairs(player) do
            if self.cursor==i and not self.actionMenu then
              Font.drawCode(Theme.cursor,8,y)
            end
            Font.draw(tostring(mon.name or mon.species or "POKéMON"),16,y)
            y=y+18
          end
          local back=#player+1
          if self.cursor==back and not self.actionMenu then
            Font.drawCode(Theme.cursor,8,y+6)
          end
          Font.draw("BACK TO ENEMY",16,y+6)
        end

        if self.actionMenu then self.actionMenu:draw() end
      end

      return state
    end,
  })

  local function runSwapScreen(game,vm,enemy)
    local h=S.hooks(vm)
    return Specials.block(vm,function(done)
      if not h.pushScreen then return done({swapped=false}) end
      local ok=h.pushScreen(SWAP_SCREEN,{
        enemy=enemy,
        onDone=done,
      })
      if not ok then done({swapped=false}) end
    end)
  end

  local function promptReadyOrRetire(game,vm)
    local h=S.hooks(vm)
    local nextBattle=(factoryStreak(game)%7)+1
    vm:showRaw(("Ready for\nBATTLE %d?"):format(nextBattle))

    local choice=Specials.block(vm,function(done)
      if not h.scriptMenu then return done(1) end
      h.scriptMenu({
        items={
          Strings.source("YES"),
          Strings.source("RETIRE"),
        },
        left=0,top=0,right=10,bottom=5,
        dataFlags=FLAGS,cursor=1,
      },done)
    end)
    choice=math.floor(tonumber(choice) or 1)
    return choice~=2
  end

  local function beginEscrow(game, rentals)
    local save=game and game.save
    if not save or save.pokesurvive_factory_rentals==true then return false end

    save.battle_factory_crystal_party_backup=save.party
    save.battle_factory_crystal_tower_backup=deepCopy(save.battleTower or {})
    save.battle_factory_crystal_mode=true
    save.battle_factory_crystal_type_map=deepCopy(pendingFactoryTypeMap or {})
    pendingFactoryTypeMap=nil

    if type(rentals)~="table" or #rentals~=3 then
      save.battle_factory_crystal_party_backup=nil
      save.battle_factory_crystal_tower_backup=nil
      save.battle_factory_crystal_mode=nil
      save.battle_factory_crystal_type_map=nil
      restoreFactoryTypeDefs(game)
      return false
    end

    -- Marker before temporary party.
    save.pokesurvive_factory_rentals=true
    save.battle_factory_crystal_wins=0
    save.battle_factory_crystal_streak=0
    save.party=rentals
    return true
  end

  local function restoreEscrow(game)
    local save=game and game.save
    if not save then return false end
    local backup=save.battle_factory_crystal_party_backup
    if type(backup)~="table" then return false end

    save.party=backup
    if type(save.battle_factory_crystal_tower_backup)=="table" then
      save.battleTower=save.battle_factory_crystal_tower_backup
    end

    save.battle_factory_crystal_party_backup=nil
    save.battle_factory_crystal_tower_backup=nil
    save.battle_factory_crystal_mode=nil
    save.battle_factory_crystal_wins=nil
    save.battle_factory_crystal_streak=nil
    save.battle_factory_crystal_lock_species=nil
    save.battle_factory_crystal_type_map=nil
    pendingFactoryTypeMap=nil
    restoreFactoryTypeDefs(game)
    if liveGame and liveGame.world and liveGame.world.vm then
    end
    save.pokesurvive_factory_rentals=nil
    factoryDialogueMode=false
    return true
  end

  local function factoryActive()
    local save=liveGame and liveGame.save
    return save and save.battle_factory_crystal_mode==true
      and save.pokesurvive_factory_rentals==true
  end

  -- RUN in a Factory trainer battle means "retire the rental run", not the
  -- vanilla trainer-battle refusal. Ask first so an accidental A press cannot
  -- throw away a run. NO/B returns to the command menu unchanged; YES ends the
  -- battle with the same lose outcome the Factory wrapper already uses for an
  -- ended run, so escrow restoration and the normal lobby return stay in one
  -- code path.
  local function openFactoryRetirePrompt(state)
    local game=state and state.game
    local stack=game and game.stack
    if not stack then return nil, "no UI stack" end

    local Menu=require("src.ui.Menu")
    local Font=require("src.render.Font")

    local overlay={}
    local menu
    menu=Menu.new(game,{
      {label="YES",onSelect=function()
        local battle=state and state.battle
        if battle and not battle.over then battle:endBattle("lose") end
        if state and state.finishBattle then state:finishBattle() end
      end},
      {label="NO",onSelect=function() end},
    },{tx=12,ty=9,tw=8,th=6,rowStep=2,cancelable=true})

    function overlay:update(dt) menu:update(dt) end
    function overlay:draw()
      -- Two-line Factory dialogue rule: the confirmation itself is exactly
      -- two visible lines, with a standard YES/NO box below it.
      Font.drawBox(0,6,20,6)
      love.graphics.setColor(0,0,0,1)
      Font.draw("RETIRE FROM THE",8,56)
      Font.draw("FACTORY RUN?",8,72)
      love.graphics.setColor(1,1,1,1)
      menu:draw()
    end

    stack:push(overlay)
    return true
  end

  do
    local okState,BattleState=pcall(require,"src.ui.gen2.BattleState")
    if okState and BattleState and BattleState.chooseMenu
      and not BattleState._battleFactoryRetirePatched then
      BattleState._battleFactoryRetirePatched=true
      local originalChooseMenu=BattleState.chooseMenu
      BattleState.chooseMenu=function(self,choice,...)
        if choice=="run" and factoryActive()
          and self and self.phase=="menu" and self.battle
          and self.battle.trainer then
          return openFactoryRetirePrompt(self)
        end
        if choice=="item" and factoryActive()
          and self and self.phase=="menu" and self.battle
          and self.battle.trainer then
          -- Factory rules forbid consumable battle items. Temporarily leave
          -- the command-menu phase so Crystal draws the message across the
          -- full battle textbox instead of covering its right half with the
          -- FIGHT/PKMN/PACK/RUN window. A/B then returns to the command menu
          -- without spending the player's turn.
          self.message="No items during\nFactory battles!"
          self.phase="factory-no-items"
          return true
        end
        return originalChooseMenu(self,choice,...)
      end

      -- The native BattleState updater has no concept of our tiny transient
      -- message phase. Handle it before vanilla update logic, then restore
      -- the normal command menu once the player acknowledges the warning.
      if BattleState.update and not BattleState._battleFactoryNoItemsUpdatePatched then
        BattleState._battleFactoryNoItemsUpdatePatched=true
        local originalUpdate=BattleState.update
        BattleState.update=function(self,dt,...)
          if self and self.phase=="factory-no-items" then
            local input=self.game and self.game.input
            if input and (input:wasPressed("a") or input:wasPressed("b")) then
              self.message=nil
              self.messageTimer=0
              self.phase="menu"
            end
            return
          end
          return originalUpdate(self,dt,...)
        end
      end
    end
  end

  local function buildFactoryHeadParty(game,head)
    local party={}
    for _,id in ipairs(head and head.team or {}) do
      if game and game.data and game.data.pokemon and game.data.pokemon[id] then
        local mon=makeMon(game,id,50)
        if mon then
          assignFactoryTypes(game,mon)
          curateFactoryMoves(game,mon,factoryClass(game))
          mon.battleFactoryRental=true
          mon.battleFactoryClass=factoryClass(game)
          mon.battleFactoryHead=true
          party[#party+1]=mon
        end
      end
    end
    return party
  end

  local function buildFactoryOpponentParty(game)
    local blocked={}
    for _,mon in ipairs(game and game.save and game.save.party or {}) do
      if mon and mon.species then blocked[mon.species]=true end
    end
    local ids=chooseUniqueSpecies(game,factoryClass(game),3,blocked,true)
    if #ids<3 then
      ids=chooseUniqueSpecies(game,factoryClass(game),3,{},true)
    end
    local party={}
    for _,id in ipairs(ids) do
      local mon=makeMon(game,id,50)
      if mon then
        assignFactoryTypes(game,mon)
        curateFactoryMoves(game,mon,factoryClass(game))
        mon.battleFactoryRental=true
        mon.battleFactoryClass=factoryClass(game)
        party[#party+1]=mon
      end
    end
    return party
  end

  local CLASS_SPRITE_ALIASES={
    -- Factory Head presentation aliases. Trainer class IDs and overworld
    -- sprite IDs are not always named identically in Crystal (notably Oak
    -- and Lance), so keep these explicit. The first existing sprite wins.
    BROCK={"SPRITE_BROCK"},
    KOGA={"SPRITE_KOGA"},
    BLAINE={"SPRITE_BLAINE"},
    BLUE={"SPRITE_BLUE"},
    WILL={"SPRITE_WILL"},
    KAREN={"SPRITE_KAREN"},
    CHAMPION={"SPRITE_LANCE"},
    CLAIR={"SPRITE_CLAIR"},
    POKEMON_PROF={"SPRITE_OAK","SPRITE_PROF_OAK"},
    RED={"SPRITE_RED"},
    COOLTRAINERM={"SPRITE_COOLTRAINER_M","SPRITE_COOLTRAINER"},
    COOLTRAINERF={"SPRITE_COOLTRAINER_F","SPRITE_COOLTRAINER"},
    POKEFANM={"SPRITE_POKEFAN_M","SPRITE_POKEFAN"},
    POKEFANF={"SPRITE_POKEFAN_F","SPRITE_POKEFAN"},
    SWIMMERM={"SPRITE_SWIMMER_GUY","SPRITE_SWIMMER_M","SPRITE_SWIMMER"},
    SWIMMERF={"SPRITE_SWIMMER_GIRL","SPRITE_SWIMMER_F","SPRITE_SWIMMER"},
    GRUNTM={"SPRITE_ROCKET","SPRITE_ROCKET_M"},
    GRUNTF={"SPRITE_ROCKET_GIRL","SPRITE_ROCKET_F"},
    EXECUTIVEM={"SPRITE_ROCKET","SPRITE_ROCKET_M"},
    EXECUTIVEF={"SPRITE_ROCKET_GIRL","SPRITE_ROCKET_F"},
    BLACKBELT_T={"SPRITE_BLACK_BELT","SPRITE_BLACKBELT"},
    PSYCHIC_T={"SPRITE_PSYCHIC"},
    POKEMANIAC={"SPRITE_POKEFAN_M","SPRITE_SUPER_NERD"},
    FIREBREATHER={"SPRITE_SUPER_NERD","SPRITE_FISHER"},
  }

  local function classOverworldSprite(game,classId,fallback)
    local sprites=game and game.data and game.data.gen2Sprites
    if type(sprites)~="table" then return fallback end

    local candidates={}
    for _,id in ipairs(CLASS_SPRITE_ALIASES[classId] or {}) do
      candidates[#candidates+1]=id
    end

    candidates[#candidates+1]="SPRITE_"..tostring(classId or "")
    candidates[#candidates+1]="SPRITE_"..tostring(classId or ""):gsub("M$","_M")
    candidates[#candidates+1]="SPRITE_"..tostring(classId or ""):gsub("F$","_F")

    for _,id in ipairs(candidates) do
      if sprites[id] then return id end
    end

    -- Last chance: compare normalized class/sprite names and pick the closest
    -- exact token match. This catches cache naming differences like
    -- BLACKBELT_T -> SPRITE_BLACK_BELT without hard-coding every class.
    local want=tostring(classId or ""):gsub("[^A-Z0-9]","")
    want=want:gsub("_T$","")
    for id,_ in pairs(sprites) do
      if type(id)=="string" and id:match("^SPRITE_") then
        local have=id:gsub("^SPRITE_",""):gsub("[^A-Z0-9]","")
        if have==want then return id end
      end
    end

    return fallback
  end

  local function forceRoomTrainerSprite(game,objectId,spriteName)
    local world=game and game.world
    if not (world and spriteName) then return false end
    objectId=math.floor(tonumber(objectId) or 0)

    -- The Battle Tower room object is rebuilt/re-read while its movement
    -- script runs. Updating only the live NPC makes it look correct once it
    -- stops, but it can walk in using the map object's original YOUNGSTER
    -- sheet. Stamp the map object too, before movement begins.
    local def=world.map and world.map.def
    local obj=def and def.objects and def.objects[objectId-1]
    if obj then obj.sprite=spriteName end

    local ok=world:setObjectSprite(objectId,spriteName)
    if world.rebuildPeople then world:rebuildPeople({seamless=true}) end
    return ok
  end

  -- Preserve vanilla handlers for normal Tower mode.
  local vanillaTryQuickSave=Vm.SPECIALS.TryQuickSave
  local vanillaRoomMenu=Vm.SPECIALS.BattleTowerRoomMenu
  local vanillaRules=Vm.SPECIALS.CheckForBattleTowerRules
  local vanillaLoadOpponent=Vm.SPECIALS.LoadOpponentTrainerAndPokemonWithOTSprite
  local vanillaTowerBattle=Vm.SPECIALS.BattleTowerBattle

  -- Factory must never write a save while the adventure party is escrowed.
  -- Pretend the Tower quick-save succeeded and let the native escort continue.
  Vm.SPECIALS.TryQuickSave=function(vm)
    if not factoryActive() then return vanillaTryQuickSave(vm) end
    S.answer(vm,1)
  end

  -- Rentals are supplied by us, so the player's adventure-party legality is
  -- irrelevant. The fixed dev rentals are legal anyway, but this makes the
  -- boundary explicit for future randomized rental rosters.
  Vm.SPECIALS.CheckForBattleTowerRules=function(vm)
    if not factoryActive() then return vanillaRules(vm) end
    S.answer(vm,0)
  end

  -- The normal Tower asks which L10-L100 room to enter. Factory rentals are
  -- currently Lv50, so silently select the L50 room and allow the SAME native
  -- receptionist/elevator/hallway script to proceed.
  Vm.SPECIALS.BattleTowerRoomMenu=function(vm)
    if not factoryActive() then
      -- The native menu returns the selected L10-L100 room through
      -- vm.btLevelGroup.  Persist it immediately as well: the opponent loader
      -- reads BattleTower.state(save).levelGroup, and relying on the later ROM
      -- SAVELEVELGROUP action can leave the recomp-side roster stuck on the
      -- default L10 group.
      local result=vanillaRoomMenu(vm)
      local group=math.floor(tonumber(vm.btLevelGroup) or 0)
      if group>=1 and group<=BattleTower.MAX_LEVEL_GROUP then
        local record=S.save(vm)
        if record then BattleTower.state(record).levelGroup=group end
      end
      return result
    end
    vm.btLevelGroup=5
    local save=liveGame and liveGame.save
    if save then BattleTower.state(save).levelGroup=5 end
    S.answer(vm,0)
  end

  -- Native room opponent entrance, replaced with our Factory opponent.
  Vm.SPECIALS.LoadOpponentTrainerAndPokemonWithOTSprite=function(vm)
    if not factoryActive() then return vanillaLoadOpponent(vm) end

    -- Native opponent generation reads the persistent Tower level-group byte,
    -- not merely vm.btLevelGroup. Reassert L50 every round so a stale vanilla
    -- L10 selection can never leak into a Factory run.
    local save=liveGame and liveGame.save
    if save then BattleTower.state(save).levelGroup=5 end
    vm.btLevelGroup=5

    -- Let Crystal's own Battle Tower logic choose the trainer AND the three
    -- Pokémon. This fixes dev.13's split-brain bug where the room presentation
    -- could use a native Tower team while the swap screen offered our separate
    -- hard-coded Factory team.
    vanillaLoadOpponent(vm)

    local opp=vm.btOpponent
    if not opp then return end

    local head=currentFactoryHead(liveGame)
    vm._factoryCrystalHead=head
    if head then
      local headClass=resolveHeadClass(liveGame,head,opp.classId)
      opp.classId=headClass
      opp.class=headClass
      opp.name=head.name
      vm._factoryCrystalGeneratedEnemy=buildFactoryHeadParty(liveGame,head)
      if #vm._factoryCrystalGeneratedEnemy~=3 then
        vm._factoryCrystalGeneratedEnemy=buildFactoryOpponentParty(liveGame)
      end
    else
      vm._factoryCrystalGeneratedEnemy=buildFactoryOpponentParty(liveGame)
    end

    -- Battle portraits are keyed from classId. Resolve the room NPC from that
    -- SAME classId rather than blindly trusting the Battle Tower's generic
    -- overworld table. Fallback remains Crystal's own opp.sprite.
    local roomSprite=classOverworldSprite(liveGame,opp.classId,opp.sprite)
    if roomSprite then
      forceRoomTrainerSprite(liveGame,vm.scriptVar,roomSprite)
    end
    vm._factoryCrystalRoomSprite=roomSprite

    -- Do NOT snapshot the team here. PokeSurvive's trainer.party hook can
    -- transform this roster while Battle.new is being constructed. The real
    -- swap snapshot is captured from battle.started below.
    vm._factoryCrystalDefeatedSnapshot=nil
  end

  -- Native room has already performed all walking/entrance choreography.
  Vm.SPECIALS.BattleTowerBattle=function(vm)
    if not factoryActive() then return vanillaTowerBattle(vm) end

    local game=liveGame
    local world=game and game.world
    local opp=vm.btOpponent
    if not (world and opp) then
      vm.btBattleEnded=1
      return S.answer(vm,1)
    end

    local enemyParty=vm._factoryCrystalGeneratedEnemy
      or buildFactoryOpponentParty(game)
    if #enemyParty~=3 then
      vm.btBattleEnded=1
      return S.answer(vm,1)
    end

    -- Fallback only. The preferred snapshot is written by battle.started
    -- from Battle.enemyParty AFTER every trainer.party/randomizer hook ran.
    local defeatedSnapshot=vm._factoryCrystalDefeatedSnapshot

    healParty(game.save.party)

    local classes=game.data and game.data.trainers
      and game.data.trainers.classes
    local class=classes and classes[opp.classId]
    local className=(class and class.name) or opp.classId

    local quotes={
      "Let's see what your\nrentals can do!",
      "Don't hold back!\nGive it your best!",
      "Ready? Let's have\na good battle!",
      "I've got a strong\nteam today!",
      "Show me how well\nyou chose your team!",
      "This should be fun!\nLet's battle!",
    }
    local quote=quotes[((tonumber(opp.index) or 0)%#quotes)+1]
    local head=vm._factoryCrystalHead
    if head then
      vm:showRaw("FACTORY HEAD\n"..tostring(head.name).."!")
      vm:showRaw("You've made it far.\nShow me your team!")
    else
      vm:showRaw(quote)
    end

    -- Give Battle.new a fresh table containing exactly three entries. This
    -- prevents any stale/native roster slots from sharing the Factory party.
    local exactEnemyParty={
      deepCopy(enemyParty[1]),
      deepCopy(enemyParty[2]),
      deepCopy(enemyParty[3]),
    }

    activeFactoryBattleVm=vm
    -- Cross-mod boundary: Factory already selected a class-legal species roster.
    -- PokeSurvive may apply randomized attributes to those species, but it must
    -- not replace them with a new species after tier selection.
    game.save.battle_factory_crystal_lock_species=true
    local outcome=Specials.block(vm,function(done)
      local started=world:startBattle({
        trainer={
          classId=opp.classId,
          class=opp.class,
          className=className,
          name=head and tostring(head.name)
            or (className and (className.." "..tostring(opp.name or ""))
              or opp.name),
          trainerName=head and tostring(head.name) or opp.name,
          party=exactEnemyParty,
          baseMoney=0, -- Factory rewards BP only; never normal prize money.
          attributes=class and class.attributes,
          -- Battle Tower trainer classes can carry consumable trainer items.
          -- Battle Factory rules are rentals-only, so even Factory Heads must
          -- fight without POTION/FULL RESTORE/etc. Passing an empty table keeps
          -- the normal trainer AI while removing its item inventory entirely.
          items={},
        },
        battleTower=true,
        battleType=1, -- CANLOSE
      },done)
      if not started then done("lose") end
    end)
    game.save.battle_factory_crystal_lock_species=nil
    activeFactoryBattleVm=nil

    healParty(game.save.party)

    defeatedSnapshot=vm._factoryCrystalDefeatedSnapshot or defeatedSnapshot
    if type(defeatedSnapshot)~="table" or #defeatedSnapshot~=3 then
      defeatedSnapshot=deepCopy(enemyParty)
    end

    if outcome=="lose" then
      vm:showRaw("The rental run\nhas ended.")
      vm:showRaw(("Final streak: %d."):format(factoryStreak(game)))

      -- Losing OR choosing RUN -> RETIRE ends the climb. Keep permanent
      -- class-clear/shop progression, but the next rental challenge begins
      -- again from CLASS 1.
      if game.save then game.save.battle_factory_crystal_current_class=1 end

      local restored=restoreEscrow(game)
      if not restored and game.save then
        game.save.pokesurvive_factory_rentals=true
      end

      vm._factoryCrystalDefeatedSnapshot=nil
      vm._factoryCrystalGeneratedEnemy=nil
      vm._factoryCrystalHead=nil
      vm.btOpponent=nil
      vm.btBattleEnded=1
      return S.answer(vm,1)
    end

    -- Bank the win BEFORE deciding whether a swap is offered. The seventh
    -- victory ends the class immediately: no post-win rental swap and no
    -- eighth opponent. This mirrors Red's Factory cadence of seven battles,
    -- class-clear ceremony, then a clean return to the receptionist.
    local streak=factoryStreak(game)+1
    game.save.battle_factory_crystal_streak=streak
    game.save.battle_factory_crystal_wins=streak
    game.save.battle_factory_crystal_best=math.max(
      streak,tonumber(game.save.battle_factory_crystal_best) or 0)

    -- Every Factory victory pays 1 BP. Clearing the seventh battle adds the
    -- class bonuses, all of which remain persistent after the rental party is
    -- restored and the player is escorted back to the lobby.
    local reward=1
    local winsInClass=((streak-1)%7)+1
    local cleared=nil

    if winsInClass==7 then
      cleared=math.min(9,math.floor((streak-1)/7)+1)
      local clearRewards=firstClearRewards(game)
      local firstClear=(clearRewards[cleared]~=true)

      reward=reward+5
      if firstClear then
        reward=reward+5
        clearRewards[cleared]=true
      end
      if cleared==9 then reward=reward+15 end

      if cleared>highestClassCleared(game) then
        game.save.battle_factory_crystal_highest_class_cleared=cleared
      end

      -- A successful clear advances the CURRENT climb to the next class.
      -- This is intentionally separate from highestClassCleared(), which is
      -- permanent and only drives unlocks/records.
      game.save.battle_factory_crystal_current_class=math.min(9,cleared+1)

      local bpTotal=addFactoryBP(game,reward)
      local clearedHead=vm._factoryCrystalHead
      if clearedHead then
        vm:showRaw(("HEAD %s\ndefeated!"):format(clearedHead.name))
      end
      vm:showRaw(("CLASS %d CLEARED!"):format(cleared))
      vm:showRaw(("Earned %d BP.\nTotal: %d BP."):format(reward,bpTotal))
      if cleared<9 then
        vm:showRaw(("CLASS %d is now\nunlocked!"):format(cleared+1))
      else
        vm:showRaw("MASTER CLASS\ncleared!")
      end

      -- A class clear is the end of this rental run. Restoring escrow here
      -- makes S.answer(...,1) follow the exact same native exit choreography
      -- as a loss/retirement, placing the player back at the attendant desk.
      restoreEscrow(game)
      vm._factoryCrystalDefeatedSnapshot=nil
      vm._factoryCrystalGeneratedEnemy=nil
      vm._factoryCrystalHead=nil
      vm.btOpponent=nil
      vm.btBattleEnded=1
      return S.answer(vm,1)
    end

    -- Ordinary victories 1-6 continue the run and therefore retain the
    -- temporary rental party. Only these wins offer the defeated-team swap.
    vm:showRaw("You won the\nrental match!")
    vm:showRaw("You may swap one\nrental if you wish.")

    local swapResult=runSwapScreen(game,vm,defeatedSnapshot)
    if swapResult and swapResult.swapped then
      vm:showRaw("Rental swap\ncomplete.")
    else
      vm:showRaw("You kept your\ncurrent team.")
    end

    healParty(game.save.party)

    local bpTotal=addFactoryBP(game,reward)
    vm:showRaw(("Earned %d BP.\nTotal: %d BP."):format(reward,bpTotal))

    -- Keep the native Tower room below its own seven-win completion trigger.
    if vm.mem then vm.mem[BattleTower.WRAM_NR_BEATEN]=winsInClass % 256 end
    vm:setStringBuffer(tostring(winsInClass+1))

    vm._factoryCrystalDefeatedSnapshot=nil
    vm._factoryCrystalGeneratedEnemy=nil
    vm._factoryCrystalHead=nil
    vm.btOpponent=nil
    vm.btBattleEnded=1
    S.answer(vm,0)
  end

  local function beginFactoryDraft(vm,game,classNo,battleNo)
    classNo=math.max(1,math.min(9,math.floor(tonumber(classNo) or 1)))
    battleNo=math.max(1,math.min(7,math.floor(tonumber(battleNo) or 1)))

    -- Streak is the number of wins already banked. This places the very next
    -- opponent at the requested class/battle. Battle 7 in Classes 3-9 is the Head.
    game.save.battle_factory_crystal_streak=(classNo-1)*7+(battleNo-1)
    vm:showRaw(("A new run starts\nin CLASS %d."):format(classNo))
    vm:showRaw("Choose three\nrental POKéMON.")
    local rentals=selectThreeRentals(game,vm)
    if not rentals then
      vm:showRaw("Rental selection\nwas cancelled.")
      factoryDialogueMode=false
      return false
    end
    for _,mon in ipairs(rentals) do
      curateFactoryMoves(game,mon,classNo)
    end
    if not beginEscrow(game,rentals) then
      vm:showRaw("I couldn't prepare\nyour rental party.")
      factoryDialogueMode=false
      return false
    end
    vm:showRaw("Your rentals are ready.\nPlease follow me.")
    return true
  end

  -- Receptionist choice. Factory now enters the SAME script branch as vanilla
  -- Challenge after installing rentals, instead of performing any direct map warp.
  Vm.SPECIALS.Menu_ChallengeExplanationCancel=function(vm)
    local h=S.hooks(vm)
    local choice=Specials.block(vm,function(done)
      if not h.scriptMenu then return done(0) end
      h.scriptMenu({
        items=ROWS,left=0,top=0,right=16,bottom=9,
        dataFlags=FLAGS,cursor=1,
      },done)
    end)
    choice=math.floor(tonumber(choice) or 0)

    if choice==1 then
      return S.answer(vm,1) -- vanilla Tower
    elseif choice==2 then
      factoryDialogueMode=true
      local game=liveGame
      if not game or not game.save then
        vm:showRaw("The FACTORY system\nisn't ready yet.")
        factoryDialogueMode=false
        return S.answer(vm,4)
      end
      if factoryActive() then
        vm:showRaw("A rental challenge\nis already active.")
        return S.answer(vm,4)
      end

      local classNo,battleNo=currentFactoryRank(game),1
      vm:showRaw(("Your current rank:\nCLASS %d."):format(classNo))
      if not bpConfirm(vm,("Start a CLASS %d\nrental run?"):format(classNo)) then
        factoryDialogueMode=false
        return S.answer(vm,4)
      end

      if not beginFactoryDraft(vm,game,classNo,battleNo) then
        return S.answer(vm,4)
      end

      -- Enter Crystal's normal Challenge branch so escort/elevator/room
      -- choreography remains identical to a real Factory run.
      return S.answer(vm,1)
    elseif choice==3 then
      return S.answer(vm,2) -- explanation
    end
    return S.answer(vm,4)
  end

  -- Dedicated lobby interactions. The receptionist handles Tower/Factory
  -- entry; a second machine beside her handles BP rewards, and a Game Boy kid
  -- gives a PokeSurvive randomizer hint.
  mod.content.commands:register("battle_factory_crystal:bp_terminal",{
    foreground=true,
    fn=function(ctx)
      local vm=ctx and ctx.vm
      local game=liveGame
      if not (vm and game and game.save) then return end
      runBPShop(game,vm)
    end,
  })

  mod.content.commands:register("battle_factory_crystal:color_kid",{
    foreground=true,
    fn=function(ctx)
      local vm=ctx and ctx.vm
      if not vm then return end
      factoryDialogueMode=true
      vm:showRaw("I watch POKéMON\ncolors really close!")
      vm:showRaw("With random types,\nthe colors are clues.")
      vm:showRaw("See a fiery color?\nMaybe it's FIRE!")
      vm:showRaw("It's not guaranteed,\nbut I like guessing!")
      factoryDialogueMode=false
    end,
  })

  local function ensureFactoryLobbyNpcs(game)
    local world=game and game.world
    if not (world and world.maps and world.maps.BATTLE_TOWER_1F) then return end
    local def=world.maps.BATTLE_TOWER_1F
    def.objects=def.objects or {}
    def.bgEvents=def.bgEvents or {}

    -- Remove the old scientist runtime NPC if this map table was already
    -- touched by an earlier dev build in the same process.
    for i=#def.objects,1,-1 do
      local obj=def.objects[i]
      if obj.owner=="battle_factory_crystal_bp_scientist" then
        table.remove(def.objects,i)
      end
    end

    -- Keep the Game Boy kid from dev.37.
    local kid=false
    for _,obj in ipairs(def.objects) do
      if obj.owner=="battle_factory_crystal_color_kid" then kid=true end
    end
    if not kid then
      world:addRuntimeObject("BATTLE_TOWER_1F",{
        sprite="SPRITE_GAMEBOY_KID",
        x=12,y=8,
        movement=0,
        type=0,
        scriptKey="battle_factory_crystal:color_kid_script",
      },"battle_factory_crystal_color_kid")
    end

    -- Build a second copy of the tall blue terminal immediately to the RIGHT
    -- of the attendant. The original terminal occupies cell-column x=6; the
    -- new one occupies x=8. Because Gen II maps are 32x32 metatiles (two
    -- object cells wide), clone just the left 16px half of the source blocks
    -- into the left half of the neighboring destination blocks.
    if not def._battleFactoryBpTerminalBuilt then
      local tileset=world.tilesets and world.tilesets[def.tileset]
      if tileset and tileset.blocks and tileset.collision and def.blocks then
        local function blockAt(bx,by)
          return def.blocks[by*def.width+bx+1]
        end
        local function cloneMachineHalf(srcBx,srcBy,dstBx,dstBy)
          local srcId=blockAt(srcBx,srcBy)
          local dstId=blockAt(dstBx,dstBy)
          local src=tileset.blocks[(srcId or 0)+1]
          local dst=tileset.blocks[(dstId or 0)+1]
          local srcColl=tileset.collision[(srcId or 0)+1]
          local dstColl=tileset.collision[(dstId or 0)+1]
          if not (src and dst and srcColl and dstColl) then return false end

          local mixed={}
          for i=1,16 do mixed[i]=dst[i] end
          -- Four tile rows; copy tile columns 0-1 (one 16px object cell).
          for row=0,3 do
            mixed[row*4+1]=src[row*4+1]
            mixed[row*4+2]=src[row*4+2]
          end

          local mixedColl={}
          for i=1,4 do mixedColl[i]=dstColl[i] end
          -- Collision quad left column: top-left and bottom-left cells.
          mixedColl[1]=srcColl[1]
          mixedColl[3]=srcColl[3]

          local newId=#tileset.blocks
          tileset.blocks[newId+1]=mixed
          tileset.collision[newId+1]=mixedColl
          def.blocks[dstBy*def.width+dstBx+1]=newId
          return true
        end

        -- Source x=6 -> block column 3. Destination x=8 -> block column 4.
        -- The machine spans the lower half of block row 2 and upper/lower
        -- portions of row 3, so copy both vertical blocks.
        local a=cloneMachineHalf(3,2,4,2)
        local c=cloneMachineHalf(3,3,4,3)
        if a or c then
          def._battleFactoryBpTerminalBuilt=true
          if world.dropMapImages then world:dropMapImages("BATTLE_TOWER_1F") end
        end
      end
    end

    -- The new terminal's lower cell is x=8,y=6. Interacting from below while
    -- facing up opens the BP shop, just like reading a normal BG machine/sign.
    local terminalEvent=false
    for _,ev in ipairs(def.bgEvents) do
      if ev.owner=="battle_factory_crystal_bp_terminal" then
        terminalEvent=true
        ev.x,ev.y=8,6
      end
    end
    if not terminalEvent then
      def.bgEvents[#def.bgEvents+1]={
        x=8,y=6,kind=0,
        scriptKey="battle_factory_crystal:bp_terminal_script",
        owner="battle_factory_crystal_bp_terminal",
      }
    end

    local vm=world.vm
    if vm and vm.scripts then
      vm.scripts["battle_factory_crystal:bp_terminal_script"]={
        {op="modcommand",verb="battle_factory_crystal:bp_terminal",args={}},
        {op="end"},
      }
      vm.scripts["battle_factory_crystal:color_kid_script"]={
        {op="modcommand",verb="battle_factory_crystal:color_kid",args={}},
        {op="end"},
      }
    end

    if world.map and world.map.id=="BATTLE_TOWER_1F"
      and world.rebuildPeople then
      world:rebuildPeople({seamless=true})
    end
  end

  local function installFactoryTextGuards(game)
    local world=game and game.world
    local vm=world and world.vm
    if not vm or vm._battleFactoryCrystalTextGuard then return end
    vm._battleFactoryCrystalTextGuard=true

    local originalShow=vm.showTextFn
    local originalYesNo=vm.yesornoFn

    -- The actual blocking HealMachineAnim callback lives on vm.healAnimFn,
    -- not vm.specials.healAnim. In Factory mode we skip the machine/palette
    -- animation entirely, keep the healing jingle, then immediately resume.
    if type(vm.healAnimFn)=="function"
      and not vm._battleFactoryHealAnimWrapped then
      vm._battleFactoryHealAnimWrapped=true
      local originalHealAnimFn=vm.healAnimFn
      vm.healAnimFn=function(animType,onDone)
        if factoryActive() then
          if liveGame and liveGame.data then
            Music.playOnce(liveGame.data,"Music_HealPokemon")
          end
          if onDone then onDone() end
          return
        end
        return originalHealAnimFn(animType,onDone)
      end
    end

    if originalShow then
      vm.showTextFn=function(text,onDone,stay,hold)
        local lower=tostring(text or ""):lower()
        local inFactory=factoryDialogueMode or factoryActive()
        if inFactory
          and tostring(world.map and world.map.id)=="BATTLE_TOWER_1F"
          and lower:find("save",1,true)
          and (lower:find("battle",1,true) or lower:find("enter",1,true)) then
          -- Factory escrow is intentionally NOT written to disk. Suppress the
          -- vanilla pre-Tower save warning and auto-accept its following prompt.
          vm._battleFactorySkipSaveYesNo=true
          if onDone then onDone() end
          return
        end
        if inFactory then text=paceFactoryText(text) end
        return originalShow(text,onDone,stay,hold)
      end
    end

    if originalYesNo then
      vm.yesornoFn=function(onDone)
        if (factoryDialogueMode or factoryActive())
          and vm._battleFactorySkipSaveYesNo then
          vm._battleFactorySkipSaveYesNo=nil
          if onDone then onDone(true) end
          return
        end
        return originalYesNo(onDone)
      end
    end
  end

  -- Capture the exact enemy roster the player is about to fight.
  -- Gen 2 Battle.new emits this only AFTER trainer.party hooks have finished,
  -- so PokeSurvive randomization is already baked into enemyParty here.
  mod.events:on("battle.started",function(ev)
    local vm=activeFactoryBattleVm
    local battle=ev and ev.battle
    if not (vm and factoryActive() and battle and battle.trainer) then return end

    if type(battle.enemyParty)=="table" then
      local classNo=factoryClass(liveGame)
      local legal={}
      for _,id in ipairs(validClassPool(liveGame,classNo)) do legal[id]=true end
      local source=vm._factoryCrystalGeneratedEnemy or {}

      -- Factory battles are always exactly 3-on-3. A later randomizer hook can
      -- mutate trainer.party after our generated roster is supplied, including
      -- appending extra mons. Clamp the ACTUAL battle party back to three.
      while #battle.enemyParty>3 do
        table.remove(battle.enemyParty)
      end
      while #battle.enemyParty<3 and source[#battle.enemyParty+1] do
        battle.enemyParty[#battle.enemyParty+1]=
          deepCopy(source[#battle.enemyParty+1])
      end

      for i=1,3 do
        local mon=battle.enemyParty[i]
        if mon and not legal[mon.species] and source[i] then
          battle.enemyParty[i]=deepCopy(source[i])
          mon=battle.enemyParty[i]
        end
        if mon then
          curateFactoryMoves(liveGame,mon,classNo)
          mon.battleFactoryRental=true
          mon.battleFactoryClass=classNo
        end
      end

      -- Snapshot only the validated 3-mon roster used by the fight/swap UI.
      if #battle.enemyParty==3 then
        vm._factoryCrystalDefeatedSnapshot=deepCopy(battle.enemyParty)
      end
    end

    -- If another mod resolves the trainer class during construction, repaint
    -- the room NPC against that exact final class as well.
    local classId=battle.trainer.classId or battle.trainer.class
    local roomSprite=classOverworldSprite(liveGame,classId,
      vm._factoryCrystalRoomSprite)
    if roomSprite then
      forceRoomTrainerSprite(liveGame,vm.scriptVar,roomSprite)
      vm._factoryCrystalRoomSprite=roomSprite
    end
  end)

  mod.events:on("save.created",function()
    if liveGame and liveGame.save then
      liveGame.save.battle_factory_crystal_highest_class_cleared=
        liveGame.save.battle_factory_crystal_highest_class_cleared or 0
      liveGame.save.battle_factory_crystal_best=
        liveGame.save.battle_factory_crystal_best or 0
      liveGame.save.battle_factory_crystal_bp=
        liveGame.save.battle_factory_crystal_bp or 0
      if type(liveGame.save.battle_factory_crystal_first_clear_rewards)~="table" then
        liveGame.save.battle_factory_crystal_first_clear_rewards={}
      end
    end
  end)

  mod.hooks:wrap("input.step",function(next,game,dt)
    liveGame=game
    if game and game.save and game.save.battle_factory_crystal_mode==true then reapplyFactoryTypeMap(game) end
    installFactoryTextGuards(game)
    ensureFactoryLobbyNpcs(game)
    local result=next(game,dt)
    return result
  end,100)

  mod.log:info("Crystal Battle Factory native escorted route installed.")
end
