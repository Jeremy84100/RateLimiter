<div align="center">
  <img src="banner.jpg" width="100%" alt="RateLimiter Banner">

  *High-performance, engine-grade security for Roblox backends*

  [![Version](https://img.shields.io/badge/version-4.0.1-blue)](https://github.com/Jeremy84100/RateLimiter)
  [![Platform](https://img.shields.io/badge/Roblox-00A2FF?logo=roblox&logoColor=white)](https://roblox.com)
  [![Luau](https://img.shields.io/badge/Luau-Strict-FF5A0E)](https://luau-lang.org)
  [![Performance](https://img.shields.io/badge/Performance-Zero--Allocation-brightgreen)](https://github.com/Jeremy84100/RateLimiter)
  [![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

  ⭐ If you like this project, star it on GitHub!

  [Overview](#overview) • [Key Features](#key-features) • [Installation](#installation) • [Benchmarks](#-performance-benchmarks) • [FAQ](#faq)

</div>

**RateLimiter V4.0.1** is a strictly-typed, synchronous security framework designed for Roblox environments requiring extreme performance. It replaces traditional $O(n)$ memory-heavy loops with pure mathematical algorithms and a **True $O(1)$ Circular Buffer**, ensuring constant execution time even under massive request volumes. Zero yielding, zero thread exhaustion.

## Key Features

- **Algorithmic Purity:** Choose between Debounce, $O(1)$ RateLimit (Circular Buffer), and Token Bucket algorithms.
- **Composite Limiting:** Chain multiple time-windows simultaneously (e.g., Burst + Sustained limits).
- **RemoteProtector:** A zero-allocation wrapper to instantly secure `RemoteEvent` instances.
- **Escalation Matrix:** Automatically scale punishment durations for persistent attackers.
- **Anti-Deco Persistence:** Seamless MemoryStoreService integration to persist player bans across sessions.
- **Weighted Requests:** Charge different "costs" for different actions sharing the same limit pool.

## Installation

### Manual
1. Clone this repository or download the latest release.
2. Place the contents of the `src` folder into a ModuleScript named `RateLimiter`.
3. Locate `RateLimiter` in `ServerStorage` or `ReplicatedStorage`.

## Quick Start

### 1. Securing Remote Events (RemoteProtector)
The most common use case. Secure server endpoints against spam and brute-force attacks instantly.

```lua
local RateLimiter = require(path.to.RateLimiter)

-- Create a protector: 10 calls/sec sliding window, ban for 60s after 5 violations
local protector = RateLimiter.createProtector(
    function() return RateLimiter.createSlidingWindow(10, 1) end,
    5, 
    {60, 300, 3600}
)

game.ReplicatedStorage.SomeRemote.OnServerEvent:Connect(function(player, ...)
    if not protector:Consume(player) then return end
    
    print(player.Name .. " performed a secured action.")
end)
```

### 2. Burst & Sustained Limits (Composite Mode)
Prevent bots from maintaining a constant maximum request rate over long periods by combining multiple time windows.

```lua
-- Allow 15 fast inputs (Burst) AND max 100 inputs per minute (Sustained)
local limiter = RateLimiter.createComposite({
    RateLimiter.createSlidingWindow(15, 1),
    RateLimiter.createSlidingWindow(100, 60)
})

if limiter:Consume() then
    print("Action allowed under both time windows.")
end
```

### 3. Weighted Requests & Token Bucket
Handle actions that consume varying amounts of backend resources.

```lua
-- Bucket holds 100 max tokens, regenerates 10 tokens per second
local bucket = RateLimiter.createTokenBucket(100, 10)

-- Consume 25 tokens for a heavy request
if bucket:Consume(25) then
    print("Saving...")
end
```

> [!TIP]
> Use `ExecuteWithCost` for actions like spawning complex models, firing projectiles, or generating terrain to accurately represent the server load.

### 4. Player Persistence (Anti-Combat Log/Deco)
Ensure that malicious users cannot reset their cooldowns or punishments by rejoining the server.

```lua
-- Create a global action limiter (automatically handles player logic if wrapped)
local protector = RateLimiter.createProtector(function()
    return RateLimiter.createSlidingWindow(5, 1)
end)

-- Link to MemoryStoreService. Punishments will now persist globally!
protector:EnablePersistence("GlobalAction_X")

-- Use in a remote
game.ReplicatedStorage.Remote.OnServerEvent:Connect(function(player)
    if not protector:Consume(player) then return end
    print("Player successfully requested action.")
end)
```

> [!IMPORTANT]  
> If you need to dynamically update a player's capacity (e.g., they purchased a VIP Gamepass), use `limiter:SetCapacity(newTokens, newRefillRate)`. This updates their limits mathematically without destroying their current state or allocations.

## ⚡ Performance Benchmarks

Tested on a standard Roblox Server instance using the native `StressTest.server.luau` suite.

### Micro-Benchmarks (1,000,000 iterations)
| Algorithm | Throughput | Time (1M calls) | Memory Leak |
| :--- | :--- | :--- | :--- |
| **Debounce** | ~35.8M calls/sec | 0.027s | **0.00 KB** |
| **TokenBucket** | ~28.3M calls/sec | 0.035s | **0.00 KB** |
| **SlidingWindow** | ~16.4M calls/sec | 0.060s | **0.00 KB** |
| **RemoteProtector** | **~10.6M calls/sec** | 0.093s | **0.00 KB** |

### Security Gatekeeper Results
- **Zero-Allocation Validation**: Confirmed 100% memory stability under 100,000 requests.
- **Quantum Hack Protection**: Successfully blocked sub-normal numbers (e.g., `1e-302` cost exploits).
- **NaN / Infinity Injection**: Native comparators successfully neutralized `math.huge` and `0/0` attacks.
- **Atomic Transactions**: Verified perfect state rollback during blocked composite transactions.

> [!TIP]
> Use `--!native` and `--!optimize 2` in your scripts to achieve these aerospace speeds. The architecture is designed to stay in the CPU cache as much as possible by avoiding heap allocations.

## Architecture

Traditional rate limiters on Roblox rely on `table.insert` and `table.remove`, causing memory allocations and garbage collection spikes. **RateLimiter V4** is built differently:

1. **$O(1)$ Complexity:** The `SlidingWindow` mode utilizes a static, pre-allocated Circular Buffer. It advances a head/tail pointer rather than resizing arrays.
2. **Synchronous Execution:** The engine is 100% yield-free. Requests are evaluated instantly. If a limit is breached, the execution is dropped, saving CPU cycles.
3. **Zero-Allocation Hot Paths:** When executing secured functions, no anonymous closures or temporary tables are generated in memory.

## FAQ

**Q: Does this replace Roblox's built-in Rate Limiting?**  
A: No, it complements it. Roblox limits overall network bandwidth; **RateLimiter V4** protects your *logic* and *DataStores* from specialized application-layer spam.

**Q: Is it safe for production?**  
A: Yes. It is used in production environments handling thousands of concurrent players with zero performance impact.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


---
*Built for professional, high-concurrency Roblox experiences.*