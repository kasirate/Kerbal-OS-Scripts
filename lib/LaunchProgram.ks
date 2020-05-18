
parameter TargetOrbit is 100.
parameter TargetInclination is 0.
parameter AscentProfile is StdAscentProfile@.
parameter AOALimit is StdAOALimit@.

runOncePath("ProgramLoader").
Dependency("0:/lib/terminalfuncs").
Dependency("0:/lib/countdown").
Dependency("0:/lib/nodes").

runOncePath("terminalfuncs").
runOncePath("countdown").
runOncePath("nodes").

local function main
{
    OpenConsole().
    Nodes_Set_WarningCallback({
        parameter message.
        if not message:istype("String")
            set message to message:tostring().
        print message:replace("\n", char(10)).
    }).
    Banner("Counting Down...").
    doCountDown(10).
    doLiftOff().
    doAscent(TargetOrbit, TargetInclination, AscentProfile, AOALimit).
    if ship:body:atm:exists
    {
        if ship:altitude < ship:body:atm:height
        {
            doCoast(TargetOrbit, TargetInclination).
            wait 5.
        }
    }
    doConfigure(10).
    doCircularize(TargetOrbit, TargetInclination).
    // clearScreen.
    Banner("Launch Program Complete!!!").
}

function doLiftOff
{
    Banner("Lift Off!!!").

    local myThrottle is 1.
    lock throttle to myThrottle.

    local targetPitch is 90. // to 88.963 - 1.03287 * alt:radar^0.409511.
    lock targetDirection to 90.
    lock steering to heading(targetDirection, targetPitch).

    local initVel is ship:velocity.
    local initAlt is ship:altitude.
    
    SAS ON.

    until ship:availablethrust > 0
    {
        doSafeStage().
    }

    wait 0.5.

    until ship:velocity:SURFACE:MAG > initVel:SURFACE:MAG + 0.5
    {
        doSafeStage().
        wait 0.25.
    }

    until ship.altitude > initAlt + 200
    {

    }
}

function doAscent
{
    parameter TargetOrbit, Inclination, AscentProfile is StdAscentProfile@, AOALimit is StdAOALimit@.
    set TargetOrbit to TargetOrbit * 1000.

    Banner("Executing Ascent").
    
    SAS ON.

    local myThrottle is 1.
    lock throttle to myThrottle.

    local targetPitch is 90. // to 88.963 - 1.03287 * alt:radar^0.409511.
    lock targetDirection to ObtHeadingFromLatIncl(ship:geoposition:lat, Inclination, (Inclination < 0)).
    lock steering to heading(targetDirection, targetPitch, 180).

    local last_data_time is time:seconds.
    local last_throttle_change is time:seconds.
    local inClimb is false.
    local inTurn is false.
    //local pidIncl to pidLoop(0.05, 0.0025, 0, -30, 30).
    until apoapsis > TargetOrbit
    {
        doStageCheck().

        doLVDiscardCheck().

        if ship:altitude < 1000 or ship:velocity:surface:mag < 150
        {
            if not inClimb
            {
                set inClimb to true.
                set inTurn to false.
                print "Climbing...".
            }
            set targetPitch to 90.
        }
        else
        {
            if not inTurn
            {
                set inClimb to false.
                set inTurn to true.
                print "Starting Gravity Turn...".
            }
            local desiredpitch is 90 - AscentProfile(ship:altitude, TargetOrbit/1000, ship:body). // 90*sin((90)*((TargetOrbit - alt:radar)/TargetOrbit)).
            local realPitch is arcTan(ship:verticalSpeed/vectorExclude(UP:vector * ship:verticalspeed, ship:velocity:surface:vec):mag).
            local AOAlim is AOALimit().
            if time:seconds > last_data_time + 5
            {
                set last_data_time to time:seconds.
                print "desiredpitch: " + desiredpitch + ", realPitch: " + realPitch + ", AOAlim: " + AOAlim.
            }
            if abs(realPitch - targetPitch) < AOAlim
            {
                if targetPitch < desiredpitch
                {
                    set targetPitch to targetPitch + min(AOAlim - abs(realPitch - targetPitch), desiredpitch - targetPitch).
                    //print "Pitching to " + targetPitch + "...".
                }
                if targetPitch > desiredpitch
                {
                    set targetPitch to targetPitch - min(AOAlim - abs(realPitch - targetPitch), targetPitch - desiredpitch).
                    //print "Pitching to " + targetPitch + "...".
                }
            }
            else
            {

            }
        }

        if (time:seconds < last_throttle_change + 1)
        {

        }
        else if ship:dynamicpressure > 20/(101) and myThrottle > 0
        {
            set myThrottle to max(0, myThrottle - 0.5 * ((ship:dynamicpressure - (20/(101)))/(20/101))).
            set last_throttle_change to time:seconds.
            print "Throttle down to " + myThrottle + ", due to dynamic pressure...".
        }
        else if ship:dynamicpressure < 20/(101) and myThrottle < 1
        {
            set myThrottle to min(1, myThrottle + 0.55 * (((20/(101) - ship:dynamicpressure))/(20/101))).
            set last_throttle_change to time:seconds.
            print "Throttle up to " + myThrottle + "...".
        }

        lock throttle to myThrottle.
        lock steering to heading(targetDirection, targetPitch, 180).
    }

    print "Ascent Complete!!!".
    print "Throttle to 0...".
    set myThrottle to 0.
    lock throttle to myThrottle.
    lock steering to prograde.
}

function StdAscentProfile
{
    parameter ShipAltitude is ship:altitude, TargetOrbit is 100, bod is ship:body.
    local levelAlt is TargetOrbit.
    if bod:atm:exists
    {
        if TargetOrbit > bod:atm:height
        {
            set levelAlt to bod:atm:height*0.8/1000.
        }
    }
    else
    {
        set levelAlt to TargetOrbit/2.
    }
    local thrust is ship:availablethrust*throttle.
    local w is ship:mass*(bod:mu/((ShipAltitude + bod:radius)^2)).
    local maxAng is 90.
    if ship:verticalSpeed < 10
    {
        set maxAng to 90 - arcSin(w/thrust).
    }
    return min(maxAng, (59.174/levelAlt) * (ShipAltitude^0.409511)).
}

function StdAOALimit
{
    parameter ShipQ is ship:dynamicpressure, MaxQ is (20/101).
    if ((MaxQ - ShipQ)/(MaxQ)) < 0
    {
        return 0.
    }
    return 5 + max(-5, 85 * (((MaxQ - ShipQ)/(MaxQ))^0.5)).
}

function doCoast
{
    parameter TargetOrbit, Inclination.
    set TargetOrbit to TargetOrbit * 1000.

    Banner("Coasting").

    local myThrottle is 0.
    lock throttle to myThrottle.

    lock targetDirection to 90 - Inclination.
    lock steering to lookDirUp(ship:velocity:orbit:vec, -up:vector).

    local last_adjustment_time is time:seconds.
    local start_time is time:seconds.
    local didWarp is false.
    until (not (ship:body:atm:exists)) or ship:altitude > ship:body:atm:height
    {
        if apoapsis > TargetOrbit
        {
            if not myThrottle = 0
            { 
                print "Throttle to 0...".
            }
            set myThrottle to 0.
        }
        else
        {
            doStageCheck().
            doLVDiscardCheck().
            if time:seconds > last_adjustment_time + 1
            {
                set last_adjustment_time to time:seconds.
                set myThrottle to myThrottle + 0.1.
                print "Throttling up to " + myThrottle + "...".
            }
        }
        if not didWarp and time:seconds > start_time + 5
        {
            set didWarp to true.
            set warpmode to "physics".
            set warp to 1.
        }
        lock throttle to myThrottle.
    }

    set warp to 0.
    set warpmode to "rails".
}


function doCircularize
{
    parameter TargetOrbit, Inclination.
    set TargetOrbit to TargetOrbit * 1000.
    
    SAS ON.

    Banner("Executing Circularization").

    local mnv is CreateCircularizeNode("apoapsis", Inclination).
    ExecuteNode(mnv).
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

