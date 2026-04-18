--!strict
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

function GlobalLimiter.new(key: string, limit: number, windowSeconds: number): GlobalLimiterInstance
    local self = setmetatable({} :: any, GlobalLimiter)
    
    self._key = key
    self._limit = limit
    self._window = windowSeconds
    self._store = MemoryStoreService:GetSortedMap("GlobalRateLimiter")
    
    return self
end

--[[
    Vérifie la limite globale sur l'infrastructure Roblox.
    @returns true si autorisé, false si limité ou erreur MS.
]]
function GlobalLimiter:ConsumeAsync(): boolean
    local success, allowed = pcall(function()
        local result = false
        self._store:UpdateAsync(self._key, function(current: any)
            local now = os_time()
            current = current or { count = 0, resetAt = now + self._window }
            
            -- Reset si la fenêtre est expirée
            if now >= current.resetAt then
                current.count = 0
                current.resetAt = now + self._window
            end
            
            if current.count < self._limit then
                current.count += 1
                result = true
                return current
            end
            
            return nil -- Ne pas mettre à jour si on est au max
        end, self._window)
        return result
    end)
    
    return if success then allowed else false
end

return GlobalLimiter
