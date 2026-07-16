local S = require('core.shared')
local timing = require('timing.timing')

local banner = {}

local accents = {
    red = { fill = rgbm(0.20, 0.03, 0.03, 0.82), border = S.colors.red },
    yellow = { fill = rgbm(0.22, 0.17, 0.02, 0.82), border = S.colors.yellow },
}

local PADDING_X = 16
local ICON_SIZE = 26
local GAP = 12
local FONT_SIZE = 18
local BANNER_HEIGHT = 50

local dragging = false
local dragOffsetX = 0
local dragOffsetY = 0

local preview = { text = 'Drag to position notifications', icon = 'assets/YellowWarning.png', accent = 'yellow' }

function banner.init() end


local function bannerSize(info, bannerScale)
    local textWidth = S.measure(info.text, FONT_SIZE * bannerScale, S.head.bold).x
    local width = (PADDING_X * 2 + ICON_SIZE + GAP) * bannerScale + textWidth
    local height = BANNER_HEIGHT * bannerScale
    return width, height
end


local function drawBannerAt(info, x, y, bannerWidth, bannerHeight, bannerScale)
    local accent = accents[info.accent] or accents.red
    S.panel(vec2(x, y), vec2(x + bannerWidth, y + bannerHeight), 12 * bannerScale, accent.fill, accent.border)

    local iconSize = ICON_SIZE * bannerScale
    local iconY = y + (bannerHeight - iconSize) * 0.5
    ui.drawImage(info.icon, vec2(x + PADDING_X * bannerScale, iconY), vec2(x + PADDING_X * bannerScale + iconSize, iconY + iconSize))

    S.text(info.text, FONT_SIZE * bannerScale,
        vec2(x + (PADDING_X + ICON_SIZE + GAP) * bannerScale, y + (bannerHeight - FONT_SIZE * bannerScale) * 0.5 - 1),
        S.head.bold, S.colors.text
    )
end


function banner.draw()
    local appSettings = S.settings
    if not appSettings then return end

    S.scale = 1
    local adjusting = appSettings.adjustNotifyPos

    local info = timing.activeBanner()
    if appSettings.showNotifications == false then
        info = nil
    end

    if not info and not adjusting then return end
    info = info or preview

    local bannerScale = (S.winScale and S.winScale.scale_banner) or 1
    local screen = ac.getUI().windowSize
    local bannerWidth, bannerHeight = bannerSize(info, bannerScale)

    local centerX = math.clamp(appSettings.notifyX * screen.x, bannerWidth * 0.5, screen.x - bannerWidth * 0.5)
    local centerY = math.clamp(appSettings.notifyY * screen.y, bannerHeight * 0.5, screen.y - bannerHeight * 0.5)

    local x = centerX - bannerWidth * 0.5
    local y = centerY - bannerHeight * 0.5

    if adjusting then
        local mouse = ui.mousePos()
        local over = mouse.x >= x and mouse.x <= x + bannerWidth and mouse.y >= y and mouse.y <= y + bannerHeight

        if over then
            local wheel = ui.mouseWheel()
            if wheel ~= 0 and S.winScale then
                S.winScale.scale_banner = math.clamp(bannerScale + wheel * S.SCALE_STEP, S.SCALE_MIN, S.SCALE_MAX)
            end
        end

        if ui.mouseClicked(ui.MouseButton.Left) and over then
            dragging = true
            dragOffsetX = mouse.x - x
            dragOffsetY = mouse.y - y
        end
        if not ui.mouseDown(ui.MouseButton.Left) then
            dragging = false
        end

        if dragging then
            centerX = math.clamp(mouse.x - dragOffsetX + bannerWidth * 0.5, bannerWidth * 0.5, screen.x - bannerWidth * 0.5)
            centerY = math.clamp(mouse.y - dragOffsetY + bannerHeight * 0.5, bannerHeight * 0.5, screen.y - bannerHeight * 0.5)
            x = centerX - bannerWidth * 0.5
            y = centerY - bannerHeight * 0.5
            appSettings.notifyX = centerX / screen.x
            appSettings.notifyY = centerY / screen.y
        end
    end

    drawBannerAt(info, x, y, bannerWidth, bannerHeight, bannerScale)
end

return banner