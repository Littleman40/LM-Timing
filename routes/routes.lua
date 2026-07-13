local S = require('core.shared')
local gates = require('gates.gates')
local pb = require('pb.pb')
local ghost = require('ghost.ghost')

local routes = {}

local WIDTH = 460
local MIN_HEIGHT = 520
local windowHeight = 560
local PADDING = 14
local APP_DIR = __dirname or '.'
local SAVE_DIR = APP_DIR .. '/routes/savedRoutes'

local view = 'list'
local routeList = {}
local listLoaded = false
local selected = nil
local historyRoute = nil

local function newDraft()
    return {
        name = '',
        author = '',
        type = 'p2p',
        carRestrict = '',
        traffic = '',
        start = nil,
        checkpoints = {},
        finish = nil,
    }
end

local draft = newDraft()

local function sanitize(name)
    return (name or 'route'):gsub('[^%w_]', '_')
end

local function scan()
    routeList = {}
    local ok, files = pcall(io.scanDir, SAVE_DIR, '*.lua')
    if ok and files then
        for _, file in ipairs(files) do
            local data = io.load(SAVE_DIR .. '/' .. file)
            local route = stringify.tryParse(data, nil, nil)
            if route and route.gates then
                route._file = file
                routeList[#routeList + 1] = route
            end
        end
    end
    listLoaded = true
    ac.log('[LMTiming] routes scanned: ' .. #routeList)
end

local function nameExists(name)
    for _, route in ipairs(routeList) do
        if (route.name or ''):lower() == name:lower() then return true end
    end
    return false
end

local function draftGateList()
    local gateList = {}

    if draft.start then
        draft.start.type = 'start'
        draft.start.index = nil
        gateList[#gateList + 1] = draft.start
    end

    for i, checkpoint in ipairs(draft.checkpoints) do
        checkpoint.type = 'checkpoint'
        checkpoint.index = i
        gateList[#gateList + 1] = checkpoint
    end

    if draft.type == 'p2p' and draft.finish then
        draft.finish.type = 'finish'
        gateList[#gateList + 1] = draft.finish
    end

    return gateList
end

local function saveDraft()
    if draft.name:match('^%s*$') then return end
    if not draft.start then return end
    if draft.type == 'p2p' and not draft.finish then return end
    if nameExists(draft.name) then return end

    local route = {
        name = draft.name,
        author = draft.author ~= '' and draft.author or 'unknown',
        type = draft.type,
        carRestrict = draft.carRestrict,
        traffic = draft.traffic,
        trackId = ac.getTrackFullID('/'),
        created = os.date('%Y-%m-%d'),
        gates = draftGateList(),
    }

    io.createDir(SAVE_DIR)
    local ok = io.save(SAVE_DIR .. '/' .. sanitize(route.name) .. '.lua', stringify(route))
    if ok then
        draft = newDraft()
        scan()
        view = 'list'
    end
end

local function deleteRoute(route)
    if route._file then io.deleteFile(SAVE_DIR .. '/' .. route._file) end
    ghost.deleteAllFor(route)
    if selected == route then selected = nil end
    scan()
    view = 'list'
end

function routes.init()
    pcall(io.createDir, SAVE_DIR)
    scan()
    ac.log('[LMTiming] routes module initialised')
end

function routes.isCreating()
    return view == 'create'
end

function routes.getCreationGates()
    return draftGateList()
end

function routes.getSelected()
    return selected
end

function routes.trackMatches(route)
    return route and route.trackId == ac.getTrackFullID('/')
end

function routes.carMatches(route)
    local allowedCars = S.splitList(route.carRestrict)
    if #allowedCars == 0 then return true end

    local currentCar = (ac.getCarID(0) or ''):lower()
    for _, carId in ipairs(allowedCars) do
        if currentCar == carId:lower() then return true end
    end
    return false
end

local spaceWidth
local function inputField(id, value, pos, width, height)
    height = height or 28
    local scale = S.scale
    local fontSize = 15
    local bottomRight = pos + vec2(width, height)
    S.rectFill(pos, bottomRight, S.colors.button, 6)
    S.rect(pos, bottomRight, S.colors.border, 6, ui.CornerFlags.All, 1)

    S.cursor(pos)
    S.itemWidth(width)
    local paddingY = math.max(0, (height * scale - ui.fontSize()) * 0.5)
    ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(8 * scale, paddingY))
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(0, 0, 0, 0))
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0))
    ui.pushStyleColor(ui.StyleColor.FrameBgHovered, rgbm(0, 0, 0, 0))
    ui.pushStyleColor(ui.StyleColor.FrameBgActive, rgbm(0, 0, 0, 0))
    ui.pushStyleColor(ui.StyleColor.TextSelectedBg, rgbm(0, 0, 0, 0))
    local edited = ui.inputText(id, value, ui.InputTextFlags.None)
    local active = ui.itemActive()
    if active then
        ui.inputTextCommand('setText', edited)
    end
    ui.popStyleColor(5)
    ui.popStyleVar()

    local areaWidth = width - 16
    local textWidth = S.measure(edited, fontSize, S.fonts.regular).x
    local trailingSpaces = edited:match(' +$')
    if trailingSpaces then
        spaceWidth = spaceWidth or (S.measure('a a', fontSize, S.fonts.regular).x - S.measure('aa', fontSize, S.fonts.regular).x)
        textWidth = textWidth + #trailingSpaces * spaceWidth
    end

    local overflow = textWidth > areaWidth
    ui.pushDWriteFont(S.fonts.regular)
    S.dclip(edited, fontSize, vec2(pos.x + 8, pos.y), vec2(pos.x + 8 + areaWidth, pos.y + height),
        overflow and ui.Alignment.End or ui.Alignment.Start, ui.Alignment.Center, false, S.colors.text)
    ui.popDWriteFont()

    if active and (os.clock() % 1) < 0.5 then
        local caretX = pos.x + 8 + (overflow and areaWidth or textWidth)
        local caretY = pos.y + (height - fontSize) * 0.5
        S.line(vec2(caretX + 1, caretY), vec2(caretX + 1, caretY + fontSize), S.colors.text, 1)
    end

    return edited
end

local function toggleInList(str, item)
    local kept = {}
    local found = false
    for _, entry in ipairs(S.splitList(str)) do
        if entry == item then
            found = true
        else
            kept[#kept + 1] = entry
        end
    end
    if not found then
        kept[#kept + 1] = item
    end
    return table.concat(kept, ', ')
end

local function listHas(str, item)
    for _, entry in ipairs(S.splitList(str)) do
        if entry == item then return true end
    end
    return false
end

local function label(text, pos)
    S.text(text, 12, pos, S.head.semibold, S.colors.textFaint)
end

local function startCreate()
    draft = newDraft()
    draft.author = ac.getDriverName(0)
    selected = nil
    view = 'create'
end

local function drawList()
    local y = S.header('Routes', vec2(WIDTH, windowHeight), { windowTitle = 'LMT Routes' })

    local barHeight = 36
    local barY = windowHeight - PADDING - barHeight
    local halfWidth = (WIDTH - PADDING * 2 - 8) * 0.5
    if S.button('##share', 'Import / Export Routes', vec2(PADDING, barY), vec2(halfWidth, barHeight),
        { fontSize = 14, flat = true, outline = true }) then
        view = 'share'
    end
    if S.button('##newroute', 'Create Route', vec2(PADDING + halfWidth + 8, barY), vec2(halfWidth, barHeight),
        { primary = true, fontSize = 14 }) then
        startCreate()
    end

    if #routeList == 0 then
        S.textCentered('No routes yet. Create one!', 15, y + 30, WIDTH, S.fonts.regular, S.colors.textDim)
        return
    end

    local listHeight = math.max(60, (barY - 10) - y)
    S.child('##routelist', vec2(PADDING, y), vec2(WIDTH - PADDING * 2, listHeight), function()
        local contentWidth = S.availX()
        local rowHeight = 90
        local gap = 10
        local rowY = 0
        for _, route in ipairs(routeList) do
            local isSelected = selected == route
            S.rectFill(vec2(0, rowY), vec2(contentWidth, rowY + rowHeight), S.colors.row, 10)
            S.rect(vec2(0, rowY), vec2(contentWidth, rowY + rowHeight), S.colors.border, 10, ui.CornerFlags.All, 1)

            local buttonWidth = 96
            local buttonHeight = 30
            local buttonGap = 8
            local stackHeight = buttonHeight * 2 + buttonGap
            local buttonX = contentWidth - 12 - buttonWidth
            local buttonY = rowY + (rowHeight - stackHeight) * 0.5
            if S.button('##info' .. route.name, 'Info', vec2(buttonX, buttonY), vec2(buttonWidth, buttonHeight),
                { fontSize = 14, flat = true, outline = true }) then
                historyRoute = route
                view = 'history'
            end
            if S.button('##load' .. route.name, isSelected and 'Loaded' or 'Load',
                vec2(buttonX, buttonY + buttonHeight + buttonGap), vec2(buttonWidth, buttonHeight),
                { fontSize = 14, flat = true, outline = true, primary = isSelected }) then
                selected = route
            end

            local meta = 'by ' .. (route.author or 'unknown')
            local chip
            local chipColor
            local chipFont
            if not routes.trackMatches(route) then
                chip = 'WRONG TRACK'
                chipColor = S.colors.yellow
                chipFont = S.head.semibold
            elseif route.carRestrict and route.carRestrict ~= '' then
                chip = route.carRestrict
                chipColor = S.colors.textFaint
                chipFont = S.fonts.regular
            end

            local nameHeight = 26
            local metaHeight = 22
            local chipHeight = chip and 18 or 0
            local blockHeight = nameHeight + metaHeight + chipHeight
            local textX = 16
            local textMax = buttonX - 12
            local textY = rowY + (rowHeight - blockHeight) * 0.5

            ui.pushDWriteFont(S.head.bold)
            S.dclip(route.name or '?', 20, vec2(textX, textY), vec2(textMax, textY + nameHeight),
                ui.Alignment.Start, ui.Alignment.Center, false, S.colors.text)
            ui.popDWriteFont()
            textY = textY + nameHeight

            ui.pushDWriteFont(S.fonts.regular)
            S.dclip(meta, 15, vec2(textX, textY), vec2(textMax, textY + metaHeight),
                ui.Alignment.Start, ui.Alignment.Center, false, S.colors.textDim)
            ui.popDWriteFont()
            textY = textY + metaHeight

            if chip then
                ui.pushDWriteFont(chipFont)
                S.dclip(chip, 12, vec2(textX, textY), vec2(textMax, textY + 16),
                    ui.Alignment.Start, ui.Alignment.Start, false, chipColor)
                ui.popDWriteFont()
            end

            rowY = rowY + rowHeight + gap
        end
        S.cursorY(rowY)
        ui.dummy(vec2(1, 1))
    end)
end

local function drawCreate()
    if S.backArrow('##back') then
        view = 'list'
    end
    S.text('Create Route', 19, vec2(42, 13), S.head.bold, S.colors.text)
    S.closeX(vec2(WIDTH, windowHeight), 'LMT Routes')
    S.line(vec2(PADDING, 46), vec2(WIDTH - PADDING, 46), S.colors.line, 1)
    local y = 56

    local halfWidth = (WIDTH - PADDING * 2 - 8) * 0.5
    if S.button('##loop', 'Loop', vec2(PADDING, y), vec2(halfWidth, 30),
        { primary = draft.type == 'loop', flat = true, outline = true, fontSize = 14 }) then
        draft.type = 'loop'
    end
    if S.button('##p2p', 'Point to Point', vec2(PADDING + halfWidth + 8, y), vec2(halfWidth, 30),
        { primary = draft.type == 'p2p', flat = true, outline = true, fontSize = 14 }) then
        draft.type = 'p2p'
    end
    y = y + 40

    local LABEL_GAP = 18

    label('Route Name:', vec2(PADDING, y))
    y = y + LABEL_GAP
    draft.name = inputField('##rname', draft.name, vec2(PADDING, y), WIDTH - PADDING * 2, 28)
    y = y + 40

    label('Author:', vec2(PADDING, y))
    y = y + LABEL_GAP
    draft.author = inputField('##rauthor', draft.author, vec2(PADDING, y), WIDTH - PADDING * 2, 28)
    y = y + 40

    label("Permitted Cars List: (optional, comma-separated)", vec2(PADDING, y))
    y = y + LABEL_GAP
    draft.carRestrict = inputField('##rcar', draft.carRestrict, vec2(PADDING, y), WIDTH - PADDING * 2 - 102, 28)
    if S.button('##usecar', 'Add Current', vec2(WIDTH - PADDING - 96, y), vec2(96, 28),
        { fontSize = 13, flat = true, outline = true }) then
        local carId = ac.getCarID(0) or ''
        if carId ~= '' and not listHas(draft.carRestrict, carId) then
            draft.carRestrict = (draft.carRestrict == '' or draft.carRestrict:match('^%s*$'))
                and carId or (draft.carRestrict .. ', ' .. carId)
        end
    end
    y = y + 40

    label('Permitted Traffic Type: (optional)', vec2(PADDING, y))
    y = y + LABEL_GAP
    local buttonWidth = (WIDTH - PADDING * 2 - 8 * 3) / 4
    for i, trafficType in ipairs(S.TRAFFIC_TYPES) do
        local buttonX = PADDING + (i - 1) * (buttonWidth + 8)
        if S.button('##tr' .. trafficType, trafficType, vec2(buttonX, y), vec2(buttonWidth, 26),
            { primary = listHas(draft.traffic, trafficType), flat = true, outline = true, fontSize = 11 }) then
            draft.traffic = toggleInList(draft.traffic, trafficType)
        end
    end
    y = y + 40

    label('Timing Gates:', vec2(PADDING, y))
    y = y + LABEL_GAP
    local listTop = y

    local saveY = windowHeight - 44
    local placeRowY = saveY - 8 - 30
    local finishY
    if draft.type == 'p2p' then
        finishY = placeRowY
        placeRowY = placeRowY - 8 - 30
    end
    local listHeight = math.max(60, (placeRowY - 10) - listTop)

    S.child('##gatelist', vec2(PADDING, listTop), vec2(WIDTH - PADDING * 2, listHeight), function()
        local contentWidth = S.availX()
        local rowY = 0
        local CARD_HEIGHT = 92

        local function nudgeCell(id, labelText, cellX, cellY, cellWidth, valueText, onMinus, onPlus)
            local function step(suffix, isPlus, onClick)
                local buttonX = isPlus and (cellX + cellWidth - 20) or cellX
                local clicked = S.button('##' .. id .. suffix, '', vec2(buttonX, cellY), vec2(20, 20),
                    { flat = true, outline = true })
                local centerX = buttonX + 10
                local centerY = cellY + 10
                local armLength = 5
                S.line(vec2(centerX - armLength, centerY), vec2(centerX + armLength, centerY), S.colors.text, 1)
                if isPlus then
                    S.line(vec2(centerX, centerY - armLength), vec2(centerX, centerY + armLength), S.colors.text, 1)
                end
                if clicked then onClick() end
            end
            step('m', false, onMinus)
            step('p', true, onPlus)

            local text = labelText .. ': ' .. valueText
            local measured = S.measure(text, 13, S.mono.medium)
            local midLeft = cellX + 20
            local midRight = cellX + cellWidth - 20
            local textX = midLeft + ((midRight - midLeft) - measured.x) * 0.5
            S.text(text, 13, vec2(textX, cellY + (20 - measured.y) * 0.5), S.mono.medium, S.colors.text)
        end

        local function gateCard(gate, text, onDelete, onMoveUp, onMoveDown)
            S.rectFill(vec2(0, rowY), vec2(contentWidth, rowY + CARD_HEIGHT), S.colors.row, 8)
            S.rect(vec2(0, rowY), vec2(contentWidth, rowY + CARD_HEIGHT), S.colors.border, 8, ui.CornerFlags.All, 1)
            S.text(text, 14, vec2(10, rowY + 9), S.fonts.medium, S.colors.text)

            local buttonX = contentWidth - 8 - 22
            if S.button('##d' .. text, '', vec2(buttonX, rowY + 7), vec2(22, 20), { danger = true }) then
                onDelete()
            end
            S.image('assets/Close.png', vec2(buttonX + 6, rowY + 12), vec2(buttonX + 16, rowY + 22), S.colors.text)

            local function chevron(suffix, isUp, x, onClick)
                local clicked = S.button('##' .. suffix .. text, '', vec2(x, rowY + 7), vec2(22, 20),
                    { flat = true, outline = true })
                local centerX = x + 11
                local centerY = rowY + 17
                local arrowHalfWidth = 4
                local arrowHalfHeight = 3
                local tipY = isUp and (centerY - arrowHalfHeight) or (centerY + arrowHalfHeight)
                local armY = isUp and (centerY + arrowHalfHeight) or (centerY - arrowHalfHeight)
                S.line(vec2(centerX - arrowHalfWidth, armY), vec2(centerX, tipY), S.colors.text, 1)
                S.line(vec2(centerX, tipY), vec2(centerX + arrowHalfWidth, armY), S.colors.text, 1)
                if clicked then onClick() end
            end
            buttonX = buttonX - 26
            if onMoveDown then
                chevron('dn', false, buttonX, onMoveDown)
            end
            buttonX = buttonX - 26
            if onMoveUp then
                chevron('up', true, buttonX, onMoveUp)
            end

            gate.pos = gate.pos or vec3()
            local cellWidth = (contentWidth - 16 - 12) * 0.5
            local leftX = 8
            local rightX = 8 + cellWidth + 12
            local rowTwoY = rowY + 38
            local rowThreeY = rowY + 64
            nudgeCell('x' .. text, 'X', leftX, rowTwoY, cellWidth, string.format('%.1f', gate.pos.x),
                function() gate.pos.x = gate.pos.x - 0.5 end,
                function() gate.pos.x = gate.pos.x + 0.5 end)
            nudgeCell('y' .. text, 'Y', rightX, rowTwoY, cellWidth, string.format('%.1f', gate.pos.y),
                function() gate.pos.y = gate.pos.y - 0.25 end,
                function() gate.pos.y = gate.pos.y + 0.25 end)
            nudgeCell('z' .. text, 'Z', leftX, rowThreeY, cellWidth, string.format('%.1f', gate.pos.z),
                function() gate.pos.z = gate.pos.z - 0.5 end,
                function() gate.pos.z = gate.pos.z + 0.5 end)
            nudgeCell('w' .. text, 'Width', rightX, rowThreeY, cellWidth, string.format('%dm', math.floor(gate.width or 12)),
                function() gate.width = math.max(2, (gate.width or 12) - 1) end,
                function() gate.width = (gate.width or 12) + 1 end)

            rowY = rowY + CARD_HEIGHT + 8
        end

        if draft.start then
            gateCard(draft.start, draft.type == 'loop' and 'Start / Finish' or 'Start Line',
                function() draft.start = nil end, nil, nil)
        end

        for i, checkpoint in ipairs(draft.checkpoints) do
            local index = i

            local function removeCheckpoint()
                table.remove(draft.checkpoints, index)
            end

            local moveUp = nil
            if index > 1 then
                moveUp = function()
                    local above = draft.checkpoints[index - 1]
                    draft.checkpoints[index - 1] = draft.checkpoints[index]
                    draft.checkpoints[index] = above
                end
            end

            local moveDown = nil
            if index < #draft.checkpoints then
                moveDown = function()
                    local below = draft.checkpoints[index + 1]
                    draft.checkpoints[index + 1] = draft.checkpoints[index]
                    draft.checkpoints[index] = below
                end
            end

            gateCard(checkpoint, 'Checkpoint #' .. i, removeCheckpoint, moveUp, moveDown)
        end

        if draft.type == 'p2p' and draft.finish then
            gateCard(draft.finish, 'Finish Line',
                function() draft.finish = nil end, nil, nil)
        end

        if rowY == 0 then
            S.text('Place a gate to get started!', 12, vec2(2, 2), S.fonts.regular, S.colors.textDim)
            rowY = 24
        end
        S.cursorY(rowY)
        ui.dummy(vec2(1, 1))
    end)

    if S.button('##placestart', draft.type == 'loop' and 'Place Start / Finish' or 'Place Start',
        vec2(PADDING, placeRowY), vec2(halfWidth, 30), { flat = true, outline = true, fontSize = 13 }) then
        draft.start = gates.create('start')
    end
    if S.button('##placecp', '+ Checkpoint', vec2(PADDING + halfWidth + 8, placeRowY), vec2(halfWidth, 30),
        { flat = true, outline = true, fontSize = 13 }) then
        draft.checkpoints[#draft.checkpoints + 1] = gates.create('checkpoint')
    end
    if draft.type == 'p2p' then
        if S.button('##placefinish', 'Place Finish', vec2(PADDING, finishY), vec2(WIDTH - PADDING * 2, 30),
            { flat = true, outline = true, fontSize = 13 }) then
            draft.finish = gates.create('finish')
        end
    end

    if S.button('##save', 'Save Route', vec2(PADDING, saveY), vec2(WIDTH - PADDING * 2, 34),
        { primary = true, fontSize = 15 }) then
        saveDraft()
    end
end

local function drawHistory()
    local route = historyRoute
    if not route then return end
    if S.backArrow('##hback') then
        view = 'list'
    end
    S.text(route.name or 'Route', 19, vec2(42, 13), S.head.bold, S.colors.text)
    S.closeX(vec2(WIDTH, windowHeight), 'LMT Routes')
    S.line(vec2(PADDING, 46), vec2(WIDTH - PADDING, 46), S.colors.line, 1)
    local y = 58

    local rec = pb.load(route)
    local halfWidth = (WIDTH - PADDING * 2 - 8) * 0.5
    local columnTwo = PADDING + halfWidth + 6

    local function detail(labelText, value, x, detailRowY)
        label(labelText, vec2(x, detailRowY))
        ui.pushDWriteFont(S.fonts.medium)
        S.dclip(value, 14, vec2(x, detailRowY + 16), vec2(x + halfWidth - 8, detailRowY + 34),
            ui.Alignment.Start, ui.Alignment.Start, false, S.colors.text)
        ui.popDWriteFont()
    end

    local detailY = y
    detail('Author:', route.author or 'unknown', PADDING, detailY)
    detail('Type:', route.type == 'loop' and 'Loop' or 'Point to Point', columnTwo, detailY)
    detail('Car:', (route.carRestrict and route.carRestrict ~= '') and route.carRestrict or 'Any', PADDING, detailY + 46)
    detail('Traffic:', (route.traffic and route.traffic ~= '') and route.traffic or 'Any', columnTwo, detailY + 46)
    S.line(vec2(PADDING, detailY + 92), vec2(WIDTH - PADDING, detailY + 92), S.colors.line, 1)
    y = detailY + 104

    label('PERSONAL BEST', vec2(PADDING, y))
    S.text(S.formatTime(rec.time), 26, vec2(PADDING, y + 18), S.mono.bold, S.colors.accent)
    label('THEORETICAL BEST', vec2(columnTwo, y))
    S.text(S.formatTime(pb.theoretical(rec)), 26, vec2(columnTwo, y + 18), S.mono.bold, S.colors.textFaint)
    y = y + 64

    local COLUMN_OFFSET = 104
    local RIGHT_MARGIN = 12
    S.text('SECTOR', 12, vec2(PADDING, y), S.head.semibold, S.colors.textFaint)
    S.textRight('THEORETICAL', 12, WIDTH - PADDING - RIGHT_MARGIN - COLUMN_OFFSET - 10 , y, S.head.semibold, S.colors.textFaint)
    S.textRight('PB', 12, WIDTH - PADDING - RIGHT_MARGIN - 37, y, S.head.semibold, S.colors.textFaint)
    y = y + 24

    local checkpointNames = {}
    for _, gate in ipairs(route.gates) do
        if gate.type == 'checkpoint' then
            checkpointNames[#checkpointNames + 1] = 'Checkpoint #' .. (gate.index or (#checkpointNames + 1))
        end
    end
    checkpointNames[#checkpointNames + 1] = 'Finish'

    local deleteY = windowHeight - 52
    local listHeight = math.max(60, (deleteY - 12) - y)
    S.child('##histsplits', vec2(PADDING, y), vec2(WIDTH - PADDING * 2, listHeight), function()
        local contentWidth = S.availX()
        local theoreticalRight = contentWidth - RIGHT_MARGIN
        local pbRight = theoreticalRight - COLUMN_OFFSET
        local rowY = 0
        for i, name in ipairs(checkpointNames) do
            local rowHeight = 28
            local rowColor = (i % 2 == 1) and S.colors.row or rgbm(0, 0, 0, 0)
            S.rectFill(vec2(0, rowY), vec2(contentWidth, rowY + rowHeight), rowColor, 4)

            local best = rec.best and rec.best[i]
            local pbSplit = rec.splits and rec.splits[i]
            if i == #checkpointNames then
                best = pb.theoretical(rec)
                pbSplit = rec.time
            end

            ui.pushDWriteFont(S.fonts.medium)
            S.dclip(name, 15, vec2(8, rowY), vec2(pbRight - 90, rowY + rowHeight),
                ui.Alignment.Start, ui.Alignment.Center, false, S.colors.text)
            ui.popDWriteFont()

            ui.pushDWriteFont(S.mono.regular)
            S.dclip(S.formatTime(best), 15, vec2(pbRight - 97, rowY), vec2(pbRight, rowY + rowHeight),
                ui.Alignment.Start, ui.Alignment.Center, false, S.colors.textFaint)
            S.dclip(S.formatTime(pbSplit), 15, vec2(pbRight, rowY), vec2(theoreticalRight, rowY + rowHeight),
                ui.Alignment.End, ui.Alignment.Center, false, S.colors.accent)
            ui.popDWriteFont()

            rowY = rowY + 30
        end
        S.cursorY(rowY)
        ui.dummy(vec2(1, 1))
    end)

    if S.button('##delpb', 'Delete PB', vec2(PADDING, deleteY), vec2(halfWidth, 36),
        { fontSize = 14, flat = true, outline = true }) then
        pb.deleteFor(route)
        ghost.deleteFor(route)
    end
    if S.button('##delroute', 'Delete Route', vec2(PADDING + halfWidth + 8, deleteY), vec2(halfWidth, 36),
        { fontSize = 14, flat = true, outline = true }) then
        deleteRoute(route)
    end
end

local function drawShare()
    if S.backArrow('##shback') then
        view = 'list'
    end
    S.text('Import / Export', 19, vec2(42, 13), S.head.bold, S.colors.text)
    S.closeX(vec2(WIDTH, windowHeight), 'LMT Routes')
    S.line(vec2(PADDING, 46), vec2(WIDTH - PADDING, 46), S.colors.line, 1)
    local y = 60

    local body =
        'Routes are plain .lua files. To share one, open the folder below, copy ' ..
        'the route file you want and send it to a friend.\n\n' ..
        'To import a route a friend sent you, drop their .lua file into that same ' ..
        'folder, and the next time you start the game, it will show up.'
    ui.pushDWriteFont(S.fonts.regular)
    S.dclip(body, 14, vec2(PADDING, y), vec2(WIDTH - PADDING, y + 150),
        ui.Alignment.Start, ui.Alignment.Start, true, S.colors.textDim)
    ui.popDWriteFont()
    y = y + 150

    label('ROUTES FOLDER', vec2(PADDING, y))
    y = y + 18
    local chipHeight = 30
    S.rectFill(vec2(PADDING, y), vec2(WIDTH - PADDING, y + chipHeight), S.colors.button, 6)
    S.rect(vec2(PADDING, y), vec2(WIDTH - PADDING, y + chipHeight), S.colors.border, 6, ui.CornerFlags.All, 1)
    ui.pushDWriteFont(S.mono.regular)
    S.dclip(SAVE_DIR, 12, vec2(PADDING + 8, y), vec2(WIDTH - PADDING - 8, y + chipHeight),
        ui.Alignment.Start, ui.Alignment.Center, false, S.colors.text)
    ui.popDWriteFont()
    y = y + chipHeight + 12

    local halfWidth = (WIDTH - PADDING * 2 - 8) * 0.5
    if S.button('##openfolder', 'Open Folder', vec2(PADDING, y), vec2(halfWidth, 34),
        { primary = true, fontSize = 14 }) then
        pcall(os.openInExplorer, SAVE_DIR)
    end
    if S.button('##copypath', 'Copy Path', vec2(PADDING + halfWidth + 8, y), vec2(halfWidth, 34),
        { fontSize = 14, flat = true, outline = true }) then
        pcall(ac.setClipboardText, SAVE_DIR)
    end
end

function routes.window()
    if not listLoaded then
        scan()
    end

    local scale = S.applyScaleInput('lmt_routes')
    local screen = ac.getUI().windowSize
    local maxHeight = math.max(MIN_HEIGHT, math.min(1000, screen.y / scale - 40))
    windowHeight = S.sizeResizableWindow('LMT Routes', 'lmt_routes', WIDTH, MIN_HEIGHT, maxHeight)

    S.windowBackground(vec2(WIDTH, windowHeight), 16)

    if view == 'create' then
        drawCreate()
    elseif view == 'history' and historyRoute then
        drawHistory()
    elseif view == 'share' then
        drawShare()
    else
        drawList()
    end

    S.resizeHandle('lmt_routes', vec2(WIDTH, windowHeight), MIN_HEIGHT, maxHeight)
end

return routes
