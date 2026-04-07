--[[
  ==============================================================
  [ BOT HELPER ÔÇö v3.1 ]
  Abas: tools | healing | caster
  Fases: Motor de Cura, UIItem, Tooltips, Status toggle por aba
  ==============================================================
]]

BOT_USE_CPP_SCHEDULER = false
local SpellAreaMatrices = {}

BotHelper = {}
BotHelper.lastHealTime = 0

-- === REFER├èNCIAS DE MEM├ôRIA ===
BotHelper.window        = nil
BotHelper.topMenuButton = nil
BotHelper.currentTab    = 'tools'
BotHelper.healingCycle  = nil
BotHelper.keyCapturing  = nil
BotHelper._hotkeyHandler = nil  -- handler persistente de hotkeys no rootWidget
BotHelper._pzHandler    = nil  -- handler de estados do jogador para detectar PZ

-- === HELPERS LOCAIS ===
local function table_contains(table, element)
  for _, value in pairs(table) do
    if value == element then return true end
  end
  return false
end

-- =============================================================
-- MAPEAMENTO CAN├öNICO DAS ABAS
-- =============================================================
BotHelper.TAB_MAP = {
  tools   = { btn = 'tabTools',   panel = 'toolsPanel',   scrollbar = 'toolsScrollBar',   label = 'Tools Helper'   },
  healing = { btn = 'tabHealing', panel = 'healingPanel', scrollbar = 'healingScrollBar', label = 'Healing Helper' },
  caster  = { btn = 'tabCaster',  panel = 'casterPanel',  scrollbar = 'casterScrollBar',  label = 'SpellCaster'    },
}

-- =============================================================
-- PERSIST├èNCIA ÔÇö g_settings (Per-Character)
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

function BotHelper.syncScheduler()
    if not BOT_USE_CPP_SCHEDULER then return end
    if not g_botScheduler then return end

    g_logger.info("[BotHelper] syncScheduler chamado - spells: " 
        .. #BotHelper.SpellCaster.spells 
        .. " heals: " .. #BotHelper.Healing.spells)

    g_botScheduler:clearSpells()
    g_botScheduler:clearHeals()
    g_botScheduler:clearPotions()

    -- Sincroniza magias de ataque
    for i, s in ipairs(BotHelper.SpellCaster.spells) do
        if s and s.text and s.text ~= "" then
            local area = SpellAreaMatrices[s.text:lower()] or {}
            g_botScheduler:addSpell(
                tostring(s.text),
                tonumber(s.manaPct) or 0,
                tonumber(s.creatures) or 1,
                tonumber(s.priority) or i,
                area
            )
        end
    end

    -- Sincroniza curas
    for i, s in ipairs(BotHelper.Healing.spells) do
        if s and s.text and s.text ~= "" then
            g_botScheduler:addHeal(
                tostring(s.text),
                tonumber(s.pct) or 100,
                0,
                1000
            )
        end
    end

    -- Sincroniza poções
    for i, p in ipairs(BotHelper.Healing.potions) do
        if p and p.itemId and tonumber(p.itemId) and tonumber(p.itemId) > 0 then
            g_botScheduler:addPotion(
                tonumber(p.itemId),
                tonumber(p.pct) or 100,
                0,
                1000
            )
        end
    end
end

-- =============================================================
-- CALLBACKS DE JOGO
-- =============================================================
function BotHelper.onGameStart()
  -- Quando o jogador entra, recarregamos as confs especificas dele para a UI e a memoria interna
  BotHelper.Tools.loadConfigToUI()
  BotHelper.Healing.loadConfigToUI()
  BotHelper.SpellCaster.loadConfigToUI()
  
  -- Retomada de Estado (Auto-Start)
  if isTabEnabled('tools')   then BotHelper.startToolsEngine()   else BotHelper.stopToolsEngine()   end
  if isTabEnabled('healing') then BotHelper.startHealingEngine() else BotHelper.stopHealingEngine() end
  if isTabEnabled('caster')  then BotHelper.startCasterEngine()  else BotHelper.stopCasterEngine()  end
  
  if BOT_USE_CPP_SCHEDULER then
    local anyEnabled = isTabEnabled('healing') or isTabEnabled('caster')
    if anyEnabled then
      g_botScheduler:start()
      BotHelper.syncScheduler()
    end
  end
  
  -- Atualiza o painel de rodape visivel
  BotHelper.refreshFooter()

  -- Conecta o guardiao de PZ ao state change do player
  local player = g_game.getLocalPlayer()
  if player then
    BotHelper._pzHandler = { onStatesChange = BotHelper.onPZStateChange }
    connect(player, BotHelper._pzHandler)
  end
end

function BotHelper.onGameEnd()
  BotHelper.stopToolsEngine()
  BotHelper.stopHealingEngine()
  BotHelper.stopCasterEngine()

  -- Desconecta o guardiao de PZ
  if BotHelper._pzHandler then
    local player = g_game.getLocalPlayer()
    if player then
      pcall(function() disconnect(player, BotHelper._pzHandler) end)
    end
    BotHelper._pzHandler = nil
  end

  if BOT_USE_CPP_SCHEDULER then
    g_botScheduler:stop()
  end
  -- Para sempre o Auto Target, independente da flag global
  if g_botScheduler then
    g_botScheduler:stopAutoTarget()
  end
  -- Em caso de deslogar, reverter UI para o estado "Default" limpo
  BotHelper.Tools.loadConfigToUI()
  BotHelper.Healing.loadConfigToUI()
  BotHelper.SpellCaster.loadConfigToUI()
end

-- =============================================================
-- HOOK: PROTECTION ZONE — Desativa SpellCaster ao entrar em PZ
-- Healing e Tools NAO sao afetados.
-- =============================================================
function BotHelper.onPZStateChange(player, now, old)
  local PZ_BIT = 16384 -- Valor absoluto para evitar erros de enum
  local wasInPZ = (bit.band(old, PZ_BIT) ~= 0)
  local isInPZ  = (bit.band(now, PZ_BIT) ~= 0)

  if isInPZ and not wasInPZ then -- Transicao OFF -> ON
    if isTabEnabled('caster') then
      cfgSet('caster', 'enabled', false)
      BotHelper.stopCasterEngine()
      if BotHelper.currentTab == 'caster' then BotHelper.refreshFooter() end
      BotHelper.showGameMessage("SpellCaster DESATIVADO em Zona de Prote" .. string.char(231) .. string.char(227) .. "o")
    end
  end
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

  -- === Tooltips via codigo (nao depende de tooltip: nativo) ===
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

  -- === Set Key do footer ===
  local footer = BotHelper.window:getChildById('botHelperFooter')
  if footer then
    local btnSetKey = footer:getChildById('btnSetKey')
    if btnSetKey then
      btnSetKey.onClick = function() BotHelper.captureHotkey(BotHelper.currentTab) end
    end
  end

  -- === Popula ComboBoxes do SpellCaster (uma vez, antes de carregar config) ===
  BotHelper.SpellCaster.setupComboBoxes()

  -- === Carrega config salva nos UIItems e SpinBoxes ===
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
-- FOOTER DINAMICO ÔÇö Status e hotkey por aba
-- =============================================================
function BotHelper.refreshFooter()
  if not BotHelper.window then return end
  local footer = BotHelper.window:getChildById('botHelperFooter')
  if not footer then return end

  local tab    = BotHelper.currentTab
  local isOn   = isTabEnabled(tab)
  local hotkey = cfgGet(tab, 'hotkey', '')

  -- Label de Status
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

  -- Botao Set Key: mostra tecla atual se definida
  local btnSetKey = footer:getChildById('btnSetKey')
  if btnSetKey then
    btnSetKey:setText(hotkey ~= '' and ('Key: ' .. hotkey) or 'Set Key')
  end
end

-- =============================================================
-- TOGGLE DE STATUS POR ABA ÔÇö @onClick do lblHelperStatusVal
-- =============================================================
function BotHelper.toggleTabStatus()
  local tab  = BotHelper.currentTab
  local isOn = isTabEnabled(tab)
  g_logger.info("[BotHelper] toggle chamado, tab=" .. tostring(tab) .. " isOn=" .. tostring(isOn))

  -- Inverte e salva imediatamente
  cfgSet(tab, 'enabled', not isOn)

  -- Inicia/para o motor de acordo com a aba ativada
  if tab == 'tools' then
    if not isOn then BotHelper.startToolsEngine() else BotHelper.stopToolsEngine() end
  elseif tab == 'healing' then
    if not isOn then BotHelper.startHealingEngine() else BotHelper.stopHealingEngine() end
  elseif tab == 'caster' then
    if not isOn then BotHelper.startCasterEngine() else BotHelper.stopCasterEngine() end
  end
  if BOT_USE_CPP_SCHEDULER then
    if not isOn then
        g_botScheduler:start()
        BotHelper.syncScheduler()
    else
        g_botScheduler:stop()
    end
  end

  -- Atualiza visual imediatamente
  BotHelper.refreshFooter()

  -- Feedback na tela
  local tabName  = BotHelper.TAB_MAP[tab] and BotHelper.TAB_MAP[tab].label or tab
  local stateStr = (not isOn) and 'ON' or 'OFF'
  BotHelper.showGameMessage(tabName .. ': ' .. stateStr)
end

-- =============================================================
-- CAPTURA DE HOTKEY
-- Armazena o keyCode como inteiro no g_settings ('hotkeyCode').
-- Nao usa g_keyboard.getKeyName (nao existe nesta build).
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

    -- Esc cancela
    if keyCode == KeyEscape then
      BotHelper.keyCapturing = nil
      BotHelper.showGameMessage('Captura cancelada.')
      disconnect(rootWidget, { onKeyDown = handler })
      return
    end

    -- Armazena o codigo inteiro da tecla
    local displayName = 'Key#' .. tostring(keyCode)
    local capturedTab = BotHelper.keyCapturing

    cfgSet(capturedTab, 'hotkeyCode', keyCode)
    cfgSet(capturedTab, 'hotkey',     displayName)  -- so para exibir no footer

    BotHelper.showGameMessage(
      'Atalho definido: ' .. displayName ..
      ' ÔåÆ ' .. (BotHelper.TAB_MAP[capturedTab] and BotHelper.TAB_MAP[capturedTab].label or capturedTab)
    )

    BotHelper.keyCapturing = nil
    disconnect(rootWidget, { onKeyDown = handler })
    BotHelper.refreshFooter()
    BotHelper.registerHotkeys()  -- atualiza handler global
  end

  connect(rootWidget, { onKeyDown = handler })

  -- Timeout de seguranca (10s)
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
-- Usa um unico handler onKeyDown no rootWidget, comparando
-- keyCodes inteiros gravados em g_settings ('hotkeyCode').
-- =============================================================
function BotHelper.registerHotkeys()
  -- Remove handler anterior para evitar duplicatas
  if BotHelper._hotkeyHandler then
    pcall(function() disconnect(rootWidget, { onKeyDown = BotHelper._hotkeyHandler }) end)
    BotHelper._hotkeyHandler = nil
  end

  -- Verifica se ha alguma hotkey configurada
  local hasAny = false
  for tabId, _ in pairs(BotHelper.TAB_MAP) do
    if cfgGet(tabId, 'hotkeyCode', 0) > 0 then
      hasAny = true
      break
    end
  end
  if not hasAny then return end

  -- Handler persistente: checa todos os keyCodes
  BotHelper._hotkeyHandler = function(widget, keyCode, keyMods)
    for tabId, _ in pairs(BotHelper.TAB_MAP) do
      local savedCode = cfgGet(tabId, 'hotkeyCode', 0)
      if savedCode > 0 and keyCode == savedCode then
        -- Toggle a aba correspondente sem alterar a aba atual permanentemente
        local prevTab = BotHelper.currentTab
        BotHelper.currentTab = tabId
        BotHelper.toggleTabStatus()
        if prevTab ~= tabId then
          BotHelper.currentTab = prevTab
          BotHelper.refreshFooter()
        end
        return  -- tecla consumida
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

-- ÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉ
-- SUBSISTEMA: TOOLS ENGINE
-- ÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉ
BotHelper.Tools = {}

-- Dados em memoria (sincronizados com g_settings + UI)
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
    -- Mecanica a vir via expansoes
  end, 500)
end

function BotHelper.stopToolsEngine()
  if BotHelper.toolsCycle then
    removeEvent(BotHelper.toolsCycle)
    BotHelper.toolsCycle = nil
  end
end

-- ÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉ
-- SUBSISTEMA: HEALING ENGINE
-- ÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉ
BotHelper.Healing = {}

-- Dados em memoria dos slots (sincronizados com g_settings + UI)
BotHelper.Healing.spells  = {}   -- {text='', pct=80}  ├ù 3
BotHelper.Healing.potions = {}   -- {itemId=0, pct=60, isMana=false} ├ù 3
BotHelper.lastHealTime = 0

-- Cooldowns (ms)
local SPELL_COOLDOWN  = 1050
local POTION_COOLDOWN = 500
local lastSpellTime   = 0
local lastPotionTime  = 0

-- =============================================================
-- Carrega g_settings ÔåÆ UI (UIItems + SpinBoxes)
-- =============================================================
function BotHelper.Healing.loadConfigToUI()
  if not BotHelper.window then return end

  local section = BotHelper.window:recursiveGetChildById('sectionAutoHeal')
  if not section then return end

  local leftCol  = section:getChildById('autoHealLeft')
  local rightCol = section:getChildById('autoHealRight')

  -- Spell slots
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

  -- Potion slots
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
        if BotHelper.Healing.potions[i].itemId > 100 then
          uiItem:setItemId(BotHelper.Healing.potions[i].itemId)
        else
          uiItem:setItemId(0)
        end
      end
    end
  end
end

-- =============================================================
-- Sincroniza SpinBoxes da UI -> memoria + g_settings
-- Chamado uma vez por ciclo do motor de cura
-- =============================================================
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
end

-- =============================================================
-- MOTOR DE CURA ÔÇö ciclo 150ms com cascata de prioridade
-- =============================================================
local SPELL_COOLDOWN  = 1050
local POTION_COOLDOWN = 1000
local lastSpellTime   = 0
local lastPotionTime  = 0

function BotHelper.startHealingEngine()
  BotHelper.stopHealingEngine()
  if BOT_USE_CPP_SCHEDULER then 
    g_logger.info("[BotHelper] startHealingEngine chamado, CPP=" .. tostring(BOT_USE_CPP_SCHEDULER))
    return 
  end

  BotHelper.healingCycle = cycleEvent(function()
    -- ÔòÉÔòÉ GUARDA-PORT├âO ABSOLUTO ÔòÉÔòÉ
    if not isTabEnabled('healing') then return end

    local player = g_game.getLocalPlayer()
    if not player then return end

    local hpPct   = player:getHealthPercent()
    local manaPct = 100
    local maxMana = player:getMaxMana()
    if maxMana > 1 then
      manaPct = math.floor(player:getMana() * 100 / maxMana)
    end

    local now = g_clock.millis()

    -- Sincroniza SpinBoxes -> memoria
    BotHelper.Healing.syncFromUI()

    -- ÔöÇÔöÇ SPELLS (cascata: menor pct configurado que foi atingido) ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ
    if now >= lastSpellTime + SPELL_COOLDOWN then
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
        g_game.talk(BotHelper.Healing.spells[bestSlot].text)
        lastSpellTime = now
        BotHelper.lastHealTime = now -- Sincroniza com motor de ataque
      end
    end

    -- ÔöÇÔöÇ POTIONS ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ
    if now >= lastPotionTime + POTION_COOLDOWN then
      -- HP Potions (slots 1 e 2)
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
        -- Mana Potion (slot 3)
        local mp = BotHelper.Healing.potions[3]
        if mp and mp.itemId and mp.itemId > 100 then
          if manaPct <= mp.pct then
            g_game.useInventoryItemWith(mp.itemId, player)
            lastPotionTime = now
          end
        end
      end
    end
  end, 150)
end

function BotHelper.stopHealingEngine()
  if BotHelper.healingCycle then
    removeEvent(BotHelper.healingCycle)
    BotHelper.healingCycle = nil
  end
end

-- =============================================================
-- CONTEXT MENU ÔÇö SPELL SLOTS (direito no icone)
-- =============================================================
function BotHelper.Healing.spellSlotMenu(iconWidget, slotIndex)
  local slot = BotHelper.Healing.spells[slotIndex]
  if not slot then return end

  local menu = g_ui.createWidget('PopupMenu')

  menu:addOption('Assign Spell', function()
    BotHelper.Healing.showSpellSelector(slotIndex)
  end)

  menu:addSeparator()

  menu:addOption('Edit Spell', function()
    BotHelper.Healing.requestSpellText(iconWidget, slotIndex)
  end)

  menu:addSeparator()

  menu:addOption('Clear Action', function()
    BotHelper.Healing.spells[slotIndex].text = ''
    BotHelper.Healing.spells[slotIndex].icon = 0
    cfgSet('healing', 'spell' .. slotIndex .. '.text', '')
    cfgSet('healing', 'spell' .. slotIndex .. '.icon', 0)
    BotHelper.Healing.updateSpellSlotLabel(iconWidget, '', 0)
  end)

  menu:display(iconWidget:getPosition())
end

-- Janela visual Modal de Selecao
function BotHelper.Healing.showSpellSelector(slotIndex)
  if not BotHelper.window then return end
  local player = g_game.getLocalPlayer()
  if not player then return end

  local otuiPath = 'bothelper_spellselector'
  local modal = g_ui.displayUI(otuiPath, modules.game_interface.getRootPanel())
  if not modal then return end

  modal:raise()
  modal:focus()

  local btnCancel = modal:getChildById('buttonCancel')
  if btnCancel then
      btnCancel.onClick = function() modal:destroy() end
  end

  local spellListGrid = modal:getChildById('spellList')
  if not spellListGrid then return end

  local spellsTbl = nil
  if _G.SpellInfo and _G.SpellInfo['Default'] then
      spellsTbl = _G.SpellInfo['Default']
  elseif modules.gamelib and modules.gamelib.SpellInfo then
      spellsTbl = modules.gamelib.SpellInfo['Default']
  end

  if not spellsTbl then
      print("[BotHelper] ERRO: Tabela SpellInfo nao encontrada do Client!")
      return
  end

  local translateVoc = _G.translateVocation or function(v) return v end
  local myVoc = translateVoc(player:getVocation())

  local function isBlacklisted(words)
      if not words then return false end
      local w = string.lower(words)
      return string.find(w, "utura") or string.find(w, "exana")
  end

  for spellName, info in pairs(spellsTbl) do
      -- Grupo 2 = Healing
      local isHealing = false
      if info.group and (info.group[2] or info.group["Healing"]) then
          isHealing = true
      elseif Spells and Spells.getPrimaryGroup then
          isHealing = (Spells.getPrimaryGroup(info) == 2)
      end

      local hasVocation = (myVoc == 0) or (info.vocations and table_contains(info.vocations, myVoc))
      local valid = isHealing and not isBlacklisted(info.words)

      if valid and hasVocation then
          local btn = g_ui.createWidget('BotHelperSpellSelectorItem', spellListGrid)
          btn:setText(spellName .. '\n"' .. info.words .. '"')
          
          local iconId = tonumber(info.clientId) or 0
          
          -- Patch para o Exura Vita Nulo
          if iconId == 0 and string.lower(info.words) == "exura vita" then
              iconId = 1
          end

          if iconId > 0 and Spells and Spells.getImageClip then
              local iconClip = Spells.getImageClip(iconId, 'Default')
              local spellIcon = btn:getChildById('spellIcon')
              if spellIcon then
                  spellIcon:setImageSource('/images/game/spells/spell-icons-32x32')
                  spellIcon:setImageClip(torect(iconClip))
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

-- Solicita texto customizado (fallback)
function BotHelper.Healing.requestSpellText(iconWidget, slotIndex)
  local current = BotHelper.Healing.spells[slotIndex].text or ''

  if type(displayInputBox) == 'function' then
    displayInputBox(
      'Spell Slot ' .. slotIndex,
      'Digite o texto da magia (ex: exura gran):',
      function(text)
        if text and text:len() > 0 then
          local iconId = 0
          local parsedSpell = nil
          if Spells and type(Spells.getSpellDataByParamWords) == 'function' then
              parsedSpell, _ = Spells.getSpellDataByParamWords(text:lower())
              if parsedSpell and parsedSpell.clientId then
                  iconId = parsedSpell.clientId
              end
          end

          local function isBlacklisted(words)
              if not words then return false end
              local w = string.lower(words)
              return string.find(w, "utura") or string.find(w, "exana")
          end

          -- Trava Rigida de Autenticidade
          if parsedSpell then
              local isHealing = false
              if parsedSpell.group and (parsedSpell.group[2] or parsedSpell.group["Healing"]) then
                  isHealing = true
              elseif Spells and Spells.getPrimaryGroup then
                  isHealing = (Spells.getPrimaryGroup(parsedSpell) == 2)
              end

              if not isHealing or isBlacklisted(text) then
                  if modules.game_textmessage then
                      modules.game_textmessage.displayFailureMessage("Erro: Apenas magias de cura instantanea sao permitidas.")
                  end
                  return
              end
          else
              -- Magia Generica / Desconhecida no DB Client
              if isBlacklisted(text) then
                  if modules.game_textmessage then
                      modules.game_textmessage.displayFailureMessage("Erro: Apenas magias de cura instantanea sao permitidas.")
                  end
                  return
              end
          end

          -- Fallback Patch para Exura Vita Nulo
          if string.lower(text) == "exura vita" and iconId == 0 then
              iconId = 1
          end

          BotHelper.Healing.spells[slotIndex].text = text
          BotHelper.Healing.spells[slotIndex].icon = iconId
          cfgSet('healing', 'spell' .. slotIndex .. '.text', text)
          cfgSet('healing', 'spell' .. slotIndex .. '.icon', iconId)
          BotHelper.Healing.updateSpellSlotLabel(iconWidget, text, iconId)
        end
      end,
      nil,
      current
    )
  else
    print('[BotHelper] Use: BotHelper.Healing.setSpell(' .. slotIndex .. ', "sua_magia")')
  end
end

-- API publica (custom script access)
function BotHelper.Healing.setSpell(slotIndex, text, iconId)
  if slotIndex < 1 or slotIndex > 3 then return end
  iconId = iconId or 0
  BotHelper.Healing.spells[slotIndex].text = text
  BotHelper.Healing.spells[slotIndex].icon = iconId
  cfgSet('healing', 'spell' .. slotIndex .. '.text', text)
  cfgSet('healing', 'spell' .. slotIndex .. '.icon', iconId)
  
  if BotHelper.window then
    local icon = BotHelper.window:recursiveGetChildById('iconSpellHeal' .. slotIndex)
    if icon then BotHelper.Healing.updateSpellSlotLabel(icon, text, iconId) end
  end
end

function BotHelper.Healing.updateSpellSlotLabel(iconWidget, text, iconId)
  if not iconWidget then return end
  iconId = tonumber(iconId) or 0

  local spellIcon = iconWidget:getChildById('spellIcon')
  local lbl = iconWidget:getChildById('slotPreviewLabel')
  if not spellIcon or not lbl then return end

  if iconId > 0 and Spells and Spells.getImageClip then
      spellIcon:setImageSource('/images/game/spells/spell-icons-32x32')
      spellIcon:setImageClip(torect(Spells.getImageClip(iconId, 'Default')))
      lbl:setText('')
  else
      spellIcon:setImageSource('')
      spellIcon:setImageClip(torect('0 0 0 0'))
      
      local preview = (text ~= nil and text ~= '') and text:sub(1, 5):upper() or ''
      lbl:setText(preview)
  end
end

-- =============================================================
-- CONTEXT MENU ÔÇö POTION SLOTS (direito no UIItem)
-- =============================================================

-- IDs de pocoes conhecidos para validacao unificada (HP / Mana / Spirit)
local allowedPotions = {
  266, 236, 239, 7643, 23375, -- Vida
  268, 237, 238, 23373,       -- Mana
  7642, 23374                 -- Spirit
}

local function isAllowedPotion(itemId)
  if type(table.contains) == 'function' then
    return table.contains(allowedPotions, itemId)
  else
    for _, id in ipairs(allowedPotions) do
      if id == itemId then return true end
    end
    return false
  end
end

function BotHelper.Healing.potionSlotMenu(btnWidget, slotIndex)
  local slot = BotHelper.Healing.potions[slotIndex]
  if not slot then return end

  local menu = g_ui.createWidget('PopupMenu')

  menu:addOption('Assign Object', function()
    BotHelper.Healing.assignPotionEvent(slotIndex, btnWidget)
  end)

  menu:addSeparator()

  menu:addOption('Clear Object', function()
    BotHelper.Healing.potions[slotIndex].itemId = 0
    cfgSet('healing', 'potion' .. slotIndex .. '.itemId', 0)
    local uiItem = btnWidget:getChildById('potionItem')
    if uiItem then uiItem:setItemId(0) end
  end)

  menu:display(g_window.getMousePosition())
end

-- =============================================================
-- CROSSHAIR ASSIGN POTION LOGIC
-- =============================================================
function BotHelper.Healing.assignPotionEvent(slotIndex, btnWidget)
  if not mouseGrabberWidget then
    mouseGrabberWidget = g_ui.createWidget('UIWidget')
    mouseGrabberWidget:setVisible(false)
    mouseGrabberWidget:setFocusable(false)
  end

  mouseGrabberWidget:grabMouse()
  if modules.client_options and modules.client_options.getOption('nativeCursor') then
    g_window.setSystemCursor('cross')
  else
    g_mouse.pushCursor('target')
  end

  mouseGrabberWidget.onMouseRelease = function(self, mousePos, mouseButton)
    BotHelper.Healing.onAssignPotionRelease(self, mousePos, mouseButton, slotIndex, btnWidget)
  end
end

function BotHelper.Healing.onAssignPotionRelease(self, mousePos, mouseButton, slotIndex, btnWidget)
  mouseGrabberWidget:ungrabMouse()
  if modules.client_options and modules.client_options.getOption('nativeCursor') then
    g_window.restoreMouseCursor()
  else
    g_mouse.popCursor('target')
  end

  if mouseButton ~= MouseLeftButton then return true end

  local rootPanel = modules.game_interface.getRootPanel()
  local clickedWidget = rootPanel:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget then return true end

  local itemId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
    itemId = clickedWidget:getItem():getId()
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePos)
    if tile and tile:getTopUseThing() then
      itemId = tile:getTopUseThing():getId()
    end
  end

  local itemType = g_things.getThingType(itemId, ThingCategoryItem)
  if not itemType or not itemType:isPickupable() then
    if modules.game_textmessage then
        modules.game_textmessage.displayFailureMessage('Invalid object')
    end
    return true
  end

  local validPotions = {
    266, 236, 239, 7643, 23375, -- Vida (Health, Strong, Great, Ultimate, Supreme)
    268, 237, 238, 23373,       -- Mana (Mana, Strong, Great, Ultimate)
    7642, 23374                 -- Spirit (Great Spirit, Ultimate Spirit)
  }

  -- Trava Unificada (Qualquer slot aceita qualquer pot da lista)
  if not table_contains(validPotions, itemId) then
    if modules.game_textmessage then
        modules.game_textmessage.displayFailureMessage("Erro: Apenas pocoes de Vida, Mana ou Spirit sao permitidas.")
    end
    return true
  end

  BotHelper.Healing.potions[slotIndex].itemId = itemId
  cfgSet('healing', 'potion' .. slotIndex .. '.itemId', itemId)
  
  local uiItem = btnWidget:getChildById('potionItem')
  if uiItem then uiItem:setItemId(itemId) end

  BotHelper.showGameMessage('Potion slot ' .. slotIndex .. ' configurado para Item ' .. itemId)
  return true
end

-- API publica para setar pocao por Lua diretamente
function BotHelper.Healing.setPotion(slotIndex, itemId)
  if slotIndex < 1 or slotIndex > 3 then return end
  BotHelper.Healing.potions[slotIndex].itemId = itemId
  cfgSet('healing', 'potion' .. slotIndex .. '.itemId', itemId)
  if BotHelper.window then
    local icon = BotHelper.window:recursiveGetChildById('iconPotionHeal' .. slotIndex)
    if icon then icon:setItemId(itemId) end
  end
end

-- ÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉ
-- SUBSISTEMA: SPELLCASTER ENGINE
-- ÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉÔòÉ
BotHelper.SpellCaster = {}

-- Dados em memoria (sincronizados com g_settings + UI)
BotHelper.SpellCaster.spells = {}
for i=1,5 do
  BotHelper.SpellCaster.spells[i] = { text = '', icon = 0, manaPct = 90, creatures = '1+', priority = '1st' }
end
BotHelper.SpellCaster.autoTargetMode = 'A'
BotHelper.SpellCaster.shooterEnabled = false

-- Popula TODOS os ComboBoxes do SpellCaster (chamado UMA VEZ em setupUI)
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
    if cmbC then
      for _, opt in ipairs(creaturesOpts) do cmbC:addOption(opt) end
    end
    if cmbP then
      for _, opt in ipairs(priorityOpts) do cmbP:addOption(opt) end
    end
  end

  -- Auto Target ComboBox
  local cmbTarget = p:recursiveGetChildById('cmbAutoTargetMode')
  if cmbTarget then
    for _, opt in ipairs(targetModes) do cmbTarget:addOption(opt) end
  end
end

function BotHelper.SpellCaster.loadConfigToUI()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('casterPanel')
  if not p then return end

  -- Restaura Auto Target
  BotHelper.SpellCaster.autoTargetMode = cfgGet('caster', 'autoTargetMode', 'A')
  local cmbTarget = p:recursiveGetChildById('cmbAutoTargetMode')
  if cmbTarget then cmbTarget:setCurrentOption(BotHelper.SpellCaster.autoTargetMode) end

  -- Restaura Enable Shooter
  BotHelper.SpellCaster.shooterEnabled = cfgGet('caster', 'shooterEnabled', false)
  local chkShooter = p:recursiveGetChildById('chkEnableShooter')
  if chkShooter then chkShooter:setChecked(BotHelper.SpellCaster.shooterEnabled) end

  -- Restaura estado do Auto Target e propaga ao C++ (usa chkAutoTarget, NAO chkEnableShooter)
  BotHelper.SpellCaster.autoTargetEnabled = cfgGet('caster', 'autoTargetEnabled', false)
  local chkAT = p:recursiveGetChildById('chkAutoTarget')
  if chkAT then chkAT:setChecked(BotHelper.SpellCaster.autoTargetEnabled) end

  if g_game.isOnline() and g_botScheduler then
    g_botScheduler:setAutoTarget(
      BotHelper.SpellCaster.autoTargetEnabled,  -- CheckBox correto: chkAutoTarget
      BotHelper.SpellCaster.autoTargetMode
    )
  end

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
    if icon then
      BotHelper.Healing.updateSpellSlotLabel(icon,
        BotHelper.SpellCaster.spells[i].text,
        BotHelper.SpellCaster.spells[i].icon)
    end
    if cmbC then cmbC:setCurrentOption(BotHelper.SpellCaster.spells[i].creatures) end
    if cmbP then cmbP:setCurrentOption(BotHelper.SpellCaster.spells[i].priority) end
  end
end

function BotHelper.SpellCaster.syncFromUI()
  if not BotHelper.window then return end
  local p = BotHelper.window:recursiveGetChildById('casterPanel')
  if not p then return end

  -- Sincroniza Auto Target
  local cmbTarget = p:recursiveGetChildById('cmbAutoTargetMode')
  if cmbTarget then
    local v = cmbTarget:getCurrentOption().text
    BotHelper.SpellCaster.autoTargetMode = v
    cfgSet('caster', 'autoTargetMode', v)
  end

  -- Sincroniza Enable Shooter
  local chkShooter = p:recursiveGetChildById('chkEnableShooter')
  if chkShooter then
    BotHelper.SpellCaster.shooterEnabled = chkShooter:isChecked()
    cfgSet('caster', 'shooterEnabled', BotHelper.SpellCaster.shooterEnabled)
  end

  -- Sincroniza Enable Shooter (independente do Auto Target)
  local chkShooter = p:recursiveGetChildById('chkEnableShooter')
  if chkShooter then
    BotHelper.SpellCaster.shooterEnabled = chkShooter:isChecked()
    cfgSet('caster', 'shooterEnabled', BotHelper.SpellCaster.shooterEnabled)
  end

  -- Sincroniza Auto Target C++ usando APENAS o chkAutoTarget (widget correto)
  local chkAT = p:recursiveGetChildById('chkAutoTarget')
  if chkAT then
    BotHelper.SpellCaster.autoTargetEnabled = chkAT:isChecked()
    cfgSet('caster', 'autoTargetEnabled', BotHelper.SpellCaster.autoTargetEnabled)
  end
  if g_botScheduler then
    g_botScheduler:setAutoTarget(
      BotHelper.SpellCaster.autoTargetEnabled, -- CheckBox correto: chkAutoTarget
      BotHelper.SpellCaster.autoTargetMode
    )
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
end

-- Context menu for caster slots
function BotHelper.SpellCaster.spellSlotMenu(iconWidget, slotIndex)
  if slotIndex > 5 then return end
  local slot = BotHelper.SpellCaster.spells[slotIndex]
  if not slot then return end

  local menu = g_ui.createWidget('PopupMenu')
  menu:addOption('Assign Spell', function()
    BotHelper.SpellCaster.requestSpellText(iconWidget, slotIndex)
  end)
  menu:addSeparator()
  menu:addOption('Clear Action', function()
    BotHelper.SpellCaster.spells[slotIndex].text = ''
    BotHelper.SpellCaster.spells[slotIndex].icon = 0
    cfgSet('caster', 'spell' .. slotIndex .. '.text', '')
    cfgSet('caster', 'spell' .. slotIndex .. '.icon', 0)
    BotHelper.Healing.updateSpellSlotLabel(iconWidget, '', 0)
  end)
  menu:display(iconWidget:getPosition())
end

-- requestSpellText com icone igual ao Healing
function BotHelper.SpellCaster.requestSpellText(iconWidget, slotIndex)
  local current = BotHelper.SpellCaster.spells[slotIndex].text or ''
  if type(displayInputBox) == 'function' then
    displayInputBox(
      'Caster Slot ' .. slotIndex,
      'Digite o texto da magia (ex: exori gran):',
      function(text)
        if text and text:len() > 0 then
          local iconId = 0
          if Spells and type(Spells.getSpellDataByParamWords) == 'function' then
            local parsedSpell = Spells.getSpellDataByParamWords(text:lower())
            if parsedSpell and parsedSpell.clientId then
              iconId = parsedSpell.clientId
            end
          end

          BotHelper.SpellCaster.spells[slotIndex].text = text
          BotHelper.SpellCaster.spells[slotIndex].icon = iconId
          cfgSet('caster', 'spell' .. slotIndex .. '.text', text)
          cfgSet('caster', 'spell' .. slotIndex .. '.icon', iconId)
          BotHelper.Healing.updateSpellSlotLabel(iconWidget, text, iconId)
        end
      end,
      nil,
      current
    )
  end
end

-- =============================================================
-- HELPER: conta criaturas visiveis (nao-player, nao-npc)
-- =============================================================
local function countVisibleCreatures()
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  local count = 0
  local creatures = g_map.getSpectators(player:getPosition(), false)
  for _, creature in ipairs(creatures) do
    if creature ~= player and creature:isCreature() and not creature:isNpc() and creature:getHealthPercent() > 0 then
      count = count + 1
    end
  end
  return count
end

-- =============================================================
-- MOTOR DO SPELL SHOOTER ÔÇö cascata de prioridade + cooldowns
-- =============================================================

-- Timers locais (fonte primaria ÔÇö confiavel mesmo com CD window oculta)
local spellTimers      = {}   -- { [spellText] = millis do ultimo cast }
local globalAttackTimer = 0   -- millis do ultimo cast de qualquer spell de ataque

local GLOBAL_CD = 2050        -- ms de exaustao global (Safety Margin 50ms)
local SPELL_CD  = 4000        -- ms de CD individual conservador (fallback)

-- Tenta obter o exhaustion real da spell pelo DB do client
local function getSpellExhaustion(spell)
  if Spells and type(Spells.getSpellDataByParamWords) == 'function' then
    local data = Spells.getSpellDataByParamWords(spell.text:lower())
    if data and data.exhaustion and data.exhaustion > 0 then
      return data.exhaustion
    end
  end
  return SPELL_CD
end

-- ==================================================================
-- isOnGlobalCD(): true ÔåÆ aborta o ciclo inteiro (nenhum cast possivel)
-- ==================================================================
local function isOnGlobalCD()
  local now = g_clock.millis()

  -- Fonte 1: modulo nativo (Attack group = 1)
  local gc = modules.game_cooldown
  if gc and type(gc.isGroupCooldownIconActive) == 'function' then
    if gc.isGroupCooldownIconActive(1) then return true end
  end

  -- Fonte 2: cronometro local de ataque
  if (now - globalAttackTimer) < GLOBAL_CD then return true end

  -- Fonte 3: sincronizacao com cura (evita colisao de pacotes)
  if (now - BotHelper.lastHealTime) < 100 then return true end

  return false
end

-- ==================================================================
-- isSpellOnCD(spell): true ÔåÆ pula APENAS este slot, testa proximo
-- ==================================================================
local function isSpellOnCD(spell)
  local now = g_clock.millis()

  -- Fonte 1: modulo nativo por iconId (quando window visivel e dados populados)
  local gc = modules.game_cooldown
  if gc and type(gc.isCooldownIconActive) == 'function' then
    if spell.icon and spell.icon > 0 then
      if gc.isCooldownIconActive(spell.icon) then return true end
    end
  end

  -- Fonte 2: cronometro local por nome da magia (sempre confiavel)
  local last = spellTimers[spell.text]
  if last then
    local cd = getSpellExhaustion(spell)
    if (now - last) < cd then return true end
  end

  return false
end

function BotHelper.startCasterEngine()
  BotHelper.stopCasterEngine()
  if BOT_USE_CPP_SCHEDULER then 
    g_logger.info("[BotHelper] startCasterEngine chamado, CPP=" .. tostring(BOT_USE_CPP_SCHEDULER))
    return 
  end

  BotHelper.casterCycle = cycleEvent(function()
    if not isTabEnabled('caster') then return end
    if not BotHelper.SpellCaster.shooterEnabled then return end

    local player = g_game.getLocalPlayer()
    if not player then return end

    -- === TRAVA 1: GCD global ÔÇö aborta o ciclo inteiro ===
    -- Nao adianta testar nenhuma spell enquanto o GCD nao limpar
    if isOnGlobalCD() then return end

    -- === Coleta e ordena slots configurados por prioridade ===
    local orderedSlots = {}
    for i = 1, 5 do
      local s = BotHelper.SpellCaster.spells[i]
      if s and s.text and s.text ~= '' then
        local prioNum = tonumber(s.priority:match('%d+')) or i
        table.insert(orderedSlots, { prio = prioNum, data = s })
      end
    end
    if #orderedSlots == 0 then return end
    table.sort(orderedSlots, function(a, b) return a.prio < b.prio end)

    -- === Recursos do jogador (calculados uma unica vez por ciclo) ===
    local maxMana = player:getMaxMana()
    local manaPct = (maxMana > 0) and math.floor(player:getMana() * 100 / maxMana) or 0
    local creaturesNaTela = countVisibleCreatures()

    -- === CASCATA: itera por prioridade, pula CD individuais ===
    for _, entry in ipairs(orderedSlots) do
      local s = entry.data
      local requiredCreatures = tonumber(s.creatures:match('%d+')) or 1
      g_logger.info("[Caster] spell=" .. s.text .. 
          " creatures_raw=" .. tostring(s.creatures) ..
          " required=" .. tostring(requiredCreatures) ..
          " onScreen=" .. tostring(creaturesNaTela))

      if manaPct >= s.manaPct and creaturesNaTela >= requiredCreatures and not isSpellOnCD(s) then
        -- ACAO 2: Fim do Sequestro Manual
        local runeId = tonumber(s.text)
        local currentTarget = g_game.getAttackingCreature()
        
        if runeId and not BotHelper.SpellCaster.autoTargetEnabled and not currentTarget then
          -- Se for Runa e AutoTarget OFF e sem target manual: IGNORA. Nao sequestra / ataca sozinho.
        else
          -- GCD limpo + CD limpo + recursos OK -> DISPARA
          if runeId and currentTarget then
            g_game.useInventoryItemWith(runeId, currentTarget)
          else
            g_game.talk(s.text)
          end
          spellTimers[s.text] = g_clock.millis()
          globalAttackTimer   = g_clock.millis()
          return  -- 1 cast por ciclo; retorna e aguarda o proximo tick
        end
      end
      -- Condicao nao atendida: continua automaticamente para o proximo slot
    end
  end, 200)

  -- Sincronizacao de UI num ciclo separado e mais lento
  BotHelper.casterSyncCycle = cycleEvent(function()
    if not isTabEnabled('caster') then return end
    BotHelper.SpellCaster.syncFromUI()
  end, 500)
end

function BotHelper.stopCasterEngine()
  if BotHelper.casterCycle then
    removeEvent(BotHelper.casterCycle)
    BotHelper.casterCycle = nil
  end
  if BotHelper.casterSyncCycle then
    removeEvent(BotHelper.casterSyncCycle)
    BotHelper.casterSyncCycle = nil
  end
end


