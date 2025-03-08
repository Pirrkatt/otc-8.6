local CODE = 107

local window = nil
local windowBtn = nil
local categories = nil
local craftPanel = nil
local itemsList = nil
local currencyPanel = nil

local selectedCategory = nil
local selectedCraftId = nil
local Crafts = {weapons = {}, equipment = {}, potions = {}, legs = {}, upgradeables = {}, others = {}}

function init()
  connect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )

  ProtocolGame.registerExtendedOpcode(CODE, onExtendedOpcode)

  if g_game.isOnline() then
    create()
  end
end

function terminate()
  disconnect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )

  ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)

  destroy()
end

function create()
  if window then
    return
  end

  windowBtn = modules.client_topmenu.addRightGameToggleButton("crafting", tr("Crafting"), "/images/topbuttons/modulemanager", toggle)
  windowBtn:setOn(false)

  window = g_ui.displayUI("crafting")
  window:hide()

  categories = window:getChildById("categories")
  craftPanel = window:getChildById("craftPanel")
  itemsList = window:getChildById("itemsList")
  currencyPanel = window:getChildById("currencyPanel")
  searchTextEdit = window:recursiveGetChildById("searchInput")

  searchTextEdit.onTextChange = function(widget, text)
    searchTextEdit:setText(string.upper(text))
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(CODE, json.encode({action = "fetch"}))
  end
end

function destroy()
  if windowBtn then
    windowBtn:destroy()
    windowBtn = nil
  end
  if window then
    categories = nil
    craftPanel = nil
    itemsList = nil
    currencyPanel = nil

    selectedCategory = nil
    selectedCraftId = nil
    Crafts = {weapons = {}, equipment = {}, potions = {}, legs = {}, upgradeables = {}, others = {}}

    window:destroy()
    window = nil
  end
end

function onExtendedOpcode(protocol, code, buffer)
  local status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not status then
    g_logger.error("[Crafting] JSON error: " .. data)
    return false
  end

  local action = json_data.action
  local data = json_data.data
  if action == "fetch" then
    if data.category == "legs" then
      selectedCategory = "legs"
      categories:getChildById("legsCat"):setOn(true)
      for i = 1, #data.crafts do
        local craft = data.crafts[i]
        local w = g_ui.createWidget("ItemListItem")
        w:setId(i + #Crafts[data.category])
        w:recursiveGetChildById("item"):setItemId(craft.item.id)
        w:getChildById("name"):setText(string.upper(craft.name))
        itemsList:addChild(w)
        if i + #Crafts[data.category] == 1 then
          w:focus()
        end
      end
    end
    for i = 1, #data.crafts do
      table.insert(Crafts[data.category], data.crafts[i])
      if i == 1 then
        selectItem(i)
      end
    end
  elseif action == "materials" then
    for i = 1, #data.materials do
      local material = data.materials[i]
      for x = 1, #material do
        local mats = Crafts[data.category][data.from + i - 1].materials[x]
        if mats then
          mats.player = material[x]
        end
      end
    end
    if data.from == 1 and window:isVisible() and selectedCategory == data.category then
      selectItem(selectedCraftId)
    end
  elseif action == "show" then
    show()
    selectItem(selectedCraftId)
  elseif action == "crafted" then
    onItemCrafted()
  elseif action == "currency" then
    if currencyPanel then
      currencyPanel:getChildById("currencyAmount"):setText(data.currency)
    end
  end
end

function onItemCrafted()
  if selectedCategory and selectedCraftId then
    local craft = Crafts[selectedCategory][selectedCraftId]
    if craft then
      local button = craftPanel:getChildById("craftButton")
      button:disable()
      scheduleEvent(
        function()
          button:enable()
        end,
        860
      )
    end
  end
end

function onSearch()
  scheduleEvent(
    function()
      local searchInput = window:recursiveGetChildById("searchInput")
      local text = searchInput:getText():lower()
      if text:len() >= 1 then
        local children = itemsList:getChildCount()
        for i = children, 1, -1 do
          local child = itemsList:getChildByIndex(i)
          local name = child:getChildById("name"):getText():lower()
          if name:find(text) then
            child:show()
            child:focus()
            selectItem(i)
          else
            child:hide()
          end
        end
      else
        local children = itemsList:getChildCount()
        for i = children, 1, -1 do
          local child = itemsList:getChildByIndex(i)
            child:show()
            child:focus()
            selectItem(i)
        end
      end
    end,
    25
  )
end

function selectCategory(category)
  if selectedCategory then
    local oldCatBtn = categories:getChildById(selectedCategory .. "Cat")
    if oldCatBtn then
      oldCatBtn:setOn(false)
    end
  end

  local newCatBtn = categories:getChildById(category .. "Cat")
  if newCatBtn then
    newCatBtn:setOn(true)
    selectedCategory = category

    itemsList:destroyChildren()

    selectedCraftId = nil

    for i = 1, 6 do
      local materialWidget = craftPanel:recursiveGetChildById("material" .. i)
      materialWidget:setItem(nil)
      craftPanel:recursiveGetChildById("count" .. i):setText("")
      craftPanel:recursiveGetChildById("disabled" .. i):setOn(false)
    end

    craftPanel:recursiveGetChildById("craftOutcome"):setItem(nil)
    craftPanel:recursiveGetChildById("totalCost"):setText("")

    for i = 1, #Crafts[selectedCategory] do
      local craft = Crafts[selectedCategory][i]
      local w = g_ui.createWidget("ItemListItem")
      w:setId(i)
      w:recursiveGetChildById("item"):setItemId(craft.item.id)
      w:getChildById("name"):setText(string.upper(craft.name))
      itemsList:addChild(w)

      if i == 1 then
        w:focus()
        selectItem(1)
      end
    end
  end
end

function selectItem(id)
  local craftId = tonumber(id)
  selectedCraftId = craftId

  local craft = Crafts[selectedCategory][craftId]

  for i = 1, 6 do
    local materialWidget = craftPanel:recursiveGetChildById("material" .. i)
    materialWidget:setItem(nil)
    craftPanel:recursiveGetChildById("count" .. i):setText("")
    craftPanel:recursiveGetChildById("disabled" .. i):setOn(false)
  end

  for i = 1, #craft.materials do
    local material = craft.materials[i]
    local materialWidget = craftPanel:recursiveGetChildById("material" .. i)
    materialWidget:setItemId(material.id)
    materialWidget:setItemCount(material.count)
    materialWidget:setShowCount(false)
    local count = craftPanel:recursiveGetChildById("count" .. i)
    count:setText(material.player .. "/" .. material.count)
    if material.player >= material.count then
      count:setColor("#FFEE00") -- Yellow
      craftPanel:recursiveGetChildById("disabled" .. i):setOn(false)
    else
      count:setColor("#FF0000") -- Red
      craftPanel:recursiveGetChildById("disabled" .. i):setOn(true)
    end
  end

  local outcome = craftPanel:recursiveGetChildById("craftOutcome")
  outcome:setItemId(craft.item.id)
  outcome:setItemCount(craft.count)
  craftPanel:recursiveGetChildById("totalCost"):setText(craft.cost)
end

function craftItem()
  if selectedCategory and selectedCraftId then
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
      protocolGame:sendExtendedOpcode(CODE, json.encode({action = "craft", data = {category = selectedCategory, craftId = selectedCraftId}}))
    end
  end
end

function toggle()
  if not window then
    return
  end

  if windowBtn:isOn() then
    hide()
  else
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
      protocolGame:sendExtendedOpcode(CODE, json.encode({action = "show"}))
    end
  end
end

function show()
  if not window then
    return
  end

  windowBtn:setOn(true)
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if not window then
    return
  end
  windowBtn:setOn(false)
  window:hide()
end

function comma_value(amount)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
    if (k == 0) then
      break
    end
  end
  return formatted
end
