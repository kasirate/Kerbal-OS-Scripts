@lazyGlobal off.

parameter 
    HoverAltitude is true,
    TerrainMode is true,
    HoverPosition is false,
    ThrustDir is angleAxis(0, ship:up:vector).

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
local hasLanded is false.
local atAltitude is false.
local inFinalDescent is false.
local bnd is ship:bounds.
local last_bnd_update is time:seconds.
local hNull is false.
local isPositionMode is false.
local PositionDistance is 0.

local pidHVel is PIDLoop(0.5, 0.001, 0).
local pidPosition is PIDLoop(0.2, 0, 0.005).

local last_log_update_time is 0.
local log_update_rate is 5.

local PositionArrowColor is Blue.
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
        1.0, 
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
    if ThrustDir:istype("Boolean")
    {
        set ThrustDir to angleAxis(0, ship:up:vector).
    }
    if HoverAltitude:isType("Boolean")
    {
        if TerrainMode
        {
            set HoverAltitude to max(ship:bounds:bottomaltradar, 50).
        }
        else
        {
            set HoverAltitude to max(ship:altitude, ship:geoPosition:TERRAINHEIGHT + 50).
        }
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
    print "Initializing Altitude hold at " + round(HoverAltitude) + "m " + sAltMode.
    print "   Position Mode: " + isPositionMode.
    set hasLanded to false.
    until hasLanded
    {
        Hover_Step().
        until not terminal:input:haschar
        {
            Hover_ProcessInput(terminal:input:getchar).
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
    LogMessage("Set target surface position to: " + HoverPosition:tostring).
}

function Hover_Set_TerrainMode
{
    parameter Mode is not TerrainMode.
    if not (Mode = TerrainMode)
    {
        set TerrainMode to Mode.
        if Mode
        {
            set HoverAltitude to HoverAltitude - ship:geoPosition:TERRAINHEIGHT.
        }
        else
        {
            set HoverAltitude to HoverAltitude + ship:geoPosition:TERRAINHEIGHT.
        }
    }
}

function Hover_Set_Altitude
{
    parameter iAlt is Hover_GetAltitude().
    set HoverAltitude to iAlt.
}

function Hover_Set_ThrustDir
{
    parameter dirThrust is angleAxis(0, ship:up:vector).
    set ThrustDir to dirThrust.
}

function Hover_Set_HSpeedLimit
{
    parameter iHSpeedLimit is hSpeedLimit.
    set hSpeedLimit to iHSpeedLimit.
}

function Hover_Set_SpeedHdg
{
    parameter iSpeed is hspeed, iHdg is hdg.
    set hSpeed to iSpeed.
    set hdg to iHdg.
}

function Hover_State_hasLanded
{
    return hasLanded.
}

function Hover_State_isLanding
{
    return isLanding.
}

function Hover_Set_Landing
{
    parameter v is not isLanding.
    set isLanding to v.
}

function Hover_Get_PositionDistance
{
    if not isPositionMode return -1.
    return PositionDistance.
}

function Hover_State_atPosition
{
    if not isPositionMode return false.
    local pos is (-1*ship:body:position).
    local hvel is vectorExclude(pos:normalized, ship:velocity:surface).
    return ((PositionDistance < 1) and (hvel:mag < 0.5)).
}

function Hover_State_atAltitude
{
    return atAltitude.
}

function Hover_State_inFinalDescent
{
    return inFinalDescent.
}

function Hover_Step
{
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
    if time:seconds > last_log_update_time + log_update_rate
    {
        set update to true.
        set last_log_update_time to time:seconds.
    }
    else
    {
        set update to false.
    }
    Hover_CtrlHSpeed().
    Hover_CtrlPitch().
    Hover_CtrlThrust().
}

local function Hover_GetAltitude
{
    if TerrainMode
    {
        return bnd:bottomaltradar.
    }
    else
    {
        return ship:altitude.
    }
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
    set pidPosition:maxoutput to ABS(hSpeedLimit).
    set pidPosition:minoutput to -ABS(hSpeedLimit).
    set hSpeed to -pidPosition:update(time:seconds, dist).
    set PositionDistance to dist.
    if dist > 1
    {
        set PositionArrowColor to Blue.
    }
    else
    {
        set PositionArrowColor to Green.
    }
    if update LogMessage("Position Mode: Horizontal Distance " + round(dist,1) + "m, Horizontal Speed Setpoint " + round(hSpeed,1) + "m/s").
}

local function Hover_CtrlPitch
{
    if ship:availablethrust = 0 return.
    local ThrustVec is (SHIP:FACING:FOREVECTOR) * ThrustDir.
    local pos is (-1*ship:body:position).
    local gAcc is (ship:body:mu/((pos:mag)^2)).
    local gForce is gAcc*ship:mass.
    local ThrustVComp is ((currentVAcc + gAcc) * ship:mass)/ship:availablethrust.
    if ABS(ThrustVComp) > 1
    {
        LogMessage(
                "In Hover.ks:Hover_CtrlPitch():" + "\n" +
                "    ((currentVAcc + gAcc) * ship:mass)/ship:availablethrust = " + ThrustVComp + "\n" +
                "        currentVAcc = " + currentVAcc + "\n" +
                "        gAcc = " + gAcc + "\n" +
                "        ship:mass = " + ship:mass + "\n" +
                "        ship:availableThrust = " + ship:availablethrust
            ).
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
        LogMessage("Heading set to: " + hdg).
    }
    local vecHDG is uNorth * angleAxis(hdg, pos:normalized).
    local hvel is vectorExclude(pos:normalized, ship:velocity:surface).
    if (isLanding and (hvel:mag < 0.1) and ((not isPositionMode) or (PositionDistance < 1)))
    {
        if not hNull
        {
            LogMessage("Beginning Final descent...").
            Hover_Set_TerrainMode(true).
            set HoverAltitude to MIN(Hover_GetAltitude() - 2, 5).
        }
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
    set pidHVel:maxoutput to ABS(hMaxA).
    set pidHVel:minoutput to -ABS(hMaxA).
    set hacc to hMaxA * -pidHVel:Update(time:seconds, hdv:mag/hMaxA).
    local pitchAng is 0.
    if not ((currentVAcc + gAcc < 0.1) or (hNull))
    {
        set pitchAng to arcSin(max(-sin(maxAng), min(sin(maxAng), hacc/(currentVAcc + gAcc)))).
    }
    else
    {
        set pitchAng to 0.
        set hacc to 0.
    }
    local pitchVec is pos:normalized * angleAxis(pitchAng, vCrs(pos:normalized, hdv:normalized)).
    set currentHAcc to hacc.
    lock steering to lookDirUp(pitchVec, -vecHDG).
    if update LogMessage("Pitch Control: " +
            "Pitch " + round(pitchAng,1) + " degress " +
            "Toward Hdg " + round(
                (choose
                    vAng(uNorth, -hdv:normalized)
                if hdv:normalized * uEast >= 0 else
                    360 - vAng(uNorth, -hdv:normalized)) 
            , 1) + " degress " +
            "for Horizontal Acceleration " + round(hacc,1) + " m/s^2"
        ).
}

local function Hover_CtrlThrust
{
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
    set atAltitude to false.
    set inFinalDescent to false.
    if (ABS(HoverAltitude - Hover_GetAltitude()) < 5) and (ABS(vSpeed) < 2)
    {
        local vSpeedTarget is ((Hover_GetAltitude() - HoverAltitude)/5)^2.
        if Hover_GetAltitude() > HoverAltitude
        {
            set vSpeedTarget to -ABS(vSpeedTarget).
        }
        if isLanding and hNull and (vSpeed < 0.1) and (vSpeed > -ABS(TouchDownSpeed))
        {
            set vSpeedTarget to -ABS(TouchDownSpeed).
            set HoverAltitude to MIN(Hover_GetAltitude() - 2, 5).
            set state to "Final Descent".
            set inFinalDescent to true.
        }
        else
        {
            set atAltitude to true.
            if update LogMessage("Hovering near target Altitude...").
        }
        set vAcc to (vSpeedTarget - (vSpeed))/1.5.

        if isLanding
        {
            if Hover_GetAltitude() < 0.1 and hNull
            {
                set hasLanded to true.
                set PositionArrow:show to false.
            }
        }
    }
    else if Hover_GetAltitude() < HoverAltitude
    {
        if (HoverAltitude - Hover_GetAltitude())/ABS(vSpeed) <= decelTime and vSpeed > 0
        {
            set state to "Slow Ascent".
            set vAcc to -((ABS(vSpeed)-1)^2)/(2*(Hover_GetAltitude() - HoverAltitude - 2)).
            if update LogMessage("Slowing ascent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...").
        }
        else
        {
            set state to "Max Ascent".
            set vAcc to 
                choose
                    min(aUp, (vSpeedLimit[1] - vSpeed)/2)
                if not (vSpeedLimit[1] = 0) else
                    aUp.
            if update LogMessage("Max ascent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...").
        }
    }
    else if Hover_GetAltitude() > HoverAltitude
    {
        if (Hover_GetAltitude() - HoverAltitude)/ABS(vSpeed) <= decelTime and vSpeed < 0
        {
            set state to "Slow Descent".
            set vAcc to ((ABS(vSpeed)-1)^2)/(2*(Hover_GetAltitude() - HoverAltitude + 2)).
            if update LogMessage("Slowing descent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...").
        }
        else
        {
            set state to "Max Descent".
            set vAcc to 
                choose 
                    MAX(aDown, ((vSpeedLimit[0] - vSpeed))/1.5)
                if not (vSpeedLimit[0] = 0) else
                    aDown.
            if update LogMessage("Max descent at " + vSpeed + "m/s (" + vAcc + "m/s^2)...").
        }
    }
    if ((currentHAcc > 0.1) or (ThrustAng > 0.1)) and vAcc <= -(gForce/ship:mass)
    {
        set state to state + "| hVel Assist".
        set vAcc to min(-0.2, -(gForce/ship:mass) + currentHAcc*sin(ThrustAng)).
    }
    set vAcc to min(aUp, max(aDown, vAcc)).
    local myThrust is (gForce + (vAcc*ship:mass))/cos(ThrustAng).
    lock throttle to myThrust/ship:availablethrust.
    set currentVAcc to vAcc.
    if myThrust/ship:availablethrust > 0.5
    {
        LogMessage("Thrust of " + round((myThrust/ship:availablethrust)*100, 1) + "% " +
        "(VertA:" + round(vAcc,1) + "m/s2@" + round(ThrustAng) + "*, HA:" + round(HoverAltitude) + ") " +
        "in state: " + state).
    }
    if update LogMessage("Throttle Control: " +
            "Throttle at " + round((myThrust/ship:availablethrust)*100,1) + "% " +
            "for Thrust " + round(myThrust, 1) + " kN " +
            "for Vertical Acceleration " + round(vAcc,1) + " m/s^2 " +
            "(Horizontal Acceleration " + round((tan(ThrustAng)*myThrust)/ship:mass,1) + " m/s^2)"
        ).
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
        set isPositionMode to false.
        set isLanding to false.
    }
    if c = "d" or c = "e"
    {
        print "HDG++".
        set hdg to hdg + 1.
        if hdg >= 360
        {
            set hdg to hdg - 360.
        }
        set isPositionMode to false.
        set isLanding to false.
    }
    if c = "s"
    {
        print "HSPEED--".
        set hSpeed to max(0, hSpeed - 1).
        set isPositionMode to false.
        set isLanding to false.
    }
    if c = "w"
    {
        print "HSPEED++".
        set hSpeed to hSpeed + 1.
        set isPositionMode to false.
        set isLanding to false.
    }
    if c = "-" or unchar(c) = 57352
    {
        print "ALT--".
        if HoverAltitude > Hover_GetAltitude()
        {
            set HoverAltitude to Hover_GetAltitude().
        }
        set HoverAltitude to HoverAltitude - 1.
        set isLanding to false.
    }
    if c = "+" or c = "=" or unchar(c) = 57351
    {
        print "ALT++".
        if HoverAltitude < Hover_GetAltitude()
        {
            set HoverAltitude to Hover_GetAltitude().
        }
        set HoverAltitude to HoverAltitude + 1.
        set isLanding to false.
    }
    if c = "p"
    {
        print "Activating Position Mode...".
        Hover_Set_Position(ship:geoPosition:lat, ship:geoPosition:lng).
    }
    if c = "g"
    {
        print "Landing".
        set isLanding to true.
        set hasLanded to false.
        set hNull to false.
        gear on.
    }
}

local Hover_LoggingFunction is def_Hover_LoggingFunction@.

function Hover_Set_LoggingFunction
{
    parameter LoggingFunction is false.
    if not LoggingFunction:istype("KOSDelegate")
    {
        set LoggingFunction to def_Hover_LoggingFunction@.
    }
    if LoggingFunction:istype("KOSDelegate")
    {
        set Hover_LoggingFunction to LoggingFunction.
    }
}

local function def_Hover_LoggingFunction
{
    parameter message is "".
    if not exists("1:/log")
    {
        createDir("1:/log").
    }
    if not exists("1:/log/hover.log")
    {
        create("1:/log/hover.log").
    }
    log message to "1:/log/hover.log".
}

local function LogMessage
{
    parameter message is "".
    local met is missionTime.
    local hpd is KUniverse:HOURSPERDAY.
    local dpy is 426.
    if hpd <> 6
    {
        set dpy to 356.
    }
    local iY is Floor(met/(dpy*hpd*60*60)).
    local iD is Floor(mod(met, dpy*hpd*60*60)/(hpd*60*60)).
    local iH is Floor(mod(met, hpd*60*60)/(60*60)).
    local iM is Floor(mod(met, 60*60)/(60)).
    local iS is Floor(mod(met, 60)).
    local iN is Floor(mod(met * 1000, 1000)).
    local sTime is "".
    if iY >= 1
    {
        set sTime to "Y" + iY:tostring + "-".
    }
    if iD >= 1 or iY >= 1
    {
        set sTime to sTime + "D" + iY:tostring + "-".
    }
    set sTime to sTime +
        (choose
            "0"
        if iH < 10 else "") +
        iH:tostring + ":" + 
        (choose
            "0"
        if iM < 10 else "") +
        iM:tostring + ":" + 
        (choose
            "0"
        if iS < 10 else "") +
        iS:tostring + "." + 
        (choose
            "0"
        if iN < 100 else "") +
        (choose
            "0"
        if iN < 10 else "") +
        iN:tostring.
    local pad is "".
    until pad:length >= sTime:length + 2
    {
        set pad to pad + " ".
    }
    set message to "T+" + sTime + ": " +
        message:replace("\n", char(10)):replace(char(10), char(10) + pad).
    if Hover_LoggingFunction:istype("KOSDelegate")
    {
        Hover_LoggingFunction(message).
    }
}

local doProgram is true.
if (defined ProgramLoaderReady)
{
    if isLoading()
    {
        set doProgram to false.
    }
}
else
{
    
}
if doProgram
{
    main().
}
else
{
    
}
