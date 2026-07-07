local S = require('core.shared')

local gates = {}

local GATE_HEIGHT = 3
local DEFAULT_WIDTH = 12
local OUTLINE_THICKNESS = 0.12
local MAX_RENDER_DIST = 100
local DISAPPEAR_AFTER = 2
local MIN_CROSS_SPEED = 1

gates.GATE_HEIGHT = GATE_HEIGHT
gates.DEFAULT_WIDTH = DEFAULT_WIDTH

local typeColor = {
    start = rgbm(0.2, 1.0, 0.4, 1),
    checkpoint = rgbm(1.0, 0.82, 0.1, 1),
    finish = rgbm(1.0, 1.0, 1.0, 1),
}
gates.typeColor = typeColor

function gates.surfaceAt(pos)
    local origin = pos + vec3(0, 2, 0)
    local hitPos = vec3()
    local hitNormal = vec3()
    local dist = render.createRay(origin, vec3(0, -1, 0), 6):physics(hitPos, hitNormal)
    if dist >= 0 then return hitPos:clone() end
    return pos:clone()
end

function gates.create(gateType, width)
    local car = ac.getCar(0)
    if not car then return nil end

    local ground = gates.surfaceAt(car.position)
    local forward = vec3(car.look.x, 0, car.look.z):normalize()
    return { type = gateType, pos = ground, normal = forward, width = width or DEFAULT_WIDTH }
end

local function rightOf(gate)
    return vec3(-gate.normal.z, 0, gate.normal.x)
end

function gates.drawOutlineFrame(gate, color)
    local up = vec3(0, 1, 0)
    local right = rightOf(gate)
    local halfWidth = (gate.width or DEFAULT_WIDTH) * 0.5
    local bottomLeft = gate.pos - right * halfWidth
    local bottomRight = gate.pos + right * halfWidth
    local topLeft = bottomLeft + up * GATE_HEIGHT
    local topRight = bottomRight + up * GATE_HEIGHT

    local function bar(from, to, perpendicular)
        local halfThick = perpendicular * (OUTLINE_THICKNESS * 0.5)
        local extension = (to - from):normalize() * (OUTLINE_THICKNESS * 0.5)
        local fromExtended = from - extension
        local toExtended = to + extension
        render.quad(fromExtended - halfThick, toExtended - halfThick, toExtended + halfThick, fromExtended + halfThick, color)
    end

    render.setDepthMode(S.settings.gateXray and render.DepthMode.Off or render.DepthMode.Normal)
    render.setBlendMode(render.BlendMode.AlphaBlend)
    bar(bottomLeft, bottomRight, up)
    bar(topLeft, topRight, up)
    bar(bottomLeft, topLeft, right)
    bar(bottomRight, topRight, right)
end

local function defaultLabel(gate)
    if gate.type == 'start' then
        return 'Start Line', typeColor.start
    elseif gate.type == 'checkpoint' then
        return 'Checkpoint #' .. (gate.index or 1), typeColor.checkpoint
    elseif gate.type == 'finish' then
        return 'Finish Line', typeColor.finish
    end
    return nil
end

function gates.drawOne(gate, labelFor)
    if gate.type == 'start' and not S.settings.showStart then return end
    if gate.type == 'checkpoint' and not S.settings.showCheckpoint then return end
    if gate.type == 'finish' and not S.settings.showFinish then return end

    if gate.crossed and gate.crossedAt and gate.type ~= 'start' then
        if (os.clock() - gate.crossedAt) > DISAPPEAR_AFTER then return end
    end

    local labelPos = gate.pos + vec3(0, GATE_HEIGHT + 0.6, 0)
    local cameraDistance = ac.getCameraPosition():distance(labelPos)
    local cullDistance = S.settings.renderDistance or MAX_RENDER_DIST
    if S.settings.renderDistanceLimit and cameraDistance > cullDistance then return end

    local color = typeColor[gate.type] or rgbm(1, 1, 1, 1)
    gates.drawOutlineFrame(gate, color)

    if S.settings.showGateText then
        local text, labelColor
        if labelFor then text, labelColor = labelFor(gate) end
        if text == nil then text, labelColor = defaultLabel(gate) end
        if text then
            local scale = math.clamp(40 / math.max(cameraDistance, 1), 0.5, 3)
            render.debugText(labelPos, text, labelColor or color, scale)
        end
    end
end

function gates.draw(list, labelFor)
    if not list then return end
    for i = 1, #list do
        gates.drawOne(list[i], labelFor)
    end
end

function gates.crossed(gate, carPos, lastPos, speed)
    if lastPos == nil then return false end

    local normal = gate.normal
    local distCurrent = (carPos.x - gate.pos.x) * normal.x + (carPos.z - gate.pos.z) * normal.z
    local distLast = (lastPos.x - gate.pos.x) * normal.x + (lastPos.z - gate.pos.z) * normal.z

    if not (distLast < 0 and distCurrent >= 0) then return false end

    local lineX = -normal.z
    local lineZ = normal.x
    local along = (carPos.x - gate.pos.x) * lineX + (carPos.z - gate.pos.z) * lineZ
    if math.abs(along) > (gate.width or DEFAULT_WIDTH) * 0.5 then return false end

    if math.abs(carPos.y - gate.pos.y) > GATE_HEIGHT then return false end

    if speed and speed < MIN_CROSS_SPEED then return false end

    return true
end

function gates.resetRuntime(list)
    if not list then return end
    for i = 1, #list do
        list[i].crossed = nil
        list[i].crossedAt = nil
    end
end

return gates
