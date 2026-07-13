local S = require('core.shared')
local gates = require('gates.gates')
local routes = require('routes.routes')
local pb = require('pb.pb')
local ghost = require('ghost.ghost')

local timing = {}

local WIDTH = 360
local TOP_HEIGHT = 198
local MIN_LIST_HEIGHT = 60
local PADDING = 16

local READY = 1
local RUNNING = 2
local FINISHED = 3
local INVALID = 4

local state = READY
local resetFlashAt = -1

local route
local rec
local compareRecord
local startGate
local finishGate
local checkpoints = {}
local splits = {}
local nextCheckpoint = 1
local startClock = 0
local currentTime = 0
local lastPos
local invalidReason
local invalidAt = -1
local runDistance = 0
local trace = {}
local TRACE_STEP = 3

local TELEPORT_THRESHOLD = 40
local LOOP_FINISH_ARM = 3
local START_LABEL_SWITCH = 5
local BANNER_SECS = 3

local SMOOTH_JUMP_THRESHOLD = 0.2
local SMOOTH_DECAY_SECONDS = 0.8

local liveDeltaRaw = nil
local liveDeltaShown = nil
local liveDeltaSmoothOffset = 0

local legacyPbDistAtSplit = {}
local legacyAnchorPbDist = 0
local legacyAnchorRunDist = 0
local legacyClampDist = nil
local legacyTraceCursor = 2

local function resetDeltaState()
    liveDeltaRaw = nil
    liveDeltaShown = nil
    liveDeltaSmoothOffset = 0
    legacyAnchorPbDist = 0
    legacyAnchorRunDist = 0
    legacyClampDist = nil
    legacyTraceCursor = 2
end

local function resetRun()
    state = READY
    currentTime = 0
    startClock = 0
    splits = {}
    nextCheckpoint = 1
    runDistance = 0
    trace = {}
    invalidReason = nil
    ghost.abortRun()
    resetDeltaState()
    if route then gates.resetRuntime(route.gates) end
end

local function invalidate(reason)
    if state ~= RUNNING then return end
    state = INVALID
    invalidReason = reason
    invalidAt = os.clock()
    ghost.abortRun()
    if route then
        rec = pb.recordPartial(route, splits) or rec
        gates.resetRuntime(route.gates)
    end
    ac.log('[LMTiming] run invalidated: ' .. reason)
end

-- legacy delta for old pbs set with v1.0.0
local function setupLegacyCompare()
    legacyPbDistAtSplit = {}
    legacyAnchorPbDist = 0
    legacyAnchorRunDist = 0
    legacyTraceCursor = 2
    legacyClampDist = nil

    local tracePoints = compareRecord and compareRecord.trace
    if not tracePoints or #tracePoints < 2 then return end

    local pbSplits = compareRecord.splits or {}
    local index = 2
    for i = 1, #checkpoints do
        local splitTime = pbSplits[i]
        if not splitTime then break end
        while index <= #tracePoints and tracePoints[index].t < splitTime do
            index = index + 1
        end
        if index > #tracePoints then
            legacyPbDistAtSplit[i] = tracePoints[#tracePoints].d
        else
            local before = tracePoints[index - 1]
            local after = tracePoints[index]
            local fraction = (splitTime - before.t) / math.max(after.t - before.t, 0.0001)
            legacyPbDistAtSplit[i] = before.d + (after.d - before.d) * fraction
        end
    end

    legacyClampDist = legacyPbDistAtSplit[1] or tracePoints[#tracePoints].d
end

local function legacyLiveDelta()
    local tracePoints = compareRecord and compareRecord.trace
    if not tracePoints or #tracePoints < 2 then return nil end

    local pbDistance = legacyAnchorPbDist + (runDistance - legacyAnchorRunDist)
    if legacyClampDist then pbDistance = math.min(pbDistance, legacyClampDist) end

    if pbDistance <= tracePoints[1].d then
        return currentTime - tracePoints[1].t
    end
    local lastPoint = tracePoints[#tracePoints]
    if pbDistance >= lastPoint.d then
        return currentTime - lastPoint.t
    end

    local index = legacyTraceCursor
    if index < 2 or index > #tracePoints or tracePoints[index - 1].d > pbDistance then
        index = 2
    end
    while tracePoints[index].d < pbDistance do
        index = index + 1
    end
    legacyTraceCursor = index

    local before = tracePoints[index - 1]
    local after = tracePoints[index]
    local fraction = (pbDistance - before.d) / math.max(after.d - before.d, 0.0001)
    return currentTime - (before.t + (after.t - before.t) * fraction)
end

local function anchorDeltaAtCheckpoint(index)
    if ghost.hasCompare() then
        local pbSplit = compareRecord and compareRecord.splits and compareRecord.splits[index]
        if pbSplit then ghost.syncToTime(pbSplit) end
        return
    end

    if legacyPbDistAtSplit[index] then
        legacyAnchorPbDist = legacyPbDistAtSplit[index]
        legacyAnchorRunDist = runDistance
    end
    local tracePoints = compareRecord and compareRecord.trace
    local traceEnd = tracePoints and #tracePoints > 0 and tracePoints[#tracePoints].d or nil
    legacyClampDist = legacyPbDistAtSplit[index + 1] or traceEnd
end

-- the new delta system
local function updateLiveDelta(dt, pos)
    if state ~= RUNNING then
        liveDeltaRaw = nil
        liveDeltaShown = nil
        return
    end

    local raw
    if ghost.hasCompare() then
        raw = ghost.liveDelta(pos, currentTime)
    else
        raw = legacyLiveDelta()
    end

    if raw and liveDeltaRaw then
        local jump = raw - liveDeltaRaw
        if math.abs(jump) > SMOOTH_JUMP_THRESHOLD then
            liveDeltaSmoothOffset = liveDeltaSmoothOffset + jump
        end
    end
    liveDeltaRaw = raw

    liveDeltaSmoothOffset = liveDeltaSmoothOffset * math.exp(-dt / SMOOTH_DECAY_SECONDS)
    liveDeltaShown = raw and (raw - liveDeltaSmoothOffset) or nil
end

local function beginRun()
    compareRecord = rec
    state = RUNNING
    startClock = os.clock()
    currentTime = 0
    nextCheckpoint = 1
    splits = {}
    runDistance = 0
    trace = { { d = 0, t = 0 } }
    resetDeltaState()
    setupLegacyCompare()
    ghost.beginRun()
    if route then gates.resetRuntime(route.gates) end
end

local function finishRun()
    state = FINISHED
    trace[#trace + 1] = { d = runDistance, t = currentTime }
    local improved = not rec or not rec.time or currentTime < rec.time
    rec = pb.recordRun(route, currentTime, splits, trace)
    if improved then
        local car = ac.getCar(0)
        if car then ghost.recordFrame(currentTime, car, true) end
        ghost.saveRecording(route, currentTime)
    else
        ghost.discardRecording()
    end
    if route then gates.resetRuntime(route.gates) end
    ac.log('[LMTiming] run finished: ' .. S.formatTime(currentTime))
end

local function syncRoute()
    local selected = routes.getSelected()
    if selected == route then return end

    route = selected
    lastPos = nil

    if route then
        rec = pb.load(route)
        startGate = nil
        finishGate = nil
        checkpoints = {}
        for _, gate in ipairs(route.gates) do
            if gate.type == 'start' then
                startGate = gate
            elseif gate.type == 'finish' then
                finishGate = gate
            elseif gate.type == 'checkpoint' then
                checkpoints[#checkpoints + 1] = gate
            end
        end
        if route.type == 'loop' then
            finishGate = startGate
        end
    else
        rec = nil
        startGate = nil
        finishGate = nil
        checkpoints = {}
    end

    ghost.setContext(route)
    compareRecord = rec
    resetRun()
end

local function canStart()
    if not route then return false, 'No route loaded' end
    if not routes.trackMatches(route) then return false, 'Wrong track' end
    if not routes.carMatches(route) then return false, 'Requires car: ' .. route.carRestrict end
    if not S.serverHasTraffic(route.traffic) then return false, 'Requires ' .. route.traffic .. ' traffic' end
    return true
end
timing.canStart = canStart

function timing.init()
    ac.onCarCollision(0, function()
        invalidate('collision')
    end)
    pb.onChanged(function(changedRoute)
        if route and changedRoute == route then
            rec = pb.load(route)
            compareRecord = rec
            resetRun()
        end
    end)
    ac.log('[LMTiming] timing module initialised')
end

function timing.update(dt)
    if S.resetButton and S.resetButton:pressed() then
        resetFlashAt = os.clock()
        resetRun()
    end

    syncRoute()
    if not route then return end

    local car = ac.getCar(0)
    if not car then return end

    local pos = car.position
    local speed = car.speedKmh

    if lastPos == nil then
        lastPos = pos:clone()
        return
    end

    if state == RUNNING then
        currentTime = os.clock() - startClock

        local dx = pos.x - lastPos.x
        local dz = pos.z - lastPos.z
        local step = math.sqrt(dx * dx + dz * dz)
        if step > TELEPORT_THRESHOLD then
            invalidate('pits')
            lastPos = pos:clone()
            return
        end

        if S.settings.restartOnStart and route.type ~= 'loop' and startGate and canStart()
                and gates.crossed(startGate, pos, lastPos, speed) then
            beginRun()
            lastPos = pos:clone()
            return
        end

        runDistance = runDistance + step
        local lastDistance = trace[#trace] and trace[#trace].d or 0
        if runDistance - lastDistance >= TRACE_STEP then
            trace[#trace + 1] = { d = runDistance, t = currentTime }
        end

        ghost.recordFrame(currentTime, car)

        if nextCheckpoint <= #checkpoints then
            local gate = checkpoints[nextCheckpoint]
            if gates.crossed(gate, pos, lastPos, speed) then
                splits[nextCheckpoint] = currentTime
                gate.crossed = true
                gate.crossedAt = os.clock()
                anchorDeltaAtCheckpoint(nextCheckpoint)
                nextCheckpoint = nextCheckpoint + 1
            end
        end

        if finishGate then
            local armed = (route.type ~= 'loop') or ((os.clock() - startClock) > LOOP_FINISH_ARM)
            if armed and gates.crossed(finishGate, pos, lastPos, speed) then
                if nextCheckpoint > #checkpoints then
                    finishGate.crossed = true
                    finishGate.crossedAt = os.clock()
                    finishRun()
                else
                    timing.notify('missed', BANNER_SECS)
                end
            end
        end

    elseif state == READY then
        if startGate and canStart() and gates.crossed(startGate, pos, lastPos, speed) then
            beginRun()
        end

    else
        if startGate and canStart() and gates.crossed(startGate, pos, lastPos, speed) then
            beginRun()
        end
    end

    updateLiveDelta(dt, pos)
    ghost.update(state == RUNNING, currentTime, pos)

    lastPos = pos:clone()
end

function timing.active()
    return state == RUNNING
end

function timing.currentDelta()
    if not compareRecord then return nil end

    if state == FINISHED then
        if compareRecord.time then return currentTime - compareRecord.time end
        return nil
    end

    if state ~= RUNNING then return nil end

    local lastIndex = #splits
    if lastIndex == 0 or not compareRecord.splits or not compareRecord.splits[lastIndex] then
        return nil
    end
    return splits[lastIndex] - compareRecord.splits[lastIndex]
end

function timing.liveDelta()
    if state ~= RUNNING then return nil end
    return liveDeltaShown
end

function timing.gateLabel(gate)
    if gate.type == 'start' then
        if route and route.type == 'loop' then
            if state == RUNNING and (os.clock() - startClock) > START_LABEL_SWITCH then
                return 'Finish Line', gates.typeColor.finish
            end
            return 'Start Line', gates.typeColor.start
        end
        if state == RUNNING then
            if S.settings.restartOnStart then
                return 'Start Line', gates.typeColor.start
            end
            return 'Already Started a Run', gates.typeColor.start
        end
        return 'Start Run: ' .. (route and route.name or ''), gates.typeColor.start
    elseif gate.type == 'checkpoint' then
        return 'Checkpoint #' .. (gate.index or 1), gates.typeColor.checkpoint
    elseif gate.type == 'finish' then
        return 'Finish Line', gates.typeColor.finish
    end
end

local bannerInfo = {
    collision = { text = 'Run Ended - Collision Detected', icon = 'assets/Collision.png', accent = 'red' },
    pits = { text = 'Run Ended - Reset to Pits', icon = 'assets/RedWarning.png', accent = 'red' },
    missed = { text = 'Missed Checkpoint', icon = 'assets/YellowWarning.png', accent = 'yellow' },
}
timing.bannerInfo = bannerInfo

local notifyReason = nil
local notifyUntil = -1

function timing.notify(reason, seconds)
    notifyReason = reason
    notifyUntil = os.clock() + (seconds or 3)
end

function timing.debugShowBanner(reason, seconds)
    timing.notify(reason, seconds or 4)
end

function timing.activeBanner()
    if (os.clock() < notifyUntil) and notifyReason then
        return bannerInfo[notifyReason] or bannerInfo.collision
    end
    if state == INVALID and invalidReason and (os.clock() - invalidAt) < BANNER_SECS then
        return bannerInfo[invalidReason] or bannerInfo.collision
    end
    return nil
end

local function drawBigTime(str, rightX, y)
    local dot = str:find('%.')
    local whole = dot and str:sub(1, dot - 1) or str
    local fraction = dot and str:sub(dot) or ''

    local wholeTemplate = whole:gsub('%d', '0')
    local fractionTemplate = fraction:gsub('%d', '0')

    local wholeWidth = S.measure(wholeTemplate, 44, S.mono.bold).x
    local fractionWidth = 0
    if fraction ~= '' then
        fractionWidth = S.measure(fractionTemplate, 26, S.mono.medium).x + 2
    end

    local x = rightX - wholeWidth - fractionWidth
    S.text(whole, 44, vec2(x, y), S.mono.bold, S.colors.text)
    if fraction ~= '' then
        S.text(fraction, 26, vec2(x + wholeWidth + 2, y + 16), S.mono.medium, S.colors.text)
    end
end

function timing.window()
    local scale = S.applyScaleInput('lmt_timing')
    local resetButtonVisible = S.settings.showResetButton ~= false
    local belowList = resetButtonVisible and 62 or PADDING
    local minHeight = TOP_HEIGHT + MIN_LIST_HEIGHT + belowList
    local maxHeight = math.max(minHeight, ac.getUI().windowSize.y / scale - 40)
    local currentHeight = S.sizeResizableWindow('LMT Timing', 'lmt_timing', WIDTH, minHeight, maxHeight)
    local windowSize = vec2(WIDTH, currentHeight)

    S.windowBackground(windowSize, 16)
    local y = S.header('Timing', windowSize, { windowTitle = 'LMT Timing' })

    if not route then
        S.textCentered('Load a route in the Routes app', 15, 150, WIDTH, S.fonts.regular, S.colors.textDim)
        return
    end

    S.text((route.name or ''):upper(), 12, vec2(PADDING, y), S.head.semibold, S.colors.textFaint)
    y = y + 20

    local delta = timing.currentDelta()
    if delta then
        S.text(S.formatDelta(delta), 24, vec2(PADDING, y + 16), S.mono.medium,
            delta < 0 and S.colors.accent or S.colors.red)
    end
    drawBigTime(S.formatTime(currentTime), WIDTH - PADDING - 16, y)
    y = y + 56

    local ok, reason = canStart()
    if not ok then
        S.text(reason, 14, vec2(PADDING, y), S.fonts.regular, S.colors.yellow)
    else
        local statusText
        if state == READY then
            statusText = 'Ready - cross the start line'
        elseif state == RUNNING then
            statusText = 'Running'
        elseif state == FINISHED then
            statusText = 'Finished!'
        else
            statusText = 'Run ended'
        end
        S.text(statusText, 14, vec2(PADDING, y), S.fonts.regular,
            state == FINISHED and S.colors.accent or S.colors.textDim)
    end
    y = y + 26
    S.line(vec2(PADDING, y), vec2(WIDTH - PADDING, y), S.colors.line, 1)
    y = y + 10

    local TIME_WIDTH = 80
    local DELTA_WIDTH = 84
    local GUTTER = 16
    local innerWidth = WIDTH - PADDING * 2
    local timeRight = innerWidth - GUTTER
    local deltaRight = timeRight - TIME_WIDTH
    local nameRight = deltaRight - DELTA_WIDTH

    S.text('CHECKPOINT', 12, vec2(PADDING, y), S.head.semibold, S.colors.textFaint)
    S.textRight('DELTA', 12, PADDING + deltaRight, y, S.head.semibold, S.colors.textFaint)
    S.textRight('TIME', 12, PADDING + timeRight, y, S.head.semibold, S.colors.textFaint)
    y = y + 24

    local listHeight = math.max(60, (currentHeight - belowList) - y)
    S.child('##splits', vec2(PADDING, y), vec2(innerWidth, listHeight), function()
        local contentWidth = S.availX()
        local rowY = 0
        local rowIndex = 0

        local function row(name, time, pbTime)
            rowIndex = rowIndex + 1
            local hasTime = time ~= nil
            local rowHeight = 26
            local rowColor = (rowIndex % 2 == 1) and S.colors.row or rgbm(0, 0, 0, 0)
            S.rectFill(vec2(0, rowY), vec2(contentWidth, rowY + rowHeight), rowColor, 4)

            local nameColor = hasTime and S.colors.text or S.colors.textFaint
            ui.pushDWriteFont(S.fonts.medium)
            S.dclip(name, 15, vec2(6, rowY), vec2(nameRight, rowY + rowHeight),
                ui.Alignment.Start, ui.Alignment.Center, false, nameColor)
            ui.popDWriteFont()

            if hasTime and pbTime then
                local deltaValue = time - pbTime
                ui.pushDWriteFont(S.mono.medium)
                S.dclip(S.formatDelta(deltaValue), 15, vec2(nameRight, rowY), vec2(deltaRight, rowY + rowHeight),
                    ui.Alignment.End, ui.Alignment.Center, false, deltaValue < 0 and S.colors.accent or S.colors.red)
                ui.popDWriteFont()
            end

            ui.pushDWriteFont(S.mono.regular)
            S.dclip(S.formatTime(time), 15, vec2(deltaRight, rowY), vec2(timeRight, rowY + rowHeight),
                ui.Alignment.End, ui.Alignment.Center, false, nameColor)
            ui.popDWriteFont()

            rowY = rowY + 30
        end

        for i = 1, #checkpoints do
            row('#' .. i, splits[i], compareRecord and compareRecord.splits and compareRecord.splits[i])
        end
        row('Finish', state == FINISHED and currentTime or nil, compareRecord and compareRecord.time)

        S.cursorY(rowY)
        ui.dummy(vec2(1, 1))
    end)

    if resetButtonVisible then
        local flashing = (os.clock() - resetFlashAt) < 0.1
        if S.button('##reset', 'Reset Run', vec2(PADDING, currentHeight - 50), vec2(innerWidth, 34),
            { fontSize = 15, flat = true, outline = true, forceHover = flashing }) then
            resetRun()
        end
    end

    S.resizeHandle('lmt_timing', windowSize, minHeight, maxHeight)
end

return timing
