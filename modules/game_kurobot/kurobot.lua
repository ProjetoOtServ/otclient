-- ==========================================
--  KuroBot — Main Controller
--  Architecture: manual tab switching (no UITabBar)
--  No bot logic in this file — UI-driving only
-- ==========================================

KuroBot = {
  Heal     = { config = { spells = {}, items = {}, conditions = {} } },
  Tools    = {},
  SkillSet = {},
  Hunting  = {}
}

kurobotWindow  = nil
kurobotButton  = nil
currentTab     = 'healing'

-- Tab button & panel id pairs — must match the OTUI ids
local TAB_DEFS = {
  { tab = 'healing',  btn = 'tabBtnHealing',  panel = 'tabHealing',  label = 'Healing'   },
  { tab = 'tools',    btn = 'tabBtnTools',    panel = 'tabTools',    label = 'Tools'     },
  { tab = 'skillset', btn = 'tabBtnSkillSet', panel = 'tabSkillSet', label = 'Skill Set' },
  { tab = 'hunting',  btn = 'tabBtnHunting',  panel = 'tabHunting',  label = 'Hunting'   },
}

local healingEvent   = nil
local itemEvent      = nil
local conditionEvent = nil

-- ==========================================
--  Lifecycle
-- ==========================================

function init()
  g_ui.importStyle('kurobot_styles')

  kurobotButton = modules.game_mainpanel.addToggleButton(
    'kurobotButton', tr('KuroBot'), '/images/topbuttons/skills', toggle)
  kurobotButton:setOn(false)

  kurobotWindow = g_ui.displayUI('kurobot')
  if not kurobotWindow then
    perror('[KuroBot] failed to load kurobot.otui')
    return
  end
  kurobotWindow:hide()

  -- Initialise dependent sub-modules
  if KuroBot.Heal.init then KuroBot.Heal.init() end

  switchTab('healing')

  connect(g_game, { onGameStart = online, onGameEnd = offline })
  if g_game.isOnline() then online() end
end

function terminate()
  disconnect(g_game, { onGameStart = online, onGameEnd = offline })

  if KuroBot.Heal.terminate then KuroBot.Heal.terminate() end
  stopHealingThreads()

  if kurobotButton and not kurobotButton:isDestroyed() then
    kurobotButton:destroy()
    kurobotButton = nil
  end
  if kurobotWindow and not kurobotWindow:isDestroyed() then
    kurobotWindow:destroy()
    kurobotWindow = nil
  end
end

-- ==========================================
--  Tab Switching
-- ==========================================

function switchTab(tabId)
  if not kurobotWindow then return end
  currentTab = tabId

  local contentArea = kurobotWindow:getChildById('contentArea')
  local tabBar      = kurobotWindow:getChildById('tabBar')
  local tabLabel    = tabBar and tabBar:getChildById('tabLabel')

  for _, def in ipairs(TAB_DEFS) do
    -- Show/hide content panels
    local panel = contentArea and contentArea:getChildById(def.panel)
    if panel then panel:setVisible(def.tab == tabId) end

    -- Check/uncheck tab buttons
    local btn = tabBar and tabBar:getChildById(def.btn)
    if btn then btn:setChecked(def.tab == tabId) end

    -- Update label
    if tabLabel and def.tab == tabId then
      tabLabel:setText(def.label)
    end
  end
end

-- ==========================================
--  Window Toggle
-- ==========================================

function toggle()
  if not kurobotWindow then return end
  if kurobotButton:isOn() then
    kurobotWindow:hide()
    kurobotButton:setOn(false)
  else
    kurobotWindow:show()
    kurobotWindow:raise()
    kurobotWindow:focus()
    kurobotButton:setOn(true)
  end
end

-- ==========================================
--  Game Online / Offline
-- ==========================================

function online()
  startHealingThreads()
end

function offline()
  stopHealingThreads()
  if kurobotWindow then kurobotWindow:hide() end
  if kurobotButton then kurobotButton:setOn(false) end
end

-- ==========================================
--  Healing Thread Stubs (logic TBD)
-- ==========================================

function startHealingThreads()
  if healingEvent then return end
  healingEvent   = cycleEvent(spellHealingRoutine,     100)
  itemEvent      = cycleEvent(itemHealingRoutine,      100)
  conditionEvent = cycleEvent(conditionHealingRoutine, 200)
end

function stopHealingThreads()
  if healingEvent   then removeEvent(healingEvent)   healingEvent   = nil end
  if itemEvent      then removeEvent(itemEvent)      itemEvent      = nil end
  if conditionEvent then removeEvent(conditionEvent) conditionEvent = nil end
end

function spellHealingRoutine()
  if not g_game.isOnline() then return end
end

function itemHealingRoutine()
  if not g_game.isOnline() then return end
end

function conditionHealingRoutine()
  if not g_game.isOnline() then return end
end
