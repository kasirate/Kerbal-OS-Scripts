
parameter LandingPosition is false.

if exists("ProgramLoader")
{
    runOncePath("ProgramLoader").
    Dependency("0:/lib/TerminalFuncs").
    Dependency("0:/lib/Nodes").
    Dependency("0:/lib/Hover").

    runOncePath("TerminalFuncs").
    runOncePath("Nodes").
    runOncePath("Hover").
}

local PositionMode is false.

local function main
{
    set PositionMode to LandingPosition:istype("GeoCoordinates").
    local mnv is Plan_DeorbitBurn().
    ExecuteNode(mnv).
    Perform_DecelerationBurn().
    Perform_HoverLand().
}

function PredictedImpact_Location
{
    local t is time:seconds.
    local tAlt is (positionAt(ship, t) - ship:body:positition - ship:body:radius).
    local tTerrain is ship:body:geopositionof(positionAt(ship, t)):terrainheight.
    until tAlt < tTerrain
    {
        set t to t + 1.
        set tAlt to (positionAt(ship, t) - ship:body:positition - ship:body:radius).
        set tTerrain to ship:body:geopositionof(positionAt(ship, t)):terrainheight.
    }
    return ship:body:geoPositionof(positionAt(ship, t)).
}

function PredictedImpact_Time
{
    local t is time:seconds.
    local lock tAlt to ((positionAt(ship, t) - ship:body:position):mag - ship:body:radius).
    local lock tTerrain to ship:body:geopositionof(positionAt(ship, t)):terrainheight.
    until tAlt < tTerrain
    {
        set t to t + 1.
    }
    return t.
}

local function Plan_DeorbitBurn
{
    local ans is false.
    local epoch is time:seconds + 10 * 60.
    if not PositionMode
    {
        local y is ship:body:radius.
        local v is IdealVelocityAtTimeForSYIE(epoch, ship, y).
        local fpAng is FlightPathAngleFromPosV(positionAt(ship, epoch)-ship:body:position, v).
        if fpAng > 0
        {
            set v to VectorWithInvertedFlightPathAngle(positionAt(ship, epoch)-ship:body:position, v).
        }
        set ans to Node(epoch, 0, 0, 0).
        add(ans).
        set ans to FinalV2Node(v, ans).
    }
    return ans.
}

local function Perform_DecelerationBurn
{
    lock steering to lookDirUp(-ship:velocity:surface, -(ship:position - ship:body:position)).
    lock throttle to 0.
    local ImpactEpoch is PredictedImpact_Time().
    local lock tImpact to ImpactEpoch-time:seconds.
    local lock pos to ship:position - ship:body:position.
    local lock ThrustAng to vAng(ship:velocity:surface, pos).
    local lock vAcc to (ship:availablethrust/ship:mass)*cos(ThrustAng)-(ship:body:mu/(pos:mag^2)).
    local lock hAcc to (ship:availablethrust/ship:mass)*sin(ThrustAng).
    local lock vSpeed to ship:velocity:surface * pos:normalized.
    local lock hSpeed to vectorExclude(pos:normalized, ship:velocity:surface):mag.
    local lock vDecelTime to vSpeed/vAcc.
    local lock hDecelTime to hSpeed/hAcc.
    until ((vDecelTime > 2 * tImpact) or (hDecelTime > 2 * tImpact)).
    until (hSpeed < 5) // or (vSpeed > -1)
    {
        lock throttle to 1.
    }
    lock throttle to 0.
    wait 0.5.
    unlock throttle.
    unlock steering.
}

local function Perform_HoverLand
{
    local lock pos to ship:position - ship:body:position.
    local lock hSpeed to vectorExclude(pos:normalized, ship:velocity:surface):mag.
    Hover_Set_Altitude().
    until Hover_State_atAltitude() and hspeed < 0.5
    {
        Hover_Step().
    }
    Hover_Set_Landing(true).
    until Hover_State_hasLanded()
    {
        Hover_Step().
    }
}

local Landing_LoggingFunction is def_Landing_LoggingFunction@.

function Landing_Set_LoggingFunction
{
    parameter LoggingFunction is false.
    if not LoggingFunction:istype("UserDelegate")
    {
        set LoggingFunction to def_Landing_LoggingFunction@.
    }
    if LoggingFunction:istype("UserDelegate")
    {
        set Landing_LoggingFunction to LoggingFunction.
    }
}

local function def_Landing_LoggingFunction
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
    if Landing_LoggingFunction:istype("UserDelegate")
    {
        Landing_LoggingFunction(message).
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