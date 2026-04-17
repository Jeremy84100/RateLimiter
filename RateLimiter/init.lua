--!strict

--[[
    @title RateLimiter API
    @author @IFloXieI
    @license MIT
    
    A high-performance, strictly-typed rate limiting framework for Roblox.
    Features include:
    - O(1) Sliding Window (Circular Buffer)
    - Token Bucket optimization
    - Composite/Dual-window limiting
    - Cross-server Global rate limiting
    - MemoryStore-based persistence for punishments
]]

local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Signal = require(script.signal)

-- Micro-optimizations: Cache standard library for fast local access
local os_clock = os.clock
local os_time = os.time

local t_insert = table.insert
local t_move = table.move
local t_pack = table.pack
local t_unpack = table.unpack
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local task_spawn = task.spawn

-- Types
export type Mode = number
type SignalType = typeof(Signal.new())

export type RateLimitConfig = {
    max: number,
    window: number,
}

export type RateManagerInstance = {
    mode: Mode,
    OnReset: SignalType,
    OnLimitHit: SignalType,
    OnWarning: SignalType,
    
    -- Configuration
    delay: number?,
    active: boolean?,
    maxCalls: number?,
    perSeconds: number?,
    
    -- TokenBucket internal state
    _maxTokens: number?,
    _tokens: number,
    _refillRate: number?,
    _lastRefill: number,
    
    -- Composite internal state
    _children: {RateManagerInstance}?,
    
    -- Sliding Window state (Circular Buffer)
    callTimestamps: {number}?,
    _head: number,
    _tail: number,
    _count: number,
    _paused: boolean,
    _lastStartTime: number,
    
    -- Punishment & Escalation Matrix
    _consecutiveHits: number,
    _punishThreshold: number?,
    _punishDurations: {number}?,
    _escalationLevel: number,
    _lastViolationTime: number,
    _timeoutUntil: number,
    
    -- Methods
    Execute: (self: RateManagerInstance, func: (...any) -> ...any, ...any) -> RateManagerInstance,
    ExecuteWithCost: (self: RateManagerInstance, cost: number, func: (...any) -> ...any, ...any) -> RateManagerInstance,
    SetPunishment: (self: RateManagerInstance, threshold: number, durations: number | {number}) -> RateManagerInstance,
    SetCapacity: (self: RateManagerInstance, maxOrTokens: number, refillOrWindow: number?) -> (),
    Destroy: (self: RateManagerInstance) -> (),
    Reset: (self: RateManagerInstance) -> (),
    _isLimited: (self: RateManagerInstance, cost: number, now: number) -> boolean,
    _commit: (self: RateManagerInstance, cost: number, now: number) -> (),
}

local RateManager = {}
RateManager.__index = RateManager

RateManager.Mode = {
    Debounce = 1,
    RateLimit = 2,
    TokenBucket = 3,
    Composite = 4,
}

local Mode = RateManager.Mode
local PERSISTENCE_EXPIRY = 86400 -- Expiration in seconds for MemoryStore

-- Purges expired timestamps from the circular buffer
local function cleanupOldTimestamps(self: RateManagerInstance, now: number)
    local timestamps = self.callTimestamps
    if not timestamps or not self.perSeconds then return end
    
    local max = self.maxCalls or 0
    while self._count > 0 do
        local oldest = timestamps[self._head]
        if oldest and (now - oldest) > self.perSeconds then
            self._head = (self._head % max) + 1
            self._count -= 1
        else
            break
        end
    end
end

function RateManager.new(delayOrMax: number | {RateLimitConfig}, perSecondsOrRefill: number?, mode: Mode?): RateManagerInstance
    local self = setmetatable({} :: any, RateManager)
    
    self.mode = mode or Mode.Debounce
    self.OnReset = Signal.new()
    self.OnLimitHit = Signal.new()
    self.OnWarning = Signal.new()
    
    self._paused = false
    self._consecutiveHits = 0
    self._escalationLevel = 1
    self._lastViolationTime = 0
    self._timeoutUntil = 0
    self._head = 1
    self._tail = 1
    self._count = 0
    self._lastStartTime = 0
    
    if self.mode == Mode.Debounce then
        self.delay = delayOrMax :: number
        self.active = false
    elseif self.mode == Mode.RateLimit then
        self.maxCalls = delayOrMax :: number
        self.perSeconds = perSecondsOrRefill
        self.callTimestamps = table.create(self.maxCalls)
    elseif self.mode == Mode.TokenBucket then
        self._maxTokens = delayOrMax :: number
        self._tokens = delayOrMax :: number
        self._refillRate = perSecondsOrRefill
        self._lastRefill = os_clock()
    elseif self.mode == Mode.Composite then
        self._children = {}
        for _, config in (delayOrMax :: {RateLimitConfig}) do
            t_insert(self._children :: {}, RateManager.new(config.max, config.window, Mode.RateLimit))
        end
    end
    
    return self
end

-- Adjusts the manager capacity at runtime without resetting state
function RateManager:SetCapacity(maxOrTokens: number, refillOrWindow: number?)
    if self.mode == Mode.Debounce then
        self.delay = maxOrTokens
    elseif self.mode == Mode.RateLimit then
        self.maxCalls = maxOrTokens
        self.perSeconds = refillOrWindow or self.perSeconds
        self.callTimestamps = table.create(maxOrTokens)
        self._head = 1
        self._tail = 1
        self._count = 0
    elseif self.mode == Mode.TokenBucket then
        local diff = maxOrTokens - (self._maxTokens or 0)
        self._maxTokens = maxOrTokens
        self._refillRate = refillOrWindow or self._refillRate
        self._tokens = math_max(0, self._tokens + diff)
    elseif self.mode == Mode.Composite then
        warn("[RateLimiter] SetCapacity is not supported directly for Composite mode. Modify children instead.")
    end
end

-- Configures ban durations when the limit is hit repeatedly
function RateManager:SetPunishment(threshold: number, durations: number | {number}): RateManagerInstance
    self._punishThreshold = threshold
    self._punishDurations = type(durations) == "table" and durations or {durations}
    return self
end

-- Mathematical replenishment for Token Bucket mode
function RateManager:_updateTokens(now: number)
    if self.mode ~= Mode.TokenBucket then return end
    local elapsed = now - self._lastRefill
    local refill = elapsed * (self._refillRate or 0)
    if refill > 0 then
        self._tokens = math_min(self._maxTokens or 0, self._tokens + refill)
        self._lastRefill = now
    end
end

-- Validates whether an action can be performed without committing state
function RateManager:_isLimited(cost: number, now: number): boolean
    if self.mode == Mode.Debounce then
        if self.active and now - self._lastStartTime < (self.delay or 0) then
            return true
        else
            self.active = false
            return false
        end
    elseif self.mode == Mode.RateLimit then
        cleanupOldTimestamps(self, now)
        local max = self.maxCalls or 0
        if self._count >= (max * 0.8) then self.OnWarning:Fire(self._count, max) end
        return self._count + cost > max
    elseif self.mode == Mode.TokenBucket then
        self:_updateTokens(now)
        return self._tokens < cost
    elseif self.mode == Mode.Composite then
        for _, child in self._children :: {} do
            if child:_isLimited(cost, now) then return true end
        end
        return false
    end
    return false
end

-- Finalizes the execution and consumes resources
function RateManager:_commit(cost: number, now: number)
    if self.mode == Mode.Debounce then
        self.active = true
        self._lastStartTime = now
    elseif self.mode == Mode.RateLimit then
        local timestamps = self.callTimestamps :: {number}
        local max = self.maxCalls or 0
        for _ = 1, cost do
            timestamps[self._tail] = now
            self._tail = (self._tail % max) + 1
        end
        self._count += cost
    elseif self.mode == Mode.TokenBucket then
        self._tokens -= cost
    elseif self.mode == Mode.Composite then
        for _, child in self._children :: {} do
            child:_commit(cost, now)
        end
    end
    self._consecutiveHits = 0
end

-- Escalates the punishment level
function RateManager:_triggerEscalation(now: number)
    local durations = self._punishDurations or {10}
    local maxPunish = durations[#durations]
    
    -- Reset escalation if enough time has passed since last violation
    if (now - self._lastViolationTime) > (maxPunish * 2) then
        self._escalationLevel = 1
    end
    
    local duration = durations[self._escalationLevel] or durations[#durations]
    self._timeoutUntil = now + duration
    self._lastViolationTime = now
    
    if self._escalationLevel < #durations then
        self._escalationLevel += 1
    end
end

function RateManager:Execute(func: (...any) -> ...any, ...: any): RateManagerInstance
    return self:ExecuteWithCost(1, func, ...)
end

function RateManager:ExecuteWithCost(cost: number, func: (...any) -> ...any, ...: any): RateManagerInstance
    if self._paused then return self end
    local now = os_clock()

    -- Static configuration validation
    local maxLimit = 0
    if self.mode == Mode.RateLimit then maxLimit = self.maxCalls or 0
    elseif self.mode == Mode.TokenBucket then maxLimit = self._maxTokens or 0
    elseif self.mode == Mode.Composite then
        maxLimit = math.huge
        for _, child in self._children :: {} do
            maxLimit = math_min(maxLimit, child.maxCalls or child._maxTokens or math.huge)
        end
    end

    -- Prevent unreachable cost scenarios
    if cost > maxLimit and self.mode ~= Mode.Debounce then
        warn(string.format("[RateManager] Execution failed: cost (%d) exceeds max capacity (%d).", cost, maxLimit))
        self.OnLimitHit:Fire()
        return self
    end
    
    -- Check if player is currently banned
    if now < self._timeoutUntil then
        self.OnLimitHit:Fire()
        return self
    end
    
    if self:_isLimited(cost, now) then
        self.OnLimitHit:Fire()
        if self._punishThreshold then
            self._consecutiveHits += 1
            if self._consecutiveHits >= self._punishThreshold then
                self:_triggerEscalation(now)
            end
        end
        return self
    end
    
    self:_commit(cost, now)
    func(...)
    return self
end

function RateManager:Destroy()
    self._paused = true
    if self.OnReset then self.OnReset:Destroy() end
    if self.OnLimitHit then self.OnLimitHit:Destroy() end
    if self.OnWarning then self.OnWarning:Destroy() end
    if self._children then
        for _, child in self._children do child:Destroy() end
    end
    table.clear(self :: any)
end

function RateManager:Reset()
    self.active = false
    local max = self.maxCalls or 0
    if self.callTimestamps then
        self.callTimestamps = table.create(max)
    end
    self._head = 1
    self._tail = 1
    self._count = 0
    self._tokens = self._maxTokens or 0
    self._lastRefill = os_clock()
    self._timeoutUntil = 0
    self._consecutiveHits = 0
    self._lastStartTime = 0
    if self._children then
        for _, child in self._children do child:Reset() end
    end
    self.OnReset:Fire()
end

--------------------------------------------------------------------------------
-- PlayerLimiter: Auto-instancing with Persistence support
--------------------------------------------------------------------------------

export type PlayerLimiter = {
    _config: {any},
    _limiters: { [Player]: RateManagerInstance },
    _playerAddedConn: RBXScriptConnection?,
    _playerRemovingConn: RBXScriptConnection?,
    _persistencePrefix: string?,
    _store: any?,
    
    ExecuteFor: (self: PlayerLimiter, player: Player, func: (...any) -> ...any, ...any) -> RateManagerInstance,
    ExecuteForWithCost: (self: PlayerLimiter, cost: number, player: Player, func: (...any) -> ...any, ...any) -> RateManagerInstance,
    SetCapacity: (self: PlayerLimiter, maxOrTokens: number, refillOrWindow: number?) -> (),
    EnablePersistence: (self: PlayerLimiter, keyPrefix: string) -> (),
    Destroy: (self: PlayerLimiter) -> (),
}

local PlayerLimiter = {}
PlayerLimiter.__index = PlayerLimiter

function RateManager.PlayerLimiter(delayOrMax: number | {RateLimitConfig}, perSecondsOrRefill: number?, mode: Mode?): PlayerLimiter
    local self = setmetatable({} :: any, PlayerLimiter)
    self._config = {delayOrMax, perSecondsOrRefill, mode or Mode.Debounce}
    self._limiters = {}
    
    self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
        local c = self._config
        local limiter = RateManager.new(c[1], c[2], c[3])
        self._limiters[player] = limiter
        if self._persistencePrefix then
            task_spawn(function() self:_loadFromMemoryStore(player, limiter) end)
        end
    end)
    
    for _, player in Players:GetPlayers() do
        local c = self._config
        local limiter = RateManager.new(c[1], c[2], c[3])
        self._limiters[player] = limiter
    end

    self._playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        local limiter = self._limiters[player]
        if limiter then
            if self._persistencePrefix then
                self:_saveToMemoryStore(player, limiter)
            end
            limiter:Destroy()
            self._limiters[player] = nil
        end
    end)
    
    return self
end

function PlayerLimiter:SetCapacity(maxOrTokens: number, refillOrWindow: number?)
    self._config[1] = maxOrTokens
    self._config[2] = refillOrWindow or self._config[2]
    for _, limiter in self._limiters do
        limiter:SetCapacity(maxOrTokens, refillOrWindow)
    end
end

function PlayerLimiter:EnablePersistence(keyPrefix: string)
    self._persistencePrefix = keyPrefix
    self._store = MemoryStoreService:GetSortedMap("RateLimiter_Persistence")
end

function PlayerLimiter:_saveToMemoryStore(player: Player, limiter: RateManagerInstance)
    if not self._store or not self._persistencePrefix then return end
    local key = self._persistencePrefix .. "_" .. (player.UserId :: any)
    local now = os_time()
    
    if limiter._timeoutUntil > os_clock() or limiter._escalationLevel > 1 then
        local timeoutRemaining = math_max(0, math_floor(limiter._timeoutUntil - os_clock()))
        local data = {
            timeoutEnd = now + timeoutRemaining,
            escalation = limiter._escalationLevel,
            lastViolation = now
        }
        
        pcall(function()
            self._store:SetAsync(key, data, PERSISTENCE_EXPIRY)
        end)
    end
end

function PlayerLimiter:_loadFromMemoryStore(player: Player, limiter: RateManagerInstance)
    if not self._store or not self._persistencePrefix then return end
    local key = self._persistencePrefix .. "_" .. (player.UserId :: any)
    
    local success, data = pcall(function()
        return self._store:GetAsync(key)
    end)
    
    if success and data then
        local now = os_time()
        if data.timeoutEnd > now then
            limiter._timeoutUntil = os_clock() + (data.timeoutEnd - now)
        end
        limiter._escalationLevel = data.escalation or 1
        limiter._lastViolationTime = os_clock() - (now - (data.lastViolation or now))
    end
end

function PlayerLimiter:ExecuteFor(player: Player, func: (...any) -> ...any, ...: any): RateManagerInstance
    return self:ExecuteForWithCost(1, player, func, ...)
end

function PlayerLimiter:_fixLimiter(player: Player): RateManagerInstance
    local c = self._config
    local limiter = RateManager.new(c[1], c[2], c[3])
    self._limiters[player] = limiter
    return limiter
end

function PlayerLimiter:ExecuteForWithCost(cost: number, player: Player, func: (...any) -> ...any, ...: any): RateManagerInstance
    local limiter = self._limiters[player]
    if not limiter then
        limiter = self:_fixLimiter(player)
    end
    return limiter:ExecuteWithCost(cost, func, ...)
end

function PlayerLimiter:Destroy()
    if self._playerAddedConn then self._playerAddedConn:Disconnect() end
    if self._playerRemovingConn then self._playerRemovingConn:Disconnect() end
    for player, limiter in self._limiters do
        if self._persistencePrefix then self:_saveToMemoryStore(player, limiter) end
        limiter:Destroy()
    end
    table.clear(self :: any)
end

--------------------------------------------------------------------------------
-- GlobalLimiter: Distributed Cross-Server rate limiting
--------------------------------------------------------------------------------

export type GlobalLimiterInstance = {
    _key: string,
    _limit: number,
    _window: number,
    _map: any,
    ExecuteAsync: (self: GlobalLimiterInstance, func: (...any) -> ...any, ...any) -> boolean,
}

local GlobalLimiter = {}
GlobalLimiter.__index = GlobalLimiter

function RateManager.GlobalLimiter(key: string, limit: number, window: number): GlobalLimiterInstance
    local self = setmetatable({} :: any, GlobalLimiter)
    self._key = key
    self._limit = limit
    self._window = window
    self._map = MemoryStoreService:GetSortedMap("GlobalRateLimiter")
    return self
end

function GlobalLimiter:ExecuteAsync(func: (...any) -> ...any, ...: any): boolean
    local args = t_pack(...)
    local allowed = false
    
    local success = pcall(function()
        self._map:UpdateAsync(self._key, function(current: any)
            current = current or { count = 0, resetAt = os_time() + self._window }
            if os_time() >= current.resetAt then
                current.count = 0
                current.resetAt = os_time() + self._window
            end
            
            if current.count < self._limit then
                current.count += 1
                allowed = true
                return current
            end
            return nil
        end, self._window)
    end)
    
    if success and allowed then
        task_spawn(func, t_unpack(args, 1, args.n))
        return true
    end
    return false
end


-- Expose the wrapper directly from the main module
RateManager.RemoteProtector = require(script.RemoteProtector)

return RateManager