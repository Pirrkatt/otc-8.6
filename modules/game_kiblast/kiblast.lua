KiBlast = {}

local config = {
  opCode = 66,
  totalTime = 10, -- Total time player have to select a spell
  cycleDelay = 500, -- Time between each icon cycle in milliseconds
}

local start_time = nil
local widget = nil
local icon = nil

local function receiveAction(_, opcode, string)
  if string == 'start' then
    KiBlast.create()
  elseif string == 'stop' then
    KiBlast.sendResult()
  end
end

function sendAction(spellId)
  if not g_game.getFeature(GameExtendedOpcode) then
    return
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(config.opCode, spellId)
  end
end

function init()
  connect(g_game, {
    onGameEnd = KiBlast.destroy
  })
  ProtocolGame.registerExtendedOpcode(config.opCode, receiveAction)
end

function terminate()
  disconnect(g_game, {
    onGameEnd = KiBlast.destroy
  })
  ProtocolGame.unregisterExtendedOpcode(config.opCode)

  KiBlast.destroy()
end

local function toggleIconOverlay(currentIcon)
  if not widget then
    return
  end

  for _, v in pairs(widget:getChildren()) do
    local iconId = v:getId():gsub("icon_", "")
    if currentIcon == tonumber(iconId) then
      v:setVisible(false)
    else
      v:setVisible(true)
    end
  end
end

local function cycleIcons(currentIcon)
  if not widget then
    return
  end

  if not start_time then
    start_time = os.time()
  end

  local elapsed_time = os.time() - start_time

  if elapsed_time >= config.totalTime then
    KiBlast.destroy()
    return
  end

  icon = currentIcon
  toggleIconOverlay(currentIcon)

  scheduleEvent(function()
    cycleIcons((currentIcon % 4) + 1)
  end, config.cycleDelay)
end

function KiBlast.create()
  if widget then
    return
  end

  widget = g_ui.displayUI("kiblast")
  cycleIcons(math.random(4))
end

function KiBlast.sendResult()
  sendAction(icon)
  KiBlast.destroy()
end

function KiBlast.destroy()
  if widget then
    widget:destroy()
  end

  widget = nil
  start_time = nil
  icon = nil
end