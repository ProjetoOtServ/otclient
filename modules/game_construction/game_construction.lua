-- game_construction.lua
-- Sistema de Construção - v5 (Final Fix)
-- Desenvolvido por Antigravity para Pixel-Planet

local ghostWidget = nil
local activeItemId = 0
local selectedItemId = 0
local constructionMode = false
local bookWindow = nil
local bookButton = nil

-- Definição de Receitas (ID -> {name, planks, nails})
local RECIPES = {
  [356] = {name = "Dirt Wall", planks = 5, nails = 2},
  [357] = {name = "Stone Wall", planks = 10, nails = 5},
  [1025] = {name = "Framework Wall", planks = 8, nails = 4},
  [408] = {name = "Wooden Floor", planks = 4, nails = 2},
  [409] = {name = "Marble Floor", planks = 2, nails = 10},
  [2474] = {name = "Wooden Coffin", planks = 8, nails = 12},
  [2582] = {name = "Wooden Chair", planks = 3, nails = 3},
  [1281] = {name = "Framework Wall 1", planks = 7, nails = 16},
  [1282] = {name = "Framework Wall 2", planks = 7, nails = 16},
  [1284] = {name = "Framework Wall 3", planks = 7, nails = 16},
  [1286] = {name = "Framework Wall 4", planks = 7, nails = 16},
  [1287] = {name = "Framework Wall 5", planks = 7, nails = 16},
}

-- Categorias Reais
local CATEGORIES = {
  {name = "Walls", items = {356, 357, 1025, 1281, 1282, 1284, 1286, 1287}},
  {name = "Windows", items = {1026, 1027}},
  {name = "Doors", items = {1211, 1212}},
  {name = "Floors", items = {408, 409}},
  {name = "Furniture", items = {2474, 2582}},
  {name = "Machinery", items = {}},
  {name = "Irrigation", items = {}},
  {name = "Stairs", items = {412, 413}},
  {name = "Fences", items = {1533, 1534, 1535}},
  {name = "Hangables", items = {}},
  {name = "Roofs", items = {}}
}

function init()
  g_logger.info("[game_construction] Initializing...")
  
  -- Garante que o estilo seja importado
  g_ui.importStyle('game_construction.otui')
  
  -- Tenta criar a janela no root panel
  local rootPanel = modules.game_interface.getRootPanel()
  if rootPanel then
    bookWindow = g_ui.createWidget('BuildingBookWindow', rootPanel)
    if bookWindow then
      bookWindow:hide()
      setupWindow()
    end
  else
    addEvent(function()
      local root = modules.game_interface.getRootPanel()
      if root and not bookWindow then
        bookWindow = g_ui.createWidget('BuildingBookWindow', root)
        if bookWindow then
          bookWindow:hide()
          setupWindow()
        end
      end
    end)
  end

  -- Eventos
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  if g_game.isOnline() then
    onGameStart()
  end
end

function setupWindow()
  if not bookWindow then return end

  -- Inicializa Categorias
  local catList = bookWindow:getChildById('listCategory')
  if catList then
    catList:destroyChildren()
    for _, cat in ipairs(CATEGORIES) do
      local label = g_ui.createWidget('Button', catList)
      label:setText(cat.name)
      label:setHeight(25)
      label.onClick = function() selectCategory(cat) end
    end
  end

  -- Botão de Posicionamento
  local btnPlace = bookWindow:recursiveGetChildById('btnPlace')
  if btnPlace then
    btnPlace.onClick = function()
      if selectedItemId > 0 then
        startConstruction(selectedItemId)
        bookWindow:hide()
      end
    end
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
  
  if bookWindow then
    bookWindow:destroy()
    bookWindow = nil
  end
  if bookButton then
    bookButton:destroy()
    bookButton = nil
  end
  stopConstruction()
end

function onGameStart()
  -- Adiciona o botão estilo Store
  -- Usamos scheduleEvent para garantir que o mainpanel processou seu onGameStart
  scheduleEvent(function()
    if modules.game_mainpanel and not bookButton then
       g_logger.info("[game_construction] Creating Store-style Button...")
       bookButton = modules.game_mainpanel.addStoreButton('buildingBookButton', tr('Building Book'), '/images/options/building_book_large', toggleBook)
       
       -- Fallback
       if not bookButton then
          g_logger.warning("[game_construction] Large button failed, creating normal toggle button")
          bookButton = modules.client_topmenu.addRightGameToggleButton('buildingBookButton', tr('Building Book'), '/images/options/building_book_large', toggleBook)
       end
    end
  end, 2000)
end

function onGameEnd()
  stopConstruction()
  if bookWindow then
    bookWindow:hide()
  end
end

function toggleBook()
  if not bookWindow then return end
  
  if bookWindow:isVisible() then
    bookWindow:hide()
  else
    bookWindow:show()
    bookWindow:raise()
    bookWindow:focus()
    selectCategory(CATEGORIES[1])
  end
end

function selectCategory(cat)
  local itemsPanel = bookWindow:recursiveGetChildById('listProduct')
  if not itemsPanel then return end
  
  itemsPanel:destroyChildren()
  
  for _, itemId in ipairs(cat.items) do
    local itemWidget = g_ui.createWidget('BuildingBookItem', itemsPanel)
    itemWidget:setItemId(itemId)
    itemWidget.onClick = function() selectItem(itemId) end
  end
end

function selectItem(itemId)
  selectedItemId = itemId
  
  local detailPanel = bookWindow:getChildById('detailPanel')
  local nameLabel = detailPanel:getChildById('itemName')
  local matLabel = detailPanel:getChildById('itemMaterials')
  local btnPlace = detailPanel:getChildById('btnPlace')
  
  local recipe = RECIPES[itemId]
  if recipe then
    nameLabel:setText(recipe.name)
    matLabel:setText(string.format("Materiais necessários: %d Planks, %d Nails", recipe.planks, recipe.nails))
    btnPlace:setEnabled(true)
  else
    nameLabel:setText("Item ID: " .. itemId)
    matLabel:setText("Materiais necessários: Desconhecido")
    btnPlace:setEnabled(true)
  end
end

-- === Lógica de Construção (Preview) ===

local inputGrabber = nil

function startConstruction(itemId)
  stopConstruction()
  
  activeItemId = itemId
  constructionMode = true
  
  -- The ghost widget
  ghostWidget = g_ui.createWidget('UIItem', modules.game_interface.getRootPanel())
  ghostWidget:setId('constructionGhost')
  ghostWidget:setItemId(itemId)
  ghostWidget:setOpacity(0.7)
  ghostWidget:setPhantom(true)
  ghostWidget.position = {x=0, y=0, z=0}
  ghostWidget:setSize({width = 32, height = 32})
  
  updateGhostPosition()
  
  -- The invisible click grabber
  inputGrabber = g_ui.createWidget('UIWidget', modules.game_interface.getRootPanel())
  inputGrabber:fill('parent')
  inputGrabber:setOpacity(0)
  inputGrabber.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      local mapPanel = modules.game_interface.getMapPanel()
      if not mapPanel then return false end
      
      local mapPos = mapPanel:getPosition(mousePos)
      if mapPos then
        modules.game_textmessage.displayFailureMessage("Enviando comando para o servidor...")
        local payload = activeItemId .. "," .. mapPos.x .. "," .. mapPos.y .. "," .. mapPos.z
        g_game.getProtocolGame():sendExtendedOpcode(101, payload)
        stopConstruction()
        return true
      else
        modules.game_textmessage.displayFailureMessage("Tile inválido.")
        return true
      end
    elseif mouseButton == MouseRightButton then
      modules.game_textmessage.displayFailureMessage("Construção cancelada.")
      stopConstruction()
      return true
    end
    return false
  end
  
  local mapPanel = modules.game_interface.getMapPanel()
  connect(mapPanel, {
    onMouseMove = onMouseMove
  })
  
  g_keyboard.bindKeyDown('Escape', stopConstruction)
end

function stopConstruction()
  if not constructionMode then return end
  constructionMode = false
  
  if ghostWidget then
    ghostWidget:destroy()
    ghostWidget = nil
  end
  
  if inputGrabber then
    inputGrabber:destroy()
    inputGrabber = nil
  end
  
  local mapPanel = modules.game_interface.getMapPanel()
  if mapPanel then
    disconnect(mapPanel, {
      onMouseMove = onMouseMove
    })
  end
  
  g_keyboard.unbindKeyDown('Escape')
end

function onMapClick()
  -- Not used anymore, kept for backwards compatibility with exports
  return false
end

function onMouseMove(widget, mousePos)
  if not constructionMode then return end
  updateGhostPosition(mousePos)
end

ModuleExporters = {
  updateGhostPosition = updateGhostPosition,
  isConstructionMode = isConstructionMode,
  onMapClick = onMapClick
}

function isConstructionMode()
  return constructionMode
end

function updateGhostPosition(mousePos)
  if not ghostWidget then return end
  
  mousePos = mousePos or g_window.getMousePosition()
  local mapPanel = modules.game_interface.getMapPanel()
  if not mapPanel then return end
  
  local tile = mapPanel:getTile(mousePos)
  
  if tile then
    -- local screenPos = mapPanel:transformPositionToPoint(tile:getPosition())
    local screenPos = mousePos
    ghostWidget:setPosition({x = screenPos.x - ghostWidget:getWidth()/2, y = screenPos.y - ghostWidget:getHeight()/2})
    ghostWidget:show()
    
    if tile:isWalkable() then
      ghostWidget:setImageColor('white')
    else
      ghostWidget:setImageColor('#ff8888')
    end
  else
    ghostWidget:hide()
  end
end
