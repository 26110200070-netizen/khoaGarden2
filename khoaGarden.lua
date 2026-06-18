--[[
=====================================================================
   360's GAG   -   Grow a Garden 2 hub
   Axon-style two-column UI, ruby-red accents.
   Right Shift toggles UI.  The X fully unloads.
=====================================================================
]]

--========================== SERVICES ==============================--
local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CollectionService= game:GetService("CollectionService")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer

--========================== GAME API ==============================--
local Net = (function() local ok,m = pcall(function() return require(ReplicatedStorage.SharedModules.Networking) end) return ok and m or nil end)()
local PSC = (function() local ok,m = pcall(function() return require(ReplicatedStorage.ClientModules.PlayerStateClient) end) return ok and m or nil end)()
if not Net then warn("[360's GAG] Networking module missing - aborting."); return end

local SeedData = (function() local ok,d = pcall(function() return require(ReplicatedStorage.SharedModules.SeedData) end) return ok and d or {} end)()
local SeedPrice = {}
for _, e in ipairs(SeedData) do
    if type(e) == "table" and e.SeedName then SeedPrice[e.SeedName] = tonumber(e.PurchasePrice) or math.huge end
end
local FruitValueCalc = (function() local ok,m = pcall(function() return require(ReplicatedStorage.SharedModules.FruitValueCalc) end) return (ok and type(m) == "function") and m or nil end)()
-- FruitValueCalc can't be called from spawned loop threads (executor capability),
-- so precompute each crop's base value here on the main thread and cache it.
local SeedBaseValue = {}
if FruitValueCalc then
    for _, e in ipairs(SeedData) do
        if type(e) == "table" and e.SeedName then
            local ok, v = pcall(FruitValueCalc, e.SeedName, 1, nil, LocalPlayer, nil)
            SeedBaseValue[e.SeedName] = (ok and type(v) == "number") and v or 0
        end
    end
end
local MUT_BONUS = 2.35  -- rough multiplier for any mutation (gold/rainbow/etc.)
local SIZE_EXP  = 2.65  -- FruitValueCalc scales value by size^2.65
local function sizeMul(sz) sz = tonumber(sz) or 1 return sz ^ SIZE_EXP end
local PetData = (function() local ok,m = pcall(function() return require(ReplicatedStorage.SharedData.PetData) end) return ok and m or {} end)()
local function getAnimalOptions()
    local list = {}
    for k, v in pairs(PetData) do if type(v) == "table" and type(k) == "string" then list[#list + 1] = k end end
    table.sort(list); return list
end

--========================== LIFECYCLE =============================--
local Hub = { running = true, conns = {} }
local genv = (getgenv and getgenv()) or _G
if genv.GAG360_unload then pcall(genv.GAG360_unload) end
local function track(conn) table.insert(Hub.conns, conn); return conn end
local function spawnLoop(interval, fn)
    task.spawn(function()
        while Hub.running do
            task.wait(interval)
            if not Hub.running then break end
            pcall(fn)
        end
    end)
end

--========================== STATE =================================--
local S = {
    autoBuySeed = false, buySeeds = {},
    autoPlant = false, plantSeeds = {}, plantReserve = 0, maxPerCycle = 40, plantDelay = 0.14, plantLoop = 1.2, smartReplant = false, autoExpand = false,
    plantPattern = "Fill", plantSource = "My Seeds", autoBuild = false, removeCrops = {},
    autoCollect = false, harvestCrops = {}, harvestMutsOnly = false, perFruitDelay = 0.05, harvestLoop = 1,
    autoSell = false, sellInterval = 20, sellOnFull = false,
    autoSteal = false, stealReturn = true, stealMult = 1,
    panicHarvest = false, retaliate = false,
    autoGrabPacks = false, grabRareOnly = true, packReturn = true, notifyRare = true,
    autoBuyGear = false, buyGears = {}, autoBuyCrate = false,
    autoEggs = false, autoCrates = false, autoPacks = false,
    autoTame = false, tameAnimals = {}, autoEquipPets = false, equipPets = {},
    walkSpeed = 16, jumpPower = 50, infJump = false, noclip = false, fly = false, flySpeed = 60,
    antiAfk = true, optimize = false, autoProgress = false,
    highlightReady = false, highlightRare = false, rareNotify = false,
    webhookUrl = "", whRareSeed = false, whBigHarvest = false, autoHopRare = false,
}

-- settings persistence: save S to disk, restore it on next load (toggles, sliders, picks)
local SAVE_FILE = "360_GAG_GrowAGarden2.json"
local HttpService = game:GetService("HttpService")
local function saveSettings()
    if not writefile then return end
    pcall(function() writefile(SAVE_FILE, HttpService:JSONEncode(S)) end)
end
local function loadSettings()
    if not (readfile and isfile) then return end
    local ok, raw = pcall(function() return isfile(SAVE_FILE) and readfile(SAVE_FILE) or nil end)
    if not (ok and raw) then return end
    local good, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not (good and type(data) == "table") then return end
    for k, v in pairs(data) do
        if S[k] ~= nil then
            if type(S[k]) == "table" and type(v) == "table" then
                table.clear(S[k]); for kk, vv in pairs(v) do S[k][kk] = vv end  -- keep the table reference the UI holds
            elseif type(S[k]) == type(v) then
                S[k] = v
            end
        end
    end
end
loadSettings()

--========================== HELPERS ===============================--
local function getReplica() if not PSC then return nil end local ok,r = pcall(function() return PSC:GetLocalReplica() end) return ok and r or nil end
local function getData()    local r = getReplica() return r and r.Data or nil end
local function getSheckles() local d = getData() return d and d.Sheckles or 0 end
local function myPlot()
    local g = Workspace:FindFirstChild("Gardens"); if not g then return nil end
    for _, plot in ipairs(g:GetChildren()) do if plot:GetAttribute("OwnerUserId") == LocalPlayer.UserId then return plot end end
end
local function isNight() local n = ReplicatedStorage:FindFirstChild("Night") return n and n.Value == true end
local function char()     return LocalPlayer.Character end
local function hrp()      local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function humanoid() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end
local function fire(pkt, ...) local a = {...} return pcall(function() return pkt:Fire(table.unpack(a)) end) end
local function teleportTo(pos) local r = hrp() if r and pos then r.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end end
local toast  -- cool in-hub slide-in notification (assigned once the GUI exists)
local function notify(t, title, col) if toast then toast(title or "360's GAG", t, col) end pcall(function() Net.Notification:Fire("360's GAG", t) end) end

local function setCharCollide(on)
    local c = char(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then pcall(function() p.CanCollide = on end) end end
end
local HOP = 70
local function reach(pos)
    local r = hrp(); if not (r and pos) then return end
    local target = pos + Vector3.new(0, 3, 0)
    setCharCollide(false)  -- noclip while teleporting so we never snag on fences/geometry
    for _ = 1, 60 do
        local cur = r.Position; local delta = target - cur
        if delta.Magnitude <= HOP then r.CFrame = CFrame.new(target); break end
        r.CFrame = CFrame.new(cur + delta.Unit * HOP); RunService.Heartbeat:Wait()
    end
    if not S.noclip then setCharCollide(true) end  -- restore unless permanent noclip is on
end
local function fruitValue(m)
    local base = SeedBaseValue[m:GetAttribute("CorePartName") or m:GetAttribute("SeedName")] or 0
    return base * sizeMul(m:GetAttribute("SizeMulti") or 1) * (m:GetAttribute("Mutation") and MUT_BONUS or 1)
end
-- a fruit/plant is ready when its Age has reached MaxAge (reliable + cheap);
-- fall back to the presence of a HarvestPrompt-tagged prompt inside it.
local function modelRipe(m)
    local age = tonumber(m:GetAttribute("Age")); local mx = tonumber(m:GetAttribute("MaxAge"))
    if age and mx then return age >= mx - 0.001 end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("ProximityPrompt") and CollectionService:HasTag(d, "HarvestPrompt") then return true end
    end
    return false
end
-- scan only MY plot (fast + reliable) instead of every tagged prompt on the server
local function ownHarvestTargets(respectFilter)
    local useCrop = respectFilter and next(S.harvestCrops) ~= nil
    local out = {}
    local plot = myPlot(); if not plot then return out end
    local plants = plot:FindFirstChild("Plants"); if not plants then return out end
    local function consider(m)
        if not m:GetAttribute("PlantId") then return end
        local crop = m:GetAttribute("CorePartName") or m:GetAttribute("SeedName")
        local mutOk = (not respectFilter) or (not S.harvestMutsOnly) or (m:GetAttribute("Mutation") ~= nil)
        if ((not useCrop) or (crop and S.harvestCrops[crop] == true)) and mutOk then out[#out + 1] = m end
    end
    for _, plant in ipairs(plants:GetChildren()) do
        local fr = plant:FindFirstChild("Fruits")
        local fruits = fr and fr:GetChildren() or {}
        if #fruits > 0 then
            for _, m in ipairs(fruits) do if modelRipe(m) then consider(m) end end  -- multi-fruit crops
        elseif modelRipe(plant) then
            consider(plant)  -- single-harvest crops (carrot/tulip/bamboo) - the plant is the unit
        end
    end
    return out
end
local function stealTargets()
    local out = {}
    for _, p in ipairs(CollectionService:GetTagged("StealPrompt")) do
        local m = p.Parent and p.Parent:FindFirstAncestorWhichIsA("Model")
        if m then
            local uid = tonumber(m:GetAttribute("UserId"))
            if uid and uid ~= LocalPlayer.UserId and m:GetAttribute("PlantId") then out[#out + 1] = { model = m, value = fruitValue(m) } end
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out
end
local function collectModel(m)
    if not m or not m.Parent then return end
    local pid = m:GetAttribute("PlantId"); if not pid then return end
    reach(m:GetPivot().Position); task.wait(S.perFruitDelay)
    fire(Net.Garden.CollectFruit, pid, m:GetAttribute("FruitId") or "")
end
-- bulk harvest: stand at plot centre once, then fire CollectFruit for every ripe
-- fruit (own crops sit within ~20 studs of centre) - no per-fruit teleporting
local function harvestAll(respectFilter)
    local plot = myPlot(); local ref = plot and plot:FindFirstChild("PlotSizeReference"); local r = hrp()
    if ref and r and (Vector3.new(r.Position.X,0,r.Position.Z) - Vector3.new(ref.Position.X,0,ref.Position.Z)).Magnitude > 16 then
        reach(ref.Position); task.wait(0.12)
    end
    local t = ownHarvestTargets(respectFilter); local n = 0
    for _, m in ipairs(t) do
        local pid = m:GetAttribute("PlantId")
        if pid then fire(Net.Garden.CollectFruit, pid, m:GetAttribute("FruitId") or ""); n = n + 1; task.wait(S.perFruitDelay) end
    end
    return n
end
local function stealModel(m, mult, skipReach)
    if not m or not m.Parent then return end
    local uid = tonumber(m:GetAttribute("UserId")); local pid = m:GetAttribute("PlantId")
    if not (uid and pid) then return end
    if not skipReach then reach(m:GetPivot().Position); task.wait(0.05) end
    fire(Net.Steal.BeginSteal, uid, pid, m:GetAttribute("FruitId") or "")
    -- you can carry multiple fruits per steal - fire CompleteSteal mult times
    for _ = 1, math.max(1, mult or 1) do fire(Net.Steal.CompleteSteal) end
end

local function stockItems(shop)
    local sv = ReplicatedStorage:FindFirstChild("StockValues"); sv = sv and sv:FindFirstChild(shop)
    return sv and sv:FindFirstChild("Items")
end
local function seedStockItems() return stockItems("SeedShop") end
local function gearStockItems() return stockItems("GearShop") end
local function stockOf(shop, name) local it = stockItems(shop); local v = it and it:FindFirstChild(name) return (v and v:IsA("ValueBase")) and v.Value or 0 end
local function seedStockOf(name) return stockOf("SeedShop", name) end
local function gearStockOf(name) return stockOf("GearShop", name) end
local function getGearOptions()
    local it = gearStockItems(); local list = {}
    if it then for _, sv in ipairs(it:GetChildren()) do list[#list + 1] = sv.Name end end
    table.sort(list); return list
end
local function getSeedOptions()
    local seen = {}
    for _, e in ipairs(SeedData) do if e.SeedName then seen[e.SeedName] = tonumber(e.SeedShopDisplayOrder) or 900 end end
    local it = seedStockItems(); if it then for _, sv in ipairs(it:GetChildren()) do if seen[sv.Name] == nil then seen[sv.Name] = 899 end end end
    local list = {} for name, ord in pairs(seen) do list[#list + 1] = { name, ord } end
    table.sort(list, function(a, b) if a[2] == b[2] then return a[1] < b[1] end return a[2] < b[2] end)
    local names = {} for _, x in ipairs(list) do names[#names + 1] = x[1] end
    return names
end
-- ONLY the seeds currently in your inventory (live-updates with the shop dropdown loop)
local function getOwnedSeedOptions()
    local d = getData(); local order = {}
    for _, e in ipairs(SeedData) do if e.SeedName then order[e.SeedName] = tonumber(e.SeedShopDisplayOrder) or 900 end end
    local list = {}
    if d and d.Inventory and d.Inventory.Seeds then
        for n, c in pairs(d.Inventory.Seeds) do if (c or 0) > 0 then list[#list + 1] = n end end
    end
    table.sort(list, function(a, b) local oa, ob = order[a] or 900, order[b] or 900 if oa == ob then return a < b end return oa < ob end)
    return list
end
-- distinct crop types currently PLANTED in your garden (for the remove picker)
local function getPlantedOptions()
    local plot = myPlot(); local seen = {}
    if plot then local plants = plot:FindFirstChild("Plants")
        if plants then for _, pl in ipairs(plants:GetChildren()) do local s = pl:GetAttribute("SeedName") or pl:GetAttribute("CorePartName") if s then seen[s] = true end end end
    end
    local list = {} for k in pairs(seen) do list[#list + 1] = k end table.sort(list); return list
end
local function getHarvestOptions()
    local seen = {}
    local plot = myPlot()
    if plot then local plants = plot:FindFirstChild("Plants") if plants then for _, pl in ipairs(plants:GetChildren()) do local s = pl:GetAttribute("SeedName") or pl:GetAttribute("CorePartName") if s then seen[s] = true end end end end
    local d = getData(); if d and d.Inventory and d.Inventory.Seeds then for n in pairs(d.Inventory.Seeds) do seen[n] = true end end
    local list = {} for k in pairs(seen) do list[#list + 1] = k end table.sort(list); return list
end
local function getPetOptions()
    local d = getData(); local seen = {}
    if d and d.Inventory and d.Inventory.Pets then
        for _, info in pairs(d.Inventory.Pets) do local nm = (type(info) == "table" and (info.PetType or info.Name)) or tostring(info) if nm and nm ~= "" then seen[nm] = true end end
    end
    local list = {} for k in pairs(seen) do list[#list + 1] = k end table.sort(list); return list
end
local function maxEquip() return tonumber(LocalPlayer:GetAttribute("MaxEquippedPets")) or 3 end

-- most valuable seed you currently own (uses cached base values)
local function bestOwnedSeed()
    local d = getData(); local seeds = d and d.Inventory and d.Inventory.Seeds; if not seeds then return nil end
    local best, bestV
    for name, count in pairs(seeds) do
        if (count or 0) > 0 then local v = SeedBaseValue[name] or 0 if not bestV or v > bestV then best, bestV = name, v end end
    end
    return best, bestV
end
-- estimated worth of harvested fruit in your backpack (cached base * size * mutation)
local function inventoryValue()
    local total, n = 0, 0
    local function scan(c) if not c then return end for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") and (t:GetAttribute("HarvestedFruit") or t:GetAttribute("Fruit")) then
            n = n + 1
            local base = SeedBaseValue[t:GetAttribute("Fruit") or t:GetAttribute("CorePartName")] or 0
            total = total + base * sizeMul(t:GetAttribute("SizeMultiplier") or t:GetAttribute("SizeMulti") or 1) * (t:GetAttribute("Mutation") and MUT_BONUS or 1)
        end
    end end
    scan(LocalPlayer:FindFirstChild("Backpack")); scan(char())
    return total, n
end
local function abbrev(n)
    n = tonumber(n) or 0
    if n >= 1e9 then return string.format("%.2fB", n/1e9) end
    if n >= 1e6 then return string.format("%.2fM", n/1e6) end
    if n >= 1e3 then return string.format("%.1fK", n/1e3) end
    return tostring(math.floor(n))
end

local EVENT_NAME = { Moon = "Moonlit", Bloodmoon = "Blood Moon", Goldmoon = "Gold Moon",
    ["Rainbow Moon"] = "Rainbow Moon", ["Chained Moon"] = "Chained Moon", ["Pizza Moon"] = "Pizza Moon", Sunset = "Sunset", Day = "Day" }
local EVENT_COLOR = {
    Day = Color3.fromRGB(255,214,90), Sunset = Color3.fromRGB(255,150,90), Moon = Color3.fromRGB(190,150,255),
    Bloodmoon = Color3.fromRGB(176,32,32), Goldmoon = Color3.fromRGB(255,205,70), ["Rainbow Moon"] = Color3.fromRGB(255,120,200),
    ["Chained Moon"] = Color3.fromRGB(150,150,162), ["Pizza Moon"] = Color3.fromRGB(232,120,60) }
local function eventColorOf(r) return EVENT_COLOR[r] or Color3.fromRGB(225,225,230) end
local function eventNameOf(r) return EVENT_NAME[r] or tostring(r or "-") end
local function currentEvent() return workspace:GetAttribute("ActiveWeather"), workspace:GetAttribute("ActivePhase"), tonumber(workspace:GetAttribute("PhaseDuration")) end
local function fmtClock(s) s = math.max(0, math.floor(s or 0)) return string.format("%d:%02d", s // 60, s % 60) end
local function restockIn(shop)
    local sv = ReplicatedStorage:FindFirstChild("StockValues"); sv = sv and sv:FindFirstChild(shop)
    local nx = sv and sv:FindFirstChild("UnixNextRestock")
    return nx and math.max(0, nx.Value - os.time()) or nil
end

--====================== GUI THEME (RUBY) ==========================--
local C = {
    bg     = Color3.fromRGB(17,17,20),  panel  = Color3.fromRGB(23,23,27),  card  = Color3.fromRGB(29,29,34),
    cardHi = Color3.fromRGB(36,36,42),  inset  = Color3.fromRGB(15,15,18),  stroke= Color3.fromRGB(46,46,53),
    white  = Color3.fromRGB(240,240,245), text = Color3.fromRGB(223,223,229), sub  = Color3.fromRGB(138,138,148),
    head   = Color3.fromRGB(120,120,130),
    accent = Color3.fromRGB(196,30,58),  accentDim = Color3.fromRGB(120,22,40),  accentText = Color3.fromRGB(232,96,114),
    green = Color3.fromRGB(80,220,130),  count = Color3.fromRGB(150,150,160),  rowOn = Color3.fromRGB(96,22,40),
}
-- number / money formatting
local function commafy(n)
    local neg = n < 0; local s = tostring(math.floor(math.abs(n) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. out
end
local function money(n) return "$" .. commafy(n) end
-- compact price tag with the game's coin sign, e.g. 700K¢ / 1.2M¢ / 5,000¢
local function fmtPrice(n)
    n = tonumber(n); if not n or n <= 0 or n == math.huge then return "" end
    local s
    if n >= 1e9 then s = string.format("%.1fB", n/1e9)
    elseif n >= 1e6 then s = string.format("%.1fM", n/1e6)
    elseif n >= 1e3 then s = string.format("%.0fK", n/1e3)
    else s = commafy(n) end
    s = s:gsub("%.0(%a)", "%1")  -- 5.0M -> 5M
    return s .. "\xc2\xa2"
end
local function seedPriceTag(nm) return fmtPrice(SeedPrice[nm]) end
local FB, FM, FR = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.Gotham
local function corner(i, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 8) c.Parent = i return c end
local function stroke(i, col, t) local s = Instance.new("UIStroke") s.Color = col or C.stroke s.Thickness = t or 1 s.Parent = i return s end
local function padAll(i, l,r,t,b) local u = Instance.new("UIPadding") u.PaddingLeft = UDim.new(0,l) u.PaddingRight = UDim.new(0,r or l) u.PaddingTop = UDim.new(0,t or l) u.PaddingBottom = UDim.new(0,b or t or l) u.Parent = i return u end
local function vlist(i, p) local l = Instance.new("UIListLayout") l.Padding = UDim.new(0,p or 8) l.SortOrder = Enum.SortOrder.LayoutOrder l.Parent = i return l end
local function nextOrder(p) local n = (p:GetAttribute("_o") or 0) + 1 p:SetAttribute("_o", n) return n end

local function guiParent()
    local p; pcall(function() p = gethui and gethui() end)
    if not p then pcall(function() p = game:GetService("CoreGui") end) end
    return p or LocalPlayer:WaitForChild("PlayerGui")
end
pcall(function() local old = guiParent():FindFirstChild("GAG360") if old then old:Destroy() end end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GAG360"; ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; ScreenGui.IgnoreGuiInset = true
if syn and syn.protect_gui then pcall(syn.protect_gui, ScreenGui) end
ScreenGui.Parent = guiParent()

local Main = Instance.new("Frame")
Main.Name = "Main"; Main.AnchorPoint = Vector2.new(0.5, 0.5); Main.Size = UDim2.fromOffset(1020, 700)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = C.bg; Main.BorderSizePixel = 0; Main.Parent = ScreenGui
corner(Main, 12); stroke(Main, C.stroke, 1)
local UIScale = Instance.new("UIScale"); UIScale.Scale = 1; UIScale.Parent = Main
do
    local sh = Instance.new("ImageLabel"); sh.BackgroundTransparency = 1; sh.Image = "rbxassetid://6014261993"
    sh.ImageColor3 = Color3.new(0,0,0); sh.ImageTransparency = 0.35; sh.ScaleType = Enum.ScaleType.Slice
    sh.SliceCenter = Rect.new(49,49,450,450); sh.Size = UDim2.new(1,46,1,46); sh.Position = UDim2.new(0,-23,0,-23); sh.ZIndex = 0; sh.Parent = Main
end

-- title bar
local Top = Instance.new("Frame"); Top.Size = UDim2.new(1,0,0,42); Top.BackgroundTransparency = 1; Top.Parent = Main
do  -- ruby gem logo
    local gem = Instance.new("Frame"); gem.AnchorPoint = Vector2.new(0.5,0.5); gem.Position = UDim2.fromOffset(26,21)
    gem.Size = UDim2.fromOffset(15,15); gem.BackgroundColor3 = C.accent; gem.Rotation = 45; gem.Parent = Top; corner(gem,4)
    local hi = Instance.new("Frame"); hi.AnchorPoint = Vector2.new(0.5,0); hi.Position = UDim2.new(0.5,0,0,2.5)
    hi.Size = UDim2.fromOffset(8,3.5); hi.BackgroundColor3 = Color3.fromRGB(245,150,160); hi.BackgroundTransparency = 0.1; hi.Parent = gem; corner(hi,2)
end
local Title = Instance.new("TextLabel"); Title.BackgroundTransparency = 1; Title.Position = UDim2.fromOffset(44,7)
Title.Size = UDim2.fromOffset(300,16); Title.Font = FB; Title.Text = "360's GAG"; Title.TextSize = 15; Title.TextColor3 = C.white
Title.TextXAlignment = Enum.TextXAlignment.Left; Title.Parent = Top
local Sub = Instance.new("TextLabel"); Sub.BackgroundTransparency = 1; Sub.Position = UDim2.fromOffset(44,23)
Sub.Size = UDim2.fromOffset(300,12); Sub.Font = FR; Sub.Text = "Grow a Garden 2"; Sub.TextSize = 10; Sub.TextColor3 = C.sub
Sub.TextXAlignment = Enum.TextXAlignment.Left; Sub.Parent = Top

local function winBtn(xoff)
    local b = Instance.new("TextButton"); b.AnchorPoint = Vector2.new(1,0.5); b.Position = UDim2.new(1, xoff, 0, 21)
    b.Size = UDim2.fromOffset(24,24); b.BackgroundColor3 = C.card; b.Text = ""; b.AutoButtonColor = true; b.Parent = Top
    corner(b,7); return b
end
local CloseBtn = winBtn(-12)
local MaxBtn   = winBtn(-42)
local MinBtn   = winBtn(-72)
CloseBtn.BackgroundColor3 = C.accentDim
track(CloseBtn.MouseEnter:Connect(function() TweenService:Create(CloseBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.accent }):Play() end))
track(CloseBtn.MouseLeave:Connect(function() TweenService:Create(CloseBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.accentDim }):Play() end))
for _, rot in ipairs({45,-45}) do
    local bar = Instance.new("Frame"); bar.AnchorPoint = Vector2.new(0.5,0.5); bar.Position = UDim2.fromScale(0.5,0.5)
    bar.Size = UDim2.fromOffset(12,2.5); bar.BackgroundColor3 = C.white; bar.BorderSizePixel = 0; bar.Rotation = rot; bar.Parent = CloseBtn; corner(bar,2)
end
local MinPlusBar
do
    local sq = Instance.new("Frame"); sq.AnchorPoint = Vector2.new(0.5,0.5); sq.Position = UDim2.fromScale(0.5,0.5)
    sq.Size = UDim2.fromOffset(10,10); sq.BackgroundTransparency = 1; sq.Parent = MaxBtn; corner(sq,2); stroke(sq, C.text, 1.5)
    -- minimize glyph: horizontal bar ("-"); a hidden vertical bar makes it a "+" when minimized
    local mb = Instance.new("Frame"); mb.AnchorPoint = Vector2.new(0.5,0.5); mb.Position = UDim2.fromScale(0.5,0.5)
    mb.Size = UDim2.fromOffset(10,2); mb.BackgroundColor3 = C.text; mb.BorderSizePixel = 0; mb.Parent = MinBtn; corner(mb,1)
    MinPlusBar = Instance.new("Frame"); MinPlusBar.AnchorPoint = Vector2.new(0.5,0.5); MinPlusBar.Position = UDim2.fromScale(0.5,0.5)
    MinPlusBar.Size = UDim2.fromOffset(2,10); MinPlusBar.BackgroundColor3 = C.text; MinPlusBar.BorderSizePixel = 0; MinPlusBar.Visible = false; MinPlusBar.Parent = MinBtn; corner(MinPlusBar,1)
end
-- body
local Body = Instance.new("Frame"); Body.Name = "Body"; Body.Position = UDim2.fromOffset(0,42)
Body.Size = UDim2.new(1,0,1,-42); Body.BackgroundTransparency = 1; Body.Parent = Main

local Sidebar = Instance.new("Frame"); Sidebar.Name = "Sidebar"; Sidebar.Position = UDim2.fromOffset(12,0)
Sidebar.Size = UDim2.new(0,176,1,-12); Sidebar.BackgroundColor3 = C.panel; Sidebar.Parent = Body
corner(Sidebar,10); stroke(Sidebar, C.stroke,1)
local SideList = Instance.new("ScrollingFrame"); SideList.BackgroundTransparency = 1; SideList.BorderSizePixel = 0; SideList.Size = UDim2.new(1,0,1,-64); SideList.Parent = Sidebar
SideList.ScrollBarThickness = 3; SideList.ScrollBarImageColor3 = C.stroke; SideList.CanvasSize = UDim2.new(0,0,0,0); SideList.AutomaticCanvasSize = Enum.AutomaticSize.Y
vlist(SideList, 3); padAll(SideList, 8, 8, 8, 6)
-- profile (pinned bottom)
do
    local pf = Instance.new("Frame"); pf.AnchorPoint = Vector2.new(0,1); pf.Position = UDim2.new(0,0,1,-8)
    pf.Size = UDim2.new(1,0,0,52); pf.BackgroundTransparency = 1; pf.Parent = Sidebar
    local av = Instance.new("ImageLabel"); av.Position = UDim2.fromOffset(12,9); av.Size = UDim2.fromOffset(34,34)
    av.BackgroundColor3 = C.card; av.Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=48&h=48"; av.Parent = pf; corner(av,17); stroke(av, C.accent, 1)
    local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Position = UDim2.fromOffset(54,11); nm.Size = UDim2.fromOffset(112,16)
    nm.Font = FB; nm.Text = LocalPlayer.DisplayName; nm.TextSize = 13; nm.TextColor3 = C.white; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = pf
    local sub = Instance.new("TextLabel"); sub.BackgroundTransparency = 1; sub.Position = UDim2.fromOffset(54,28); sub.Size = UDim2.fromOffset(112,14)
    sub.Font = FR; sub.Text = "Grow a Garden 2"; sub.TextSize = 10; sub.TextColor3 = C.sub; sub.TextXAlignment = Enum.TextXAlignment.Left; sub.Parent = pf
end

-- content (header title + scroll)
local Content = Instance.new("Frame"); Content.Name = "Content"; Content.Position = UDim2.fromOffset(200,0)
Content.Size = UDim2.new(1,-212,1,-12); Content.BackgroundColor3 = C.panel; Content.Parent = Body
corner(Content,10); stroke(Content, C.stroke,1)
local CTitle = Instance.new("TextLabel"); CTitle.BackgroundTransparency = 1; CTitle.Position = UDim2.fromOffset(18,10)
CTitle.Size = UDim2.new(1,-36,0,20); CTitle.Font = FB; CTitle.Text = "Farm"; CTitle.TextSize = 17; CTitle.TextColor3 = C.white
CTitle.TextXAlignment = Enum.TextXAlignment.Left; CTitle.Parent = Content
local Scroll = Instance.new("ScrollingFrame"); Scroll.Position = UDim2.fromOffset(8,36); Scroll.Size = UDim2.new(1,-16,1,-44)
Scroll.BackgroundTransparency = 1; Scroll.BorderSizePixel = 0; Scroll.ScrollBarThickness = 4; Scroll.ScrollBarImageColor3 = C.stroke
Scroll.CanvasSize = UDim2.new(0,0,0,0); Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; Scroll.Parent = Content
padAll(Scroll, 10, 10, 4, 10)

-- status (bottom strip, left aligned)
local Status = Instance.new("TextLabel"); Status.AnchorPoint = Vector2.new(0,1); Status.Position = UDim2.new(0,16,1,-1)
Status.Size = UDim2.fromOffset(560,12); Status.BackgroundTransparency = 1; Status.Font = FR; Status.Text = "ready"; Status.TextSize = 10
Status.TextColor3 = C.sub; Status.TextXAlignment = Enum.TextXAlignment.Left; Status.Parent = Main
local function setStatus(t) Status.Text = t end

-- cool slide-in toast notifications (top-right, stack downward, auto-dismiss).
-- Parented to the ScreenGui so they show full-size even when the window is hidden.
local activeToasts = {}
-- the ScreenGui sits inside CoreGui/HiddenUI which is offset (AbsolutePosition.Y ~= 0);
-- compensate so y=0 is the real screen top, otherwise toasts render off-screen.
local function topInset() return -ScreenGui.AbsolutePosition.Y end
local function reflowToasts()
    local base = topInset() + 18; local y = 0
    for _, c in ipairs(activeToasts) do
        TweenService:Create(c, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = UDim2.new(1, -18, 0, base + y) }):Play()
        y = y + c.AbsoluteSize.Y + 8
    end
end
toast = function(title, msg, col)
    col = col or C.accent
    local card = Instance.new("Frame"); card.AnchorPoint = Vector2.new(1,0); card.Size = UDim2.fromOffset(300,0); card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = C.card; card.Position = UDim2.new(1, 360, 0, topInset() + 18); card.Parent = ScreenGui
    corner(card,10); stroke(card, col, 1.5)
    local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,12); pad.PaddingTop = UDim.new(0,10); pad.PaddingBottom = UDim.new(0,10); pad.Parent = card
    local vl = Instance.new("UIListLayout"); vl.Padding = UDim.new(0,3); vl.SortOrder = Enum.SortOrder.LayoutOrder; vl.Parent = card
    local hrow = Instance.new("Frame"); hrow.Size = UDim2.new(1,0,0,16); hrow.BackgroundTransparency = 1; hrow.LayoutOrder = 1; hrow.Parent = card
    local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0,0.5); dot.Position = UDim2.new(0,1,0.5,0); dot.Size = UDim2.fromOffset(9,9); dot.BackgroundColor3 = col; dot.BorderSizePixel = 0; dot.Parent = hrow; corner(dot,5)
    local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Position = UDim2.fromOffset(18,0); t.Size = UDim2.new(1,-18,1,0); t.Font = FB; t.Text = title; t.TextSize = 14; t.TextColor3 = col; t.TextXAlignment = Enum.TextXAlignment.Left; t.Parent = hrow
    local m = Instance.new("TextLabel"); m.BackgroundTransparency = 1; m.Size = UDim2.new(1,0,0,0); m.AutomaticSize = Enum.AutomaticSize.Y; m.Font = FR; m.Text = msg; m.TextSize = 12.5; m.TextColor3 = C.text; m.TextWrapped = true; m.TextXAlignment = Enum.TextXAlignment.Left; m.LayoutOrder = 2; m.Parent = card
    table.insert(activeToasts, 1, card)
    task.defer(reflowToasts)
    task.delay(4.8, function()
        if not card.Parent then return end
        TweenService:Create(card, TweenInfo.new(0.24, Enum.EasingStyle.Quad), { Position = UDim2.new(1, 360, 0, card.Position.Y.Offset) }):Play()
        task.wait(0.26)
        for i, c in ipairs(activeToasts) do if c == card then table.remove(activeToasts, i) break end end
        card:Destroy(); reflowToasts()
    end)
    return card
end

--========================= TAB SYSTEM =============================--
local pages, tabButtons, tabBars, tabLabels = {}, {}, {}, {}
local TI = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
local function selectTab(name)
    CTitle.Text = name
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, b in pairs(tabButtons) do
        local on = (n == name)
        TweenService:Create(b, TI, { BackgroundColor3 = on and C.card or C.panel }):Play()
        if tabLabels[n] then TweenService:Create(tabLabels[n], TI, { TextColor3 = on and C.accentText or C.sub }):Play() end
        if tabBars[n] then
            TweenService:Create(tabBars[n], TI, { BackgroundTransparency = on and 0 or 1, Size = UDim2.fromOffset(3, on and 14 or 0) }):Play()
        end
    end
end
local sideOrder = 0
local function addGroup(title)
    sideOrder = sideOrder + 1
    local h = Instance.new("Frame"); h.Size = UDim2.new(1,0,0,30); h.BackgroundTransparency = 1; h.LayoutOrder = sideOrder; h.Parent = SideList
    local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0,0.5); dot.Position = UDim2.new(0,8,0,21); dot.Size = UDim2.fromOffset(5,5); dot.BackgroundColor3 = C.accent; dot.Parent = h; corner(dot,3)
    local l = Instance.new("TextLabel"); l.Position = UDim2.fromOffset(20,10); l.Size = UDim2.new(1,-26,0,18); l.BackgroundTransparency = 1; l.Font = FB
    l.Text = string.upper(title); l.TextSize = 12; l.TextColor3 = C.accentText; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = h
end
local function addTab(name, icon)
    sideOrder = sideOrder + 1
    local b = Instance.new("TextButton"); b.Size = UDim2.new(1,0,0,28); b.BackgroundColor3 = C.panel
    b.Text = ""; b.AutoButtonColor = false; b.LayoutOrder = sideOrder; b.Parent = SideList; corner(b,7)
    -- active indicator bar at the far left (its own column, never under the label)
    local bar = Instance.new("Frame"); bar.AnchorPoint = Vector2.new(0,0.5); bar.Position = UDim2.new(0,5,0.5,0)
    bar.Size = UDim2.fromOffset(3,0); bar.BackgroundColor3 = C.accent; bar.BackgroundTransparency = 1; bar.Parent = b; corner(bar,2)
    local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.Position = UDim2.fromOffset(16,0); lbl.Size = UDim2.new(1,-22,1,0)
    lbl.Font = FM; lbl.Text = name; lbl.TextSize = 12.5; lbl.TextColor3 = C.sub; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = b
    track(b.MouseButton1Click:Connect(function() selectTab(name) end))
    tabButtons[name] = b; tabBars[name] = bar; tabLabels[name] = lbl
    -- -20 width: a ScrollingFrame's UIPadding shifts children right but does NOT shrink
    -- their (1,0) width, so without this the right column overflows the visible area.
    local page = Instance.new("Frame"); page.Name = name; page.Size = UDim2.new(1,-20,0,0); page.AutomaticSize = Enum.AutomaticSize.Y
    page.BackgroundTransparency = 1; page.Visible = false; page.Parent = Scroll
    local row = Instance.new("UIListLayout"); row.FillDirection = Enum.FillDirection.Horizontal; row.Padding = UDim.new(0,14)
    row.SortOrder = Enum.SortOrder.LayoutOrder; row.HorizontalAlignment = Enum.HorizontalAlignment.Left; row.Parent = page
    pages[name] = page
    return page
end
-- columns. NOTE: the page row layout adds a 14px gap, so two 0.5 columns must each
-- shed 7px or the right column overflows the page and gets clipped.
local function column(page, w, off)
    local col = Instance.new("Frame"); col.Size = UDim2.new(w, off or 0, 0, 0); col.AutomaticSize = Enum.AutomaticSize.Y
    col.BackgroundTransparency = 1; col.LayoutOrder = nextOrder(page); col.Parent = page
    vlist(col, 8); return col
end
local function twoCol(page) return column(page, 0.5, -7), column(page, 0.5, -7) end
local function oneCol(page) return column(page, 1, 0) end

--========================= COMPONENTS ============================--
local function colTitle(_, _) end  -- column titles removed for a tighter layout
local function subTitle(parent, txt)
    local l = Instance.new("TextLabel"); l.Size = UDim2.new(1,0,0,16); l.BackgroundTransparency = 1; l.Font = FB
    l.Text = string.upper(txt); l.TextSize = 11; l.TextColor3 = C.accentText; l.TextXAlignment = Enum.TextXAlignment.Center
    l.LayoutOrder = nextOrder(parent); l.Parent = parent; return l
end
local function card(parent, h)
    local f = Instance.new("Frame"); f.BackgroundColor3 = C.card; f.Size = UDim2.new(1,0,0,h or 0)
    if not h then f.AutomaticSize = Enum.AutomaticSize.Y end
    f.LayoutOrder = nextOrder(parent); f.Parent = parent; corner(f,8); stroke(f, C.stroke,1); return f
end
local function textBlock(parent, name, desc, rightPad)
    local box = Instance.new("Frame"); box.BackgroundTransparency = 1; box.Position = UDim2.fromOffset(0,0)
    box.Size = UDim2.new(1, -(rightPad or 52), 0, 0); box.AutomaticSize = Enum.AutomaticSize.Y; box.Parent = parent
    vlist(box, 2)
    local n = Instance.new("TextLabel"); n.Size = UDim2.new(1,0,0,16); n.BackgroundTransparency = 1; n.Font = FM
    n.Text = name; n.TextSize = 13; n.TextColor3 = C.text; n.TextXAlignment = Enum.TextXAlignment.Left; n.LayoutOrder = 1; n.Parent = box
    if desc then
        local d = Instance.new("TextLabel"); d.Size = UDim2.new(1,0,0,0); d.AutomaticSize = Enum.AutomaticSize.Y; d.BackgroundTransparency = 1
        d.Font = FR; d.Text = desc; d.TextSize = 11; d.TextColor3 = C.sub; d.TextWrapped = true; d.TextXAlignment = Enum.TextXAlignment.Left; d.LayoutOrder = 2; d.Parent = box
    end
    return box
end
local function howItWorks(parent, text)
    local f = card(parent); padAll(f, 12, 12, 10, 11); vlist(f, 4)
    local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,0,0,14); t.BackgroundTransparency = 1; t.Font = FB
    t.Text = "How it works"; t.TextSize = 12; t.TextColor3 = C.white; t.TextXAlignment = Enum.TextXAlignment.Left; t.LayoutOrder = 1; t.Parent = f
    local d = Instance.new("TextLabel"); d.Size = UDim2.new(1,0,0,0); d.AutomaticSize = Enum.AutomaticSize.Y; d.BackgroundTransparency = 1
    d.Font = FR; d.Text = text; d.TextSize = 11; d.TextColor3 = C.sub; d.TextWrapped = true; d.TextXAlignment = Enum.TextXAlignment.Left; d.LayoutOrder = 2; d.Parent = f
    return f
end
local function toggleRow(parent, name, desc, key, cb)
    local f = card(parent); padAll(f, 12, 12, 10, 10)
    textBlock(f, name, desc)
    local sw = Instance.new("TextButton"); sw.AnchorPoint = Vector2.new(1,0); sw.Position = UDim2.new(1,0,0,2); sw.Size = UDim2.fromOffset(28,28)
    sw.AutoButtonColor = false; sw.Text = ""; sw.BackgroundColor3 = C.inset; sw.Parent = f; corner(sw,7); local sws = stroke(sw, C.stroke,1)
    -- white checkmark (two connected bars) shown on a green box when on
    local chk = Instance.new("Frame"); chk.BackgroundTransparency = 1; chk.Size = UDim2.fromScale(1,1); chk.Visible = false; chk.Parent = sw
    local b1 = Instance.new("Frame"); b1.AnchorPoint = Vector2.new(0.5,0.5); b1.Position = UDim2.new(0.35,0,0.59,0); b1.Size = UDim2.fromOffset(7,3); b1.Rotation = 45; b1.BackgroundColor3 = C.white; b1.BorderSizePixel = 0; b1.Parent = chk; corner(b1,2)
    local b2 = Instance.new("Frame"); b2.AnchorPoint = Vector2.new(0.5,0.5); b2.Position = UDim2.new(0.57,0,0.50,0); b2.Size = UDim2.fromOffset(14,3); b2.Rotation = -47; b2.BackgroundColor3 = C.white; b2.BorderSizePixel = 0; b2.Parent = chk; corner(b2,2)
    local function render(v)
        TweenService:Create(sw, TweenInfo.new(0.12), { BackgroundColor3 = v and C.green or C.inset }):Play()
        sws.Color = v and C.green or C.stroke; chk.Visible = v
    end
    local function set(v) if key then S[key] = v end render(v) if cb then cb(v) end saveSettings() end
    track(sw.MouseButton1Click:Connect(function() set(not (key and S[key])) end))
    render(key and S[key] or false)
    -- restore a saved-ON cb-driven effect (e.g. Optimize) without re-saving
    if cb and key and S[key] then task.spawn(function() cb(true) end) end
    return set
end
local function sliderRow(parent, name, mn, mx, default, decimals, setFn)
    local f = card(parent); padAll(f, 12, 12, 10, 12); vlist(f, 8)
    local head = Instance.new("Frame"); head.Size = UDim2.new(1,0,0,18); head.BackgroundTransparency = 1; head.LayoutOrder = 1; head.Parent = f
    local n = Instance.new("TextLabel"); n.Size = UDim2.new(1,-64,1,0); n.BackgroundTransparency = 1; n.Font = FM; n.Text = name
    n.TextSize = 13; n.TextColor3 = C.text; n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = head
    local box = Instance.new("Frame"); box.AnchorPoint = Vector2.new(1,0.5); box.Position = UDim2.new(1,0,0.5,0); box.Size = UDim2.fromOffset(56,22)
    box.BackgroundColor3 = C.inset; box.Parent = head; corner(box,6); stroke(box, C.stroke, 1)
    local val = Instance.new("TextBox"); val.Size = UDim2.new(1,-8,1,0); val.Position = UDim2.fromOffset(4,0); val.BackgroundTransparency = 1; val.Font = FB
    val.TextSize = 12; val.TextColor3 = C.accentText; val.ClearTextOnFocus = false; val.TextXAlignment = Enum.TextXAlignment.Center; val.Parent = box
    local track_ = Instance.new("Frame"); track_.Size = UDim2.new(1,0,0,6); track_.BackgroundColor3 = C.inset; track_.LayoutOrder = 2; track_.Parent = f; corner(track_,3)
    local fill = Instance.new("Frame"); fill.BackgroundColor3 = C.accent; fill.Parent = track_; corner(fill,3)
    local function fmt(v) if decimals and decimals > 0 then return string.format("%."..decimals.."f", v) else return tostring(math.floor(v)) end end
    local cur = default
    local function apply(v)
        cur = v; fill.Size = UDim2.new((v-mn)/(mx-mn),0,1,0); val.Text = fmt(v); if setFn then setFn(v) end
    end
    apply(default)
    local dragging = false
    local function upd(px)
        local rel = math.clamp((px - track_.AbsolutePosition.X)/math.max(1,track_.AbsoluteSize.X), 0, 1)
        local raw = mn + (mx-mn)*rel
        local v = (decimals and decimals > 0) and (math.floor(raw*10^decimals + 0.5)/10^decimals) or math.floor(raw + 0.5)
        apply(v)
    end
    track(track_.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true upd(i.Position.X) end end))
    track(UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 and dragging then dragging = false saveSettings() end end))
    track(UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then upd(i.Position.X) end end))
    -- typed input: clamp to range, revert if invalid
    track(val.FocusLost:Connect(function()
        local num = tonumber((tostring(val.Text):gsub("[^%d%.%-]", "")))
        if num then apply(math.clamp(num, mn, mx)) else val.Text = fmt(cur) end
        saveSettings()
    end))
    return f
end
local function actionRow(parent, name, desc, cb)
    local f = card(parent); padAll(f, 12, 12, 10, 10)
    textBlock(f, name, desc, 50)
    -- round button (a clean circle, no arrow)
    local btn = Instance.new("Frame"); btn.AnchorPoint = Vector2.new(1,0.5); btn.Position = UDim2.new(1,0,0.5,0); btn.Size = UDim2.fromOffset(30,30)
    btn.BackgroundColor3 = C.accentDim; btn.Parent = f; corner(btn,15)
    local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0.5,0.5); dot.Position = UDim2.fromScale(0.5,0.5); dot.Size = UDim2.fromOffset(9,9)
    dot.BackgroundColor3 = C.white; dot.BorderSizePixel = 0; dot.Parent = btn; corner(dot,5)
    -- the whole card is the click target
    local cover = Instance.new("TextButton"); cover.Size = UDim2.fromScale(1,1); cover.BackgroundTransparency = 1; cover.Text = ""; cover.AutoButtonColor = false; cover.ZIndex = 4; cover.Parent = f
    local function hov(on)
        TweenService:Create(f, TweenInfo.new(0.12), { BackgroundColor3 = on and C.cardHi or C.card }):Play()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = on and C.accent or C.accentDim }):Play()
    end
    track(cover.MouseEnter:Connect(function() hov(true) end))
    track(cover.MouseLeave:Connect(function() hov(false) end))
    track(cover.MouseButton1Click:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), { Size = UDim2.fromOffset(25,25) }):Play()
        task.delay(0.1, function() TweenService:Create(btn, TweenInfo.new(0.1), { Size = UDim2.fromOffset(30,30) }):Play() end)
        if cb then task.spawn(cb) end
    end))
    return cover
end
-- dropdown row: label+desc + trigger; list expands below as its own card
local function dropdownRow(parent, name, desc, getOptions, selectedSet, getStockFn, maxSelectFn, priceFn)
    local f = card(parent); padAll(f, 12, 12, 10, 10)
    textBlock(f, name, desc, 152)
    local trig = Instance.new("TextButton"); trig.AnchorPoint = Vector2.new(1,0); trig.Position = UDim2.new(1,0,0,2); trig.Size = UDim2.fromOffset(138,30)
    trig.AutoButtonColor = false; trig.BackgroundColor3 = C.inset; trig.Text = ""; trig.Parent = f; corner(trig,8); stroke(trig, C.stroke,1)
    local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.RichText = true; tl.Position = UDim2.fromOffset(10,0); tl.Size = UDim2.new(1,-26,1,0)
    tl.Font = FM; tl.TextSize = 11; tl.TextColor3 = C.text; tl.TextXAlignment = Enum.TextXAlignment.Left; tl.TextTruncate = Enum.TextTruncate.AtEnd; tl.Parent = trig
    local ar = Instance.new("TextLabel"); ar.BackgroundTransparency = 1; ar.AnchorPoint = Vector2.new(1,0.5); ar.Position = UDim2.new(1,-8,0.5,0)
    ar.Size = UDim2.fromOffset(12,12); ar.Font = FB; ar.Text = "v"; ar.TextSize = 11; ar.TextColor3 = C.sub; ar.Parent = trig

    local list = Instance.new("Frame"); list.Size = UDim2.new(1,0,0,0); list.AutomaticSize = Enum.AutomaticSize.Y; list.BackgroundColor3 = C.inset
    list.Visible = false; list.LayoutOrder = nextOrder(parent); list.Parent = parent; corner(list,8); stroke(list, C.stroke,1)
    local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,2); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list
    padAll(list, 6)

    local function count() local n = 0 for _ in pairs(selectedSet) do n = n + 1 end return n end
    local function updateTrig()
        local n = count()
        if maxSelectFn then
            local mx = maxSelectFn()
            tl.Text = (n >= mx) and '<font color="rgb(232,96,114)">MAX</font>' or (n == 0 and ("0/"..mx) or (n.."/"..mx))
        elseif n == 0 then
            tl.Text = "Any"
        else
            local names = {}; for k in pairs(selectedSet) do names[#names + 1] = k end; table.sort(names)
            tl.Text = table.concat(names, ", ")
        end
    end
    -- "Select All / Clear" pill pinned to the top of the open list
    local selAll = Instance.new("TextButton"); selAll.Size = UDim2.new(1,0,0,28); selAll.BackgroundColor3 = C.inset; selAll.AutoButtonColor = false
    selAll.Font = FB; selAll.TextSize = 11; selAll.TextColor3 = C.accentText; selAll.Text = "SELECT ALL"; selAll.LayoutOrder = -1; selAll.Parent = list; corner(selAll,7); stroke(selAll, C.stroke,1)
    local rowRefs = {}
    local function makeRow(nm, order)
        local r = Instance.new("TextButton"); r.Size = UDim2.new(1,0,0,30); r.BackgroundColor3 = C.card; r.Text = ""; r.AutoButtonColor = false
        r.LayoutOrder = order; r.Parent = list; corner(r,8)
        local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.RichText = true; lbl.Position = UDim2.fromOffset(12,0)
        lbl.Size = UDim2.new(1, getStockFn and -64 or -22, 1, 0); lbl.Font = FM; lbl.TextSize = 12; lbl.TextColor3 = C.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Parent = r
        local st
        if getStockFn then st = Instance.new("TextLabel"); st.BackgroundTransparency = 1; st.AnchorPoint = Vector2.new(1,0.5); st.Position = UDim2.new(1,-12,0.5,0); st.Size = UDim2.fromOffset(48,16); st.Font = FB; st.TextSize = 11; st.TextColor3 = C.sub; st.TextXAlignment = Enum.TextXAlignment.Right; st.Parent = r end
        local function label(on)
            local t = nm
            if priceFn then local p = priceFn(nm); if p and p ~= "" then t = t .. '  <font color="rgb('..(on and "255,205,222" or "120,220,150")..')">' .. p .. '</font>' end end
            return t
        end
        local function paint()
            local on = selectedSet[nm] == true
            TweenService:Create(r, TweenInfo.new(0.12), { BackgroundColor3 = on and C.rowOn or C.card }):Play()
            lbl.TextColor3 = on and C.white or C.text; lbl.Text = label(on)
        end
        paint()
        track(r.MouseEnter:Connect(function() if not selectedSet[nm] then TweenService:Create(r, TweenInfo.new(0.1), { BackgroundColor3 = C.cardHi }):Play() end end))
        track(r.MouseLeave:Connect(function() if not selectedSet[nm] then TweenService:Create(r, TweenInfo.new(0.1), { BackgroundColor3 = C.card }):Play() end end))
        track(r.MouseButton1Click:Connect(function()
            if selectedSet[nm] then selectedSet[nm] = nil
            elseif (not maxSelectFn) or count() < maxSelectFn() then selectedSet[nm] = true end
            paint(); updateTrig(); saveSettings()
        end))
        rowRefs[nm] = { st = st, paint = paint }
    end
    local lastSig = ""
    local function rebuild()
        local names = getOptions(); local sig = table.concat(names, ",")
        if sig == lastSig then return end
        lastSig = sig
        for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") and c ~= selAll then c:Destroy() end end
        rowRefs = {}
        for i, nm in ipairs(names) do makeRow(nm, i) end
        updateTrig()
    end
    local function repaintAll() for _, ref in pairs(rowRefs) do if ref.paint then ref.paint() end end end
    local function selectAll(v)
        if v and maxSelectFn then
            local mx, n = maxSelectFn(), count()
            for _, nm in ipairs(getOptions()) do if n >= mx then break end if not selectedSet[nm] then selectedSet[nm] = true; n = n + 1 end end
        else
            for _, nm in ipairs(getOptions()) do selectedSet[nm] = v or nil end
        end
        repaintAll(); updateTrig(); saveSettings()
    end
    track(selAll.MouseButton1Click:Connect(function()
        local allOn = count() >= #getOptions() and #getOptions() > 0
        selectAll(not allOn); selAll.Text = allOn and "SELECT ALL" or "CLEAR ALL"
    end))
    local expanded = false
    track(trig.MouseButton1Click:Connect(function()
        expanded = not expanded; list.Visible = expanded; ar.Text = expanded and "^" or "v"
        if expanded then rebuild() end
    end))
    updateTrig(); rebuild()
    spawnLoop(4, function()
        if not parent.Parent or not parent.Parent.Visible then return end
        rebuild()
        if getStockFn then for nm, ref in pairs(rowRefs) do if ref.st then local s = getStockFn(nm) ref.st.Text = s > 0 and (s.."x") or "-" ref.st.TextColor3 = s > 0 and C.green or C.sub end end end
    end)
    return { selectAll = selectAll }
end
-- text input row (e.g. webhook URL)
local function inputRow(parent, name, desc, default, placeholder, onSet)
    local f = card(parent); padAll(f, 12, 12, 10, 11); vlist(f, 6)
    local n = Instance.new("TextLabel"); n.Size = UDim2.new(1,0,0,16); n.BackgroundTransparency = 1; n.Font = FM; n.Text = name; n.TextSize = 13; n.TextColor3 = C.text; n.TextXAlignment = Enum.TextXAlignment.Left; n.LayoutOrder = 1; n.Parent = f
    if desc then local d = Instance.new("TextLabel"); d.Size = UDim2.new(1,0,0,0); d.AutomaticSize = Enum.AutomaticSize.Y; d.BackgroundTransparency = 1; d.Font = FR; d.Text = desc; d.TextSize = 11; d.TextColor3 = C.sub; d.TextWrapped = true; d.TextXAlignment = Enum.TextXAlignment.Left; d.LayoutOrder = 2; d.Parent = f end
    local box = Instance.new("Frame"); box.Size = UDim2.new(1,0,0,30); box.BackgroundColor3 = C.inset; box.LayoutOrder = 3; box.Parent = f; corner(box,7); stroke(box, C.stroke,1)
    local tb = Instance.new("TextBox"); tb.Size = UDim2.new(1,-16,1,0); tb.Position = UDim2.fromOffset(8,0); tb.BackgroundTransparency = 1; tb.Font = FR; tb.TextSize = 12; tb.TextColor3 = C.text
    tb.PlaceholderText = placeholder or ""; tb.PlaceholderColor3 = C.sub; tb.Text = default or ""; tb.ClearTextOnFocus = false; tb.TextXAlignment = Enum.TextXAlignment.Left; tb.TextTruncate = Enum.TextTruncate.AtEnd; tb.Parent = box
    track(tb.FocusLost:Connect(function() if onSet then onSet(tb.Text) end saveSettings() end))
    return tb
end
-- single-select dropdown (radio style) for things like Plant Pattern / Plant Source
local function choiceRow(parent, name, desc, getOptions, getSel, onPick)
    local f = card(parent); padAll(f, 12, 12, 10, 10)
    textBlock(f, name, desc, 152)
    local trig = Instance.new("TextButton"); trig.AnchorPoint = Vector2.new(1,0); trig.Position = UDim2.new(1,0,0,2); trig.Size = UDim2.fromOffset(138,30)
    trig.AutoButtonColor = false; trig.BackgroundColor3 = C.inset; trig.Text = ""; trig.Parent = f; corner(trig,8); stroke(trig, C.stroke,1)
    local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Position = UDim2.fromOffset(10,0); tl.Size = UDim2.new(1,-26,1,0); tl.Font = FM; tl.TextSize = 11; tl.TextColor3 = C.text; tl.TextXAlignment = Enum.TextXAlignment.Left; tl.TextTruncate = Enum.TextTruncate.AtEnd; tl.Parent = trig
    local ar = Instance.new("TextLabel"); ar.BackgroundTransparency = 1; ar.AnchorPoint = Vector2.new(1,0.5); ar.Position = UDim2.new(1,-8,0.5,0); ar.Size = UDim2.fromOffset(12,12); ar.Font = FB; ar.Text = "v"; ar.TextSize = 11; ar.TextColor3 = C.sub; ar.Parent = trig
    local list = Instance.new("Frame"); list.Size = UDim2.new(1,0,0,0); list.AutomaticSize = Enum.AutomaticSize.Y; list.BackgroundColor3 = C.inset; list.Visible = false; list.LayoutOrder = nextOrder(parent); list.Parent = parent; corner(list,8); stroke(list, C.stroke,1)
    local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,2); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list; padAll(list, 6)
    local function refresh() tl.Text = tostring(getSel() or "—") end
    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        for i, opt in ipairs(getOptions()) do
            local sel = (getSel() == opt)
            local r = Instance.new("TextButton"); r.Size = UDim2.new(1,0,0,30); r.BackgroundColor3 = sel and C.rowOn or C.card; r.Text = ""; r.AutoButtonColor = false; r.LayoutOrder = i; r.Parent = list; corner(r,8)
            local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.Position = UDim2.fromOffset(12,0); lbl.Size = UDim2.new(1,-22,1,0); lbl.Font = FM; lbl.TextSize = 12; lbl.TextColor3 = sel and C.white or C.text; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = opt; lbl.Parent = r
            track(r.MouseButton1Click:Connect(function() onPick(opt); refresh(); list.Visible = false; ar.Text = "v"; saveSettings() end))
            track(r.MouseEnter:Connect(function() if getSel() ~= opt then TweenService:Create(r, TweenInfo.new(0.1), { BackgroundColor3 = C.cardHi }):Play() end end))
            track(r.MouseLeave:Connect(function() if getSel() ~= opt then TweenService:Create(r, TweenInfo.new(0.1), { BackgroundColor3 = C.card }):Play() end end))
        end
    end
    local expanded = false
    track(trig.MouseButton1Click:Connect(function() expanded = not expanded; list.Visible = expanded; ar.Text = expanded and "^" or "v"; if expanded then rebuild() end end))
    refresh()
    spawnLoop(3, function() if not (parent.Parent and parent.Parent.Visible) then return end if list.Visible then rebuild() end refresh() end)
    return { refresh = refresh }
end

--========================= WINDOW CHROME =========================--
do
    local dragging, di, dp
    track(Top.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true di = i.Position dp = Main.Position end end))
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - di; Main.Position = UDim2.new(dp.X.Scale, dp.X.Offset + d.X, dp.Y.Scale, dp.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end))
end
local minimized = false
track(MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized; Body.Visible = not minimized; Status.Visible = not minimized
    if MinPlusBar then MinPlusBar.Visible = minimized end  -- "-" becomes "+" when minimized
    TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = minimized and UDim2.fromOffset(1020,42) or UDim2.fromOffset(1020,700) }):Play()
end))
local maximized = false
track(MaxBtn.MouseButton1Click:Connect(function()
    maximized = not maximized
    TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = maximized and UDim2.fromOffset(1160,800) or UDim2.fromOffset(1020,700) }):Play()
end))

--========================== UNLOAD ================================--
function Hub.unload()
    if not Hub.running then return end
    saveSettings()  -- persist current settings before we tear everything down
    Hub.running = false
    for _, c in ipairs(Hub.conns) do pcall(function() c:Disconnect() end) end
    Hub.conns = {}
    if Hub.stopFly then pcall(Hub.stopFly) end
    local h = humanoid(); if h then h.WalkSpeed = 16; h.UseJumpPower = true; h.JumpPower = 50; h.PlatformStand = false end
    local c = char(); if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end end end
    for k, v in pairs(S) do if type(v) == "boolean" then S[k] = false end end
    pcall(function() ScreenGui:Destroy() end)
    print("[360's GAG] unloaded.")
end
genv.GAG360_unload = Hub.unload
genv.GAG360_notify = function(msg, title, col) notify(msg, title, col) end  -- external trigger for the toast
track(CloseBtn.MouseButton1Click:Connect(function() Hub.unload() end))
track(UserInputService.InputBegan:Connect(function(i, gpe) if not gpe and i.KeyCode == Enum.KeyCode.RightShift then Main.Visible = not Main.Visible end end))

--========================== FEATURE LOOPS =========================--
-- The actual plantable soil is the CollectionService "PlantArea" parts (two ~44x50
-- columns, centred ~12 studs off the PlotSizeReference centre). Grid over those, not a
-- guessed rectangle, so planting covers the WHOLE garden. Patterns sub-select cells.
local PLANT_PATTERNS = { "Fill", "Checkerboard", "Rows", "Columns", "Diagonal", "Spaced" }
local function patternKeep(pat, gx, gz)
    if pat == "Checkerboard" then return (gx + gz) % 2 == 0
    elseif pat == "Rows" then return gz % 2 == 0
    elseif pat == "Columns" then return gx % 2 == 0
    elseif pat == "Diagonal" then return (gx - gz) % 3 == 0
    elseif pat == "Spaced" then return gx % 2 == 0 and gz % 2 == 0 end
    return true  -- Fill
end
local function plantAreas(plot)
    local areas = {}
    for _, p in ipairs(CollectionService:GetTagged("PlantArea")) do
        if p:IsA("BasePart") and p:IsDescendantOf(plot) and p.Size.X * p.Size.Z > 400 then areas[#areas + 1] = p end
    end
    if #areas == 0 then local ref = plot:FindFirstChild("PlotSizeReference"); if ref then areas = { ref } end end
    return areas
end
local function plantPositions(plot)
    local pat = S.plantPattern or "Fill"
    local step = 6
    local seen, list = {}, {}
    for _, area in ipairs(plantAreas(plot)) do
        local cf, sz = area.CFrame, area.Size
        local topY = area.Position.Y + sz.Y/2 + 0.3
        local hx, hz = sz.X/2 - 3, sz.Z/2 - 3
        local nx, nz = math.floor((2*hx)/step), math.floor((2*hz)/step)
        for ix = 0, nx do for iz = 0, nz do
            local w = (cf * CFrame.new(-hx + ix*step, 0, -hz + iz*step)).Position
            local gx, gz = math.floor(w.X/step + 0.5), math.floor(w.Z/step + 0.5)
            if patternKeep(pat, gx, gz) then
                local key = math.floor(w.X/4 + 0.5) .. "," .. math.floor(w.Z/4 + 0.5)
                if not seen[key] then seen[key] = true; list[#list + 1] = Vector3.new(w.X, topY, w.Z) end
            end
        end end
    end
    return list
end
local function freePlantPositions(plot)
    local grid = plantPositions(plot); local plants = plot:FindFirstChild("Plants"); local occ = {}
    if plants then for _, pl in ipairs(plants:GetChildren()) do local ok, pv = pcall(function() return pl:GetPivot().Position end) if ok then occ[#occ+1] = pv end end end
    local free = {}
    for _, pos in ipairs(grid) do
        local clear = true
        for _, o in ipairs(occ) do if (Vector3.new(o.X,0,o.Z) - Vector3.new(pos.X,0,pos.Z)).Magnitude < 6 then clear = false break end end
        if clear then free[#free+1] = pos end
    end
    return free
end

--======================= GARDEN SNAPSHOTS ========================--
-- Capture another player's garden (which seeds + how many, and its buildings) to a named
-- snapshot, then replant the same seeds/amounts (and optionally rebuild the layout) on yours.
local SNAP_FILE = "360_GAG_GAG2_Snapshots.json"
local Snapshots = {}
local function saveSnapshots() if writefile then pcall(function() writefile(SNAP_FILE, HttpService:JSONEncode(Snapshots)) end) end end
do
    if readfile and isfile then
        local ok, raw = pcall(function() return isfile(SNAP_FILE) and readfile(SNAP_FILE) or nil end)
        if ok and raw then local g, d = pcall(function() return HttpService:JSONDecode(raw) end) if g and type(d) == "table" then Snapshots = d end end
    end
end
local function snapshotNames()
    local list = {} for n in pairs(Snapshots) do list[#list + 1] = n end table.sort(list); return list
end
-- the garden the player is standing in / nearest to
local function gardenNearPlayer()
    local g = Workspace:FindFirstChild("Gardens"); local r = hrp(); if not (g and r) then return nil end
    local best, bestD
    for _, plot in ipairs(g:GetChildren()) do
        local ref = plot:FindFirstChild("PlotSizeReference")
        if ref then local d = (Vector3.new(ref.Position.X,0,ref.Position.Z) - Vector3.new(r.Position.X,0,r.Position.Z)).Magnitude
            if not bestD or d < bestD then best, bestD = plot, d end end
    end
    return best
end
-- the building folders a plot can hold (placed props/sprinklers/pots/gnomes)
local BUILD_FOLDERS = { "Props", "Sprinklers", "Gnomes", "PottedPlants", "Pots", "Objects", "Decor" }
local function captureSnapshot(name)
    local plot = gardenNearPlayer(); if not plot then return false, "no garden nearby" end
    local ref = plot:FindFirstChild("PlotSizeReference"); local center = ref and ref.Position or Vector3.zero
    local snap = { seeds = {}, buildings = {}, owner = plot:GetAttribute("OwnerUserId") }
    -- plants -> seed counts
    local plants = plot:FindFirstChild("Plants")
    if plants then for _, pl in ipairs(plants:GetChildren()) do
        local s = pl:GetAttribute("SeedName") or pl:GetAttribute("CorePartName")
        if s then snap.seeds[s] = (snap.seeds[s] or 0) + 1 end
    end end
    -- buildings -> type + position relative to plot centre (best-effort; folders vary)
    for _, fname in ipairs(BUILD_FOLDERS) do
        local f = plot:FindFirstChild(fname)
        if f then for _, b in ipairs(f:GetChildren()) do
            local ok, piv = pcall(function() return b:GetPivot().Position end)
            if ok then
                local kind = b:GetAttribute("PropName") or b:GetAttribute("ItemName") or b:GetAttribute("Name") or b:GetAttribute("Type") or b.Name
                snap.buildings[#snap.buildings + 1] = { kind = tostring(kind), folder = fname,
                    rx = piv.X - center.X, ry = piv.Y - center.Y, rz = piv.Z - center.Z,
                    rot = (select(2, (b:GetPivot()):ToOrientation()) or 0) }
            end
        end end
    end
    Snapshots[name] = snap; saveSnapshots()
    local nSeeds = 0 for _ in pairs(snap.seeds) do nSeeds = nSeeds + 1 end
    return true, ("captured %d seed types, %d buildings"):format(nSeeds, #snap.buildings)
end

--====================== REMOVE / BUILD ===========================--
-- the shovel must be EQUIPPED and passed to UseShovel(plantId, fruitId, shovelAttr, shovelTool)
local function findShovel()
    local function scan(cont) if cont then for _, c in ipairs(cont:GetChildren()) do if c:IsA("Tool") and (c:GetAttribute("Shovel") ~= nil or c.Name:lower():find("shovel")) then return c end end end end
    return scan(char()) or scan(LocalPlayer:FindFirstChild("Backpack"))
end
local function equipShovel()
    local sh = findShovel(); if not sh then return nil end
    local h = humanoid()
    if h and sh.Parent ~= char() then pcall(function() h:EquipTool(sh) end); task.wait(0.3) end
    return sh
end
-- remove plants matching matchFn(cropName) (nil = remove everything)
local function removePlants(matchFn)
    local plot = myPlot(); if not plot then return 0 end
    local plants = plot:FindFirstChild("Plants"); if not plants then return 0 end
    local sh = equipShovel(); if not sh then setStatus("equip a shovel first"); return 0 end
    local sa = sh:GetAttribute("Shovel"); local n = 0; local lastPos
    for _, pl in ipairs(plants:GetChildren()) do
        local pid = pl:GetAttribute("PlantId")
        local crop = pl:GetAttribute("SeedName") or pl:GetAttribute("CorePartName")
        if pid and ((not matchFn) or matchFn(crop)) then
            local ok, pos = pcall(function() return pl:GetPivot().Position end)
            if ok and (not lastPos or (pos - lastPos).Magnitude > 10) then reach(pos); lastPos = pos end
            pcall(function() Net.Shovel.UseShovel:Fire(pid, "", sa, sh) end)
            n = n + 1; task.wait(0.05)
        end
    end
    return n
end
local function removeAllPlants() return removePlants(nil) end
local function removeSelectedPlants() return removePlants(function(crop) return crop and S.removeCrops[crop] == true end) end
local function removeAllBuildings()
    local plot = myPlot(); if not plot then return 0 end
    local n = 0
    for _, fname in ipairs(BUILD_FOLDERS) do
        local f = plot:FindFirstChild(fname)
        if f then for _, b in ipairs(f:GetChildren()) do
            pcall(function()
                if Net.Prop and Net.Prop.PickupProp then Net.Prop.PickupProp:Fire(b) end
                if Net.PotPlacement and Net.PotPlacement.PickUpPottedPlant then Net.PotPlacement.PickUpPottedPlant:Fire(b) end
                if fname == "Gnomes" and Net.Place and Net.Place.RemoveGnome then Net.Place.RemoveGnome:Fire(b) end
            end)
            n = n + 1; task.wait(0.06)
        end end
    end
    return n
end

spawnLoop(2, function()
    if not S.autoBuySeed then return end
    local it = seedStockItems(); if not it then return end
    local anySel = next(S.buySeeds) ~= nil  -- nothing picked = buy everything in stock
    for _, sv in ipairs(it:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 and ((not anySel) or S.buySeeds[sv.Name] == true) then
            if getSheckles() >= (SeedPrice[sv.Name] or 0) then fire(Net.SeedShop.PurchaseSeed, sv.Name); task.wait(0.08) end
        end
    end
end)

spawnLoop(0.6, function()
    if not S.autoPlant then return end
    task.wait(math.max(0, S.plantLoop - 0.6))
    if not S.autoPlant then return end
    local plot = myPlot(); if not plot then return end
    local d = getData(); local seeds = d and d.Inventory and d.Inventory.Seeds; if not seeds then return end
    local useFilter = next(S.plantSeeds) ~= nil
    local toPlant = {}
    local snap = (S.plantSource and S.plantSource ~= "My Seeds") and Snapshots[S.plantSource] or nil
    if snap then
        -- replant to match the snapshot's seed counts (capped by what you own)
        local have = {}
        local plf = plot:FindFirstChild("Plants")
        if plf then for _, pl in ipairs(plf:GetChildren()) do local s = pl:GetAttribute("SeedName") or pl:GetAttribute("CorePartName") if s then have[s] = (have[s] or 0) + 1 end end end
        for seed, target in pairs(snap.seeds) do
            local need = math.min((target or 0) - (have[seed] or 0), seeds[seed] or 0)
            for _ = 1, math.max(0, need) do toPlant[#toPlant + 1] = seed end
        end
    elseif S.smartReplant then
        local best = bestOwnedSeed()
        if best and ((not useFilter) or S.plantSeeds[best]) then
            local keep = S.plantReserve or 0
            for _ = 1, math.min(math.max(0, (seeds[best] or 0) - keep), 80) do toPlant[#toPlant + 1] = best end
        end
    else
        for name, count in pairs(seeds) do
            if (not useFilter) or S.plantSeeds[name] == true then
                local keep = S.plantReserve or 0
                for _ = 1, math.min(math.max(0, (count or 0) - keep), 40) do toPlant[#toPlant + 1] = name end
            end
        end
    end
    if #toPlant == 0 then return end
    local free = freePlantPositions(plot); if #free == 0 then return end
    local cap = math.min(#free, #toPlant, S.maxPerCycle); local planted = 0
    for i = 1, cap do
        fire(Net.Plant.PlantSeed, free[i], toPlant[i], plot); planted = planted + 1; task.wait(S.plantDelay)
    end
    if planted > 0 then setStatus("planted " .. planted) end
end)

-- auto-expand the garden (server gates on cost, so just fire when toggled)
spawnLoop(6, function()
    if not S.autoExpand then return end
    local plot = myPlot(); if not plot then return end
    local before = tonumber(plot:GetAttribute("GardenExpansion")) or 0
    fire(Net.Actions.ExpandGarden)
    task.wait(1)
    local after = tonumber(plot:GetAttribute("GardenExpansion")) or before
    if after > before then setStatus("garden expanded to size " .. after) end
end)

-- auto-build: recreate the selected snapshot's building layout on your plot (best-effort)
local function buildSnapshot()
    local snap = (S.plantSource and S.plantSource ~= "My Seeds") and Snapshots[S.plantSource] or nil
    if not (snap and snap.buildings and #snap.buildings > 0) then setStatus("pick a snapshot (with buildings) as the source") return 0 end
    local plot = myPlot(); if not plot then return 0 end
    local ref = plot:FindFirstChild("PlotSizeReference"); local center = ref and ref.Position or Vector3.zero
    local n = 0
    for _, b in ipairs(snap.buildings) do
        local pos = Vector3.new(center.X + (b.rx or 0), center.Y + (b.ry or 0), center.Z + (b.rz or 0))
        pcall(function() if Net.Prop and Net.Prop.PlaceProp then Net.Prop.PlaceProp:Fire(pos, b.kind, b.rot or 0, b.rot or 0) end end)
        n = n + 1; task.wait(0.15)
    end
    setStatus("auto-build: attempted " .. n .. " buildings")
    return n
end
spawnLoop(8, function()
    if not S.autoBuild then return end
    local snap = (S.plantSource and S.plantSource ~= "My Seeds") and Snapshots[S.plantSource] or nil
    if not (snap and snap.buildings and #snap.buildings > 0) then return end
    local plot = myPlot(); if not plot then return end
    local built = 0
    for _, fname in ipairs(BUILD_FOLDERS) do local f = plot:FindFirstChild(fname) if f then built = built + #f:GetChildren() end end
    if built < #snap.buildings then buildSnapshot() end
end)

spawnLoop(0.4, function()
    if not S.autoCollect then return end
    task.wait(math.max(0, S.harvestLoop - 0.4))
    if not S.autoCollect then return end
    local n = harvestAll(true)
    if n > 0 then setStatus("harvested " .. n) end
end)

spawnLoop(1, function()
    if S.sellOnFull then
        local fc = LocalPlayer:GetAttribute("FruitCount") or 0
        local mx = LocalPlayer:GetAttribute("MaxFruitCapacity") or 100
        if fc >= mx - 1 then fire(Net.NPCS.SellAll); setStatus("sold (backpack full)") end
    end
end)
do
    local acc = 0
    spawnLoop(1, function() acc = acc + 1 if S.autoSell and acc >= S.sellInterval then acc = 0 fire(Net.NPCS.SellAll) end end)
end

spawnLoop(0.8, function()
    if not S.autoSteal then return end
    if not isNight() then setStatus("steal: waiting for night") return end
    local home = hrp() and hrp().Position
    local t = stealTargets(); local n = 0; local lastPos
    for _, e in ipairs(t) do
        if not S.autoSteal or not isNight() then break end
        local m = e.model; local pos = (m and m.Parent) and m:GetPivot().Position or nil
        local skip = (lastPos and pos and (pos - lastPos).Magnitude <= 12) or false  -- same plant cluster -> don't re-teleport
        if pos and not skip then lastPos = pos end
        stealModel(m, S.stealMult, skip); n = n + 1
        setStatus(string.format("steal: %d/%d  (worth %d)", n, #t, math.floor(e.value))); task.wait(0.03)
    end
    if n > 0 then setStatus(("stole %d fruit this pass"):format(n)) end
    if S.stealReturn and home then reach(home - Vector3.new(0,3,0)) end
end)

-- event seeds: gold/rainbow seeds + seed packs randomly spawn around the map; you walk
-- to them and HOLD E (a server-added ProximityPrompt) to collect. We TP over + fire it.
local function packKind(loc)
    if loc:GetAttribute("GoldSeed") == true then return "Gold Seed" end
    if loc:GetAttribute("RainbowSeed") == true then return "Rainbow Seed" end
    if loc:GetAttribute("SeedPack") ~= nil then return tostring(loc:GetAttribute("SeedPack")) end
    return nil
end
local function isRarePack(loc)
    if loc:GetAttribute("GoldSeed") == true or loc:GetAttribute("RainbowSeed") == true then return true end
    local sp = loc:GetAttribute("SeedPack")
    return type(sp) == "string" and (sp:lower():find("gold") ~= nil or sp:lower():find("rainbow") ~= nil)
end
local function firePrompt(d)
    pcall(function()
        local hold = tonumber(d.HoldDuration) or 0
        if fireproximityprompt then
            if hold > 0 then fireproximityprompt(d, hold) else fireproximityprompt(d) end
        else
            d:InputHoldBegin(); task.wait(hold + 0.1); d:InputHoldEnd()
        end
    end)
end
local function packLocations()
    local map = Workspace:FindFirstChild("Map"); local f = map and map:FindFirstChild("SeedPackSpawnServerLocations")
    return f and f:GetChildren() or {}
end
-- hold every collect-prompt on / near a spawned seed (server adds the hold-E prompt)
local function holdSeedPrompts(pos)
    local map = Workspace:FindFirstChild("Map")
    for _, cont in ipairs({ map and map:FindFirstChild("SeedPackSpawnServerLocations"), map and map:FindFirstChild("SeedPackSpawnClient"), Workspace:FindFirstChild("Temporary") }) do
        if cont then for _, d in ipairs(cont:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local p = d.Parent; local ok, pp = pcall(function() return p.Position end)
                if (not ok) or (pp - pos).Magnitude <= 35 then firePrompt(d) end
            end
        end end
    end
end
local function locPart(loc) return loc:IsA("BasePart") and loc or loc:FindFirstChildWhichIsA("BasePart", true) end
local function locPos(loc)
    if loc:IsA("BasePart") then return loc.Position end
    local ok, cf = pcall(function() return loc:GetPivot() end); if ok then return cf.Position end
    local bp = locPart(loc); return bp and bp.Position or nil
end
-- stand on the seed and collect it: fire its hold-E prompt, any nearby prompt, AND touch it
local function grabPack(loc)
    local landed = false
    for _ = 1, 90 do
        if not (loc and loc.Parent) then break end
        local pos = locPos(loc); if not pos then break end
        local r = hrp()
        if (not landed) or (r and (r.Position - pos).Magnitude > 6) then reach(pos); landed = true end
        for _, d in ipairs(loc:GetDescendants()) do if d:IsA("ProximityPrompt") then firePrompt(d) end end  -- prompt on the seed itself
        holdSeedPrompts(pos)                                                                                   -- + any prompt nearby (client visual)
        local part = locPart(loc)
        if firetouchinterest and part and hrp() then pcall(function() firetouchinterest(hrp(), part, 0); firetouchinterest(hrp(), part, 1) end) end  -- touch-to-collect fallback
        task.wait(0.12)
    end
end
do
    local grabbing = {}
    spawnLoop(0.6, function()
        if not S.autoGrabPacks then return end
        for _, loc in ipairs(packLocations()) do
            if loc.Parent and not grabbing[loc] then
                local rare = isRarePack(loc)
                if S.notifyRare and rare then local k = packKind(loc) or "Rare seed"; setStatus("EVENT: " .. k .. " spawned!"); notify(k .. " spawned on the map - grabbing it now!", "✦ Rare Seed Spawned", C.accent) end
                if (not S.grabRareOnly) or rare then
                    grabbing[loc] = true
                    task.spawn(function() grabPack(loc); grabbing[loc] = nil end)
                end
            end
        end
    end)
end
do
    local wasNight = false
    spawnLoop(1, function()
        local n = isNight()
        if S.packReturn and S.autoGrabPacks and wasNight and not n then
            local plot = myPlot(); local sp = plot and plot:FindFirstChild("SpawnPoint")
            if sp then reach(sp.Position); setStatus("event over - returned to garden") end
        end
        wasNight = n
    end)
end

do
    local wasNight = false
    spawnLoop(0.5, function()
        local n = isNight()
        if S.panicHarvest and n and not wasNight then
            setStatus("defense: panic harvesting")
            harvestAll(false)
        end
        wasNight = n
    end)
end
spawnLoop(0.6, function()
    if not S.retaliate then return end
    local plot = myPlot(); local ref = plot and plot:FindFirstChild("PlotSizeReference"); if not ref then return end
    local center, size = ref.Position, ref.Size
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local r = pl.Character:FindFirstChild("HumanoidRootPart")
            if r and math.abs(r.Position.X - center.X) < size.X/2 + 4 and math.abs(r.Position.Z - center.Z) < size.Z/2 + 4 then fire(Net.Shovel.HitPlayer, pl.UserId) end
        end
    end
end)

spawnLoop(3, function()
    if not S.autoBuyCrate then return end
    local it = stockItems("CrateShop"); if not it then return end
    for _, sv in ipairs(it:GetChildren()) do if sv:IsA("ValueBase") and sv.Value > 0 then fire(Net.CrateShop.PurchaseCrate, sv.Name); task.wait(0.1) end end
end)
spawnLoop(3, function()
    if not S.autoBuyGear then return end
    local it = gearStockItems(); if not it then return end
    local anySel = next(S.buyGears) ~= nil
    for _, sv in ipairs(it:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 and ((not anySel) or S.buyGears[sv.Name] == true) then fire(Net.GearShop.PurchaseGear, sv.Name); task.wait(0.1) end
    end
end)

local function openAll(invKey, pkt, flag)
    spawnLoop(2.5, function()
        if not S[flag] then return end
        local d = getData(); local bag = d and d.Inventory and d.Inventory[invKey]; if not bag then return end
        for name, count in pairs(bag) do local n = (type(count) == "number") and count or 1 for _ = 1, n do task.spawn(function() fire(pkt, name) end) task.wait(0.15) end end
    end)
end
openAll("Eggs", Net.Egg.OpenEgg, "autoEggs")
openAll("Crates", Net.Crate.OpenCrate, "autoCrates")
openAll("SeedPacks", Net.SeedPack.OpenSeedPack, "autoPacks")

spawnLoop(1.2, function()
    if not S.autoTame then return end
    local map = Workspace:FindFirstChild("Map"); local refs = map and map:FindFirstChild("WildPetRef"); if not refs then return end
    local anySel = next(S.tameAnimals) ~= nil
    for _, pet in ipairs(refs:GetChildren()) do
        if not S.autoTame then break end
        local owner = tonumber(pet:GetAttribute("OwnerUserId")) or 0
        local species = pet:GetAttribute("PetName")
        if ((not anySel) or (species and S.tameAnimals[species] == true)) and (owner == 0 or owner == LocalPlayer.UserId) and pet:IsA("BasePart") then
            reach(pet.Position); setStatus("taming " .. tostring(species))
            for _ = 1, 6 do if not S.autoTame then break end pcall(function() Net.Pets.WildPetTame:Fire(pet) end) task.wait(0.08) end
        end
    end
end)
-- AUTO PROGRESS: hands-off progression. Harvest -> sell -> buy the best seeds you can
-- afford -> plant them everywhere -> tame valuable pets when they spawn. Snowballs coins.
local GOOD_PETS = {
    Raccoon = true, Dragonfly = true, ["Dragon Fly"] = true, Dragonling = true, Mimic = true,
    ["Disco Bee"] = true, ["Queen Bee"] = true, Kitsune = true, ["Red Fox"] = true, Fox = true,
    Owl = true, ["Night Owl"] = true, Bear = true, ["Polar Bear"] = true, Butterfly = true,
    ["Golden Lab"] = true, Cat = true, ["Red Giant Ant"] = true, Snail = true,
}
local function progressBuy()
    local it = seedStockItems(); if not it then return end
    local money = getSheckles(); local best, bestV
    for _, sv in ipairs(it:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 then
            local price, val = SeedPrice[sv.Name] or math.huge, SeedBaseValue[sv.Name] or 0
            if price <= money * 0.5 and (not bestV or val > bestV) then best, bestV = sv.Name, val end
        end
    end
    if best then for _ = 1, 6 do if getSheckles() < (SeedPrice[best] or 0) then break end fire(Net.SeedShop.PurchaseSeed, best); task.wait(0.1) end end
    return best
end
local function progressPlant()
    local plot = myPlot(); if not plot then return 0 end
    local d = getData(); local seeds = d and d.Inventory and d.Inventory.Seeds; if not seeds then return 0 end
    local toPlant = {}
    for name, count in pairs(seeds) do for _ = 1, math.min(count or 0, 30) do toPlant[#toPlant + 1] = name end end
    if #toPlant == 0 then return 0 end
    local free = freePlantPositions(plot); local cap = math.min(#free, #toPlant); local n = 0
    for i = 1, cap do fire(Net.Plant.PlantSeed, free[i], toPlant[i], plot); n = n + 1; task.wait(0.08) end
    return n
end
spawnLoop(4, function()
    if not S.autoProgress then return end
    local h = harvestAll(false)
    if (LocalPlayer:GetAttribute("FruitCount") or 0) > 0 then fire(Net.NPCS.SellAll); task.wait(0.2) end
    progressBuy()
    local p = progressPlant()
    setStatus(("auto progress: +%d harvest, +%d plant, %s"):format(h, p, money(getSheckles())))
end)
spawnLoop(1.5, function()
    if not S.autoProgress then return end
    local map = Workspace:FindFirstChild("Map"); local refs = map and map:FindFirstChild("WildPetRef"); if not refs then return end
    for _, pet in ipairs(refs:GetChildren()) do
        if not S.autoProgress then break end
        local species = pet:GetAttribute("PetName"); local owner = tonumber(pet:GetAttribute("OwnerUserId")) or 0
        if species and GOOD_PETS[species] and (owner == 0 or owner == LocalPlayer.UserId) and pet:IsA("BasePart") then
            reach(pet.Position); setStatus("auto progress: taming " .. species)
            for _ = 1, 6 do if not S.autoProgress then break end pcall(function() Net.Pets.WildPetTame:Fire(pet) end) task.wait(0.08) end
        end
    end
end)
spawnLoop(5, function()
    if not S.autoEquipPets then return end
    local n, mx = 0, maxEquip()
    for name in pairs(S.equipPets) do if n >= mx then break end fire(Net.Pets.RequestEquipByName, tostring(name)); n = n + 1; task.wait(0.15) end
end)

-- fly + movement
local flyBV, flyBG
local function stopFly()
    if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
    local h = humanoid(); if h then h.PlatformStand = false end
end
Hub.stopFly = stopFly
local function startFly()
    local r = hrp(); if not r then return end
    stopFly()
    flyBV = Instance.new("BodyVelocity"); flyBV.MaxForce = Vector3.new(1,1,1)*9e9; flyBV.Velocity = Vector3.zero; flyBV.Parent = r
    flyBG = Instance.new("BodyGyro"); flyBG.MaxTorque = Vector3.new(1,1,1)*9e9; flyBG.P = 1e5; flyBG.CFrame = r.CFrame; flyBG.Parent = r
end
track(RunService.Heartbeat:Connect(function()
    if not Hub.running then return end
    local h = humanoid()
    if h then
        if S.walkSpeed ~= 16 then h.WalkSpeed = S.walkSpeed end
        if S.jumpPower ~= 50 then h.UseJumpPower = true; h.JumpPower = S.jumpPower end
    end
    if S.noclip then local c = char() if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end end end end
    if S.fly then
        local r = hrp(); local cam = Workspace.CurrentCamera
        if r and cam then
            if not flyBV then startFly() end
            if h then h.PlatformStand = true end
            local d = Vector3.zero
            local function k(c) return UserInputService:IsKeyDown(c) end
            if k(Enum.KeyCode.W) then d = d + cam.CFrame.LookVector end
            if k(Enum.KeyCode.S) then d = d - cam.CFrame.LookVector end
            if k(Enum.KeyCode.D) then d = d + cam.CFrame.RightVector end
            if k(Enum.KeyCode.A) then d = d - cam.CFrame.RightVector end
            if k(Enum.KeyCode.Space) then d = d + Vector3.new(0,1,0) end
            if k(Enum.KeyCode.LeftControl) then d = d - Vector3.new(0,1,0) end
            if flyBV then flyBV.Velocity = (d.Magnitude > 0 and d.Unit or Vector3.zero) * S.flySpeed end
            if flyBG then flyBG.CFrame = cam.CFrame end
        end
    elseif flyBV then stopFly() end
end))
track(UserInputService.JumpRequest:Connect(function() if S.infJump then local h = humanoid() if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end end))

-- anti-afk: VirtualUser click on the Idled signal (fires just before the 20-min
-- idle kick). Non-disruptive - only acts when you are actually idle.
do
    local VU = game:GetService("VirtualUser")
    track(LocalPlayer.Idled:Connect(function()
        if not S.antiAfk then return end
        pcall(function()
            VU:CaptureController()
            VU:ClickButton2(Vector2.new())
        end)
    end))
end

-- webhook + server hopper
local HttpService = game:GetService("HttpService")
local TPS = game:GetService("TeleportService")
local httpRequest = (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request) or (typeof(request) == "function" and request) or http_request
local function sendWebhook(content)
    if not (S.webhookUrl and S.webhookUrl ~= "" and httpRequest) then return false end
    task.spawn(function()
        pcall(function()
            httpRequest({ Url = S.webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({ username = "360's GAG", content = content }) })
        end)
    end)
    return true
end
local function fetchServers()
    local ok, res = pcall(function()
        local raw = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        return HttpService:JSONDecode(raw)
    end)
    return (ok and res and res.data) or {}
end
local function serverHop(lowPop)
    setStatus("finding a server...")
    local servers = fetchServers(); local pick
    for _, s in ipairs(servers) do
        if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
            if lowPop then if not pick or s.playing < pick.playing then pick = s end
            else pick = s; break end
        end
    end
    if pick then setStatus("hopping (" .. pick.playing .. " players)..."); pcall(function() TPS:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer) end)
    else setStatus("no server found - retrying may help") end
end
local function rareSeedInStock()
    local it = seedStockItems(); if not it then return false end
    for _, sv in ipairs(it:GetChildren()) do if sv:IsA("ValueBase") and sv.Value > 0 and (SeedPrice[sv.Name] or 0) >= 5000 then return true, sv.Name end end
    return false
end
-- hop between servers until a rare seed is in stock
spawnLoop(20, function()
    if not S.autoHopRare then return end
    if not rareSeedInStock() then serverHop(false) end
end)

-- profit tracker (net sheckles, rolling 60s rate)
local Profit = { startS = nil, session = 0, perMin = 0, perHr = 0, win = {} }
spawnLoop(2, function()
    local s = getSheckles()
    if Profit.startS == nil then Profit.startS = s end
    Profit.session = s - Profit.startS
    table.insert(Profit.win, { t = os.clock(), s = s })
    while #Profit.win > 1 and (os.clock() - Profit.win[1].t) > 60 do table.remove(Profit.win, 1) end
    local f = Profit.win[1]; local dt = os.clock() - f.t
    if dt > 4 then Profit.perMin = (s - f.s)/dt*60; Profit.perHr = Profit.perMin*60 end
end)

-- highlight ESP (own ready crops + mutated fruit, distance-capped)
local hlFolder = Instance.new("Folder"); hlFolder.Name = "GAG_HL"; hlFolder.Parent = ScreenGui
local function clearHL() for _, h in ipairs(hlFolder:GetChildren()) do h:Destroy() end end
local function addHL(model, col)
    if not model or not model.Parent then return end
    local h = Instance.new("Highlight"); h.Adornee = model; h.FillColor = col; h.FillTransparency = 0.55
    h.OutlineColor = col; h.OutlineTransparency = 0; h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; h.Parent = hlFolder
end
spawnLoop(1, function()
    if not (S.highlightReady or S.highlightRare) then if #hlFolder:GetChildren() > 0 then clearHL() end return end
    clearHL()
    local root = hrp(); local rp = root and root.Position
    if S.highlightReady then for _, m in ipairs(ownHarvestTargets()) do addHL(m, C.accent) end end
    if S.highlightRare and rp then
        local count = 0
        for _, p in ipairs(CollectionService:GetTagged("StealPrompt")) do
            if count >= 50 then break end
            local m = p.Parent and p.Parent:FindFirstAncestorWhichIsA("Model")
            if m and m:GetAttribute("Mutation") then
                local ok, piv = pcall(function() return m:GetPivot().Position end)
                if ok and (piv - rp).Magnitude < 220 then addHL(m, Color3.fromRGB(255,205,70)); count = count + 1 end
            end
        end
    end
end)
table.insert(Hub.conns, { Disconnect = function() pcall(clearHL) pcall(function() hlFolder:Destroy() end) end })

-- rare seed restock notifier (fires once when an expensive seed appears in stock)
do
    local prev = {}
    spawnLoop(3, function()
        if not S.rareNotify then return end
        local it = seedStockItems(); if not it then return end
        for _, sv in ipairs(it:GetChildren()) do
            if sv:IsA("ValueBase") then
                local now = sv.Value > 0
                if now and not prev[sv.Name] and (SeedPrice[sv.Name] or 0) >= 5000 then
                    setStatus("RARE SEED IN STOCK: " .. sv.Name); notify(sv.Name .. " just restocked - " .. sv.Value .. "x available (" .. fmtPrice(SeedPrice[sv.Name]) .. ")", "✦ Rare Seed In Stock", C.green)
                    if S.whRareSeed then sendWebhook("**Rare seed in stock:** " .. sv.Name .. " (" .. sv.Value .. "x)  -  " .. LocalPlayer.Name) end
                end
                prev[sv.Name] = now
            end
        end
    end)
end

-- performance optimizer: flat textures, grey sky, no effects (FPS boost)
local Lighting = game:GetService("Lighting")
local optConns, optOrig
local function optimizeInstance(o)
    pcall(function()
        if o:IsA("BasePart") then
            o.Material = Enum.Material.SmoothPlastic; o.Reflectance = 0; o.CastShadow = false
        elseif o:IsA("Decal") or o:IsA("Texture") then
            o.Transparency = 1
        elseif o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") or o:IsA("Smoke") or o:IsA("Fire") or o:IsA("Sparkles") then
            o.Enabled = false
        elseif o:IsA("PostEffect") then
            o.Enabled = false
        end
    end)
end
local function setOptimize(on)
    if on then
        optOrig = optOrig or { gs = Lighting.GlobalShadows, fc = Lighting.FogColor, fs = Lighting.FogStart, fe = Lighting.FogEnd, br = Lighting.Brightness, oa = Lighting.OutdoorAmbient, am = Lighting.Ambient }
        pcall(function()
            Lighting.GlobalShadows = false
            Lighting.FogColor = Color3.fromRGB(131,133,139); Lighting.FogStart = 220; Lighting.FogEnd = 780  -- grey sky via fog
            Lighting.OutdoorAmbient = Color3.fromRGB(140,140,146); Lighting.Ambient = Color3.fromRGB(122,122,128)  -- neutralise colour tint
        end)
        for _, e in ipairs(Lighting:GetDescendants()) do
            if e:IsA("Atmosphere") or e:IsA("Clouds") or e:IsA("PostEffect") then pcall(function() e.Enabled = false end) end
            if e:IsA("Sky") then pcall(function() e.CelestialBodiesShown = false end) end
        end
        pcall(function() Workspace.Terrain.Decoration = false end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        for _, o in ipairs(Workspace:GetDescendants()) do optimizeInstance(o) end
        -- keep optimizing ANYTHING that streams in later (new plants, players, effects, etc.)
        if optConns then for _, c in ipairs(optConns) do pcall(function() c:Disconnect() end) end end
        local function onAdd(o) if S.optimize then task.defer(optimizeInstance, o) end end
        optConns = { Workspace.DescendantAdded:Connect(onAdd), Lighting.DescendantAdded:Connect(onAdd) }
        for _, c in ipairs(optConns) do track(c) end
        setStatus("optimized - flat textures, grey sky, effects off")
    else
        if optConns then for _, c in ipairs(optConns) do pcall(function() c:Disconnect() end) end optConns = nil end
        if optOrig then pcall(function()
            Lighting.GlobalShadows = optOrig.gs; Lighting.FogColor = optOrig.fc; Lighting.FogStart = optOrig.fs; Lighting.FogEnd = optOrig.fe; Lighting.Brightness = optOrig.br
            Lighting.OutdoorAmbient = optOrig.oa; Lighting.Ambient = optOrig.am
        end) end
        for _, e in ipairs(Lighting:GetDescendants()) do
            if e:IsA("Atmosphere") or e:IsA("Clouds") or e:IsA("PostEffect") then pcall(function() e.Enabled = true end) end
            if e:IsA("Sky") then pcall(function() e.CelestialBodiesShown = true end) end
        end
        pcall(function() Workspace.Terrain.Decoration = true end)
        for _, o in ipairs(Workspace:GetDescendants()) do
            if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") or o:IsA("Smoke") or o:IsA("Fire") or o:IsA("Sparkles") then pcall(function() o.Enabled = true end)
            elseif o:IsA("Decal") or o:IsA("Texture") then pcall(function() o.Transparency = 0 end) end
        end
        setStatus("optimizer off (rejoin to restore textures fully)")
    end
end

--========================== PAGES =================================--
addGroup("Automation")
-- FARM
do
    local p = addTab("Farm")
    local L, R = twoCol(p)
    -- Planting
    colTitle(L, "Planting"); subTitle(L, "Auto Plant")
    howItWorks(L, "Equips each owned seed and plants it across your plot's soil. Leave the picker empty to plant every seed you own, or choose specific ones.")
    toggleRow(L, "Auto Plant", "Plants your owned seeds on a loop.", "autoPlant")
    dropdownRow(L, "Seeds To Plant", "Only seeds in your inventory. Empty = plant them all.", getOwnedSeedOptions, S.plantSeeds, nil, nil, seedPriceTag)
    choiceRow(L, "Plant Pattern", "How seeds are laid out on the soil.", function() return PLANT_PATTERNS end, function() return S.plantPattern end, function(v) S.plantPattern = v end)
    choiceRow(L, "Plant Source", "My Seeds, or replant a saved garden snapshot.", function() local t={"My Seeds"} for _,n in ipairs(snapshotNames()) do t[#t+1]=n end return t end, function() return S.plantSource end, function(v) S.plantSource = v end)
    toggleRow(L, "Smart Replant", "Only plant the most profitable seed you own.", "smartReplant")
    actionRow(L, "Plant Once Now", "Run a single planting pass.", function()
        local plot = myPlot(); if not plot then return end
        local d = getData(); local seeds = d and d.Inventory and d.Inventory.Seeds; if not seeds then return end
        local useF = next(S.plantSeeds) ~= nil; local tp = {}
        for n, c in pairs(seeds) do if (not useF) or S.plantSeeds[n] then for _=1,math.min(c or 0,40) do tp[#tp+1]=n end end end
        local free = freePlantPositions(plot)
        for i = 1, math.min(#free, #tp) do fire(Net.Plant.PlantSeed, free[i], tp[i], plot) task.wait(S.plantDelay) end
        setStatus("planted " .. math.min(#free, #tp))
    end)
    subTitle(L, "Garden Size")
    toggleRow(L, "Auto Expand Garden", "Buys the next expansion whenever you can afford it.", "autoExpand")
    actionRow(L, "Expand Garden Now", "Buy one garden expansion.", function()
        local plot = myPlot(); if not plot then return end
        local before = tonumber(plot:GetAttribute("GardenExpansion")) or 0
        fire(Net.Actions.ExpandGarden); task.wait(0.8)
        local after = tonumber(plot:GetAttribute("GardenExpansion")) or before
        setStatus(after > before and ("expanded to size " .. after) or "can't expand (need more money or maxed)")
    end)
    subTitle(L, "Timing")
    sliderRow(L, "Keep In Reserve (per seed)", 0, 25, S.plantReserve, 0, function(v) S.plantReserve = v end)
    sliderRow(L, "Max Plants / Cycle", 1, 80, S.maxPerCycle, 0, function(v) S.maxPerCycle = v end)
    sliderRow(L, "Plant Delay", 0.05, 1, S.plantDelay, 2, function(v) S.plantDelay = v end)
    sliderRow(L, "Loop Delay", 0.5, 10, S.plantLoop, 1, function(v) S.plantLoop = v end)
    -- Harvest
    colTitle(R, "Harvest"); subTitle(R, "Auto Harvest")
    howItWorks(R, "Collects grown fruit on your plot by firing CollectFruit for each. Use the filters below to only pick up certain crops or mutations.")
    toggleRow(R, "Auto Harvest", "Collects all ready fruit on your plot on a loop.", "autoCollect")
    dropdownRow(R, "Only These Crops", "Empty = harvest every crop type.", getHarvestOptions, S.harvestCrops, nil, nil)
    toggleRow(R, "Only Harvest Mutated Fruit", "Skips any fruit that has no mutation.", "harvestMutsOnly")
    sliderRow(R, "Per-Fruit Delay", 0.02, 0.5, S.perFruitDelay, 2, function(v) S.perFruitDelay = v end)
    sliderRow(R, "Loop Delay", 0.5, 10, S.harvestLoop, 1, function(v) S.harvestLoop = v end)
    actionRow(R, "Harvest Now", "Collect every ready fruit immediately.", function()
        setStatus("harvested " .. harvestAll(false))
    end)
    subTitle(R, "Sell")
    toggleRow(R, "Auto Sell (timed)", "Sells everything every interval.", "autoSell")
    sliderRow(R, "Sell Interval (s)", 5, 120, S.sellInterval, 0, function(v) S.sellInterval = v end)
    toggleRow(R, "Sell When Backpack Full", "Auto-sells the moment your backpack fills.", "sellOnFull")
    actionRow(R, "Sell All Now", "Sell every harvested fruit.", function() fire(Net.NPCS.SellAll); setStatus("sold all") end)
end

-- SHOP
do
    local p = addTab("Shop", "🛒")
    local L, R = twoCol(p)
    subTitle(L, "Seeds")
    howItWorks(L, "Buys the seeds you tick the instant they restock. Empty picker = buy every seed in stock you can afford.")
    toggleRow(L, "Auto Buy Seeds", "Buys selected seeds (or all if empty).", "autoBuySeed")
    dropdownRow(L, "Seeds To Buy", "Empty = buy everything in stock.", getSeedOptions, S.buySeeds, seedStockOf, nil, seedPriceTag)
    actionRow(L, "Buy Now", "Buy your picked seeds (or all if empty) in stock.", function()
        local it = seedStockItems(); if not it then return end
        local anySel = next(S.buySeeds) ~= nil
        for _, sv in ipairs(it:GetChildren()) do if sv:IsA("ValueBase") and sv.Value > 0 and ((not anySel) or S.buySeeds[sv.Name] == true) then fire(Net.SeedShop.PurchaseSeed, sv.Name) task.wait(0.08) end end
        setStatus("bought seeds")
    end)

    subTitle(R, "Gear & Crates")
    howItWorks(R, "Buys gear (sprinklers, mushrooms, pots, traps...) on restock. Empty gear picker = buy EVERY gear in stock.")
    toggleRow(R, "Auto Buy Gears", "Buys selected gear (or all if empty).", "autoBuyGear")
    dropdownRow(R, "Gear To Buy", "Empty = buy everything in stock.", getGearOptions, S.buyGears, gearStockOf, nil)
    toggleRow(R, "Auto Buy Crates", "Buys every crate in stock on restock.", "autoBuyCrate")
end

-- STEAL
do
    local p = addTab("Steal", "🌙")
    local L, R = twoCol(p)
    colTitle(L, "Night Raiding"); subTitle(L, "Auto Steal")
    howItWorks(L, "Steals ripe fruit from every other garden, most valuable first. Grabs multiple fruit per plant in one trip. Works only at NIGHT.")
    toggleRow(L, "Auto Steal", "Raid all gardens by fruit value.", "autoSteal")
    toggleRow(L, "Return Home After", "Teleport back to your garden each pass.", "stealReturn")
    sliderRow(L, "Fruits Per Steal", 1, 10, S.stealMult, 0, function(v) S.stealMult = v end)
    colTitle(R, "Manual"); subTitle(R, "Actions")
    actionRow(R, "Steal Most Valuable", "Grab the single highest-value fruit now.", function()
        if not isNight() then setStatus("not night - cannot steal") return end
        local t = stealTargets(); if t[1] then stealModel(t[1].model, S.stealMult); setStatus("stole fruit worth " .. math.floor(t[1].value)) else setStatus("nothing to steal") end
    end)
end

-- DEFENSE
do
    local p = addTab("Defense", "🛡️")
    local L = oneCol(p)
    colTitle(L, "Protect Your Garden"); subTitle(L, "Defense")
    howItWorks(L, "Panic harvest instantly collects all your ripe crops the moment night begins, before thieves can reach them. Retaliate shovels anyone standing on your plot.")
    toggleRow(L, "Panic Harvest At Night", "Grab all ripe fruit when night starts.", "panicHarvest")
    toggleRow(L, "Retaliate (shovel intruders)", "Hit any non-owner standing in your plot.", "retaliate")
    actionRow(L, "Harvest Everything Now", "Emergency-collect all ripe fruit.", function() setStatus("harvested " .. harvestAll(false)) end)
end

-- EVENT
do
    local p = addTab("Event", "✨")
    local L = oneCol(p)
    colTitle(L, "Gold Moon"); subTitle(L, "Seed Pack Grabber")
    howItWorks(L, "During the Gold Moon, Gold/Rainbow seed packs spawn around the map. The hub flies to one and completes its hold-to-claim prompt. It only returns to your garden once the event ends.")
    toggleRow(L, "Auto Grab Seed Packs", "Fly to and claim spawned packs.", "autoGrabPacks")
    toggleRow(L, "Rare Only (Gold / Rainbow)", "Ignore ordinary seed packs.", "grabRareOnly")
    toggleRow(L, "Return When Event Ends", "Go home only after the night ends.", "packReturn")
    toggleRow(L, "Notify On Rare Spawn", "Alert when a Gold/Rainbow spawns.", "notifyRare")
    actionRow(L, "Grab Nearest Pack Now", "Claim the closest spawned pack.", function()
        local root = hrp(); if not root then return end
        local map = Workspace:FindFirstChild("Map"); local locs = map and map:FindFirstChild("SeedPackSpawnServerLocations")
        if not locs or #locs:GetChildren() == 0 then setStatus("no pack spawned right now") return end
        local best, bestD
        for _, loc in ipairs(locs:GetChildren()) do local d = (loc.Position - root.Position).Magnitude if d < (bestD or math.huge) then best, bestD = loc, d end end
        if best then grabPack(best); setStatus("grabbed nearest pack") end
    end)
end

addGroup("Garden")
-- TIMERS
do
    local p = addTab("Timers")
    local L, R = twoCol(p)
    colTitle(L, "Active Event"); subTitle(L, "Cycle")
    local function tRow(parent, leftText)
        local f = card(parent); padAll(f, 12, 12, 9, 9)
        local Lb = Instance.new("TextLabel"); Lb.BackgroundTransparency = 1; Lb.Size = UDim2.new(1,-90,0,16); Lb.Font = FM; Lb.Text = leftText
        Lb.TextSize = 13; Lb.TextColor3 = C.text; Lb.TextXAlignment = Enum.TextXAlignment.Left; Lb.Parent = f
        local Rb = Instance.new("TextLabel"); Rb.AnchorPoint = Vector2.new(1,0); Rb.BackgroundTransparency = 1; Rb.Position = UDim2.new(1,0,0,0); Rb.Size = UDim2.fromOffset(86,16)
        Rb.Font = FB; Rb.Text = "-"; Rb.TextSize = 13; Rb.TextColor3 = C.white; Rb.TextXAlignment = Enum.TextXAlignment.Right; Rb.Parent = f
        return Lb, Rb
    end
    local evL, evR = tRow(L, "-")
    subTitle(R, "Shop Restocks")
    local _, sR = tRow(R, "Seed shop"); local _, gR = tRow(R, "Gear shop"); local _, cR = tRow(R, "Crate shop")
    spawnLoop(1, function()
        if not p.Visible then return end
        local raw, _, endsAt = currentEvent()
        evL.Text = eventNameOf(raw); evL.TextColor3 = eventColorOf(raw)
        evR.Text = endsAt and fmtClock(endsAt - os.time()) or "-"
        local s, g, c = restockIn("SeedShop"), restockIn("GearShop"), restockIn("CrateShop")
        sR.Text = s and fmtClock(s) or "-"; gR.Text = g and fmtClock(g) or "-"; cR.Text = c and fmtClock(c) or "-"
    end)
end

-- ITEMS
do
    local p = addTab("Items", "📦")
    local L, R = twoCol(p)
    subTitle(L, "Auto Open")
    toggleRow(L, "Auto Open Eggs", "Opens every egg you own on a loop.", "autoEggs")
    toggleRow(L, "Auto Open Crates", "Opens every crate you own on a loop.", "autoCrates")
    toggleRow(L, "Auto Open Seed Packs", "Opens every seed pack on a loop.", "autoPacks")
    actionRow(L, "Open All Eggs", "Open your whole egg inventory now.", function() local d = getData() local b = d and d.Inventory and d.Inventory.Eggs if b then for n in pairs(b) do task.spawn(function() fire(Net.Egg.OpenEgg, n) end) task.wait(0.15) end end setStatus("opened eggs") end)
    actionRow(L, "Open All Crates", "Open your whole crate inventory now.", function() local d = getData() local b = d and d.Inventory and d.Inventory.Crates if b then for n in pairs(b) do task.spawn(function() fire(Net.Crate.OpenCrate, n) end) task.wait(0.15) end end setStatus("opened crates") end)
    actionRow(L, "Open All Seed Packs", "Open your whole seed-pack inventory now.", function() local d = getData() local b = d and d.Inventory and d.Inventory.SeedPacks if b then for n in pairs(b) do task.spawn(function() fire(Net.SeedPack.OpenSeedPack, n) end) task.wait(0.15) end end setStatus("opened packs") end)

    subTitle(R, "Garden Snapshots")
    howItWorks(R, "Stand in any garden and snapshot it to capture exactly which seeds (and how many) plus its building layout. Then pick the snapshot as your Plant Source on the Farm tab to replant it, or use Auto Build to recreate the buildings.")
    local snapName = "Snapshot 1"
    inputRow(R, "Snapshot Name", "Name to save the capture under.", snapName, "Snapshot 1", function(t) if t and t ~= "" then snapName = t end end)
    actionRow(R, "Snapshot This Garden", "Capture the garden you're standing in.", function()
        local ok, msg = captureSnapshot(snapName)
        if ok then notify('Saved "' .. snapName .. '" - ' .. msg, "Garden Snapshot", C.green) else setStatus(tostring(msg)) end
    end)
    subTitle(R, "Auto Build")
    toggleRow(R, "Auto Build Snapshot", "Recreate the source snapshot's buildings (experimental).", "autoBuild")
    actionRow(R, "Build Snapshot Now", "Place the source snapshot's buildings once.", function() buildSnapshot() end)
    subTitle(R, "Cleanup")
    dropdownRow(R, "Plants To Remove", "Pick crop types, then Remove Selected.", getPlantedOptions, S.removeCrops, nil, nil)
    actionRow(R, "Remove Selected", "Shovel only the picked crop types.", function()
        if not next(S.removeCrops) then setStatus("pick crops to remove first") return end
        setStatus("removing selected...") task.spawn(function() local n = removeSelectedPlants() setStatus("removed " .. n .. " plants") end)
    end)
    actionRow(R, "Remove All Plants", "Shovel up every plant on your plot.", function() setStatus("removing plants...") task.spawn(function() local n = removeAllPlants() setStatus("removed " .. n .. " plants") end) end)
    actionRow(R, "Remove All Buildings", "Pick up every building on your plot.", function() setStatus("removing buildings...") task.spawn(function() local n = removeAllBuildings() setStatus("removed " .. n .. " buildings") end) end)
end

-- PETS
do
    local p = addTab("Pets", "🐾")
    local L, R = twoCol(p)
    colTitle(L, "Wild Animals"); subTitle(L, "Auto Tame")
    howItWorks(L, "Sits on wild animals and tames them. Pick which species to chase, or leave empty to tame every wild animal that spawns.")
    toggleRow(L, "Auto Tame Wild Animals", "Tame selected species automatically.", "autoTame")
    dropdownRow(L, "Animals To Tame", "Empty = tame everything.", getAnimalOptions, S.tameAnimals, nil, nil)

    colTitle(R, "Your Pets"); subTitle(R, "Auto Equip")
    howItWorks(R, "Keeps your chosen pets equipped. You can pick up to your equip slot count - the picker shows 1/3, 2/3, then MAX in red.")
    toggleRow(R, "Auto Equip Pets", "Keeps the selected pets equipped.", "autoEquipPets")
    dropdownRow(R, "Pets To Equip", "Pick up to your slot count.", getPetOptions, S.equipPets, nil, maxEquip)
    actionRow(R, "Equip Now", "Equip the selected pets immediately.", function()
        local n, mx = 0, maxEquip()
        for name in pairs(S.equipPets) do if n >= mx then break end fire(Net.Pets.RequestEquipByName, tostring(name)) n = n + 1 task.wait(0.12) end
        setStatus("equipped " .. n .. " pets")
    end)
end

addGroup("Tools")
-- STATS
do
    local p = addTab("Stats")
    local L, R = twoCol(p)
    local function statRow(parent, lbl, col)
        local f = card(parent); padAll(f, 12, 12, 9, 9)
        local Lb = Instance.new("TextLabel"); Lb.BackgroundTransparency = 1; Lb.Size = UDim2.new(1,-150,0,16); Lb.Font = FM; Lb.Text = lbl; Lb.TextSize = 13; Lb.TextColor3 = C.text; Lb.TextXAlignment = Enum.TextXAlignment.Left; Lb.Parent = f
        local Rb = Instance.new("TextLabel"); Rb.AnchorPoint = Vector2.new(1,0); Rb.BackgroundTransparency = 1; Rb.Position = UDim2.new(1,0,0,0); Rb.Size = UDim2.fromOffset(146,16); Rb.Font = FB; Rb.Text = "-"; Rb.TextSize = 13; Rb.TextColor3 = col or C.accentText; Rb.TextXAlignment = Enum.TextXAlignment.Right; Rb.TextTruncate = Enum.TextTruncate.AtEnd; Rb.Parent = f
        return Rb
    end
    subTitle(L, "Profit Tracker")
    local sMin = statRow(L, "Per Minute", C.green); local sHr = statRow(L, "Per Hour", C.green); local sSess = statRow(L, "Session Earned", C.green)
    subTitle(R, "Inventory")
    local sInv = statRow(R, "Backpack Value", C.green); local sCnt = statRow(R, "Fruit Count"); local sBest = statRow(R, "Best Crop To Plant")
    actionRow(R, "Rescan Inventory", "Recalculate backpack worth now.", function() local v, n = inventoryValue() setStatus("inventory worth " .. money(v) .. " (" .. n .. " fruit)") end)
    spawnLoop(1, function()
        if not p.Visible then return end
        sMin.Text = money(Profit.perMin); sHr.Text = money(Profit.perHr); sSess.Text = money(Profit.session)
        local v, n = inventoryValue(); sInv.Text = money(v); sCnt.Text = n .. "x"
        local best = bestOwnedSeed(); local d = getData(); local cnt = (best and d and d.Inventory and d.Inventory.Seeds and d.Inventory.Seeds[best]) or 0
        sBest.Text = best and (best .. "   " .. cnt .. "x") or "-"
    end)
end

-- TELEPORT
do
    local p = addTab("Teleport", "📍")
    local L, R = twoCol(p)
    colTitle(L, "Shops & NPCs"); subTitle(L, "Quick Travel")
    local function tpBtn(parent, label, pad)
        actionRow(parent, label, "Travel to the " .. label .. ".", function()
            local t = Workspace:FindFirstChild("Teleports"); local d = t and t:FindFirstChild(pad)
            if d and d:IsA("BasePart") then reach(d.Position); setStatus("teleported to " .. label) else setStatus(label .. " not found") end
        end, "GO")
    end
    tpBtn(L, "Seed Shop", "Seeds"); tpBtn(L, "Gear Shop", "Gears"); tpBtn(L, "Sell NPC", "Sell"); tpBtn(L, "Props Shop", "Props")
    colTitle(R, "Garden"); subTitle(R, "Home")
    actionRow(R, "My Garden", "Return to your own plot.", function() local plot = myPlot() local sp = plot and plot:FindFirstChild("SpawnPoint") if sp then reach(sp.Position) end setStatus("teleported home") end, "GO")
end

-- VISUAL
do
    local p = addTab("Visual", "👁️")
    local L = oneCol(p)
    colTitle(L, "ESP & Alerts"); subTitle(L, "Visual")
    howItWorks(L, "Outlines crops on screen and pings you about rare stock. Mutated-fruit ESP is distance-capped so it stays light.")
    toggleRow(L, "Highlight Ready Crops", "Outlines your own ripe crops in ruby.", "highlightReady")
    toggleRow(L, "Highlight Mutated Fruit", "Outlines nearby gold/mutated fruit in gold.", "highlightRare")
    toggleRow(L, "Rare Seed Restock Alert", "Notifies when a pricey seed hits the shop.", "rareNotify")
end

addGroup("Player")
do
    local p = addTab("Player", "🏃")
    local L, R = twoCol(p)
    subTitle(L, "Movement")
    howItWorks(L, "The game snaps you back if you move too fast, so keep speeds moderate. The hub also paces its teleports in safe hops.")
    sliderRow(L, "Walk Speed", 16, 120, S.walkSpeed, 0, function(v) S.walkSpeed = v end)
    sliderRow(L, "Jump Power", 50, 250, S.jumpPower, 0, function(v) S.jumpPower = v end)
    toggleRow(L, "Infinite Jump", "Jump again any time mid-air.", "infJump")
    toggleRow(L, "Noclip", "Walk through walls and fences.", "noclip", function(v) if not v then local c = char() if c then for _, pp in ipairs(c:GetDescendants()) do if pp:IsA("BasePart") then pp.CanCollide = true end end end end end)
    subTitle(R, "Fly")
    toggleRow(R, "Fly", "Free-fly with W/A/S/D, Space up, Ctrl down.", "fly", function(v) if not v and Hub.stopFly then Hub.stopFly() end end)
    sliderRow(R, "Fly Speed", 20, 150, S.flySpeed, 0, function(v) S.flySpeed = v end)
    subTitle(R, "Teleport")
    actionRow(R, "Go To My Garden", "Hop back to your own plot.", function() local plot = myPlot() local sp = plot and plot:FindFirstChild("SpawnPoint") if sp then reach(sp.Position) end setStatus("teleported") end)
end

addGroup("Misc")
do
    local p = addTab("Misc", "⚙️")
    local L = oneCol(p)
    colTitle(L, "Utility"); subTitle(L, "Auto Progress")
    howItWorks(L, "Hands-off progression: harvests your crops, sells them, buys the best seeds you can afford, plants them across the whole garden, and tames valuable pets (Raccoon, Dragonfly...) when they spawn. Leave it on and your coins + pets snowball.")
    toggleRow(L, "Auto Progress", "Farm, sell, reinvest and tame - automatically.", "autoProgress")
    subTitle(L, "Performance")
    toggleRow(L, "Optimize", "Flat textures, grey sky, no effects - big FPS boost.", "optimize", setOptimize)
    subTitle(L, "Session")
    toggleRow(L, "Anti-AFK", "Prevents the 20-minute idle kick.", "antiAfk")
    actionRow(L, "Rejoin Server", "Teleport into the same place again.", function() pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer) end) end)
    actionRow(L, "Server Hop", "Request a fresh server.", function() pcall(function() Net.AntiAfk.RequestHop:Fire() end) setStatus("requesting new server") end)
    subTitle(L, "Info")
    local info = card(L); padAll(info, 12, 12, 10, 10); vlist(info, 3)
    local i1 = Instance.new("TextLabel"); i1.Size = UDim2.new(1,0,0,14); i1.BackgroundTransparency = 1; i1.Font = FR; i1.Text = "Right Shift toggles the menu. The X fully unloads everything."; i1.TextSize = 11; i1.TextColor3 = C.sub; i1.TextWrapped = true; i1.TextXAlignment = Enum.TextXAlignment.Left; i1.AutomaticSize = Enum.AutomaticSize.Y; i1.LayoutOrder = 1; i1.Parent = info
    local i2 = Instance.new("TextLabel"); i2.Size = UDim2.new(1,0,0,14); i2.BackgroundTransparency = 1; i2.Font = FR; i2.Text = "UserId " .. LocalPlayer.UserId .. "   -   Plot " .. (myPlot() and myPlot().Name or "?"); i2.TextSize = 11; i2.TextColor3 = C.sub; i2.TextXAlignment = Enum.TextXAlignment.Left; i2.LayoutOrder = 2; i2.Parent = info
    actionRow(L, "Unload Hub", "Stop everything and close.", function() Hub.unload() end)
end

-- SERVER
do
    local p = addTab("Server")
    local L, R = twoCol(p)
    subTitle(L, "Server Hop")
    howItWorks(L, "Jump to other servers - handy for finding rare seed stock or fresh events. Low-pop finds the emptiest server.")
    actionRow(L, "Server Hop", "Teleport to a different server.", function() serverHop(false) end)
    actionRow(L, "Low-Pop Hop", "Teleport to the emptiest server.", function() serverHop(true) end)
    toggleRow(L, "Auto-Hop Until Rare Seed", "Keeps hopping until a 5K+ seed is in stock.", "autoHopRare")
    subTitle(R, "Webhook")
    howItWorks(R, "Paste a Discord webhook URL to get pinged about events. Toggle which events to send.")
    inputRow(R, "Webhook URL", "Discord webhook to post to.", S.webhookUrl, "https://discord.com/api/webhooks/...", function(t) S.webhookUrl = t end)
    toggleRow(R, "Notify: Rare Seed In Stock", "Posts when a 5K+ seed restocks.", "whRareSeed")
    actionRow(R, "Send Test Message", "Post a test message to your webhook.", function() if sendWebhook("Test from 360's GAG - webhook is working!") then setStatus("test sent") else setStatus("set a webhook URL first") end end)
end

--========================== INIT ==================================--
selectTab("Farm")
-- subtle open animation
-- whole hub scales as one unit (UIScale) so text, boxes & descriptions stay in proportion
local UI_SCALE = 0.88
UIScale.Scale = 0.74
TweenService:Create(UIScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = UI_SCALE }):Play()
notify("Loaded successfully - press Right Shift to toggle the menu.", "360's GAG", C.accent)
setStatus("loaded - Right Shift to toggle")
print("[360's GAG] loaded.")
