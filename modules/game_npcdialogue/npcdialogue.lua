NpcDialogue = {}

config = {
  opCode = 68,
  closeTime = 4,            -- Time to close the dialogue window after saying 'Bye' etc (minimum should be 2 seconds so it won't bug)
  fadeEffect = true,        -- Gradually fades the window in and out
  animateText = false,      -- Message will appear 1 letter at a time like an animation
  animateTime = 50,         -- Time between letters when animating (milliseconds)
  hideNpcTabText = false,   -- Hides NPC messages from appearing in 'NPCs' Console Tab
  hideNpcPopupText = false, -- Hides NPC messages from appearing above their character
}

local widget = nil
local mainPanel = nil
local npcName = nil
local npcOutfit = nil
local npcOutfitItem = nil
local npcMessage = nil

local hideEvent = nil
local animateEvent = nil

local g_console = modules.game_console

function onExtendedOpcode(protocol, code, buffer)
  local status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not status then
    g_logger.error("[NPC Dialogue] JSON error: " .. json_data)
    return false
  end

  if json_data.action == 'greet' then
	  NpcDialogue.greet()
  elseif json_data.action == 'cancel' then
	  NpcDialogue.cancel()
  elseif json_data.action == 'talk' then
	  NpcDialogue.talk(json_data.data)
  end
end

function onTextButtonClicked(widget, text)
  local npcTab = g_console.consoleTabBar:getTab("NPCs")
  if npcTab then
    g_console.sendMessage(text, npcTab)
  end
end

function onTextButtonHovered(widget, text, hovered)
  if hovered then
    g_mouse.pushCursor("pointer")
  else
    g_mouse.popCursor("pointer")
  end
end

function init()
  connect(g_game, {
    onGameEnd = NpcDialogue.destroy
  })

  widget = g_ui.loadUI("npcdialogue", modules.game_interface.getRootPanel())
  widget:addAnchor(AnchorBottom, 'bottomSplitter', AnchorBottom)

  mainPanel = widget.mainPanel
  npcName = widget.npcName
  npcOutfit = widget.outfitBox.npcOutfit
  npcOutfitItem = widget.outfitBox.npcOutfitItem
  npcMessage = widget.textPanel.npcText

  if config.fadeEffect then
    widget:setOpacity(0)
  else
	  widget:hide()
  end

	ProtocolGame.registerExtendedOpcode(config.opCode, onExtendedOpcode)
end

function terminate()
  disconnect(g_game, {
    onGameEnd = NpcDialogue.destroy
  })

  ProtocolGame.unregisterExtendedOpcode(config.opCode)
  NpcDialogue.destroy()
end

local function calculateDialogHeight(text)
	local maxCharsPerLine = 70
	local lineHeight = 16
	local numLines = math.ceil(string.len(text) / maxCharsPerLine)
	local height = numLines * lineHeight

	return height
end

local function parseOutfit(npcOutfit)
  local outfit = {
    feet = npcOutfit.lookFeet,
    head = npcOutfit.lookHead,
    legs = npcOutfit.lookLegs,
    addons = npcOutfit.lookAddons,
    body = npcOutfit.lookBody,
    type = npcOutfit.lookType,
    auxType = npcOutfit.lookTypeEx
  }
  return outfit
end

function NpcDialogue.talk(npcData)
  if not widget then
    return
  end

  if animateEvent then
    animateEvent:cancel()
    animateEvent = nil
  end

  widget:setHeight(80 + calculateDialogHeight(npcData.message) - 20)
  mainPanel:setHeight(80 + calculateDialogHeight(npcData.message) - 20)

  npcName:setText(npcData.name)
  npcName:setColor(npcData.color)

  local highlightData = g_console.getNewHighlightedText(npcData.message, "#FFFFFF", "#1F9FFE")
  if #highlightData > 2 then
    for i = 1, #highlightData, 2 do
      if highlightData[i + 1] == "#1F9FFE" then
        highlightData[i] = string.format("[text-event]%s[/text-event]", highlightData[i])
      end
    end
  end

  npcData.message = npcData.message:gsub("[{}]", "")

  if config.animateText then
    NpcDialogue.runAnimation(npcData.message, 1, highlightData)
  else
    if #highlightData > 2 then
      npcMessage:setColoredText(highlightData)
    else
      npcMessage:setText(npcData.message)
    end
  end

  if npcData.outfit.lookTypeEx ~= 0 then
    npcOutfitItem:setItem(Item.create(npcData.outfit.lookTypeEx, 1))
    npcOutfitItem:setVisible(true)
    npcOutfit:setVisible(false)
  else
    local outfit = parseOutfit(npcData.outfit)
    npcOutfit:setOutfit(outfit)
    npcOutfit:setVisible(true)
    npcOutfitItem:setVisible(false)
  end

  if config.fadeEffect then
    if widget:getOpacity() == 0 then
      g_effects.fadeIn(widget)
    end
  else
    if not widget:isVisible() then
      widget:show()
    end
  end

  if not npcMessage:hasEventListener(EVENT_TEXT_CLICK) and not npcMessage:hasEventListener(EVENT_TEXT_HOVER) then
    npcMessage:setEventListener(EVENT_TEXT_CLICK)
    npcMessage:setEventListener(EVENT_TEXT_HOVER)
    connect(npcMessage, { onTextClick = onTextButtonClicked, onTextHoverChange = onTextButtonHovered })
  end
end

function NpcDialogue.greet()
  if hideEvent then
    hideEvent:cancel()
    hideEvent = nil
  end
end

function NpcDialogue.cancel()
  if not widget then
    return
  end

  if hideEvent then
    hideEvent:cancel()
    hideEvent = nil
  end

  hideEvent = scheduleEvent(function()
    if config.fadeEffect then
      if widget:getOpacity() == 1 then
        g_effects.fadeOut(widget)
      end
    else
      if widget:isVisible() then
        widget:hide()
      end
    end

    hideEvent = nil
  end, 1000 * config.closeTime)
end

function NpcDialogue.runAnimation(message, currentLength, highlightData)
  if not widget then
    return
  end

  local processedMessage = message:sub(1, currentLength)
  npcMessage:setText(processedMessage)

  if #message == currentLength then
    if #highlightData > 2 then
      npcMessage:setColoredText(highlightData)
    end
    animateEvent = nil
    return
  end

  animateEvent = scheduleEvent(function() NpcDialogue.runAnimation(message, currentLength + 1, highlightData) end, config.animateTime)
end

function NpcDialogue.destroy()
  if widget then
    widget:destroy()
  end

  widget = nil
  mainPanel = nil
  npcName = nil
  npcOutfit = nil
  npcOutfitItem = nil
  npcMessage = nil

  hideEvent = nil
  animateEvent = nil
end
