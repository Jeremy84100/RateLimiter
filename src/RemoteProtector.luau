--!strict
--!native
--!optimize 2
--[[
    @title RemoteProtector
    @summary Managed player rate limiting with persistence and punishment support.
]]
local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local os_clock = os.clock
local os_time = os.time
local math_max = math.max
local math_floor = math.floor

local RemoteProtector = {}
RemoteProtector.__index = RemoteProtector

-- Strictly typed player data for performance and clarity
type PlayerData = { 
    hits: number, 
    timeoutUntil: number, 
    escalation: number, 
    isLoading: boolean,
    limiter: any 
}

export type RemoteProtectorInstance = {
    _limiterFactory: () -> any,
    _pool: {any},
    _punishThreshold: number,
    _punishDurations: {number},
    
    _persistencePrefix: string?,
    _store: any?,
    
    _playerData: { [Player]: PlayerData },
    _playerAddedConn: RBXScriptConnection?,
    _playerRemovingConn: RBXScriptConnection?,
    
    Consume: (self: RemoteProtectorInstance, player: Player, cost: number?, peek: boolean?) -> boolean,
    SetCapacityForPlayer: (self: RemoteProtectorInstance, player: Player, ...any) -> (),
    UpdateCapacities: (self: RemoteProtectorInstance, ...any) -> (),
    EnablePersistence: (self: RemoteProtectorInstance, keyPrefix: string) -> (),
    _initPlayer: (self: RemoteProtectorInstance, player: Player) -> (),
    Destroy: (self: RemoteProtectorInstance) -> (),
}

function RemoteProtector.new(limiterFactory: () -> any, punishThreshold: number?, punishDurations: {number}?): RemoteProtectorInstance
    local self = setmetatable({} :: any, RemoteProtector)
    
    self._limiterFactory = limiterFactory
    self._pool = {}
    self._playerData = {}
    
    self._punishThreshold = punishThreshold or 5
    self._punishDurations = punishDurations or {10, 60, 300}
    
    self._playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
        local data = self._playerData[player]
        if not data then return end

        if self._persistencePrefix and self._store then
            if data.timeoutUntil > os_clock() or data.escalation > 1 then
                local timeoutRemaining = math_max(0, math_floor(data.timeoutUntil - os_clock()))
                pcall(function()
                    self._store:SetAsync(self._persistencePrefix .. "_" .. player.UserId, {
                        timeoutEnd = os_time() + timeoutRemaining,
                        escalation = data.escalation
                    }, 86400)
                end)
            end
        end

        local limiter = data.limiter
        if limiter then
            if limiter.ResetState then limiter:ResetState() end
            self._pool[#self._pool + 1] = limiter 
        end
        self._playerData[player] = nil
    end)
    
    self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
        self:_initPlayer(player)
    end)

    for _, player in Players:GetPlayers() do
        task.spawn(self._initPlayer, self, player)
    end
    
    return self
end

function RemoteProtector:_initPlayer(player: Player)
    if self._playerData[player] then return end
    
    local poolSize = #self._pool
    local limiter = if poolSize > 0 then self._pool[poolSize] else self._limiterFactory()
    if poolSize > 0 then self._pool[poolSize] = nil end
    
    local data: PlayerData = { 
        hits = 0, 
        timeoutUntil = 0, 
        escalation = 1, 
        isLoading = false,
        limiter = limiter 
    }
    self._playerData[player] = data
    
    if self._persistencePrefix and self._store then
        data.isLoading = true
        task.spawn(function()
            local success, persisted = pcall(function()
                return self._store:GetAsync(self._persistencePrefix .. "_" .. (player.UserId :: any))
            end)
            if success and persisted and self._playerData[player] then
                local timeRemaining = persisted.timeoutEnd - os_time()
                if timeRemaining > 0 then
                    self._playerData[player].timeoutUntil = os_clock() + timeRemaining
                end
                self._playerData[player].escalation = persisted.escalation or 1
            end
            if self._playerData[player] then
                self._playerData[player].isLoading = false
            end
        end)
    end
end

function RemoteProtector:EnablePersistence(keyPrefix: string)
    self._persistencePrefix = keyPrefix
    self._store = MemoryStoreService:GetSortedMap("RateLimiter_Persistence")
end

function RemoteProtector:SetCapacityForPlayer(player: Player, ...: any)
    local data = self._playerData[player]
    if data and data.limiter and data.limiter.SetCapacity then
        data.limiter:SetCapacity(...)
    end
end

function RemoteProtector:UpdateCapacities(...: any)
    local first = select(1, ...)
    local startIdx = 1
    if type(first) == "function" then
        self._limiterFactory = first
        startIdx = 2
    end
    
    for _, data in self._playerData do
        if data.limiter and data.limiter.SetCapacity then 
            data.limiter:SetCapacity(select(startIdx, ...)) 
        end
    end
    for _, limiter in self._pool do
        if limiter.SetCapacity then limiter:SetCapacity(select(startIdx, ...)) end
    end
end

-- Critical path: implementation uses zero-allocation and branch flattening
function RemoteProtector:Consume(player: Player, cost: number?, peek: boolean?): boolean
    local data = self._playerData[player]
    
    -- Guard clauses
    if not data or data.isLoading then return false end

    local actualNow = os_clock()
    if actualNow < data.timeoutUntil then return false end
    
    local limiter = data.limiter
    
    -- Optimized branch: success path
    if limiter:Consume(cost, actualNow, peek) then
        if not peek then data.hits = 0 end
        return true
    end
    
    -- If execution reaches here, the action was rejected by the limiter.
    -- If this was a peek (UI check), exit without applying punishment.
    if peek then return false end

    -- Punishment logic for violation thresholds
    data.hits += 1
    
    local threshold = self._punishThreshold
    if data.hits >= threshold then
        local durations = self._punishDurations
        local escalation = data.escalation
        local maxEscalation = #durations
        
        data.timeoutUntil = actualNow + (durations[escalation] or durations[maxEscalation])
        data.hits = 0
        
        if escalation < maxEscalation then 
            data.escalation += 1 
        end

        if limiter.ResetState then limiter:ResetState() end
    end
    
    return false
end

function RemoteProtector:Destroy()
    if self._playerAddedConn then self._playerAddedConn:Disconnect() end
    if self._playerRemovingConn then self._playerRemovingConn:Disconnect() end
    table.clear(self._playerData)
    table.clear(self._pool)
    table.clear(self :: any)
end

table.freeze(RemoteProtector)
return RemoteProtector