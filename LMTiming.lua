local S = require('core.shared')
local gates = require('gates.gates')
local routes = require('routes.routes')
local timing = require('timing.timing')
local delta = require('delta.delta')
local ghost = require('ghost.ghost')
local settings = require('settings.settings')
local main = require('main.main')
local banner = require('banner.banner')

local started = false

local function bootstrap()
    if started then return end
    started = true

    S.init()
    settings.init()
    routes.init()
    ghost.init()
    timing.init()
    delta.init()
    main.init()
    banner.init()
    ac.log('[LMTiming] all modules initialised')
end

function script.update(dt)
    bootstrap()
    timing.update(dt)
end

render.on('main.track.transparent', function()
    if not started then return end

    ghost.draw()

    if routes.isCreating() then
        gates.draw(routes.getCreationGates())
    else
        local route = routes.getSelected()
        if route then
            gates.draw(route.gates, timing.gateLabel)
        end
    end
end)

function mainWindow(dt)
    bootstrap()
    main.window()
end

function timingWindow(dt)
    bootstrap()
    timing.window()
end

function routesWindow(dt)
    bootstrap()
    routes.window()
end

function deltaWindow(dt)
    bootstrap()
    delta.window()
end

function settingsWindow(dt)
    bootstrap()
    settings.window()
end

function fullscreenMain()
    if not started then return end
    banner.draw()
end
