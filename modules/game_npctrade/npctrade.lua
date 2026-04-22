BUY = 1
SELL = 2
CURRENCY = 'gold'
CURRENCY_DECIMAL = false
WEIGHT_UNIT = 'oz'
LAST_INVENTORY = 10

npcWindow = nil
itemsPanel = nil
radioTabs = nil
radioItems = nil
searchText = nil
setupPanel = nil
quantity = nil
quantityScroll = nil
nameLabel = nil
priceLabel = nil
moneyLabel = nil
weightDesc = nil
weightLabel = nil
capacityDesc = nil
capacityLabel = nil
tradeButton = nil
buyTab = nil
sellTab = nil
initialized = false

showWeight = true
buyWithBackpack = nil
ignoreCapacity = nil
ignoreEquipped = nil
showAllItems = nil
sellAllButton = nil

playerFreeCapacity = 0
playerMoney = 0
tradeItems = {}
playerItems = {}
selectedItem = nil

cancelNextRelease = nil

function init()
    npcWindow = g_ui.displayUI('npctrade')
    npcWindow:setVisible(false)

    itemsPanel = npcWindow:recursiveGetChildById('itemsPanel')
    searchText = npcWindow:recursiveGetChildById('searchText')

    setupPanel = npcWindow:recursiveGetChildById('setupPanel')
    quantityScroll = setupPanel:getChildById('quantityScroll')
    nameLabel = setupPanel:getChildById('name')
    priceLabel = setupPanel:getChildById('price')
    moneyLabel = setupPanel:getChildById('money')
    weightDesc = setupPanel:getChildById('weightDesc')
    weightLabel = setupPanel:getChildById('weight')
    capacityDesc = setupPanel:getChildById('capacityDesc')
    capacityLabel = setupPanel:getChildById('capacity')
    tradeButton = npcWindow:recursiveGetChildById('tradeButton')

    buyWithBackpack = npcWindow:recursiveGetChildById('buyWithBackpack')
    ignoreCapacity = npcWindow:recursiveGetChildById('ignoreCapacity')
    ignoreEquipped = npcWindow:recursiveGetChildById('ignoreEquipped')
    showAllItems = npcWindow:recursiveGetChildById('showAllItems')
    sellAllButton = npcWindow:recursiveGetChildById('sellAllButton')

    buyTab = npcWindow:getChildById('buyTab')
    sellTab = npcWindow:getChildById('sellTab')

    radioTabs = UIRadioGroup.create()
    radioTabs:addWidget(buyTab)
    radioTabs:addWidget(sellTab)
    radioTabs:selectWidget(buyTab)
    radioTabs.onSelectionChange = onTradeTypeChange

    cancelNextRelease = false

    if g_game.isOnline() then
        playerFreeCapacity = g_game.getLocalPlayer():getFreeCapacity()
    end

    connect(g_game, {
        onGameEnd = hide,
        onOpenNpcTrade = onOpenNpcTrade,
        onCloseNpcTrade = onCloseNpcTrade,
        onPlayerGoods = onPlayerGoods
    })

    connect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onInventoryChange = onInventoryChange
    })

    initialized = true
end

function terminate()
    initialized = false
    npcWindow:destroy()

    disconnect(g_game, {
        onGameEnd = hide,
        onOpenNpcTrade = onOpenNpcTrade,
        onCloseNpcTrade = onCloseNpcTrade,
        onPlayerGoods = onPlayerGoods
    })

    disconnect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onInventoryChange = onInventoryChange
    })
end

function show()
    if g_game.isOnline() then
        if #tradeItems[BUY] > 0 then
            radioTabs:selectWidget(buyTab)
        else
            radioTabs:selectWidget(sellTab)
        end

        npcWindow:show()
        npcWindow:raise()
        npcWindow:focus()
    end
end

function hide()
    npcWindow:hide()
end

function onItemBoxChecked(widget)
    if widget:isChecked() then
        local item = widget.item
        selectedItem = item
        refreshItem(item)
        tradeButton:enable()

        if getCurrentTradeType() == SELL then
            quantityScroll:setValue(quantityScroll:getMaximum())
        end
    end
end

function onQuantityValueChange(quantity)
    if selectedItem then
        weightLabel:setText(string.format('%.2f', selectedItem.weight * quantity) .. ' ' .. WEIGHT_UNIT)
        priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
    end
end

function onTradeTypeChange(radioTabs, selected, deselected)
    tradeButton:setText(selected:getText())
    selected:setOn(true)
    deselected:setOn(false)

    local currentTradeType = getCurrentTradeType()
    buyWithBackpack:setVisible(currentTradeType == BUY)
    ignoreCapacity:setVisible(currentTradeType == BUY)
    ignoreEquipped:setVisible(currentTradeType == SELL)
    showAllItems:setVisible(currentTradeType == SELL)
    sellAllButton:setVisible(currentTradeType == SELL)

    refreshTradeItems()
    refreshPlayerGoods()
end

function onTradeClick()
    if getCurrentTradeType() == BUY then
        g_game.buyItem(selectedItem.ptr, quantityScroll:getValue(), ignoreCapacity:isChecked(),
                       buyWithBackpack:isChecked())
    else
        g_game.sellItem(selectedItem.ptr, quantityScroll:getValue(), ignoreEquipped:isChecked())
    end
end

function onSearchTextChange()
    refreshPlayerGoods()
end

function itemPopup(self, mousePosition, mouseButton)
    if cancelNextRelease then
        cancelNextRelease = false
        return false
    end

    local item = self:getItem()
    if not item then return false end
    
    local itemId = item:getId()

    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        
        -- Look option
        menu:addOption(tr('Look'), function()
            return g_game.inspectNpcTrade(item)
        end)
        
        -- Super Trader Blacklist options
        if modules.game_supertrader and itemId then
            menu:addSeparator()
            
            if modules.game_supertrader.isBlacklisted(itemId) then
                menu:addOption(tr('Remove from Sell Blacklist'), function()
                    modules.game_supertrader.removeFromBlacklist(itemId)
                end)
            else
                menu:addOption(tr('Add to Sell Blacklist'), function()
                    modules.game_supertrader.addToBlacklist(itemId)
                end)
            end
            
            menu:addOption(tr('View Blacklist'), function()
                modules.game_supertrader.showBlacklistWindow()
            end)
        end
        
        menu:display(mousePosition)
        return true
    elseif ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or
        (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
        cancelNextRelease = true
        g_game.inspectNpcTrade(item)
        return true
    end
    return false
end

function onBuyWithBackpackChange()
    if selectedItem then
        refreshItem(selectedItem)
    end
end

function onIgnoreCapacityChange()
    refreshPlayerGoods()
end

function onIgnoreEquippedChange()
    refreshPlayerGoods()
end

function onShowAllItemsChange()
    refreshPlayerGoods()
end

function setCurrency(currency, decimal)
    CURRENCY = currency
    CURRENCY_DECIMAL = decimal
end

function setShowWeight(state)
    showWeight = state
    weightDesc:setVisible(state)
    weightLabel:setVisible(state)
end

function setShowYourCapacity(state)
    capacityDesc:setVisible(state)
    capacityLabel:setVisible(state)
    ignoreCapacity:setVisible(state)
end

function clearSelectedItem()
    nameLabel:clearText()
    weightLabel:clearText()
    priceLabel:clearText()
    tradeButton:disable()
    quantityScroll:setMinimum(0)
    quantityScroll:setMaximum(0)
    if selectedItem then
        radioItems:selectWidget(nil)
        selectedItem = nil
    end
end

function getCurrentTradeType()
    if tradeButton:getText() == tr('Buy') then
        return BUY
    else
        return SELL
    end
end

function getItemPrice(item, single)
    local amount = 1
    local single = single or false
    if not single then
        amount = quantityScroll:getValue()
    end
    if getCurrentTradeType() == BUY then
        if buyWithBackpack:isChecked() then
            if item.ptr:isStackable() then
                return item.price * amount + 20
            else
                return item.price * amount + math.ceil(amount / 20) * 20
            end
        end
    end
    return item.price * amount
end

function getSellQuantity(item)
    if not item or not playerItems[item:getId()] then
        return 0
    end
    local removeAmount = 0
    if ignoreEquipped:isChecked() then
        local localPlayer = g_game.getLocalPlayer()
        for i = 1, LAST_INVENTORY do
            local inventoryItem = localPlayer:getInventoryItem(i)
            if inventoryItem and inventoryItem:getId() == item:getId() then
                removeAmount = removeAmount + inventoryItem:getCount()
            end
        end
    end
    return playerItems[item:getId()] - removeAmount
end

function canTradeItem(item)
    if getCurrentTradeType() == BUY then
        return
            (ignoreCapacity:isChecked() or (not ignoreCapacity:isChecked() and playerFreeCapacity >= item.weight)) and
                playerMoney >= getItemPrice(item, true)
    else
        return getSellQuantity(item.ptr) > 0
    end
end

function refreshItem(item)
    nameLabel:setText(item.name)

    if getCurrentTradeType() == BUY then
        local capacityMaxCount = math.floor(playerFreeCapacity / item.weight)
        if ignoreCapacity:isChecked() then
            capacityMaxCount = 65535
        end
        local priceMaxCount = math.floor(playerMoney / getItemPrice(item, true))
        local finalCount = math.max(0, math.min(getMaxAmount(), math.min(priceMaxCount, capacityMaxCount)))
        quantityScroll:setMinimum(1)
        quantityScroll:setMaximum(finalCount)
    else
        quantityScroll:setMinimum(1)
        quantityScroll:setMaximum(math.max(0, math.min(getMaxAmount(), getSellQuantity(item.ptr))))
    end

    onQuantityValueChange(quantityScroll:getValue())

    setupPanel:enable()
end

function refreshTradeItems()
    local layout = itemsPanel:getLayout()
    layout:disableUpdates()

    clearSelectedItem()

    searchText:clearText()
    setupPanel:disable()
    itemsPanel:destroyChildren()

    if radioItems then
        radioItems:destroy()
    end
    radioItems = UIRadioGroup.create()

    local currentTradeType = getCurrentTradeType()
    local currentTradeItems = tradeItems[currentTradeType]
    
    if not currentTradeItems then
        g_logger.info("[npctrade] refreshTradeItems() called but no trade items for type=" .. tostring(currentTradeType))
        layout:enableUpdates()
        layout:update()
        return
    end
    
    local hiddenCount = 0
    local shownCount = 0
    
    g_logger.info("[npctrade] refreshTradeItems() called, type=" .. currentTradeType .. ", total trade items=" .. #currentTradeItems)
    
    for key, item in pairs(currentTradeItems) do
        -- Filter blacklisted items in SELL tab
        if currentTradeType == SELL then
            if modules.game_supertrader then
                local itemId = item.ptr and item.ptr:getId()
                if itemId and modules.game_supertrader.isBlacklisted(itemId) then
                    g_logger.info("[npctrade] Hiding blacklisted item: " .. itemId .. " (" .. item.name .. ")")
                    hiddenCount = hiddenCount + 1
                    -- Skip this item (don't show in list)
                else
                    shownCount = shownCount + 1
                    local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
                    itemBox.item = item

                    local text = ''
                    local name = item.name
                    text = text .. name
                    if showWeight then
                        local weight = string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
                        text = text .. '\n' .. weight
                    end
                    local price = formatCurrency(item.price)
                    text = text .. '\n' .. price
                    itemBox:setText(text)

                    local itemWidget = itemBox:getChildById('item')
                    itemWidget:setItem(item.ptr)
                    itemWidget.onMouseRelease = itemPopup

                    radioItems:addWidget(itemBox)
                end
            else
                shownCount = shownCount + 1
                local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
                itemBox.item = item

                local text = ''
                local name = item.name
                text = text .. name
                if showWeight then
                    local weight = string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
                    text = text .. '\n' .. weight
                end
                local price = formatCurrency(item.price)
                text = text .. '\n' .. price
                itemBox:setText(text)

                local itemWidget = itemBox:getChildById('item')
                itemWidget:setItem(item.ptr)
                itemWidget.onMouseRelease = itemPopup

                radioItems:addWidget(itemBox)
            end
        else
            shownCount = shownCount + 1
            local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
            itemBox.item = item

            local text = ''
            local name = item.name
            text = text .. name
            if showWeight then
                local weight = string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
                text = text .. '\n' .. weight
            end
            local price = formatCurrency(item.price)
            text = text .. '\n' .. price
            itemBox:setText(text)

            local itemWidget = itemBox:getChildById('item')
            itemWidget:setItem(item.ptr)
            itemWidget.onMouseRelease = itemPopup

            radioItems:addWidget(itemBox)
        end
    end

    g_logger.info("[npctrade] refreshTradeItems() complete: shown=" .. shownCount .. ", hidden=" .. hiddenCount)

    layout:enableUpdates()
    layout:update()
end

function refreshPlayerGoods()
    if not initialized then
        return
    end

    checkSellAllTooltip()

    moneyLabel:setText(formatCurrency(playerMoney))
    capacityLabel:setText(string.format('%.2f', playerFreeCapacity) .. ' ' .. WEIGHT_UNIT)

    local currentTradeType = getCurrentTradeType()
    local searchFilter = searchText:getText():lower()
    local foundSelectedItem = false

    local items = itemsPanel:getChildCount()
    for i = 1, items do
        local itemWidget = itemsPanel:getChildByIndex(i)
        local item = itemWidget.item

        local canTrade = canTradeItem(item)
        itemWidget:setOn(canTrade)
        itemWidget:setEnabled(canTrade)

        local searchCondition = (searchFilter == '') or
                                    (searchFilter ~= '' and string.find(item.name:lower(), searchFilter) ~= nil)
        local showAllItemsCondition = (currentTradeType == BUY) or (showAllItems:isChecked()) or
                                          (currentTradeType == SELL and not showAllItems:isChecked() and canTrade)
        itemWidget:setVisible(searchCondition and showAllItemsCondition)

        if selectedItem == item and itemWidget:isEnabled() and itemWidget:isVisible() then
            foundSelectedItem = true
        end
    end

    if not foundSelectedItem then
        clearSelectedItem()
    end

    if selectedItem then
        refreshItem(selectedItem)
    end
end

function onOpenNpcTrade(items)
    tradeItems[BUY] = {}
    tradeItems[SELL] = {}

    for key, item in pairs(items) do
        if item[4] > 0 then
            local newItem = {}
            newItem.ptr = item[1]
            newItem.name = item[2]
            newItem.weight = item[3] / 100
            newItem.price = item[4]
            table.insert(tradeItems[BUY], newItem)
        end

        if item[5] > 0 then
            local newItem = {}
            newItem.ptr = item[1]
            newItem.name = item[2]
            newItem.weight = item[3] / 100
            newItem.price = item[5]
            table.insert(tradeItems[SELL], newItem)
        end
    end

    refreshTradeItems()
    addEvent(show) -- player goods has not been parsed yet
    
    -- Safety net: refresh sell tab after a short delay to ensure blacklist module is ready
    scheduleEvent(function()
        if getCurrentTradeType() == SELL then
            refreshTradeItems()
            refreshPlayerGoods()
        end
    end, 200)
end

function closeNpcTrade()
    g_game.closeNpcTrade()
    hide()
end

function onCloseNpcTrade()
    hide()
end

function onPlayerGoods(money, items)
    playerMoney = money

    playerItems = {}
    for key, item in pairs(items) do
        local id = item[1]:getId()
        if not playerItems[id] then
            playerItems[id] = item[2]
        else
            playerItems[id] = playerItems[id] + item[2]
        end
    end

    refreshPlayerGoods()
end

function onFreeCapacityChange(localPlayer, freeCapacity, oldFreeCapacity)
    playerFreeCapacity = freeCapacity

    if npcWindow:isVisible() then
        refreshPlayerGoods()
    end
end

function onInventoryChange(inventory, item, oldItem)
    refreshPlayerGoods()
end

function getTradeItemData(id, type)
    if table.empty(tradeItems[type]) then
        return false
    end

    if type then
        for key, item in pairs(tradeItems[type]) do
            if item.ptr and item.ptr:getId() == id then
                return item
            end
        end
    else
        for _, items in pairs(tradeItems) do
            for key, item in pairs(items) do
                if item.ptr and item.ptr:getId() == id then
                    return item
                end
            end
        end
    end
    return false
end

function checkSellAllTooltip()
    sellAllButton:setEnabled(true)
    sellAllButton:removeTooltip()

    local total = 0
    local info = ''
    local first = true

    for key, amount in pairs(playerItems) do
        local data = getTradeItemData(key, SELL)
        if data then
            amount = getSellQuantity(data.ptr)
            if amount > 0 then
                if data and amount > 0 then
                    info = info .. (not first and '\n' or '') .. amount .. ' ' .. data.name .. ' (' .. data.price *
                               amount .. ' gold)'

                    total = total + (data.price * amount)
                    if first then
                        first = false
                    end
                end
            end
        end
    end
    if info ~= '' then
        info = info .. '\nTotal: ' .. total .. ' gold'
        sellAllButton:setTooltip(info)
    else
        sellAllButton:setEnabled(false)
    end
end

function formatCurrency(amount)
    if CURRENCY_DECIMAL then
        return string.format('%.02f', amount / 100.0) .. ' ' .. CURRENCY
    else
        return amount .. ' ' .. CURRENCY
    end
end

function getMaxAmount()
    if getCurrentTradeType() == SELL and g_game.getFeature(GameDoubleShopSellAmount) then
        return 10000
    end
    return 100
end

function sellAll()
    g_logger.info("[npctrade] Sell All started")
    
    -- Collect all items to sell first
    local itemsToSell = {}
    local skippedCount = 0
    
    for itemId, count in pairs(playerItems) do
        -- Check blacklist
        if modules.game_supertrader and modules.game_supertrader.isBlacklisted(itemId) then
            skippedCount = skippedCount + 1
            g_logger.info("[npctrade] Skipping blacklisted item: " .. itemId)
            goto continue
        end
        
        -- Get trade data (contains the real item pointer from server)
        local tradeData = getTradeItemData(itemId, SELL)
        if tradeData and tradeData.ptr then
            local amount = getSellQuantity(tradeData.ptr)
            if amount > 0 then
                table.insert(itemsToSell, {
                    id = itemId,
                    ptr = tradeData.ptr,
                    amount = amount,
                    price = tradeData.price * amount
                })
            end
        else
            g_logger.warning("[npctrade] No trade data found for item " .. itemId)
        end
        
        ::continue::
    end
    
    if #itemsToSell == 0 then
        if modules.game_textmessage then
            modules.game_textmessage.displayGameMessage("Sell All: No items to sell.")
        end
        return
    end
    
    -- Sell items sequentially with delay
    local currentIndex = 1
    local soldCount = 0
    local totalGold = 0
    
    local function sellNextItem()
        if currentIndex > #itemsToSell then
            -- All done - show summary
            local msg = "Sell All: " .. soldCount .. " items sold"
            if skippedCount > 0 then
                msg = msg .. ", " .. skippedCount .. " blacklisted items skipped"
            end
            msg = msg .. " (Total: " .. totalGold .. " gold)"
            
            if modules.game_textmessage then
                modules.game_textmessage.displayGameMessage(msg)
            end
            if modules.game_console then
                modules.game_console.addText(msg, nil, "Server Log")
            end
            g_logger.info("[npctrade] Sell All completed: " .. soldCount .. " items, " .. skippedCount .. " skipped, " .. totalGold .. " gold")
            return
        end
        
        local itemData = itemsToSell[currentIndex]
        currentIndex = currentIndex + 1
        
        -- Double-check blacklist before selling (may have changed)
        if modules.game_supertrader and modules.game_supertrader.isBlacklisted(itemData.id) then
            g_logger.info("[npctrade] Item " .. itemData.id .. " was blacklisted during Sell All, skipping")
            sellNextItem() -- Skip and continue immediately
            return
        end
        
        -- Sell using the real trade item pointer
        if g_game and g_game.isOnline() and itemData.ptr then
            g_logger.info("[npctrade] Selling item " .. itemData.id .. " x" .. itemData.amount)
            g_game.sellItem(itemData.ptr, itemData.amount, ignoreEquipped:isChecked())
            soldCount = soldCount + 1
            totalGold = totalGold + itemData.price
        else
            g_logger.warning("[npctrade] Cannot sell item " .. itemData.id .. " - no valid pointer or not online")
        end
        
        -- Schedule next item with 100ms delay
        scheduleEvent(sellNextItem, 100)
    end
    
    -- Start selling
    sellNextItem()
end
