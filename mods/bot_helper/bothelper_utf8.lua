--[[
  ==============================================================
  [ BOT HELPER â€” v3.1 ]
  Abas: tools | healing | caster
  Fases: Motor de Cura, UIItem, Tooltips, Status toggle por aba
  ==============================================================
]]

BOT_USE_CPP_SCHEDULER = false -- Se true, usa o motor C++ (1ms). Se false, usa o motor Lua (50ms).

BotHelper = {}

-- === REFERÃŠNCIAS DE MEMÃ“RIA ===
BotHelper.window        = nil
BotHelper.topMenuButton = nil
BotHelper.currentTab    = 'tools'
BotHelper.healingCycle  = nil
BotHelper.keyCapturing  = nil
BotHelper._hotkeyHandler = nil  -- handler persistente de hotkeys no rootWidget
BotHelper.BOT_DEBUG_GEOMETRY = true -- Mudar para false para desabilitar o debug visual no console

-- === HELPERS LOCAIS ===
local function table_contains(table, element)
  for _, value in pairs(table) do
    if value == element then return true end
  end
  return false
end

-- =============================================================
-- MAPEAMENTO CANÃ”NICO DAS ABAS
-- =============================================================
BotHelper.TAB_MAP = {
  tools   = { btn = 'tabTools',   panel = 'toolsPanel',   scrollbar = 'toolsScrollBar',   label = 'Tools Helper'   },
  healing = { btn = 'tabHealing', panel = 'healingPanel', scrollbar = 'healingScrollBar', label = 'Healing Helper' },
  caster  = { btn = 'tabCaster',  panel = 'casterPanel',  scrollbar = 'casterScrollBar',  label = 'SpellCaster'    },
}

-- =============================================================
-- AoE â€” matrizes relativas ao jogador virado para NORTE (y negativo = frente)
-- Formato: { { x = 0, y = -1 }, ... } â†’ g_map.getEnemiesInArea(...)
-- =============================================================
local SPELL_WAVE_CONE_NORTH = {
  { x = 0, y = -1 },
  { x = -1, y = -2 }, { x = 0, y = -2 }, { x = 1, y = -2 },
  { x = -2, y = -3 }, { x = -1, y = -3 }, { x = 0, y = -3 }, { x = 1, y = -3 }, { x = 2, y = -3 },
}

local SPELL_EXORI_RING = {
  { x = -1, y = -1 }, { x = 0, y = -1 }, { x = 1, y = -1 },
  { x = -1, y = 0 },                       { x = 1, y = 0 },
  { x = -1, y = 1 },  { x = 0, y = 1 },  { x = 1, y = 1 },
}

-- Anel externo 5x5 (sem o quadrado 3x3 central) â€” â€œcruz grossaâ€ / Ã¡rea expandida
local SPELL_EXORI_GRAN_AREA = {}
do
  for dx = -2, 2 do
    for dy = -2, 2 do
      local inner = (math.abs(dx) <= 1 and math.abs(dy) <= 1)
      if not inner then
        SPELL_EXORI_GRAN_AREA[#SPELL_EXORI_GRAN_AREA + 1] = { x = dx, y = dy }
      end
    end
  end
end

-- UE-style: bloco 7x7 sem o centro (ajuste se seu servidor usar outro raio)
local SPELL_UE_AREA = {}
do
  for dx = -3, 3 do
    for dy = -3, 3 do
      if not (dx == 0 and dy == 0) then
        SPELL_UE_AREA[#SPELL_UE_AREA + 1] = { x = dx, y = dy }
      end
    end
  end
end

-- Chaves em minÃºsculas (use normalizeSpellWords ao buscar)
local SpellAreaMatrices = {
  ['exori'] = SPELL_EXORI_RING,
  ['exori gran'] = SPELL_EXORI_GRAN_AREA,
  ['exori mas'] = SPELL_EXORI_GRAN_AREA,
  ['exori min'] = SPELL_WAVE_CONE_NORTH,
  ['exevo vis hur'] = SPELL_WAVE_CONE_NORTH,
  ['exevo frigo hur'] = SPELL_WAVE_CONE_NORTH,
  ['exevo terra hur'] = SPELL_WAVE_CONE_NORTH,
  ['exevo terra hurr'] = SPELL_WAVE_CONE_NORTH,
  ['exevo flam hur'] = SPELL_WAVE_CONE_NORTH,
  ['exevo mort hur'] = SPELL_WAVE_CONE_NORTH,
  ['exevo san hur'] = SPELL_WAVE_CONE_NORTH,
  ['exevo gran mas tera'] = SPELL_UE_AREA,
  ['exevo gran mas vis'] = SPELL_UE_AREA,
  ['exevo gran mas flam'] = SPELL_UE_AREA,
  ['exevo gran mas frigo'] = SPELL_UE_AREA,
  ['exevo gran mas mort'] = SPELL_UE_AREA,
  ['exevo mas san'] = SPELL_UE_AREA,
}
-- ReferÃªncia pÃºblica: mesma tabela (minÃºsculas nas chaves)
BotHelper.SpellAreaMatrices = SpellAreaMatrices

local function normalizeSpellWords(words)
  if not words or type(words) ~= 'string' then return '' end
  local w = words:lower():gsub('^%s+', ''):gsub('%s+$', '')
  return w
end

-- =============================================================
-- PERSISTÃŠNCIA â€” g_settings (Per-Character)
-- =============================================================
local function cfgKey(tab, field)
  local charName = 'Default'
  if g_game.isOnline() then
    local player = g_game.getLocalPlayer()
    if player then charName = player:getName() end
  end
  return 'BotHelper.' .. charName .. '.' .. tab .. '.' .. field
end

local function cfgGet(tab, field, default)
  local v = g_settings.get(cfgKey(tab, field))
  if v == nil or v == '' then return default end
  if type(default) == 'number'  then return tonumber(v) or default end
  if type(default) == 'boolean' then return v == 'true' end
  return v
end

local function cfgSet(tab, field, value)
  g_settings.set(cfgKey(tab, field), tostring(value))
end

-- =============================================================
-- HELPER: verifica se uma aba esta habilitada
-- Usada como guarda-portao no motor de cura
-- =============================================================
local function isTabEnabled(tab)
  return cfgGet(tab, 'enabled', false)
end

-- =============================================================
-- INIT
-- =============================================================
function BotHelper.init()
  BotHelper.topMenuButton = modules.game_mainpanel.addToggleButton(
    'botHelperToggle', tr('Bot Helper'), '/images/options/bot',
    BotHelper.toggle, false, 99999
  )
  BotHelper.topMenuButton:setOn(false)

  connect(g_game, {
    onGameStart = BotHelper.onGameStart,
    onGameEnd   = BotHelper.onGameEnd,
  })

  BotHelper.setupUI()
end

-- =============================================================
-- TERMINATE
-- =============================================================
function BotHelper.terminate()
  BotHelper.stopToolsEngine()
  BotHelper.stopHealingEngine()
  BotHelper.stopCasterEngine()
  disconnect(g_game, { onGameStart = BotHelper.onGameStart, onGameEnd = BotHelper.onGameEnd })
  if BotHelper.topMenuButton then BotHelper.topMenuButton:destroy(); BotHelper.topMenuButton = nil end
  if BotHelper.window         then BotHelper.window:destroy();        BotHelper.window = nil end
end

-- =============================================================
-- CALLBACKS DE JOGO
-- =============================================================
function BotHelper.onGameStart()
  BotHelper.Tools.loadConfigToUI()
  BotHelper.Healing.loadConfigToUI()
  BotHelper.SpellCaster.loadConfigToUI()
  
  BotHelper.startBotEngine()
  BotHelper.syncScheduler()
  
  if isTabEnabled('tools')   then BotHelper.startToolsEngine()   else BotHelper.stopToolsEngine()   end
  if isTabEnabled('healing') then BotHelper.startHealingEngine() else BotHelper.stopHealingEngine() end
  if isTabEnabled('caster')  then BotHelper.startCasterEngine()  else BotHelper.stopCasterEngine()  end
  
  BotHelper.refreshFooter()
end

function BotHelper.onGameEnd()
  BotHelper.stopToolsEngine()
  BotHelper.stopHealingEngine()
  BotHelper.stopCasterEngine()
  BotHelper.stopBotEngine()
  BotHelper.Tools.loadConfigToUI()
  BotHelper.Healing.loadConfigToUI()
  BotHelper.SpellCaster.loadConfigToUI()
end

-- =============================================================
-- SETUP UI
-- =============================================================
function BotHelper.setupUI()
  if BotHelper.window then return end

  BotHelper.window = g_ui.displayUI('bothelper')
  if not BotHelper.window then
    perror('[BotHelper] Erro fatal: bothelper.otui ausente ou corrompido.')
    return
  end

  local function safeTooltip(panel, btnId, text)
    if not panel then return end
    local btn = panel:recursiveGetChildById(btnId)
    if btn then btn:setTooltip(text) end
  end

  local healPanel = BotHelper.window:recursiveGetChildById('sectionAutoHeal')
  if healPanel then
    local spellTip  = 'Clique direito no slot para atribuir a magia.\nMenor % tem prioridade de uso.'
    local potionTip = 'Clique direito no slot para atribuir a pocao.\nMenor % tem prioridade de uso.'
    local manaTip   = 'Clique direito no slot para atribuir a pocao.\nUsa quando mana% <= valor configurado.'
    safeTooltip(healPanel, 'btnInfoSpellHeal1',  spellTip)
    safeTooltip(healPanel, 'btnInfoSpellHeal2',  spellTip)
    safeTooltip(healPanel, 'btnInfoSpellHeal3',  spellTip)
    safeTooltip(healPanel, 'btnInfoPotionHeal1', potionTip)
    safeTooltip(healPanel, 'btnInfoPotionHeal2', potionTip)
    safeTooltip(healPanel, 'btnInfoPotionHeal3', manaTip)
  end

  local footer = BotHelper.window:getChildById('botHelperFooter')
  if footer then
    local btnSetKey = footer:getChildById('btnSetKey')
    if btnSetKey then
      btnSetKey.onClick = function() BotHelper.captureHotkey(BotHelper.currentTab) end
    end
  end

  BotHelper.SpellCaster.setupComboBoxes()
  BotHelper.Tools.loadConfigToUI()
  BotHelper.Healing.loadConfigToUI()
  BotHelper.SpellCaster.loadConfigToUI()

  BotHelper.window:hide()
  BotHelper.showTab(BotHelper.currentTab)
end

-- =============================================================
-- TOGGLE DA JANELA
-- =============================================================
function BotHelper.toggle()
  if not BotHelper.window then return end
  if BotHelper.window:isVisible() then
    BotHelper.window:hide()
    if BotHelper.topMenuButton then BotHelper.topMenuButton:setOn(false) end
  else
    BotHelper.window:show()
    BotHelper.window:raise()
    BotHelper.window:focus()
    if BotHelper.topMenuButton then BotHelper.topMenuButton:setOn(true) end
    BotHelper.refreshFooter()
  end
end

-- =============================================================
-- ROTEADOR DE ABAS
-- =============================================================
function BotHelper.showTab(tabId)
  if not BotHelper.window then return end
  local content = BotHelper.window:getChildById('botHelperTabContent')
  local tabBar  = BotHelper.window:getChildById('botHelperTabBar')
  if not content or not tabBar then return end

  BotHelper.currentTab = tabId

  for id, route in pairs(BotHelper.TAB_MAP) do
    local active = (id == tabId)
    local btn = tabBar:getChildById(route.btn)
    if btn then btn:setChecked(active) end
    local p = content:getChildById(route.panel)
    if p then p:setVisible(active) end
    local sb = content:getChildById(route.scrollbar)
    if sb then sb:setVisible(active) end
    if active then
      local lbl = tabBar:getChildById('tabLabelText')
      if lbl then lbl:setText(route.label) end
    end
  end

  BotHelper.refreshFooter()
end

-- =============================================================
-- FOOTER DINAMICO
-- =============================================================
function BotHelper.refreshFooter()
  if not BotHelper.window then return end
  local footer = BotHelper.window:getChildById('botHelperFooter')
  if not footer then return end

  local tab    = BotHelper.currentTab
  local isOn   = isTabEnabled(tab)
  local hotkey = cfgGet(tab, 'hotkey', '')

  local lblVal = footer:getChildById('lblHelperStatusVal')
  if lblVal then
    if isOn then
      lblVal:setText('ON')
      lblVal:setColor('#4ade80')
    else
      lblVal:setText('OFF')
      lblVal:setColor('#f87171')
    end
  end

  local btnSetKey = footer:getChildById('btnSetKey')
  if btnSetKey then
    btnSetKey:setText(hotkey ~= '' and ('Key: ' .. hotkey) or 'Set Key')
  end
end

-- =============================================================
-- TOGGLE DE STATUS POR ABA
-- =============================================================
function BotHelper.toggleTabStatus()
  local tab  = BotHelper.currentTab
  local isOn = isTabEnabled(tab)

  cfgSet(tab, 'enabled', not isOn)

  if tab == 'tools' then
    if not isOn then BotHelper.startToolsEngine() else BotHelper.stopToolsEngine() end
  elseif tab == 'healing' then
    if not isOn then BotHelper.startHealingEngine() else BotHelper.stopHealingEngine() end
  elseif tab == 'caster' then
    if not isOn then BotHelper.startCasterEngine() else BotHelper.stopCasterEngine() end
  end

  BotHelper.refreshFooter()
  local tabName  = BotHelper.TAB_MAP[tab] and BotHelper.TAB_MAP[tab].label or tab
  local stateStr = (not isOn) and 'ON' or 'OFF'
  BotHelper.showGameMessage(tabName .. ': ' .. stateStr)
end

-- =============================================================
-- CAPTURA DE HOTKEY
-- =============================================================
function BotHelper.captureHotkey(tabId)
  if BotHelper.keyCapturing then return end
  BotHelper.keyCapturing = tabId
  BotHelper.showGameMessage('Pressione a tecla desejada... (Esc = cancelar)')

  local handler
  handler = function(widget, keyCode, keyMods)
    if not BotHelper.keyCapturing then
      disconnect(rootWidget, { onKeyDown = handler })
      return
    end

    if keyCode == KeyEscape then
      BotHelper.keyCapturing = nil
      BotHelper.showGameMessage('Captura cancelada.')
      disconnect(rootWidget, { onKeyDown = handler })
      return
    end

    local displayName = 'Key#' .. tostring(keyCode)
    local capturedTab = BotHelper.keyCapturing

    cfgSet(capturedTab, 'hotkeyCode', keyCode)
    cfgSet(capturedTab, 'hotkey',     displayName)

    BotHelper.showGameMessage(
      'Atalho definido: ' .. displayName ..
      ' â†’ ' .. (BotHelper.TAB_MAP[capturedTab] and BotHelper.TAB_MAP[capturedTab].label or capturedTab)
    )

    BotHelper.keyCapturing = nil
    disconnect(rootWidget, { onKeyDown = handler })
    BotHelper.refreshFooter()
    BotHelper.registerHotkeys()
  end

  connect(rootWidget, { onKeyDown = handler })

  scheduleEvent(function()
    if BotHelper.keyCapturing then
      BotHelper.keyCapturing = nil
      BotHelper.showGameMessage('Tempo esgotado. Captura cancelada.')
      pcall(function() disconnect(rootWidget, { onKeyDown = handler }) end)
    end
  end, 10000)
end

-- =============================================================
-- REGISTRO DE HOTKEYS GLOBAIS
-- =============================================================
function BotHelper.registerHotkeys()
  if BotHelper._hotkeyHandler then
    pcall(function() disconnect(rootWidget, { onKeyDown = BotHelper._hotkeyHandler }) end)
    BotHelper._hotkeyHandler = nil
  end

  local hasAny = false
  for tabId, _ in pairs(BotHelper.TAB_MAP) do
    if cfgGet(tabId, 'hotkeyCode', 0) > 0 then
      hasAny = true
      break
    end
  end
  if not hasAny then return end

  BotHelper._hotkeyHandler = function(widget, keyCode, keyMods)
    for tabId, _ in pairs(BotHelper.TAB_MAP) do
      local savedCode = cfgGet(tabId, 'hotkeyCode', 0)
      if savedCode > 0 and keyCode == savedCode then
        local prevTab = BotHelper.currentTab
        BotHelper.currentTab = tabId
        BotHelper.toggleTabStatus()
        if prevTab ~= tabId then
          BotHelper.currentTab = prevTab
          BotHelper.refreshFooter()
        end
        return
      end
    end
  end

  connect(rootWidget, { onKeyDown = BotHelper._hotkeyHandler })
end

-- =============================================================
-- MENSAGEM NA TELA
-- =============================================================
function BotHelper.showGameMessage(text)
  if modules.game_textmessage then
    pcall(function() modules.game_textmessage.displayGameMessage(text) end)
  else
    print('[BotHelper] ' .. text)
  end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- SUBSISTEMA: TOOLS ENGINE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
BotHelper.Tools = {}
BotHelper.Tools.config = {
  manaTrain = { enabled = false, pct = 90 },
  exercise = { enabled = false, type = 0 },
  haste = { enabled = false, pz = false },
  changeGold = false,
  autoEat = false,
  autoReconnect = false
}

function BotHelper.Tools.loadConfigToUI()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('toolsPanel')
  if not p then return end

  BotHelper.Tools.config.manaTrain.enabled = cfgGet('tools', 'manaTrain.enabled', false)
  BotHelper.Tools.config.manaTrain.pct     = cfgGet('tools', 'manaTrain.pct', 90)
  
  local chkMana = p:recursiveGetChildById('chkManaEnable')
  local spnMana = p:recursiveGetChildById('spinManaPct')
  if chkMana then chkMana:setChecked(BotHelper.Tools.config.manaTrain.enabled) end
  if spnMana then spnMana:setValue(BotHelper.Tools.config.manaTrain.pct) end

  BotHelper.Tools.config.exercise.enabled = cfgGet('tools', 'exercise.enabled', false)
  local chkEx = p:recursiveGetChildById('chkExerciseEnable')
  if chkEx then chkEx:setChecked(BotHelper.Tools.config.exercise.enabled) end

  BotHelper.Tools.config.haste.enabled = cfgGet('tools', 'haste.enabled', false)
  BotHelper.Tools.config.haste.pz      = cfgGet('tools', 'haste.pz', false)
  
  local chkHaste = p:recursiveGetChildById('chkHasteEnable')
  local chkPz    = p:recursiveGetChildById('chkHastePZ')
  if chkHaste then chkHaste:setChecked(BotHelper.Tools.config.haste.enabled) end
  if chkPz    then chkPz:setChecked(BotHelper.Tools.config.haste.pz) end

  BotHelper.Tools.config.changeGold = cfgGet('tools', 'changeGold', false)
  BotHelper.Tools.config.autoEat    = cfgGet('tools', 'autoEat', false)
  BotHelper.Tools.config.autoReconnect = cfgGet('tools', 'autoReconnect', false)

  local chkGold = p:recursiveGetChildById('chkChangeGold')
  local chkEat  = p:recursiveGetChildById('chkAutoEatFood')
  local chkRec  = p:recursiveGetChildById('chkAutoReconnect')
  if chkGold then chkGold:setChecked(BotHelper.Tools.config.changeGold) end
  if chkEat  then chkEat:setChecked(BotHelper.Tools.config.autoEat) end
  if chkRec  then chkRec:setChecked(BotHelper.Tools.config.autoReconnect) end
end

function BotHelper.Tools.syncFromUI()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('toolsPanel')
  if not p then return end

  local function syncChk(id, field1, field2)
    local w = p:recursiveGetChildById(id)
    if w then
      local v = w:isChecked()
      if field2 then BotHelper.Tools.config[field1][field2] = v else BotHelper.Tools.config[field1] = v end
      cfgSet('tools', (field2 and (field1..'.'..field2) or field1), v)
    end
  end

  local function syncSpn(id, field1, field2)
    local w = p:recursiveGetChildById(id)
    if w then
      local v = w:getValue()
      BotHelper.Tools.config[field1][field2] = v
      cfgSet('tools', field1..'.'..field2, v)
    end
  end

  syncChk('chkManaEnable', 'manaTrain', 'enabled')
  syncSpn('spinManaPct', 'manaTrain', 'pct')
  syncChk('chkExerciseEnable', 'exercise', 'enabled')
  syncChk('chkHasteEnable', 'haste', 'enabled')
  syncChk('chkHastePZ', 'haste', 'pz')
  syncChk('chkChangeGold', 'changeGold')
  syncChk('chkAutoEatFood', 'autoEat')
  syncChk('chkAutoReconnect', 'autoReconnect')
end

function BotHelper.startToolsEngine()
  BotHelper.stopToolsEngine()
  BotHelper.toolsCycle = cycleEvent(function()
    if not isTabEnabled('tools') then return end
    BotHelper.Tools.syncFromUI()
  end, 500)
end

function BotHelper.stopToolsEngine()
  if BotHelper.toolsCycle then
    removeEvent(BotHelper.toolsCycle)
    BotHelper.toolsCycle = nil
  end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- SUBSISTEMA: HEALING ENGINE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
BotHelper.Healing = {}
BotHelper.Healing.spells  = {}
BotHelper.Healing.potions = {}

local SPELL_COOLDOWN_HEAL  = 1000
local POTION_COOLDOWN_HEAL = 1000
local lastSpellTime   = 0
local lastPotionTime  = 0

function BotHelper.Healing.loadConfigToUI()
  if not BotHelper.window then return end
  local section = BotHelper.window:recursiveGetChildById('sectionAutoHeal')
  if not section then return end

  local leftCol  = section:getChildById('autoHealLeft')
  local rightCol = section:getChildById('autoHealRight')

  local defaultSpellPcts = {80, 60, 40}
  for i = 1, 3 do
    BotHelper.Healing.spells[i] = {
      text = cfgGet('healing', 'spell' .. i .. '.text', ''),
      pct  = cfgGet('healing', 'spell' .. i .. '.pct',  defaultSpellPcts[i]),
      icon = cfgGet('healing', 'spell' .. i .. '.icon', 0),
    }
    if leftCol then
      local row  = leftCol:getChildById('rowSpellHeal' .. i)
      local icon = row  and row:getChildById('iconSpellHeal' .. i)
      local spin = row  and row:getChildById('spinSpellHeal' .. i)
      if spin then spin:setValue(BotHelper.Healing.spells[i].pct) end
      if icon then
        BotHelper.Healing.updateSpellSlotLabel(icon, BotHelper.Healing.spells[i].text, BotHelper.Healing.spells[i].icon)
      end
    end
  end

  local defaultPotionPcts = {60, 30, 30}
  for i = 1, 3 do
    BotHelper.Healing.potions[i] = {
      itemId = cfgGet('healing', 'potion' .. i .. '.itemId', 0),
      pct    = cfgGet('healing', 'potion' .. i .. '.pct',    defaultPotionPcts[i]),
      isMana = (i == 3),
    }
    if rightCol then
      local row    = rightCol:getChildById('rowPotionHeal' .. i)
      local btn    = row and row:getChildById('iconPotionHeal' .. i)
      local uiItem = btn and btn:getChildById('potionItem')
      local spin   = row and row:getChildById('spinPotionHeal' .. i)
      if spin then spin:setValue(BotHelper.Healing.potions[i].pct) end
      if uiItem then
        uiItem:setItemId(BotHelper.Healing.potions[i].itemId > 100 and BotHelper.Healing.potions[i].itemId or 0)
      end
    end
  end
end

function BotHelper.Healing.syncFromUI()
  if not BotHelper.window then return end
  local section = BotHelper.window:recursiveGetChildById('sectionAutoHeal')
  if not section then return end

  local leftCol  = section:getChildById('autoHealLeft')
  local rightCol = section:getChildById('autoHealRight')

  for i = 1, 3 do
    if leftCol then
      local row  = leftCol:getChildById('rowSpellHeal' .. i)
      local spin = row and row:getChildById('spinSpellHeal' .. i)
      if spin and BotHelper.Healing.spells[i] then
        local v = spin:getValue()
        BotHelper.Healing.spells[i].pct = v
        cfgSet('healing', 'spell' .. i .. '.pct', v)
      end
    end
    if rightCol then
      local row  = rightCol:getChildById('rowPotionHeal' .. i)
      local spin = row and row:getChildById('spinPotionHeal' .. i)
      if spin and BotHelper.Healing.potions[i] then
        local v = spin:getValue()
        BotHelper.Healing.potions[i].pct = v
        cfgSet('healing', 'potion' .. i .. '.pct', v)
      end
    end
  end

  if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
end

function BotHelper.Healing.process(now, player)
  if not isTabEnabled('healing') then return end

  local hpPct   = player:getHealthPercent()
  local manaPct = 100
  local maxMana = player:getMaxMana()
  if maxMana > 1 then manaPct = math.floor(player:getMana() * 100 / maxMana) end

  BotHelper.Healing.syncFromUI()

  -- SPELLS
  if now >= lastSpellTime + SPELL_COOLDOWN_HEAL then
    local bestSlot, bestPct = nil, 101
    for i = 1, 3 do
      local s = BotHelper.Healing.spells[i]
      if s and s.text and s.text ~= '' then
        if hpPct <= s.pct and s.pct < bestPct then
          bestSlot, bestPct = i, s.pct
        end
      end
    end
    if bestSlot then
      local words = BotHelper.Healing.spells[bestSlot].text
      if g_game.castSpell then g_game.castSpell(words) else g_game.talk(words) end
      lastSpellTime = now
      BotHelper.nextGlobalAttack = math.max(BotHelper.nextGlobalAttack or 0, now + 10)
    end
  end

  -- POTIONS
  if now >= lastPotionTime + POTION_COOLDOWN_HEAL then
    local bestHPSlot, bestHPPct = nil, 101
    for i = 1, 2 do
      local p = BotHelper.Healing.potions[i]
      if p and p.itemId and p.itemId > 100 then
        if hpPct <= p.pct and p.pct < bestHPPct then
          bestHPSlot, bestHPPct = i, p.pct
        end
      end
    end

    if bestHPSlot then
      g_game.useInventoryItemWith(BotHelper.Healing.potions[bestHPSlot].itemId, player)
      lastPotionTime = now
    else
      local mp = BotHelper.Healing.potions[3]
      if mp and mp.itemId and mp.itemId > 100 then
        if manaPct <= mp.pct then
          g_game.useInventoryItemWith(mp.itemId, player)
          lastPotionTime = now
        end
      end
    end
  end
end

function BotHelper.startHealingEngine()
  lastSpellTime = 0
  lastPotionTime = 0
end

function BotHelper.stopHealingEngine() end

function BotHelper.Healing.spellSlotMenu(iconWidget, slotIndex)
  local slot = BotHelper.Healing.spells[slotIndex]
  if not slot then return end

  local menu = g_ui.createWidget('PopupMenu')
  menu:addOption('Assign Spell', function() BotHelper.Healing.showSpellSelector(slotIndex) end)
  menu:addSeparator()
  menu:addOption('Edit Spell', function() BotHelper.Healing.requestSpellText(iconWidget, slotIndex) end)
  menu:addSeparator()
  menu:addOption('Clear Action', function()
    BotHelper.Healing.spells[slotIndex].text = ''
    BotHelper.Healing.spells[slotIndex].icon = 0
    cfgSet('healing', 'spell' .. slotIndex .. '.text', '')
    cfgSet('healing', 'spell' .. slotIndex .. '.icon', 0)
    BotHelper.Healing.updateSpellSlotLabel(iconWidget, '', 0)
    if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
  end)
  menu:display(iconWidget:getPosition())
end

function BotHelper.Healing.showSpellSelector(slotIndex)
  if not BotHelper.window then return end
  local player = g_game.getLocalPlayer()
  if not player then return end

  local modal = g_ui.displayUI('bothelper_spellselector', modules.game_interface.getRootPanel())
  if not modal then return end
  modal:raise(); modal:focus()

  local btnCancel = modal:getChildById('buttonCancel')
  if btnCancel then btnCancel.onClick = function() modal:destroy() end end

  local spellListGrid = modal:getChildById('spellList')
  if not spellListGrid then return end

  local spellsTbl = (_G.SpellInfo and _G.SpellInfo['Default']) or (modules.gamelib and modules.gamelib.SpellInfo and modules.gamelib.SpellInfo['Default'])
  if not spellsTbl then return end

  local translateVoc = _G.translateVocation or function(v) return v end
  local myVoc = translateVoc(player:getVocation())

  for spellName, info in pairs(spellsTbl) do
    local isHealing = false
    if info.group and (info.group[2] or info.group["Healing"]) then isHealing = true end

    local hasVocation = (myVoc == 0) or (info.vocations and table_contains(info.vocations, myVoc))
    if isHealing and hasVocation then
      local btn = g_ui.createWidget('BotHelperSpellSelectorItem', spellListGrid)
      btn:setText(spellName .. '\n"' .. info.words .. '"')
      local iconId = tonumber(info.clientId) or 0
      if iconId == 0 and string.lower(info.words) == "exura vita" then iconId = 1 end

      if iconId > 0 and Spells and Spells.getImageClip then
        local spellIcon = btn:getChildById('spellIcon')
        if spellIcon then
          spellIcon:setImageSource('/images/game/spells/spell-icons-32x32')
          spellIcon:setImageClip(torect(Spells.getImageClip(iconId, 'Default')))
        end
      end

      btn.onClick = function()
        BotHelper.Healing.spells[slotIndex].text = info.words
        BotHelper.Healing.spells[slotIndex].icon = iconId
        cfgSet('healing', 'spell' .. slotIndex .. '.text', info.words)
        cfgSet('healing', 'spell' .. slotIndex .. '.icon', iconId)
        local icon = BotHelper.window:recursiveGetChildById('iconSpellHeal' .. slotIndex)
        BotHelper.Healing.updateSpellSlotLabel(icon, info.words, iconId)
        modal:destroy()
      end
    end
  end
end

function BotHelper.Healing.requestSpellText(iconWidget, slotIndex)
  local current = BotHelper.Healing.spells[slotIndex].text or ''
  if type(displayInputBox) == 'function' then
    displayInputBox('Spell Slot ' .. slotIndex, 'Texto da magia:', function(text)
      if text and text:len() > 0 then
        local iconId = 0
        if string.lower(text) == "exura vita" then iconId = 1 end
        BotHelper.Healing.spells[slotIndex].text = text
        BotHelper.Healing.spells[slotIndex].icon = iconId
        cfgSet('healing', 'spell' .. slotIndex .. '.text', text)
        cfgSet('healing', 'spell' .. slotIndex .. '.icon', iconId)
        BotHelper.Healing.updateSpellSlotLabel(iconWidget, text, iconId)
        if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
      end
    end, nil, current)
  end
end

function BotHelper.Healing.updateSpellSlotLabel(iconWidget, text, iconId)
  if not iconWidget then return end
  local spellIcon = iconWidget:getChildById('spellIcon')
  local lbl = iconWidget:getChildById('slotPreviewLabel')
  if not spellIcon or not lbl then return end

  if iconId > 0 and Spells and Spells.getImageClip then
    spellIcon:setImageSource('/images/game/spells/spell-icons-32x32')
    spellIcon:setImageClip(torect(Spells.getImageClip(iconId, 'Default')))
    lbl:setText('')
  else
    spellIcon:setImageSource('')
    lbl:setText((text ~= nil and text ~= '') and text:sub(1, 5):upper() or '')
  end
end

function BotHelper.Healing.potionSlotMenu(btnWidget, slotIndex)
  local menu = g_ui.createWidget('PopupMenu')
  menu:addOption('Assign Object', function() BotHelper.Healing.assignPotionEvent(slotIndex, btnWidget) end)
  menu:addSeparator()
  menu:addOption('Clear Object', function()
    BotHelper.Healing.potions[slotIndex].itemId = 0
    cfgSet('healing', 'potion' .. slotIndex .. '.itemId', 0)
    local uiItem = btnWidget:getChildById('potionItem')
    if uiItem then uiItem:setItemId(0) end
    if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
  end)
  menu:display(g_window.getMousePosition())
end

function BotHelper.Healing.assignPotionEvent(slotIndex, btnWidget)
  if not mouseGrabberWidget then
    mouseGrabberWidget = g_ui.createWidget('UIWidget')
    mouseGrabberWidget:setVisible(false); mouseGrabberWidget:setFocusable(false)
  end
  mouseGrabberWidget:grabMouse()
  if modules.client_options and modules.client_options.getOption('nativeCursor') then g_window.setSystemCursor('cross') else g_mouse.pushCursor('target') end
  mouseGrabberWidget.onMouseRelease = function(self, mousePos, mouseButton)
    mouseGrabberWidget:ungrabMouse()
    if modules.client_options and modules.client_options.getOption('nativeCursor') then g_window.restoreMouseCursor() else g_mouse.popCursor('target') end
    if mouseButton ~= MouseLeftButton then return true end

    local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePos, false)
    if not clickedWidget then return true end

    local itemId = 0
    if clickedWidget:getClassName() == 'UIItem' and clickedWidget:getItem() then itemId = clickedWidget:getItem():getId()
    elseif clickedWidget:getClassName() == 'UIGameMap' then
      local tile = clickedWidget:getTile(mousePos)
      if tile and tile:getTopUseThing() then itemId = tile:getTopUseThing():getId() end
    end

    if itemId > 100 then
      BotHelper.Healing.potions[slotIndex].itemId = itemId
      cfgSet('healing', 'potion' .. slotIndex .. '.itemId', itemId)
      local uiItem = btnWidget:getChildById('potionItem')
      if uiItem then uiItem:setItemId(itemId) end
      if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
    end
    return true
  end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- SUBSISTEMA: SPELLCASTER ENGINE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
BotHelper.SpellCaster = {}
BotHelper.SpellCaster.spells = {}
for i=1,5 do BotHelper.SpellCaster.spells[i] = { text = '', icon = 0, manaPct = 90, creatures = '1+', priority = '1st' } end
BotHelper.SpellCaster.autoTargetMode = 'A'
BotHelper.SpellCaster.shooterEnabled = false

function BotHelper.SpellCaster.setupComboBoxes()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('casterPanel')
  if not p then return end

  local creaturesOpts = {'1+', '2+', '3+', '4+', '5+'}
  local priorityOpts  = {'1st', '2nd', '3rd', '4th', '5th'}
  local targetModes   = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'}

  for i = 1, 5 do
    local cmbC = p:recursiveGetChildById('cmbCreatures' .. i)
    local cmbP = p:recursiveGetChildById('cmbPriority' .. i)
    if cmbC then for _, opt in ipairs(creaturesOpts) do cmbC:addOption(opt) end end
    if cmbP then for _, opt in ipairs(priorityOpts) do cmbP:addOption(opt) end end
  end
  local cmbTarget = p:recursiveGetChildById('cmbAutoTargetMode')
  if cmbTarget then for _, opt in ipairs(targetModes) do cmbTarget:addOption(opt) end end
end

function BotHelper.SpellCaster.loadConfigToUI()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('casterPanel')
  if not p then return end

  BotHelper.SpellCaster.autoTargetMode = cfgGet('caster', 'autoTargetMode', 'A')
  local cmbTarget = p:recursiveGetChildById('cmbAutoTargetMode')
  if cmbTarget then cmbTarget:setCurrentOption(BotHelper.SpellCaster.autoTargetMode) end

  BotHelper.SpellCaster.shooterEnabled = cfgGet('caster', 'shooterEnabled', false)
  local chkShooter = p:recursiveGetChildById('chkEnableShooter')
  if chkShooter then chkShooter:setChecked(BotHelper.SpellCaster.shooterEnabled) end

  for i = 1, 5 do
    BotHelper.SpellCaster.spells[i].text      = cfgGet('caster', 'spell'..i..'.text', '')
    BotHelper.SpellCaster.spells[i].icon      = cfgGet('caster', 'spell'..i..'.icon', 0)
    BotHelper.SpellCaster.spells[i].manaPct   = cfgGet('caster', 'spell'..i..'.manaPct', 80)
    BotHelper.SpellCaster.spells[i].creatures = cfgGet('caster', 'spell'..i..'.creatures', '1+')
    BotHelper.SpellCaster.spells[i].priority  = cfgGet('caster', 'spell'..i..'.priority', '1st')

    local icon = p:recursiveGetChildById('iconSpellCaster' .. i)
    local spin = p:recursiveGetChildById('spinSpellMana' .. i)
    local cmbC = p:recursiveGetChildById('cmbCreatures' .. i)
    local cmbP = p:recursiveGetChildById('cmbPriority' .. i)

    if spin then spin:setValue(BotHelper.SpellCaster.spells[i].manaPct) end
    if icon then BotHelper.Healing.updateSpellSlotLabel(icon, BotHelper.SpellCaster.spells[i].text, BotHelper.SpellCaster.spells[i].icon) end
    if cmbC then cmbC:setCurrentOption(BotHelper.SpellCaster.spells[i].creatures) end
    if cmbP then cmbP:setCurrentOption(BotHelper.SpellCaster.spells[i].priority) end
  end
end

function BotHelper.SpellCaster.syncFromUI()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('casterPanel')
  if not p then return end

  local cmbTarget = p:recursiveGetChildById('cmbAutoTargetMode')
  if cmbTarget then
    local v = cmbTarget:getCurrentOption().text
    BotHelper.SpellCaster.autoTargetMode = v
    cfgSet('caster', 'autoTargetMode', v)
  end

  local chkShooter = p:recursiveGetChildById('chkEnableShooter')
  if chkShooter then
    BotHelper.SpellCaster.shooterEnabled = chkShooter:isChecked()
    cfgSet('caster', 'shooterEnabled', BotHelper.SpellCaster.shooterEnabled)
  end

  for i = 1, 5 do
    local spin = p:recursiveGetChildById('spinSpellMana' .. i)
    local cmbC = p:recursiveGetChildById('cmbCreatures' .. i)
    local cmbP = p:recursiveGetChildById('cmbPriority' .. i)
    if spin then
      local v = spin:getValue()
      BotHelper.SpellCaster.spells[i].manaPct = v
      cfgSet('caster', 'spell'..i..'.manaPct', v)
    end
    if cmbC then
      local v = cmbC:getCurrentOption().text
      BotHelper.SpellCaster.spells[i].creatures = v
      cfgSet('caster', 'spell'..i..'.creatures', v)
    end
    if cmbP then
      local v = cmbP:getCurrentOption().text
      BotHelper.SpellCaster.spells[i].priority = v
      cfgSet('caster', 'spell'..i..'.priority', v)
    end
  end
  if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
end

function BotHelper.SpellCaster.spellSlotMenu(iconWidget, slotIndex)
  local menu = g_ui.createWidget('PopupMenu')
  menu:addOption('Assign Spell', function() BotHelper.SpellCaster.requestSpellText(iconWidget, slotIndex) end)
  menu:addSeparator()
  menu:addOption('Clear Action', function()
    BotHelper.SpellCaster.spells[slotIndex].text = ''
    BotHelper.SpellCaster.spells[slotIndex].icon = 0
    cfgSet('caster', 'spell' .. slotIndex .. '.text', '')
    cfgSet('caster', 'spell' .. slotIndex .. '.icon', 0)
    BotHelper.Healing.updateSpellSlotLabel(iconWidget, '', 0)
    if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
  end)
  menu:display(iconWidget:getPosition())
end

function BotHelper.SpellCaster.requestSpellText(iconWidget, slotIndex)
  local current = BotHelper.SpellCaster.spells[slotIndex].text or ''
  if type(displayInputBox) == 'function' then
    displayInputBox('Caster Slot ' .. slotIndex, 'Texto da magia:', function(text)
      if text and text:len() > 0 then
        local iconId = 0
        if Spells and type(Spells.getSpellDataByParamWords) == 'function' then
          local parsedParsed = Spells.getSpellDataByParamWords(text:lower())
          if parsedParsed and parsedParsed.clientId then iconId = parsedParsed.clientId end
        end
        BotHelper.SpellCaster.spells[slotIndex].text = text
        BotHelper.SpellCaster.spells[slotIndex].icon = iconId
        cfgSet('caster', 'spell' .. slotIndex .. '.text', text)
        cfgSet('caster', 'spell' .. slotIndex .. '.icon', iconId)
        BotHelper.Healing.updateSpellSlotLabel(iconWidget, text, iconId)
        if BOT_USE_CPP_SCHEDULER then BotHelper.syncScheduler() end
      end
    end, nil, current)
  end
end

function BotHelper.SpellCaster.process(now, player)
  if not isTabEnabled('caster') or not BotHelper.SpellCaster.shooterEnabled then return end
  if now < (BotHelper.nextGlobalAttack or 0) then return end

  local activeSpells = {}
  for i = 1, 5 do
    local s = BotHelper.SpellCaster.spells[i]
    if s and type(s.text) == 'string' and s.text ~= '' then
      table.insert(activeSpells, {
        priorityValue = tonumber(s.priority:match('%d+')) or i,
        words = s.text,
        manaPct = s.manaPct or 80,
        requiredCreatures = tonumber((s.creatures or '1+'):match('%d+')) or 1,
      })
    end
  end
  if #activeSpells == 0 then return end

  table.sort(activeSpells, function(a, b) return a.priorityValue < b.priorityValue end)

  local maxMana = player:getMaxMana()
  local manaPct = (maxMana > 0) and math.floor(player:getMana() * 100 / maxMana) or 0
  local playerPos = player:getPosition()
  local playerDir = player:getDirection()

  for _, spellCfg in ipairs(activeSpells) do
    local normWords = normalizeSpellWords(spellCfg.words)
    if normWords ~= '' and manaPct >= spellCfg.manaPct then
      local matrix = SpellAreaMatrices[normWords]
      local hitCount = 0
      if matrix and g_map.getEnemiesInArea then
        hitCount = g_map.getEnemiesInArea(matrix, playerPos, playerDir)
      else
        hitCount = 1 -- fallback single target
      end

      if hitCount >= spellCfg.requiredCreatures then
        if g_game.castSpell then g_game.castSpell(spellCfg.words) else g_game.talk(spellCfg.words) end
        BotHelper.nextGlobalAttack = now + 2000 -- GCD Attack
        break
      end
    end
  end
end

function BotHelper.startCasterEngine()
  BotHelper.casterSyncCycle = cycleEvent(function()
    if not isTabEnabled('caster') then return end
    BotHelper.SpellCaster.syncFromUI()
  end, 500)
end

function BotHelper.stopCasterEngine()
  if BotHelper.casterSyncCycle then removeEvent(BotHelper.casterSyncCycle); BotHelper.casterSyncCycle = nil end
end

-- =============================================================
-- UNIFIED MASTER CYCLE & C++ BRIDGE
-- =============================================================
function BotHelper.startBotEngine()
  if BOT_USE_CPP_SCHEDULER then g_botScheduler:start(); BotHelper.syncScheduler() else g_botScheduler:stop() end
  BotHelper.mainBotCycle = cycleEvent(function()
    local player = g_game.getLocalPlayer()
    if not player then return end
    if BOT_USE_CPP_SCHEDULER then return end
    local now = g_clock.millis()
    BotHelper.Healing.process(now, player)
    BotHelper.SpellCaster.process(now, player)
  end, 50)
end

function BotHelper.stopBotEngine()
  g_botScheduler:stop()
  if BotHelper.mainBotCycle then removeEvent(BotHelper.mainBotCycle); BotHelper.mainBotCycle = nil end
end

function BotHelper.syncScheduler()
  if not g_game.isOnline() or not g_botScheduler then return end
  
  -- Limpeza prÃ©via no motor nativo
  g_botScheduler:clearSpells()
  g_botScheduler:clearHeals()
  g_botScheduler:clearPotions()

  local function safeInt(val, default)
    local n = tonumber(val)
    if not n then return default or 0 end
    return math.floor(n)
  end

  -- 1. HEALING SPELLS
  for i = 1, 3 do
    local s = BotHelper.Healing.spells[i]
    if s and s.text and s.text ~= '' then
      local pct = safeInt(s.pct, 0)
      -- DEBUG: print(string.format("[BotSync] Heal Spell %d: '%s' | %%: %d (%s)", i, s.text, pct, type(pct)))
      g_botScheduler:addHeal(tostring(s.text), pct, 0, 1000)
    end
  end

  -- 2. POTIONS
  for i = 1, 3 do
    local p = BotHelper.Healing.potions[i]
    if p and p.itemId and p.itemId > 100 then
      local itemId = safeInt(p.itemId, 0)
      local pct    = safeInt(p.pct, 0)
      if i <= 2 then 
        g_botScheduler:addPotion(itemId, pct, 0, 1000) 
      else 
        g_botScheduler:addPotion(itemId, 0, pct, 1000) 
      end
    end
  end

  -- 3. ATTACK SPELLS
  for i = 1, 5 do
    local s = BotHelper.SpellCaster.spells[i]
    if s and s.text and s.text ~= '' then
      local norm = normalizeSpellWords(s.text)
      local area = SpellAreaMatrices[norm] or {}
      local minC = tonumber(tostring(s.creatures):match('%d+')) or 1
      local mana = safeInt(s.manaPct, 80)
      
      g_botScheduler:addSpell(tostring(s.text), mana, 1000, math.floor(minC), area)
    end
  end
end
