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

local function storageFor(route)
    local key = routeKey(route)
    if not proxies[key] then
        proxies[key] = ac.storage({ [key] = '' })
    end
    return proxies[key], key
end

local function loadAllRecords(route)
    local store, key = storageFor(route)
    return stringify.tryParse(store[key], nil, {}) or {}
end

local function blankRecord()
    return { time = nil, splits = {}, best = {}, bestSectors = {}, lastTime = nil, lastSplits = {} }
end

local function isPlainList(value)
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
    local record = loadAllRecords(route)[pb.carKeyFor(route)] or blankRecord()

    if not isPlainList(record.splits) and isPlainList(record.lastSplits) and record.lastTime == record.time then
        record.splits = copyList(record.lastSplits)
    end
    if not isPlainList(record.splits) then record.splits = {} end
    if not isPlainList(record.lastSplits) then record.lastSplits = {} end
    if not isPlainList(record.best) then record.best = {} end
    if not isPlainList(record.bestSectors) then record.bestSectors = {} end

    return record
end

function pb.save(route, record)
    local all = loadAllRecords(route)
    all[pb.carKeyFor(route)] = record
    local store, key = storageFor(route)
    store[key] = stringify(all, true)
end

local function updateBests(record, splits, finalSector)
    record.best = record.best or {}
    record.bestSectors = record.bestSectors or {}

    local previous = 0
    for i = 1, #splits do
        if not record.best[i] or splits[i] < record.best[i] then
            record.best[i] = splits[i]
        end

        local sector = splits[i] - previous
        if not record.bestSectors[i] or sector < record.bestSectors[i] then
            record.bestSectors[i] = sector
        end
        previous = splits[i]
    end

    if finalSector then
        local i = #splits + 1
        if not record.bestSectors[i] or finalSector < record.bestSectors[i] then
            record.bestSectors[i] = finalSector
        end
    end
end

function pb.recordRun(route, time, splits)
    local record = pb.load(route)

    record.lastTime = time
    record.lastSplits = copyList(splits)

    if not record.time or time < record.time then
        record.time = time
        record.splits = copyList(splits)
        record.trace = nil
    end

    updateBests(record, splits, time - (splits[#splits] or 0))
    pb.save(route, record)
    return record
end

function pb.recordPartial(route, splits)
    if not splits or #splits == 0 then return nil end

    local record = pb.load(route)
    updateBests(record, splits, nil)
    pb.save(route, record)
    return record
end

function pb.theoreticalBest(record)
    if not record or not record.bestSectors or #record.bestSectors == 0 then return nil end

    local sum = 0
    for i = 1, #record.bestSectors do
        sum = sum + record.bestSectors[i]
    end
    return sum
end

function pb.deleteRecord(route)
    local all = loadAllRecords(route)
    all[pb.carKeyFor(route)] = nil
    local store, key = storageFor(route)
    store[key] = stringify(all, true)

    proxies[key] = nil

    for i = 1, #changeListeners do
        changeListeners[i](route)
    end
end

return pb
