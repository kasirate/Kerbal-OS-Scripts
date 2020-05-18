@lazyGlobal off.

parameter isLoose is true, ThrustDir is angleAxis(0, ship:up:vector), HoverAltitude is ship:altitude.

local vSpeedLimit is list(0,0).
local aLimit is list(0,0).
local hSpeedLimit is 50.
local hdg is -1.

local update is false.

if exists("ProgramLoader")
{
    runOncePath("ProgramLoader").
    Dependency("0:/lib/TerminalFuncs").
    Dependency("0:/lib/Nodes").

    runOncePath("TerminalFuncs").
    runOncePath("Nodes").
}

local function main 
{
    //parameter isLoose is true, ThrustDir is angleAxis(0, ship:up:vector).
    print "Initializing Altitude hold at " + round(HoverAltitude) + "m".
    until false
    {
        set update to true.
        Hover_Step(isLoose, ThrustDir, HoverAltitude).
        set update to false.
        local nextUpdate is time:seconds + 5.
        until time:seconds > nextUpdate
        {
            Hover_Step(isLoose, ThrustDir, HoverAltitude).
            until not terminal:input:haschar
            {
                Hover_ProcessInput(terminal:input:getchar).
            }
        }
    }
}

function Hover_Step
{
    parameter isLoose is true, ThrustDir is angleAxis(0, ship:up:vector), HoverAltitude is ship:altitude.
    if ship:availablethrust = 0 return.
    Hover_CtrlPitch(isLoose, ThrustDir).
    Hover_CtrlThrust(ThrustDir, HoverAltitude).
}

local function Hover_CtrlPitch
{
    parameter isLoose is true, ThrustDir is angleAxis(0, ship:up:vector).
    if ship:availablethrust = 0 return.
    local ThrustVec is (SHIP:FACING:FOREVECTOR) * ThrustDir.
    local pos is (-1*ship:body:position).
    local gForce is (ship:body:mu/((pos:mag)^2))*ship:mass.
    local maxAng is arcCos(gForce/ship:availablethrust).
    local ThrustAng is vAng(ThrustVec:normalized, pos:normalized).
    local uNorth is NorthVectorAtPos(pos, ship:body).
    local uEast is vcrs(pos, uNorth):normalized.
    if hdg < 0
    {
        local vecHDG is vectorExclude(pos:normalized, ((SHIP:FACING) * ThrustDir):topvector).
        set hdg to 
            choose
                vAng(uNorth, vecHDG)
            if vecHDG * uEast >= 0 else
                360 - vAng(uNorth, vecHDG).
        print "Heading set to: " + hdg.
    }
    local truehdg is vectorExclude(pos:normalized,ThrustVec):normalized.
    local vecHDG is uNorth * angleAxis(hdg, pos:normalized).
    lock steering to lookDirUp(pos:normalized, vecHDG).
}

local function Hover_CtrlThrust
{
    parameter ThrustDir is angleAxis(0, ship:up:vector), HoverAltitude is ship:altitude.
    
    if ship:availablethrust = 0 return.
    local ThrustVec is (SHIP:FACING:FOREVECTOR) * ThrustDir.
    local pos is (-1*ship:body:position).
    local gForce is (ship:body:mu/((pos:mag)^2))*ship:mass.
    local ThrustAng is vAng(ThrustVec:normalized, pos:normalized).
    local aUp is aLimit[1].
    local aDown is aLimit[0].

    if aDown = 0
    {
        set aDown to -gForce/ship:mass.
    }
    if aUp = 0
    {
        set aUp to 0.8*((ship:availablethrust*cos(ThrustAng))-gForce)/ship:mass.
    }
    set aUp to min(aUp, ((ship:availablethrust*cos(ThrustAng))-gForce)/ship:mass).

    local vAcc is 0.
    local vSpeed is ship:velocity:surface * pos:normalized.
    local decelTime is 
        choose
            ABS(vSpeed/aDown)
        if vSpeed > 0 else
            ABS(vSpeed/aUp).
    if ship:altitude < HoverAltitude
    {
        if (HoverAltitude - ship:altitude)/ABS(vSpeed) <= decelTime and vSpeed > 0
        {
            set vAcc to aDown.
            if update print "Slowing ascent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
        else
        {
            set vAcc to 
                choose
                    aUp*MIN(1, ((vSpeedLimit[1] - vSpeed)/vSpeedLimit[1]))
                if not (vSpeedLimit[1] = 0) else
                    aUp.
            if update print "Max ascent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
    }
    if ship:altitude > HoverAltitude
    {
        if (ship:altitude - HoverAltitude)/ABS(vSpeed) <= decelTime and vSpeed < 0
        {
            set vAcc to aUp.
            if update print "Slowing descent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
        else
        {
            set vAcc to 
                choose 
                    aDown*MIN(1, ((vSpeedLimit[0] - vSpeed)/vSpeedLimit[0]))
                if not (vSpeedLimit[0] = 0) else
                    aDown.
            if update print "Max descent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
    }
    local myThrust is (gForce + (vAcc*ship:mass))/cos(ThrustAng).
    lock throttle to myThrust/ship:availablethrust.
}

local function Hover_ProcessInput
{
    parameter c is terminal:input:getchar().
    print unchar(c) + ":" + c.
    set c to c:tolower().
    if c = "a" or c = "q"
    {
        print "HDG--".
        set hdg to hdg - 1.
        if hdg < 0
        {
            set hdg to 360 + hdg.
        }
    }
    if c = "d" or c = "e"
    {
        print "HDG++".
        set hdg to hdg + 1.
        if hdg >= 360
        {
            set hdg to hdg - 360.
        }
    }
    if c = "s"
    {
        print "HSPEED--".
    }
    if c = "w"
    {
        print "HSPEED++".
    }
    if c = "-" or unchar(c) = 57352
    {
        print "ALT--".
        set HoverAltitude to ship:altitude - 1.
    }
    if c = "+" or c = "=" or unchar(c) = 57351
    {
        print "ALT++".
        set HoverAltitude to ship:altitude + 1.
    }
    if c = "g"
    {
        print "Landing".
        set vSpeedLimit[0] to -0.5.
        set HoverAltitude to -ship:body:radius.
        set hSpeedLimit to 0.
        gear on.
    }
}

local doProgram is true.
if (defined ProgramLoaderReady)
{
    if isLoading()
    {
        //print "Loading program...".
        set doProgram to false.
    }
}
else
{
    //print "Variable" + char(32) + "ProgramLoaderReady" + char(32) + " not found...".
}
if doProgram
{
    //print "Executing program...".
    main().
}
else
{
    print "Program Loaded.".
}
