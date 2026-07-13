local S = require('core.shared')

local pb = {}

local changeListeners = {}

function pb.onChanged(listener)
    changeListeners[#changeListeners + 1] = listener
end

local function routeKey(route)
    return 'LMT_pb_' .. ((route.name or 'route'):gsub('[^%w_]', '_'))
end

function pb.carKeyFor(route)
    if route.carRestrict and route.carRestrict ~= '' then return 'fixed' end
    return ac.getCarID(0) or 'unknown'
end

local proxies = {}

local function proxy(route)
    local key = routeKey(route)
    if not proxies[key] then
        proxies[key] = ac.storage({ [key] = '' })
    end
    return proxies[key], key
end

local function loadAll(route)
    local store, key = proxy(route)
    return stringify.tryParse(store[key], nil, {}) or {}
end

local function blank()
    return { time = nil, splits = {}, best = {}, bestSectors = {}, lastTime = nil, lastSplits = {} }
end

local function validList(value)
    return type(value) == 'table' and value.type == nil
end

local function copyList(source)
    local copy = {}
    if type(source) == 'table' then
        for i = 1, #source do
            copy[i] = source[i]
        end
    end
    return copy
end

function pb.load(route)
    local rec = loadAll(route)[pb.carKeyFor(route)] or blank()

    if not validList(rec.splits) and validList(rec.lastSplits) and rec.lastTime == rec.time then
        rec.splits = copyList(rec.lastSplits)
    end

    if not validList(rec.splits) then rec.splits = {} end
    if not validList(rec.lastSplits) then rec.lastSplits = {} end
    if not validList(rec.best) then rec.best = {} end
    if not validList(rec.bestSectors) then rec.bestSectors = {} end

    return rec
end

function pb.save(route, rec)
    local all = loadAll(route)
    all[pb.carKeyFor(route)] = rec
    local store, key = proxy(route)
    store[key] = stringify(all, true)
end

local function foldBests(rec, splits, finalSector)
    rec.best = rec.best or {}
    rec.bestSectors = rec.bestSectors or {}

    local previous = 0
    for i = 1, #splits do
        if not rec.best[i] or splits[i] < rec.best[i] then
            rec.best[i] = splits[i]
        end
        local sector = splits[i] - previous
        if not rec.bestSectors[i] or sector < rec.bestSectors[i] then
            rec.bestSectors[i] = sector
        end
        previous = splits[i]
    end

    if finalSector then
        local i = #splits + 1
        if not rec.bestSectors[i] or finalSector < rec.bestSectors[i] then
            rec.bestSectors[i] = finalSector
        end
    end
end

function pb.recordRun(route, time, splits, trace)
    local rec = pb.load(route)
    rec.lastTime = time
    rec.lastSplits = copyList(splits)

    if not rec.time or time < rec.time then
        rec.time = time
        rec.splits = copyList(splits)
        rec.trace = trace
    end

    foldBests(rec, splits, time - (splits[#splits] or 0))
    pb.save(route, rec)
    return rec
end

function pb.recordPartial(route, splits)
    if not splits or #splits == 0 then return nil end

    local rec = pb.load(route)
    foldBests(rec, splits, nil)
    pb.save(route, rec)
    return rec
end

function pb.theoretical(rec)
    if not rec or not rec.bestSectors or #rec.bestSectors == 0 then return nil end

    local sum = 0
    for i = 1, #rec.bestSectors do
        sum = sum + rec.bestSectors[i]
    end
    return sum
end

function pb.deleteFor(route)
    local all = loadAll(route)
    all[pb.carKeyFor(route)] = nil
    local store, key = proxy(route)
    store[key] = stringify(all, true)
    proxies[key] = nil
    for i = 1, #changeListeners do
        changeListeners[i](route)
    end
end

return pb
