--!strict
local os_clock = os.clock

local Debounce = {}
Debounce.__index = Debounce

export type DebounceInstance = {
    _delay: number,
    _lastTime: number,
    
    Consume: (self: DebounceInstance, cost: number?, now: number?) -> boolean,
    ResetState: (self: DebounceInstance) -> (),
}

function Debounce.new(delaySeconds: number): DebounceInstance
    local self = setmetatable({} :: any, Debounce)
    
    self._delay = delaySeconds
    self._lastTime = 0
    
    return self
end

function Debounce:Consume(cost: number?, now: number?): boolean
    local currentTime = now or os_clock()
    
    if currentTime - self._lastTime >= self._delay then
        self._lastTime = currentTime
        return true
    end
    
    return false
end

function Debounce:ResetState()
    self._lastTime = 0
end

return Debounce
