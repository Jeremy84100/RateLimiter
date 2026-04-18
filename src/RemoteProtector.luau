--!strict
local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local os_clock = os.clock
local os_time = os.time

local RemoteProtector = {}
RemoteProtector.__index = RemoteProtector

export type RemoteProtectorInstance = {
    _limiterFactory: () -> any,
    _pool: {any},
    _activeLimiters: { [Player]: any },
    _punishThreshold: number,
    _punishDurations: {number},
    
    _persistencePrefix: string?,
    _store: any?,
    
    _playerData: { [Player]: { hits: number, timeoutUntil: number, escalation: number, isLoading: boolean? } },
    _cleaningConn: RBXScriptConnection?,
    
    Consume: (self: RemoteProtectorInstance, player: Player, cost: number?) -> boolean,
    EnablePersistence: (self: RemoteProtectorInstance, keyPrefix: string) -> (),
    Destroy: (self: RemoteProtectorInstance) -> (),
}

function RemoteProtector.new(limiterFactory: () -> any, punishThreshold: number?, punishDurations: {number}?): RemoteProtectorInstance
    local self = setmetatable({} :: any, RemoteProtector)
    
    self._limiterFactory = limiterFactory
    self._pool = {}
    self._activeLimiters = {}
    self._playerData = {}
    
    self._punishThreshold = punishThreshold or 5
    self._punishDurations = punishDurations or {10, 60, 300}
    
    self._cleaningConn = Players.PlayerRemoving:Connect(function(player: Player)
        -- 1. Sauvegarde Persistence avant le nettoyage
        if self._persistencePrefix and self._store then
            local data = self._playerData[player]
            if data and (data.timeoutUntil > os_clock() or data.escalation > 1) then
                local timeoutRemaining = math.max(0, math.floor(data.timeoutUntil - os_clock()))
                pcall(function()
                    self._store:SetAsync(self._persistencePrefix .. "_" .. player.UserId, {
                        timeoutEnd = os_time() + timeoutRemaining,
                        escalation = data.escalation
                    }, 86400) -- Expire après 24h
                end)
            end
        end

        -- 2. Recyclage du Limiteur
        local limiter = self._activeLimiters[player]
        if limiter then
            if limiter.ResetState then limiter:ResetState() end
            table.insert(self._pool, limiter)
            self._activeLimiters[player] = nil
        end
        self._playerData[player] = nil
    end)
    
    return self
end

function RemoteProtector:EnablePersistence(keyPrefix: string)
    self._persistencePrefix = keyPrefix
    self._store = MemoryStoreService:GetSortedMap("RateLimiter_Persistence")
end

function RemoteProtector:Consume(player: Player, cost: number?): boolean
    local now = os_clock()
    local data = self._playerData[player]
    
    if not data then
        data = { hits = 0, timeoutUntil = 0, escalation = 1, isLoading = false }
        self._playerData[player] = data
        
        -- Load asynchrone si persistence active
        if self._persistencePrefix and self._store then
            data.isLoading = true
            task.spawn(function()
                local success, persisted = pcall(function()
                    return self._store:GetAsync(self._persistencePrefix .. "_" .. (player.UserId :: any))
                end)
                if success and persisted and data then
                    local timeRemaining = persisted.timeoutEnd - os_time()
                    if timeRemaining > 0 then
                        data.timeoutUntil = os_clock() + timeRemaining
                    end
                    data.escalation = persisted.escalation or 1
                end
                data.isLoading = false
            end)
        end
    end
    
    if now < data.timeoutUntil then return false end
    
    local limiter = self._activeLimiters[player]
    if not limiter then
        limiter = table.remove(self._pool) or self._limiterFactory()
        self._activeLimiters[player] = limiter
    end
    
    if limiter:Consume(cost, now) then
        data.hits = 0 
        return true
    else
        data.hits += 1
        if data.hits >= self._punishThreshold then
            local duration = self._punishDurations[data.escalation] or self._punishDurations[#self._punishDurations]
            data.timeoutUntil = now + duration
            data.hits = 0
            if data.escalation < #self._punishDurations then data.escalation += 1 end
        end
        return false
    end
end

function RemoteProtector:Destroy()
    if self._cleaningConn then self._cleaningConn:Disconnect() end
    table.clear(self._activeLimiters)
    table.clear(self._pool)
    table.clear(self :: any)
end

return RemoteProtector
