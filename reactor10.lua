local function apiPath(path)
    if fs.exists(path) then return path end
    if fs.exists(path .. ".lua") then return path .. ".lua" end
    return nil
end

local function makeFallbackF()
    local api = {}

    local function targetFor(m)
        if m and m.monitor then return m.monitor end
        if m then return m end
        return term.current()
    end

    local function setColors(target, textColor, bgColor)
        if target.setTextColor and textColor then target.setTextColor(textColor) end
        if target.setBackgroundColor and bgColor then target.setBackgroundColor(bgColor) end
    end

    function api.periphSearch(peripheralType)
        if peripheral.find then
            local found = peripheral.find(peripheralType)
            if found then return found end
        end

        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == peripheralType then
                return peripheral.wrap(name)
            end
        end

        return nil
    end

    function api.firstSet(m)
        local target = targetFor(m)
        if target.setBackgroundColor then target.setBackgroundColor(colors.black) end
        if target.setTextColor then target.setTextColor(colors.white) end
        _G.__reactorButtonTarget = target
    end

    function api.draw_line(m, x1, y, x2, color)
        local target = targetFor(m)
        if x2 < x1 then x1, x2 = x2, x1 end
        setColors(target, colors.white, color)
        target.setCursorPos(x1, y)
        target.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
    end

    function api.draw_line_y(m, x, y1, y2, color)
        local target = targetFor(m)
        if y2 < y1 then y1, y2 = y2, y1 end
        setColors(target, colors.white, color)
        for y = y1, y2 do
            target.setCursorPos(x, y)
            target.write(" ")
        end
    end

    function api.draw_text(m, x, y, text, textColor, bgColor)
        local target = targetFor(m)
        setColors(target, textColor, bgColor)
        target.setCursorPos(x, y)
        target.write(tostring(text or ""))
    end

    function api.draw_text_lr(m, x, y, spacing, label, value, labelColor, valueColor, bgColor)
        local target = targetFor(m)
        local labelText = tostring(label or "")
        local valueText = tostring(value or "")

        setColors(target, labelColor, bgColor)
        target.setCursorPos(x, y)
        target.write(labelText)

        setColors(target, valueColor, bgColor)
        target.setCursorPos(x + string.len(labelText) + (spacing or 1), y)
        target.write(valueText)
    end

    function api.progress_bar(m, x, y, width, value, maxValue, barColor, bgColor)
        local target = targetFor(m)
        width = math.max(0, math.floor(width or 0))
        maxValue = maxValue or 100
        value = value or 0

        local ratio = 0
        if maxValue > 0 then
            ratio = value / maxValue
            if ratio < 0 then ratio = 0 end
            if ratio > 1 then ratio = 1 end
        end

        local filled = math.floor(ratio * width + 0.5)

        setColors(target, colors.white, barColor)
        target.setCursorPos(x, y)
        target.write(string.rep(" ", filled))

        setColors(target, colors.white, bgColor)
        target.write(string.rep(" ", math.max(0, width - filled)))
    end

    function api.format_int(value)
        local text = tostring(math.floor(tonumber(value) or 0))
        local sign, digits = text:match("^(-?)(%d+)$")
        if not digits then return text end

        local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        formatted = formatted:gsub("^,", "")
        return sign .. formatted
    end

    return api
end

local function makeFallbackButton()
    local api = {}
    local buttons = {}

    local function getTarget()
        return _G.__reactorButtonTarget or term.current()
    end

    local function drawButton(btn)
        local target = getTarget()
        local width = math.max(1, btn.x2 - btn.x1 + 1)
        local height = math.max(1, btn.y2 - btn.y1 + 1)
        local textY = btn.y1 + math.floor((height - 1) / 2)
        local textX = btn.x1 + math.floor(math.max(0, width - string.len(btn.label)) / 2)

        target.setBackgroundColor(btn.color or colors.blue)
        target.setTextColor(colors.white)
        for y = btn.y1, btn.y2 do
            target.setCursorPos(btn.x1, y)
            target.write(string.rep(" ", width))
        end

        target.setCursorPos(textX, textY)
        target.write(btn.label)
        target.setBackgroundColor(colors.black)
    end

    function api.bindMonitor(target)
        _G.__reactorButtonTarget = target
    end

    function api.clearTable()
        buttons = {}
    end

    function api.setButton(id, label, callback, x1, y1, x2, y2, arg1, arg2, color)
        buttons[id] = {
            label = tostring(label or id),
            callback = callback,
            x1 = math.min(x1, x2),
            y1 = math.min(y1, y2),
            x2 = math.max(x1, x2),
            y2 = math.max(y1, y2),
            arg1 = arg1,
            arg2 = arg2,
            color = color
        }
        drawButton(buttons[id])
    end

    function api.screen()
        for _, btn in pairs(buttons) do
            drawButton(btn)
        end
    end

    function api.clickEvent()
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            local x, y

            if event == "monitor_touch" then
                x, y = p2, p3
            elseif event == "mouse_click" then
                x, y = p2, p3
            end

            if x and y then
                for _, btn in pairs(buttons) do
                    if x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2 then
                        btn.callback(btn.arg1, btn.arg2)
                        break
                    end
                end
            end
        end
    end

    return api
end

local function loadApiOrFallback(path, globalName, fallback)
    local resolved = apiPath(path)
    if resolved then
        local ok, err = pcall(os.loadAPI, resolved)
        if not ok then
            error("Failed to load optional API " .. globalName .. ": " .. tostring(err), 0)
        end
    end

    if _G[globalName] then return _G[globalName] end
    if _G[globalName .. ".lua"] then return _G[globalName .. ".lua"] end

    _G[globalName] = fallback
    return fallback
end

local f = loadApiOrFallback("lib/f", "f", makeFallbackF())
local button = loadApiOrFallback("lib/button", "button", makeFallbackButton())

local startupFieldTarget = 50
local minOptimizedFieldTarget = 10
local maxTemp = 8000
local safeTemp = 3000
local lowFieldPer = 10

local activateOnCharge = true
local version = 0.48

local autoInputGate = 1
local curInputGate = 222000

-- Auto Output and Balance Mode
-- Behavior when Auto is ON:
-- 1) Startup latch (only when truly starting cold): input >= 1.2M and output = 0 until field and saturation reach 99% once
-- 2) Ramp quickly but smoothly to 4M output while maintaining 50% field
-- 3) Above 4M, wait for temperature to start falling, then add small output steps
-- 4) Above 5M, slowly lower field target toward 10% as an input-efficiency lever
-- 5) Stress response: hold or gently trim output; emergency shutdown remains latched

local autoOutputGate = 0
local autoOutputTarget = 0

local outputCap = 1000000000
local inputCap = 5000000

local minChargeInput = 1200000
local baseOutput = 500000
local baselineOutput = 4000000
local fieldOptimizeStartOutput = 5000000

local chargeFieldMin = 99
local chargeSatMin = 99

-- Operating temperature band
local opTempLow = 6200
local opTempHigh = 7400
local opTempHys = 75

-- Steps and pacing
local autoInterval = 1.0
local lastAutoAdjust = 0

local holdOutStep = 50000
local autoInStep = 25000
local outputRiseLimit = 250000
local outputStepAfterBaseline = 50000
local outputStepCooldown = 10
local outputDropLimit = 250000
local outputSettleRatio = 0.95

-- Warm-up tuning (fast to enter band, but limit rate of climb)
local warmMinStep = 10000
local warmMaxStep = 150000
local warmGain = 100

local warmMaxRiseRate = 20    -- C/sec: at or above this, stop increasing output
local warmBrakeRate = 35      -- C/sec: at or above this, reduce output

local prevTemp = nil
local prevTempTime = nil

-- Field response
local fieldHys = 0.25
local fieldBoostPerPct = 150000
local fieldOutputHeadroom = 2.0
local fieldPanicBuffer = 3.0
local baselineFieldRaiseMin = 40
local baselineFieldTrimMin = 35
local fieldOutputSoftMin = 25
local fieldTrimBuffer = 3.0

-- Optimizer behavior
local activeFieldTarget = startupFieldTarget
local optimizerMode = "Idle"
local optimizerStableTicks = 0
local baselineStableTicks = 0
local optimizationUnlocked = false
local lastControlStepTime = 0
local lastNetEstimate = 0
local bestNetEstimate = 0
local opToFeMultiplier = nil
local opToFeConfigPath = nil
local lastOpToFeConfigCheck = 0
local opToFeConfigCheckInterval = 10
local opToFeConfigNames = {
    "config/draconic-mekanism-reactor-patch.properties",
    "/config/draconic-mekanism-reactor-patch.properties",
    "draconic-mekanism-reactor-patch.properties"
}
local opToFeSettingNames = {
    "draconic_mekanism_reactor_patch.opToFeMultiplier",
    "draconic-mekanism-reactor-patch.opToFeMultiplier",
    "opToFeMultiplier"
}
local opToFePeripheralMethods = {
    "getOpToFeMultiplier",
    "getOPToFEMultiplier",
    "opToFeMultiplier",
    "getFePerOp",
    "getFEPerOP",
    "getForgeEnergyMultiplier"
}
local baselineStableSamples = 20
local optimizeStableSamples = 30
local fieldLowerStep = 0.25
local fieldRaiseStep = 2.5
local fieldTrimHeadroom = 1.0
local optimizeStableRiseRate = 5
local optimizeMaxRiseRate = 12
local tempFallThreshold = -0.25
local lowTempFastRamp = 5500
local midTempFastRamp = 6500
local satOptimizeMin = 55

-- Saturation guardrails
local satHardMin = 25         -- if saturation drops below this, back off output
local satSoftMin = 40

-- Safety/state latches
local safetyShutdownLatched = false
local shutdownReason = ""
local startupArmed = false

-- Latches
local chargedOnce = false

local mon, monitor, monX, monY

local reactor
local fluxgate
local inputFluxgate

local ri

local action = "None since reboot"
local actioncolor = colors.gray

monitor = f.periphSearch("monitor")
reactor = f.periphSearch("draconic_reactor")

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function isRunningStatus(s)
    return s == "running" or s == "online"
end

local function isChargingStatus(s)
    return s == "warming_up" or s == "charging" or s == "charged"
end

local function inAuto()
    return autoOutputGate == 1
end

local function nowSec()
    if os.epoch then
        return os.epoch("utc") / 1000
    end
    return os.clock()
end

function detectFlowGates()
    local gates = {peripheral.find("flow_gate")}
    if #gates < 2 then
        error("Error: Less than 2 flow gates detected!")
        return nil, nil
    end

    print("Please set input flow gate to 10 OP/t manually.")

    local inputGate, outputGate, inputName, outputName

    while not inputGate do
        sleep(1)
        for _, name in pairs(peripheral.getNames()) do
            if peripheral.getType(name) == "flow_gate" then
                local gate = peripheral.wrap(name)
                local setFlow = gate.getSignalLowFlow()

                if setFlow == 10 then
                    inputGate, inputName = gate, name
                    print("Detected input gate:", name)
                else
                    outputGate, outputName = gate, name
                end
            end
        end
    end

    if not outputGate then
        print("Error: Could not identify output gate!")
        return nil, nil
    end

    return inputGate, outputGate, inputName, outputName
end

function saveFlowGateNames(inputName, outputName)
    local file = fs.open("flowgate_names.txt", "w")
    file.writeLine(inputName)
    file.writeLine(outputName)
    file.close()
    print("Saved flow gate names for reboot!")
end

function loadFlowGateNames()
    if not fs.exists("flowgate_names.txt") then
        print("No saved flow gate names found. Running detection again...")
        return nil, nil, nil, nil
    end

    local file = fs.open("flowgate_names.txt", "r")
    local inputName = file.readLine()
    local outputName = file.readLine()
    file.close()

    print("Loaded saved flow gate names:", inputName, outputName)

    if peripheral.isPresent(inputName) and peripheral.isPresent(outputName) then
        return peripheral.wrap(inputName), peripheral.wrap(outputName), inputName, outputName
    else
        print("Saved peripherals not found. Running detection again...")
        return nil, nil, nil, nil
    end
end

function setupFlowGates()
    local inGate, outGate, inputName, outputName = loadFlowGateNames()

    if not inGate or not outGate then
        inGate, outGate, inputName, outputName = detectFlowGates()
        if inGate and outGate then
            saveFlowGateNames(inputName, outputName)
        else
            error("Flow gate setup failed. Set the input flow gate to 10 before running again.")
            return nil, nil
        end
    end

    return inGate, outGate
end

inputFluxgate, fluxgate = setupFlowGates()

if monitor == nil then error("No valid monitor was found") end
if fluxgate == nil then error("No valid flow gate was found") end
if inputFluxgate == nil then error("No input flow gate was found. Set low signal value to 10") end
if reactor == nil then error("No reactor was found") end

monX, monY = monitor.getSize()
mon = {}
mon.monitor, mon.X, mon.Y = monitor, monX, monY

if button.bindMonitor then button.bindMonitor(monitor) end
f.firstSet(mon)

function mon.clear()
    mon.monitor.setBackgroundColor(colors.black)
    mon.monitor.clear()
    mon.monitor.setCursorPos(1,1)
    button.screen()
end

function save_config()
    local sw = fs.open("reactorconfig.txt", "w")
    sw.writeLine(autoInputGate or 1)
    sw.writeLine(curInputGate or 222000)

    sw.writeLine(autoOutputGate or 0)
    sw.writeLine(autoOutputTarget or fluxgate.getSignalLowFlow() or 0)
    sw.writeLine(outputCap or 1000000000)
    sw.writeLine(inputCap or 5000000)
    sw.writeLine(safetyShutdownLatched and 1 or 0)
    sw.writeLine(shutdownReason or "")

    sw.close()
end

function load_config()
    local sr = fs.open("reactorconfig.txt", "r")
    autoInputGate = tonumber(sr.readLine() or "1")
    curInputGate = tonumber(sr.readLine() or "222000")

    autoOutputGate = tonumber(sr.readLine() or "0")
    autoOutputTarget = tonumber(sr.readLine() or tostring(fluxgate.getSignalLowFlow() or 0))
    outputCap = tonumber(sr.readLine() or "1000000000")
    inputCap = tonumber(sr.readLine() or "5000000")
    safetyShutdownLatched = tonumber(sr.readLine() or "0") == 1
    shutdownReason = sr.readLine() or ""

    sr.close()

    if autoOutputTarget < 0 then autoOutputTarget = 0 end
    if autoOutputTarget > outputCap then autoOutputTarget = outputCap end
    if safetyShutdownLatched then autoOutputGate = 0 end
end

if fs.exists("reactorconfig.txt") == false then
    autoOutputTarget = fluxgate.getSignalLowFlow()
    save_config()
else
    load_config()
end

if safetyShutdownLatched and shutdownReason ~= "" then
    action = shutdownReason .. " Manual restart required."
    actioncolor = colors.red
end

function reset()
    term.clear()
    term.setCursorPos(1,1)
end

function reactorStatus(r)
    local statusTable = {
        running = {"Online", colors.green},
        online = {"Online", colors.green},
        cold = {"Offline", colors.gray},
        warming_up = {"Charging", colors.orange},
        charging = {"Charging", colors.orange},
        charged = {"Charged", colors.orange},
        cooling = {"Cooling Down", colors.blue},
        stopping = {"Shutting Down", colors.red}
    }
    return statusTable[r] or statusTable["stopping"]
end

local lastTerminalValues = {}

function drawTerminalText(x, y, label, newValue)
    local key = label
    local asText = tostring(newValue)
    if lastTerminalValues[key] ~= asText then
        term.setCursorPos(x, y)
        term.clearLine()
        term.write(label .. ": " .. asText)
        lastTerminalValues[key] = asText
    end
end

function getPercentage(value, maxValue)
    if not maxValue or maxValue == 0 then return 0 end
    return math.ceil(value / maxValue * 10000) * 0.01
end

function formatPercent(value, places)
    return string.format("%."..(places or 2).."f", tonumber(value) or 0)
end

function trimText(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function parseOpToFeMultiplier(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end

    local file = fs.open(path, "r")
    if not file then return nil end

    while true do
        local line = file.readLine()
        if not line then break end

        line = trimText(line)
        if line ~= "" and not line:match("^[#!]") then
            local key, value = line:match("^([^:=]+)%s*[:=]%s*(.-)%s*$")
            if key and trimText(key) == "opToFeMultiplier" then
                value = trimText(value):gsub("[fFdDlL]$", "")
                file.close()
                return tonumber(value)
            end
        end
    end

    file.close()
    return nil
end

function normalizePositiveNumber(value)
    if type(value) == "string" then
        value = trimText(value):gsub("[fFdDlL]$", "")
    end

    local number = tonumber(value)
    if number and number > 0 then return number end
    return nil
end

function getOpToFeFromSettings()
    if not settings or type(settings.get) ~= "function" then return nil end

    for _, name in ipairs(opToFeSettingNames) do
        local multiplier = normalizePositiveNumber(settings.get(name))
        if multiplier then return multiplier, "setting:"..name end
    end

    return nil
end

function getOpToFeFromPeripheral(periph, label)
    if not periph then return nil end

    for _, method in ipairs(opToFePeripheralMethods) do
        local fn = periph[method]
        if type(fn) == "function" then
            local ok, value = pcall(fn)
            if not ok then
                ok, value = pcall(fn, periph)
            end
            local multiplier = ok and normalizePositiveNumber(value) or nil
            if multiplier then return multiplier, label.."."..method end
        end
    end

    return nil
end

function getOpToFeFromPeripherals()
    local multiplier, source = getOpToFeFromPeripheral(reactor, "reactor")
    if multiplier then return multiplier, source end

    multiplier, source = getOpToFeFromPeripheral(fluxgate, "outputGate")
    if multiplier then return multiplier, source end

    multiplier, source = getOpToFeFromPeripheral(inputFluxgate, "inputGate")
    if multiplier then return multiplier, source end

    return nil
end

function getOpToFeMultiplier()
    local now = nowSec()
    if (now - lastOpToFeConfigCheck) < opToFeConfigCheckInterval then
        return opToFeMultiplier, opToFeConfigPath
    end

    lastOpToFeConfigCheck = now
    opToFeMultiplier = nil
    opToFeConfigPath = nil

    opToFeMultiplier, opToFeConfigPath = getOpToFeFromPeripherals()
    if opToFeMultiplier then return opToFeMultiplier, opToFeConfigPath end

    opToFeMultiplier, opToFeConfigPath = getOpToFeFromSettings()
    if opToFeMultiplier then return opToFeMultiplier, opToFeConfigPath end

    for _, path in ipairs(opToFeConfigNames) do
        local multiplier = parseOpToFeMultiplier(path)
        if multiplier and multiplier > 0 then
            opToFeMultiplier = multiplier
            opToFeConfigPath = path
            break
        end
    end

    return opToFeMultiplier, opToFeConfigPath
end

function getFuelPercent(ri)
    if not ri then return 0 end
    return 100 - getPercentage(ri.fuelConversion, ri.maxFuelConversion)
end

function getInputForFieldTarget(ri, fieldTarget)
    if not ri then return curInputGate end

    local fieldDrainRate = tonumber(ri.fieldDrainRate) or 0
    local target = clamp(fieldTarget or startupFieldTarget, minOptimizedFieldTarget, 95)
    return fieldDrainRate / (1 - (target / 100))
end

function outputHasSettled(outputFlow, generationRate)
    outputFlow = tonumber(outputFlow) or 0
    generationRate = tonumber(generationRate) or 0

    if outputFlow <= baseOutput then return true end
    return generationRate >= (outputFlow * outputSettleRatio)
end

function resetOptimizer(mode)
    activeFieldTarget = startupFieldTarget
    optimizerStableTicks = 0
    baselineStableTicks = 0
    optimizationUnlocked = false
    lastControlStepTime = 0
    lastNetEstimate = 0
    bestNetEstimate = 0
    optimizerMode = mode or "Idle"
end

function updateOptimizerState(fieldPct, satPct, temp, riseRate, currentOut, currentIn, generationRate, now)
    activeFieldTarget = clamp(activeFieldTarget, minOptimizedFieldTarget, startupFieldTarget)
    lastNetEstimate = (currentOut or 0) - (currentIn or 0)
    if lastNetEstimate > bestNetEstimate then
        bestNetEstimate = lastNetEstimate
    end

    local fieldDanger = fieldPct <= (lowFieldPer + fieldPanicBuffer)
    local tempDanger = temp >= (maxTemp - 500)
    local satDanger = satPct <= satHardMin
    local fastHeat = riseRate >= warmBrakeRate

    if fieldDanger or tempDanger or satDanger or fastHeat then
        activeFieldTarget = clamp(activeFieldTarget + (fieldRaiseStep * 2), minOptimizedFieldTarget, startupFieldTarget)
        optimizerStableTicks = 0
        optimizerMode = "Recover"
        return
    end

    local output = currentOut or 0
    local tempFalling = riseRate <= tempFallThreshold
    local stepReady = tempFalling and (((now or nowSec()) - lastControlStepTime) >= outputStepCooldown)
    local tempHot = temp > opTempHigh
    local fieldWeak = fieldPct < fieldOutputSoftMin
    local heatingFast = riseRate >= optimizeMaxRiseRate

    if fieldWeak or tempHot or heatingFast then
        if fieldPct < activeFieldTarget then
            activeFieldTarget = clamp(activeFieldTarget + fieldRaiseStep, minOptimizedFieldTarget, startupFieldTarget)
        end

        optimizerStableTicks = 0
        if tempHot then
            optimizerMode = "Temp Trim"
        elseif heatingFast then
            optimizerMode = "Temp Hold"
        else
            optimizerMode = "Field Recover"
        end
        return
    end

    if output < baselineOutput then
        activeFieldTarget = startupFieldTarget
        optimizationUnlocked = false
        optimizerStableTicks = 0
        optimizerMode = "Ramp 4M"
        return
    end

    if output < fieldOptimizeStartOutput then
        activeFieldTarget = startupFieldTarget
        optimizationUnlocked = false
        optimizerStableTicks = 0

        if stepReady then
            optimizerMode = "Step Climb"
        elseif tempFalling then
            optimizerMode = "Step Wait"
        else
            optimizerMode = "Wait Cool"
        end
        return
    end

    optimizationUnlocked = true

    if tempFalling and fieldPct >= (activeFieldTarget + fieldTrimHeadroom) and satPct >= satOptimizeMin and lastNetEstimate > 0 then
        optimizerStableTicks = optimizerStableTicks + 1
        if optimizerStableTicks >= optimizeStableSamples then
            optimizerStableTicks = 0
            if activeFieldTarget > minOptimizedFieldTarget then
                activeFieldTarget = clamp(activeFieldTarget - fieldLowerStep, minOptimizedFieldTarget, startupFieldTarget)
                lastControlStepTime = now or nowSec()
                optimizerMode = "Field Trim"
            elseif stepReady then
                optimizerMode = "Step Climb"
            else
                optimizerMode = "Step Wait"
            end
        elseif stepReady then
            optimizerMode = "Step Climb"
        else
            optimizerMode = "Step Wait"
        end
    else
        optimizerStableTicks = 0
        optimizerMode = "Wait Cool"
    end
end

function reactorReadyToActivate(ri)
    if not ri then return false end

    local fieldPct = getPercentage(ri.fieldStrength, ri.maxFieldStrength)
    local satPct = getPercentage(ri.energySaturation, ri.maxEnergySaturation)

    return fieldPct >= chargeFieldMin and satPct >= chargeSatMin
end

function clearSafetyLatch()
    safetyShutdownLatched = false
    shutdownReason = ""
    resetOptimizer("Manual Reset")
    action = "Safety latch cleared by manual restart"
    actioncolor = colors.orange
end

-- Toggle Auto:
-- OFF: disables auto immediately, does not reset anything, does not touch output
-- ON: enables auto and immediately resumes the auto program from current output level
function toggleAutoOutput()
    if autoOutputGate == 1 then
        autoOutputGate = 0

        -- Do not modify output or input here. Leave everything exactly where it is.
        action = "Auto output disabled"
        actioncolor = colors.gray

        -- Keep autoOutputTarget as the last known output for when auto is re-enabled
        autoOutputTarget = fluxgate.getSignalLowFlow()

    else
        if safetyShutdownLatched then
            action = "Safety latch active. Manual restart required."
            actioncolor = colors.red
            ActionMenu()
            return
        end

        autoOutputGate = 1

        -- Start from whatever the current output is (manual state)
        autoOutputTarget = fluxgate.getSignalLowFlow()

        -- Allow auto to act immediately and compute temperature rise rate cleanly
        lastAutoAdjust = 0
        prevTemp = nil
        prevTempTime = nil
        resetOptimizer("Auto Enabled")

        action = "Auto output enabled"
        actioncolor = colors.lime
    end

    save_config()

    if currentMenu == "output" then
        outputMenu()
        return
    elseif currentMenu == "controls" then
        buttonControls()
    end
end

function handleAutoProgram(ri)
    if not inAuto() then return end
    if safetyShutdownLatched then return end
    if not ri or not isRunningStatus(ri.status) then
        chargedOnce = false
        prevTemp = nil
        prevTempTime = nil
        resetOptimizer("Idle")
        return
    end

    local now = nowSec()
    if (now - lastAutoAdjust) < autoInterval then return end
    lastAutoAdjust = now

    local fieldPct = getPercentage(ri.fieldStrength, ri.maxFieldStrength)
    local satPct = getPercentage(ri.energySaturation, ri.maxEnergySaturation)
    local temp = ri.temperature or 0
    local generationRate = tonumber(ri.generationRate) or 0

    -- Temperature rise rate (C/sec)
    local riseRate = 0
    if prevTemp ~= nil and prevTempTime ~= nil then
        local dt = now - prevTempTime
        if dt > 0 then
            riseRate = (temp - prevTemp) / dt
        end
    end

    local currentIn = clamp(inputFluxgate.getSignalLowFlow(), 0, inputCap)
    local currentOut = clamp(fluxgate.getSignalLowFlow(), 0, outputCap)

    updateOptimizerState(fieldPct, satPct, temp, riseRate, currentOut, currentIn, generationRate, now)

    local controlTarget = activeFieldTarget
    local baseInput = autoInputGate == 1
        and getInputForFieldTarget(ri, controlTarget)
        or curInputGate

    local desiredIn = clamp(baseInput or currentIn, 0, inputCap)
    local desiredOut = currentOut
    local forceOutputCut = false

    -- Hard safety temperature governor
    if fieldPct <= (lowFieldPer + fieldPanicBuffer) then
        desiredOut = 0
        desiredIn = inputCap
        forceOutputCut = true
    elseif temp >= (maxTemp - 50) then
        desiredOut = 0
        desiredIn = math.min(inputCap, desiredIn + (autoInStep * 10))
        forceOutputCut = true
    elseif temp >= (maxTemp - 500) then
        desiredOut = math.max(0, desiredOut - outputDropLimit)
        desiredIn = math.min(inputCap, desiredIn + (autoInStep * 10))
    else
        chargedOnce = true

        -- Running means productive. Seed output, then let safety governors trim it.
        if desiredOut < baseOutput then
            desiredOut = baseOutput
        end

        local fieldTrimLine
        fieldTrimLine = math.max(lowFieldPer + fieldPanicBuffer, fieldOutputSoftMin)

        -- Maintain the current field target. A normal dip adds input; only a soft danger dip trims output.
        if fieldPct < (controlTarget - fieldHys) then
            local deficit = controlTarget - fieldPct
            desiredIn = math.min(inputCap, desiredIn + (deficit * fieldBoostPerPct))

            if fieldPct <= fieldTrimLine then
                desiredIn = inputCap
                desiredOut = math.max(0, desiredOut - outputDropLimit)
            end
        elseif fieldPct > (controlTarget + fieldOutputHeadroom + 2) then
            desiredIn = math.max(0, desiredIn - autoInStep)
        end

        -- Saturation guardrails
        if satPct <= satHardMin then
            desiredOut = math.max(0, desiredOut - outputDropLimit)
        end

        local fieldCanRaise = fieldPct > fieldTrimLine
        local heatCanRaise = riseRate < warmBrakeRate and temp < opTempHigh
        local satCanRaise = satPct > satHardMin

        if temp > opTempHigh then
            desiredOut = math.max(baseOutput, desiredOut - outputStepAfterBaseline)
        elseif riseRate >= warmBrakeRate then
            desiredOut = math.max(baseOutput, desiredOut - holdOutStep)
        elseif fieldCanRaise and heatCanRaise and satCanRaise then
            local step

            if currentOut < baselineOutput then
                step = outputRiseLimit
                desiredOut = math.min(baselineOutput, desiredOut + step)
            elseif optimizerMode == "Step Climb" then
                step = outputStepAfterBaseline
                desiredOut = math.min(outputCap, desiredOut + step)
            else
                step = 0
            end
        end
    end

    desiredIn = clamp(math.floor(desiredIn + 0.5), 0, inputCap)
    desiredOut = clamp(math.floor(desiredOut + 0.5), 0, outputCap)

    if forceOutputCut then
        desiredOut = 0
    elseif desiredOut > currentOut then
        local riseLimit = currentOut < baselineOutput and outputRiseLimit or outputStepAfterBaseline
        desiredOut = math.min(desiredOut, currentOut + riseLimit)
    elseif desiredOut < currentOut then
        desiredOut = math.max(desiredOut, currentOut - outputDropLimit)
    end

    if desiredOut > currentOut then
        lastControlStepTime = now
    end

    inputFluxgate.setSignalLowFlow(desiredIn)
    fluxgate.setSignalLowFlow(desiredOut)

    autoOutputTarget = desiredOut
    curInputGate = desiredIn

    prevTemp = temp
    prevTempTime = now
end

function reactorControl()
    reset()

    while true do
        local info = reactor.getReactorInfo()
        if not info then
            print("Reactor not setup correctly. Retrying in 2s...")
            sleep(2)
            goto continue
        end

        ri = info

        local i = 1
        for k, v in pairs(ri) do
            drawTerminalText(1, i, k, v)
            i = i + 1
        end

        i = i + 1
        drawTerminalText(1, i, "Output Gate", fluxgate.getSignalLowFlow())
        i = i + 1
        drawTerminalText(1, i, "Input Gate", inputFluxgate.getSignalLowFlow())
        i = i + 1
        drawTerminalText(1, i, "Auto Output", inAuto() and "ON" or "OFF")
        i = i + 1
        drawTerminalText(1, i, "Charged Once", chargedOnce and "YES" or "NO")
        i = i + 1
        drawTerminalText(1, i, "Safety Latch", safetyShutdownLatched and "ON" or "OFF")
        i = i + 1
        drawTerminalText(1, i, "Startup Armed", startupArmed and "YES" or "NO")

        if not checkReactorSafety(ri) then
            sleep(0.2)
            goto continue
        end

        if safetyShutdownLatched then
            startupArmed = false
            chargedOnce = false
            prevTemp = nil
            prevTempTime = nil
            resetOptimizer("Locked")

            if inAuto() then
                autoOutputGate = 0
                save_config()
            end

            fluxgate.setSignalLowFlow(0)
            if ri.status ~= "cold" then
                inputFluxgate.setSignalLowFlow(inputCap)
            end

            if isRunningStatus(ri.status) then
                reactor.stopReactor()
            end

            sleep(0.2)
            goto continue
        end

        if startupArmed and isChargingStatus(ri.status) then
            inputFluxgate.setSignalLowFlow(minChargeInput)
            fluxgate.setSignalLowFlow(0)
            resetOptimizer("Charging")

            if activateOnCharge and reactorReadyToActivate(ri) then
                reactor.activateReactor()
                startupArmed = false
                action = "Startup charged; activating reactor"
                actioncolor = colors.lime
            end
        elseif isChargingStatus(ri.status) then
            inputFluxgate.setSignalLowFlow(minChargeInput)
            fluxgate.setSignalLowFlow(0)
            resetOptimizer("Charging")
        end

        if isRunningStatus(ri.status) then
            startupArmed = false

            local baseInput = autoInputGate == 1
                and getInputForFieldTarget(ri, inAuto() and activeFieldTarget or startupFieldTarget)
                or curInputGate

            i = i + 1
            drawTerminalText(1, i, "Base Input", math.floor(baseInput))

            if inAuto() then
                handleAutoProgram(ri)

                i = i + 1
                drawTerminalText(1, i, "Auto Target", autoOutputTarget)
                i = i + 1
                drawTerminalText(1, i, "Field Target", formatPercent(activeFieldTarget, 2).."%")
                i = i + 1
                drawTerminalText(1, i, "Power Mode", optimizerMode)

                i = i + 1
                drawTerminalText(1, i, "Applied In", inputFluxgate.getSignalLowFlow())

                i = i + 1
                drawTerminalText(1, i, "Applied Out", fluxgate.getSignalLowFlow())
            else
                inputFluxgate.setSignalLowFlow(baseInput)

                i = i + 1
                drawTerminalText(1, i, "Target Gate", math.floor(baseInput))
            end
        else
            chargedOnce = false
            prevTemp = nil
            prevTempTime = nil
            resetOptimizer("Idle")
        end

        checkReactorSafety(ri)

        sleep(0.2)
        ::continue::
    end
end

function checkReactorSafety(ri)
    if not ri then return false end

    local fuelPercent = getFuelPercent(ri)
    local fieldPercent = getPercentage(ri.fieldStrength, ri.maxFieldStrength)

    if fuelPercent <= 10 then
        emergencyShutdown("Fuel Low! Refuel Now!")
        return false
    elseif fieldPercent <= lowFieldPer and isRunningStatus(ri.status) then
        emergencyShutdown("Field Strength Below "..lowFieldPer.."%!")
        return false
    elseif (ri.temperature or 0) >= maxTemp and isRunningStatus(ri.status) then
        emergencyShutdown("Reactor Overheated!")
        return false
    end

    return true
end

function emergencyShutdown(message)
    if safetyShutdownLatched and shutdownReason == message then
        return
    end

    safetyShutdownLatched = true
    shutdownReason = message or "Safety shutdown"
    startupArmed = false
    autoOutputGate = 0
    chargedOnce = false
    prevTemp = nil
    prevTempTime = nil
    resetOptimizer("Emergency")

    pcall(function() fluxgate.setSignalLowFlow(0) end)
    pcall(function() inputFluxgate.setSignalLowFlow(inputCap) end)

    pcall(function() reactor.stopReactor() end)
    actioncolor = colors.red
    action = shutdownReason .. " Manual restart required."
    save_config()
    ActionMenu()
end

local MenuText = "Loading..."

function clearMenuArea()
    for i = 26, monY-1 do
        f.draw_line(mon, 2, i, monX-2, colors.black)
    end
    button.clearTable()

    f.draw_line(mon, 2, 26, monX-2, colors.gray)
    f.draw_line(mon, 2, monY-1, monX-2, colors.gray)
    f.draw_line_y(mon, 2, 26, monY-1, colors.gray)
    f.draw_line_y(mon, monX-1, 26, monY-1, colors.gray)
    f.draw_text(mon, 4, 26, " "..MenuText.." ", colors.white, colors.black)
end

function toggleReactor()
    ri = reactor.getReactorInfo()
    if not ri then
        action = "No reactor info. Cannot toggle."
        actioncolor = colors.red
        ActionMenu()
        return
    end

    if isRunningStatus(ri.status) then
        startupArmed = false
        autoOutputGate = 0
        chargedOnce = false
        prevTemp = nil
        prevTempTime = nil
        resetOptimizer("Manual Stop")
        fluxgate.setSignalLowFlow(0)
        reactor.stopReactor()
        action = "Manual shutdown requested"
        actioncolor = colors.orange
        save_config()
    elseif ri.status == "stopping" or ri.status == "cooling" then
        startupArmed = false
        resetOptimizer("Cooling")
        action = "Reactor is still shutting down"
        actioncolor = colors.orange
        ActionMenu()
    else
        if safetyShutdownLatched then
            if getFuelPercent(ri) <= 10 then
                action = "Safety latch held: refuel before restart"
                actioncolor = colors.red
                ActionMenu()
                return
            elseif (ri.temperature or 0) > safeTemp then
                action = "Safety latch held: wait below "..safeTemp.."C"
                actioncolor = colors.red
                ActionMenu()
                return
            end

            clearSafetyLatch()
        end

        startupArmed = true
        chargedOnce = false
        prevTemp = nil
        prevTempTime = nil
        resetOptimizer("Manual Start")

        inputFluxgate.setSignalLowFlow(minChargeInput)
        fluxgate.setSignalLowFlow(0)

        if ri.status == "charged" or reactorReadyToActivate(ri) then
            reactor.activateReactor()
            startupArmed = false
            action = "Manual reactor activation"
        else
            reactor.chargeReactor()
            action = "Manual startup requested"
        end

        actioncolor = colors.lime
        save_config()
    end
end

function ActionMenu()
    currentMenu = "action"
    MenuText = "ATTENTION"
    clearMenuArea()
    button.setButton("action", action, buttonMain, 5, 28, monX-4, 30, 0, 0, colors.red)
    button.screen()
end

function rebootSystem()
    os.reboot()
end

function buttonControls()
    currentMenu = "controls"
    MenuText = "CONTROLS"
    clearMenuArea()

    local sLength = 6+(string.len("Toggle Reactor")+1)
    button.setButton("toggle", "Toggle Reactor", toggleReactor, 6, 28, sLength, 30, 0, 0, colors.blue)

    local sLength2 = (sLength+12+(string.len("Reboot"))+1)
    button.setButton("reboot", "Reboot", rebootSystem, sLength+12, 28, sLength2, 30, 0, 0, colors.blue)

    local sLength3 = 4+(string.len("Back")+1)
    button.setButton("back", "Back", buttonMain, 4, 32, sLength3, 34, 0, 0, colors.blue)

    button.screen()
end

function changeOutputValue(num, val)
    local cFlow = fluxgate.getSignalLowFlow()

    if val == 1 then
        cFlow = cFlow + num
    else
        cFlow = cFlow - num
    end

    cFlow = clamp(cFlow, 0, outputCap)
    fluxgate.setSignalLowFlow(cFlow)

    -- If auto is on, keep the auto target aligned to manual nudges
    if inAuto() then
        autoOutputTarget = cFlow
        save_config()
    end

    updateReactorInfo()
end

function outputMenu()
    currentMenu = "output"
    MenuText = "OUTPUT"
    clearMenuArea()

    local buttonData = {
        {label = ">>>>", value = 1000000, changeType = 1},
        {label = ">>>", value = 100000, changeType = 1},
        {label = ">>", value = 10000, changeType = 1},
        {label = ">", value = 1000, changeType = 1},
        {label = "<", value = 1000, changeType = 0},
        {label = "<<", value = 10000, changeType = 0},
        {label = "<<<", value = 100000, changeType = 0},
        {label = "<<<<", value = 1000000, changeType = 0},
    }

    local spacing = 2
    local buttonY = 28

    local currentX = monX - 7
    for _, data in ipairs(buttonData) do
        local buttonLength = string.len(data.label) + 1
        local startX = currentX - buttonLength
        local endX = startX + buttonLength

        button.setButton(data.label, data.label, changeOutputValue, startX, buttonY, endX, buttonY + 2, data.value, data.changeType, colors.blue)
        currentX = currentX - buttonLength - spacing
    end

    local backLength = 4 + string.len("Back") + 1
    button.setButton("back", "Back", buttonMain, 4, 32, backLength, 34, 0, 0, colors.blue)

    -- Auto toggle: unique IDs per state so label always flips cleanly
    local isOn = inAuto()
    local autoLabel = safetyShutdownLatched and "Auto: LOCKED" or (isOn and "Auto: ON" or "Auto: OFF")
    local autoId = safetyShutdownLatched and "autoout_locked" or (isOn and "autoout_on" or "autoout_off")
    local autoButtonColor = safetyShutdownLatched and colors.red or colors.purple

    local autoLen = string.len(autoLabel) + 1
    local autoEndX = monX - 4
    local autoStartX = autoEndX - autoLen
    button.setButton(autoId, autoLabel, toggleAutoOutput, autoStartX, 32, autoEndX, 34, 0, 0, autoButtonColor)

    button.screen()
end

function buttonMain()
    currentMenu = "main"
    MenuText = "MAIN MENU"
    clearMenuArea()

    local sLength = 4+(string.len("Controls")+1)
    button.setButton("controls", "Controls", buttonControls, 4, 28, sLength, 30, 0, 0, colors.blue)

    local sLength2 = (sLength+13+(string.len("Output"))+1)
    button.setButton("output", "Output", outputMenu, sLength+13, 28, sLength2, 30, 0, 0, colors.blue)

    button.screen()
end

local lastValues = {}

function drawUpdatedText(x, y, label, value, color)
    local key = tostring(x)..":"..tostring(y)
    local displayState = tostring(label).."|"..tostring(value).."|"..tostring(color)
    if lastValues[key] ~= displayState then
        f.draw_text_lr(mon, x, y, 3, "            ", "                    ", colors.white, color, colors.black)
        f.draw_text_lr(mon, x, y, 3, label, value, colors.white, color, colors.black)
        lastValues[key] = displayState
    end
end

function getTempColor(temp)
    temp = tonumber(temp) or 0
    if temp <= opTempHigh then return colors.green end
    if temp < (maxTemp - 500) then return colors.orange end
    return colors.red
end

function getFieldColor(percent)
    percent = tonumber(percent) or 0
    if percent <= (lowFieldPer + fieldPanicBuffer) then return colors.red end
    if percent <= (activeFieldTarget + fieldOutputHeadroom) then return colors.orange end
    return colors.blue
end

function getFuelColor(percent)
    percent = tonumber(percent) or 0
    if percent >= 70 then return colors.green end
    if percent > 30 then return colors.orange end
    return colors.red
end

function reactorInfoScreen()
    mon.clear()

    f.draw_text(mon, 2, 38, "Made by: StormFusions Auto by: Bloodfallen Corp.  v"..version, colors.gray, colors.black)

    f.draw_line(mon, 2, 22, monX-2, colors.gray)
    f.draw_line(mon, 2, 2, monX-2, colors.gray)
    f.draw_line_y(mon, 2, 2, 22, colors.gray)
    f.draw_line_y(mon, monX-1, 2, 22, colors.gray)
    f.draw_text(mon, 4, 2, " INFO ", colors.white, colors.black)

    f.draw_line(mon, 2, 26, monX-2, colors.gray)
    f.draw_line(mon, 2, monY-1, monX-2, colors.gray)
    f.draw_line_y(mon, 2, 26, monY-1, colors.gray)
    f.draw_line_y(mon, monX-1, 26, monY-1, colors.gray)
    f.draw_text(mon, 4, 26, " "..MenuText.." ", colors.white, colors.black)

    while true do
        updateReactorInfo()
        sleep(1)
    end
end

function updateReactorInfo()
    ri = reactor.getReactorInfo()
    if not ri then return end

    drawUpdatedText(4, 4, "Status:", reactorStatus(ri.status)[1], reactorStatus(ri.status)[2])
    drawUpdatedText(4, 5, "Generation:", f.format_int(ri.generationRate).." OP/t", colors.lime)

    local outputFlow = tonumber(fluxgate.getSignalLowFlow()) or 0
    local inputFlow = tonumber(inputFluxgate.getSignalLowFlow()) or 0
    local netEstimate = outputFlow - inputFlow
    drawUpdatedText(4, 6, "Net Est:", f.format_int(netEstimate).." OP/t", netEstimate >= 0 and colors.lime or colors.red)

    local opToFe = getOpToFeMultiplier()
    if opToFe then
        local feEstimate = netEstimate * opToFe
        drawUpdatedText(4, 7, "FE Est:", f.format_int(feEstimate).." FE/t", feEstimate >= 0 and colors.lime or colors.red)
    else
        drawUpdatedText(4, 7, "", "", colors.black)
    end

    local autoColor = inAuto() and colors.lime or colors.gray
    drawUpdatedText(4, 8, "Auto Output:", inAuto() and "ON" or "OFF", autoColor)

    local optimizerColor = optimizerMode == "Recover" and colors.red
        or optimizerMode == "Field Recover" and colors.orange
        or optimizerMode == "Temp Hold" and colors.orange
        or optimizerMode == "Temp Trim" and colors.red
        or optimizerMode == "Ramp 4M" and colors.lightBlue
        or optimizerMode == "Step Wait" and colors.lightBlue
        or optimizerMode == "Wait Cool" and colors.orange
        or optimizerMode == "Step Climb" and colors.lime
        or optimizerMode == "Field Trim" and colors.lime
        or optimizerMode == "Baseline Hold" and colors.orange
        or optimizerMode == "Stabilize 50" and colors.orange
        or optimizerMode == "Settling Output" and colors.lightBlue
        or optimizerMode == "Ramping 4M" and colors.lightBlue
        or optimizerMode == "Stable 4M" and colors.lime
        or optimizerMode == "Optimize Ready" and colors.lime
        or colors.lightBlue
    drawUpdatedText(4, 9, "Power Mode:", optimizerMode, optimizerColor)

    local tempColor = getTempColor(ri.temperature)
    drawUpdatedText(4, 10, "Temperature:", f.format_int(ri.temperature).."C", tempColor)

    local autoTargetText = inAuto() and (f.format_int(autoOutputTarget).." OP/t") or "-"
    drawUpdatedText(4, 11, "Auto Target:", autoTargetText, autoColor)

    drawUpdatedText(4, 12, "Output Gate:", f.format_int(outputFlow).." OP/t", colors.lightBlue)
    drawUpdatedText(4, 13, "Input Gate:", f.format_int(inputFlow).." OP/t", colors.lightBlue)

    drawUpdatedText(4, 14, "Field Target:", formatPercent(activeFieldTarget, 2).."%", colors.lightBlue)

    local latchColor = safetyShutdownLatched and colors.red or colors.green
    drawUpdatedText(4, 15, "Safety Latch:", safetyShutdownLatched and "ON" or "OK", latchColor)

    local satPercent = getPercentage(ri.energySaturation, ri.maxEnergySaturation)
    drawUpdatedText(4, 16, "Energy Saturation:", satPercent.."%", colors.green)
    f.progress_bar(mon, 4, 17, monX-7, satPercent, 100, colors.green, colors.lightGray)

    local fieldPercent = getPercentage(ri.fieldStrength, ri.maxFieldStrength)
    local fieldColor = getFieldColor(fieldPercent)
    drawUpdatedText(4, 18, "Field Strength:", fieldPercent.."%", fieldColor)
    f.progress_bar(mon, 4, 19, monX-7, fieldPercent, 100, fieldColor, colors.lightGray)

    local fuelPercent = getFuelPercent(ri)
    local fuelColor = getFuelColor(fuelPercent)
    drawUpdatedText(4, 20, "Fuel:", fuelPercent.."%", fuelColor)
    f.progress_bar(mon, 4, 21, monX-7, fuelPercent, 100, fuelColor, colors.lightGray)
end

mon.clear()
mon.monitor.setTextScale(0.5)

buttonMain()
parallel.waitForAny(reactorInfoScreen, reactorControl, button.clickEvent)
