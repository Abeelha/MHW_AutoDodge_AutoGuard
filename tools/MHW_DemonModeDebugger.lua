-- MHW_DemonModeDebugger.lua
-- Finds the persistent "is in demon mode" flag for Dual Blades in MHW_AutoDodge.
--
-- HOW TO USE:
--   1. Copy this file to reframework/autorun/
--   2. Equip Dual Blades, load a hunt, open REFramework UI -> [DemonDebug]
--   3. Stand still in NORMAL stance for a few seconds (baseline captured)
--   4. Click "Capture baseline" button
--   5. Enter demon mode
--   6. Watch the CHANGED list — anything that flipped is a candidate
--   7. Exit demon mode — confirm it flips back
--   8. Remove from autorun when done

local SCAN_TYPES = {
    "app.HunterCharacter",
    "app.CharacterBase",
    "app.MasterPlayer",
}

-- Also try these weapon/action related types
local EXTRA_TYPES = {
    "app.DualBladesCharacter",
    "app.DBCharacter",
    "app.WeaponCharacter",
    "app.HunterWeapon",
    "app.DualBladesWeapon",
}

local character    = nil
local masterPlayer = nil
local dumped       = false

local allGetters   = {}   -- { label, method, target_type }
local baseline     = {}   -- label -> value string
local current      = {}   -- label -> value string
local changed      = {}   -- label -> true if differs from baseline
local baselineCaptured = false
local changedList  = {}   -- ordered list of { label, was, now }

local function buildGetterList()
    local seen = {}

    local function scanType(typeName, targetType)
        local td = sdk.find_type_definition(typeName)
        if not td then return end
        for _, m in ipairs(td:get_methods()) do
            pcall(function()
                local name = m:get_name()
                local label = string.format('[%s] %s', typeName, name)
                if not seen[label] and (
                    name:sub(1, 4) == "get_" or
                    name:sub(1, 2) == "is" or
                    name:sub(1, 3) == "has"
                ) then
                    seen[label] = true
                    table.insert(allGetters, {
                        label      = label,
                        method     = name,
                        targetType = targetType,
                    })
                end
            end)
        end
    end

    for _, t in ipairs(SCAN_TYPES) do
        scanType(t, "character")
    end
    scanType("app.MasterPlayer", "masterplayer")

    log.info(string.format('[DemonDebug] Built getter list: %d methods', #allGetters))
end

local function pollAll()
    current = {}
    for _, g in ipairs(allGetters) do
        local target = (g.targetType == "masterplayer") and masterPlayer or character
        if target then
            local ok, val = pcall(function() return target:call(g.method) end)
            if ok and val ~= nil then
                local t = type(val)
                if t == "boolean" or t == "number" then
                    current[g.label] = tostring(val)
                end
            end
        end
    end
end

local function captureBaseline()
    baseline = {}
    for k, v in pairs(current) do
        baseline[k] = v
    end
    changed = {}
    changedList = {}
    baselineCaptured = true
    log.info(string.format('[DemonDebug] Baseline captured (%d values)', #allGetters))
end

local function updateChanged()
    changedList = {}
    for k, now in pairs(current) do
        local was = baseline[k]
        if was ~= nil and was ~= now then
            table.insert(changedList, { label = k, was = was, now = now })
            changed[k] = true
        end
    end
end

re.on_pre_application_entry('BeginRendering', function()
    pcall(function()
        local pm = sdk.get_managed_singleton('app.PlayerManager')
        if not pm then return end
        local mp = pm:getMasterPlayer()
        if not mp then return end
        masterPlayer = mp
        character = mp:get_Character()
    end)

    if not dumped and character then
        dumped = true
        buildGetterList()
    end

    if not character then return end
    pollAll()
    if baselineCaptured then updateChanged() end
end)

re.on_draw_ui(function()
    if not imgui.tree_node('[DemonDebug] Demon Mode Flag Finder') then return end

    if not character then
        imgui.text_colored('No character — load a hunt first', 0xFFAAAAFF)
        imgui.tree_pop()
        return
    end

    if dumped then
        imgui.text_colored(string.format('Getter list built: %d methods tracked', #allGetters), 0xFF44FF44)
    else
        imgui.text('Waiting for character...')
        imgui.tree_pop()
        return
    end

    imgui.spacing()
    imgui.text_colored('STEP 1: Stand still in NORMAL stance', 0xFFFFFF44)
    imgui.text_colored('STEP 2: Click Capture Baseline', 0xFFFFFF44)
    imgui.text_colored('STEP 3: Enter demon mode', 0xFFFFFF44)
    imgui.text_colored('STEP 4: Watch CHANGED list below', 0xFFFFFF44)
    imgui.spacing()

    if imgui.button('Capture Baseline (normal stance)') then
        captureBaseline()
    end

    if baselineCaptured then
        imgui.same_line()
        imgui.text_colored(string.format('Baseline: %d values', #allGetters), 0xFF44FF44)
    end

    imgui.spacing()
    imgui.separator()
    imgui.spacing()

    if not baselineCaptured then
        imgui.text_colored('Capture baseline first', 0xFFAAAAFF)
        imgui.tree_pop()
        return
    end

    imgui.text(string.format('Changed from baseline (%d):', #changedList))
    imgui.spacing()

    if #changedList == 0 then
        imgui.text_colored('No changes yet — enter demon mode', 0xFFAAAAAA)
    else
        imgui.indent(16)
        for _, c in ipairs(changedList) do
            local col = 0xFF44FF44
            imgui.text_colored(string.format('%s', c.label), col)
            imgui.indent(16)
            imgui.text_colored(string.format('was: %s   now: %s', c.was, c.now), 0xFFFFFF44)
            imgui.unindent(16)
        end
        imgui.unindent(16)
    end

    imgui.spacing()
    imgui.separator()
    imgui.spacing()
    imgui.text_colored('Look for a bool: false→true on demon enter, true→false on exit', 0xFFAAAAAA)
    imgui.text_colored('Or an int/enum that changes to a specific value', 0xFFAAAAAA)

    imgui.tree_pop()
end)
