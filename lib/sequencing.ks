@lazyGlobal off.

runOncePath("ProgramLoader").
Dependency("0:/lib/TerminalFuncs").

runOncePath("TerminalFuncs").


function doSafeStage
{
    wait until stage:ready.
    stage.
    wait until stage:ready.
}

function doStageCheck
{
    if not (defined oldAvailableThrust)
    global oldAvailableThrust is ship:availablethrust.
    if not (defined last_stage_time)
    global last_stage_time is time:seconds.
    if (oldAvailableThrust > ship:availablethrust + 10 or ship:availablethrust < 1) and (last_stage_time + 1 < time:seconds) and stage:number > 0
    {
        if ship:availablethrust < 1
        {
            print "Staging to next engine...".
        }
        else
        {
            print "Discarding spent stage...".
        }
        doSafeStage().
        set last_stage_time to time:seconds.
        set oldAvailableThrust to ship:availablethrust.
    }
}

function doLVDiscardCheck
{
    if not (defined didAG2)
    {
        global didAG2 is false.
    }
    if periapsis > 5000 and not didAG2 
    {
        AG2 ON.
        set didAG2 to true.
        print "Safely discarding lift vehicle...".
    }
}

function doConfigure
{
    parameter delay is 5.
    Banner("Executing Configuration").

    local myThrottle is 0.
    lock throttle to myThrottle.

    AG1 ON.

    if delay > 0
    {
        print "Waiting on configuration change for " + delay + " seconds...".
        wait delay.
    }
}


