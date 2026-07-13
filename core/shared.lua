local S = {}

S.colors = {
    bg = rgbm(0.01, 0.01, 0.01, 0.6),
    border = rgbm(0.6, 0.6, 0.6, 0.5),
    line = rgbm(1, 1, 1, 0.08),
    text = rgbm(1, 1, 1, 1),
    textDim = rgbm(0.90, 0.90, 0.90, 1),
    textFaint = rgbm(0.78, 0.78, 0.78, 1),

    accent = rgbm(0.36, 0.78, 0.42, 1),
    accentHover = rgbm(0.45, 0.86, 0.50, 1),
    accentDim = rgbm(0.20, 0.30, 0.22, 1),

    red = rgbm(0.85, 0.27, 0.27, 1),
    redHover = rgbm(0.95, 0.36, 0.36, 1),
    yellow = rgbm(1.0, 0.78, 0.18, 1),

    row = rgbm(1, 1, 1, 0.035),
    rowHover = rgbm(1, 1, 1, 0.075),
    field = rgbm(0, 0, 0, 0.35),
    button = rgbm(0.14, 0.14, 0.14, 1),
    buttonHover = rgbm(0.21, 0.21, 0.21, 1),
    buttonFlat = rgbm(0.22, 0.22, 0.22, 1),
}

S.fonts = {
    light = ui.DWriteFont('RobotoFlex', 'fonts/RobotoFlex.ttf'):weight(300),
    regular = ui.DWriteFont('RobotoFlex', 'fonts/RobotoFlex.ttf'):weight(400),
    medium = ui.DWriteFont('RobotoFlex', 'fonts/RobotoFlex.ttf'):weight(500),
    bold = ui.DWriteFont('RobotoFlex', 'fonts/RobotoFlex.ttf'):weight(700),
}

S.head = {
    medium = ui.DWriteFont('Montserrat', 'fonts/Montserrat.ttf'):weight(500),
    semibold = ui.DWriteFont('Montserrat', 'fonts/Montserrat.ttf'):weight(600),
    bold = ui.DWriteFont('Montserrat', 'fonts/Montserrat.ttf'):weight(700),
}

S.mono = {
    regular = ui.DWriteFont('GeistMono', 'fonts/GeistMono.ttf'):weight(400),
    medium = ui.DWriteFont('GeistMono', 'fonts/GeistMono.ttf'):weight(500),
    bold = ui.DWriteFont('GeistMono', 'fonts/GeistMono.ttf'):weight(700),
}

S.settings = nil
S.resetButton = nil

S.scale = 1
S.SCALE_MIN = 0.5
S.SCALE_MAX = 2.0
S.SCALE_STEP = 0.1
S.winScale = nil
S._currentWindowId = nil
S._zoomGuard = {}
S._accessors = {}
S._resizeActive = {}
S._resizeGrab = {}

function S.init()
    S.winScale = ac.storage{
        scale_lmt_main = 1.0,
        scale_lmt_timing = 1.0,
        scale_lmt_routes = 1.0,
        scale_lmt_delta = 1.0,
        scale_lmt_settings = 1.0,
        scale_banner = 1.0,
        height_lmt_timing = 380,
        height_lmt_routes = 560,
    }

    S.settings = ac.storage{
        showStart = true,
        showCheckpoint = true,
        showFinish = true,
        showGateText = true,
        gateXray = false,
        renderDistanceLimit = true,
        renderDistance = 170,
        restartOnStart = true,
        showResetButton = false,
        showGhost = true,
        showNotifications = true,
        adjustNotifyPos = false,
        notifyX = 0.5,
        notifyY = 0.08,
    }

    S.resetButton = ac.ControlButton('lmt_reset_run')
    ac.log('[LMTiming] core.shared initialised')
end

function S.applyScaleInput(id)
    S._currentWindowId = id

    local key = 'scale_' .. id
    local scale = (S.winScale and S.winScale[key]) or 1

    if ui.windowHovered(ui.HoveredFlags.ChildWindows) then
        local wheel = ui.mouseWheel()
        if wheel ~= 0 and not S._zoomGuard[id] then
            scale = math.clamp(scale + wheel * S.SCALE_STEP, S.SCALE_MIN, S.SCALE_MAX)
            if S.winScale then S.winScale[key] = scale end
        end
        if ui.mouseClicked(ui.MouseButton.Right) then
            scale = 1.0
            if S.winScale then S.winScale[key] = scale end
        end
    end

    S._zoomGuard[id] = false
    S.scale = scale
    return scale
end

local function accessor(title)
    local cached = S._accessors[title]
    if cached and cached:valid() then return cached end

    local windows = ac.getAppWindows()
    for i = 1, #windows do
        local window = windows[i]
        if window and window.title == title then
            local handle = ac.accessAppWindow(window.name)
            S._accessors[title] = handle
            return handle
        end
    end

    return nil
end

function S.clampToScreen(name)
    if ui.mouseDown(ui.MouseButton.Left) then return end

    local window = accessor(name)
    if not window then return end

    local pos = window:position()
    local size = window:size()
    local uiState = ac.getUI()
    local screen = uiState.windowSize * uiState.uiScale

    local clampedX = math.clamp(pos.x, 0, math.max(0, screen.x - size.x))
    local clampedY = math.clamp(pos.y, 0, math.max(0, screen.y - size.y))
    if math.abs(clampedX - pos.x) > 0.5 or math.abs(clampedY - pos.y) > 0.5 then
        pcall(function() window:move(vec2(clampedX, clampedY)) end)
    end
end

function S.beginWindow(name, id, baseSize)
    local scale = S.applyScaleInput(id)

    local window = accessor(name)
    if window then
        local pixelSize = baseSize * (scale * ac.getUI().uiScale)
        pcall(function() window:resize(pixelSize) end)
    end

    S.clampToScreen(name)
    return scale
end

function S.sizeResizableWindow(name, id, baseWidth, minHeight, maxHeight)
    local heightKey = 'height_' .. id
    local height = math.clamp((S.winScale and S.winScale[heightKey]) or minHeight, minHeight, maxHeight)
    if S.winScale then S.winScale[heightKey] = height end

    local window = accessor(name)
    if window then
        local pixelSize = vec2(baseWidth, height) * (S.scale * ac.getUI().uiScale)
        pcall(function() window:resize(pixelSize) end)
    end

    S.clampToScreen(name)
    return height
end

function S.resizeHandle(id, windowSize, minHeight, maxHeight)
    S.resizeHint(windowSize)

    local gripSize = 20
    ui.setCursor(vec2(windowSize.x - gripSize, windowSize.y - gripSize) * S.scale)
    ui.invisibleButton('##resize_' .. id, vec2(gripSize, gripSize) * S.scale)
    if ui.itemHovered() or ui.itemActive() then
        ui.setMouseCursor(ui.MouseCursor.ResizeNS)
    end

    if ui.itemActive() then
        local cursorHeight = (ui.mousePos().y - ui.windowPos().y) / S.scale
        if not S._resizeActive[id] then
            S._resizeGrab[id] = windowSize.y - cursorHeight
            S._resizeActive[id] = true
        end
        local newHeight = cursorHeight + (S._resizeGrab[id] or 0)
        if S.winScale then
            S.winScale['height_' .. id] = math.clamp(newHeight, minHeight, maxHeight)
        end
    else
        S._resizeActive[id] = false
    end
end

S.WINDOW_IDS = { 'lmt_main', 'lmt_timing', 'lmt_routes', 'lmt_delta', 'lmt_settings' }

function S.resetAllScales()
    if not S.winScale then return end
    for _, id in ipairs(S.WINDOW_IDS) do
        S.winScale['scale_' .. id] = 1.0
    end
    S.winScale.scale_banner = 1.0
end

function S.cursor(pos)
    ui.setCursor(pos * S.scale)
end

function S.cursorY(y)
    ui.setCursorY(y * S.scale)
end

function S.itemWidth(width)
    ui.setNextItemWidth(width * S.scale)
end

function S.availX()
    return ui.availableSpaceX() / S.scale
end

function S.line(p1, p2, color, thickness)
    ui.drawLine(p1 * S.scale, p2 * S.scale, color, (thickness or 1) * S.scale)
end

function S.rectFill(p1, p2, color, rounding)
    ui.drawRectFilled(p1 * S.scale, p2 * S.scale, color, (rounding or 0) * S.scale)
end

function S.rect(p1, p2, color, rounding, flags, thickness)
    ui.drawRect(p1 * S.scale, p2 * S.scale, color, (rounding or 0) * S.scale, flags, (thickness or 1) * S.scale)
end

function S.image(tex, p1, p2, color)
    ui.drawImage(tex, p1 * S.scale, p2 * S.scale, color)
end

function S.circle(center, radius, color)
    ui.drawCircleFilled(center * S.scale, radius * S.scale, color)
end

function S.dclip(str, size, p1, p2, alignX, alignY, wrap, color)
    ui.dwriteDrawTextClipped(str, size * S.scale, p1 * S.scale, p2 * S.scale, alignX, alignY, wrap, color)
end

function S.child(id, pos, size, body)
    local currentWindowId = S._currentWindowId
    ui.setCursor(pos * S.scale)
    ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(0, 0))
    ui.childWindow(id, size * S.scale, false, function()
        body()
        if currentWindowId and ui.windowHovered() and ui.getScrollMaxY() > 0 then
            S._zoomGuard[currentWindowId] = true
        end
    end)
    ui.popStyleVar()
end

function S.text(str, size, pos, font, color)
    ui.pushDWriteFont(font or S.fonts.regular)
    ui.dwriteDrawText(str, size * S.scale, pos * S.scale, color or S.colors.text)
    ui.popDWriteFont()
end

function S.textCentered(str, size, y, width, font, color, xOffset)
    ui.pushDWriteFont(font or S.fonts.regular)
    local textSize = ui.measureDWriteText(str, size)
    local pos = vec2((xOffset or 0) + (width - textSize.x) * 0.5, y)
    ui.dwriteDrawText(str, size * S.scale, pos * S.scale, color or S.colors.text)
    ui.popDWriteFont()
    return textSize
end

function S.textRight(str, size, xRight, y, font, color)
    ui.pushDWriteFont(font or S.fonts.regular)
    local textSize = ui.measureDWriteText(str, size)
    ui.dwriteDrawText(str, size * S.scale, vec2(xRight - textSize.x, y) * S.scale, color or S.colors.text)
    ui.popDWriteFont()
    return textSize
end

function S.measure(str, size, font)
    ui.pushDWriteFont(font or S.fonts.regular)
    local textSize = ui.measureDWriteText(str, size)
    ui.popDWriteFont()
    return textSize
end

function S.roundedRectPath(p1, p2, rounding, segments)
    segments = segments or 14
    local scale = S.scale
    p1 = p1 * scale
    p2 = p2 * scale
    rounding = rounding * scale

    local radius = math.min(rounding, (p2.x - p1.x) * 0.5, (p2.y - p1.y) * 0.5)
    local quarterTurn = math.pi * 0.5
    ui.pathArcTo(vec2(p1.x + radius, p1.y + radius), radius, math.pi, math.pi + quarterTurn, segments)
    ui.pathArcTo(vec2(p2.x - radius, p1.y + radius), radius, math.pi + quarterTurn, math.pi * 2, segments)
    ui.pathArcTo(vec2(p2.x - radius, p2.y - radius), radius, 0, quarterTurn, segments)
    ui.pathArcTo(vec2(p1.x + radius, p2.y - radius), radius, quarterTurn, math.pi, segments)
end

function S.panel(p1, p2, rounding, fill, border)
    rounding = rounding or 16
    S.roundedRectPath(p1, p2, rounding)
    ui.pathFillConvex(fill or S.colors.bg)
    S.roundedRectPath(p1, p2, rounding)
    ui.pathStroke(border or S.colors.border, true, 1 * S.scale)
end

function S.windowBackground(size, rounding)
    S.panel(vec2(1, 1), vec2(size.x - 1, size.y - 1), rounding or 16)
end

function S.closeX(size, windowTitle)
    local buttonSize = 24
    local margin = 12
    local top = 12
    local buttonX = size.x - margin - buttonSize

    ui.setCursor(vec2(buttonX, top) * S.scale)
    local clicked = ui.invisibleButton('##close_' .. windowTitle, vec2(buttonSize, buttonSize) * S.scale)
    local hovered = ui.itemHovered()
    if hovered then ui.setMouseCursor(ui.MouseCursor.Hand) end

    S.image('assets/Close.png',
        vec2(buttonX + 4, top + 4),
        vec2(buttonX + buttonSize - 4, top + buttonSize - 4),
        hovered and S.colors.text or S.colors.textDim)

    if clicked then S.closeWindow(windowTitle) end
end

function S.header(title, size, opts)
    opts = opts or {}
    local padding = 16
    local y = 14

    S.text(title, 19, vec2(padding, y), S.head.bold, S.colors.text)
    if opts.windowTitle then S.closeX(size, opts.windowTitle) end
    S.line(vec2(padding, y + 34), vec2(size.x - padding, y + 34), S.colors.line, 1)

    return y + 48
end

function S.backArrow(id)
    local buttonSize = 24
    local margin = 12
    local top = 12
    local glyphSize = 12
    local inset = (buttonSize - glyphSize) * 0.5

    ui.setCursor(vec2(margin, top) * S.scale)
    local clicked = ui.invisibleButton(id, vec2(buttonSize, buttonSize) * S.scale)
    local hovered = ui.itemHovered()
    if hovered then ui.setMouseCursor(ui.MouseCursor.Hand) end

    S.image('assets/ArrowLeft.png',
        vec2(margin + inset, top + inset),
        vec2(margin + inset + glyphSize, top + inset + glyphSize),
        hovered and S.colors.text or S.colors.textDim)

    return clicked
end

function S.button(id, label, pos, size, opts)
    opts = opts or {}
    local scale = S.scale

    ui.setCursor(pos * scale)
    local clicked = ui.invisibleButton(id, size * scale)
    local hovered = ui.itemHovered() or opts.forceHover
    local hoverShift = hovered and not opts.flat
    local rounding = opts.rounding or 6

    local background
    if opts.disabled then
        background = rgbm(0.1, 0.1, 0.1, 0.6)
    elseif opts.primary then
        background = hoverShift and S.colors.accentHover or S.colors.accent
    elseif opts.danger then
        background = hoverShift and S.colors.redHover or S.colors.red
    elseif opts.flat then
        background = hovered and S.colors.border or S.colors.buttonFlat
    else
        background = hovered and S.colors.buttonHover or S.colors.button
    end
    S.rectFill(pos, pos + size, background, rounding)

    if opts.outline then
        local outlineColor = opts.outline == true and S.colors.border or opts.outline
        S.rect(pos, pos + size, outlineColor, rounding, ui.CornerFlags.All, 1)
    end

    local fontSize = opts.fontSize or 15
    local textColor
    if opts.disabled then
        textColor = S.colors.textFaint
    elseif opts.textColor then
        textColor = opts.textColor
    elseif opts.primary then
        textColor = rgbm(0.05, 0.1, 0.05, 1)
    else
        textColor = S.colors.text
    end

    local labelFont = opts.font or S.fonts.medium
    local textSize = S.measure(label, fontSize, labelFont)
    S.text(label, fontSize, pos + (size - textSize) * 0.5, labelFont, textColor)

    if hovered and not opts.disabled then ui.setMouseCursor(ui.MouseCursor.Hand) end
    return clicked and not opts.disabled
end

function S.toggle(id, pos, value, size)
    size = size or vec2(40, 22)

    ui.setCursor(pos * S.scale)
    local clicked = ui.invisibleButton(id, size * S.scale)
    if ui.itemHovered() then ui.setMouseCursor(ui.MouseCursor.Hand) end

    local radius = size.y * 0.5
    S.rectFill(pos, pos + size, value and S.colors.accent or rgbm(0.28, 0.28, 0.28, 1), radius)

    local knobX = value and (pos.x + size.x - radius) or (pos.x + radius)
    S.circle(vec2(knobX, pos.y + radius), radius - 3, rgbm(1, 1, 1, 1))

    if clicked then return not value end
    return value
end

function S.field(p1, p2, rounding)
    S.rectFill(p1, p2, S.colors.field, rounding or 6)
end

function S.closeWindow(title)
    local windows = ac.getAppWindows()
    for i = 1, #windows do
        local window = windows[i]
        if window and window.title == title then
            local handle = ac.accessAppWindow(window.name)
            if handle then pcall(function() handle:setVisible(false) end) end
            return
        end
    end
end

function S.splitList(str)
    local items = {}
    if not str then return items end

    for part in tostring(str):gmatch('[^,]+') do
        local trimmed = part:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed ~= '' then
            items[#items + 1] = trimmed
        end
    end

    return items
end

S.TRAFFIC_TYPES = { 'Light', 'Realistic', 'Heavy', 'Rush Hour' }

function S.serverName()
    local ok, name = pcall(ac.getServerName)
    if ok and name then return name end
    return ''
end

local function normalize(text)
    return text:lower():gsub('%s', '')
end

function S.isNoHesi()
    return normalize(S.serverName()):find('nohesi', 1, true) ~= nil
end

function S.serverHasTraffic(traffic)
    local allowedKinds = S.splitList(traffic)
    if #allowedKinds == 0 then return true end
    if not S.isNoHesi() then return true end

    local serverText = normalize(S.serverName())
    for _, kind in ipairs(allowedKinds) do
        if serverText:find(normalize(kind .. ' Traffic'), 1, true) ~= nil then
            return true
        end
    end

    return false
end

function S.resizeHint(windowSize)
    local hintSize = 14
    local p1 = vec2(windowSize.x - hintSize - 3, windowSize.y - hintSize - 3)
    local p2 = vec2(windowSize.x - 3, windowSize.y - 3)
    S.image('assets/Resize.png', p1, p2, S.colors.textFaint)
end

function S.formatTime(seconds)
    if seconds == nil then return '--:--.---' end
    local minutes = math.floor(seconds / 60)
    local remainder = seconds - minutes * 60
    return string.format('%d:%06.3f', minutes, remainder)
end

function S.formatDelta(delta)
    if delta == nil then return '' end
    return string.format('%+.2f', delta)
end

return S
