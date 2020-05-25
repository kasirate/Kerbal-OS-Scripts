@lazyGlobal off.

parameter 
    ThrustDir is angleAxis(0, ship:up:vector), 
    HoverAltitude is max(ship:bounds:bottomaltradar, 50),
    HoverPosition is false.

local vSpeedLimit is list(0,0).
local aLimit is list(0,0).
local hSpeedLimit is 50.
local hSpeed is 0.
local hdg is -1.
local ThrustSafetyMargin is 0.
local isLanding is false.
local TouchDownSpeed is -0.5.

local currentVAcc is 0.
local currentHAcc is 0.
local checkLanded is false.
local LandedCheck_starttime is 0.
local hasLanded is false.
local bnd is ship:bounds.
local last_bnd_update is time:seconds.
local hNull is false.
local isPositionMode is false.
local TerrainMode is true.

local pidHVel is PIDLoop(0.5, 0.001, 0).

local PositionArrowColor is red.
local PositionArrow is 
    VECDRAW(
        ship:position, 
        {
            return 
                choose
                    HoverPosition:position
                if HoverPosition:isType("GeoCoordinates") and isPositionMode else
                    ship:position.
        }, 
        {return PositionArrowColor.}, 
        "", 
        1.0, 
        false, 
        0.2, 
        true
    ).

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
    if ThrustDir:istype("Boolean")
    {
        set ThrustDir to angleAxis(0, ship:up:vector).
    }
    if HoverAltitude:isType("Boolean")
    {
        set HoverAltitude to max(ship:bounds:bottomaltradar, 50).
    }
    if HoverPosition:istype("Boolean")
    {
        set isPositionMode to HoverPosition.
        set HoverPosition to ship:geoPosition.
    }
    else if HoverPosition:istype("GeoCoordinates")
    {
        set isPositionMode to true.
    }
    else
    {
        set isPositionMode to false.
        print "typeof(HoverPosition) = " + HoverPosition:typename.
    }
    local sAltMode is
        choose
            "AGL"
        if TerrainMode else
            "ASL".
    //Hover_Set_Position().
    //set HoverAltitude to HoverAltitude + 50.
    print "Initializing Altitude hold at " + round(HoverAltitude) + "m " + sAltMode.
    print "   Position Mode: " + isPositionMode.
    set hasLanded to false.
    until hasLanded
    {
        set update to true.
        Hover_Step(ThrustDir, HoverAltitude).
        set update to false.
        local nextUpdate is time:seconds + 5.
        until time:seconds > nextUpdate
        {
            Hover_Step(ThrustDir, HoverAltitude).
            until not terminal:input:haschar
            {
                Hover_ProcessInput(terminal:input:getchar).
            }
            if hasLanded break.
        }
    }
}

function Hover_Set_DistHdg
{
    parameter Dist is 0, iHdg is -1.
    local pos is (-1*ship:body:position).
    local uNorth is NorthVectorAtPos(pos, ship:body).
    local uEast is -vcrs(pos, uNorth):normalized.
    if iHdg < 0
    {
        local vecHDG is vectorExclude(pos:normalized, ((SHIP:FACING) * ThrustDir):topvector).
        set iHdg to 
            choose
                vAng(uNorth, -vecHDG)
            if vecHDG * uEast >= 0 else
                360 - vAng(uNorth, -vecHDG).
    }
    local nComp is cos(iHdg).
    local eComp is sin(iHdg).
    local degTgt is (Dist/pos:mag)*constant:RadToDeg.
    return Hover_Set_Position(nComp*degTgt, eComp*degTgt, true).
}

function Hover_Set_Position
{
    parameter lat is ship:geoPosition:lat, lng is ship:geoPosition:lng, Relative is false.
    if Relative
    {
        set lat to ship:geoPosition:lat + lat.
        set lng to ship:geoPosition:lng + lng.
    }
    set HoverPosition to latlng(lat, lng).
    set isPositionMode to true.
}

function Hover_Step
{
    parameter ThrustDir is angleAxis(0, ship:up:vector), HoverAltitude is bnd:bottomaltradar.
    if ship:availablethrust = 0 return.
    local bnd_update_rate is
        choose
            1
        if (isLanding and hNull) else
            10.
    if time:seconds > last_bnd_update + bnd_update_rate
    {
        set bnd to ship:bounds.
        set last_bnd_update to time:seconds.
    }
    Hover_CtrlHSpeed().
    Hover_CtrlPitch(ThrustDir).
    Hover_CtrlThrust(ThrustDir, HoverAltitude).
}

local function Hover_CtrlHSpeed
{
    if not isPositionMode 
    {
        set PositionArrow:show to false.
        return.
    }
    if not PositionArrow:show 
    {
        print "Displaying postion target vector".
        set PositionArrow:show to true.
    }
    local pos is (-1*ship:body:position).
    local gAcc is (ship:body:mu/((pos:mag)^2)).
    local gForce is gAcc*ship:mass.
    local maxAng is min(30, arcCos(((currentVAcc + gAcc) * ship:mass)/ship:availablethrust)).
    local uNorth is NorthVectorAtPos(pos, ship:body).
    local uEast is vcrs(pos, uNorth):normalized.
    local tgt is HoverPosition:position-ship:body:position.
    local startVec is ship:geoPosition:position-ship:body:position.
    local hMaxA is 
        choose
            (currentVAcc + gAcc)*sin(maxAng)
        if not ((currentVAcc + gAcc) = 0) else
            (-0.2 + gAcc)*sin(maxAng).
    if TerrainMode
    {
        set tgt to tgt:normalized * (tgt:mag + HoverAltitude).
        set startVec to startVec:normalized * (startVec:mag + HoverAltitude).
    }
    else
    {
        set tgt to tgt:normalized * (ship:body:radius + HoverAltitude).
        set startVec to startVec:normalized * (ship:body:radius + HoverAltitude).
    }
    local pathVec is tgt - startVec.
    set hdg to 
        choose
            vAng(uNorth, pathVec)
        if pathVec * uEast >= 0 else
            360 - vAng(uNorth, pathVec).
    local dist is vAng(startVec, tgt)*constant:DegToRad*startVec:mag.
    set hMaxA to max (0, hMaxA).
    if 2*hMaxA*dist < 0
    {
        print "    2*hMaxA*dist = " + 2*hMaxA*dist.
        print "        hMaxA = " + hMaxA.
        print "        dist = " + dist.
        until false.
    }
    set hSpeed to min(hSpeedLimit, dist/20).
    if dist > 1
    {
        set PositionArrowColor to Red.
    }
    else
    {
        set PositionArrowColor to Green.
    }
}

local function Hover_CtrlPitch
{
    parameter ThrustDir is angleAxis(0, ship:up:vector).
    if ship:availablethrust = 0 return.
    local ThrustVec is (SHIP:FACING:FOREVECTOR) * ThrustDir.
    local pos is (-1*ship:body:position).
    local gAcc is (ship:body:mu/((pos:mag)^2)).
    local gForce is gAcc*ship:mass.
    local ThrustVComp is ((currentVAcc + gAcc) * ship:mass)/ship:availablethrust.
    if ABS(ThrustVComp) > 1
    {
        print "In Hover.ks:Hover_CtrlPitch():".
        print "    ((currentVAcc + gAcc) * ship:mass)/ship:availablethrust = " + ThrustVComp.
        print "        currentVAcc = " + currentVAcc.
        print "        gAcc = " + gAcc.
        print "        ship:mass = " + ship:mass.
        print "        ship:availableThrust = " + ship:availablethrust.
        set ThrustVComp to ThrustVComp/ABS(ThrustVComp).
    }
    local maxAng is min(30, arcCos(ThrustVComp)).
    local ThrustAng is vAng(ThrustVec:normalized, pos:normalized).
    local uNorth is NorthVectorAtPos(pos, ship:body).
    local uEast is -vcrs(pos, uNorth):normalized.
    local aUp is ABS(aLimit[1]).

    if aUp = 0
    {
        set aUp to (1 - ThrustSafetyMargin)*((ship:availablethrust*cos(ThrustAng))-gForce)/ship:mass.
    }
    set aUp to min(aUp, ((ship:availablethrust*cos(ThrustAng))-gForce)/ship:mass).

    if isLanding and not isPositionMode
    {
        set hSpeed to 0.
    }
    if hdg < 0
    {
        local vecHDG is vectorExclude(pos:normalized, ((SHIP:FACING) * ThrustDir):topvector).
        set hdg to 
            choose
                vAng(uNorth, -vecHDG)
            if vecHDG * uEast >= 0 else
                360 - vAng(uNorth, -vecHDG).
        print "Heading set to: " + hdg.
    }
    local truehdg is vectorExclude(pos:normalized,ThrustVec):normalized.
    local vecHDG is uNorth * angleAxis(hdg, pos:normalized).
    local hvel is vectorExclude(pos:normalized, ship:velocity:surface).
    if (isLanding and (hvel:mag < 0.1))
    {
        if not hNull
        {
            print "Beginning Final descent...".
            set HoverAltitude to MIN(bnd:bottomaltradar - 2, 5).
        }
        // set hSpeed to hvel:mag.
        // set hdg to
        //     choose
        //         vAng(uNorth, -hvel:normalized)
        //     if hvel:normalized * uEast >= 0 else
        //         360 - vAng(uNorth, -hvel:normalized).
        set hNull to true.
    }
    else
    {
        set hNull to false.
    }
    local hMaxA is 
        choose
            (currentVAcc + gAcc)*sin(maxAng)
        if not ((currentVAcc + gAcc) = 0) else
            (-0.2 + gAcc)*sin(maxAng).
    local hdv is vecHdg * hSpeed - hvel.
    local hacc is hMaxA.
    // if hdv:mag < (hMaxA * 10)/2 // 10s ramp down
    // {
    //     set hacc to hMaxA * hdv:mag*((2)/(hMaxA * 10)).
    // }
    set pidHVel:maxoutput to hMaxA.
    set pidHVel:minoutput to -hMaxA.
    set hacc to hMaxA * -pidHVel:Update(time:seconds, hdv:mag/hMaxA).
    local pitchAng is 0.
    if not ((currentVAcc + gAcc < 0.1) or (hNull))
    {
        set pitchAng to arcSin(max(-sin(maxAng), min(sin(maxAng), hacc/(currentVAcc + gAcc)))).
    }
    else
    {
        set pitchAng to 0.//arcSin(min(sin(maxAng), hacc/(aUp))).
        set hacc to 0.
    }
    local pitchVec is pos:normalized * angleAxis(pitchAng, vCrs(pos:normalized, hdv:normalized)).
    set currentHAcc to hacc.
    lock steering to lookDirUp(pitchVec, -vecHDG).
}

local function Hover_CtrlThrust
{
    parameter ThrustDir is angleAxis(0, ship:up:vector), HoverAltitude is bnd:bottomaltradar.
    
    if ship:availablethrust = 0 return.
    local ThrustVec is (SHIP:FACING:FOREVECTOR) * ThrustDir.
    local pos is (-1*ship:body:position).
    local gAcc is (ship:body:mu/((pos:mag)^2)).
    local gForce is gAcc*ship:mass.
    local ThrustAng is vAng(ThrustVec:normalized, pos:normalized).
    local aUp is ABS(aLimit[1]).
    local aDown is -ABS(aLimit[0]).
    local state is "n/a".

    if aUp = 0
    {
        set aUp to (1-ThrustSafetyMargin)*((ship:availablethrust*cos(ThrustAng))-gForce)/ship:mass.
    }
    set aUp to min(aUp, ((ship:availablethrust*cos(ThrustAng))-gForce)/ship:mass).

    if aDown = 0
    {
        set aDown to -gForce/ship:mass.
    }
    set aDown to max(aDown, -gForce/ship:mass).

    local vAcc is 0.
    local vSpeed is ship:velocity:surface * pos:normalized.
    local decelTime is 
        choose
            ABS(vSpeed/aDown)
        if vSpeed > 0 else
            ABS(vSpeed/aUp).
    if (ABS(HoverAltitude - bnd:bottomaltradar) < 5) and (ABS(vSpeed) < 2)
    {
        local vSpeedTarget is ((bnd:bottomaltradar - HoverAltitude)/5)^2.
        if bnd:bottomaltradar > HoverAltitude
        {
            set vSpeedTarget to -ABS(vSpeedTarget).
        }
        if isLanding and hNull and (vSpeed < 0.1) and (vSpeed > -ABS(TouchDownSpeed))
        {
            set vSpeedTarget to -ABS(TouchDownSpeed).
            set HoverAltitude to MIN(bnd:bottomaltradar - 2, 5).
            set state to "Final Descent".
        }
        else
        {
            //if update print "Hovering near target Altitude...".
        }
        set vAcc to (vSpeedTarget - (vSpeed))/1.5.

        if isLanding
        {
            if bnd:bottomaltradar < 0.1 and hNull
            {
                set hasLanded to true.
            }
        }
    }
    else if bnd:bottomaltradar < HoverAltitude
    {
        if (HoverAltitude - bnd:bottomaltradar)/ABS(vSpeed) <= decelTime and vSpeed > 0
        {
            set state to "Slow Ascent".
            set vAcc to -((ABS(vSpeed)-1)^2)/(2*(bnd:bottomaltradar - HoverAltitude - 2)).
            // if update print "Slowing ascent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
        else
        {
            set state to "Max Ascent".
            set vAcc to 
                choose
                    min(aUp, (vSpeedLimit[1] - vSpeed)/2)
                if not (vSpeedLimit[1] = 0) else
                    aUp.
            // if update print "Max ascent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
    }
    else if bnd:bottomaltradar > HoverAltitude
    {
        if (bnd:bottomaltradar - HoverAltitude)/ABS(vSpeed) <= decelTime and vSpeed < 0
        {
            set state to "Slow Descent".
            set vAcc to ((ABS(vSpeed)-1)^2)/(2*(bnd:bottomaltradar - HoverAltitude + 2)).
            // if update print "Slowing descent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
        else
        {
            set state to "Max Descent".
            set vAcc to 
                choose 
                    MAX(aDown, ((vSpeedLimit[0] - vSpeed))/1.5)
                if not (vSpeedLimit[0] = 0) else
                    aDown.
            // if update print "Max descent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...".
        }
    }
    if ((currentHAcc > 0.1) or (ThrustAng > 0.1)) and vAcc <= -(gForce/ship:mass)
    {
        set state to state + "| hVel Assist".
        set vAcc to min(-0.2, -(gForce/ship:mass) + currentHAcc*sin(ThrustAng)).
    }
    set vAcc to min(aUp, max(aDown, vAcc)).
    local myThrust is (gForce + (vAcc*ship:mass))/cos(ThrustAng).
    // if ((myThrust = 0) and (currentHAcc > 0) and ((ThrustVec:normalized * pos:normalized) < 0.1))
    // {
    //     set myThrust to currentHAcc * ship:mass.
    //     set state to state + "| hVel Assist".
    // }
    lock throttle to myThrust/ship:availablethrust.
    set currentVAcc to vAcc.
    if myThrust/ship:availablethrust > 0.5
    {
        print "Thrust of " + round((myThrust/ship:availablethrust)*100, 1) + "% " +
        "(VertA:" + round(vAcc,1) + "m/s2@" + round(ThrustAng) + "*, HA:" + round(HoverAltitude) + ") " +
        "in state: " + state.
    }
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
        set hSpeed to max(0, hSpeed - 1).
    }
    if c = "w"
    {
        print "HSPEED++".
        set hSpeed to hSpeed + 1.
    }
    if c = "-" or unchar(c) = 57352
    {
        print "ALT--".
        if HoverAltitude > bnd:bottomaltradar
        {
            set HoverAltitude to bnd:bottomaltradar.
        }
        set HoverAltitude to HoverAltitude - 1.
    }
    if c = "+" or c = "=" or unchar(c) = 57351
    {
        print "ALT++".
        if HoverAltitude < bnd:bottomaltradar
        {
            set HoverAltitude to bnd:bottomaltradar.
        }
        set HoverAltitude to HoverAltitude + 1.
    }
    if c = "g"
    {
        print "Landing".
        set isLanding to true.
        set hasLanded to false.
        set checkLanded to false.
        set hNull to false.
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
