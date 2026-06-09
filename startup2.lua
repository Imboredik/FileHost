local fuel_store = peripheral.find("minecraft:barrel")
local monitor_main = peripheral.wrap("monitor_1")
local myID = os.getComputerID()
print(myID)

local message

local burnTimes = {
    ["minecraft:coal"] = 80,      -- уголь
    ["minecraft:charcoal"] = 80,  -- древесный уголь
    ["minecraft:oak_planks"] = 15, -- дубовые доски
    ["minecraft:stick"] = 5,      -- палка
    ["minecraft:oak_log"] = 15,    -- бревно
    ["quark:charcoal_block"] = 800
    -- добавьте свои предметы
}


local fuel_seconds = 0
local fuel_minutes = 0
local fuel_hours = 0



local function fuel()
    local totalSec = 0
    for i = 1, fuel_store.size() do
        local item = fuel_store.getItemDetail(i)
        if item then
            local burn = burnTimes[item.name]
            if burn then
            totalSec = totalSec + (burn * item.count)
            end
        end
    end
    totalSec = totalSec / 3

    fuel_hours = math.floor(totalSec / 3600)
    fuel_minutes = math.floor((totalSec % 3600) / 60)
    fuel_seconds = totalSec % 60
end

rednet.open("right")

while true do

    fuel()
    local message = string.format("%d:%d:%d", fuel_hours, fuel_minutes, fuel_seconds)
    rednet.send(1, message)
    sleep(5)
    rednet.send(1, message)
    
end



