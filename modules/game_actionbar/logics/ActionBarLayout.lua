-- === SISTEMA DE MINIMIZAR ACTION BARS ===
modules.game_actionbar.toggleActionBar = function(actionBar)
    if not actionBar then return end
    
    if actionBar.isMinimized then
        -- RESTAURAR (Traz o fundo e as magias de volta)
        actionBar.isMinimized = false
        actionBar.tabBar:show()
        if actionBar.prevPanel then actionBar.prevPanel:show() end
        
        if actionBar.isVertical then
            actionBar:setHeight(300)
        else
            actionBar:setWidth(400)
        end
        modules.game_actionbar.updateVisibleWidgets()
    else
        -- MINIMIZAR (Some com as magias, deixa só a bordinha dos botões)
        actionBar.isMinimized = true
        actionBar.tabBar:hide()
        if actionBar.prevPanel then actionBar.prevPanel:hide() end
        
        if actionBar.isVertical then
            actionBar:setHeight(34) 
        else
            actionBar:setWidth(17) 
        end
    end
end

local function createActionBars()
    local rootPanel = modules.game_interface.getRootPanel()
    
    for i = 1, 9 do
        local layout = (i <= 3) and '/modules/game_actionbar/otui/actionbar' or '/modules/game_actionbar/otui/sideactionbar'
        local isVertical = (i > 3)
        
        actionBars[i] = g_ui.loadUI(layout, rootPanel)
        actionBars[i]:setId("actionbar." .. i)
        actionBars[i].n = i
        actionBars[i].isVertical = isVertical
        
        -- Quebra as âncoras para não auto-alinhar
        actionBars[i]:removeAnchor(AnchorTop)
        actionBars[i]:removeAnchor(AnchorBottom)
        actionBars[i]:removeAnchor(AnchorLeft)
        actionBars[i]:removeAnchor(AnchorRight)
        actionBars[i]:removeAnchor(AnchorHorizontalCenter)
        actionBars[i]:removeAnchor(AnchorVerticalCenter)
        
        -- Define os tamanhos com a borda de arrasto
        if isVertical then
            actionBars[i]:setHeight(300)
            actionBars[i]:setWidth(44)
        else
            actionBars[i]:setWidth(400)
            actionBars[i]:setHeight(44)
        end
        
        -- Carrega posição salva ou define a padrão
        local savedPos = ApiJson.getBarPosition(i)
        if savedPos then
            actionBars[i]:setPosition(savedPos)
        else
            local rootSize = rootPanel:getSize()
            if i <= 3 then
                actionBars[i]:setPosition({x = (rootSize.width / 2) - 200, y = rootSize.height - 100 - (i * 45)})
            elseif i <= 6 then
                actionBars[i]:setPosition({x = 50 + ((i - 3) * 45), y = (rootSize.height / 2) - 150})
            else
                actionBars[i]:setPosition({x = rootSize.width - 100 - ((i - 6) * 45), y = (rootSize.height / 2) - 150})
            end
        end

        -- Habilita a propriedade básica
        actionBars[i]:setDraggable(true)

        local handle = actionBars[i]:getChildById('dragHandle')
        if handle then
            handle.onDragEnter = function(widget, mousePos)
                -- O Handle intercepta e ordena que o PAI (a ActionBar) inicie o arraste
                return UIWindow.onDragEnter(actionBars[i], mousePos)
            end

            handle.onDragMove = function(widget, mousePos, mouseMoved)
                -- O Handle delega a continuidade do movimento nativamente para puxar as coordenadas do PAI
                return UIWindow.onDragMove(actionBars[i], mousePos, mouseMoved)
            end
        end

        -- Gatilho de salvar posição
        actionBars[i].onPositionChange = function(widget)
            if widget:getX() > 0 and widget:getY() > 0 then
                ApiJson.saveBarPosition(i, widget:getPosition())
                g_settings.save()
            end
        end
    end -- Fim do laço 'for'

    -- Oculta resíduos da interface antiga (Cadeados e Barras finas)
    local root = modules.game_interface.getRootPanel()
    local lock1 = root:recursiveGetChildById('bottomLockPanel')
    if lock1 then lock1:hide() end
    local lock2 = root:recursiveGetChildById('leftLockPanel')
    if lock2 then lock2:hide() end
    local lock3 = root:recursiveGetChildById('rightLockPanel')
    if lock3 then lock3:hide() end

end -- Fim exato da função createActionBars

function onCreateActionBars()

    if #actionBars ~= 0 then

        return true

    end

    local gameMapPanel = modules.game_interface.gameMapPanel

    if not gameMapPanel then

        return true

    end

    if #actionBars == 0 then

        createActionBars()

    end

    activeActionBars = {}

    for i = 1, #actionBars do

        local actionbar = actionBars[i]

        local barState = ApiJson.getActionBar(i) or {}

        local enabled = barState.isVisible and true or false

        actionbar:setVisible(enabled)

        actionbar:setOn(enabled)

        setupActionBar(i)

        if enabled then

            addActiveActionBar(actionbar)

        end

    end

    resizeLockButtons()

end



local function updateLockIcon(button, optionKey)

    if not button then

        return

    end

    local locked = ApiJson.getClientOption(optionKey) and true or false

    button:setIcon(locked and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")

end



local function getFirstVisibleButton(actionBar)

    for _, button in ipairs(actionBar.tabBar:getChildren()) do

        if button:isVisible() then

            return button

        end

    end

    return nil

end



local function getPrevInvisibleButton(actionBar)

    local lastButton = nil

    for _, button in ipairs(actionBar.tabBar:getChildren()) do

        if button:isVisible() then

            return lastButton

        end

        lastButton = button

    end

    return nil

end



local function getLastVisibleButton(actionBar)

    for _, button in ipairs(actionBar.tabBar:getReverseChildren()) do

        if button:isVisible() then

            return button

        end

    end

    return nil

end



local function getNextInvisibleChild(actionBar, firstIndex)

    for i, button in ipairs(actionBar.tabBar:getChildren()) do

        if i >= firstIndex and not button:isVisible() then

            return button

        end

    end

    return nil

end



function resizeLockButtons()
    -- Como as Action Bars agora são flutuantes, os painéis cinzas de cadeado tornaram-se obsoletos.
    -- Zeramos seus tamanhos e os deixamos invisíveis para manter o mapa Widescreen limpo.
    
    local rightLockPanel = modules.game_interface.getRightLockPanel()
    if rightLockPanel then
        rightLockPanel:setWidth(0)
        rightLockPanel:setVisible(false)
        if rightLockPanel:getParent() then rightLockPanel:getParent():setWidth(0) end
    end
    
    local bottomLockPanel = modules.game_interface.getBottomLockPanel()
    if bottomLockPanel then
        bottomLockPanel:setHeight(0)
        bottomLockPanel:setVisible(false)
    end
    
    local leftLockPanel = modules.game_interface.getLeftLockPanel()
    if leftLockPanel then
        leftLockPanel:setWidth(0)
        leftLockPanel:setVisible(false)
        if leftLockPanel:getParent() then leftLockPanel:getParent():setWidth(0) end
    end
end



function updateVisibleWidgets()

    for _, actionBar in pairs(actionBars) do

        if actionBar:isVisible() then

            local tabBar = actionBar.tabBar

            local children = tabBar:getChildren()

            local dimension = actionBar.isVertical and tabBar:getHeight() or tabBar:getWidth()

            local visibleCount = math.max(1, math.floor(dimension / 36))

            local firstIndex = actionBar.firstVisibleIndex or 1

            local totalChildren = #children

           

            -- If we can show all buttons, start from the beginning

            if visibleCount >= totalChildren then

                firstIndex = 1

            else

                -- Check if we're currently at or past the end

                local currentLastVisible = firstIndex + visibleCount - 1

               

                if currentLastVisible > totalChildren then

                    -- We're past the end, pull back to show the last N buttons

                    firstIndex = math.max(1, totalChildren - visibleCount + 1)

                elseif currentLastVisible < totalChildren then

                    -- We're not at the end yet, but check if window got bigger

                    -- and we can show more buttons by moving forward

                    local optimalFirstIndex = math.max(1, totalChildren - visibleCount + 1)

                   

                    -- If we were previously at the end and window got bigger,

                    -- or if we can move forward to show more without losing current view

                    if firstIndex > optimalFirstIndex then

                        -- Keep current position, we have space ahead

                    else

                        -- Try to show more at the end if we have space

                        local newFirstIndex = math.min(firstIndex, optimalFirstIndex)

                        firstIndex = newFirstIndex

                    end

                end

               

                -- Final bounds check

                firstIndex = math.max(1, math.min(firstIndex, totalChildren - visibleCount + 1))

            end

           

            -- Update the action bar's stored indices

            actionBar.firstVisibleIndex = firstIndex

           

            -- Apply visibility to buttons

            for i, button in ipairs(children) do

                if i >= firstIndex and i < firstIndex + visibleCount then

                    button:setVisible(true)

                    actionBar.lastVisibleIndex = i

                else

                    button:setVisible(false)

                end

            end

            -- Update navigation button states

            local prevEnabled = firstIndex > 1

            local nextEnabled = (firstIndex + visibleCount - 1) < totalChildren

           

            if actionBar.prevPanel then

                if actionBar.prevPanel.prev then actionBar.prevPanel.prev:setOn(prevEnabled) end

                if actionBar.prevPanel.first then actionBar.prevPanel.first:setOn(prevEnabled) end

            end

            if actionBar.nextPanel then

                if actionBar.nextPanel.next then actionBar.nextPanel.next:setOn(nextEnabled) end

                if actionBar.nextPanel.last then actionBar.nextPanel.last:setOn(nextEnabled) end

            end

        end

    end

end



function moveActionButtons(widget)

    local dir = widget:getId()

    local actionBar = widget:getParent():getParent()

    local scroll = actionBar.actionScroll

    local tabBar = actionBar.tabBar

    local buttons = {actionBar.prevPanel.prev, actionBar.prevPanel.first, actionBar.nextPanel.next,

                     actionBar.nextPanel.last}

    local children = tabBar:getChildren()

    local reverseChildren = tabBar.getReverseChildren and tabBar:getReverseChildren() or {}

    local dimension = actionBar.isVertical and tabBar:getHeight() or tabBar:getWidth()

    local visibleCount = math.max(1, math.floor(dimension / 36))

    if dir == "next" then

        local firstVisible = getFirstVisibleButton(actionBar)

        if not firstVisible then

            return

        end

        local firstIndex = tabBar:getChildIndex(firstVisible)

        local nextInvisible = getNextInvisibleChild(actionBar, firstIndex)

        if not nextInvisible then

            return

        end

        firstVisible:setVisible(false)

        nextInvisible:setVisible(true)

        scroll:increment(36)

        actionBar.firstVisibleIndex = tabBar:getChildIndex(firstVisible) + 1

        actionBar.lastVisibleIndex = tabBar:getChildIndex(nextInvisible)

    elseif dir == "prev" then

        local prevInvisible = getPrevInvisibleButton(actionBar)

        local lastVisible = getLastVisibleButton(actionBar)

        if not prevInvisible then

            return

        end

        prevInvisible:setVisible(true)

        lastVisible:setVisible(false)

        scroll:decrement(36)

        actionBar.firstVisibleIndex = tabBar:getChildIndex(prevInvisible)

        actionBar.lastVisibleIndex = tabBar:getChildIndex(lastVisible) - 1

    elseif dir == "first" then

        for i, button in ipairs(children) do

            button:setVisible(i <= visibleCount)

        end

        actionBar.firstVisibleIndex = 1

        actionBar.lastVisibleIndex = tabBar:getChildIndex(getLastVisibleButton(actionBar))

        scroll:setValue(scroll:getMinimum())

    elseif dir == "last" then

        for i, button in ipairs(reverseChildren) do

            button:setVisible(i <= visibleCount)

        end

        actionBar.firstVisibleIndex = tabBar:getChildIndex(getFirstVisibleButton(actionBar))

        actionBar.lastVisibleIndex = #children

        scroll:setValue(scroll:getMaximum())

    end



    local prevEnabled = actionBar.firstVisibleIndex ~= 1

    local nextEnabled = actionBar.lastVisibleIndex ~= #children

    buttons[1]:setOn(prevEnabled)

    buttons[2]:setOn(prevEnabled)

    buttons[3]:setOn(nextEnabled)

    buttons[4]:setOn(nextEnabled)

end



function changeLockStatus(button, barType)

    local barData = {

        ["Bottom"] = {

            option = "actionBarBottomLocked",

            startPos = 1,

            endPos = 3

        },

        ["Left"] = {

            option = "actionBarLeftLocked",

            startPos = 4,

            endPos = 6

        },

        ["Right"] = {

            option = "actionBarRightLocked",

            startPos = 7,

            endPos = 9

        }

    }

    local data = barData[barType]

    if not data then

        return true

    end

    ApiJson.toggleLockGroup(data.option, data.startPos, data.endPos)

    for i = data.startPos, data.endPos do

        actionBars[i].locked = ApiJson.isBarLocked(i)

    end

    updateLockIcon(button, data.option)

end



function unbindActionBarEvent(actionbar)

    for _, button in pairs(actionbar.tabBar:getChildren()) do

        if button.cache and button.cache.hotkey then

            unbindHotkey(button.cache.hotkey)

        end

        if button.cache.cooldownEvent then

            removeEvent(button.cache.cooldownEvent)

        end

        resetButtonCache(button)

    end

end