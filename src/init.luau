--!strict
--[[
    @title RateLimiter V4 (Masterclass)
    @summary All-in-one high-performance rate limiting architecture.
]]

local RateManager = {}

-- Requirements
local SlidingWindow = require(script.Limiters.SlidingWindow)
local TokenBucket = require(script.Limiters.TokenBucket)
local Debounce = require(script.Limiters.Debounce)
local GlobalLimiter = require(script.Limiters.GlobalLimiter)
local RemoteProtector = require(script.RemoteProtector)

-- Factory: Sliding Window O(1)
function RateManager.createSlidingWindow(maxCalls: number, windowSeconds: number)
    return SlidingWindow.new(maxCalls, windowSeconds)
end

-- Factory: Token Bucket
function RateManager.createTokenBucket(maxTokens: number, refillRate: number)
    return TokenBucket.new(maxTokens, refillRate)
end

-- Factory: Debounce (Cooldown)
function RateManager.createDebounce(delaySeconds: number)
    return Debounce.new(delaySeconds)
end

-- Factory: Global Limiter (Cross-Server)
function RateManager.createGlobalLimiter(key: string, limit: number, windowSeconds: number)
    return GlobalLimiter.new(key, limit, windowSeconds)
end

-- Factory: RemoteProtector
function RateManager.createProtector(limiterFactory: () -> any, punishThreshold: number?, punishDurations: {number}?)
    return RemoteProtector.new(limiterFactory, punishThreshold, punishDurations)
end

return RateManager