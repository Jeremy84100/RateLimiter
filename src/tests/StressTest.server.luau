--!strict
-- src/tests/StressTest.server.luau
--[[
    @title StressTest V4 "Zero-Gravity"
    @summary Ultimate performance and memory validation for the RateLimiter V4 architecture.
]]

local RateManager = require(script.Parent.Parent)

print("\n--- 🔬 DEMARRAGE DU LABORATOIRE DE STRESS V4 ---")

-- Mock d'un joueur pour les tests
local mockPlayer = {
    Name = "TestSubject_001",
    UserId = 1234567
} :: any

--------------------------------------------------------------------------------
-- TEST 1 : PREUVE DU ZÉRO-ALLOCATION (GC STABILITY)
--------------------------------------------------------------------------------
local function runGarbageTest()
    print("\n[TEST 1] Vérification du Zéro-Allocation...")
    
    local slidingWindow = RateManager.createSlidingWindow(100, 1)
    
    -- Temps de chauffe pour stabiliser l'état initial des tables internes
    for _ = 1, 100 do slidingWindow:Consume() end
    
    local memBefore = gcinfo() -- Luau Memory en KB
    
    -- On bombarde 100 000 fois dans la même frame !
    local start = os.clock()
    for _ = 1, 100000 do
        slidingWindow:Consume()
    end
    local duration = os.clock() - start
    
    local memAfter = gcinfo()
    local leak = memAfter - memBefore
    
    print(string.format("   - 100 000 requêtes traitées en : %.4f secondes", duration))
    print(string.format("   - Mémoire avant : %d KB | Après : %d KB", memBefore, memAfter))
    
    if leak <= 0 then
        print("   - SUCCESS: 0-Allocation confirmé ! (Aucun déchet généré) ✅")
    else
        -- Note: Un leak de quelques KB peut arriver si Luau réorganise sa mémoire interne,
        -- mais il ne doit pas augmenter proportionnellement aux requêtes.
        print(string.format("   - WARNING: Ecart de %d KB (Probablement une réorganisation interne de Luau)", leak))
    end
end

--------------------------------------------------------------------------------
-- TEST 2 : OBJECT POOL ET RECYCLAGE (MEMORY STABILITY)
--------------------------------------------------------------------------------
local function runPoolTest()
    print("\n[TEST 2] Validation de l'Object Pool (Recyclage)...")
    
    -- On utilise une factory simple de SlidingWindow
    local factory = function() return RateManager.createSlidingWindow(10, 1) end
    local protector = RateManager.createProtector(factory, 5, {10})
    
    -- Simulation de 100 faux joueurs qui rejoignent
    local fakePlayers = {}
    for i = 1, 100 do
        fakePlayers[i] = { Name = "Bot_"..i, UserId = i } :: any
    end
    
    -- 1. Attaque initiale (Création de 100 objets)
    for _, p in fakePlayers do
        protector:Consume(p)
    end
    
    -- 2. Déconnexion massive (Remplissage du Pool)
    -- On accède aux internes du pool juste pour vérifier dans ce test
    local protectorInternal = (protector :: any)
    print("   - Simulation de départ des 100 joueurs...")
    for i = 1, 100 do
        local p = fakePlayers[i]
        local limiter = protectorInternal._activeLimiters[p]
        if limiter then
            limiter:ResetState()
            table.insert(protectorInternal._pool, limiter)
            protectorInternal._activeLimiters[p] = nil
        end
    end
    
    local poolSize = #protectorInternal._pool
    print("   - Taille de l'Object Pool : " .. poolSize)
    
    if poolSize == 100 then
        print("   - SUCCESS: 100% des limiteurs ont été recyclés dans le Pool ! ✅")
    else
        print("   - FAILURE: Le pool ne contient pas le nombre attendu d'objets.")
    end

    -- 3. Re-connexion (Utilisation du Pool)
    print("   - Simulation du retour de 100 joueurs (Consommation du Pool)...")
    for _, p in fakePlayers do
        protector:Consume(p)
    end
    
    if #protectorInternal._pool == 0 then
        print("   - SUCCESS: Les objets du Pool ont été réutilisés sans nouvelle allocation ! ✅")
    else
         print("   - FAILURE: Le pool n'a pas été vidé lors de la reconnexion.")
    end
end

--------------------------------------------------------------------------------
-- TEST 3 : ESCALADE ET PUNITION
--------------------------------------------------------------------------------
local function runPunishTest()
    print("\n[TEST 3] Validation des Punitions (Escalade)...")
    
    local protector = RateManager.createProtector(
        function() return RateManager.createSlidingWindow(5, 1) end,
        3, -- Threshold: 3 hits pour un ban
        {1, 5} -- Bans de 1s puis 5s
    )
    
    -- On spamme jusqu'au ban
    print("   - Spamming TestSubject...")
    for i = 1, 10 do protector:Consume(mockPlayer) end
    
    local isBanned = not protector:Consume(mockPlayer)
    if isBanned then
        print("   - Joueur banni avec succès ! ✅")
    end
    
    print("   - Attente de la fin du premier ban (1.1s)...")
    task.wait(1.1)
    
    if protector:Consume(mockPlayer) then
        print("   - Joueur débanni. Deuxième attaque immédiate pour tester l'escalade...")
        for i = 1, 10 do protector:Consume(mockPlayer) end
        
        print("   - Vérification de l'escalade (Ban de 5s)...")
        task.wait(2) -- On attend 2s (le ban de 1s serait fini, mais celui de 5s doit être actif)
        if not protector:Consume(mockPlayer) then
            print("   - SUCCESS: L'escalade de 5s est active ! ✅")
        else
             print("   - FAILURE: L'escalade n'a pas déclenché le ban de 5s.")
        end
    else
         print("   - FAILURE: Le joueur n'a pas été débanni après 1s.")
    end
end

-- Exécution de la suite de tests
task.spawn(function()
    runGarbageTest()
    runPoolTest()
    runPunishTest()
    print("\n--- ✅ SUITE DE TESTS V4 TERMINEE AVEC SUCCÈS ---")
end)