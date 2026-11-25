-- Original BananaLite decision logic. No Roblox services or network calls.
local Core = {}

function Core.finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function Core.canAfford(item, balances)
    return type(item) == "table" and type(item.itemType) == "string"
        and type(item.currency) == "string" and Core.finite(item.price)
        and item.price >= 0 and Core.finite(balances[item.currency])
        and balances[item.currency] >= item.price
        and not item.disabled and not item.lockedByForge
end

function Core.nextTier(chain, owned)
    local current = 0
    for i, name in ipairs(chain) do
        if (owned[name] or 0) > 0 then current = i end
    end
    return chain[current + 1]
end

-- One item per decision. A fresh inventory is required for the next decision.
function Core.choosePurchase(owned, catalog, options)
    options = options or {}
    local function candidate(id)
        local item = id and catalog[id]
        if item and Core.canAfford(item, owned) then return item end
    end
    local order = {}
    local function add(id) if id then table.insert(order, id) end end
    if (owned[options.woolType or "wool_white"] or 0) < 32 then add("wool_white") end
    add(Core.nextTier({"leather_chestplate", "iron_chestplate", "diamond_chestplate", "emerald_chestplate"}, owned))
    if not options.hammer then add(Core.nextTier({"wood_sword", "stone_sword", "iron_sword", "diamond_sword", "emerald_sword"}, owned)) end
    add(Core.nextTier({"wood_pickaxe", "stone_pickaxe", "iron_pickaxe", "diamond_pickaxe"}, owned))
    add(Core.nextTier({"wood_axe", "stone_axe", "iron_axe", "diamond_axe"}, owned))
    if (owned.bow or 0) == 0 and (owned.crossbow or 0) == 0 and (owned.tactical_crossbow or 0) == 0 then add("bow") end
    if (owned.bow or 0) + (owned.crossbow or 0) + (owned.tactical_crossbow or 0) > 0 and (owned.arrow or 0) < 24 then add("arrow") end
    if (owned[options.woolType or "wool_white"] or 0) < 64 then add("wool_white") end
    for _, id in ipairs(order) do
        local item = candidate(id)
        if item then return item end
    end
end

function Core.chooseHammer(tiers, meta, crystals)
    if not Core.finite(crystals) or crystals < 0 then return end
    -- Strength first at equal tier; never invent a missing tier or price.
    local best, bestTier
    for _, name in ipairs({"strength", "speed", "shield"}) do
        local tier, entry = tiers[name], meta[name]
        if Core.finite(tier) and tier >= 0 and tier % 1 == 0 and entry and entry.tiers then
            local nextUpgrade = entry.tiers[tier + 1]
            if nextUpgrade and Core.finite(nextUpgrade.price) and nextUpgrade.price >= 0
                and nextUpgrade.price <= crystals and (not bestTier or tier < bestTier) then
                best, bestTier = name, tier
            end
        end
    end
    return best
end

function Core.phrases(text)
    local result = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if #line > 0 and #line <= 180 and #result < 30 then table.insert(result, line) end
    end
    return result
end

-- Ballistic low arc, with no speed or gravity modifications.
function Core.arc(horizontal, height, speed, gravity)
    if not (Core.finite(horizontal) and Core.finite(height) and Core.finite(speed)
        and Core.finite(gravity)) or horizontal <= 0.01 or speed <= 0 or gravity < 0 then return end
    if gravity < 0.001 then
        local distance = math.sqrt(horizontal * horizontal + height * height)
        return math.atan2(height, horizontal), distance / speed
    end
    local v2 = speed * speed
    local d = v2 * v2 - gravity * (gravity * horizontal * horizontal + 2 * height * v2)
    if d < 0 then return end
    local angle = math.atan((v2 - math.sqrt(d)) / (gravity * horizontal))
    return angle, horizontal / (math.cos(angle) * speed)
end

-- Serial transaction gate. A timeout is ambiguous, not permission to buy again.
function Core.gate()
    local gate = {state = "idle", generation = 0, nextAt = 0}
    function gate:begin(now, key, before)
        if self.state ~= "idle" or now < self.nextAt then return end
        self.generation = self.generation + 1
        self.state, self.key, self.before, self.started = "pending", key, before, now
        return self.generation
    end
    function gate:reply(token, ok, now)
        if token ~= self.generation or self.state == "idle" then return end
        if ok == false then
            self.state, self.nextAt = "idle", now + 2
        elseif ok == true then
            self.state = "accepted"
        end
    end
    function gate:observe(now, confirmed)
        if self.state == "idle" then return end
        if confirmed then
            self.state, self.nextAt = "idle", now + 0.4
        elseif now - self.started >= 8 then
            self.state = "uncertain"
        end
    end
    return gate
end

-- No catch-up burst after a pause; disabled jobs do no work.
function Core.scheduler()
    local scheduler = {jobs = {}}
    function scheduler:add(name, interval, callback)
        self.jobs[name] = {interval = interval, callback = callback, nextAt = 0, enabled = false, busy = false}
    end
    function scheduler:step(now, dispatch)
        for _, job in pairs(self.jobs) do
            if job.enabled and not job.busy and now >= job.nextAt then
                job.nextAt, job.busy = now + job.interval, true
                dispatch(job)
            end
        end
    end
    return scheduler
end

return Core
