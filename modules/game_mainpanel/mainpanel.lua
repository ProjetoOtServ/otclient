local standModeBox
local chaseModeBox
local optionsAmount = 0
local specialsAmount = 0
local storeAmount = 0

local chaseModeRadioGroup
local controlButton1400 = nil
local optionPanel = nil
local buttonConfigs = {}
local buttonOrder = {}
local COLORS = {
    BASE_1 = "#484848",
    BASE_2 = "#414141"
}

local PANEL_CONSTANTS = {
    ICON_WIDTH = 18,
    ICON_HEIGHT = 18,
    MAX_ICONS_PER_ROW = {
        OPTIONS = 5,
        SPECIALS = 2,
        STORE = 1
    },
    MULTI_STORE_HEIGHT = 20,
    HEIGHT_EXTRA_ONPANEL = -5,
    HEIGHT_EXTRA_SHRINK = 5
}

local optionsShrink = false

local function calculatePanelHeight(panel, max_icons_per_row)
    local icon_count = 0
    for _, icon in ipairs(panel:getChildren()) do
        if icon:isVisible() then
            icon_count = icon_count + 1
        end
    end
    local rows = math.ceil(icon_count / max_icons_per_row)
    local height = (rows * PANEL_CONSTANTS.ICON_HEIGHT) + (rows * 3)
    return height, icon_count
end

function reloadMainPanelSizes()
    local main_panel = modules.game_interface.getMainRightPanel()
    local right_panel = modules.game_interface.getRightPanel()
    if not main_panel or not right_panel then
        return
    end
    local total_height = 1
    for _, panel in ipairs(main_panel:getChildren()) do
        if panel.panelHeight ~= nil then
            if panel:isVisible() then
                panel:setHeight(panel.panelHeight)
                total_height = total_height + panel.panelHeight
                if panel:getId() == 'mainoptionspanel' then
                    if panel:isOn() then
                        local options_panel = optionsController.ui.onPanel.options
                        local options_height, options_count =
                            calculatePanelHeight(options_panel, PANEL_CONSTANTS.MAX_ICONS_PER_ROW.OPTIONS)
                        local specials_panel = optionsController.ui.onPanel.specials
                        local specials_height, specials_count =
                            calculatePanelHeight(specials_panel, PANEL_CONSTANTS.MAX_ICONS_PER_ROW.SPECIALS)
                        local store_panel = panel.onPanel.store
                        local store_height, store_count = calculatePanelHeight(store_panel,
                            PANEL_CONSTANTS.MAX_ICONS_PER_ROW.STORE)
                        if store_count > 0 then
                            store_height = store_count * PANEL_CONSTANTS.MULTI_STORE_HEIGHT + (store_count - 1) * 2
                        end
                        local combined_height = store_height + math.max(options_height, specials_height)
                        local extra_height = PANEL_CONSTANTS.HEIGHT_EXTRA_ONPANEL
                        if store_count >= 2 then
                            extra_height = extra_height - (store_count - 1) * 5
                        end
                        combined_height = combined_height + extra_height
                        store_panel:setHeight(store_height)
                        panel:setHeight(combined_height + panel.panelHeight)
                        total_height = total_height + combined_height
                    else
                        total_height = total_height + PANEL_CONSTANTS.HEIGHT_EXTRA_SHRINK
                    end
                end
            else
                panel:setHeight(0)
            end
        end
    end
    main_panel:setHeight(total_height)
    right_panel:fitAll()
end

local function refreshOptionsSizes()
    if optionsShrink then
        optionsController.ui:setOn(false)
        optionsController.ui.offPanel:show()
    else
        optionsController.ui:setOn(true)
        optionsController.ui.offPanel:hide()
    end
    reloadMainPanelSizes()
end

-- === CRIAÇÃO DE BOTÕES DA LOJA (SEM CLONES) ===
local function createButton_large(id, description, image, callback, special, front)
    local panel = optionsController.ui.onPanel.store
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    
    -- O SEGREDO 1: Procura o botão nas DUAS gavetas antes de criar um novo!
    local button = panel:getChildById(id)
    if not button and rightGamePanel then
        button = rightGamePanel:getChildById(id)
    end

    if not button then
        button = g_ui.createWidget('largeToggleButton')
        button.originalPanel = "specials" -- Carimbo de origem para não se perder
        
        -- Define onde ele deve nascer baseado no modo Widescreen
        local target = (modules.game_interface.currentViewMode == 2) and rightGamePanel or panel
        if front then
            target:insertChild(1, button)
        else
            target:addChild(button)
        end
    end
    
    button:setId(id)
    button:setTooltip(description)
    button:setImageSource(image)
    button:setImageClip('0 0 108 20')
    button.onMouseRelease = function(widget, mousePos, mouseButton)
        if widget:containsPoint(mousePos) and mouseButton ~= MouseMidButton then
            callback()
            return true
        end
    end

    return button
end

-- === CRIAÇÃO DE BOTÕES NORMAIS (SEM CLONES) ===
local function createButton(id, description, image, callback, special, front, index)
    local panel
    local panelName
    if special then
        panel = optionsController.ui.onPanel.specials
        panelName = "specials"
    else
        panel = optionsController.ui.onPanel.options
        panelName = "options"
    end

    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    
    -- O SEGREDO 2: Busca onipresente!
    local button = panel:getChildById(id)
    if not button and rightGamePanel then
        button = rightGamePanel:getChildById(id)
    end

    if not button then
        button = g_ui.createWidget('MainToggleButton')
        button.originalPanel = panelName
        
        local target = (modules.game_interface.currentViewMode == 2) and rightGamePanel or panel
        if front then
            target:insertChild(1, button)
        else
            target:addChild(button)
        end
    end

    button:setId(id)
    button:setTooltip(description)
    button:setSize('20 20')
    button:setImageSource(image)
    button:setImageClip('0 0 20 20')
    button.onMouseRelease = function(widget, mousePos, mouseButton)
        if widget:containsPoint(mousePos) and mouseButton ~= MouseMidButton then
            callback()
            return true
        end
    end
    if not button.index and type(index) == 'number' then
        button.index = index or 1000
    end

    refreshOptionsSizes()
    return button
end

optionsController = Controller:new()
optionsController:setUI('mainoptionspanel', modules.game_interface.getMainRightPanel())

function optionsController:onInit()
    createButton_large('Store shop', tr('Store shop'), '/images/options/store_large', toggleStore,
    false, 8)

    if not optionPanel then
        optionPanel = g_ui.loadUI('option_control_buttons', modules.client_options:getPanel())
        modules.client_options.addButton("Interface", "Control Buttons", optionPanel, function() initControlButtons() end)
    end
end

function toggleStore()
    if  g_game.getFeature(GameIngameStore) then
        modules.game_store.toggle() -- cipsoft packets
    else
        modules.game_shop.toggle() -- custom
    end
end

function optionsController:onTerminate()
    if optionPanel then
        optionPanel:destroy()
        optionPanel = nil
        modules.client_options.removeButton("Interface", "Control Buttons")  -- hot reload
    end
    if controlButton1400 then
        controlButton1400:destroy()
        controlButton1400 = nil
    end
end

function optionsController:onGameStart()
    optionsShrink = g_settings.getBoolean('mainpanel_shrink_options')
    refreshOptionsSizes()
    modules.game_interface.setupOptionsMainButton()
    modules.client_options.setupOptionsMainButton()
    
    optionsController:scheduleEvent(function()
        if optionPanel then
            local config = loadButtonConfig()
            buttonConfigs = config.buttons or {}
            buttonOrder = config.order or {}
            
            -- [CORREÇÃO 3 - CIDADE FANTASMA]: Ensina o código a procurar os botões 
            -- na barra do Topo se o Widescreen estiver ativo!
            local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
            local optionsPanel = optionsController.ui.onPanel.options
            local targetPanel = (modules.game_interface.currentViewMode == 2) and rightGamePanel or optionsPanel

            for _, button in ipairs(targetPanel:getChildren()) do
                local id = button:getId()
                -- Só aplica a invisibilidade se NÃO for o botão da Store ("specials")
                if id and buttonConfigs[id] and button.originalPanel ~= "specials" then
                    button:setVisible(buttonConfigs[id].visible)
                end
            end
            
            reorderButtons()
            updateDisplayedButtonsList()
            updateAvailableButtonsList()
            reloadMainPanelSizes()
        end
    end, 50, "onGameStart")
    
    if g_game.getClientVersion() >= 1400 and not controlButton1400 then
        controlButton1400 = modules.game_mainpanel.addToggleButton('controButtons', tr('Manage control buttons'),
        '/images/options/button_control', function() modules.client_options.openOptionsCategory("Interface", "Control Buttons") end, false, 1)
        controlButton1400:setOn(false)
    end
end

function optionsController:onGameEnd()
end

function changeOptionsSize()
    optionsShrink = not optionsShrink
    g_settings.set('mainpanel_shrink_options', optionsShrink)
    refreshOptionsSizes()
end

function addToggleButton(id, description, image, callback, front, index)
    return createButton(id, description, image, callback, false, front, index)
end

function addSpecialToggleButton(id, description, image, callback, front, index)
    return createButton(id, description, image, callback, true, front, index)
end

function addStoreButton(id, description, image, callback, front)
    return createButton_large(id, description, image, callback, true, front)
end

function getButton(id)
    return optionsController.ui.onPanel.options:recursiveGetChildById(id)
end

-- Função que decide o que vai pra barra superior no modo Widescreen
function toggleExtendedViewButtons(extended)
    local optionsPanel = optionsController.ui.onPanel.options
    local specialsPanel = optionsController.ui.onPanel.store
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    
    -- [CORREÇÃO 1]: Forçamos o carregamento do save ANTES de mover os botões!
    if not buttonConfigs or table.empty(buttonConfigs) then
        local config = loadButtonConfig()
        buttonConfigs = config.buttons or {}
        buttonOrder = config.order or {}
    end

    if extended then
        -- Movemos os botões NORMAIS (Inventário, Mapa, etc)
        local optionChildren = optionsPanel:getChildren()
        for _, button in ipairs(optionChildren) do
            if not button:isDestroyed() then
                button.originalPanel = "options"
                rightGamePanel:addChild(button)
                
                -- Aplica a visibilidade do save. Se não existir, mostra por padrão.
                if buttonConfigs[button:getId()] ~= nil then
                    button:setVisible(buttonConfigs[button:getId()].visible)
                else
                    button:setVisible(true) 
                end
            end
        end
        
        -- [CORREÇÃO 2]: Movemos os botões ESPECIAIS (Store) garantindo que NÃO fiquem invisíveis!
        local specialChildren = specialsPanel:getChildren()
        for _, button in ipairs(specialChildren) do
            if not button:isDestroyed() then
                button.originalPanel = "specials"
                rightGamePanel:addChild(button)
                button:setVisible(true) -- A Loja é imune ao Displayed Buttons, sempre visível!
            end
        end
        
        optionsController.ui:hide()
        optionsController.ui:setHeight(0)
    else
        -- Quando desloga, devolve os botões pra direita...
        local children = rightGamePanel:getChildren()
        for _, button in ipairs(children) do
            if not button:isDestroyed() then
                if button.originalPanel == "options" then
                    optionsPanel:addChild(button)
                    if buttonConfigs[button:getId()] ~= nil then
                        button:setVisible(buttonConfigs[button:getId()].visible)
                    end
                elseif button.originalPanel == "specials" then
                    specialsPanel:addChild(button)
                    button:setVisible(true) -- Loja sempre visível ao deslogar
                end
            end
        end
        optionsController.ui:show()
        optionsController.ui:setHeight(28)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if mainRightPanel:hasChild(optionsController.ui) then
            mainRightPanel:moveChildToIndex(optionsController.ui, 4)
        end
    end
    
    reorderButtons()
    refreshOptionsSizes()
end

function saveButtonConfig()
    local config = {
        buttons = {},
        order = {}
    }
    for id, buttonConfig in pairs(buttonConfigs) do
        if type(id) == "string" and type(buttonConfig) == "table" then
            config.buttons[id] = {
                visible = buttonConfig.visible,
                tooltip = buttonConfig.tooltip
            }
        end
    end
    for i, id in ipairs(buttonOrder) do
        config.order[tostring(i)] = id
    end
    -- MUDANÇA: Salva globalmente em um nó novo e blindado
    g_settings.setNode('global_control_buttons', config)
    g_settings.save() -- Força a gravação no disco na mesma hora!
end

function loadButtonConfig()
    -- MUDANÇA: Lê do nó global
    local config = g_settings.getNode('global_control_buttons') or {
        buttons = {},
        order = {}
    }
    local orderArray = {}
    if config.order then
        local keys = {}
        for k in pairs(config.order) do
            table.insert(keys, tonumber(k))
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            table.insert(orderArray, config.order[tostring(k)])
        end
    end

    return {
        buttons = config.buttons or {},
        order = orderArray
    }
end

local function updateList(listWidget, isVisibleList)
    if not g_game.isOnline() or not listWidget then
        return
    end
    local focusedItem = listWidget:getFocusedChild()
    local focusedId = focusedItem and focusedItem.buttonId
    local existingItems = {}
    for _, child in ipairs(listWidget:getChildren()) do
        existingItems[child.buttonId] = child
    end
    local displayButtons = {}
    for id, config in pairs(buttonConfigs) do
        if (config.visible == true) == isVisibleList then
            table.insert(displayButtons, {
                id = id,
                config = config
            })
        end
    end
    if isVisibleList then
        table.sort(displayButtons, function(a, b)
            local indexA = table.find(buttonOrder, a.id) or 999
            local indexB = table.find(buttonOrder, b.id) or 999
            return indexA < indexB
        end)
    end
    for buttonId, item in pairs(existingItems) do
        local shouldBeInList = false
        for _, buttonData in ipairs(displayButtons) do
            if buttonData.id == buttonId then
                shouldBeInList = true
                break
            end
        end
        if not shouldBeInList then
            item:destroy()
            existingItems[buttonId] = nil
        end
    end

    local currentChildren = {}
    for i, buttonData in ipairs(displayButtons) do
        local buttonId = buttonData.id
        local buttonConfig = buttonData.config
        local item = existingItems[buttonId]
        if not item then
            item = g_ui.createWidget('HotkeyListLabel', listWidget)
            item:setId(buttonId)
            item.buttonId = buttonId
            item:setText(buttonConfig.tooltip)
            item:setTextAlign(AlignLeft)
        end
        if not item:isFocused() then
            item:setBackgroundColor((i % 2 == 0) and COLORS.BASE_1 or COLORS.BASE_2)
        end

        table.insert(currentChildren, item)
    end
    listWidget:reorderChildren(currentChildren)
    if focusedId then
        for _, child in ipairs(listWidget:getChildren()) do
            if child.buttonId == focusedId then
                child:focus()
                break
            end
        end
    end
end

function updateDisplayedButtonsList()
    updateList(optionPanel.panelDisplayedButtons.displayedButtonsList, true)
end

function updateAvailableButtonsList()
    updateList(optionPanel.panelAvailableButtons.displayedAvailableButtonsList, false)
end

-- === ESCONDER BOTÃO ===
function moveToAvailable()
    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local selectedItem = displayedList:getFocusedChild()

    if not selectedItem then return end

    local buttonId = selectedItem.buttonId
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    local optionsPanel = optionsController.ui.onPanel.options
    
    -- O SEGREDO 3: Acha o botão quer ele esteja na lateral ou no topo
    local button = optionsPanel:getChildById(buttonId)
    if not button and rightGamePanel then
        button = rightGamePanel:getChildById(buttonId)
    end

    if button then
        button:setVisible(false)
        buttonConfigs[buttonId].visible = false
        table.removevalue(buttonOrder, buttonId)
        updateDisplayedButtonsList()
        updateAvailableButtonsList()
        saveButtonConfig()
        reloadMainPanelSizes()
        displayedList:focusNextChild(KeyboardFocusReason)
    end
end

-- === MOSTRAR BOTÃO ===
function moveToDisplayed()
    local availableList = optionPanel.panelAvailableButtons.displayedAvailableButtonsList
    local selectedItem = availableList:getFocusedChild()

    if not selectedItem then return end

    local buttonId = selectedItem.buttonId
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    local optionsPanel = optionsController.ui.onPanel.options
    
    -- Mesma busca onipresente
    local button = optionsPanel:getChildById(buttonId)
    if not button and rightGamePanel then
        button = rightGamePanel:getChildById(buttonId)
    end

    if button then
        button:setVisible(true)
        buttonConfigs[buttonId].visible = true
        table.insert(buttonOrder, buttonId)
        updateDisplayedButtonsList()
        updateAvailableButtonsList()
        reorderButtons()
        saveButtonConfig()
        reloadMainPanelSizes()
        availableList:focusNextChild(KeyboardFocusReason)
    end
end

function moveButtonUp()
    if not g_game.isOnline() then
        return
    end

    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local selectedItem = displayedList:getFocusedChild()

    if not selectedItem then
        return
    end

    local buttonId = selectedItem.buttonId
    local index = table.find(buttonOrder, buttonId)

    if index and index > 1 then
        buttonOrder[index], buttonOrder[index - 1] = buttonOrder[index - 1], buttonOrder[index]
        updateDisplayedButtonsList()
        reorderButtons()
        saveButtonConfig()
        local focusedChild = displayedList:getFocusedChild()
        if focusedChild then
            displayedList:ensureChildVisible(focusedChild)
        end
    end
end

function moveButtonDown()
    if not g_game.isOnline() then
        return
    end

    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local selectedItem = displayedList:getFocusedChild()

    if not selectedItem then
        return
    end

    local buttonId = selectedItem.buttonId
    local index = table.find(buttonOrder, buttonId)

    if index and index < #buttonOrder then
        buttonOrder[index], buttonOrder[index + 1] = buttonOrder[index + 1], buttonOrder[index]

        updateDisplayedButtonsList()
        reorderButtons()
        saveButtonConfig()
        local focusedChild = displayedList:getFocusedChild()
        if focusedChild then
            displayedList:ensureChildVisible(focusedChild)
        end
    end
end

-- Função que coloca os botões em fila indiana de acordo com sua escolha
function reorderButtons()
    if not g_game.isOnline() then return end
    
    local optionsPanel = optionsController.ui.onPanel.options
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    local targetPanel = (modules.game_interface.currentViewMode == 2) and rightGamePanel or optionsPanel
    
    local currentChildren = targetPanel:getChildren()
    local childrenSet = {}
    
    -- Mapeia todos os filhos que existem fisicamente no painel
    for _, child in ipairs(currentChildren) do
        local key = child:getId() or tostring(child)
        childrenSet[key] = child
    end
    
    local sortedChildren = {}
    
    -- 1. Garante os Especiais (Store) no começo
    for _, child in ipairs(currentChildren) do
        if child.originalPanel == "specials" then
            table.insert(sortedChildren, child)
            local key = child:getId() or tostring(child)
            childrenSet[key] = nil -- Tira da lista de pendentes
        end
    end
    
    -- 2. Coloca os botões na sua ordem customizada
    for _, id in ipairs(buttonOrder) do
        local child = childrenSet[id]
        if child then
            table.insert(sortedChildren, child)
            childrenSet[id] = nil
        end
    end
    
    -- 3. Tudo o que sobrou (botões novos de atualizações, etc) vai pro final
    for key, child in pairs(childrenSet) do
        table.insert(sortedChildren, child)
    end
    
    -- A trava de segurança contra o crash de memória
    if #sortedChildren == #currentChildren then
        targetPanel:reorderChildren(sortedChildren)
    else
        print("Protecao ativada: falha na engine do reorderChildren prevenida.")
    end
end

-- === O RESET QUE NÃO TRAVA E NÃO LIMPA A LOJA ===
-- === O RESET QUE NÃO TRAVA E NÃO LIMPA A LOJA ===
function reset()
    buttonConfigs = {}
    buttonOrder = {}
    
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    local optionsPanel = optionsController.ui.onPanel.options
    
    local function clearPanel(panel)
        if not panel then return end
        for _, button in ipairs(panel:getChildren()) do
            if button.originalPanel ~= "specials" then
                local id = button:getId()
                if id then
                    -- A MÁGICA DO RESET: Puxa todos os botões escondidos de volta para a tela
                    button:setVisible(true) 
                    
                    buttonConfigs[id] = {
                        visible = true,
                        tooltip = button:getTooltip() or id
                    }
                    table.insert(buttonOrder, id)
                end
            end
        end
    end
    
    clearPanel(optionsPanel)
    clearPanel(rightGamePanel)
    
    saveButtonConfig()
    updateDisplayedButtonsList()
    updateAvailableButtonsList()
    reorderButtons()
    reloadMainPanelSizes()
end

function initControlButtons()
    local config = loadButtonConfig()
    buttonConfigs = config.buttons or {}
    buttonOrder = config.order or {}
    local currentButtons = {}
    
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    local optionsPanel = optionsController.ui.onPanel.options
    local targetPanel = (modules.game_interface.currentViewMode == 2) and rightGamePanel or optionsPanel

    for _, button in ipairs(targetPanel:getChildren()) do
        if button.originalPanel ~= "specials" then
            local id = button:getId()
            if id then
                currentButtons[id] = true
                if not buttonConfigs[id] then
                    -- A MÁGICA: Botões novos nascem 100% visíveis por padrão!
                    buttonConfigs[id] = {
                        visible = true,
                        tooltip = button:getTooltip() or id
                    }
                    table.insert(buttonOrder, id)
                    button:setVisible(true)
                else
                    button:setVisible(buttonConfigs[id].visible)
                end
            end
        end
    end

    local toRemove = {}
    for id in pairs(buttonConfigs) do
        if not currentButtons[id] then
            table.insert(toRemove, id)
        end
    end

    for _, id in ipairs(toRemove) do
        buttonConfigs[id] = nil
        for i, orderId in ipairs(buttonOrder) do
            if orderId == id then
                table.remove(buttonOrder, i)
                break
            end
        end
    end
    updateDisplayedButtonsList()
    updateAvailableButtonsList()
    reorderButtons()
    reloadMainPanelSizes()
end
