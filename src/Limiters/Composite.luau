--!strict
--!native
--!optimize 2
--[[
    @title Composite Limiter
    @summary Allows chaining multiple limiters into a single atomic transaction.
]]
local os_clock = os.clock

local Composite = {}
Composite.__index = Composite

export type CompositeInstance = {
    _limiters: {any},
    
    Consume: (self: CompositeInstance, cost: number?, now: number?, peek: boolean?) -> boolean,
    ResetState: (self: CompositeInstance) -> (),
}

function Composite.new(limiters: {any}): CompositeInstance
    local self = setmetatable({} :: any, Composite)
    self._limiters = limiters
    return self
end

function Composite:Consume(cost: number?, now: number?, peek: boolean?): boolean
    local actualCost: number = cost or 1
    
    -- Gatekeeper: early rejection for invalid cost
    if actualCost < 1 then
        return false
    end

    -- Synchronize time once for all children
    local actualNow: number = now or os_clock()
    
    -- Optimized local caching to avoid table lookups
    local limiters = self._limiters 
    
    -- Phase 1: Atomic polling (transaction check)
    -- Optimized generalized iteration by Luau VM
    for _, limiter in limiters do
        if not limiter:Consume(actualCost, actualNow, true) then
            return false
        end
    end
    
    -- Phase 2: Early exit for peek checks
    if peek then 
        return true 
    end
    
    -- Phase 3: Committal consumption (transaction completion)
    -- All limiters passed, now commit changes to state
    for _, limiter in limiters do
        limiter:Consume(actualCost, actualNow, false)
    end
    
    return true
end

function Composite:ResetState()
    local limiters = self._limiters
    for _, limiter in limiters do
        if limiter.ResetState then 
            limiter:ResetState() 
        end
    end
end

-- Freeze class for maximum inline caching and VM performance
table.freeze(Composite)

return Composite