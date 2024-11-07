KiBlast = {}

local OP_CODE = 66

-- Sent from server
local total_time = nil
local cycle_delay = nil

local start_time = nil
local widget = nil
local icon = nil

local function receiveAction(protocol, opcode, json_data)
  local action = json_data['action']
  local data = json_data['data']
  if action == 'start' then
    total_time = data.totalTime
    cycle_delay = data.cycleDelay
    KiBlast.create()
  elseif action == 'stop' then
    KiBlast.sendResult()
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
    onGameEnd = KiBlast.destroy
  })
  ProtocolGame.registerExtendedJSONOpcode(OP_CODE, receiveAction)
end

function terminate()
  disconnect(g_game, {
    onGameEnd = KiBlast.destroy
  })
  ProtocolGame.unregisterExtendedJSONOpcode(OP_CODE)

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

  if elapsed_time >= total_time then
    KiBlast.destroy()
    return
  end

  icon = currentIcon
  toggleIconOverlay(currentIcon)

  scheduleEvent(function()
    cycleIcons((currentIcon % 4) + 1)
  end, cycle_delay)
end

function KiBlast.create()
  if widget then
    return
  end

  widget = g_ui.displayUI("kiblast")
  cycleIcons(math.random(4))
end

function KiBlast.sendResult()
  sendAction('result', icon)
  KiBlast.destroy()
end

function KiBlast.destroy()
  if widget then
    widget:destroy()
  end

  total_time = nil
  cycle_delay = nil

  widget = nil
  start_time = nil
  icon = nil
end