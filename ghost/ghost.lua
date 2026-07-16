local S = require('core.shared')
local pb = require('pb.pb')

local ghost = {}

local APP_DIR = __dirname or '.'
local GHOST_DIR = APP_DIR .. '/recordedGhosts'

local FORMAT_VERSION = 1
local SAMPLE_INTERVAL = 0.05
local FRAME_STRIDE = 10
local SEARCH_BACK = 15
local SEARCH_FORWARD = 40

local FADE_NEAR = 3
local FADE_FAR = 17
local MAX_ALPHA = 0.3
local TINT = vec3(0.53333, 0.0, 0.94118)

local context = nil

local pbData = nil
local frameCount = 0

local recording = nil
local recordingLastTime = nil

local playCursor = 1
local projectionCursor = 1

local drawAlpha = 0

local meshParams = {
    mesh = nil,
    transform = mat4x4.identity(),
    textures = {},
    values = { gTint = TINT, gAlpha = MAX_ALPHA },

    shader = [[
        float4 main(PS_IN pin) {
            return float4((pin.NormalW.yyy + 1) * gTint * gWhiteRefPoint, gAlpha * pin.FogAlphaMultiplier());
        }
    ]]
}


local function sanitize(name)
    return (name or 'route'):gsub('[^%w_]', '_')
end


local function recordingPath(route)
    return GHOST_DIR .. '/' .. sanitize(route.name) .. '__' .. sanitize(pb.carKeyFor(route)) .. '.ghost'
end


local function frameBase(index)
    return (index - 1) * FRAME_STRIDE
end


local function frameTime(index)
    return pbData.frames[frameBase(index) + 1]
end


local function framePosition(index, out)
    local base = frameBase(index)
    return out:set(pbData.frames[base + 2], pbData.frames[base + 3], pbData.frames[base + 4])
end


local function resolveCarShape()
    meshParams.mesh = nil
    if not pbData then return end

    local shapeCarIndex = nil
    local sim = ac.getSim()
    for i = 0, sim.carsCount - 1 do
        if ac.getCarID(i) == pbData.carId then
            shapeCarIndex = i
            break
        end
    end

    if shapeCarIndex == nil then
        shapeCarIndex = 0
        ac.log('[LMTiming] ghost: PB car ' .. tostring(pbData.carId) .. ' is not in this session, using the player car shape')
    end

    meshParams.mesh = ac.SimpleMesh.carShape(shapeCarIndex, true)
end


function ghost.init()
    pcall(io.createDir, GHOST_DIR)
    ac.log('[LMTiming] ghost module initialised')
end


function ghost.setRoute(route)
    ghost.abortRun()
    pbData = nil
    frameCount = 0
    context = nil

    if not route then
        resolveCarShape()
        return
    end

    context = { route = route, file = recordingPath(route) }


    local raw = io.load(context.file, nil)
    if raw then
        local parsed = stringify.binary.tryParse(raw, nil)

        if parsed and parsed.version == FORMAT_VERSION and parsed.carId
                and type(parsed.frames) == 'table' and #parsed.frames >= FRAME_STRIDE * 2 then
            pbData = parsed
            frameCount = math.floor(#parsed.frames / FRAME_STRIDE)
            ac.log('[LMTiming] ghost: loaded ' .. frameCount .. ' frames for ' .. (route.name or '?'))
        else
            ac.log('[LMTiming] ghost: file for ' .. (route.name or '?') .. ' is unreadable, ignoring')
        end
    end

    resolveCarShape()
end


function ghost.hasRecording()
    return pbData ~= nil and frameCount >= 2
end


function ghost.beginRun()
    playCursor = 1
    projectionCursor = 1
    recording = {}
    recordingLastTime = nil
    drawAlpha = 0
end


function ghost.abortRun()
    recording = nil
    recordingLastTime = nil
    drawAlpha = 0
end


function ghost.recordFrame(elapsed, car, force)
    if not recording then return end

    if not force and recordingLastTime and (elapsed - recordingLastTime) < SAMPLE_INTERVAL then return end
    recordingLastTime = elapsed

    local body = car.bodyTransform
    local position = body.position
    local look = body.look
    local up = body.up

    local n = #recording
    recording[n + 1] = elapsed
    recording[n + 2] = position.x
    recording[n + 3] = position.y
    recording[n + 4] = position.z
    recording[n + 5] = look.x
    recording[n + 6] = look.y
    recording[n + 7] = look.z
    recording[n + 8] = up.x
    recording[n + 9] = up.y
    recording[n + 10] = up.z
end


function ghost.discardRecording()
    recording = nil
    recordingLastTime = nil
end


function ghost.saveRecording(route, runTime)
    local frames = recording
    recording = nil
    recordingLastTime = nil

    if not frames or #frames < FRAME_STRIDE * 2 then return end
    if not context or not route then return end

    local saved = {
        version = FORMAT_VERSION,
        carId = ac.getCarID(0) or 'unknown',
        time = runTime,
        rate = 1 / SAMPLE_INTERVAL,
        frames = frames,
    }


    pcall(io.createDir, GHOST_DIR)
    local ok = io.save(context.file, stringify.binary(saved))
    if ok then
        pbData = saved
        frameCount = math.floor(#frames / FRAME_STRIDE)
        playCursor = 1
        projectionCursor = 1
        resolveCarShape()
        ac.log('[LMTiming] ghost: saved recording (' .. frameCount .. ' frames)')
    else
        ac.log('[LMTiming] ghost: failed to save recording')
    end
end

local samplePos0 = vec3()
local samplePos1 = vec3()
local sampleLook = vec3()
local sampleUp = vec3()


local function sampleAtTime(elapsed)
    if elapsed <= frameTime(1) then
        playCursor = 1
    elseif elapsed >= frameTime(frameCount) then
        playCursor = frameCount - 1
    else
        if frameTime(playCursor) > elapsed then playCursor = 1 end
        while playCursor < frameCount - 1 and frameTime(playCursor + 1) < elapsed do
            playCursor = playCursor + 1
        end
    end

    local baseA = frameBase(playCursor)
    local baseB = frameBase(playCursor + 1)
    local timeA = pbData.frames[baseA + 1]
    local timeB = pbData.frames[baseB + 1]
    local mix = math.clamp((elapsed - timeA) / math.max(timeB - timeA, 0.0001), 0, 1)

    local function lerpComponent(offset)
        local a = pbData.frames[baseA + offset]
        local b = pbData.frames[baseB + offset]
        return a + (b - a) * mix
    end

    samplePos0:set(lerpComponent(2), lerpComponent(3), lerpComponent(4))
    sampleLook:set(lerpComponent(5), lerpComponent(6), lerpComponent(7)):normalize()
    sampleUp:set(lerpComponent(8), lerpComponent(9), lerpComponent(10)):normalize()
    return samplePos0, sampleLook, sampleUp
end


function ghost.update(running, elapsed, playerPos)
    drawAlpha = 0

    if not ghost.hasRecording() or meshParams.mesh == nil then return end
    if not running or not S.settings.showGhost or ac.getSim().isReplayActive then return end

    local position, look, up = sampleAtTime(elapsed)

    local sideX = up.y * look.z - up.z * look.y
    local sideY = up.z * look.x - up.x * look.z
    local sideZ = up.x * look.y - up.y * look.x

    local transform = meshParams.transform
    transform.row1:set(sideX, sideY, sideZ, 0)
    transform.row2:set(up.x, up.y, up.z, 0)
    transform.row3:set(look.x, look.y, look.z, 0)
    transform.row4:set(position.x, position.y, position.z, 1)

    local fade = 1
    if playerPos then
        fade = math.clamp((position:distance(playerPos) - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0, 1)
    end
    drawAlpha = MAX_ALPHA * fade
end


function ghost.draw()
    if drawAlpha <= 0.005 then return end

    render.setBlendMode(render.BlendMode.AlphaBlend)
    render.setCullMode(render.CullMode.None)
    render.setDepthMode(render.DepthMode.ReadOnly)
    meshParams.values.gAlpha = drawAlpha
    render.mesh(meshParams)
end


function ghost.liveDelta(carPos, elapsed)
    if not ghost.hasRecording() then return nil end

    local carX = carPos.x
    local carZ = carPos.z
    local from = math.max(1, projectionCursor - SEARCH_BACK)
    local to = math.min(frameCount - 1, projectionCursor + SEARCH_FORWARD)

    local bestIndex = projectionCursor
    local bestFraction = 0
    local bestDistSq = math.huge

    framePosition(from, samplePos0)
    for i = from, to do
        framePosition(i + 1, samplePos1)

        local segX = samplePos1.x - samplePos0.x
        local segZ = samplePos1.z - samplePos0.z
        local lengthSq = segX * segX + segZ * segZ

        local fraction = 0
        if lengthSq > 0.000001 then
            fraction = math.clamp(((carX - samplePos0.x) * segX + (carZ - samplePos0.z) * segZ) / lengthSq, 0, 1)
        end

        local dx = carX - (samplePos0.x + segX * fraction)
        local dz = carZ - (samplePos0.z + segZ * fraction)
        local distSq = dx * dx + dz * dz
        if distSq < bestDistSq then
            bestDistSq = distSq
            bestIndex = i
            bestFraction = fraction
        end

        samplePos0:set(samplePos1)
    end

    projectionCursor = bestIndex

    local timeA = frameTime(bestIndex)
    local timeB = frameTime(bestIndex + 1)
    local ghostTime = timeA + (timeB - timeA) * bestFraction
    return elapsed - ghostTime
end


function ghost.syncToTime(pbTime)
    if not ghost.hasRecording() then return end

    local low = 1
    local high = frameCount
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        if frameTime(mid) <= pbTime then
            low = mid
        else
            high = mid - 1
        end
    end

    projectionCursor = math.min(low, frameCount - 1)
end


function ghost.deleteRecording(route)
    pcall(io.deleteFile, recordingPath(route))

    if context and context.route == route then
        ghost.abortRun()
        pbData = nil
        frameCount = 0
        resolveCarShape()
    end
end


function ghost.deleteAllRecordings(route)
    local prefix = sanitize(route.name) .. '__'
    local ok, files = pcall(io.scanDir, GHOST_DIR, '*.ghost')
    if ok and files then
        for _, file in ipairs(files) do
            if file:sub(1, #prefix) == prefix then
                pcall(io.deleteFile, GHOST_DIR .. '/' .. file)
            end
        end
    end

    if context and context.route == route then
        ghost.abortRun()
        pbData = nil
        frameCount = 0
        resolveCarShape()
    end
end

return ghost
