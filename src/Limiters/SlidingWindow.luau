--!strict
--!native
--!optimize 2
--[[
    @title Sliding Window Limiter
    @summary Real O(1) sliding window algorithm using a pre-allocated circular buffer.
]]
local os_clock = os.clock

local SlidingWindow = {}
SlidingWindow.__index = SlidingWindow

export type SlidingWindowInstance = {
    _max: number,
    _window: number,
    _buffer: {number},
    _head: number,
    _tail: number,
    _count: number,
    
    Consume: (self: SlidingWindowInstance, cost: number?, now: number?, peek: boolean?) -> boolean,
    SetCapacity: (self: SlidingWindowInstance, maxCalls: number, windowSeconds: number) -> (),
    ResetState: (self: SlidingWindowInstance) -> (),
}

function SlidingWindow.new(maxCalls: number, windowSeconds: number): SlidingWindowInstance
    local self = setmetatable({} :: any, SlidingWindow)
    
    self._max = maxCalls
    self._window = windowSeconds
    self._buffer = table.create(maxCalls, 0)
    self._head = 1
    self._tail = 1
    self._count = 0
    
    return self
end

function SlidingWindow:Consume(cost: number?, now: number?, peek: boolean?): boolean
    local actualNow: number = now or os_clock()
    local actualCost: number = cost or 1
    
    -- Prevent invalid/negative costs to block exploits
    if actualCost < 1 then 
        return false 
    end
    
    local max = self._max
    local window = self._window
    local buffer = self._buffer
    
    -- 1. Eviction (Zero-allocation cleanup)
    local head = self._head
    local count = self._count
    while count > 0 do
        if actualNow - buffer[head] >= window then
            head += 1
            if head > max then head = 1 end
            count -= 1
        else
            break
        end
    end
    
    -- 2. Availability check
    if count + actualCost <= max then
        if peek then return true end
        
        -- 3. Circular buffer write 
        -- Luau compiler will optimize this loop automatically
        local tail = self._tail
        for _ = 1, actualCost do
            buffer[tail] = actualNow
            tail += 1
            if tail > max then tail = 1 end
        end
        
        self._head = head
        self._tail = tail
        self._count = count + actualCost
        
        return true
    end
    
    return false
end

function SlidingWindow:SetCapacity(maxCalls: number, windowSeconds: number)
    self._window = windowSeconds
    
    if maxCalls ~= self._max then
        local newBuffer = table.create(maxCalls, 0)
        local oldBuffer = self._buffer
        local head = self._head
        local oldMax = self._max
        
        local keepCount = self._count
        if keepCount > maxCalls then
            head += (keepCount - maxCalls)
            if head > oldMax then head -= oldMax end
            keepCount = maxCalls
        end
        
        for i = 1, keepCount do
            newBuffer[i] = oldBuffer[head]
            head += 1
            if head > oldMax then head = 1 end
        end
        
        self._buffer = newBuffer
        self._max = maxCalls
        self._count = keepCount
        self._head = 1
        
        self._tail = keepCount + 1
        if self._tail > maxCalls then self._tail = 1 end
    end
end

function SlidingWindow:ResetState()
    self._count = 0
    self._head = 1
    self._tail = 1
end

table.freeze(SlidingWindow)

return SlidingWindow