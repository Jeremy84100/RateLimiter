--!strict
--[[
    @title SlidingWindow Limiter (O(1))
    @summary A memory-efficient, zero-allocation rate limiter using a circular buffer.
]]

local SlidingWindow = {}
SlidingWindow.__index = SlidingWindow

export type SlidingWindowInstance = {
    _max: number,
    _window: number,
    _buffer: {number},
    _head: number,
    _tail: number,
    _count: number,
    
    Consume: (self: SlidingWindowInstance, cost: number?, now: number?) -> boolean,
    ResetState: (self: SlidingWindowInstance) -> (),
}

--[[
    Creates a new SlidingWindow instance with pre-allocated memory.
]]
function SlidingWindow.new(maxCalls: number, windowSeconds: number): SlidingWindowInstance
    local self = setmetatable({} :: any, SlidingWindow)
    
    self._max = maxCalls
    self._window = windowSeconds
    self._buffer = table.create(maxCalls, 0) -- Pre-allocation for Zero-Allocation runtime
    self._head = 1
    self._tail = 1
    self._count = 0
    
    return self
end

--[[
    Checks if a request can be consumed.
    @returns true if allowed, false if rate limited.
]]
function SlidingWindow:Consume(cost: number?, now: number?): boolean
    local currentTime = now or os.clock()
    local requestedCost = cost or 1
    
    -- 1. Remove expired timestamps (Constant Time amortized)
    while self._count > 0 do
        local oldest = self._buffer[self._head]
        if currentTime - oldest >= self._window then
            self._head = (self._head % self._max) + 1
            self._count -= 1
        else
            break
        end
    end
    
    -- 2. Check Capacity
    if self._count + requestedCost <= self._max then
        -- 3. Add new timestamps (Circular update)
        for _ = 1, requestedCost do
            self._buffer[self._tail] = currentTime
            self._tail = (self._tail % self._max) + 1
            self._count += 1
        end
        return true
    end
    
    return false
end

--[[
    Resets the internal state for Object Pooling reuse.
]]
function SlidingWindow:ResetState()
    self._count = 0
    self._head = 1
    self._tail = 1
    -- No table.clear on buffer to keep memory allocation
end

return SlidingWindow
