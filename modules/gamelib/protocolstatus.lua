-- @docclass
ProtocolStatus = extends(Protocol, "ProtocolStatus")

StatusServerCharacterInfo = 34

function ProtocolStatus:login(host, port, characters)
    if string.len(host) == 0 or port == nil or port == 0 then
        signalcall(self.onLoginError, self, tr("You must enter a valid server address and port."))
        return
    end

    self.connectCallback = function() self:sendStatusPacket(characters) end
    self:connect(host, port)
end

function ProtocolStatus:cancelLogin()
    self:disconnect()
end

function ProtocolStatus:sendStatusPacket(characters)
    local msg = OutputMessage.create()
    msg:addU8(255)
    msg:addU8(1)
    msg:addU16(64)

    msg:addU8(#characters)
    for _, name in pairs(characters) do
        msg:addString(name)
    end

    self:send(msg)
    self:recv()
end

function ProtocolStatus:onConnect()
    self.gotConnection = true
    self:connectCallback()
    self.connectCallback = nil
end

function ProtocolStatus:onRecv(msg)
    while not msg:eof() do
        local opcode = msg:getU8()
        if opcode == StatusServerCharacterInfo then
          self:parseCharacterInfo(msg)
        end
    end
    self:disconnect()
end

function ProtocolStatus:parseError(msg)
    local errorMessage = msg:getString()
    signalcall(self.onLoginError, self, errorMessage)
end

function ProtocolStatus:onError(msg, code)
    local text = translateNetworkError(code, self:isConnecting(), msg)
    signalcall(self.onLoginError, self, text)
end

function ProtocolStatus:parseCharacterInfo(msg)
  local charactersInfo = {}

  local size = msg:getU8()

  for _ = 1, size do
    local characterName = msg:getString()
    local onlineStatus = msg:getU8()
    local health = msg:getU32()
    local healthMax = msg:getU32()
    local mana = msg:getU32()
    local manaMax = msg:getU32()

    charactersInfo[characterName] = {
      ["onlineStatus"] = onlineStatus,
      ["health"] = health,
      ["healthMax"] = healthMax,
      ["mana"] = mana,
      ["manaMax"] = manaMax,
    }
  end

  signalcall(self.onUpdateCharList, self, charactersInfo)
end

function ProtocolStatus:requestUpdateCharList(characters)
  if not characters then
    return
  end

  local serverInfo = G.host:split(":")
  self:login(serverInfo[1], 7171, characters)
end