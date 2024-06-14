AutoLoot = {}

local OP_CODE = 65

local settingsFile = "/settings/autoloot.json"
local settings = {}

local autolootWindow = nil
local itemList = nil
local slotsGroup = nil
local slotsAmount = nil
local skinLabel = nil
local skinOutfit = nil
local activateButton = nil
local removeButton = nil

local addItemWindow = nil
local buySlotsWindow = nil

local serverData = {}

local function saveSettings()
  if not g_resources.fileExists(settingsFile) then
    g_resources.makeDir("/settings")
    g_resources.writeFileContents(settingsFile, "[]")
  end

  local fullSettings = {}
  do
    local json_status, json_data =
      pcall(
      function()
        return json.decode(g_resources.readFileContents(settingsFile))
      end
    )

    if not json_status then
      g_logger.error("[saveSettings] Couldn't load JSON: " .. json_data)
      return
    end
    fullSettings = json_data
  end

  fullSettings[g_game.getCharacterName()] = settings

  local json_status, json_data =
    pcall(
    function()
      return json.encode(fullSettings)
    end
  )

  if not json_status then
    g_logger.error("[saveSettings] Couldn't save JSON: " .. json_data)
    return
  end

  g_resources.writeFileContents(settingsFile, json.encode(fullSettings, 2))
end

local function loadSettings()
  if not g_resources.fileExists(settingsFile) then
    g_resources.makeDir("/settings")
  end

  if g_resources.fileExists(settingsFile) then
    local json_status, json_data =
      pcall(
      function()
        return json.decode(g_resources.readFileContents(settingsFile))
      end
    )

    if not json_status then
      g_logger.error("[loadSettings] Couldn't load JSON: " .. json_data)
      return
    end

    if json_data[g_game.getCharacterName()] then
      settings = json_data[g_game.getCharacterName()]
    else
      settings.lootData = {}
    end
  end
end

local function receiveAction(protocol, opcode, json_data)
  local action = json_data['action']
  local data = json_data['data']
  if action == 'cancel' then
    AutoLoot.destroy()
  elseif action == 'init' then
    AutoLoot.create()
    AutoLoot.updateWindow(data)
  elseif action == 'addItem' then
    AutoLoot.newEntry(data)
  elseif action == 'buySlots' then
    AutoLoot.create()
    AutoLoot.updateWindow(data)
    g_ui.createWidget('PurchaseComplete', rootWidget)
  end
end

function sendAction(action, data)
  if not g_game.getFeature(GameExtendedOpcode) then
    return
  end

  if data == nil then
    data = {}
  end
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedJSONOpcode(OP_CODE, {action = action, data = data})
  end
end

function init()
  connect(g_game, {
    openAutoLootWindow = AutoLoot.open,
    onGameEnd = AutoLoot.destroy
  })
  ProtocolGame.registerExtendedJSONOpcode(OP_CODE, receiveAction)
end

function terminate()
  disconnect(g_game, {
    openAutoLootWindow = AutoLoot.open,
    onGameEnd = AutoLoot.destroy
  })
  ProtocolGame.unregisterExtendedJSONOpcode(OP_CODE, receiveAction)
  AutoLoot.destroy()
end

function AutoLoot.open()
  if autolootWindow then
    return
  end

  sendAction('init')
  loadSettings()
end

function AutoLoot.create()
  AutoLoot.destroy()

  autolootWindow = g_ui.displayUI("autoloot")
  itemList = autolootWindow:recursiveGetChildById('itemEntries')
  slotsGroup = autolootWindow:recursiveGetChildById('slotsGroup')
  slotsAmount = autolootWindow:recursiveGetChildById('slotsAmount')
  skinLabel = autolootWindow:recursiveGetChildById('skinLabel')
  skinOutfit = autolootWindow:recursiveGetChildById('skinCreature')
  activateButton = autolootWindow:recursiveGetChildById('activateButton')
  removeButton = autolootWindow:recursiveGetChildById('removeButton')

  removeButton.onClick = function()
    if #itemList:getChildren() <= 0 then
      return
    end

    local childIndex = itemList:getChildIndex(itemList:getFocusedChild())
    AutoLoot.removeEntry(itemList:getFocusedChild())
    itemList:focusChild(itemList:getChildByIndex(math.min(#itemList:getChildren(), childIndex)))
  end
end

function AutoLoot.updateWindow(data)
  if not autolootWindow then
    return
  end

  serverData.maxSlots = data["maxSlots"]
  serverData.pricePerSlot = data["pricePerSlot"]

  serverData.slots = data["slots"]
  serverData.skins = data["skins"]
  serverData.currentSkin = data["currentSkin"]
  serverData.activated = data["activated"]
  serverData.lootData = {}

  skinLabel:setText(serverData.currentSkin.name)
  slotsGroup:setTooltip("Total Slots: " .. serverData.slots)
  skinOutfit:setOutfit({type = serverData.currentSkin.lookType})
  activateButton:setOn(serverData.activated)

  for _, itemInfo in ipairs(settings.lootData) do
      AutoLoot.newEntry(itemInfo)
  end

  AutoLoot.updateSlots()
end

function AutoLoot.newEntry(itemInfo)
  local widgetId = 'autolootEntry' .. itemInfo.itemId

  -- Check if item already exists in list
  if autolootWindow:recursiveGetChildById(widgetId) then
    sendAction('alreadyExists')
    return
  end

  -- Check if list is full
  if #itemList:getChildren() >= serverData.slots then
    return
  end

  local widget = g_ui.createWidget('AutoLootEntry', itemList)
  local name = widget:getChildById('autolootName')
  local item = widget:getChildById('autolootItem')
  local weight = widget:getChildById('autolootWeight')
  local button = widget:getChildById('autolootButton')

  widget:setId('autolootEntry' .. itemInfo.itemId)
  name:setText(itemInfo.itemName:upper())
  item:setItemId(itemInfo.clientId)
  weight:setText(string.format(weight.baseText, string.format("%.2f", itemInfo.itemWeight / 100)))
  button:setOn(itemInfo.activated)

  table.insert(serverData.lootData, itemInfo)
  AutoLoot.updateSlots()
end

function AutoLoot.addEntry()
  if #itemList:getChildren() >= serverData.slots then
    sendAction('listFull')
    return
  end

  if buySlotsWindow then
    buySlotsWindow:destroy()
    buySlotsWindow = nil
  end

  addItemWindow = g_ui.createWidget('AddItemWindow', rootWidget)
  addItemWindow:raise()
  addItemWindow:focus()
end

function AutoLoot.addItemButton()
  local itemText = addItemWindow:getChildById('itemText')
  sendAction('addItem', itemText:getText())

  addItemWindow:destroy()
  addItemWindow = nil
end

function AutoLoot.removeEntry(entry)
  local id = entry:getId():gsub('autolootEntry', "")
  for _, itemInfo in ipairs(serverData.lootData) do
    if itemInfo.itemId == tonumber(id) then
      table.removevalue(serverData.lootData, itemInfo)
      break
    end
  end

  entry:destroy()
  AutoLoot.updateSlots()
end

function AutoLoot.cycleSkins(direction)
  local nextSkin, prevSkin

  for k, v in ipairs(serverData.skins) do
    if serverData.currentSkin.storage == v.storage then
      nextSkin = (k % #serverData.skins) + 1
      prevSkin = (k - 2) % #serverData.skins + 1
      break
    end
  end

  if direction == "right" then
    serverData.currentSkin = serverData.skins[nextSkin]
  elseif direction == "left" then
    serverData.currentSkin = serverData.skins[prevSkin]
  end

  skinLabel:setText(serverData.currentSkin.name)
  skinOutfit:setOutfit({type = serverData.currentSkin.lookType})
end

function AutoLoot.toggleEntry(entry)
  if not entry then
    return
  end

  local button = entry:recursiveGetChildById('autolootButton')
  button:setOn(not button:isOn())

  local id = entry:getId():gsub('autolootEntry', "")
  for _, itemInfo in ipairs(serverData.lootData) do
    if itemInfo.itemId == tonumber(id) then
      itemInfo.activated = button:isOn()
      break
    end
  end
end

function AutoLoot.updateSlots()
  if not slotsAmount or not itemList or not serverData.slots then
    return
  end

  slotsAmount:setText(serverData.slots - #itemList:getChildren())
end

function AutoLoot.buySlots()
  if serverData.slots >= serverData.maxSlots then
    sendAction('maxSlots')
    return
  end

  if addItemWindow then
    addItemWindow:destroy()
    addItemWindow = nil
  end

  buySlotsWindow = g_ui.createWidget('BuySlotsWindow', rootWidget)
  buySlotsWindow:raise()
  buySlotsWindow:focus()

  local amountScrollbar = buySlotsWindow:recursiveGetChildById('amountScrollbar')
  local amountLabel = buySlotsWindow:recursiveGetChildById('amountLabel')
  local buyButton = buySlotsWindow:recursiveGetChildById('buyButton')

  amountScrollbar:setMaximum(serverData.maxSlots - serverData.slots)
  amountScrollbar.onValueChange = function()
    amountLabel:setText(string.format(amountLabel.baseText, amountScrollbar:getValue(), amountScrollbar:getValue() * serverData.pricePerSlot))
  end
  buyButton.onClick = function()
    AutoLoot.saveData()

    local data = { slotsAmount = amountScrollbar:getValue() }
    sendAction('buySlots', data)
  end

  amountLabel:setText(string.format(amountLabel.baseText, 1, serverData.pricePerSlot))
end

function AutoLoot.saveData()
  serverData.activated = activateButton:isOn()
  sendAction('save', serverData)

  settings.lootData = serverData.lootData
  saveSettings()
end

function AutoLoot.destroy()
  if autolootWindow then
    AutoLoot.saveData()
    autolootWindow:destroy()
  end

  if addItemWindow then
    addItemWindow:destroy()
  end

  if buySlotsWindow then
    buySlotsWindow:destroy()
  end

  autolootWindow = nil
  itemList = nil
  slotsGroup = nil
  slotsAmount = nil
  skinLabel = nil
  skinOutfit = nil
  activateButton = nil
  removeButton = nil
  addItemWindow = nil
  buySlotsWindow = nil

  serverData = {}
end