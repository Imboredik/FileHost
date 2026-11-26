local sensor   = peripheral.find("integrated_flight_sensor")
local thruster = peripheral.find("liquid_vector_thruster")
local backpack = peripheral.find("sophisticatedbackpacks:backpack")
local bus      = peripheral.find("multi_channel_cable_bus")

if not sensor or not thruster then error("Sensor or Thruster not found!") end
local bpName = backpack and peripheral.getName(backpack) or nil

-- SETTINGS
local PITCH_OVER_H  = 80    -- climb 80 blocks vertically before turning
local CRUISE_Y      = 140   -- safe cruise altitude
local MAX_SAFE_Y    = 170   -- hard ceiling
local DIVE_DIST     = 450   -- distance N to pitch nose straight into target
local DETONATE_DIST = 50    -- warhead trigger radius

local SIGN_TURN     = 1
local SIGN_TILT     = -1
local SIGN_ROLL     = 1

local KP_TURN       = 0.003
local KD_TURN       = 0.01
local KP_TILT       = 0.008
local KD_TILT       = 0.0085
local MAX_VEC       = 0.28

local function clamp(v, minV, maxV)
    return math.max(minV, math.min(maxV, v))
end

local function wrap180(a)
    while a >  180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

-- INIT
thruster.setThrustNormalized(0)
thruster.setVector(0, 0)
if bpName then thruster.pullFluid(bpName) end

local tx, ty, tz
print("Waiting for disk...")

while not tx or not ty or not tz do
    if fs.exists("disk/target.txt") then
        local f = fs.open("disk/target.txt", "r")
        if f then
            tx = tonumber(f.readLine())
            ty = tonumber(f.readLine())
            tz = tonumber(f.readLine())
            f.close()
        end
    end
    if not tx or not ty or not tz then
        sleep(0.5)
    end
end


sensor.setTarget(tx, ty, tz)

local logFile = fs.open("flight_log.txt", "w")
if logFile then
    logFile.writeLine(string.format("=== VELOCITY-HEADING LOG | TARGET: %.1f, %.1f, %.1f ===", tx, ty, tz))
    logFile.flush()
end

print("Launch in 3s...")
sleep(3)

local reachedCruise = false
local startY = sensor.getCoordinates().y or 0
local startTime = os.clock()
local tick = 0
local diveRollLock = nil
local prevDist = 999999

while true do
    tick = tick + 1
    local t = os.clock() - startTime
    if bpName then thruster.pullFluid(bpName) end

    local all   = sensor.getAll()
    local pos   = all.position
    local tgt   = all.target
    local vel   = all.velocity
    local ang   = all.gimbal
    local press = all.airPressure or 1.0

    local x, y, z     = pos.x, pos.y, pos.z
    local vx, vy, vz  = vel.x or 0, vel.y or 0, vel.z or 0
    local spd         = vel.speed or 0
    local gSpd        = math.sqrt(vx * vx + vz * vz)
    local hDist       = tgt.horizontalDistance
    local dist        = tgt.distance

    local pitchDeg    = math.abs(ang.pitch or 0)
    local rollDeg     = ang.roll or 0
    local pRate       = clamp(ang.pitchRate or 0, -180, 180)
    local yRate       = clamp(ang.yawRate or 0, -180, 180)

    local targetBrg   = math.deg(math.atan2(tx - x, -(tz - z)))
    local actualHdg   = gSpd > 4.0 and math.deg(math.atan2(vx, -vz)) or targetBrg
    local relAngle    = wrap180(targetBrg - actualHdg)

    -- DETONATION (direct hit OR closest-approach proximity fuse within 22 blocks)
    local closestApproach = (dist < 22.0 and dist > prevDist)
    prevDist = dist

    if dist <= DETONATE_DIST or closestApproach then
        if logFile then
            logFile.writeLine(string.format("EVENT: DETONATE at Pos:(%.1f,%.1f,%.1f) Dist:%.2f", x, y, z, dist))
            logFile.close()
        end
        print("BOOM! Dist: " .. string.format("%.1f", dist))
        if bus then bus.setChannel(1, 15) end
        thruster.setVector(0, 0)
        thruster.setThrustNormalized(0)
        break
    end
    if t > 8.0 and spd < 0.8 then
        if logFile then
            logFile.writeLine(string.format("EVENT: STOPPED at Pos:(%.1f,%.1f,%.1f) Dist:%.1f", x, y, z, dist))
            logFile.close()
        end
        print("STOPPED!")
        thruster.setVector(0, 0)
        thruster.setThrustNormalized(0)
        break
    end

    -- ============================================================
    -- 1. FLIGHT PHASE & DESIRED PITCH
    -- ============================================================
    if y >= startY + PITCH_OVER_H then
        reachedCruise = true
    end

    local phase = "CLIMB"
    local desPitch = 0
    local turnErr  = 0
    local thrust   = 0.88
    local curKpTurn  = KP_TURN
    local curKdTurn  = KD_TURN
    local curKpTilt  = KP_TILT
    local curKdTilt  = KD_TILT
    local curMaxTurn = MAX_VEC

    if not reachedCruise then
        phase = "CLIMB"
        desPitch = 0
        turnErr  = 0
        thrust   = 1.0

    elseif hDist > DIVE_DIST then
        phase = "CRUISE"
        diveRollLock = nil
        desPitch = clamp(65 - (CRUISE_Y - y) * 0.5 + vy * 0.6, 45, 80)
        turnErr  = relAngle

        if y >= MAX_SAFE_Y or press < 0.65 then
            thrust = 0.50
        elseif y > CRUISE_Y + 6 then
            thrust = clamp(0.75 - (y - CRUISE_Y) * 0.02 - math.max(0, vy) * 0.02, 0.55, 0.85)
        elseif y < CRUISE_Y - 6 or vy < -1.5 then
            thrust = 1.0
        else
            thrust = 1.0
        end

    else
        phase = "DIVE"
        -- Lock the exact roll angle at the start of the dive so >90 deg Euler roll flip doesn't invert axes!
        if diveRollLock == nil then
            diveRollLock = rollDeg
        end

        curKpTurn  = 0.05
        curKdTurn  = 0.016
        curMaxTurn = 0.30
        curKpTilt  = 0.05
        curKdTilt  = 0.016

        local heightAboveTgt = y - tgt.y
        local glideAngle = math.deg(math.atan2(heightAboveTgt, math.max(hDist, 5)))
        desPitch = 155--clamp(90 + glideAngle, 135, 180)
        turnErr  = relAngle
        thrust   = 0.61
    end

    -- ============================================================
    -- 2. WORLD-HORIZON COMMANDS (NO SIGN FLIPS AT 90 DEG)
    -- ============================================================
    local tiltErr = desPitch - pitchDeg

    local cmdTurn = clamp((turnErr * curKpTurn - yRate * curKdTurn) * SIGN_TURN, -curMaxTurn, curMaxTurn)
    local cmdTilt = clamp((tiltErr * curKpTilt + pRate * curKdTilt) * SIGN_TILT, -MAX_VEC, MAX_VEC)

    -- ============================================================
    -- 3. ROTATE COMMANDS BY ROLL ANGLE
    -- ============================================================
    local useRoll = (phase == "DIVE" and diveRollLock ~= nil) and diveRollLock or rollDeg
    local rRad = math.rad(useRoll * SIGN_ROLL)
    local cr, sr = math.cos(rRad), math.sin(rRad)

    local vec1 = clamp(cmdTurn * cr - cmdTilt * sr, -MAX_VEC, MAX_VEC)
    local vec2 = clamp(cmdTurn * sr + cmdTilt * cr, -MAX_VEC, MAX_VEC)

    thruster.setThrustNormalized(thrust)
    thruster.setVector(-vec1, -vec2)

    -- ============================================================
    -- 4. LOG EVERY TICK
    -- ============================================================
    if logFile then
        logFile.writeLine(string.format(
            "[T:%d | %.2fs | %s] Pos:(%.1f,%.1f,%.1f) Dist:%.0f hDist:%.0f | " ..
            "Vel:(%.1f,%.1f,%.1f) Spd:%.1f | Pit:%.1f/%.1f TgtBrg:%.1f ActHdg:%.1f RelAng:%.1f Rol:%.1f | " ..
            "cmdTurn:%.3f cmdTilt:%.3f | Thr:%.2f Vec:(%.3f,%.3f)",
            tick, t, phase, x, y, z, dist, hDist,
            vx, vy, vz, spd, pitchDeg, desPitch, targetBrg, actualHdg, relAngle, rollDeg,
            cmdTurn, cmdTilt, thrust, vec1, vec2
        ))
        logFile.flush()
    end

    term.clear()
    term.setCursorPos(1, 1)
    print(string.format("[%s] Y:%.0f/%d D:%.0f", phase, y, CRUISE_Y, dist))
    print(string.format("Pit:%.0f/%.0f Rel:%.0f Rol:%.0f", pitchDeg, desPitch, relAngle, rollDeg))
    print(string.format("Vec:(%.2f,%.2f) Thr:%.2f", vec1, vec2, thrust))

    sleep(0.05)
end

if logFile then
    logFile.close()
end
