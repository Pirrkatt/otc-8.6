local CODE = 107

local window = nil
local windowBtn = nil
local categories = nil
local craftPanel = nil
local itemsList = nil

local selectedCategory = nil
local selectedCraftId = nil
local Crafts = {weapons = {}, equipment = {}, potions = {}, legs = {}, upgradeables = {}, others = {}}

local vocations = {
  "All"
}

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

  local vocDrop = window:recursiveGetChildById("vocations")
  if vocDrop:getOptionsCount() == 0 then
    vocDrop.onOptionChange = onVocationChange
    for i = 1, #vocations do
      vocDrop:addOption(vocations[i], i)
    end
    vocDrop:setCurrentIndex(1)
  end
  vocDrop.menuHeight = 125
  vocDrop.menuScroll = false

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
    if data.category == "weapons" then
      selectedCategory = "weapons"
      categories:getChildById("weaponsCat"):setOn(true)
      for i = 1, #data.crafts do
        local craft = data.crafts[i]
        local w = g_ui.createWidget("ItemListItem")
        w:setId(i + #Crafts[data.category])
        w:getChildById("item"):setItemId(craft.item.id)
        w:getChildById("name"):setText(craft.name)
        w:getChildById("level"):setText("Level " .. craft.level)
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
  end
end

function onItemCrafted()
  if selectedCategory and selectedCraftId then
    local craft = Crafts[selectedCategory][selectedCraftId]
    if craft then
      for i = 1, #craft.materials do
        local materialWidget = craftPanel:getChildById("craftLine" .. i)
        materialWidget:setImageSource("/images/crafting/craft_line" .. i .. "on")
        scheduleEvent(
          function()
            materialWidget:setImageSource("/images/crafting/craft_line" .. (i == 2 and 5 or i))
          end,
          850
        )
      end
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
        local vocDrop = window:recursiveGetChildById("vocations")
        local vocId = vocDrop:getCurrentOption().data
        for i = children, 1, -1 do
          local child = itemsList:getChildByIndex(i)
          local craftId = tonumber(child:getId())
          local craft = Crafts[selectedCategory][craftId]
          if vocId == 1 then
            child:show()
            child:focus()
            selectItem(i)
          else
            if type(craft.vocation) == "table" then
              if table.contains(craft.vocation, vocId) then
                child:show()
                child:focus()
                selectItem(i)
              else
                child:hide()
              end
            else
              if craft.vocation ~= vocId then
                child:hide()
              else
                child:show()
                child:focus()
                selectItem(i)
              end
            end
          end
        end
      end
    end,
    25
  )
end

function onVocationChange(widget, name, id)
  local searchInput = window:recursiveGetChildById("searchInput")
  local text = searchInput:getText():lower()
  if text:len() >= 1 then
    onSearch()
    return
  end

  local description = craftPanel:recursiveGetChildById("description")
  description:setText("")

  for i = 1, 6 do
    local materialWidget = craftPanel:getChildById("material" .. i)
    materialWidget:setItem(nil)
    craftPanel:getChildById("count" .. i):setText("")
  end

  local outcome = craftPanel:getChildById("craftOutcome")
  outcome:setItem(nil)
  craftPanel:recursiveGetChildById("totalCost"):setText("")

  local childCount = itemsList:getChildCount()
  for i = 1, childCount do
    local child = itemsList:getChildByIndex(i)
    local craftId = tonumber(child:getId())
    local craft = Crafts[selectedCategory][craftId]
    if id == 1 then
      child:show()
      if i == 1 then
        child:focus()
        selectItem(i)
      end
    else
      if type(craft.vocation) == "table" then
        if table.contains(craft.vocation, id) then
          child:show()
          if i == 1 then
            child:focus()
            selectItem(i)
          end
        else
          child:hide()
        end
      else
        if craft.vocation ~= id then
          child:hide()
        else
          child:show()
          if i == 1 then
            child:focus()
            selectItem(i)
          end
        end
      end
    end
  end
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
      local materialWidget = craftPanel:getChildById("material" .. i)
      materialWidget:setItem(nil)
      craftPanel:getChildById("count" .. i):setText("")
    end

    craftPanel:getChildById("craftOutcome"):setItem(nil)
    craftPanel:recursiveGetChildById("totalCost"):setText("")

    for i = 1, #Crafts[selectedCategory] do
      local craft = Crafts[selectedCategory][i]
      local w = g_ui.createWidget("ItemListItem")
      w:setId(i)
      w:getChildById("item"):setItemId(craft.item.id)
      w:getChildById("name"):setText(craft.name)
      w:getChildById("level"):setText("Level " .. craft.level)
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

  local description = craftPanel:recursiveGetChildById("description")
  description:setText(craft.name .. "\n" .. craft.description)

  for i = 1, 6 do
    local materialWidget = craftPanel:getChildById("material" .. i)
    materialWidget:setItem(nil)
    craftPanel:getChildById("count" .. i):setText("")
  end

  for i = 1, #craft.materials do
    local material = craft.materials[i]
    local materialWidget = craftPanel:getChildById("material" .. i)
    materialWidget:setItemId(material.id)
    materialWidget:setItemCount(material.count)
    local count = craftPanel:getChildById("count" .. i)
    count:setText(material.player .. "\n" .. material.count)
    if material.player >= material.count then
      count:setColor("#FFFFFF")
    else
      count:setColor("#FF0000")
    end
  end

  local outcome = craftPanel:getChildById("craftOutcome")
  outcome:setItemId(craft.item.id)
  outcome:setItemCount(craft.count)
  craftPanel:recursiveGetChildById("totalCost"):setText(comma_value(craft.cost))
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
    show()
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
