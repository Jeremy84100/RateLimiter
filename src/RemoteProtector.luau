--!strict

--[[
    @title RemoteProtector
    @summary A wrapper for RateManager to handle per-player RemoteEvent protection.
]]

local Players = game:GetService("Players")
local RateManager = require(script.Parent)

type RateManagerInstance = RateManager.RateManagerInstance

export type RemoteProtectorInstance = {
    _maxCalls: number,
    _perSeconds: number,
    _punishHits: number?,
    _punishDurations: {number}?,
    _playerLimiters: { [Player]: RateManagerInstance },
    _connections: {RBXScriptConnection},
    _playerRemovingConn: RBXScriptConnection?,
    
    Connect: (self: RemoteProtectorInstance, remoteEvent: RemoteEvent, callback: (Player, ...any) -> ()) -> RBXScriptConnection,
    SetCapacity: (self: RemoteProtectorInstance, maxCalls: number, perSeconds: number?) -> (),
    SetPunishment: (self: RemoteProtectorInstance, threshold: number, durations: number | {number}) -> (),
    Destroy: (self: RemoteProtectorInstance) -> (),
}

local RemoteProtector = {}
RemoteProtector.__index = RemoteProtector

function RemoteProtector.new(maxCalls: number, perSeconds: number, punishHits: number?, punishDuration: (number | {number})?): RemoteProtectorInstance
    -- Security Asserts (Fail-Fast)
    assert(type(maxCalls) == "number" and maxCalls > 0, "maxCalls must be a number > 0")
    assert(type(perSeconds) == "number" and perSeconds > 0, "perSeconds must be a number > 0")
    
    local self = setmetatable({} :: any, RemoteProtector)
    
    -- Fast direct variables instead of tables
    self._maxCalls = maxCalls
    self._perSeconds = perSeconds
    self._punishHits = punishHits
    self._punishDurations = type(punishDuration) == "table" and punishDuration or (punishDuration and {punishDuration} or nil)
    
    self._playerLimiters = {}
    self._connections = {}
    
    -- Automatic cleanup to prevent memory leaks
    self._playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
        if self._playerLimiters[player] then
            self._playerLimiters[player]:Destroy()
            self._playerLimiters[player] = nil
        end
    end)
    
    return self
end

function RemoteProtector:Connect(remoteEvent: RemoteEvent, callback: (Player, ...any) -> ()): RBXScriptConnection
    assert(typeof(remoteEvent) == "Instance" and remoteEvent:IsA("RemoteEvent"), "RemoteProtector:Connect expects a RemoteEvent")
    
    local conn = remoteEvent.OnServerEvent:Connect(function(player: Player, ...)
        local limiter = self._playerLimiters[player]
        
        if not limiter then
            limiter = RateManager.new(self._maxCalls, self._perSeconds, RateManager.Mode.RateLimit)
            
            if self._punishHits and self._punishDurations then
                limiter:SetPunishment(self._punishHits, self._punishDurations)
            end
            
            self._playerLimiters[player] = limiter
        end
        
        -- Low-overhead execution: Validates the player's rate limit before firing the callback.
        -- Uses direct argument passing to avoid closures and table allocations.
        limiter:Execute(callback, player, ...)
    end)
    
    table.insert(self._connections, conn)
    return conn
end

function RemoteProtector:SetCapacity(maxCalls: number, perSeconds: number?)
    self._maxCalls = maxCalls
    self._perSeconds = perSeconds or self._perSeconds
    for _, limiter in self._playerLimiters do
        limiter:SetCapacity(maxCalls, perSeconds)
    end
end

function RemoteProtector:SetPunishment(threshold: number, durations: number | {number})
    self._punishHits = threshold
    self._punishDurations = type(durations) == "table" and durations or {durations}
    for _, limiter in self._playerLimiters do
        limiter:SetPunishment(threshold, self._punishDurations)
    end
end

function RemoteProtector:Destroy()
    if self._playerRemovingConn then
        self._playerRemovingConn:Disconnect()
        self._playerRemovingConn = nil
    end
    
    for _, conn in self._connections do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(self._connections)
    
    for _, limiter in self._playerLimiters do
        limiter:Destroy()
    end
    
    -- Ultimate memory sweep
    table.clear(self :: any)
end

return RemoteProtector
