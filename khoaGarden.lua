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

local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)
local WindUI
do
	local ok, result = pcall(function()
		return require("./src/Init")
	end)
	if ok then
		WindUI = result
	else
		if cloneref(game:GetService("RunService")):IsStudio() then
			WindUI = require(cloneref(game:GetService("ReplicatedStorage"):WaitForChild("WindUI"):WaitForChild("Init")))
		else
			WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
		end
	end
end


--========================== GAME API ==============================--
local Net = (function() local ok,m = pcall(function() return require(ReplicatedStorage.SharedModules.Networking) end) return ok and m or nil end)()
local PSC = (function() local ok,m = pcall(function() return require(ReplicatedStorage.ClientModules.PlayerStateClient) end) return ok and m or nil end)()
if not Net then warn("[Khoa Dev > Grow a Garden 2] Thiếu module Networking - hủy bỏ."); return end

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
if genv.KhoaDevGarden_unload then pcall(genv.KhoaDevGarden_unload) end
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
local function notify(t, title, col) if toast then toast(title or "Khoa Dev > Grow a Garden 2", t, col) end pcall(function() Net.Notification:Fire("Khoa Dev > Grow a Garden 2", t) end) end

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

----====================== WIND UI SYSTEM ==========================--
local C = {
    accent = Color3.fromRGB(16, 197, 80),
    green = Color3.fromRGB(16, 197, 80),
    text = Color3.fromRGB(223, 223, 229),
    sub = Color3.fromRGB(138, 138, 148),
    white = Color3.fromRGB(240, 240, 245)
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

local function guiParent()
    local p; pcall(function() p = gethui and gethui() end)
    if not p then pcall(function() p = game:GetService("CoreGui") end) end
    return p or LocalPlayer:WaitForChild("PlayerGui")
end

local StatusLabel
local function setStatus(t)
    if not StatusLabel then
        local sg = Instance.new("ScreenGui")
        sg.Name = "GAG360Status"
        sg.ResetOnSpawn = false
        if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end
        sg.Parent = guiParent()
        
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 340, 0, 26)
        lbl.Position = UDim2.new(0.5, -170, 1, -40)
        lbl.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        lbl.BackgroundTransparency = 0.3
        lbl.TextColor3 = Color3.fromRGB(240, 240, 240)
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.Text = ""
        lbl.Parent = sg
        
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = lbl
        
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(16, 197, 80)
        s.Thickness = 1
        s.Parent = lbl
        
        StatusLabel = lbl
    end
    StatusLabel.Text = "Trạng thái: " .. t
end

local function notify(t, title, col)
    pcall(function()
        WindUI:Notify({
            Title = title or "Khoa Dev > Grow a Garden 2",
            Content = t,
            Duration = 5
        })
    end)
    pcall(function() Net.Notification:Fire("Khoa Dev > Grow a Garden 2", t) end)
end

-- Wind UI Window Setup
local Window = WindUI:CreateWindow({
	Title = "Khoa Dev  >  Grow a Garden 2",
	Folder = "KhoaDevGarden",
	Icon = "solar:leaf-bold-duotone",
	NewElements = true,
	HideSearchBar = true,
	OpenButton = {
		Title = "Mở Khoa Dev UI",
		CornerRadius = UDim.new(1, 0),
		StrokeThickness = 3,
		Enabled = true,
		Draggable = true,
		OnlyMobile = false,
		Scale = 0.5,
		Color = ColorSequence.new(
			Color3.fromRGB(16, 197, 80),
			Color3.fromRGB(162, 255, 48)
		),
	},
})
Window:SetToggleKey(Enum.KeyCode.RightShift)

local currentSidebarSection = nil
local function addGroup(title)
    currentSidebarSection = Window:Section({
        Title = title
    })
end

local pages = {}
local function addTab(name, icon)
    local tabObj
    if currentSidebarSection then
        tabObj = currentSidebarSection:Tab({
            Title = name,
            Icon = icon or "solar:folder-2-bold"
        })
    else
        tabObj = Window:Tab({
            Title = name,
            Icon = icon or "solar:folder-2-bold"
        })
    end
    pages[name] = tabObj
    return tabObj
end

local function twoCol(page)
    return page, page
end
local function oneCol(page)
    return page
end
local function colTitle(parent, text)
end
local function subTitle(parent, text)
    return parent:Section({
        Title = text
    })
end

local function howItWorks(parent, text)
    return parent:Paragraph({
        Title = "How it works",
        Desc = text
    })
end

local function toggleRow(parent, name, desc, key, cb)
    local toggle
    toggle = parent:Toggle({
        Title = name,
        Desc = desc,
        Value = S[key] or false,
        Callback = function(v)
            if key then S[key] = v end
            if cb then pcall(cb, v) end
            saveSettings()
        end
    })
    if cb and key and S[key] then
        task.spawn(function() pcall(cb, true) end)
    end
    return function(v)
        if toggle and toggle.Set then toggle:Set(v) end
    end
end

local function sliderRow(parent, name, mn, mx, default, decimals, setFn)
    local slider
    slider = parent:Slider({
        Title = name,
        Step = decimals and (1 / (10 ^ decimals)) or 1,
        IsTooltip = true,
        IsTextbox = true,
        Value = {
            Min = mn,
            Max = mx,
            Default = default,
        },
        Callback = function(v)
            if setFn then pcall(setFn, v) end
            saveSettings()
        end
    })
    return slider
end

local function actionRow(parent, name, desc, cb)
    return parent:Button({
        Title = name,
        Desc = desc,
        Callback = cb
    })
end

local dropdownsToRefresh = {}

local function setToList(set)
    local list = {}
    for k, v in pairs(set) do
        if v == true then table.insert(list, k) end
    end
    return list
end

local function listToSet(list, set)
    table.clear(set)
    for _, v in ipairs(list) do
        set[v] = true
    end
end

local function cleanName(opt)
    local idx = string.find(opt, " %- ")
    if idx then
        return string.sub(opt, 1, idx - 1)
    end
    return opt
end

local function getFormattedValues(getOptions, priceFn, getStockFn)
    local opts = getOptions()
    local formatted = {}
    for _, opt in ipairs(opts) do
        local label = opt
        local price = priceFn and priceFn(opt)
        local stock = getStockFn and getStockFn(opt)
        local suffix = {}
        if price and price ~= "" then table.insert(suffix, price) end
        if stock and stock > 0 then table.insert(suffix, stock .. "x") end
        if #suffix > 0 then label = label .. " - " .. table.concat(suffix, ", ") end
        table.insert(formatted, label)
    end
    return formatted
end

local function dropdownRow(parent, name, desc, getOptions, selectedSet, getStockFn, maxSelectFn, priceFn)
    local dropdown
    local function getSelectedList()
        local list = {}
        for k, v in pairs(selectedSet) do
            if v == true then
                local found = false
                for _, opt in ipairs(getOptions()) do
                    if opt == k then
                        local label = k
                        local price = priceFn and priceFn(k)
                        local stock = getStockFn and getStockFn(k)
                        local suffix = {}
                        if price and price ~= "" then table.insert(suffix, price) end
                        if stock and stock > 0 then table.insert(suffix, stock .. "x") end
                        if #suffix > 0 then label = label .. " - " .. table.concat(suffix, ", ") end
                        table.insert(list, label)
                        found = true
                        break
                    end
                end
                if not found then table.insert(list, k) end
            end
        end
        return list
    end

    local updating = false
    dropdown = parent:Dropdown({
        Title = name,
        Desc = desc,
        Values = getFormattedValues(getOptions, priceFn, getStockFn),
        Multi = true,
        Value = getSelectedList(),
        Callback = function(selected)
            if updating then return end
            local maxVal = maxSelectFn and maxSelectFn()
            if maxVal and #selected > maxVal then
                updating = true
                local trimmed = {}
                for i = 1, maxVal do table.insert(trimmed, selected[i]) end
                task.spawn(function()
                    dropdown:Select(trimmed)
                    updating = false
                end)
                selected = trimmed
            end
            
            table.clear(selectedSet)
            for _, val in ipairs(selected) do
                selectedSet[cleanName(val)] = true
            end
            saveSettings()
        end
    })
    
    table.insert(dropdownsToRefresh, {
        element = dropdown,
        getOptions = getOptions,
        priceFn = priceFn,
        getStockFn = getStockFn,
        getSelectedList = getSelectedList
    })
    
    return {
        selectAll = function(v)
            if v then
                local opts = getOptions()
                if maxSelectFn then
                    local mx = maxSelectFn()
                    local n = 0
                    table.clear(selectedSet)
                    for _, opt in ipairs(opts) do
                        if n >= mx then break end
                        selectedSet[opt] = true
                        n = n + 1
                    end
                else
                    for _, opt in ipairs(opts) do
                        selectedSet[opt] = true
                    end
                end
            else
                table.clear(selectedSet)
            end
            saveSettings()
            pcall(function()
                dropdown:Select(getSelectedList())
            end)
        end
    }
end

local function choiceRow(parent, name, desc, getOptions, getSel, onPick)
    local dropdown
    dropdown = parent:Dropdown({
        Title = name,
        Desc = desc,
        Values = getOptions(),
        Value = getSel(),
        Callback = function(v)
            if onPick then pcall(onPick, v) end
            saveSettings()
        end
    })
    return {
        refresh = function()
            pcall(function() dropdown:Select(getSel()) end)
        end
    }
end

local function inputRow(parent, name, desc, default, placeholder, onSet)
    return parent:Input({
        Title = name,
        Desc = desc,
        Value = default,
        Placeholder = placeholder,
        Callback = function(v)
            if onSet then pcall(onSet, v) end
            saveSettings()
        end
    })
end

--========================== UNLOAD ================================--
function Hub.unload()
    if not Hub.running then return end
    saveSettings()
    Hub.running = false
    for _, c in ipairs(Hub.conns) do pcall(function() c:Disconnect() end) end
    Hub.conns = {}
    if Hub.stopFly then pcall(Hub.stopFly) end
    local h = humanoid(); if h then h.WalkSpeed = 16; h.UseJumpPower = true; h.JumpPower = 50; h.PlatformStand = false end
    local c = char(); if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end end end
    for k, v in pairs(S) do if type(v) == "boolean" then S[k] = false end end
    pcall(function() Window:Destroy() end)
    pcall(function() game:GetService("CoreGui"):FindFirstChild("GAG360Status"):Destroy() end)
    print("[Khoa Dev > Grow a Garden 2] đã gỡ bỏ hoàn toàn.")
end
genv.KhoaDevGarden_unload = Hub.unload
genv.KhoaDevGarden_notify = function(msg, title, col) notify(msg, title, col) end
track({ Disconnect = function() pcall(function() Window:Destroy() end) pcall(function() game:GetService("CoreGui"):FindFirstChild("GAG360Status"):Destroy() end) end })

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
-- Custom template rows for Timers and Stats tabs
local function tRow(parent, leftText)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 36)
    f.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    f.BackgroundTransparency = 0.2
    f.BorderSizePixel = 0
    f.Parent = parent
    
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = f
    
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(50, 50, 55)
    s.Thickness = 1
    s.Parent = f
    
    local Lb = Instance.new("TextLabel")
    Lb.BackgroundTransparency = 1
    Lb.Size = UDim2.new(1, -100, 1, 0)
    Lb.Position = UDim2.new(0, 12, 0, 0)
    Lb.Font = Enum.Font.GothamMedium
    Lb.Text = leftText
    Lb.TextSize = 13
    Lb.TextColor3 = Color3.fromRGB(200, 200, 205)
    Lb.TextXAlignment = Enum.TextXAlignment.Left
    Lb.Parent = f
    
    local Rb = Instance.new("TextLabel")
    Rb.BackgroundTransparency = 1
    Rb.Size = UDim2.new(0, 90, 1, 0)
    Rb.Position = UDim2.new(1, -102, 0, 0)
    Rb.Font = Enum.Font.GothamBold
    Rb.Text = "-"
    Rb.TextSize = 13
    Rb.TextColor3 = Color3.fromRGB(255, 255, 255)
    Rb.TextXAlignment = Enum.TextXAlignment.Right
    Rb.Parent = f
    
    return Lb, Rb
end

local function statRow(parent, lbl, col)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 36)
    f.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    f.BackgroundTransparency = 0.2
    f.BorderSizePixel = 0
    f.Parent = parent
    
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = f
    
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(50, 50, 55)
    s.Thickness = 1
    s.Parent = f
    
    local Lb = Instance.new("TextLabel")
    Lb.BackgroundTransparency = 1
    Lb.Size = UDim2.new(1, -160, 1, 0)
    Lb.Position = UDim2.new(0, 12, 0, 0)
    Lb.Font = Enum.Font.GothamMedium
    Lb.Text = lbl
    Lb.TextSize = 13
    Lb.TextColor3 = Color3.fromRGB(200, 200, 205)
    Lb.TextXAlignment = Enum.TextXAlignment.Left
    Lb.Parent = f
    
    local Rb = Instance.new("TextLabel")
    Rb.BackgroundTransparency = 1
    Rb.Size = UDim2.new(0, 150, 1, 0)
    Rb.Position = UDim2.new(1, -162, 0, 0)
    Rb.Font = Enum.Font.GothamBold
    Rb.Text = "-"
    Rb.TextSize = 13
    Rb.TextColor3 = col or Color3.fromRGB(232, 96, 114)
    Rb.TextXAlignment = Enum.TextXAlignment.Right
    Rb.TextTruncate = Enum.TextTruncate.AtEnd
    Rb.Parent = f
    
    return Rb
end

addGroup("Tự Động Hóa")

-- FARM
do
    local p = addTab("Nông Trại", "solar:home-2-bold")
    local L, R = twoCol(p)
    -- Planting
    colTitle(L, "Gieo Hạt"); subTitle(L, "Tự Động Gieo Hạt")
    howItWorks(L, "Tự động gieo tất cả hạt giống bạn sở hữu lên khu vườn. Nếu để trống bộ lọc, nó sẽ gieo toàn bộ hạt giống có sẵn, hoặc bạn có thể chọn các loại cụ thể.")
    toggleRow(L, "Tự Động Gieo Hạt", "Tự động gieo hạt giống bạn sở hữu theo vòng lặp.", "autoPlant")
    dropdownRow(L, "Hạt Giống Cần Gieo", "Chỉ gồm hạt giống trong kho của bạn. Để trống = gieo tất cả.", getOwnedSeedOptions, S.plantSeeds, nil, nil, seedPriceTag)
    
    local PLANT_PATTERNS_VN = { "Đầy Đủ", "Bàn Cờ", "Theo Hàng", "Theo Cột", "Đường Chéo", "Giãn Cách" }
    local PLANT_PATTERN_MAP = {
        ["Đầy Đủ"] = "Fill", ["Bàn Cờ"] = "Checkerboard", ["Theo Hàng"] = "Rows",
        ["Theo Cột"] = "Columns", ["Đường Chéo"] = "Diagonal", ["Giãn Cách"] = "Spaced"
    }
    local PLANT_PATTERN_REV = {
        ["Fill"] = "Đầy Đủ", ["Checkerboard"] = "Bàn Cờ", ["Rows"] = "Theo Hàng",
        ["Columns"] = "Theo Cột", ["Diagonal"] = "Đường Chéo", ["Spaced"] = "Giãn Cách"
    }
    choiceRow(L, "Mẫu Bố Trí", "Cách hạt giống được rải trên đất ruộng.", function() return PLANT_PATTERNS_VN end, function() return PLANT_PATTERN_REV[S.plantPattern] or "Đầy Đủ" end, function(v) S.plantPattern = PLANT_PATTERN_MAP[v] or "Fill" end)
    
    local plantSourceDropdown
    plantSourceDropdown = choiceRow(L, "Nguồn Hạt Giống", "Gieo hạt từ kho cá nhân hoặc tái tạo từ ảnh chụp vườn.", function()
        local t = {"Kho Hạt Giống"}
        for _, n in ipairs(snapshotNames()) do t[#t+1] = n end
        return t
    end, function() return S.plantSource == "My Seeds" and "Kho Hạt Giống" or S.plantSource end, function(v)
        S.plantSource = v == "Kho Hạt Giống" and "My Seeds" or v
    end)
    
    toggleRow(L, "Gieo Hạt Thông Minh", "Chỉ gieo loại hạt giống có giá trị cao nhất mà bạn sở hữu.", "smartReplant")
    actionRow(L, "Gieo Hạt Ngay", "Chạy một đợt gieo hạt ngay lập tức.", function()
        local plot = myPlot(); if not plot then return end
        local d = getData(); local seeds = d and d.Inventory and d.Inventory.Seeds; if not seeds then return end
        local useF = next(S.plantSeeds) ~= nil; local tp = {}
        for n, c in pairs(seeds) do if (not useF) or S.plantSeeds[n] then for _=1,math.min(c or 0,40) do tp[#tp+1]=n end end end
        local free = freePlantPositions(plot)
        for i = 1, math.min(#free, #tp) do fire(Net.Plant.PlantSeed, free[i], tp[i], plot) task.wait(S.plantDelay) end
        setStatus("đã gieo " .. math.min(#free, #tp))
    end)
    subTitle(L, "Kích Thước Vườn")
    toggleRow(L, "Tự Động Mở Rộng", "Tự động mua thêm đất mở rộng vườn khi đủ tiền.", "autoExpand")
    actionRow(L, "Mở Rộng Ngay", "Mua thêm một ô đất mở rộng.", function()
        local plot = myPlot(); if not plot then return end
        local before = tonumber(plot:GetAttribute("GardenExpansion")) or 0
        fire(Net.Actions.ExpandGarden); task.wait(0.8)
        local after = tonumber(plot:GetAttribute("GardenExpansion")) or before
        setStatus(after > before and ("đất mở rộng thành kích thước " .. after) or "không thể mở rộng (không đủ tiền hoặc đã tối đa)")
    end)
    subTitle(L, "Thời Gian & Giới Hạn")
    sliderRow(L, "Hạt Dự Trữ (mỗi loại)", 0, 25, S.plantReserve, 0, function(v) S.plantReserve = v end)
    sliderRow(L, "Hạt Gieo Tối Đa / Chu Kỳ", 1, 80, S.maxPerCycle, 0, function(v) S.maxPerCycle = v end)
    sliderRow(L, "Độ Trễ Gieo (giây)", 0.05, 1, S.plantDelay, 2, function(v) S.plantDelay = v end)
    sliderRow(L, "Chu Kỳ Lặp (giây)", 0.5, 10, S.plantLoop, 1, function(v) S.plantLoop = v end)
    
    -- Harvest
    colTitle(R, "Thu Hoạch"); subTitle(R, "Tự Động Thu Hoạch")
    howItWorks(R, "Tự động thu hoạch trái cây chín trên plot của bạn bằng cách gửi tín hiệu CollectFruit. Sử dụng các bộ lọc bên dưới để chỉ thu hoạch các cây cụ thể hoặc đột biến.")
    toggleRow(R, "Tự Động Thu Hoạch", "Thu hoạch tất cả trái cây chín trên plot theo vòng lặp.", "autoCollect")
    dropdownRow(R, "Chỉ Thu Hoạch Cây Này", "Để trống = thu hoạch tất cả các loại cây.", getHarvestOptions, S.harvestCrops, nil, nil)
    toggleRow(R, "Chỉ Thu Hoạch Trái Đột Biến", "Bỏ qua các trái cây không có đột biến.", "harvestMutsOnly")
    sliderRow(R, "Độ Trễ Mỗi Trái (giây)", 0.02, 0.5, S.perFruitDelay, 2, function(v) S.perFruitDelay = v end)
    sliderRow(R, "Chu Kỳ Lặp (giây)", 0.5, 10, S.harvestLoop, 1, function(v) S.harvestLoop = v end)
    actionRow(R, "Thu Hoạch Ngay", "Thu hoạch ngay lập tức tất cả trái cây chín.", function()
        setStatus("đã thu hoạch " .. harvestAll(false))
    end)
    subTitle(R, "Bán Trái Cây")
    toggleRow(R, "Tự Động Bán (theo giờ)", "Tự động bán toàn bộ trái cây sau mỗi khoảng thời gian.", "autoSell")
    sliderRow(R, "Khoảng Thời Gian Bán (giây)", 5, 120, S.sellInterval, 0, function(v) S.sellInterval = v end)
    toggleRow(R, "Bán Khi Đầy Túi", "Tự động bán ngay lập tức khi balo của bạn bị đầy.", "sellOnFull")
    actionRow(R, "Bán Tất Cả Ngay", "Bán toàn bộ trái cây đã thu hoạch.", function() fire(Net.NPCS.SellAll); setStatus("đã bán tất cả") end)
end

-- SHOP
do
    local p = addTab("Cửa Hàng", "🛒")
    local L, R = twoCol(p)
    subTitle(L, "Hạt Giống")
    howItWorks(L, "Tự động mua các loại hạt giống bạn đã chọn ngay khi cửa hàng hồi hàng. Để trống = mua toàn bộ loại hạt giống có sẵn trong tầm giá.")
    toggleRow(L, "Tự Động Mua Hạt Giống", "Mua hạt giống đã chọn (hoặc tất cả nếu để trống).", "autoBuySeed")
    dropdownRow(L, "Hạt Giống Cần Mua", "Để trống = mua tất cả hạt giống có hàng.", getSeedOptions, S.buySeeds, seedStockOf, nil, seedPriceTag)
    actionRow(L, "Mua Hạt Giống Ngay", "Mua hạt giống đã chọn (hoặc tất cả nếu để trống) đang có sẵn.", function()
        local it = seedStockItems(); if not it then return end
        local anySel = next(S.buySeeds) ~= nil
        for _, sv in ipairs(it:GetChildren()) do if sv:IsA("ValueBase") and sv.Value > 0 and ((not anySel) or S.buySeeds[sv.Name] == true) then fire(Net.SeedShop.PurchaseSeed, sv.Name) task.wait(0.08) end end
        setStatus("đã mua hạt giống")
    end)

    subTitle(R, "Trang Bị & Rương")
    howItWorks(R, "Tự động mua trang bị (bình tưới nước, nấm, chậu, bẫy...) khi hồi hàng. Để trống = mua MỌI trang bị có sẵn.")
    toggleRow(R, "Tự Động Mua Trang Bị", "Mua trang bị đã chọn (hoặc tất cả nếu để trống).", "autoBuyGear")
    dropdownRow(R, "Trang Bị Cần Mua", "Để trống = mua tất cả trang bị có sẵn.", getGearOptions, S.buyGears, gearStockOf, nil)
    toggleRow(R, "Tự Động Mua Rương", "Tự động mua mọi rương có sẵn khi hồi hàng.", "autoBuyCrate")
end

-- STEAL
do
    local p = addTab("Ăn Trộm", "🌙")
    local L, R = twoCol(p)
    colTitle(L, "Đi Trộm Đêm"); subTitle(L, "Tự Động Trộm")
    howItWorks(L, "Tự động đột nhập và trộm trái cây chín từ vườn nhà người khác, ưu tiên giá trị cao nhất. Có thể lấy nhiều trái mỗi cây. Chỉ hoạt động vào BAN ĐÊM.")
    toggleRow(L, "Tự Động Đi Trộm", "Đột kích tất cả vườn nhà người khác để trộm quả.", "autoSteal")
    toggleRow(L, "Trở Về Nhà Sau Khi Trộm", "Tự động dịch chuyển về vườn nhà bạn sau mỗi đợt.", "stealReturn")
    sliderRow(L, "Số Quả Trộm Mỗi Lần", 1, 10, S.stealMult, 0, function(v) S.stealMult = v end)
    colTitle(R, "Hành Động"); subTitle(R, "Hành Động Thủ Công")
    actionRow(R, "Trộm Quả Đắt Nhất", "Trộm một trái cây có giá trị cao nhất ngay lập tức.", function()
        if not isNight() then setStatus("không phải ban đêm - không thể trộm") return end
        local t = stealTargets(); if t[1] then stealModel(t[1].model, S.stealMult); setStatus("đã trộm trái cây trị giá " .. math.floor(t[1].value)) else setStatus("không có gì để trộm") end
    end)
end

-- DEFENSE
do
    local p = addTab("Phòng Thủ", "🛡️")
    local L = oneCol(p)
    colTitle(L, "Bảo Vệ Vườn"); subTitle(L, "Hệ Thống Phòng Thủ")
    howItWorks(L, "Tính năng Thu Hoạch Khẩn Cấp tự động gặt hái tất cả cây chín ngay khi đêm bắt đầu trước khi kẻ trộm kịp tới. Tính năng Đánh Trả tự động dùng xẻng vụt bất kỳ ai đứng trên đất của bạn.")
    toggleRow(L, "Panic Harvest At Night", "Gặt tất cả trái chín ngay khi trời tối.", "panicHarvest")
    toggleRow(L, "Đánh Trả (vụt xẻng kẻ đột nhập)", "Tự động đánh trả người lạ đứng trên plot của bạn.", "retaliate")
    actionRow(L, "Thu Hoạch Khẩn Cấp Ngay", "Thu hoạch toàn bộ trái chín lập tức.", function() setStatus("đã thu hoạch " .. harvestAll(false)) end)
end

-- EVENT
do
    local p = addTab("Sự Kiện", "✨")
    local L = oneCol(p)
    colTitle(L, "Sự Kiện Trăng"); subTitle(L, "Nhặt Gói Hạt Giống")
    howItWorks(L, "Trong sự kiện Gold Moon, các gói hạt giống Vàng/Cầu vồng sẽ rơi ngẫu nhiên trên bản đồ. Script sẽ tự bay tới và nhặt chúng. Chỉ quay về vườn khi sự kiện kết thúc.")
    toggleRow(L, "Tự Động Nhặt Gói Hạt", "Tự bay tới và nhặt các gói hạt giống rơi ra.", "autoGrabPacks")
    toggleRow(L, "Chỉ Nhặt Loại Hiếm", "Bỏ qua các gói hạt giống thường, chỉ nhặt Vàng/Cầu Vồng.", "grabRareOnly")
    toggleRow(L, "Về Nhà Khi Hết Sự Kiện", "Chỉ dịch chuyển về vườn sau khi đêm kết thúc.", "packReturn")
    toggleRow(L, "Thông Báo Khi Có Hạt Hiếm", "Cảnh báo khi có gói hạt giống Vàng/Cầu Vồng xuất hiện.", "notifyRare")
    actionRow(L, "Nhặt Gói Gần Nhất Ngay", "Thu thập gói hạt giống ở gần bạn nhất.", function()
        local root = hrp(); if not root then return end
        local map = Workspace:FindFirstChild("Map"); local locs = map and map:FindFirstChild("SeedPackSpawnServerLocations")
        if not locs or #locs:GetChildren() == 0 then setStatus("không có gói hạt giống nào xuất hiện") return end
        local best, bestD
        for _, loc in ipairs(locs:GetChildren()) do local d = (loc.Position - root.Position).Magnitude if d < (bestD or math.huge) then best, bestD = loc, d end end
        if best then grabPack(best); setStatus("đã nhặt gói hạt giống gần nhất") end
    end)
end

addGroup("Khu Vườn")

-- TIMERS
do
    local p = addTab("Thời Gian", "solar:clock-circle-bold")
    local L, R = twoCol(p)
    colTitle(L, "Sự Kiện Hiện Tại"); subTitle(L, "Chu Kỳ Ngày Đêm")
    local evL, evR = tRow(L, "-")
    subTitle(R, "Thời Gian Hồi Hàng")
    local _, sR = tRow(R, "Cửa hàng hạt"); local _, gR = tRow(R, "Cửa hàng đồ"); local _, cR = tRow(R, "Cửa hàng rương")
    spawnLoop(1, function()
        if not Window.Visible then return end
        local raw, _, endsAt = currentEvent()
        evL.Text = eventNameOf(raw); evL.TextColor3 = eventColorOf(raw)
        evR.Text = endsAt and fmtClock(endsAt - os.time()) or "-"
        local s, g, c = restockIn("SeedShop"), restockIn("GearShop"), restockIn("CrateShop")
        sR.Text = s and fmtClock(s) or "-"; gR.Text = g and fmtClock(g) or "-"; cR.Text = c and fmtClock(c) or "-"
    end)
end

-- ITEMS
do
    local p = addTab("Vật Phẩm", "solar:box-bold")
    local L, R = twoCol(p)
    subTitle(L, "Tự Động Mở")
    toggleRow(L, "Tự Động Mở Trứng", "Tự động mở mọi quả trứng bạn sở hữu theo vòng lặp.", "autoEggs")
    toggleRow(L, "Tự Động Mở Rương Đồ", "Tự động mở mọi rương trang bị bạn sở hữu theo vòng lặp.", "autoCrates")
    toggleRow(L, "Tự Động Mở Gói Hạt Giống", "Tự động mở mọi gói hạt giống.", "autoPacks")
    actionRow(L, "Mở Toàn Bộ Trứng", "Mở tất cả trứng trong kho ngay.", function() local d = getData() local b = d and d.Inventory and d.Inventory.Eggs if b then for n in pairs(b) do task.spawn(function() fire(Net.Egg.OpenEgg, n) end) task.wait(0.15) end end setStatus("đã mở trứng") end)
    actionRow(L, "Mở Toàn Bộ Rương Đồ", "Mở tất cả rương đồ trong kho ngay.", function() local d = getData() local b = d and d.Inventory and d.Inventory.Crates if b then for n in pairs(b) do task.spawn(function() fire(Net.Crate.OpenCrate, n) end) task.wait(0.15) end end setStatus("đã mở rương") end)
    actionRow(L, "Mở Toàn Bộ Gói Hạt Giống", "Mở tất cả gói hạt giống trong kho ngay.", function() local d = getData() local b = d and d.Inventory and d.Inventory.SeedPacks if b then for n in pairs(b) do task.spawn(function() fire(Net.SeedPack.OpenSeedPack, n) end) task.wait(0.15) end end setStatus("đã mở gói hạt") end)

    subTitle(R, "Ảnh Chụp Vườn")
    howItWorks(R, "Đứng ở bất kỳ khu vườn nào và chụp snapshot để ghi lại chính xác loại hạt giống và cách bố trí vật phẩm. Sau đó, bạn có thể chọn snapshot đó làm Nguồn Gieo Hạt ở tab Nông Trại để tự động gieo lại, hoặc dùng Tự Động Xây Dựng để tái tạo trang bị.")
    local snapName = "Snapshot 1"
    inputRow(R, "Tên Ảnh Chụp", "Đặt tên để lưu giữ ảnh chụp vườn.", snapName, "Ảnh Chụp 1", function(t) if t and t ~= "" then snapName = t end end)
    actionRow(R, "Chụp Khu Vườn Này", "Chụp lại bố cục khu vườn bạn đang đứng.", function()
        local ok, msg = captureSnapshot(snapName)
        if ok then
            notify('Đã lưu "' .. snapName .. '" - ' .. msg, "Ảnh Chụp Vườn", C.green)
            -- update plant source dropdown values instantly
            if plantSourceDropdown and plantSourceDropdown.refresh then plantSourceDropdown.refresh() end
        else
            setStatus(tostring(msg))
        end
    end)
    subTitle(R, "Tự Động Xây Dựng")
    toggleRow(R, "Tự Động Xây Theo Ảnh Chụp", "Đặt lại các trang bị/vật phẩm theo ảnh chụp (thử nghiệm).", "autoBuild")
    actionRow(R, "Xây Theo Ảnh Chụp Ngay", "Đặt trang bị theo ảnh chụp vườn một lần.", function() buildSnapshot() end)
    subTitle(R, "Dọn Dẹp Khu Vườn")
    dropdownRow(R, "Cây Cần Xóa", "Chọn loại cây cần nhổ, sau đó bấm Nhổ Cây Đã Chọn.", getPlantedOptions, S.removeCrops, nil, nil)
    actionRow(R, "Nhổ Cây Đã Chọn", "Chỉ đào những loại cây đã được tick ở trên.", function()
        if not next(S.removeCrops) then setStatus("hãy chọn cây trồng cần xóa trước") return end
        setStatus("đang dọn dẹp...") task.spawn(function() local n = removeSelectedPlants() setStatus("đã nhổ " .. n .. " cây") end)
    end)
    actionRow(R, "Nhổ Toàn Bộ Cây", "Đào bỏ toàn bộ cây trồng trong vườn nhà bạn.", function() setStatus("đang nhổ cây...") task.spawn(function() local n = removeAllPlants() setStatus("đã nhổ tất cả cây") end) end)
    actionRow(R, "Dọn Tất Cả Vật Phẩm", "Thu hồi mọi trang bị/vật phẩm trên ruộng nhà bạn.", function() setStatus("đang thu hồi vật phẩm...") task.spawn(function() local n = removeAllBuildings() setStatus("đã thu hồi tất cả vật phẩm") end) end)
end

-- PETS
do
    local p = addTab("Thú Cưng", "solar:bone-bold")
    local L, R = twoCol(p)
    colTitle(L, "Thu Phục"); subTitle(L, "Tự Động Thu Phục")
    howItWorks(L, "Tự động bay đến cưỡi và thuần hóa thú cưng hoang dã. Chọn loài cụ thể bạn muốn bắt, hoặc để trống để bắt mọi con thú xuất hiện.")
    toggleRow(L, "Tự Động Thu Phục Thú Hoang", "Tự động thu phục các loài thú cưng đã chọn.", "autoTame")
    dropdownRow(L, "Thú Cưng Cần Thu Phục", "Để trống = bắt tất cả.", getAnimalOptions, S.tameAnimals, nil, nil)

    colTitle(R, "Đeo Thú Cưng"); subTitle(R, "Tự Động Đeo Thú Cưng")
    howItWorks(R, "Tự động đeo các thú cưng bạn đã chọn. Số lượng tối đa phụ thuộc vào số ô thú cưng của bạn (bộ lọc hiển thị 1/3, 2/3, hoặc báo Đầy bằng màu đỏ).")
    toggleRow(R, "Tự Động Đeo Thú Cưng", "Luôn giữ cho thú cưng đã chọn được trang bị.", "autoEquipPets")
    dropdownRow(R, "Thú Cưng Cần Đeo", "Chọn số lượng thú cưng trong giới hạn của bạn.", getPetOptions, S.equipPets, nil, maxEquip)
    actionRow(R, "Đeo Thú Cưng Ngay", "Đeo toàn bộ thú cưng đã chọn ngay lập tức.", function()
        local n, mx = 0, maxEquip()
        for name in pairs(S.equipPets) do if n >= mx then break end fire(Net.Pets.RequestEquipByName, tostring(name)) n = n + 1 task.wait(0.12) end
        setStatus("đã đeo " .. n .. " thú cưng")
    end)
end

addGroup("Công Cụ")

-- STATS
do
    local p = addTab("Thống Kê", "solar:graph-new-bold")
    local L, R = twoCol(p)
    subTitle(L, "Theo Dõi Lợi Nhuận")
    local sMin = statRow(L, "Mỗi Phút", C.green)
    local sHr = statRow(L, "Mỗi Giờ", C.green)
    local sSess = statRow(L, "Trong Phiên Này", C.green)
    subTitle(R, "Kho Balo")
    local sInv = statRow(R, "Giá Trị Balo", C.green)
    local sCnt = statRow(R, "Số Lượng Trái Cây")
    local sBest = statRow(R, "Cây Tốt Nhất Để Gieo")
    actionRow(R, "Quét Lại Balo", "Tính toán lại giá trị balo của bạn ngay.", function() local v, n = inventoryValue() setStatus("balo trị giá " .. money(v) .. " (" .. n .. " quả)") end)
    spawnLoop(1, function()
        if not Window.Visible then return end
        sMin.Text = money(Profit.perMin); sHr.Text = money(Profit.perHr); sSess.Text = money(Profit.session)
        local v, n = inventoryValue(); sInv.Text = money(v); sCnt.Text = n .. "x"
        local best = bestOwnedSeed(); local d = getData(); local cnt = (best and d and d.Inventory and d.Inventory.Seeds and d.Inventory.Seeds[best]) or 0
        sBest.Text = best and (best .. "   " .. cnt .. "x") or "-"
    end)
end

-- TELEPORT
do
    local p = addTab("Dịch Chuyển", "solar:map-point-bold")
    local L, R = twoCol(p)
    colTitle(L, "Cửa Hàng & NPC"); subTitle(L, "Di Chuyển Nhanh")
    local function tpBtn(parent, label, pad)
        actionRow(parent, label, "Dịch chuyển tới " .. label .. ".", function()
            local t = Workspace:FindFirstChild("Teleports"); local d = t and t:FindFirstChild(pad)
            if d and d:IsA("BasePart") then reach(d.Position); setStatus("đã dịch chuyển tới " .. label) else setStatus(label .. " không tìm thấy") end
        end, "GO")
    end
    tpBtn(L, "Cửa Hàng Hạt Giống", "Seeds"); tpBtn(L, "Cửa Hàng Trang Bị", "Gears"); tpBtn(L, "NPC Bán Đồ", "Sell"); tpBtn(L, "Cửa Hàng Đồ Trí", "Props")
    colTitle(R, "Khu Vườn"); subTitle(R, "Về Nhà")
    actionRow(R, "Vườn Của Tôi", "Dịch chuyển về đất ruộng của bạn.", function() local plot = myPlot() local sp = plot and plot:FindFirstChild("SpawnPoint") if sp then reach(sp.Position) end setStatus("đã về nhà") end, "GO")
end

-- VISUAL
do
    local p = addTab("Hiển Thị", "solar:eye-bold")
    local L = oneCol(p)
    colTitle(L, "ESP & Cảnh Báo"); subTitle(L, "Visual")
    howItWorks(L, "Tạo viền sáng quanh cây trồng trên màn hình và cảnh báo khi shop có hạt hiếm. Bộ lọc ESP cây đột biến được giới hạn khoảng cách để tránh giật lag.")
    toggleRow(L, "Viền Cây Trồng Đã Chín", "Tạo viền đỏ quanh cây trồng đã chín nhà bạn.", "highlightReady")
    toggleRow(L, "Viền Quả Đột Biến", "Tạo viền vàng quanh quả đột biến/vàng ở gần.", "highlightRare")
    toggleRow(L, "Cảnh Báo Hồi Hạt Hiếm", "Gửi thông báo khi hạt giống đắt tiền xuất hiện trong shop.", "rareNotify")
end

addGroup("Người Chơi")

do
    local p = addTab("Người Chơi", "solar:walking-bold")
    local L, R = twoCol(p)
    subTitle(L, "Tốc Độ & Di Chuyển")
    howItWorks(L, "Game sẽ giới hạn tốc độ di chuyển của bạn, vì vậy hãy giữ tốc độ ở mức vừa phải. Hack di chuyển cũng được thực hiện qua các bước nhảy an toàn.")
    sliderRow(L, "Tốc Độ Đi Bộ", 16, 120, S.walkSpeed, 0, function(v) S.walkSpeed = v end)
    sliderRow(L, "Lực Nhảy", 50, 250, S.jumpPower, 0, function(v) S.jumpPower = v end)
    toggleRow(L, "Nhảy Vô Hạn", "Nhảy nhiều lần trên không trung.", "infJump")
    toggleRow(L, "Đi Xuyên Tường", "Đi xuyên qua tường và hàng rào.", "noclip", function(v) if not v then local c = char() if c then for _, pp in ipairs(c:GetDescendants()) do if pp:IsA("BasePart") then pp.CanCollide = true end end end end end)
    subTitle(R, "Bay Lượn")
    toggleRow(R, "Chế Độ Bay", "Tự do bay lượn bằng phím W/A/S/D, Space để bay lên, Ctrl để hạ xuống.", "fly", function(v) if not v and Hub.stopFly then Hub.stopFly() end end)
    sliderRow(R, "Tốc Độ Bay", 20, 150, S.flySpeed, 0, function(v) S.flySpeed = v end)
    subTitle(R, "Dịch Chuyển Nhanh")
    actionRow(R, "Về Vườn Nhà", "Dịch chuyển tức thời về plot ruộng của bạn.", function() local plot = myPlot() local sp = plot and plot:FindFirstChild("SpawnPoint") if sp then reach(sp.Position) end setStatus("đã dịch chuyển") end)
end

addGroup("Tiện Ích Khác")

do
    local p = addTab("Tiện Ích", "solar:settings-bold")
    local L = oneCol(p)
    colTitle(L, "Tiện Ích"); subTitle(L, "Tự Động Vận Hành Lũy Kế")
    howItWorks(L, "Tính năng auto tự vận hành: tự thu hoạch quả -> tự bán -> tự dùng tiền mua hạt giống tốt nhất -> tự gieo hạt phủ kín ruộng -> tự bắt thú cưng giá trị cao (Raccoon, Dragonfly...) khi xuất hiện. Giúp tiền và thú cưng của bạn tự sinh sôi.")
    toggleRow(L, "Tự Động Vận Hành Lũy Kế", "Tự thu hoạch, bán đồ, tái đầu tư và bắt thú hoang - hoàn toàn tự động.", "autoProgress")
    subTitle(L, "Tối Ưu Hiệu Năng")
    toggleRow(L, "Tối Ưu Hóa (FPS)", "Làm phẳng vật thể, bầu trời xám, tắt hiệu ứng - tăng mạnh FPS.", "optimize", setOptimize)
    subTitle(L, "Phiên Kết Nối")
    toggleRow(L, "Chống Treo Máy (AFK)", "Tránh việc bị ngắt kết nối khi treo máy quá 20 phút.", "antiAfk")
    actionRow(L, "Vào Lại Server", "Kết nối lại vào chính server hiện tại.", function() pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer) end) end)
    actionRow(L, "Chuyển Server", "Yêu cầu chuyển sang một server khác.", function() pcall(function() Net.AntiAfk.RequestHop:Fire() end) setStatus("đang yêu cầu chuyển server") end)
    subTitle(L, "Thông Tin")
    p:Paragraph({
        Title = "Thông Tin",
        Desc = "Bấm phím Right Shift để ẩn/hiện menu. Bấm nút Gỡ Bỏ Script để tắt hoàn toàn.\nUserId " .. LocalPlayer.UserId .. "   -   Plot " .. (myPlot() and myPlot().Name or "?")
    })
    actionRow(L, "Gỡ Bỏ Script", "Ngừng toàn bộ hoạt động của hack và đóng menu.", function() Hub.unload() end)
end

-- SERVER
do
    local p = addTab("Server & Webhook", "solar:server-bold")
    local L, R = twoCol(p)
    subTitle(L, "Chuyển Server")
    howItWorks(L, "Dịch chuyển sang server công khai khác - rất hữu ích khi săn hạt hiếm hoặc đợi sự kiện mới. Low-Pop sẽ tìm các server có ít người nhất.")
    actionRow(L, "Chuyển Server Công Khai", "Dịch chuyển sang một server ngẫu nhiên.", function() serverHop(false) end)
    actionRow(L, "Đến Server Ít Người", "Tìm và dịch chuyển tới server vắng nhất.", function() serverHop(true) end)
    toggleRow(L, "Tự Động Săn Hạt Hiếm", "Liên tục chuyển server cho đến khi shop bán hạt giá 5K+.", "autoHopRare")
    subTitle(R, "Gửi Tin Discord Webhook")
    howItWorks(R, "Dán địa chỉ Discord Webhook để nhận thông báo tự động về điện thoại/máy tính khi có sự kiện. Bật tắt các sự kiện bên dưới.")
    inputRow(R, "Địa Chỉ Webhook", "Dán Discord webhook để nhận thông tin.", S.webhookUrl, "https://discord.com/api/webhooks/...", function(t) S.webhookUrl = t end)
    toggleRow(R, "Báo Khi Có Hạt Hiếm Hồi Hàng", "Gửi tin nhắn khi hạt giống đắt tiền (5K+) xuất hiện.", "whRareSeed")
    actionRow(R, "Gửi Tin Nhắn Thử", "Post a test message to your webhook.", function() if sendWebhook("Tin nhắn thử nghiệm từ Khoa Dev > Grow a Garden 2 - Webhook hoạt động tốt!") then setStatus("đã gửi tin thử") else setStatus("hãy dán địa chỉ Webhook trước") end end)
end

--========================== INIT ==================================--
-- Background loop to refresh dropdown values dynamically
spawnLoop(3.5, function()
    if not Window.Visible then return end
    for _, item in ipairs(dropdownsToRefresh) do
        pcall(function()
            item.element:Refresh(getFormattedValues(item.getOptions, item.priceFn, item.getStockFn))
        end)
    end
end)

notify("Đã tải thành công - Nhấn phím Right Shift hoặc nút bấm trên màn hình để ẩn/hiện menu.", "Khoa Dev > Grow a Garden 2", C.accent)
setStatus("đã tải thành công - Nhấp Right Shift để ẩn/hiện")
print("[Khoa Dev > Grow a Garden 2] đã tải thành công.")

