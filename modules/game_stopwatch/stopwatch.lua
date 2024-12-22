Stopwatch = {}

local config = {
  opCode = 67,
  immuneTime = 4, -- Seconds
  totalSquares = 10, -- Squares to fill the progress bar with
}

local addSquareInterval = (config.immuneTime - (config.immuneTime / config.totalSquares)) / config.totalSquares -- We deduct 1/10 of the total immuneTime to reserve for the last loop for looks

function init()
  ProtocolGame.registerExtendedOpcode(config.opCode, Stopwatch.create)
  g_ui.importStyle("stopwatch")
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(config.opCode)
  Stopwatch.destroy()
end

function Stopwatch.create(_, _, posString)
  local pos = string.split(posString, ",")

  local data = {}
  data.pos = {x = pos[1], y = pos[2], z = pos[3]}

  local tile = g_map.getTile(data.pos)
	if tile and not tile:getWidget() then
    local creature = tile:getCreatures()[1]
    if not creature then
      return
    end

    local start_time = g_clock.millis()
		local widget = g_ui.createWidget("StopWatchWidget", rootWidget)
    local offset = creature:getInformationOffset()

    widget:setMarginTop(widget:getMarginTop() + offset.y)
    widget:setMarginLeft(widget:getMarginLeft() + offset.x)

    data.start_time = start_time
    data.widget = widget
    data.squaresAdded = 0

		tile:setWidget(widget)
    Stopwatch.updateBar(data)
	end
end

function Stopwatch.updateBar(data)
  if not data then
    return
  end

  if data.squaresAdded >= 10 then
      Stopwatch.destroy(data)
    return
  end

  local elapsed_time = g_clock.millis() - data.start_time
  local squaresToShow = math.min(10, math.floor((elapsed_time / 1000) / addSquareInterval))

  if squaresToShow > data.squaresAdded then
    local bar = data.widget:getChildById('stopwatchFilled')
    if not bar then
      return
    end

    local barWidth = 2 + (config.totalSquares * squaresToShow) -- 2 to add edges

    local rect = {
      x = 0,
      y = 0,
      width = math.max(1, barWidth),
      height = bar:getHeight()
    }
    bar:setImageClip(rect)
    bar:setImageRect(rect)

    data.squaresAdded = squaresToShow
  end

  scheduleEvent(function()
    Stopwatch.updateBar(data)
  end, addSquareInterval * 1000)
end

function Stopwatch.destroy(data)
  local tile = g_map.getTile(data.pos)
  if tile and tile:getWidget() then
    tile:removeWidget()
  end

  data = nil
end