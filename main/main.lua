local S = require('core.shared')

local main = {}

local WIDTH = 360
local HEIGHT = 410
local PADDING = 16

local DEVELOPER = 'Littleman40'
local VERSION = '1.0.0'
local DISCLAIMER = 'LMTiming is an unofficial, third-party app made for use on No Hesi servers. ' ..
    'It is not affiliated with, endorsed by, or associated with No Hesi or its creators. ' ..
    'All trademarks and game content belong to their respective owners. Use at your own risk.'

function main.init() end

local apps = {
    { name = 'Timing', description = 'The core timing app with live splits and deltas.' },
    { name = 'Routes', description = 'Create, share, manage and see your routes.' },
    { name = 'Delta Bar', description = 'A visual live gap compared to your PB.' },
    { name = 'Settings', description = 'Manage settings and hotkeys for the entire app.' },
}

function main.window()
    S.beginWindow('LMT Info', 'lmt_main', vec2(WIDTH, HEIGHT))
    S.windowBackground(vec2(WIDTH, HEIGHT), 16)

    S.text('LMTiming', 22, vec2(PADDING, 15), S.head.bold, S.colors.text)
    S.closeX(vec2(WIDTH, HEIGHT), 'LMT Info')
    S.line(vec2(PADDING, 52), vec2(WIDTH - PADDING, 52), S.colors.line, 1)
    local y = 66

    for _, app in ipairs(apps) do
        S.text(app.name, 15, vec2(PADDING, y), S.head.bold, S.colors.text)
        y = y + 18
        S.text(app.description, 13, vec2(PADDING, y), S.fonts.regular, S.colors.textDim)
        y = y + 26
    end

    y = y + 2
    S.line(vec2(PADDING, y), vec2(WIDTH - PADDING, y), S.colors.line, 1)
    y = y + 16

    S.text('Developer: ' .. DEVELOPER, 12, vec2(PADDING, y), S.head.semibold, S.colors.textFaint)
    S.textRight('Version: ' .. VERSION, 12, WIDTH - PADDING, y, S.head.semibold, S.colors.textFaint)
    y = y + 28

    S.text('Disclaimer:', 12, vec2(PADDING, y), S.head.semibold, S.colors.textFaint)
    y = y + 20
    ui.pushDWriteFont(S.fonts.regular)
    S.dclip(DISCLAIMER, 12, vec2(PADDING, y), vec2(WIDTH - PADDING, HEIGHT - PADDING),
        ui.Alignment.Start, ui.Alignment.Start, true, S.colors.textFaint)
    ui.popDWriteFont()
end

return main
