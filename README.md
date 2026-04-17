<div align="center">
  <img src="https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/shield-check.svg" width="96" alt="RateLimiter logo">

  # RateLimiter
  *High-performance, engine-grade security for Roblox backends*

  [![Version](https://img.shields.io/badge/version-3.2.2-blue?style=flat-square)](https://github.com/Jeremy84100/RateLimiter)
  [![Platform](https://img.shields.io/badge/Roblox-00A2FF?style=flat-square&logo=roblox&logoColor=white)](https://roblox.com)
  [![Luau](https://img.shields.io/badge/Luau-Strict-FF5A0E?style=flat-square)](https://luau-lang.org)
  [![Performance](https://img.shields.io/badge/Performance-Zero--Allocation-brightgreen?style=flat-square)](https://github.com/Jeremy84100/RateLimiter)

  ⭐ If you like this project, star it on GitHub!

  [Key Features](#key-features) • [Installation](#installation) • [Quick Start](#quick-start) • [Architecture](#architecture--performance)

</div>

**RateLimiter** is a strictly-typed, synchronous security framework designed for Roblox environments requiring extreme performance. It replaces traditional $O(n)$ memory-heavy loops with pure mathematical algorithms and a **True $O(1)$ Circular Buffer**, ensuring constant execution time even under massive request volumes. Zero yielding, zero thread exhaustion.

## Key Features

- **Algorithmic Purity:** Choose between Debounce, $O(1)$ RateLimit (Circular Buffer), and Token Bucket algorithms.
- **Composite Limiting:** Chain multiple time-windows simultaneously (e.g., Burst + Sustained limits).
- **RemoteProtector:** A zero-allocation wrapper to instantly secure `RemoteEvent` instances.
- **Escalation Matrix:** Automatically scale punishment durations for persistent attackers.
- **Anti-Deco Persistence:** Seamless MemoryStoreService integration to persist player bans across sessions.
- **Weighted Requests:** Charge different "costs" for different actions sharing the same limit pool.

## Installation

### Wally (Recommended)
Add this to your `wally.toml`:
```toml
[dependencies]
RateLimiter = "jeremy84100/ratelimiter@3.2.2"
```

### Manual
1. Download the latest release from the repository.
2. Place the `RateLimiter` module into `ServerStorage` or `ReplicatedStorage`.

## Quick Start

### 1. Securing Remote Events (RemoteProtector)
The most common use case. Secure server endpoints against spam and brute-force attacks instantly.

```lua
local RateLimiter = require(path.to.RateLimiter)

-- Allow 10 requests per second. Ban for 120s after 3 strikes.
local protector = RateLimiter.RemoteProtector.new(10, 1, 3, 120)

protector:Connect(game.ReplicatedStorage.DataEvent, function(player, actionData)
    -- This code ONLY runs if the player is within their strict limits.
    print(player.Name .. " performed a secured action.")
end)
```

### 2. Burst & Sustained Limits (Composite Mode)
Prevent bots from maintaining a constant maximum request rate over long periods by combining multiple time windows.

```lua
-- Allow 15 fast inputs (Burst) AND max 100 inputs per minute (Sustained)
local limiter = RateLimiter.new({
    {max = 15, window = 1},
    {max = 100, window = 60}
}, nil, RateLimiter.Mode.Composite)

limiter:Execute(function()
    print("Action allowed under both time windows.")
end)
```

### 3. Weighted Requests & Token Bucket
Handle actions that consume varying amounts of backend resources.

```lua
-- Bucket holds 100 max tokens, regenerates 10 tokens per second
local bucket = RateLimiter.new(100, 10, RateLimiter.Mode.TokenBucket)

local function heavyDatabaseSave()
    print("Saving...")
end

-- Consume 25 tokens for a heavy request
bucket:ExecuteWithCost(25, heavyDatabaseSave)
```

> [!TIP]
> Use `ExecuteWithCost` for actions like spawning complex models, firing projectiles, or generating terrain to accurately represent the server load.

### 4. Player Persistence (Anti-Combat Log/Deco)
Ensure that malicious users cannot reset their cooldowns or punishments by rejoining the server.

```lua
local playerLimiter = RateLimiter.PlayerLimiter(5, 1, RateLimiter.Mode.RateLimit)

-- Link to MemoryStoreService. Punishments will now persist globally!
playerLimiter:EnablePersistence("GlobalAction_X")

-- Use ExecuteFor to track requests per player
playerLimiter:ExecuteFor(somePlayer, function()
    print("Player successfully requested action.")
end)
```

> [!IMPORTANT]  
> If you need to dynamically update a player's capacity (e.g., they purchased a VIP Gamepass), use `limiter:SetCapacity(newTokens, newRefillRate)`. This updates their limits mathematically without destroying their current state or allocations.

## Architecture & Performance

Traditional rate limiters on Roblox rely on `table.insert` and `table.remove`, causing memory allocations and garbage collection spikes. If a player spams requests, traditional limits yield (`task.wait`), leading to thread exhaustion and server crashes.

**RateLimiter** is built differently:
1. **$O(1)$ Complexity:** The `RateLimit` mode utilizes a static, pre-allocated Circular Buffer. It advances a head/tail pointer rather than resizing arrays.
2. **Synchronous Execution:** The engine is 100% yield-free. Requests are evaluated instantly. If a limit is breached, the execution is dropped, saving CPU cycles.
3. **Zero-Allocation Hot Paths:** When executing secured functions, no anonymous closures or temporary tables are generated in memory.

---
*Built for professional, high-concurrency Roblox experiences.*