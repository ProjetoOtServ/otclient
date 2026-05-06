-- game_construction.lua
-- Sistema de Construção - v5 (Final Fix)
-- Desenvolvido por Antigravity para Pixel-Planet

local ghostWidget = nil
local activeItemId = 0
local selectedItemId = 0
local constructionMode = false
local bookWindow = nil
local bookButton = nil
local managerWindow = nil
local lastSitePos = nil

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

-- === Inicialização ===

function init()
  g_logger.info("[game_construction] Initializing...")
  
  -- Garante que o estilo seja importado
  g_ui.importStyle('game_construction.otui')
  
  -- Tenta criar as janelas no root panel
  local rootPanel = modules.game_interface.getRootPanel()
  if rootPanel then
    bookWindow = g_ui.createWidget('BuildingBookWindow', rootPanel)
    managerWindow = g_ui.createWidget('ConstructionManagerWindow', rootPanel)
    if bookWindow then bookWindow:hide() end
    if managerWindow then managerWindow:hide() end
    setupWindow()
  else
    addEvent(function()
      local root = modules.game_interface.getRootPanel()
      if root then
        if not bookWindow then bookWindow = g_ui.createWidget('BuildingBookWindow', root) end
        if not managerWindow then managerWindow = g_ui.createWidget('ConstructionManagerWindow', root) end
        if bookWindow then bookWindow:hide() end
        if managerWindow then managerWindow:hide() end
        setupWindow()
      end
    end)
  end

  -- Opcodes
  ProtocolGame.registerExtendedOpcode(102, onConstructionStatus)

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
  if not bookWindow or not managerWindow then return end

  -- Inicializa Categorias do Livro
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

  -- Botão de Posicionamento do Livro
  local btnPlace = bookWindow:recursiveGetChildById('btnPlace')
  if btnPlace then
    btnPlace.onClick = function()
      if selectedItemId > 0 then
        startConstruction(selectedItemId)
        bookWindow:hide()
      end
    end
  end

  -- Slots do Manager
  for i=1, 4 do
    local slot = managerWindow:recursiveGetChildById('slot' .. i)
    slot.onDrop = function(widget, droppedWidget, mousePos)
        if not droppedWidget or not droppedWidget.getItem then return false end
        local item = droppedWidget:getItem()
        if not item then return false end
        
        local itemId = item:getId()
        if itemId == 5901 or itemId == 953 then
            addMaterial(itemId, item:getCount())
            return true
        end
        return false
    end
  end

  local btnBuild = managerWindow:getChildById('btnBuild')
  btnBuild.onClick = function()
      if not lastSitePos then return end
      g_game.getProtocolGame():sendExtendedOpcode(104, string.format("%d,%d,%d", lastSitePos.x, lastSitePos.y, lastSitePos.z))
      managerWindow:hide()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
  
  ProtocolGame.unregisterExtendedOpcode(102)

  if bookWindow then bookWindow:destroy(); bookWindow = nil end
  if managerWindow then managerWindow:destroy(); managerWindow = nil end
  if bookButton then bookButton:destroy(); bookButton = nil end
  stopConstruction()
end

-- === Opcodes e Comunicação ===

function onConstructionStatus(protocol, opcode, buffer)
    if buffer == "CLOSE" then
        if managerWindow then managerWindow:hide() end
        return
    end

    -- Buffer: Name|P_Cur|P_Ned|N_Cur|N_Ned|X|Y|Z
    local parts = buffer:split("|")
    if #parts < 8 then return end

    local name = parts[1]
    local pCur = tonumber(parts[2])
    local pNed = tonumber(parts[3])
    local nCur = tonumber(parts[4])
    local nNed = tonumber(parts[5])
    lastSitePos = {x = tonumber(parts[6]), y = tonumber(parts[7]), z = tonumber(parts[8])}

    managerWindow:getChildById('projectTitle'):setText(name)
    
    -- Calcula o que falta
    local pMissing = pNed - pCur
    local nMissing = nNed - nCur
    local statusText = ""
    if pMissing > 0 and nMissing > 0 then
        statusText = string.format("Faltam: %d Madeira e %d Pregos", pMissing, nMissing)
    elseif pMissing > 0 then
        statusText = string.format("Faltam: %d Madeira", pMissing)
    elseif nMissing > 0 then
        statusText = string.format("Faltam: %d Pregos", nMissing)
    else
        statusText = "Materiais prontos!"
    end
    managerWindow:getChildById('materialStatus'):setText(statusText)

    -- Atualiza visual dos slots
    local slot1 = managerWindow:recursiveGetChildById('slot1')
    local slot2 = managerWindow:recursiveGetChildById('slot2')
    
    if pCur > 0 then
        slot1:setItemId(5901)
        slot1:setItemCount(pCur)
    else
        slot1:setItemId(0)
    end

    if nCur > 0 then
        slot2:setItemId(953)
        slot2:setItemCount(nCur)
    else
        slot2:setItemId(0)
    end

    -- Habilita botão se materiais estiverem prontos
    local btnBuild = managerWindow:getChildById('btnBuild')
    if pCur >= pNed and nCur >= nNed then
        btnBuild:setEnabled(true)
    else
        btnBuild:setEnabled(false)
    end

    if not managerWindow:isVisible() then
        managerWindow:show()
        managerWindow:raise()
        startDistanceCheck()
    end
end

local distanceCheckEvent = nil

function startDistanceCheck()
    if distanceCheckEvent then removeEvent(distanceCheckEvent) end
    distanceCheckEvent = cycleEvent(function()
        if not managerWindow:isVisible() then
            removeEvent(distanceCheckEvent)
            distanceCheckEvent = nil
            return
        end

        local player = g_game.getLocalPlayer()
        if player and lastSitePos then
            local pPos = player:getPosition()
            local dist = math.max(math.abs(pPos.x - lastSitePos.x), math.abs(pPos.y - lastSitePos.y))
            if dist > 1 or pPos.z ~= lastSitePos.z then
                managerWindow:hide()
            end
        end
    end, 500)
end

function addMaterial(materialId, count)
    if not lastSitePos then return end
    count = count or 1
    local payload = string.format("%d,%d,%d,%d,%d", materialId, count, lastSitePos.x, lastSitePos.y, lastSitePos.z)
    g_logger.info("[game_construction] Sending Opcode 103: " .. payload)
    g_game.getProtocolGame():sendExtendedOpcode(103, payload)
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
    matLabel:setText(string.format("Materiais necessários: %d Madeira, %d Pregos", recipe.planks, recipe.nails))
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
