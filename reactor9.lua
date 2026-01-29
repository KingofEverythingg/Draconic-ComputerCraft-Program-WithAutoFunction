os.loadAPI("lib/f")
os.loadAPI("lib/button")

local targetStrength = 50
local maxTemp = 8000
local safeTemp = 3000
local lowFieldPer = 15

local activateOnCharge = true
local version = 0.35

local autoInputGate = 1
local curInputGate = 222000

-- Auto Output and Balance Mode
-- Behavior when Auto is ON:
-- 1) Startup latch (only when truly starting cold): input >= 1.2M and output = 0 until field and saturation reach 99% once
-- 2) Warm into operating band: raise output until temp >= 5500
-- 3) Production: if temp is between 5500 and 7000, increment output while maintaining field at 50% and staying under 8000

local autoOutputGate = 0
local autoOutputTarget = 0

local outputCap = 1000000000
local inputCap = 5000000

local minChargeInput = 1200000
local baseOutput = 2500000

local chargeFieldMin = 98
local chargeSatMin = 99

-- Operating temperature band
local opTempLow = 5500
local opTempHigh = 7000
local opTempHys = 50

-- Steps and pacing
local autoInterval = 1.0
local lastAutoAdjust = 0

local holdOutStep = 50000
local autoInStep = 25000

-- Warm-up tuning (fast to enter band, but limit rate of climb)
local warmMinStep = 50000
local warmMaxStep = 750000
local warmGain = 300

local warmMaxRiseRate = 60    -- C/sec: at or above this, stop increasing output
local warmBrakeRate = 90      -- C/sec: at or above this, reduce output

local prevTemp = nil
local prevTempTime = nil

-- Field response
local fieldHys = 0.1
local fieldBoostPerPct = 75000

-- Saturation guardrails
local satHardMin = 20         -- if saturation drops below this, back off output

-- Latches
local chargedOnce = false

local mon, monitor, monX, monY

local reactor
local fluxgate
local inputFluxgate

local ri

local action = "None since reboot"
local actioncolor = colors.gray
local emergencyCharge = false
local emergencyTemp = false

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

    print("Please set input flow gate to 10 RF/t manually.")

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

    sr.close()

    if autoOutputTarget < 0 then autoOutputTarget = 0 end
    if autoOutputTarget > outputCap then autoOutputTarget = outputCap end
end

if fs.exists("reactorconfig.txt") == false then
    autoOutputTarget = fluxgate.getSignalLowFlow()
    save_config()
else
    load_config()
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
        autoOutputGate = 1

        -- Start from whatever the current output is (manual state)
        autoOutputTarget = fluxgate.getSignalLowFlow()

        -- Allow auto to act immediately and compute temperature rise rate cleanly
        lastAutoAdjust = 0
        prevTemp = nil
        prevTempTime = nil

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

function handleAutoProgram(ri, baseInput)
    if not inAuto() then return end
    if not ri or not isRunningStatus(ri.status) then
        chargedOnce = false
        prevTemp = nil
        prevTempTime = nil
        return
    end

    local now = nowSec()
    if (now - lastAutoAdjust) < autoInterval then return end
    lastAutoAdjust = now

    local fieldPct = getPercentage(ri.fieldStrength, ri.maxFieldStrength)
    local satPct = getPercentage(ri.energySaturation, ri.maxEnergySaturation)
    local temp = ri.temperature or 0

    -- Temperature rise rate (C/sec)
    local riseRate = 0
    if prevTemp ~= nil and prevTempTime ~= nil then
        local dt = now - prevTempTime
        if dt > 0 then
            riseRate = (temp - prevTemp) / dt
        end
    end

    local desiredIn = clamp(baseInput or inputFluxgate.getSignalLowFlow(), 0, inputCap)
    local desiredOut = clamp(fluxgate.getSignalLowFlow(), 0, outputCap)

    -- Hard safety temperature governor
    if temp >= (maxTemp - 25) then
        desiredOut = math.max(0, desiredOut - (holdOutStep * 25))
        desiredIn = math.min(inputCap, desiredIn + (autoInStep * 5))
    else
        -- Only do the 99/99 latch if we are actually starting cold with zero draw
        local likelyStartup = (temp < 2000) and (desiredOut <= 0)

        if likelyStartup and not chargedOnce then
            desiredIn = math.max(desiredIn, minChargeInput)

            if (fieldPct >= chargeFieldMin) and (satPct >= chargeSatMin) then
                chargedOnce = true
                desiredOut = math.max(desiredOut, baseOutput)
            else
                desiredOut = 0
            end
        else
            -- Normal run: keep at least base output
            if desiredOut < baseOutput then
                desiredOut = baseOutput
            end

            -- Maintain field around 50%
            if fieldPct < (targetStrength - fieldHys) then
                local deficit = (targetStrength - fieldPct)
                desiredOut = math.max(0, desiredOut - (holdOutStep * 10))
                desiredIn = math.min(inputCap, desiredIn + (deficit * fieldBoostPerPct))
            end

            -- Saturation hard guard
            if satPct <= satHardMin then
                desiredOut = math.max(0, desiredOut - (holdOutStep * 2))
            end

            -- Below band: warm up toward opTempLow
            if temp < (opTempLow - opTempHys) then
                if fieldPct >= targetStrength and satPct > satHardMin then
                    local err = (opTempLow - temp)
                    local step = clamp(err * warmGain, warmMinStep, warmMaxStep)

                    if riseRate >= warmBrakeRate then
                        desiredOut = math.max(0, desiredOut - holdOutStep)
                    elseif riseRate >= warmMaxRiseRate then
                        -- hold
                    else
                        desiredOut = math.min(outputCap, desiredOut + step)
                    end
                end

            -- Above band: back down
            elseif temp > (opTempHigh + opTempHys) then
                desiredOut = math.max(0, desiredOut - (holdOutStep * 2))

            -- In band: increment output
            else
                if fieldPct >= targetStrength and satPct > satHardMin then
                    if riseRate >= warmBrakeRate then
                        desiredOut = math.max(0, desiredOut - holdOutStep)
                    elseif riseRate >= warmMaxRiseRate then
                        -- hold
                    else
                        if temp <= (opTempHigh - opTempHys) then
                            desiredOut = math.min(outputCap, desiredOut + holdOutStep)
                        end
                    end
                end
            end
        end
    end

    desiredIn = clamp(math.floor(desiredIn + 0.5), 0, inputCap)
    desiredOut = clamp(math.floor(desiredOut + 0.5), 0, outputCap)

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

        if emergencyCharge then
            reactor.chargeReactor()
        end

        if isChargingStatus(ri.status) then
            if inAuto() then
                inputFluxgate.setSignalLowFlow(minChargeInput)
            else
                inputFluxgate.setSignalLowFlow(900000)
            end

            emergencyCharge = false

            if activateOnCharge then
                reactor.activateReactor()
            end
        elseif ri.status == "stopping" and (ri.temperature or 0) < safeTemp and emergencyTemp then
            reactor.activateReactor()
            emergencyTemp = false
        end

        if isRunningStatus(ri.status) then
            local baseInput = autoInputGate == 1
                and ri.fieldDrainRate / (1 - (targetStrength / 100))
                or curInputGate

            i = i + 1
            drawTerminalText(1, i, "Base Input", math.floor(baseInput))

            if inAuto() then
                handleAutoProgram(ri, baseInput)

                i = i + 1
                drawTerminalText(1, i, "Auto Target", autoOutputTarget)

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
        end

        checkReactorSafety(ri)

        sleep(0.2)
        ::continue::
    end
end

function checkReactorSafety(ri)
    local fuelPercent = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000) * 0.01
    local fieldPercent = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000) * 0.01

    if fuelPercent <= 10 then
        emergencyShutdown("Fuel Low! Refuel Now!")
    elseif fieldPercent <= lowFieldPer and isRunningStatus(ri.status) then
        emergencyShutdown("Field Strength Below "..lowFieldPer.."%!")
        reactor.chargeReactor()
        emergencyCharge = true
    elseif (ri.temperature or 0) > maxTemp then
        emergencyShutdown("Reactor Overheated!")
        emergencyTemp = true
    end
end

function emergencyShutdown(message)
    reactor.stopReactor()
    actioncolor = colors.red
    action = message
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

    if isRunningStatus(ri.status) then
        reactor.stopReactor()
    elseif ri.status == "stopping" then
        reactor.activateReactor()
    else
        reactor.chargeReactor()
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
    local autoLabel = isOn and "Auto: ON" or "Auto: OFF"
    local autoId = isOn and "autoout_on" or "autoout_off"

    local autoLen = string.len(autoLabel) + 1
    local autoEndX = monX - 4
    local autoStartX = autoEndX - autoLen
    button.setButton(autoId, autoLabel, toggleAutoOutput, autoStartX, 32, autoEndX, 34, 0, 0, colors.purple)

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
    local key = label
    if lastValues[key] ~= value then
        f.draw_text_lr(mon, x, y, 3, "            ", "                    ", colors.white, color, colors.black)
        f.draw_text_lr(mon, x, y, 3, label, value, colors.white, color, colors.black)
        lastValues[key] = value
    end
end

function getTempColor(temp)
    if temp <= 5000 then return colors.green end
    if temp <= 6500 then return colors.orange end
    return colors.red
end

function getFieldColor(percent)
    if percent >= 50 then return colors.blue end
    if percent > 30 then return colors.orange end
    return colors.red
end

function getFuelColor(percent)
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
    drawUpdatedText(4, 5, "Generation:", f.format_int(ri.generationRate).." rf/t", colors.lime)

    local autoColor = inAuto() and colors.lime or colors.gray
    drawUpdatedText(4, 6, "Auto Output:", inAuto() and "ON" or "OFF", autoColor)

    local tempColor = getTempColor(ri.temperature)
    drawUpdatedText(4, 7, "Temperature:", f.format_int(ri.temperature).."C", tempColor)

    local autoTargetText = inAuto() and (f.format_int(autoOutputTarget).." rf/t") or "-"
    drawUpdatedText(4, 8, "Auto Target:", autoTargetText, autoColor)

    drawUpdatedText(4, 9, "Output Gate:", f.format_int(fluxgate.getSignalLowFlow()).." rf/t", colors.lightBlue)
    drawUpdatedText(4, 10, "Input Gate:", f.format_int(inputFluxgate.getSignalLowFlow()).." rf/t", colors.lightBlue)

    local satPercent = getPercentage(ri.energySaturation, ri.maxEnergySaturation)
    drawUpdatedText(4, 12, "Energy Saturation:", satPercent.."%", colors.green)
    f.progress_bar(mon, 4, 13, monX-7, satPercent, 100, colors.green, colors.lightGray)

    local fieldPercent = getPercentage(ri.fieldStrength, ri.maxFieldStrength)
    local fieldColor = getFieldColor(fieldPercent)
    drawUpdatedText(4, 15, "Field Strength:", fieldPercent.."%", fieldColor)
    f.progress_bar(mon, 4, 16, monX-7, fieldPercent, 100, fieldColor, colors.lightGray)

    local fuelPercent = 100 - getPercentage(ri.fuelConversion, ri.maxFuelConversion)
    local fuelColor = getFuelColor(fuelPercent)
    drawUpdatedText(4, 18, "Fuel:", fuelPercent.."%", fuelColor)
    f.progress_bar(mon, 4, 19, monX-7, fuelPercent, 100, fuelColor, colors.lightGray)
end

mon.clear()
mon.monitor.setTextScale(0.5)

buttonMain()
parallel.waitForAny(reactorInfoScreen, reactorControl, button.clickEvent)
