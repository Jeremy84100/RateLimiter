--!strict
local os_clock = os.clock

local TokenBucket = {}
TokenBucket.__index = TokenBucket

export type TokenBucketInstance = {
    _max: number,
    _refillRate: number,
    _tokens: number,
    _lastRefill: number,
    
    Consume: (self: TokenBucketInstance, cost: number?, now: number?) -> boolean,
    ResetState: (self: TokenBucketInstance) -> (),
}

function TokenBucket.new(maxTokens: number, refillRatePerSecond: number): TokenBucketInstance
    local self = setmetatable({} :: any, TokenBucket)
    
    self._max = maxTokens
    self._refillRate = refillRatePerSecond
    self._tokens = maxTokens
    self._lastRefill = os_clock()
    
    return self
end

function TokenBucket:Consume(cost: number?, now: number?): boolean
    local currentTime = now or os_clock()
    local requestedCost = cost or 1
    
    -- 1. Calcul du remplissage (Replenishment)
    local elapsed = currentTime - self._lastRefill
    local refill = elapsed * self._refillRate
    
    if refill > 0 then
        self._tokens = math.min(self._max, self._tokens + refill)
        self._lastRefill = currentTime
    end
    
    -- 2. Vérification de la capacité
    if self._tokens >= requestedCost then
        self._tokens -= requestedCost
        return true
    end
    
    return false
end

function TokenBucket:ResetState()
    self._tokens = self._max
    self._lastRefill = os_clock()
end

return TokenBucket
