--!strict
--!native
--!optimize 2
--[[
    @title Token Bucket Limiter
    @summary Efficient token bucket algorithm for burst handling and weighted requests.
]]
local os_clock = os.clock

local TokenBucket = {}
TokenBucket.__index = TokenBucket

export type TokenBucketInstance = {
    _max: number,
    _refillRate: number,
    _tokens: number,
    _lastRefill: number,
    
    Consume: (self: TokenBucketInstance, cost: number?, now: number?, peek: boolean?) -> boolean,
    SetCapacity: (self: TokenBucketInstance, maxTokens: number, refillRate: number) -> (),
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

function TokenBucket:Consume(cost: number?, now: number?, peek: boolean?): boolean
    local actualCost: number = cost or 1
    
    -- Immediate rejection of invalid/negative costs to prevent exploits
    if actualCost < 1 then
        return false
    end

    local actualNow: number = now or os_clock()
    
    -- Local cache to minimize table lookups
    local maxTokens = self._max
    local currentTokens = self._tokens
    local lastRefill = self._lastRefill

    local refill = (actualNow - lastRefill) * self._refillRate
    
    if refill > 0 then
        currentTokens += refill
        if currentTokens > maxTokens then
            currentTokens = maxTokens
        end
    end
    
    if currentTokens >= actualCost then
        if peek then return true end
        
        self._tokens = currentTokens - actualCost
        self._lastRefill = actualNow
        return true
    end
    
    return false
end

function TokenBucket:SetCapacity(maxTokens: number, refillRate: number)
    -- Settle the balance using the current rate before updating to prevent retroactive errors
    local now = os_clock()
    local elapsed = now - self._lastRefill
    
    if elapsed > 0 then
        local currentTokens = self._tokens + (elapsed * self._refillRate)
        self._tokens = if currentTokens > self._max then self._max else currentTokens
    end
    
    self._lastRefill = now

    -- Apply new constraints and ensure current tokens do not exceed the new maximum
    self._max = maxTokens
    self._refillRate = refillRate
    self._tokens = if self._tokens > maxTokens then maxTokens else self._tokens
end

function TokenBucket:ResetState()
    self._tokens = self._max
    self._lastRefill = os_clock()
end

-- Freeze the prototype to enable maximum inline caching and VM optimizations
table.freeze(TokenBucket)

return TokenBucket
