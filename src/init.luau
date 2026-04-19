--!strict
--[[
    @title RateLimiter V4
    @author @Jeremy84100
    @license MIT
    
    A high-performance, strictly-typed rate limiting framework for Roblox.
]]

local RateManager = {}

-- Requirements
local SlidingWindow = require(script.Limiters.SlidingWindow)
local TokenBucket = require(script.Limiters.TokenBucket)
local Debounce = require(script.Limiters.Debounce)
local Composite = require(script.Limiters.Composite)
local GlobalLimiter = require(script.Limiters.GlobalLimiter)
local RemoteProtector = require(script.RemoteProtector)

export type SlidingWindowInstance = SlidingWindow.SlidingWindowInstance
export type TokenBucketInstance = TokenBucket.TokenBucketInstance
export type DebounceInstance = Debounce.DebounceInstance
export type CompositeInstance = Composite.CompositeInstance
export type GlobalLimiterInstance = GlobalLimiter.GlobalLimiterInstance
export type RemoteProtectorInstance = RemoteProtector.RemoteProtectorInstance

function RateManager.createSlidingWindow(maxCalls: number, windowSeconds: number): SlidingWindowInstance
    return SlidingWindow.new(maxCalls, windowSeconds)
end

-- Factory: Token Bucket
function RateManager.createTokenBucket(maxTokens: number, refillRate: number): TokenBucketInstance
    return TokenBucket.new(maxTokens, refillRate)
end

-- Factory: Debounce (Cooldown)
function RateManager.createDebounce(delaySeconds: number): DebounceInstance
    return Debounce.new(delaySeconds)
end

-- Factory: Composite
function RateManager.createComposite(limiters: {any}): CompositeInstance
    return Composite.new(limiters)
end

-- Factory: Global Limiter (Cross-Server)
function RateManager.createGlobalLimiter(key: string, limit: number, windowSeconds: number): GlobalLimiterInstance
    return GlobalLimiter.new(key, limit, windowSeconds)
end

-- Factory: RemoteProtector
function RateManager.createProtector(limiterFactory: () -> any, punishThreshold: number?, punishDurations: {number}?): RemoteProtectorInstance
    return RemoteProtector.new(limiterFactory, punishThreshold, punishDurations)
end

-- Freeze for security and maximum VM performance
table.freeze(RateManager)

return RateManager