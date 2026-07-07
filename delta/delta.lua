local S = require('core.shared')
local timing = require('timing.timing')

local delta = {}

local WIDTH = 580
local HEIGHT = 88
local FULL_SCALE = 2.0

function delta.init() end

function delta.window()
    S.beginWindow('LMT Delta Bar', 'lmt_delta', vec2(WIDTH, HEIGHT))
    S.windowBackground(vec2(WIDTH, HEIGHT), 14)

    local gap = timing.liveDelta()
    local ahead = gap and gap < 0

    local text = gap and S.formatDelta(gap) or '--'
    local color
    if not gap then
        color = S.colors.textDim
    elseif ahead then
        color = S.colors.accent
    else
        color = S.colors.red
    end
    S.textCentered(text, 42, 8, WIDTH, S.mono.bold, color)

    local barY = HEIGHT - 22
    local barLeft = 28
    local barRight = WIDTH - 28
    local center = (barLeft + barRight) * 0.5
    S.rectFill(vec2(barLeft, barY), vec2(barRight, barY + 10), rgbm(1, 1, 1, 0.08), 5)

    if gap then
        local magnitude = math.clamp(math.abs(gap) / FULL_SCALE, 0, 1)
        if ahead then
            S.rectFill(vec2(center, barY), vec2(center + (barRight - center) * magnitude, barY + 10), S.colors.accent, 5)
        else
            S.rectFill(vec2(center - (center - barLeft) * magnitude, barY), vec2(center, barY + 10), S.colors.red, 5)
        end
    end

    S.line(vec2(center, barY - 3), vec2(center, barY + 13), rgbm(1, 1, 1, 0.3), 1)
end

return delta
