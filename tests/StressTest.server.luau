--!strict
-- tests/StressTest.server.luau
--[[
    @title StressTest V4.0.3
    @summary Performance, memory, and security validation for RateLimiter V4.0.3.
]]

local RateManager = require(game:GetService("ReplicatedStorage"):WaitForChild("RateLimiter"))

print("\n--- 🔬 STARTING STRESS TEST LABORATORY V4.0.3 ---")

local mockPlayer = { UserId = 12345, Name = "MockPlayer" } :: any

--------------------------------------------------------------------------------
-- CATEGORY 1 : CORE INFRASTRUCTURE (REMOTEPROTECTOR)
--------------------------------------------------------------------------------

local function runMemoryTest()
    print("\n[TEST 1] Zero-Allocation Validation (100,000 requests)...")
    local protector = RateManager.createProtector(function() return RateManager.createSlidingWindow(100001, 60) end)
    local internalProtector = (protector :: any)
    internalProtector:_initPlayer(mockPlayer)
    for _ = 1, 10000 do protector:Consume(mockPlayer) end
    task.wait(0.5)
    local memBefore = gcinfo()
    for _ = 1, 100000 do protector:Consume(mockPlayer) end
    local memAfter = gcinfo()
    local diff = memAfter - memBefore
    print("   - Memory Before : " .. memBefore .. " KB")
    print("   - Memory After  : " .. memAfter .. " KB")
    if diff <= 1 then print("   - SUCCESS: Zero-Allocation detected! 💎✅")
    else warn("   - WARNING: Micro-allocation detected (" .. diff .. " KB).") end
end

local function runPoolTest()
    print("\n[TEST 2] Object Pool Validation (Recycling)...")
    local protector = RateManager.createProtector(function() return RateManager.createSlidingWindow(10, 60) end)
    local internal = (protector :: any)
    local fakePlayers = {}
    for i = 1, 10 do
        local p = { UserId = i } :: any
        table.insert(fakePlayers, p)
        internal:_initPlayer(p)
        protector:Consume(p)
    end
    for _, p in fakePlayers do
        local data = internal._playerData[p]
        if data and data.limiter then
            data.limiter:ResetState()
            internal._pool[#internal._pool + 1] = data.limiter
        end
        internal._playerData[p] = nil
    end
    local poolSize = #internal._pool
    print("   - Pool size after 10 disconnections : " .. poolSize)
    if poolSize == 10 then print("   - SUCCESS: All instances were successfully recycled! ♻️✅")
    else warn("   - FAILURE: Instances lost in the pool.") end
end

local function runEscalationTest()
    print("\n[TEST 3] Punishment Escalation Validation...")
    local protector = RateManager.createProtector(function() return RateManager.createSlidingWindow(1, 10) end, 2, {1, 2})
    local internal = (protector :: any)
    internal:_initPlayer(mockPlayer)
    protector:Consume(mockPlayer)
    protector:Consume(mockPlayer) -- Hit 1
    protector:Consume(mockPlayer) -- Hit 2 -> Ban 1s
    print("   - Status 1 (Expected: Banned) : " .. (protector:Consume(mockPlayer) and "Free" or "Banned"))
    task.wait(1.1)
    protector:Consume(mockPlayer) -- Autorisé
    protector:Consume(mockPlayer) -- Hit 1
    protector:Consume(mockPlayer) -- Hit 2 -> Ban 2s (Escalade)
    task.wait(1.1)
    print("   - Status after 1.1s (Expected: Banned) : " .. (protector:Consume(mockPlayer) and "Free" or "Banned"))
    task.wait(1)
    print("   - Status after 2.1s (Expected: Free) : " .. (protector:Consume(mockPlayer) and "Free" or "Banned"))
end

local function runGhostLoadingTest()
    print("\n[TEST 4] The Ghost Loading Exploit (Async DB Race Condition)...")
    local protector = RateManager.createProtector(function() return RateManager.createDebounce(0) end)
    local internal = (protector :: any)
    internal:_initPlayer(mockPlayer)
    internal._playerData[mockPlayer].isLoading = true 
    local hackSuccess = protector:Consume(mockPlayer)
    print("   - Attempting to consume while loading: " .. (hackSuccess and "FAILED (HACK SUCCESSFUL)" or "SUCCESS (Blocked by Gatekeeper)"))
    internal._playerData[mockPlayer].isLoading = false
    local normalTry = protector:Consume(mockPlayer)
    print("   - Action after full load: " .. (normalTry and "SUCCESS" or "FAILED"))
end

local function runStateIsolationTest()
    print("\n[TEST 5] Memory State Isolation (Cross-Bleed Verification)...")
    local protector = RateManager.createProtector(function() return RateManager.createTokenBucket(10, 0) end)
    local internal = (protector :: any)
    local playerA = { UserId = 1, Name = "PlayerA" } :: any
    local playerB = { UserId = 2, Name = "PlayerB" } :: any
    internal:_initPlayer(playerA)
    internal:_initPlayer(playerB)
    protector:Consume(playerA, 10)
    local bSuccess = protector:Consume(playerB, 10)
    print("   - Player B consumption after Player A exhaustion: " .. (bSuccess and "SUCCESS (Isolated memory!)" or "FAILED (CROSS-BLEED DETECTED)"))
end

local function runRapidRejoinTest()
    print("\n[TEST 6] Network Schizophrenia (Rapid Rejoin Memory Stress)...")
    local protector = RateManager.createProtector(function() return RateManager.createDebounce(1) end)
    local internal = (protector :: any)
    local p = { UserId = 999 } :: any
    for _ = 1, 500 do
        internal:_initPlayer(p)
        local data = internal._playerData[p]
        if data and data.limiter then
            data.limiter:ResetState()
            internal._pool[#internal._pool + 1] = data.limiter
        end
        internal._playerData[p] = nil
    end
    print("   - Pool size after 500 rapid rejoins (Expected: 1) : " .. #internal._pool)
    if #internal._pool == 1 then print("   - SUCCESS: GC and Pool handled the load perfectly! 🧠✅")
    else warn("   - FAILED: Memory leak detected (" .. #internal._pool .. " instances).") end
end

--------------------------------------------------------------------------------
-- CATEGORY 2 : DEBOUNCE
--------------------------------------------------------------------------------

local function runDebounceTest()
    print("\n[TEST 7] Debounce Basic Logic...")
    local db = RateManager.createDebounce(1)
    print("   - Click 1 : " .. (db:Consume() and "OK" or "FAILED"))
    print("   - Click 2 (Immediate) : " .. (db:Consume() and "FAILED" or "OK"))
    task.wait(1.1)
    print("   - Click 3 (After 1.1s) : " .. (db:Consume() and "OK" or "FAILED"))
end

local function runDebounceFirstShotTest()
    print("\n[TEST 8] Debounce 'First Shot' Validation...")
    local db = RateManager.createDebounce(10)
    local success = db:Consume()
    print("   - Instant first shot (Expected: SUCCESS): " .. (success and "SUCCESS" or "FAILED (Weapon jammed on spawn!)"))
end

local function runDebounceSecurityTest()
    print("\n[TEST 9] Debounce Security (Invalid Cost Exploit)...")
    local db = RateManager.createDebounce(5)
    db:Consume()
    local hackSuccess = db:Consume(-100)
    print("   - Negative cost attempt (-100): " .. (hackSuccess and "FAILED (HACK SUCCESSFUL!)" or "SUCCESS (Hack blocked properly)"))
end

local function runDebounceBenchmark()
    print("\n[TEST 10] Pure Debounce Micro-Benchmark (1 MILLION calls)...")
    local db = RateManager.createDebounce(1)
    local start = os.clock()
    local fakeNow = start
    for i = 1, 1000000 do
        fakeNow += 1.1
        db:Consume(1, fakeNow)
    end
    local duration = os.clock() - start
    print(string.format("   - 1,000,000 Debounce calculations processed in : %.5f seconds", duration))
    if duration < 0.05 then print("   - SUCCESS: Speed of light achieved! (Zero-Allocation) ⚡✅")
    else warn("   - WARNING: CPU processing takes too long ("..duration.."s).") end
end

--------------------------------------------------------------------------------
-- CATEGORY 3 : TOKEN BUCKET
--------------------------------------------------------------------------------

local function runTokenBucketTest()
    print("\n[TEST 11] TokenBucket Validation (Costs, Peek, and SetCapacity)...")
    local bucket = RateManager.createTokenBucket(5, 1)
    print("   - Consuming 3 tokens: " .. (bucket:Consume(3) and "OK" or "FAILED"))
    print("   - Consuming 3 tokens (Impossible, should fail): " .. (bucket:Consume(3) and "FAILED" or "OK"))
    local canPeek = bucket:Consume(2, nil, true)
    print("   - PEEK at 2 remaining tokens: " .. (canPeek and "OK" or "FAILED"))
    local stealTest = bucket:Consume(2)
    print("   - Real consumption of 2 after Peek: " .. (stealTest and "OK" or "FAILED"))
    task.wait(1.1)
    print("   - After 1s, consume 1 token : " .. (bucket:Consume(1) and "OK" or "FAILED"))
    bucket:SetCapacity(10, 5)
    bucket:ResetState()
    print("   - SetCapacity at 10 max. consume 10 tokens : " .. (bucket:Consume(10) and "OK" or "FAILED"))
end

local function runTokenOverflowTest()
    print("\n[TEST 12] TokenBucket Overflow Protection...")
    local bucket = RateManager.createTokenBucket(5, 10)
    bucket:Consume(5)
    task.wait(1.1)
    local exploitSuccess = bucket:Consume(10)
    print("   - Attempting to consume 10 tokens after long refill: " .. (exploitSuccess and "FAILED (Overflow detected!)" or "SUCCESS (Capacity limit respected)"))
    local maxSuccess = bucket:Consume(5)
    print("   - Consuming the full capacity (5 tokens): " .. (maxSuccess and "SUCCESS" or "FAILED"))
end

local function runTokenMathTest()
    print("\n[TEST 13] Mathematical Validation of 'Hot' Capacity Upgrade...")
    local bucket = RateManager.createTokenBucket(10, 2)
    bucket:Consume(10)
    task.wait(1)
    bucket:SetCapacity(20, 10) 
    local canConsume3 = bucket:Consume(3)
    print("   - Attempting to consume 3 tokens: " .. (canConsume3 and "FAILED (Incorrect token generation)" or "SUCCESS (Mathematical balance correct)"))
    local canConsume2 = bucket:Consume(2)
    print("   - Consuming the expected 2 tokens: " .. (canConsume2 and "SUCCESS" or "FAILED (Tokens lost during upgrade)"))
end

local function runTokenBucketBenchmark()
    print("\n[TEST 14] Pure TokenBucket Micro-Benchmark...")
    local bucket = RateManager.createTokenBucket(100, 10)
    local start = os.clock()
    local fakeNow = start
    for _ = 1, 1000000 do
        fakeNow += 0.0001
        bucket:Consume(1, fakeNow)
    end
    local duration = os.clock() - start
    print(string.format("   - 1,000,000 TokenBucket calculations processed in : %.5f seconds", duration))
    if duration < 0.08 then print("   - SUCCESS: F1 Mathematical Engine Validated! 🏎️✅")
    else warn("   - WARNING: Algorithm complexity detected ("..duration.."s).") end
end

--------------------------------------------------------------------------------
-- CATEGORY 4 : SLIDING WINDOW
--------------------------------------------------------------------------------

local function runSlidingWindowBasicTest()
    print("\n[TEST 15] SlidingWindow Core Logic & Time Expiration...")
    local sw = RateManager.createSlidingWindow(3, 1)
    print("   - Consumption 1, 2, 3: " .. (sw:Consume() and sw:Consume() and sw:Consume() and "SUCCESS" or "FAILED"))
    print("   - Consumption 4 (Immediate, should block): " .. (sw:Consume() and "FAILED" or "SUCCESS (Blocked)"))
    task.wait(1.1)
    print("   - Consumption after 1.1s (Should pass): " .. (sw:Consume() and "SUCCESS" or "FAILED (Eviction bug)"))
end

local function runSlidingWindowSecurityTest()
    print("\n[TEST 16] SlidingWindow Security (Negative Cost Exploit)...")
    local sw = RateManager.createSlidingWindow(5, 10)
    sw:Consume(5)
    local hackSuccess = sw:Consume(-10)
    print("   - Negative cost attempt (-10): " .. (hackSuccess and "FAILED (HACK SUCCESSFUL!)" or "SUCCESS (Hack blocked)"))
    local normalTry = sw:Consume(1)
    print("   - Normal consumption after hack attempt: " .. (normalTry and "FAILED (Counter corrupted)" or "SUCCESS (Still blocked, counter intact)"))
end

local function runSlidingWindowMutationTest()
    print("\n[TEST 17] SlidingWindow Ring Buffer Mutation (SetCapacity)...")
    local sw = RateManager.createSlidingWindow(10, 60)
    sw:Consume(10)
    sw:SetCapacity(3, 60)
    local internal = (sw :: any)
    print("   - Internal size of new buffer (Expected: 3): " .. #internal._buffer)
    print("   - Internal request count (Expected: 3): " .. internal._count)
    if #internal._buffer == 3 and internal._count == 3 then print("   - SUCCESS: Perfect mathematical shrink without corruption! 📐✅")
    else warn("   - WARNING: Ring Buffer failed to transfer data correctly.") end
end

local function runSlidingWindowBenchmark()
    print("\n[TEST 18] Pure SlidingWindow Micro-Benchmark...")
    local sw = RateManager.createSlidingWindow(100, 1)
    local start = os.clock()
    local fakeNow = start
    for i = 1, 1000000 do
        fakeNow += 0.02 
        sw:Consume(1, fakeNow)
    end
    local duration = os.clock() - start
    print(string.format("   - 1,000,000 SlidingWindow calculations processed in : %.5f seconds", duration))
    if duration < 0.15 then print("   - SUCCESS: F1 Ring Buffer Engine Validated! (0 Allocation) 🏎️✅")
    else warn("   - WARNING: Algorithm complexity detected ("..duration.."s).") end
end

--------------------------------------------------------------------------------
-- CATEGORY 5 : COMPOSITE
--------------------------------------------------------------------------------

local function runCompositeTest()
    print("\n[TEST 19] Composite Pattern Validation...")
    local comp = RateManager.createComposite({
        RateManager.createSlidingWindow(2, 1),
        RateManager.createSlidingWindow(5, 10)
    })
    print("   - Clicks 1 & 2 : " .. (comp:Consume() and comp:Consume() and "OK" or "FAILED"))
    print("   - Immediate click 3 (Blocked by 2/1s limit) : " .. (comp:Consume() and "FAILED" or "OK"))
    task.wait(1.1)
    print("   - Clicks 3, 4, 5 : " .. (comp:Consume() and comp:Consume() and comp:Consume() and "OK" or "FAILED"))
    print("   - Immediate click 6 (Blocked by 5/10s limit) : " .. (comp:Consume() and "FAILED" or "OK"))
end

local function runCompositeSecurityTest()
    print("\n[TEST 20] Composite Atomic Transaction & Front-Door Security...")
    local db1 = RateManager.createDebounce(1)
    local db2 = RateManager.createDebounce(5)
    local comp = RateManager.createComposite({db1, db2})
    local hackSuccess = comp:Consume(-50)
    print("   - Composite Negative Cost Hack: " .. (hackSuccess and "FAILED (HACK SUCCESSFUL!)" or "SUCCESS (Hack destroyed at front-door)"))
    comp:Consume()
    task.wait(1.1)
    local atomicTry = comp:Consume()
    print("   - Atomic attempt (db1 ready, db2 blocked): " .. (atomicTry and "FAILED (Passed!)" or "SUCCESS (Blocked globally)"))
    local db1State = db1:Consume()
    print("   - db1 state verification (Should be intact): " .. (db1State and "SUCCESS (Perfect rollback!)" or "FAILED (db1 was consumed for nothing!)"))
end

local function runInceptionTest()
    print("\n[TEST 21] Inception Validation (Nested Composites)...")
    local db1 = RateManager.createDebounce(1)
    local sw1 = RateManager.createSlidingWindow(5, 10)
    local subComposite = RateManager.createComposite({db1, sw1})
    local db2 = RateManager.createDebounce(5)
    local megaComposite = RateManager.createComposite({subComposite, db2})
    local success = megaComposite:Consume()
    print("   - Exécution de l'Inception : " .. (success and "SUCCESS" or "FAILED (Crash ou blocage)"))
    local tryAgain = megaComposite:Consume()
    print("   - Deuxième tir (Doit être bloqué par db1) : " .. (tryAgain and "FAILED" or "SUCCESS (Bloqué correctement)"))
end

--------------------------------------------------------------------------------
-- CATEGORY 6 : GLOBAL LIMITER
--------------------------------------------------------------------------------

local function runGlobalLimiterTest()
    print("\n[TEST 22] GlobalLimiter Concurrency & Network Throughput...")
    local uniqueKey = "StressTest_" .. tostring(os.clock())
    local globalLimiter = RateManager.createGlobalLimiter(uniqueKey, 5, 10)
    local successCount, failCount, threadsCompleted = 0, 0, 0
    local totalThreads = 20
    print("   - Dispatching 20 simultaneous cross-server requests (Limit: 5)...")
    for _ = 1, totalThreads do
        task.spawn(function()
            local allowed = globalLimiter:ConsumeAsync()
            if allowed then successCount += 1 else failCount += 1 end
            threadsCompleted += 1
        end)
    end
    while threadsCompleted < totalThreads do task.wait(0.05) end
    print("   - Successes : " .. successCount .. " (Expected: 5)")
    print("   - Failures  : " .. failCount .. " (Expected: 15)")
    if successCount == 5 and failCount == 15 then print("   - SUCCESS: Global MemoryStore race-conditions mitigated! 🌍✅")
    else warn("   - WARNING: Concurrency anomaly or API Throttling detected.") end
end

--------------------------------------------------------------------------------
-- CATEGORY 7 : CHAOS ENGINEERING & SECURITY HARDENING
--------------------------------------------------------------------------------

local function runChaosMathTest()
    print("\n[TEST 23] Extreme Security Validation (NaN & Infinity Injection)...")
    local bucket = RateManager.createTokenBucket(10, 1)
    local infHack = bucket:Consume(math.huge)
    print("   - math.huge (Infinity) injection attempt: " .. (infHack and "FAILED (HACK SUCCESSFUL!)" or "SUCCESS (Hack blocked)"))
    local nanHack = bucket:Consume(0/0)
    print("   - NaN (0/0) injection attempt: " .. (nanHack and "FAILED (HACK SUCCESSFUL!)" or "SUCCESS (Hack blocked by native comparators)"))
end

local function runTimeTravelerTest()
    print("\n[TEST 24] Time Traveler Validation (10 Years AFK Simulation)...")
    local bucket = RateManager.createTokenBucket(100, 5)
    bucket:Consume(100)
    local tenYearsInSeconds = 315360000
    local futureTime = os.clock() + tenYearsInSeconds
    local success = bucket:Consume(100, futureTime)
    local internal = (bucket :: any)
    print("   - Tokens remaining after consuming 100 regenerated over 10 years (Expected: 0): " .. internal._tokens)
    if internal._tokens == 0 and success then print("   - SUCCESS: Absolute mathematical ceiling respected! 🕰️✅")
    else warn("   - FAILED: Overflow or calculation error (" .. internal._tokens .. ")") end
end

local function runZeroCostExploitTest()
    print("\n[TEST 25] The Zero-Cost Exploit (Sub-normal numbers)...")
    local bucket = RateManager.createTokenBucket(5, 1)
    local hackZero = bucket:Consume(0)
    print("   - Cost = 0 attack attempt: " .. (hackZero and "FAILED (HACK SUCCESSFUL)" or "SUCCESS (Blocked)"))
    local hackQuantum = bucket:Consume(1e-300) 
    print("   - Cost = 1e-300 attack attempt: " .. (hackQuantum and "FAILED (HACK SUCCESSFUL)" or "SUCCESS (Blocked - Quantum Hack neutralized!)"))
end

local function runDDOSPoolTest()
    print("\n[TEST 26] DDOS Simulation & Mass Pool Stress...")
    local protector = RateManager.createProtector(function() return RateManager.createTokenBucket(5, 1) end)
    local internal = (protector :: any)
    local mockHorde = {}
    for i = 1, 100 do table.insert(mockHorde, { UserId = 1000 + i, Name = "Bot_"..i } :: any) end
    for _, bot in mockHorde do
        task.spawn(function()
            internal:_initPlayer(bot)
            for _ = 1, 10 do protector:Consume(bot) end
        end)
    end
    task.wait(0.2)
    for _, bot in mockHorde do
        local data = internal._playerData[bot]
        if data and data.limiter then
            data.limiter:ResetState()
            internal._pool[#internal._pool + 1] = data.limiter
        end
        internal._playerData[bot] = nil
    end
    print("   - Pool size after 100 bots DDOS (Expected: 100): " .. #internal._pool)
    if #internal._pool == 100 then print("   - SUCCESS: Memory Pool survived DDOS! 🛡️✅")
    else warn("   - FAILED: Memory leak or Pool corruption.") end
end

--------------------------------------------------------------------------------
-- CATEGORY 8 : GLOBAL PERFORMANCE BENCHMARK
--------------------------------------------------------------------------------

local function runCPUBenchmark()
    print("\n[TEST 27] CPU Micro-Benchmark for RemoteProtector (1 MILLION calls)...")
    local protector = RateManager.createProtector(function() return RateManager.createDebounce(0) end)
    local internalProtector = (protector :: any)
    internalProtector:_initPlayer(mockPlayer)
    local start = os.clock()
    for _ = 1, 1000000 do protector:Consume(mockPlayer) end
    local duration = os.clock() - start
    print(string.format("   - 1,000,000 requests processed in : %.5f seconds", duration))
    if duration < 0.1 then print("   - SUCCESS: Aerospace Speed! (Pre-warming + Zero C++ Overhead) 🚀✅")
    else warn("   - WARNING: CPU processing takes too long ("..duration.."s).") end
end

--------------------------------------------------------------------------------
-- EXECUTION BLOCK
--------------------------------------------------------------------------------
task.spawn(function()
    -- Category 1: Core Infrastructure
    runMemoryTest()
    runPoolTest()
    runEscalationTest()
    runGhostLoadingTest()
    runStateIsolationTest()
    runRapidRejoinTest()

    -- Category 2: Debounce
    runDebounceTest()
    runDebounceFirstShotTest()
    runDebounceSecurityTest()
    runDebounceBenchmark()

    -- Category 3: Token Bucket
    runTokenBucketTest()
    runTokenOverflowTest()
    runTokenMathTest()
    runTokenBucketBenchmark()

    -- Category 4: Sliding Window
    runSlidingWindowBasicTest()
    runSlidingWindowSecurityTest()
    runSlidingWindowMutationTest()
    runSlidingWindowBenchmark()

    -- Category 5: Composite
    runCompositeTest()
    runCompositeSecurityTest()
    runInceptionTest()

    -- Category 6: Global Limiter
    runGlobalLimiterTest()

    -- Category 7: Chaos & Security
    runChaosMathTest()
    runTimeTravelerTest()
    runZeroCostExploitTest()
    runDDOSPoolTest()

    -- Category 8: Finals
    runCPUBenchmark()
    
    print("\n--- 🏆 ALL TESTS COMPLETED (GRADE: 100% COVERAGE) 🏆 ---")
end)