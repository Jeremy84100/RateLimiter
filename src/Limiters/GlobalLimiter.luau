--!strict
--[[
    @title Global Limiter
    @summary Distributed cross-server rate limiting using MemoryStoreService.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local os_time = os.time

local GlobalLimiter = {}
GlobalLimiter.__index = GlobalLimiter

export type GlobalLimiterInstance = {
    _key: string,
    _limit: number,
    _window: number,
    _store: any, -- MemoryStoreSortedMap
    
    ConsumeAsync: (self: GlobalLimiterInstance) -> boolean,
}

--[[
    Create a new instance of a global rate limiter.
    Uses MemoryStoreService to synchronize limits across all game servers.
]]
function GlobalLimiter.new(key: string, limit: number, windowSeconds: number): GlobalLimiterInstance
    local self = setmetatable({} :: any, GlobalLimiter)
    
    self._key = key
    self._limit = limit
    self._window = windowSeconds
    self._store = MemoryStoreService:GetSortedMap("GlobalRateLimiter")
    
    return self
end

--[[
    Attempts to consume a request on the global network.
    @returns true if permitted, false if limit reached or Roblox services are saturated.
]]
function GlobalLimiter:ConsumeAsync(): boolean
    local result = false
    
    -- pcall is mandatory as MemoryStore operations can fail (network errors or quota limits)
    local success = pcall(function()
        self._store:UpdateAsync(self._key, function(current: any)
            -- Reset result for each attempt; Roblox may retry the callback automatically.
            result = false 
            
            local now = os_time()
            current = current or { count = 0, resetAt = now + self._window }
            
            -- Reset counter if the time window has expired
            if now >= current.resetAt then
                current.count = 0
                current.resetAt = now + self._window
            end
            
            -- Increment and allow if below limit
            if current.count < self._limit then
                current.count += 1
                result = true
                return current
            end
            
            -- Limit reached: return nil to cancel transaction and optimize request budget
            return nil 
        end, self._window)
    end)
    
    -- Return true only if communication succeeded AND quota was available
    return if success then result else false
end

-- Freeze class for maximum inline caching and VM performance
table.freeze(GlobalLimiter)

return GlobalLimiter