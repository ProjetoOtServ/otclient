--[[
  Super Trader Blacklist Module for OTClient
  
  Features:
  1. Right-click menu to add/remove items from sell blacklist
  2. Filter items in NPC trade window (hide blacklisted items)
  3. Sell All button respects blacklist
  4. Blacklist window with item icons
]]

local gameSuperTrader = {}

-- Blacklist storage (itemId -> boolean)
local blacklist = {}
local moduleLoaded = false
local blacklistWindow = nil

-- Initialize module
function init()
  g_logger.info("[game_supertrader] Initializing...")
  blacklist = {}
  moduleLoaded = true
  g_logger.info("[game_supertrader] Initialized successfully")
end

-- Terminate module
function terminate()
  g_logger.info("[game_supertrader] Terminating...")
  if blacklistWindow then
    blacklistWindow:destroy()
    blacklistWindow = nil
  end
  blacklist = {}
  moduleLoaded = false
end

-- Check if item is blacklisted
function gameSuperTrader.isBlacklisted(itemId)
  if not itemId or not moduleLoaded then return false end
  return blacklist[itemId] == true
end

-- Refresh NPC trade window if open
local function refreshNpcTrade()
  if modules.game_npctrade and modules.game_npctrade.npcWindow and modules.game_npctrade.npcWindow:isVisible() then
    if modules.game_npctrade.refreshTradeItems then
      modules.game_npctrade.refreshTradeItems()
    end
    if modules.game_npctrade.refreshPlayerGoods then
      modules.game_npctrade.refreshPlayerGoods()
    end
  end
end

-- Add item to blacklist
function gameSuperTrader.addToBlacklist(itemId)
  if not itemId or not moduleLoaded then 
    g_logger.warning("[game_supertrader] Cannot add to blacklist")
    return false 
  end
  
  blacklist[itemId] = true
  g_logger.info("[game_supertrader] Added item " .. itemId .. " to blacklist")
  
  -- Show feedback
  if modules.game_textmessage then
    modules.game_textmessage.displayGameMessage("Item added to Sell Blacklist.")
  end
  
  if modules.game_console then
    modules.game_console.addText("Item ID " .. itemId .. " added to Sell Blacklist.", nil, "Server Log")
  end
  
  refreshNpcTrade()
  return true
end

-- Remove item from blacklist
function gameSuperTrader.removeFromBlacklist(itemId)
  if not itemId or not moduleLoaded then 
    g_logger.warning("[game_supertrader] Cannot remove from blacklist")
    return false 
  end
  
  blacklist[itemId] = nil
  g_logger.info("[game_supertrader] Removed item " .. itemId .. " from blacklist")
  
  -- Show feedback
  if modules.game_textmessage then
    modules.game_textmessage.displayGameMessage("Item removed from Sell Blacklist.")
  end
  
  if modules.game_console then
    modules.game_console.addText("Item ID " .. itemId .. " removed from Sell Blacklist.", nil, "Server Log")
  end
  
  refreshNpcTrade()
  return true
end

-- Toggle item in blacklist
function gameSuperTrader.toggleBlacklist(itemId)
  if gameSuperTrader.isBlacklisted(itemId) then
    return gameSuperTrader.removeFromBlacklist(itemId)
  else
    return gameSuperTrader.addToBlacklist(itemId)
  end
end

-- Get blacklist as list of itemIds
function gameSuperTrader.getBlacklist()
  local list = {}
  for itemId, _ in pairs(blacklist) do
    table.insert(list, itemId)
  end
  return list
end

-- Clear all blacklist
function gameSuperTrader.clearBlacklist()
  blacklist = {}
  g_logger.info("[game_supertrader] Blacklist cleared")
  
  if modules.game_textmessage then
    modules.game_textmessage.displayGameMessage("Sell Blacklist cleared.")
  end
  
  refreshNpcTrade()
  
  if blacklistWindow then
    blacklistWindow:destroy()
    blacklistWindow = nil
  end
  
  return true
end

-- Hide blacklist window
function gameSuperTrader.hideBlacklistWindow()
  if blacklistWindow then
    blacklistWindow:hide()
  end
end

-- Show blacklist window with item icons in a grid
function gameSuperTrader.showBlacklistWindow()
  if not moduleLoaded then
    g_logger.error("[game_supertrader] Module not loaded")
    return
  end
  
  -- Count items
  local count = 0
  for _ in pairs(blacklist) do count = count + 1 end
  
  if count == 0 then
    if modules.game_textmessage then
      modules.game_textmessage.displayGameMessage("Your Sell Blacklist is empty.")
    end
    return
  end
  
  -- Remove existing window
  if blacklistWindow then
    blacklistWindow:destroy()
    blacklistWindow = nil
  end
  
  -- Load and create window from OTUI
  local window = g_ui.displayUI('game_supertrader.otui')
  if not window then
    g_logger.error("[game_supertrader] Failed to load OTUI file")
    return
  end
  
  blacklistWindow = window
  window:setText("Sell Blacklist (" .. count .. " items)")
  window:centerIn('parent')
  
  local itemsGrid = window:recursiveGetChildById('itemsGrid')
  if not itemsGrid then
    g_logger.error("[game_supertrader] itemsGrid not found")
    window:destroy()
    blacklistWindow = nil
    return
  end
  
  -- Add each blacklisted item as an icon
  for itemId, _ in pairs(blacklist) do
    local itemBox = g_ui.createWidget('UIWidget', itemsGrid)
    if not itemBox then
      g_logger.warning("[game_supertrader] Failed to create itemBox for item " .. itemId)
      goto continue
    end
    
    itemBox:setSize({ width = 42, height = 42 })
    itemBox:setBorderWidth(1)
    itemBox:setBorderColor('#333333')
    itemBox:setBackgroundColor('#2a2a2a')
    
    -- Create the item sprite using UIItem (not Item)
    local itemWidget = g_ui.createWidget('UIItem', itemBox)
    if not itemWidget then
      g_logger.warning("[game_supertrader] Failed to create UIItem for item " .. itemId)
      goto continue
    end
    
    itemWidget:setId('sprite')
    itemWidget:setSize({ width = 32, height = 32 })
    itemWidget:setPosition({ x = 5, y = 5 })
    itemWidget:setItemId(itemId)
    itemWidget:setPhantom(true)
    itemWidget:setVirtual(true)
    
    -- Add tooltip with item ID
    itemBox:setTooltip("Right-click to remove from Sell Blacklist\nItem ID: " .. itemId)
    
    -- Right-click to remove
    itemBox.onMouseRelease = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption("Remove from Sell Blacklist", function()
          gameSuperTrader.removeFromBlacklist(itemId)
          if blacklistWindow then
            blacklistWindow:destroy()
            blacklistWindow = nil
          end
          -- Re-open window to refresh
          scheduleEvent(function()
            gameSuperTrader.showBlacklistWindow()
          end, 150)
        end)
        menu:display(mousePos)
        return true
      end
      return false
    end
    
    ::continue::
  end
  
  window:show()
  window:raise()
  window:focus()
end

-- Export module
modules = modules or {}
modules.game_supertrader = gameSuperTrader
_G.gameSuperTrader = gameSuperTrader

return gameSuperTrader
