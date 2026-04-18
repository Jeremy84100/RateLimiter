--!strict
--!native
--!optimize 2
--[[
    @title Debounce Limiter
    @summary Simple cooldown-based rate limiting (debounce).
]]
local os_clock = os.clock

local Debounce = {}
Debounce.__index = Debounce

export type DebounceInstance = {
    _cooldown: number,
    _lastCall: number,
    
    Consume: (self: DebounceInstance, cost: number?, now: number?, peek: boolean?) -> boolean,
    SetCapacity: (self: DebounceInstance, delaySeconds: number) -> (),
    ResetState: (self: DebounceInstance) -> (),
}

function Debounce.new(cooldownSeconds: number): DebounceInstance
    local self = setmetatable({} :: any, Debounce)
    
    self._cooldown = cooldownSeconds
    
    -- Initialize in the past to avoid blocking the first call after server startup
    self._lastCall = -cooldownSeconds
    
    return self
end

function Debounce:Consume(cost: number?, now: number?, peek: boolean?): boolean
    -- Prevent exploits using negative costs
    local actualCost = cost or 1
    if actualCost < 1 then
        return false
    end

    local actualNow: number = now or os_clock()
    local lastCall = self._lastCall
    
    if actualNow - lastCall >= self._cooldown then
        if peek then return true end
        self._lastCall = actualNow
        return true
    end
    
    return false
end

function Debounce:SetCapacity(delaySeconds: number)
    self._cooldown = delaySeconds
end

function Debounce:ResetState()
    -- Reset to the past to allow immediate execution for the next call
    self._lastCall = -self._cooldown
end

table.freeze(Debounce)

return Debounce