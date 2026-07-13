local S = require('core.shared')

local settings = {}

local WIDTH = 360
local HEIGHT = 782
local PADDING = 18

function settings.init() end

local function slider(id, pos, width, value, minValue, maxValue, disabled)
    local trackHeight = 6
    local p1 = vec2(pos.x, pos.y + 8)
    local p2 = vec2(pos.x + width, pos.y + 8 + trackHeight)
    local fraction = (value - minValue) / (maxValue - minValue)
    local fill = disabled and rgbm(0.4, 0.4, 0.4, 1) or S.colors.accent
    local knob = disabled and rgbm(0.55, 0.55, 0.55, 1) or rgbm(1, 1, 1, 1)
    S.rectFill(p1, p2, rgbm(1, 1, 1, 0.1), 3)
    S.rectFill(p1, vec2(pos.x + width * fraction, p2.y), fill, 3)
    S.circle(vec2(pos.x + width * fraction, pos.y + 11), 8, knob)

    if not disabled then
        ui.setCursor(pos * S.scale)
        ui.invisibleButton(id, vec2(width, 22) * S.scale)
        if ui.itemActive() then
            local mouseX = (ui.mousePos().x - ui.windowPos().x) / S.scale
            value = minValue + math.clamp((mouseX - pos.x) / width, 0, 1) * (maxValue - minValue)
        end
        if ui.itemHovered() then
            ui.setMouseCursor(ui.MouseCursor.Hand)
        end
    end

    return value
end

local function sectionHeading(title, description, y)
    S.text(title, 16, vec2(PADDING, y), S.head.bold, S.colors.text)
    if description then
        local titleWidth = S.measure(title, 16, S.head.bold).x
        S.text(description, 12, vec2(PADDING + titleWidth + 10, y + 4), S.fonts.regular, S.colors.textFaint)
    end
end

local function toggleRow(id, text, y, value, dotColor)
    if dotColor then
        S.circle(vec2(PADDING + 6, y + 12), 5, dotColor)
    end
    S.text(text, 15, vec2(PADDING + (dotColor and 22 or 0), y + 2), S.fonts.regular, S.colors.text)
    return S.toggle(id, vec2(WIDTH - PADDING - 48, y), value, vec2(44, 24))
end

function settings.window()
    S.beginWindow('LMT Settings', 'lmt_settings', vec2(WIDTH, HEIGHT))
    S.windowBackground(vec2(WIDTH, HEIGHT), 16)

    local appSettings = S.settings
    local y = S.header('Settings', vec2(WIDTH, HEIGHT), { windowTitle = 'LMT Settings' })

    sectionHeading('Timing Gate Settings', nil, y)
    y = y + 32

    appSettings.showStart = toggleRow('##tStart', 'Start Gate', y, appSettings.showStart)
    y = y + 36
    appSettings.showCheckpoint = toggleRow('##tCp', 'Checkpoint Gates', y, appSettings.showCheckpoint)
    y = y + 36
    appSettings.showFinish = toggleRow('##tFin', 'Finish Gate', y, appSettings.showFinish)
    y = y + 36
    appSettings.showGateText = toggleRow('##tText', 'Gate Text', y, appSettings.showGateText)
    y = y + 36
    appSettings.gateXray = toggleRow('##tXray', 'Gate X-Ray', y, appSettings.gateXray)
    y = y + 36

    appSettings.renderDistanceLimit = toggleRow('##tDist', 'Gate Render Distance', y, appSettings.renderDistanceLimit)
    y = y + 36

    local renderDistanceDisabled = not appSettings.renderDistanceLimit
    local renderDistanceColor = renderDistanceDisabled and S.colors.textFaint or S.colors.text
    S.text('Render Distance', 15, vec2(PADDING, y + 2), S.fonts.regular, renderDistanceColor)
    S.textRight(string.format('%dm', math.floor(appSettings.renderDistance + 0.5)), 14, WIDTH - PADDING, y + 3,
        S.mono.medium, renderDistanceColor)
    y = y + 26
    appSettings.renderDistance = math.floor(
        slider('##rdist', vec2(PADDING, y), WIDTH - PADDING * 2, appSettings.renderDistance, 25, 500, renderDistanceDisabled) + 0.5)
    y = y + 36

    sectionHeading('Notifications', nil, y)
    y = y + 32

    appSettings.showNotifications = toggleRow('##tNotif', 'Show Notifications', y, appSettings.showNotifications)
    y = y + 36

    appSettings.adjustNotifyPos = toggleRow('##tNotifyPos', 'Adjust Notification Position', y, appSettings.adjustNotifyPos)
    y = y + 36

    sectionHeading('Ghost Car', nil, y)
    y = y + 32

    appSettings.showGhost = toggleRow('##tGhost', 'Show Ghost Car', y, appSettings.showGhost)
    y = y + 36

    sectionHeading('Run', nil, y)
    y = y + 32

    appSettings.restartOnStart = toggleRow('##tRestart', 'Always Restart Runs On Start Line', y, appSettings.restartOnStart)
    y = y + 36
    appSettings.showResetButton = toggleRow('##tResetBtn', 'Show Reset Run Button', y, appSettings.showResetButton)
    y = y + 36

    S.text('Reset Run Keybind:', 15, vec2(PADDING, y + 2), S.fonts.regular, S.colors.text)
    y = y + 26
    ui.setCursor(vec2(PADDING, y) * S.scale)
    if S.resetButton then
        S.resetButton:control(vec2(WIDTH - PADDING * 2, 36) * S.scale)
    end
    y = y + 36 + 18

    if S.button('##resetscales', 'Reset all app scales to 100%', vec2(PADDING, y), vec2(WIDTH - PADDING * 2, 36),
        { flat = true, outline = true, fontSize = 14 }) then
        S.resetAllScales()
    end
end

return settings
