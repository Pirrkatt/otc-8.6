local categoryMap = {
  itemCategory = 1,
  outfitCategory = 2,
  specialCategory = 3,
  cosmeticsCategory = 4,
  labelsCategory = 5,
  aurasCategory = 6,
  shadersCategory = 7,
  furnitureCategory = 8,
}

-- private variables
local SHOP_EXTENTED_OPCODE = 201

shop = nil
transferWindow = nil
local otcv8shop = false
local shopButton = nil
local msgWindow = nil
local selectedWindow = nil
local browsingHistory = false
local transferValue = 0
local changeCost

-- for classic store
local storeUrl = ""
local coinsPacketSize = 0

local CATEGORIES = {}
local HISTORY = {}
local STATUS = {}

local selectedOffer = {}

local function sendAction(action, data)
  if not g_game.getFeature(GameExtendedOpcode) then
    return
  end
  
  local protocolGame = g_game.getProtocolGame()
  if data == nil then
    data = {}
  end
  if protocolGame then
    protocolGame:sendExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, {action = action, data = data})
  end  
end

-- public functions
function init()
  connect(g_game, {
    onGameStart = check, 
    onGameEnd = hide,
    onStoreInit = onStoreInit,
    onStoreCategories = onStoreCategories,
    onStoreOffers = onStoreOffers,
    onStoreTransactionHistory = onStoreTransactionHistory,    
    onStorePurchase = onStorePurchase,
    onStoreError = onStoreError,
    onCoinBalance = onCoinBalance    
  })

  ProtocolGame.registerExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)
  
  if g_game.isOnline() then
    check()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = check, 
    onGameEnd = hide,
    onStoreInit = onStoreInit,
    onStoreCategories = onStoreCategories,
    onStoreOffers = onStoreOffers,
    onStoreTransactionHistory = onStoreTransactionHistory,    
    onStorePurchase = onStorePurchase,
    onStoreError = onStoreError,
    onCoinBalance = onCoinBalance    
  })

  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)

  if shopButton then
    shopButton:destroy()
    shopButton = nil
  end
  if shop then
    disconnect(shop.categoryPanel, { onChildFocusChange = changeCategory })
    shop:destroy()
    shop = nil
  end
  if msgWindow then
    msgWindow:destroy()
  end
  if selectedWindow then
    selectedWindow:destroy()
    selectedWindow = nil
  end
end

function check()
  otcv8shop = false
  sendAction("init")
end

function hide()
  if not shop then
    return
  end
  shop:hide()
end

function show()
  if not shop or not shopButton then
    return
  end
  if g_game.getFeature(GameIngameStore) then
    g_game.openStore(0)
  end

  shop:show()
  shop:raise()
  shop:focus()
end

function toggle()
  if not shop then
    return
  end
  if shop:isVisible() then
    return hide()
  end
  show()
  check()
end

function createShop()
  if shop then return end
  shop = g_ui.displayUI('shop')
  shop:hide()
  shopButton = modules.client_topmenu.addRightGameToggleButton('shopButton', tr('Shop'), '/images/topbuttons/shop', toggle, false, 8)
  connect(shop.categoryPanel, { onChildFocusChange = changeCategory })
end

function onStoreInit(url, coins)
  if otcv8shop then return end
  storeUrl = url
  if storeUrl:len() > 0 then
    if storeUrl:sub(storeUrl:len(), storeUrl:len()) ~= "/" then
      storeUrl = storeUrl .. "/"
    end
    storeUrl = storeUrl .. "64/"
    if storeUrl:sub(1, 4):lower() ~= "http" then
      storeUrl = "http://" .. storeUrl
    end
  end
  coinsPacketSize = coins
  createShop()
end

function onStoreCategories(categories)
  if not shop or otcv8shop then return end
  local correctCategories = {}
  for i, category in ipairs(categories) do
    local image = ""
    if category.icon:len() > 0 then
      image = storeUrl .. category.icon
    end
    table.insert(correctCategories, {
      type = "image",
      image = image,
      name = category.name,
      offers = {}
    })
  end
  processCategories(correctCategories)
end

function onStoreOffers(categoryName, offers)
  if not shop or otcv8shop then return end
  local updated = false

  for i, category in ipairs(CATEGORIES) do
    if category.name == categoryName then
      if #category.offers ~= #offers then
        updated = true
      end
      for i=1,#category.offers do
        if category.offers[i].title ~= offers[i].name or category.offers[i].id ~= offers[i].id or category.offers[i].cost ~= offers[i].price then
          updated = true
        end
      end
      if updated then    
        for offer in pairs(category.offers) do
          category.offers[offer] = nil
        end
        for i, offer in ipairs(offers) do
          local image = ""
          if offer.icon:len() > 0 then
            image = storeUrl .. offer.icon
          end
          table.insert(category.offers, {
            id=offer.id,
            type="image",
            image=image,
            cost=offer.price,
            title=offer.name,
            description=offer.description        
          })
        end
      end
    end
  end
  if not updated then
    return
  end

  local activeCategory = shop.categoryPanel:getFocusedChild()
  changeCategory(activeCategory, activeCategory)
end

function onStoreTransactionHistory(currentPage, hasNextPage, offers)
  if not shop or otcv8shop then return end
  HISTORY = {}
  for i, offer in ipairs(offers) do
    table.insert(HISTORY, {
      id=offer.id,
      type="image",
      image=storeUrl .. offer.icon,
      cost=offer.price,
      title=offer.name,
      description=offer.description        
    })
  end

  if not browsingHistory then return end  
  clearOffers()
  shop.categoryPanel:focusChild(nil)
  for i, transaction in ipairs(HISTORY) do
    addOffer(0, transaction)
  end
end

function onStorePurchase(message)
  if not shop or otcv8shop then
    return
  end
  processMessage({title="Successful shop purchase", msg=message})
end

function onStoreError(errorType, message)
  if not shop or otcv8shop then
    return
  end
  processMessage({title="Shop Error", msg=message})
end

function onCoinBalance(coins, transferableCoins)
  if not shop or otcv8shop then return end
  shop.gemsPanel.gemsGroup.gemsAmount:setText(coins)
end

function onExtendedJSONOpcode(protocol, code, json_data)
  createShop()
  -- createTransferWindow()

  local action = json_data['action']
  local data = json_data['data']
  local status = json_data['status']
  if not action or not data then
    return false
  end
  
  otcv8shop = true
  if action == 'categories' then
    processCategories(data)
  elseif action == 'history' then
    processHistory(data)
  elseif action == 'message' then
    processMessage(data)
  end

  if status then
    processStatus(status)
  end
end

function clearOffers()
  while shop.offers:getChildCount() > 0 do
    local child = shop.offers:getLastChild()
    shop.offers:destroyChildren(child)
  end
end

function clearHistory()
  HISTORY = {}
  if browsingHistory then
    clearOffers()
  end
end

function processCategories(data)
  if table.equal(CATEGORIES,data) then
    return
  end

  CATEGORIES = data

  if not browsingHistory then
    local firstCategory = shop.categoryPanel:getChildByIndex(1)
    if firstCategory then
      firstCategory:focus()
      changeCategory(firstCategory, firstCategory)
    end
  end
end

function processHistory(data)
  if table.equal(HISTORY,data) then
    return
  end
  HISTORY = data
  if browsingHistory then
    showHistory(true)
  end
end

function processMessage(data)
  if msgWindow then
    msgWindow:destroy()
  end
    
  local title = tr(data["title"])
  local msg = data["msg"]
  msgWindow = displayInfoBox(title, msg)
  msgWindow.onDestroy = function(widget)
    if widget == msgWindow then
      msgWindow = nil
    end
  end
  msgWindow:show()
  msgWindow:raise()
  msgWindow:focus()
end

function processStatus(data)
  if table.equal(STATUS,data) then
    return
  end
  STATUS = data

  if data['nickCost'] then
	  changeCost = tonumber(data['nickCost'])
  end
  if data['points'] then
    shop.gemsPanel.gemsGroup.gemsAmount:setText(data['points'])
  end
  if data['buyUrl'] and data['buyUrl']:sub(1, 4):lower() == "http" then
    shop.gemsPanel.gemsButton.onMouseRelease = function() 
      scheduleEvent(function() g_platform.openUrl(data['buyUrl']) end, 50)
    end
  end
end

function showHistory(force)
  if browsingHistory and not force then
    return
  end

  if g_game.getFeature(GameIngameStore) and not otcv8shop then
    g_game.openTransactionHistory(100)
  end
  sendAction("history")

  browsingHistory = true
  clearOffers()
  shop.categoryPanel:focusChild(nil)
  for i, transaction in ipairs(HISTORY) do
    addOffer(0, transaction)
  end
end

function addOffer(category, data)
  local offer
  if data["type"] == "item" then
    offer = g_ui.createWidget('ShopOfferItem', shop.offers)
    offer.item:setItemId(data["item"])
    offer.item:setItemCount(data["count"])
    offer.item:setShowCount(false)
  elseif data["type"] == "outfit" then
    offer = g_ui.createWidget('ShopOfferCreature', shop.offers)
    offer.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      offer.creature:setAutoRotating(true)
    end
  elseif data["type"] == "image" then
    offer = g_ui.createWidget('ShopOfferImage', shop.offers)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
      HTTP.downloadImage(data['image'], function(path, err) 
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
        if not offer.image then return end
        offer.image:setImageSource(path)
      end)
    elseif data["image"] and data["image"]:len() > 1 then
      offer.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop offer type: " .. tostring(data["type"]))
    return
  end
  offer:setId("offer_" .. category .. "_" .. shop.offers:getChildCount())
  offer.titlePanel.title:setText(data["title"])
  offer.price:setText(data["cost"])
  -- offer.description:setText(data["description"])
  offer.offerId = data["id"]
  if category ~= 0 then
    offer.onClick = selectOffer
  end
end

function changeCategory(widget, newCategory)
  if not newCategory then
    return
  end

  if g_game.getFeature(GameIngameStore) and widget ~= newCategory and not otcv8shop then
    local serviceType = 0
    if g_game.getFeature(GameTibia12Protocol) then
      serviceType = 2
    end
    g_game.requestStoreOffers(newCategory.name:getText(), serviceType)
  end

  browsingHistory = false
  local id = categoryMap[newCategory:getId()]
  clearOffers()

  if CATEGORIES[id] and CATEGORIES[id]["offers"] then
    for _, offer in ipairs(CATEGORIES[id]["offers"]) do
      addOffer(id, offer)
    end
  end

  shop.offers:focusChild(nil)
end

function NicknameShopWindow()
  scheduleEvent(function()
    if msgWindow then
      msgWindow:destroy()
    end
	  selectedOffer = {}

	  msgWindow = g_ui.createWidget('NicknameShopWindow', rootWidget)
	  msgWindow:setText("Buying from shop")
	  msgWindow:getChildById('countMessage'):setText("New name:")
	  msgWindow:getChildById('countMessagePoints'):setText("Want to change nickname for "..changeCost.."?")
	  local nicknameConfirmed = function()
		  sendAction("changeName", {newName=msgWindow:getChildById('newName'):getText()})
	  end

	  local okButton = msgWindow:getChildById('buttonOk')
	  local cancelButton = msgWindow:getChildById('buttonCancel')

	  g_keyboard.bindKeyPress("Enter", function() nicknameConfirmed() end, spinbox)

	  msgWindow.onEnter = nicknameConfirmed
	  msgWindow.onEscape = buyCanceled

	  okButton.onClick = nicknameConfirmed
	  cancelButton.onClick = buyCanceled

      msgWindow:show()
      msgWindow:raise()
      msgWindow:focus()
      msgWindow:raise()
    end, 50)
end

function selectOffer(widget, focused)
  if not widget then
    return
  end

  if focused then
    local split = widget:getId():split("_")
    if #split ~= 3 then
      return
    end
    local category = tonumber(split[2])
    local offer = tonumber(split[3])
    local item = CATEGORIES[category]["offers"][offer]
    if not item then
      return
    end

    selectedOffer = {category=category, buyCount=1, offer=offer, title=item.title, cost=item.cost, id=widget.offerId}
    selectedWindow = g_ui.createWidget('SelectedOverlay', shop)
	  selectedWindow:recursiveGetChildById('selectedTitle'):setText(selectedOffer.title)

	  local itemParent = selectedWindow:recursiveGetChildById('selectedBackground')
	  local priceText = selectedWindow:recursiveGetChildById('selectedPrice')
    priceText:setText(selectedOffer.cost)

    if item.type == 'item' then
      if item.imageFile then
        local imageEffect = g_ui.createWidget('ImageEffect', itemParent)
        imageEffect:setImageSource(item.imageFile)
      else
        local itemOverlay = g_ui.createWidget('OverlayItem', itemParent)
        local itemId = itemOverlay:recursiveGetChildById('item')
        local itemCount = itemOverlay:recursiveGetChildById('itemCount')
        itemId:setItemId(item["item"])
        itemId:setItemCount(1)
        itemId:setShowCount(false)
        itemCount:setText('X1')
        scrollbar = itemOverlay:getChildById('horizontalScroll')
        scrollbar.onValueChange = function()
          itemCount:setText(string.format('X%d', scrollbar:getValue()))
          itemId:setItemCount(scrollbar:getValue())
          priceText:setText(selectedOffer.cost * scrollbar:getValue())
          selectedOffer.buyCount = scrollbar:getValue()
        end
      end
    elseif item.type == 'outfit' then
      local outfitOverlay = g_ui.createWidget('OverlayOutfit', itemParent)
      outfitOverlay:setOutfit(item["outfit"])
      if item["outfit"]["rotating"] then
        outfitOverlay:setAutoRotating(true)
      end
    end

	  local buyButton = selectedWindow:recursiveGetChildById('buyButton')

	  buyButton.onClick = function()
      local totalCost = math.max(selectedOffer.cost, selectedOffer.cost * selectedOffer.buyCount)
      if totalCost > tonumber(shop.gemsPanel.gemsGroup.gemsAmount:getText()) then
        local noPointsPanel = g_ui.createWidget('NoPointsOverlay', itemParent)
        noPointsPanel:getChildById('okButton').onClick = buyCanceled
        return
      end

      buyConfirmed(selectedOffer)
    end
    shop.onEscape = buyCanceled

    selectedWindow:show()
    selectedWindow:raise()
    selectedWindow:focus()
  end
end

function buyConfirmed(buyData)
  if not selectedWindow then
    return
  end
  
  selectedWindow:destroy()
  selectedWindow = nil
  sendAction("buy", buyData)
  if g_game.getFeature(GameIngameStore) and buyData.id and not otcv8shop then
    local offerName = buyData.title:lower()
    if string.find(offerName, "name") and string.find(offerName, "change") and modules.client_textedit then
      modules.client_textedit.singlelineEditor("", function(newName)
        if newName:len() == 0 then
          return
        end
        g_game.buyStoreOffer(buyData.id, 1, newName)        
      end)
    else
      g_game.buyStoreOffer(buyData.id, 0, "")
    end
  end

  shop.onEscape = function() hide() end
end

function buyCanceled()
  if selectedWindow then
    selectedWindow:destroy()
    selectedWindow = nil
  end

  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end

  selectedOffer = {}
  shop.onEscape = function() hide() end
end