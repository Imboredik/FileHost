local sensor = peripheral.find("gimbal_sensor")

local redstone_1 = peripheral.wrap("redstone_relay_4")

local gear_tl = peripheral.wrap("Create_RotationSpeedController_11")
local gear_tr = peripheral.wrap("Create_RotationSpeedController_12")
local gear_bl = peripheral.wrap("Create_RotationSpeedController_14")
local gear_br = peripheral.wrap("Create_RotationSpeedController_15")

local gear_go = peripheral.wrap("Create_RotationSpeedController_13")


local monitor_main = peripheral.wrap("monitor_1")
local height_sensor = peripheral.find("altitude_sensor")
local speed_sensor = peripheral.find("velocity_sensor")
local stress_sensor = peripheral.find("Create_Stressometer")

local x_ang
local z_ang

local tr_boost
local tl_boost   

local br_boost
local bl_boost

local acceleration = 0
local go_boost = 0

local last_error_x = 0
local last_error_z = 0


local Kp_x = 0.19
local Kp_z = 1
local Ki_x = 0.3
local Ki_z = 0.5
local kd_x = 0.7
local Kd_z = 0.2

local p_x = 0
local p_z = 0
local i_x = 0
local i_z = 0
local d_x = 0
local d_z = 0

local out_x
local out_z

local corr_pitch
local corr_roll

local speed = 0
local messedge_fuel = "fetching fuel"
local old_message
local sender_fuel

local stress_capacity
local stress
local stress_buf
local col

local myID = os.getComputerID()
print(myID)


local function updateDisplay()
    monitor_main.clear()
    monitor_main.setCursorPos(1, 1)
    monitor_main.setTextScale(0.5)
    
    -- Строка 1: тяга и углы стабилизации
    monitor_main.setTextColor(colors.yellow)
    monitor_main.write(string.format("T:%3d", acceleration))

    monitor_main.write(" GO:")
    monitor_main.write(string.format("%3d", go_boost))

    monitor_main.setTextColor(colors.lightBlue)
    monitor_main.setCursorPos(45, 1)
    monitor_main.write("Fuel time:")
    monitor_main.setCursorPos(45, 2)
    if messedge_fuel == "fetching fuel" then
        col = colors.orange
    else
        col = colors.green
    end
    monitor_main.setTextColor(col)
    monitor_main.write(messedge_fuel)


    monitor_main.setTextColor(colors.lightBlue)
    monitor_main.setCursorPos(25, 1)
    monitor_main.write("Power usage:")
    monitor_main.setCursorPos(25, 2)
    if stress_buf <= 0.2 then
        col = colors.green
    elseif stress_buf <= 0.4 then
        col = colors.lime
    elseif stress_buf <= 0.6 then
        col = colors.yellow
    elseif stress_buf <= 0.8 then
        col = colors.orange
    elseif stress_buf <= 1.0 then
        col = colors.red
    end
    monitor_main.setTextColor(col)
    monitor_main.write(string.format("%d", stress))
    monitor_main.setTextColor(colors.lightGray)
    monitor_main.write(string.format("/"))
    monitor_main.setTextColor(colors.white)
    monitor_main.write(string.format("%d", stress_capacity))
    monitor_main.setTextColor(col)
    monitor_main.write(string.format("   %d", stress_buf * 100))
    monitor_main.setTextColor(colors.lightGray)
    monitor_main.write("%")
  



    
    --monitor_main.setTextColor(colors.gray)
    --monitor_main.write(" | ")
    --
    --monitor_main.setTextColor(colors.green)
    --monitor_main.write(string.format("P:%3d", corr_pitch))
    --
    --monitor_main.setTextColor(colors.gray)
    --monitor_main.write(" ")
    --
    --monitor_main.setTextColor(colors.cyan)
    --monitor_main.write(string.format("R:%3d", corr_roll))
    
    -- Строка 2: PID вывод (X и Z)
    monitor_main.setCursorPos(1, 2)
    monitor_main.setTextColor(colors.lightGray)
    monitor_main.write("PID")
    monitor_main.setTextColor(colors.gray)
    monitor_main.write(" X")
    monitor_main.setTextColor(colors.white)
    monitor_main.write(string.format("%3d", out_x))
    monitor_main.setTextColor(colors.gray)
    monitor_main.write(" Z")
    monitor_main.setTextColor(colors.white)
    monitor_main.write(string.format("%3d", out_z))
    
    -- Строка 3: моторы (кратко)
    monitor_main.setCursorPos(1, 3)
    --monitor_main.setTextColor(colors.lime)
    --monitor_main.write("TL")
    --monitor_main.setTextColor(colors.white)
    --monitor_main.write(string.format("%3d", tl_boost))
    --monitor_main.setTextColor(colors.gray)
    --monitor_main.write(" TR")
    --monitor_main.setTextColor(colors.white)
    --monitor_main.write(string.format("%3d", tr_boost))
    --monitor_main.setTextColor(colors.gray)
    --monitor_main.write(" BL")
    --monitor_main.setTextColor(colors.white)
    --monitor_main.write(string.format("%3d", bl_boost))
    --monitor_main.setTextColor(colors.gray)
    --monitor_main.write(" BR")
    --monitor_main.setTextColor(colors.white)
    --monitor_main.write(string.format("%3d", br_boost))


    monitor_main.setCursorPos(1, 4)
    monitor_main.setTextColor(colors.white)
    monitor_main.write(string.format("%.1d", speed  * 3,6))
    monitor_main.setTextColor(colors.cyan)
    monitor_main.write(" km/h")

    monitor_main.setCursorPos(1, 10)
    monitor_main.write("_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_")

    
end


acceleration = gear_tl.getTargetSpeed()
rednet.open("right")

while true do

    if math.abs(acceleration) <= 80 then
        acceleration = acceleration + (redstone_1.getAnalogInput("top") / 3) - (redstone_1.getAnalogInput("bottom") / 3)

    else
        acceleration = acceleration + (redstone_1.getAnalogInput("top") / 15) - (redstone_1.getAnalogInput("bottom") / 15)

    end

    go_boost = go_boost + (redstone_1.getAnalogInput("right") / 3) - (redstone_1.getAnalogInput("left") / 3)

    if redstone_1.getInput("back") then
        go_boost = 0
    end

    gear_go.setTargetSpeed(go_boost)

    local angles = sensor.getAngles()

    for key, value in pairs(angles) do
        if key == 1 then
            x_ang = math.floor(value / 1)
        else
            z_ang = math.floor(value / 1)
        end
    end

    if acceleration == 0 then
        p_x, p_z, i_x, i_z, d_x, d_z = 0, 0, 0, 0, 0, 0
    else
        p_x = Kp_x * x_ang
        p_z = Kp_z * z_ang

        i_x = math.max(-20, math.min(20, i_x + x_ang * 0.1 * Ki_x))
        i_z = math.max(-20, math.min(20, i_z + z_ang * 0.1 * Ki_z))

        d_x = (x_ang - last_error_x) / kd_x
        d_z = (z_ang - last_error_z) / Kd_z
    end

    last_error_x = x_ang
    last_error_z = z_ang

    out_x = p_x + i_x + d_x
    out_z = p_z + i_z + d_z

    corr_roll = math.max(-30, math.min(30, out_z))
    corr_pitch = math.max(-10, math.min(10, out_x))

    tl_boost = acceleration - corr_pitch + corr_roll
    tr_boost = acceleration + corr_pitch + corr_roll
    bl_boost = acceleration - corr_pitch - corr_roll
    br_boost = acceleration + corr_pitch - corr_roll
    
    gear_tl.setTargetSpeed(tl_boost)
    gear_tr.setTargetSpeed(tr_boost)
    gear_br.setTargetSpeed(br_boost)
    gear_bl.setTargetSpeed(bl_boost)

    speed = speed_sensor.getVelocity()

    
    old_message = messedge_fuel
    sender_fuel, messedge_fuel = rednet.receive(0.01)
    if messedge_fuel == nil then
        messedge_fuel = old_message
    end

    stress_capacity = stress_sensor.getStressCapacity()
    stress = stress_sensor.getStress()
    stress_buf = stress / stress_capacity

    updateDisplay()
    
end