-- BananaLite 0.1.0 | original source | normal gameplay limits
local Core = (function()
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

end)()
local SelfTest = (function()
return function(Core)
    local passed = 0
    local function test(name, fn)
        assert(fn(), "FAILED: " .. name)
        passed = passed + 1
        print("[BananaLite test] PASS " .. name)
    end
    local item = {itemType = "wool_white", currency = "iron", price = 8, amount = 16}
    test("reject NaN price", function() return not Core.canAfford({itemType="x",currency="iron",price=0/0},{iron=100}) end)
    test("reject infinite balance", function() return not Core.canAfford(item, {iron=math.huge}) end)
    test("reject negative price", function() return not Core.canAfford({itemType="x",currency="iron",price=-1},{iron=100}) end)
    test("exact balance accepted", function() return Core.canAfford(item,{iron=8}) end)
    test("unaffordable purchase skipped", function() return not Core.canAfford(item,{iron=7}) end)
    test("missing pickaxe starts at wood", function() return Core.nextTier({"wood_pickaxe","stone_pickaxe"},{}) == "wood_pickaxe" end)
    test("highest owned tier used", function() return Core.nextTier({"wood","stone","iron"},{wood=1,stone=1}) == "iron" end)
    test("maxed gear stops buying", function() return Core.nextTier({"wood","stone"},{stone=1}) == nil end)
    test("wool floor takes priority", function() return Core.choosePurchase({iron=100},{wool_white=item}) == item end)
    test("stock target stops wool", function() return Core.choosePurchase({iron=100,wool_white=64},{wool_white=item}) == nil end)
    test("no affordable items is idle", function() return Core.choosePurchase({iron=0},{wool_white=item}) == nil end)
    local meta = {strength={tiers={{price=3}}},speed={tiers={{price=3}}},shield={tiers={{price=3}}}}
    test("hammer chooses strength on tie", function() return Core.chooseHammer({strength=0,speed=0,shield=0},meta,3) == "strength" end)
    test("hammer no overspending", function() return Core.chooseHammer({strength=0},meta,2) == nil end)
    test("hammer unknown state is idle", function() return Core.chooseHammer({},meta,100) == nil end)
    test("hammer maxed tier skipped", function() return Core.chooseHammer({strength=1,speed=0},meta,3) == "speed" end)
    test("phrases trim and ignore blank lines", function() local p=Core.phrases("  hello  \n\nworld"); return #p==2 and p[1]=="hello" end)
    test("phrases size bounded", function() return #Core.phrases(string.rep("a",181))==0 end)
    test("unreachable ballistic arc rejected", function() return Core.arc(10000,0,100,196.2)==nil end)
    test("ballistic result reaches target", function()
        local angle,t=Core.arc(30,5,100,196.2)
        return angle and math.abs(math.cos(angle)*100*t-30)<0.001 and math.abs(math.sin(angle)*100*t-98.1*t*t-5)<0.001
    end)
    test("zero-gravity trajectory", function() local a,t=Core.arc(3,4,5,0); return math.abs(t-1)<0.0001 and a>0 end)
    test("nonfinite arc rejected", function() return Core.arc(10,0,math.huge,196.2)==nil end)
    local gate = Core.gate()
    local token = gate:begin(0,"wool",0)
    test("purchase serialized", function() return gate:begin(1,"armor",0)==nil end)
    gate:observe(9,false)
    test("timeout blocks duplicate purchase", function() return gate.state=="uncertain" and gate:begin(10,"wool",0)==nil end)
    gate:reply(token,true,10)
    test("acceptance waits for inventory", function() return gate.state=="accepted" and gate:begin(10,"wool",0)==nil end)
    gate:observe(11,true)
    test("observed purchase unlocks with cooldown", function() return gate:begin(11,"wool",16)==nil and gate:begin(12,"wool",16)~=nil end)
    gate:reply(token,false,13)
    test("stale reply cannot unlock newer purchase", function() return gate.state=="pending" end)
    gate:reply(gate.generation,false,13)
    test("rejection backs off", function() return gate:begin(14,"wool",16)==nil and gate:begin(15,"wool",16)~=nil end)
    local s, runs = Core.scheduler(), 0
    s:add("test",1,function() end)
    local function dispatch(j) runs=runs+1; j.busy=false end
    s:step(0,dispatch)
    test("disabled scheduler is idle", function() return runs==0 end)
    s.jobs.test.enabled=true
    s:step(0,dispatch); s:step(0.5,dispatch); s:step(100,dispatch)
    test("scheduler never catches up in a burst", function() return runs==2 end)
    s.jobs.test.busy=true; s:step(200,dispatch)
    test("scheduler prevents overlapping jobs", function() return runs==2 end)
    print("[BananaLite] SELFTEST "..passed.."/"..passed.." PASSED")
    return passed
end

end)()

if shared.BananaLiteSelfTest then
    shared.BananaLiteSelfTest = nil
    SelfTest(Core)
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Tags = game:GetService("CollectionService")
local Chat = game:GetService("TextChatService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer

if shared.BananaLite then shared.BananaLite:Destroy() end
local app = {alive=true, connections={}, modules={}, dependencies={}, version="0.1.0"}
shared.BananaLite = app
local scheduler, purchaseGate, kitGate = Core.scheduler(), Core.gate(), Core.gate()
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(app.connections,c)
    return c
end
local function make(class, props, parent)
    local object = Instance.new(class)
    for k,v in pairs(props) do object[k]=v end
    object.Parent=parent
    return object
end
local gui = make("ScreenGui",{Name="BananaLite",ResetOnSpawn=false,DisplayOrder=10},player:WaitForChild("PlayerGui",10))
local panel = make("Frame",{Size=UDim2.fromOffset(326,498),Position=UDim2.fromOffset(16,90),BackgroundColor3=Color3.fromRGB(25,27,30),BorderSizePixel=0},gui)
make("TextLabel",{Size=UDim2.new(1,-70,0,28),Position=UDim2.fromOffset(10,4),BackgroundTransparency=1,Text="BananaLite · 16v16",TextColor3=Color3.fromRGB(255,218,90),TextSize=17,Font=Enum.Font.SourceSansBold,TextXAlignment=Enum.TextXAlignment.Left},panel)
local close = make("TextButton",{Size=UDim2.fromOffset(40,24),Position=UDim2.new(1,-45,0,6),Text="Unload",TextSize=12,BackgroundColor3=Color3.fromRGB(55,55,60),TextColor3=Color3.new(1,1,1),BorderSizePixel=0},panel)
local status = make("TextLabel",{Position=UDim2.fromOffset(10,34),Size=UDim2.new(1,-20,0,40),Text="Checking compatibility…",TextWrapped=true,TextSize=13,Font=Enum.Font.SourceSans,TextColor3=Color3.fromRGB(205,210,218),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left},panel)
local function report(message)
    if not app.alive then return end
    status.Text=message
    print("[BananaLite] "..message)
end
local rows=make("Frame",{Position=UDim2.fromOffset(10,80),Size=UDim2.new(1,-20,0,308),BackgroundTransparency=1},panel)
make("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},rows)
local phraseBox=make("TextBox",{Position=UDim2.fromOffset(10,397),Size=UDim2.new(1,-20,0,48),Text="",PlaceholderText="Chat phrases, one per line (15s interval)",MultiLine=true,ClearTextOnFocus=false,TextSize=12,TextWrapped=true,TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(40,42,47),BorderSizePixel=0},panel)
local testButton=make("TextButton",{Position=UDim2.fromOffset(10,453),Size=UDim2.fromOffset(118,25),Text="Run logic tests",TextSize=13,TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(50,53,59),BorderSizePixel=0},panel)
make("TextLabel",{Position=UDim2.fromOffset(135,453),Size=UDim2.fromOffset(180,25),Text="RightShift: show / hide",TextSize=12,TextColor3=Color3.fromRGB(180,185,190),BackgroundTransparency=1},panel)

local function setEnabled(id, value)
    local m = app.modules[id]
    if not m then return end
    if value and not app.ready then report("Still checking dependencies. Try again shortly."); return end
    if value and m.requires then
        for _, name in ipairs(m.requires) do
            if not app.dependencies[name] then report(id..": unavailable — "..name.." failed to load"); return end
        end
    end
    m.enabled=value
    m.errors=0
    scheduler.jobs[id].enabled=value
    m.button.Text=(value and "ON   " or "OFF  ")..m.label
    m.button.TextColor3=value and Color3.fromRGB(255,218,90) or Color3.fromRGB(205,210,218)
    if m.change then
        local ok,err=pcall(m.change,value)
        if not ok then report(id..": "..tostring(err)) end
    end
end
function app:SetEnabled(id, value) setEnabled(id,value==true) end
function app:Diagnostics()
    local out={version=self.version,ready=self.ready,alive=self.alive,connections=#self.connections,features={},dependencies={}}
    for id,m in pairs(self.modules) do out.features[id]={enabled=m.enabled,errors=m.errors} end
    for name in pairs(self.dependencies) do out.dependencies[name]=true end
    return out
end
local function module(id,label,interval,requirements,run,change)
    local b=make("TextButton",{Size=UDim2.new(1,0,0,25),LayoutOrder=#rows:GetChildren(),Text="OFF  "..label,TextSize=14,Font=Enum.Font.SourceSans,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(205,210,218),BackgroundColor3=Color3.fromRGB(37,40,45),BorderSizePixel=0},rows)
    local m={enabled=false,label=label,button=b,requires=requirements,errors=0,change=change}
    app.modules[id]=m
    scheduler:add(id,interval,function() if app.alive and m.enabled then run() end end)
    connect(b.Activated,function() setEnabled(id,not m.enabled) end)
end
local function state()
    local store=app.dependencies.Store
    return store and store:getState() or {}
end
local function inventory()
    local s=state()
    local observed=s.Inventory and s.Inventory.observedInventory
    return observed and observed.inventory or {items={},armor={}}
end
local function counts()
    local inv,out=inventory(),{}
    for _,item in pairs(inv.items or {}) do
        if type(item) == "table" and type(item.itemType)=="string" then out[item.itemType]=(out[item.itemType] or 0)+(tonumber(item.amount) or 1) end
    end
    for _,item in pairs(inv.armor or {}) do
        if type(item)=="table" and item.itemType then out[item.itemType]=math.max(out[item.itemType] or 0,1) end
    end
    return out
end
local function character()
    local c=player.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if h and h.Health>0 and root and not player:GetAttribute("Spectator") then return c,h,root end
end
local function playable()
    local s=state()
    return s.Game and s.Game.matchState==1 and character()~=nil and not Input:GetFocusedTextBox() and not GuiService.MenuIsOpen
end
local function controller(name) return app.dependencies.Knit.Controllers[name] end
local function held() return inventory().hand end
local function itemMeta(item)
    return item and app.dependencies.ItemMeta.getItemMeta(item.itemType) or nil
end
local function opponent(p)
    if p==player then return false end
    local mine,theirs=player:GetAttribute("Team"),p:GetAttribute("Team")
    if mine~=nil and theirs~=nil then return mine~=theirs end
    return player.Team~=nil and p.Team~=nil and player.Team~=p.Team
end
local function cast(origin,direction)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={player.Character,workspace.CurrentCamera}
    return workspace:Raycast(origin,direction,params)
end
local function visible(origin,target)
    local c=target.Parent
    local hit=cast(origin,target.Position-origin)
    return not hit or hit.Instance:IsDescendantOf(c)
end
local function nearest(range)
    local c,h,root=character()
    if not c then return end
    local head=c:FindFirstChild("Head") or root
    local best,distance
    for _,p in ipairs(Players:GetPlayers()) do
        local char=p.Character
        local target=char and char:FindFirstChild("HumanoidRootPart")
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if opponent(p) and target and hum and hum.Health>0 and not char:FindFirstChildOfClass("ForceField") then
            local d=(target.Position-root.Position).Magnitude
            if d<=range and (not distance or d<distance) and visible(head.Position,target) then best,distance=target,d end
        end
    end
    return best
end
local sprintOwned=false
module("keepsprint","KeepSprint · normal speed",0.2,{"Knit","Store"},function()
    local c,h=character()
    local sprint=controller("SprintController")
    if playable() and h.MoveDirection.Magnitude>0 and not sprint:isSprinting() then
        sprint:startSprinting()
        sprintOwned=true
    end
end,function(on)
    if not on and sprintOwned and app.dependencies.Knit then controller("SprintController"):stopSprinting(); sprintOwned=false end
end)

local meleeBox=make("SelectionBox",{Name="BananaTarget",LineThickness=0.035,SurfaceTransparency=1,Color3=Color3.fromRGB(255,220,80)},gui)
local nextMelee=0
module("killaura","Melee assist · normal reach",0.1,{"Knit","Store","ItemMeta","Combat"},function()
    meleeBox.Adornee=nil
    if not playable() then return end
    local item=held()
    local meta=itemMeta(item)
    local sword=meta and meta.sword
    local sc=controller("SwordController")
    if not sword or sword.chargedAttack or sc:getSwordSwingDisabled() or sc:getRemainingSwingCooldown()>0 or os.clock()<nextMelee then return end
    local range=sword.attackRange or app.dependencies.Combat.RAYCAST_SWORD_CHARACTER_DISTANCE
    if not Core.finite(range) or range<=0 then error("Unknown native weapon range") end
    local target=nearest(range)
    if not target then return end
    local point,onScreen=workspace.CurrentCamera:WorldToViewportPoint(target.Position)
    if not onScreen then return end
    meleeBox.Adornee=target.Parent
    nextMelee=os.clock()+math.max(sword.attackSpeed or 0.3,0.1)
    -- Invoke the ordinary swing selection. Never submit a fabricated hit.
    sc:swingSwordAtViewportPoint(Vector2.new(point.X,point.Y))
end,function(on) if not on then meleeBox.Adornee=nil end end)

local projectileCharge,nextProjectile=nil,0
module("projectileaura","Bow assist · clear trajectories",0.1,{"Knit","Store","ItemMeta","ProjectileMeta"},function()
    if not playable() then projectileCharge=nil; return end
    local item=held()
    local meta=itemMeta(item)
    local source=meta and meta.projectileSource
    if not item or not item.itemType:find("bow") or not source or os.clock()<nextProjectile then projectileCharge=nil; return end
    local ammo
    local owned=counts()
    for _,name in ipairs(source.ammoItemTypes or {}) do if (owned[name] or 0)>0 then ammo=name; break end end
    if not ammo then projectileCharge=nil; return end
    local projectile=source.projectileType(ammo)
    local pm=app.dependencies.ProjectileMeta[projectile]
    if not pm or not Core.finite(pm.launchVelocity) then error("Unknown projectile speed") end
    local pc=controller("ProjectileController")
    local handlerController=controller("DefaultProjectileSourceController")
    local handler=handlerController and handlerController.projectileHandler
    local handlerItem=handler and handler.projectileSourceController and handler.projectileSourceController:getHandItem()
    if not handlerItem or handlerItem.tool~=item.tool then projectileCharge=nil; return end
    local origin=pc:getLaunchPosition(item.tool)
    if not origin then projectileCharge=nil; return end
    origin=origin+(handler.fromPositionOffset or Vector3.new(0,2,0))
    local target=nearest(200)
    if not target then projectileCharge=nil; return end
    if not projectileCharge or projectileCharge.tool~=item.tool or projectileCharge.target~=target then
        projectileCharge={tool=item.tool,target=target,started=os.clock()}
        return
    end
    local duration=os.clock()-projectileCharge.started
    local charge=source.maxStrengthChargeSec
    if not Core.finite(charge) or charge<0 then error("Unknown bow charge duration") end
    if duration<charge then return end
    local gravity=pm.gravitationalAcceleration or workspace.Gravity
    local predicted,velocity,flight=target.Position,nil,nil
    for _=1,3 do
        local delta=predicted-origin
        local flat=Vector3.new(delta.X,0,delta.Z)
        local angle,t=Core.arc(flat.Magnitude,delta.Y,pm.launchVelocity,gravity)
        if not angle then projectileCharge=nil; return end
        velocity=flat.Unit*(math.cos(angle)*pm.launchVelocity)+Vector3.new(0,math.sin(angle)*pm.launchVelocity,0)
        flight=t
        predicted=target.Position+target.AssemblyLinearVelocity*t
    end
    local previous=origin
    for i=1,16 do
        local t=flight*i/16
        local point=origin+velocity*t-Vector3.new(0,gravity*t*t/2,0)
        local obstruction=cast(previous,point-previous)
        if obstruction then
            if not obstruction.Instance:IsDescendantOf(target.Parent) then projectileCharge=nil; return end
            break
        end
        previous=point
    end
    local ac=controller("AbilityController")
    local cooldownId=source.cooldownId or (item.itemType.."-proj-source")
    if ac and ac.cooldownController:isOnCooldown(cooldownId) then return end
    nextProjectile=os.clock()+math.max(source.fireDelaySec or 1,0.2)
    projectileCharge=nil
    pc:launchProjectileWithValues({initialVelocity=velocity,positionFrom=origin,drawDurationSeconds=duration},item.tool,source,ammo,nil,projectile)
end,function() projectileCharge=nil end)

local bedLabels,nameLabels={},{}
local function clearLabels(labels)
    for key,label in pairs(labels) do label:Destroy(); labels[key]=nil end
end
local function billboard(part,text,color)
    local b=make("BillboardGui",{Size=UDim2.fromOffset(170,25),StudsOffset=Vector3.new(0,3,0),Adornee=part,AlwaysOnTop=true,MaxDistance=1200},gui)
    make("TextLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=0.35,BackgroundColor3=Color3.new(0,0,0),Text=text,TextSize=14,TextColor3=color,Font=Enum.Font.SourceSansBold,BorderSizePixel=0},b)
    return b
end
module("bedesp","BedESP",0.5,{},function()
    local current={}
    for _,bed in ipairs(Tags:GetTagged("bed")) do
        if bed:IsA("BasePart") then
            current[bed]=true
            if not bedLabels[bed] then bedLabels[bed]=billboard(bed,"BED",Color3.fromRGB(255,215,80)) end
        end
    end
    for bed,label in pairs(bedLabels) do if not current[bed] or not bed.Parent then label:Destroy(); bedLabels[bed]=nil end end
end,function(on) if not on then clearLabels(bedLabels) end end)
module("nametags","Nametags · opponents only",0.5,{},function()
    local current={}
    for _,p in ipairs(Players:GetPlayers()) do
        local char=p.Character
        local root=char and char:FindFirstChild("Head")
        local h=char and char:FindFirstChildOfClass("Humanoid")
        if opponent(p) and root and h and h.Health>0 then
            current[root]=true
            if not nameLabels[root] then nameLabels[root]=billboard(root,p.DisplayName.." (@"..p.Name..")",Color3.fromRGB(255,150,150)) end
        end
    end
    for root,label in pairs(nameLabels) do if not current[root] then label:Destroy(); nameLabels[root]=nil end end
end,function(on) if not on then clearLabels(nameLabels) end end)

local nextQueue=0
module("autoqueue","AutoQueue · current mode",1,{"Knit","Store"},function()
    local s=state()
    if not s.Game or s.Game.matchState~=2 or s.Game.customMatch then return end
    local party=s.Party
    if not party or not party.leader or party.leader.userId~=player.UserId or party.queueState~=0 then return end
    if os.clock()<nextQueue or type(s.Game.queueType)~="string" or s.Game.queueType=="bedwars_test" then return end
    nextQueue=os.clock()+10
    controller("QueueController"):joinQueue(s.Game.queueType)
    report("Requested the same queue: "..s.Game.queueType)
end)
local teleportQueued=false
connect(player.OnTeleport,function(teleportState)
    if teleportState==Enum.TeleportState.Failed then teleportQueued=false; return end
    if teleportState~=Enum.TeleportState.Started or teleportQueued or not app.modules.autoqueue.enabled then return end
    local queueFunction=queue_on_teleport or queueonteleport
    if type(queueFunction)~="function" then report("AutoQueue reload is unavailable in this executor."); return end
    local enabled={}
    for id,m in pairs(app.modules) do if m.enabled then enabled[id]=true end end
    local payload=game:GetService("HttpService"):JSONEncode({enabled=enabled,phrases=phraseBox.Text})
    local resumeCode=string.format("shared.BananaLiteResume=game:GetService('HttpService'):JSONDecode(%q); loadstring(game:HttpGet('https://raw.githubusercontent.com/BananaMan2006/banana-lite-bedwars/main/banana-lite.lua'))()",payload)
    queueFunction(resumeCode)
    teleportQueued=true
end)
local nextChat,lastPhrase=0,nil
module("chatspammer","Chat phrases · every 15 seconds",1,{},function()
    if os.clock()<nextChat then return end
    local choices=Core.phrases(phraseBox.Text)
    if #choices==0 then return end
    local channels=Chat:FindFirstChild("TextChannels")
    local general=channels and channels:FindFirstChild("RBXGeneral")
    if not general then error("Default chat channel is unavailable") end
    local index=math.random(1,#choices)
    if #choices>1 and index==lastPhrase then index=index%#choices+1 end
    nextChat,lastPhrase=os.clock()+15,index
    general:SendAsync(choices[index])
end,function(on) if on then nextChat=os.clock()+15 end end)

local placer,lastCell,lastPlace=nil,nil,0
module("scaffold","Scaffold · wool first",0.15,{"Knit","Store","ItemMeta","BlockEngine","BlockController","BlockPlacer"},function()
    if not playable() or player:GetAttribute("DenyBlockPlace") then return end
    local bc=controller("BlockPlacementController")
    if not bc or bc.disabled then return end
    local char,h,root=character()
    if h.MoveDirection.Magnitude<0.1 then return end
    local block
    for _,item in pairs(inventory().items or {}) do
        local meta=itemMeta(item)
        if (item.amount or 0)>0 and meta and meta.block then
            if not block or item.itemType:find("wool") then block=item end
            if item.itemType:find("wool") then break end
        end
    end
    if not block then return end
    local position=root.Position-Vector3.new(0,h.HipHeight+root.Size.Y/2+1.5,0)+h.MoveDirection*3
    local cell=app.dependencies.BlockController:getBlockPosition(position)
    if cell==lastCell and os.clock()-lastPlace<0.7 then return end
    if app.dependencies.BlockController:getStore():getBlockAt(cell) then return end
    if not placer then placer=app.dependencies.BlockPlacer.new(app.dependencies.BlockEngine,block.itemType) end
    placer.blockType=block.itemType
    lastCell,lastPlace=cell,os.clock()
    -- The unmodified game's placer performs adjacency/range/cooldown checks.
    placer:placeBlock(cell)
end)

local breakMaid
module("nuker","Bed breaker · normal mining",0.15,{"Knit","Store","ItemMeta","BlockController"},function()
    if not playable() or player:GetAttribute("DenyBlockBreak") then return end
    local bc=controller("BlockBreakController")
    if not bc:isBlockBreakEnabled() then return end
    local breaker=bc:getBlockBreaker()
    if not breaker or tick()-(breaker.lastHitTime or 0)<breaker:getCooldown() then return end
    local item=held()
    local meta=itemMeta(item)
    if not meta or not meta.breakBlock then return end
    local char,h,root=character()
    local head=char:FindFirstChild("Head") or root
    local range=breaker:getRange()
    local best,dist
    for _,bed in ipairs(Tags:GetTagged("bed")) do
        if bed:IsA("BasePart") and not bed:GetAttribute("Team"..tostring(player:GetAttribute("Team")).."NoBreak")
            and (bed:GetAttribute("BedShieldEndTime") or 0)<=workspace:GetServerTimeNow() then
            local d=(bed.Position-root.Position).Magnitude
            if d<=range and (not dist or d<dist) then best,dist=bed,d end
        end
    end
    if not best then return end
    local ray=Ray.new(head.Position,(best.Position-head.Position).Unit)
    local info=breaker.clientManager:getBlockSelector():getMouseInfo(1,{ray=ray,range=range})
    if not info or not info.target then return end
    local target=info.target.blockInstance
    if not target or not target:IsA("BasePart") or (target.Position-best.Position).Magnitude>9 then return end
    local ref={blockPosition=app.dependencies.BlockController:getBlockPosition(target.Position)}
    if not app.dependencies.BlockController:isBlockBreakable(ref,player) then return end
    if not breakMaid then breakMaid=rawget(getmetatable(breaker.maid),"new")() end
    breakMaid:DoCleaning()
    breaker:hitBlock(breakMaid,ray)
end,function(on) if not on and breakMaid then breakMaid:DoCleaning() end end)

local function remoteRequest(name,payload,gate,token)
    local remote=app.dependencies.Remotes.Client:Get(name)
    local result=remote:CallServerAsync(payload)
    if type(result)=="table" and type(result.andThen)=="function" then
        result:andThen(function(ok)
            local success
            if ok==true then success=true elseif ok==false then success=false end
            gate:reply(token,success,os.clock())
        end,
            function(err) report(name..": response failed; awaiting inventory confirmation — "..tostring(err)) end)
    elseif type(result)=="boolean" then gate:reply(token,result,os.clock()) end
end
local function currentKit()
    local b=state().Bedwars
    local value=b and b.kit
    if type(value)=="string" then return value=="frost_hammer_kit" end
    if type(value)=="table" then for _,v in pairs(value) do if v=="frost_hammer_kit" then return true end end end
    return false
end
local catalogIds={"wool_white","leather_chestplate","iron_chestplate","diamond_chestplate","emerald_chestplate","wood_sword","stone_sword","iron_sword","diamond_sword","emerald_sword","wood_pickaxe","stone_pickaxe","iron_pickaxe","diamond_pickaxe","wood_axe","stone_axe","iron_axe","diamond_axe","bow","arrow"}
local function eligible(item)
    if not item or item.disabled or item.lockedByForge then return false end
    if item.requiresKit and #item.requiresKit>0 then return false end
    if item.ignoredByKit and #item.ignoredByKit>0 then return false end
    if item.ignoreAttribute and item.ignoreAttribute~="" and player:GetAttribute(item.ignoreAttribute) then return false end
    if item.requireAttribute and item.requireAttribute~="" and not player:GetAttribute(item.requireAttribute) then return false end
    if item.require and item.require.teamUpgrade then
        local required=item.require.teamUpgrade
        local b=state().Bedwars
        local team=b and b.teamUpgrades and b.teamUpgrades[player:GetAttribute("Team")]
        if not team or (team[required.upgradeId] or -1)<required.lowestTierIndex then return false end
    end
    return true
end
module("autobuy","AutoBuy · gear and supplies",0.6,{"Knit","Store","Shop","Remotes"},function()
    local owned=counts()
    if purchaseGate.state~="idle" then
        purchaseGate:observe(os.clock(),(owned[purchaseGate.key] or 0)>purchaseGate.before)
        if purchaseGate.state=="uncertain" then
            report("AutoBuy paused: purchase outcome unknown. Check inventory; no duplicate request sent.")
            setEnabled("autobuy",false)
        end
        return
    end
    if not playable() then return end
    local _,_,root=character()
    local shop,dist
    for _,npc in ipairs(Tags:GetTagged("BedwarsItemShop")) do
        if npc:IsA("BasePart") then
            local d=(npc.Position-root.Position).Magnitude
            if d<=16 and (not dist or d<dist) then shop,dist=npc,d end
        end
    end
    if not shop then return end
    local catalog={}
    for _,id in ipairs(catalogIds) do
        local entry=app.dependencies.Shop.getShopItem(id,player)
        if eligible(entry) then catalog[id]=entry end
    end
    local woolType=app.dependencies.Shop.getTeamWoolById(player:GetAttribute("Team"))
    local item=Core.choosePurchase(owned,catalog,{woolType=woolType,hammer=currentKit()})
    if not item then return end
    local observedId=item.itemType=="wool_white" and woolType or item.itemType
    local token=purchaseGate:begin(os.clock(),observedId,owned[observedId] or 0)
    if token then remoteRequest("BedwarsPurchaseItem",{shopItem=item,shopId=shop.Name},purchaseGate,token) end
end)
module("autokit","AutoKit · Adetunde hammer",0.6,{"Knit","Store","HammerUtil","HammerMeta","Remotes"},function()
    local tiers=app.dependencies.HammerUtil.getUpgradesFromHammer(player) or {}
    if kitGate.state~="idle" then
        kitGate:observe(os.clock(),(tiers[kitGate.key] or 0)>kitGate.before)
        if kitGate.state=="uncertain" then report("AutoKit paused: upgrade outcome unknown."); setEnabled("autokit",false) end
        return
    end
    if not playable() or not currentKit() then return end
    local choice=Core.chooseHammer(tiers,app.dependencies.HammerMeta,counts().frost_crystal or 0)
    if choice then
        local token=kitGate:begin(os.clock(),choice,tiers[choice])
        if token then remoteRequest("UpgradeFrostyHammer",choice,kitGate,token) end
    end
end)

function app:Destroy()
    if not self.alive then return end
    for id in pairs(self.modules) do setEnabled(id,false) end
    self.alive=false
    for _,c in ipairs(self.connections) do c:Disconnect() end
    if breakMaid then breakMaid:DoCleaning() end
    clearLabels(bedLabels); clearLabels(nameLabels)
    if placer and type(placer.destroy)=="function" then pcall(placer.destroy,placer) end
    gui:Destroy()
    if shared.BananaLite==self then shared.BananaLite=nil end
    print("[BananaLite] Unloaded; all jobs and UI disconnected")
end
connect(close.Activated,function() app:Destroy() end)
connect(testButton.Activated,function()
    local ok,result=pcall(SelfTest,Core)
    report(ok and (tostring(result).." logic tests passed; gameplay tests are separate") or tostring(result))
end)
connect(Input.InputBegan,function(key,processed)
    if not processed and key.KeyCode==Enum.KeyCode.RightShift then panel.Visible=not panel.Visible end
end)
connect(RunService.Heartbeat,function()
    if not app.alive or not app.ready then return end
    scheduler:step(os.clock(),function(job)
        task.spawn(function()
            local ok,err=pcall(job.callback)
            job.busy=false
            if not ok and app.alive then
                for id,m in pairs(app.modules) do
                    if scheduler.jobs[id]==job then
                        m.errors=m.errors+1
                        job.nextAt=os.clock()+2
                        report(id..": "..tostring(err))
                        if m.errors>=3 then setEnabled(id,false); report(id.." disabled after repeated errors") end
                        break
                    end
                end
            end
        end)
    end)
end)

task.spawn(function()
    if shared.vape then report("Unload CatVape and rejoin first; its active hooks would invalidate tests."); return end
    local definitions={
        Knit=function() return require(RS.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient end,
        Store=function() return require(player.PlayerScripts.TS.ui.store).ClientStore end,
        ItemMeta=function() return require(RS.TS.item["item-meta"]) end,
        Combat=function() return require(RS.TS.combat["combat-constant"]).CombatConstant end,
        ProjectileMeta=function() return require(RS.TS.projectile["projectile-meta"]).ProjectileMeta end,
        Shop=function() return require(RS.TS.games.bedwars.shop["bedwars-shop"]).BedwarsShop end,
        Remotes=function() return require(RS.TS.remotes).default end,
        HammerUtil=function() return require(RS.TS.games.bedwars.items["frosty-hammer"]["frosty-hammer-util"]).FrostyHammerUtil end,
        HammerMeta=function() return require(RS.TS.games.bedwars.items["frosty-hammer"]["frosty-hammer-upgrades"]).FrostyHammerUpgradeMeta end,
        BlockController=function() return require(RS.rbxts_include.node_modules["@easy-games"]["block-engine"].out).BlockEngine end,
        BlockEngine=function() return require(player.PlayerScripts.TS.lib["block-engine"]["client-block-engine"]).ClientBlockEngine end,
        BlockPlacer=function() return require(RS.rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.placement["block-placer"]).BlockPlacer end,
    }
    local remaining,failures=0,{}
    for _ in pairs(definitions) do remaining=remaining+1 end
    for name,fn in pairs(definitions) do
        task.spawn(function()
            local ok,value
            for attempt=1,3 do
                ok,value=pcall(fn)
                if ok and value then break end
                if not app.alive then return end
                task.wait(attempt*0.5)
            end
            if app.alive and not app.ready then
                if ok and value then app.dependencies[name]=value else failures[name]=tostring(value) end
                remaining=remaining-1
            end
        end)
    end
    local deadline=os.clock()+12
    repeat task.wait(0.1) until not app.alive or remaining==0 or os.clock()>=deadline
    if not app.alive then return end
    app.ready=true
    local count=0
    for name in pairs(definitions) do
        if app.dependencies[name] then count=count+1 else print("[BananaLite] dependency "..name.." unavailable: "..tostring(failures[name] or "timed out")) end
    end
    report("Ready · "..count.."/12 dependencies. All features start OFF. No flight or NoFall overrides.")
    local resume=shared.BananaLiteResume
    shared.BananaLiteResume=nil
    if type(resume)=="table" and type(resume.enabled)=="table" then
        phraseBox.Text=type(resume.phrases)=="string" and resume.phrases or ""
        for id,enabled in pairs(resume.enabled) do if enabled==true then setEnabled(id,true) end end
        report("Restored your enabled features after teleport.")
    end
    print("[BananaLite] BUILD 0.1.0 loaded; no game hooks installed")
end)
