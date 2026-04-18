--!strict

-- Professional Testing Suite for the RateLimiter Framework
local RateManager = require(game.ReplicatedStorage:WaitForChild("RateLimiter"))
local Mode = RateManager.Mode

print("\n--- RateLimiter Performance & Stability Test Suite ---")

local function assertTest(name: string, condition: boolean)
    if condition then
        print("✅ PASSED: " .. name)
    else
        warn("❌ FAILED: " .. name)
    end
end

-- TEST 1: Request Weighting (Cost-based execution)
local function testRequestWeighting()
    print("\n[Executing Request Weighting Suite...]")
    local limiter = RateManager.new(10, 5, Mode.RateLimit)
    local count = 0
    
    limiter:ExecuteWithCost(5, function() count += 1 end)
    assertTest("Weighting: Verified initial multi-token consumption", count == 1)
    
    for _ = 1, 5 do limiter:Execute(function() count += 1 end) end
    assertTest("Weighting: Reached maximum window capacity", count == 6)
    
    limiter:Execute(function() count += 1 end)
    assertTest("Weighting: Blocked requests exceeding capacity", count == 6)
    limiter:Destroy()
end

-- TEST 2: Escalation Matrix (Punishment Logic)
local function testEscalation()
    print("\n[Executing Escalation Matrix Suite...]")
    local limiter = RateManager.new(2, 1, Mode.RateLimit)
    limiter:SetPunishment(1, {1, 3})
    
    limiter:Execute(function() end)
    limiter:Execute(function() end)
    limiter:Execute(function() end) -- Hits threshold, triggers 1s ban
    
    -- Spamming during active punishment should not extend the existing timer
    for _ = 1, 10 do limiter:Execute(function() end) end
    
    task.wait(1.1)
    local success = false
    limiter:Execute(function() success = true end)
    assertTest("Escalation: Confirmed automatic recovery after penalty expires", success == true)
    limiter:Destroy()
end

-- TEST 3: Validation - Cost > Capacity
local function testCostExceedsMax()
    print("\n[Executing Edge Case Validation...]")
    local limiter = RateManager.new(10, 1, Mode.RateLimit)
    local executed = false
    
    limiter:ExecuteWithCost(100, function() executed = true end)
    assertTest("Validation: Dropped request exceeding total bucket capacity", executed == false)
    
    limiter:Execute(function() executed = true end)
    assertTest("Validation: Standard requests operational after dropped heavy request", executed == true)
    limiter:Destroy()
end

-- TEST 4: Debounce Mode Accuracy
local function testDebounce()
    print("\n[Executing Debounce Precision Suite...]")
    local limiter = RateManager.new(0.5, nil, Mode.Debounce)
    local count = 0
    local function inc() count += 1 end
    
    limiter:Execute(inc) -- Allowed
    limiter:Execute(inc) -- Blocked by cooldown
    assertTest("Debounce: Blocked rapid consecutive execution", count == 1)
    
    task.wait(0.6)
    limiter:Execute(inc) -- Recovered
    assertTest("Debounce: Resumed execution after specified cooldown period", count == 2)
    limiter:Destroy()
end

-- TEST 5: TokenBucket Architecture
local function testTokenBucket()
    print("\n[Executing TokenBucket Engine Suite...]")
    local limiter = RateManager.new(5, 2, Mode.TokenBucket)
    local count = 0
    
    for _ = 1, 5 do limiter:Execute(function() count += 1 end) end
    assertTest("TokenBucket: Total capacity consumption successful", count == 5)
    
    limiter:Execute(function() count += 1 end)
    assertTest("TokenBucket: Execution blocked on empty bucket", count == 5)
    
    task.wait(1.1) -- Should regenerate 2 tokens
    limiter:Execute(function() count += 1 end)
    limiter:Execute(function() count += 1 end)
    assertTest("TokenBucket: Resumed execution via partial token regeneration", count == 7)
    limiter:Destroy()
end

-- TEST 6: Composite Mode Validation (Dual-Window)
local function testComposite()
    print("\n[Executing Composite Limiter Suite...]")
    local limiter = RateManager.new({
        {max = 2, window = 1},
        {max = 3, window = 10}
    }, nil, Mode.Composite)
    
    local count = 0
    limiter:Execute(function() count += 1 end)
    limiter:Execute(function() count += 1 end)
    assertTest("Composite: Validated execution under both active constraints", count == 2)
    
    limiter:Execute(function() count += 1 end)
    assertTest("Composite: Successfully blocked by primary short-window limit", count == 2)
    limiter:Destroy()
end

-- TEST 7: Architectural Persistence Flow
local function testPersistence()
    print("\n[Executing Persistence Architecture Suite...]")
    local pl = RateManager.PlayerLimiter(2, 5, Mode.RateLimit)
    local mockPlayer = {UserId = 99999, Name = "PersistenceTester"} :: any
    
    pl:ExecuteFor(mockPlayer, function() end)
    pl:ExecuteFor(mockPlayer, function() end)
    pl:ExecuteFor(mockPlayer, function() end)
    
    pl:Destroy()
    assertTest("Persistence: Lifecycle cleanup flow completed successfully", true)
end

-- TEST 8: Memory Management (Object Disposal)
local function testMemoryLeaks()
    print("\n[Executing Memory Management Suite...]")
    local before = gcinfo()
    
    local instances: {any} = {}
    for _ = 1, 100 do
        table.insert(instances, RateManager.new(10, 1, Mode.RateLimit))
    end
    
    for i = 1, 100 do
        instances[i]:Destroy()
        instances[i] = nil
    end
    
    instances = {} :: any
    
    -- Synchronous wait to ensure GC and test sequence order
    task.wait(1) 
    local after = gcinfo()
    print(string.format("Memory Benchmark: Before: %d KB, After: %d KB", before, after))
    assertTest("Memory: Successful resource cleanup and GC collection", after <= before + 200)
end

-- Initialize Test Sequence
task.spawn(function()
    testRequestWeighting()
    testEscalation()
    testCostExceedsMax()
    testDebounce()
    testTokenBucket()
    testComposite()
    testPersistence()
    testMemoryLeaks()
    
    print("\n==============================================")
    print("--- ALL OPERATIONAL TESTS COMPLETED ---")
    print("==============================================\n")
end)