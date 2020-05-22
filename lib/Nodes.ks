@lazyGlobal off.

runOncePath("ProgramLoader").
Dependency("0:/lib/sequencing").

runOncePath("sequencing").

function ExecuteNode
{
    parameter mnv is nextNode, AutoWarp is true, AutoStage is true, AutoLVDiscard is false.

    SAS ON.
    set warpmode to "rails".

    local myThrottle is 0.
    lock throttle to myThrottle.

    // calculate start time
    local burntime is getBurnTime(mnv).
    local start_time is time:seconds + mnv:eta - (burntime/2).

    // wait to align
    if AutoWarp
    {
        print "waiting to align with maneuver node...".
        warpto(start_time - 10 * 60 - 5).
        set warp to 0.
    }
    else
    {
        when time:seconds > start_time - 10 * 60 - 30 then
        {
            set warp to 0.
        }
    }
    until time:seconds > start_time - 10 * 60
    {

    }

    // wait until aligned
    lock steering to lookDirUp(mnv:burnvector, ship:facing:topvector).
    print "aligning with maneuver node...".
    until ship:angularVel:mag < (3.14159/180)/10 or time:seconds > start_time
    {

    }

    if not (time:seconds > start_time)
    {
        print "waiting until burn start time (Calculated burn time:" + burntime + " seonds)...".
        if AutoWarp
        {
            warpTo(start_time - 15).
            set warp to 0.
        }
        else
        {
            when time:seconds > start_time - 60 then
            {
                set warp to 0.
            }
        }
        until time:seconds > start_time
        {

        }
    }

    print "executing burn...".
    local acc is ship:availableThrust/ship:mass.
    until mnv:deltaV:mag < 0.1
    {
        set acc to ship:availableThrust/ship:mass.
        if (acc > 0)
        {
            set myThrottle to 
                max(0, min(1, 
                    ((mnv:deltaV:mag/acc)/2) * ((ship:facing:vector:normalized * mnv:deltav:normalized)^2)
                )).
        }
        
        if AutoStage
        {
            doStageCheck().
        }
        if AutoLVDiscard
        {
            doLVDiscardCheck().
        }
    }

    set myThrottle to 0.
    wait 1.
    remove(mnv).
    unlock throttle.
    unlock steering.
}

function CreateCircularizeNode
{
    parameter epoch is "apoapsis".
    parameter Inclination is 0.

    // fix inclination
    // {
    //     until Inclination < 360
    //     {
    //         set Inclination to Inclination - 360.
    //     }
    //     until Inclination > -360
    //     {
    //         set Inclination to Inclination + 360.
    //     }
    // }
    set Inclination to FixInclination(Inclination).

    // determine node time
    if epoch = "a" or epoch = "apoapsis"
    {
        set epoch to time:seconds + eta:apoapsis.
    }
    else if epoch = "p" or epoch = "periapsis"
    {
        set epoch to time:seconds + eta:periapsis.
    }
    else if epoch:typename = "String"
    {
        // todo: string parser
    }

    // add node
    local mnv is node(epoch, 0, 0, 0).
    Add(mnv).

    // determine altitude
    local altofburn is mnv:orbit:body:altitudeof(positionAt(ship, epoch)).
    // local posofburn is positionAt(ship, epoch) - positionat(mnv:orbit:body, time:seconds).

    // speed data
    local velatburn is velocityAt(ship, epoch):orbit.

    local finalv is IdealVelocityAtTimeForSYIE(epoch, ship, altofburn+ship:body:radius, Inclination, 0).
    local dv is finalv - velatburn.
    set mnv to DeltaV2Node(dv, mnv).

    return mnv.
}

function IdealVelocityAtTimeForSYIE
{
    parameter
        epoch is choose ship:nextNode if ship:hasNode else time:seconds,
        obj is ship,
        y is false,
        i is false,
        e is false.
    local ans is V(0,0,0).

    // fix optional param types
    {
        // fix epoch type
        {
            if epoch:istype("ManueverNode")
            {
                set epoch to time:seconds + epoch:eta.
            }
            if not (epoch:istype("Scalar"))
            {
                WarningMessage(
                    "IdealVelocityAt(): epoch requires Scalar or ManueverNode, not " 
                    + epoch:typename() + 
                    "  \n  epoch: " + epoch:tostring()).
                return ans.
            }
        }

        // fix type y
        {
            if y:istype("Boolean")
            {
                set y to 2*(positionAt(obj, epoch) - positionAt(BodyAt(epoch), epoch)).
            }
            if not (y:istype("Scalar"))
            {
                WarningMessage(
                    "IdealVelocityAt(): y requires Scalar or Boolean, not " 
                    + y:typename() + 
                    "  \n  y: " + y:tostring()).
                return ans.
            }
        }

        // fix type i
        {
            if i:istype("Boolean")
            {
                set i to orbitAt(obj, epoch):inclination.
            }
            if not (i:istype("Scalar"))
            {
                WarningMessage(
                    "IdealVelocityAt(): i requires Scalar or Boolean, not " 
                    + i:typename() + 
                    "  \n  i: " + i:tostring()).
                return ans.
            }
        }

        // fix type e
        {
            if e:istype("Boolean")
            {
                set e to 0.
            }
            if not (e:istype("Scalar"))
            {
                WarningMessage(
                    "IdealVelocityAt(): e requires Scalar or Boolean, not " 
                    + e:typename() + 
                    "  \n  e: " + e:tostring()).
                return ans.
            }
        }
    }

    local posatepoch is 
        choose
            positionAt(obj, epoch) - positionAt(BodyAt(epoch, obj), epoch)
        if not (BodyAt(epoch, obj):name = ship:orbit:body:name) else
            positionAt(obj, epoch) - ship:body:position.
    log "posatepoch:mag = " + posatepoch:mag to "1:/debug.txt".
    if (posatepoch:mag > 2*y) and (y > 0)
    {
        WarningMessage(
                    "IdealVelocityAt(): position at epoch exceeds twice semimajoraxis y "
                    + "  \n  epoch: " + epoch:tostring()
                    + "  \n  radius: " + posatepoch:mag:tostring()
                    + "  \n  y: " + y:tostring()).
        return ans.
    }

    //log "BodyAt(epoch, obj) <" + BodyAt(epoch, obj):typename +"> = " + BodyAt(epoch, obj):tostring to "1:/debug.txt".
    local bod is BodyAt(epoch, obj).
    //log "bod <" + bod:typename +"> = " + bod:tostring to "1:/debug.txt".
    local mu is bod:mu.
    local minecc is abs(y-posatepoch:mag)/(y). // iffy
    set e to max(e, minecc).
    local minIncl is abs((bod:geopositionof(posatepoch+bod:position)):lat).
    set i to max(i, minIncl).
    
    local uNorth is NorthVectorAtPos(posatepoch, bod).
    local northerly_vel is (velocityAt(obj, epoch):orbit*uNorth).
    local isSoutherly is false.
    if (northerly_vel < 0)
    {
        set isSoutherly to true.
    }
    else if (northerly_vel = 0) and (bod:geopositionof(posatepoch+bod:position):lat > 0)
    {
        set isSoutherly to true.
    }
    
    local idealSpeed is SpeedAtRY(posatepoch:mag, y, mu).

    local idealFltAng is FlightPathAngleFromEYR(e, y, posatepoch:mag, mu).
    local idealHdg is ObtHeadingFromLatIncl(bod:geopositionof(posatepoch+bod:position):lat, i, isSoutherly).

    local dirHdg is angleAxis(idealHdg, posatepoch:normalized).
    local dirFltAng is angleAxis(idealFltAng, -1*vectorCrossProduct(posatepoch, uNorth):normalized).

    set ans to ((uNorth*idealSpeed)*dirFltAng)*dirHdg.

    log "i = " + i to "1:/debug.txt".
    log "e = " + e to "1:/debug.txt".

    log "Ideal Speed: " + idealSpeed to "1:/debug.txt".
    log "Ideal Flight Angle: " + idealFltAng to "1:/debug.txt".
    log "Ideal Hdg: " + idealHdg to "1:/debug.txt".
    log "Ideal Velocity: " + ans to "1:/debug.txt".

    return ans.
}

function BodyAt
{
    parameter epoch is time:seconds, obj is ship.
    return orbitAt(obj, epoch):body.
}

function FinalV2Node
{
    parameter FinalV, mnv is nextNode.

    local epoch is time:seconds + mnv:eta.
    local velatburn is velocityAt(ship, epoch):orbit.

    return DeltaV2Node(FinalV - velatburn, mnv).
}

function DeltaV2Node
{
    parameter DeltaV, mnv is nextNode.

    // get unit vectors
    local coord is FlightCoordAtTime(time:seconds + mnv:eta, ship).

    set mnv:prograde to coord[0] * DeltaV.
    set mnv:radialout to coord[1] * DeltaV.
    set mnv:normal to coord[2] * DeltaV.

    return mnv.
}

function FlightCoordAtTime
{
    parameter epoch is time:seconds, obj is ship.
    local lock bod to BodyAt(epoch, obj).
    local posatepoch is positionAt(obj, epoch) - positionat(bod, time:seconds).
    local velatepoch is velocityAt(obj, epoch):orbit.

    return FlightCoordAtRV(posatepoch, velatepoch).
}

function FlightCoordAtRV
{
    parameter pos, vel.

    // get unit vectors
    local uPrograde is vel:normalized.
    local uRadial is vectorExclude(uPrograde, pos):normalized.
    local uNormal is vectorCrossProduct(uPrograde, uRadial):normalized.

    return list(uPrograde, uRadial, uNormal).
}

function getBurnTime
{
    parameter mnv is nextNode.

    if mnv:istype("Node")
    {
        set mnv to mnv:deltav.
    }
    if mnv:istype("Vector")
    {
        set mnv to mnv:mag.
    }
    if not mnv:istype("Scalar") 
    {    
        WarningMessage(
            "WARNING: getBurnTime(): mnv is type <" + mnv:typename + ">, not <scalar>, <Vector>, or <Node>." 
            + char(10) + "    mnv: " + mnv:tostring()).
        print "WARNING: getBurnTime(): mnv is type <" + mnv:typename + ">, not <scalar>, <Vector>, or <Node>." 
            + char(10) + "    mnv: " + mnv:tostring().
    }

    local acc is ship:availablethrust/ship:mass.
    local dur is choose mnv/acc if mnv:istype("Scalar") else 0.

    return dur.
}

/// vvv Orbit Mechanics

function PAtoEccentricity
{
    parameter p, a.
    if p+a = 0 return -1.
    return (a-p)/(a+p).
}

function EccentricitytoPARatio
{
    parameter e.
    if e = -1
    {
        WarningMessage(
            "EccentricitytoPARatio(): e cannot be -1 "
            + "  \n  e: " + e:tostring()).
        return 0.
    }
    return (1-e)/(1+e).
}

function SpeedAtRY
{
    parameter radius, y is ship:orbit:semimajoraxis, mu is ship:body.
    local ans is 0.
    if mu:istype("Body")
    {
        set mu to mu:mu.
    }
    if not mu:istype("Scalar")
    {
        WarningMessage(
            "SpeedAtRY(): mu must be scalar or body, not "
            + mu:typename()
            + "  \n  mu: " + mu:tostring()).
        return ans.
    }
    if (y = 0) or (radius = 0)
    {
        WarningMessage(
            "SpeedAtRY(): Invalid y or radius value "
            + "  \n  y: " + y:tostring()
            + "  \n  radius: " + radius:tostring()).
        return ans.
    }
    local lock eq0 to mu*((2/radius)-(1/y)).
    if eq0 < 0
    {
        WarningMessage(
            "SpeedAtRY(): mu*((2/radius)-(1/y)) < 0 "
            + "  \n  mu: " + mu:tostring()
            + "  \n  radius: " + radius:tostring()
            + "  \n  y: " + y:tostring()).
        return ans.
    }
    set ans to sqrt(eq0).
    return ans.
}

function RadiusAtSY
{
    parameter speed, y is ship:orbit:semimajoraxis, mu is ship:body.
    local ans is 0.
    if mu:istype("Body")
    {
        set mu to mu:mu.
    }
    if not mu:istype("Scalar")
    {
        WarningMessage(
            "RadiusAtSY(): mu must be scalar or body, not "
            + mu:typename()
            + "  \n  mu: " + mu:tostring()).
        return ans.
    }
    if (y = 0)
    {
        WarningMessage(
            "RadiusAtSY(): y cannot be 0 "
            + "  \n  y: " + y:tostring()).
        return ans.
    }
    set ans to (2/(((speed^2)/mu)-(1/y))).
    return ans.
}

function SemiMajorAxisAtRS
{
    parameter radius, speed is ship:velocity:mag, mu is ship:body.
    local ans is 0.
    if mu:istype("Body")
    {
        set mu to mu:mu.
    }
    if not mu:istype("Scalar")
    {
        WarningMessage(
            "SemiMajorAxisAtRS(): mu must be scalar or body, not "
            + mu:typename()
            + "  \n  mu: " + mu:tostring()).
        return ans.
    }
    if (radius = 0)
    {
        WarningMessage(
            "SemiMajorAxisAtRS(): radius cannot be 0 "
            + "  \n  radius: " + radius:tostring()).
        return ans.
    }
    set ans to (1/((2/radius)-((speed^2)/mu))).
    return ans.
}

function PeriapsisFromEY
{
    parameter e is ship:orbit:eccentricity, y is ship:orbit:semimajoraxis.
    local ans is 0.
    if e = -1
    {
        WarningMessage(
            "PeriapsisFromEY(): e cannot be -1 "
            + "  \n  e: " + e:tostring()).
        return ans.
    }
    set ans to (1-e)*y.
    return ans.
}

function FlightPathAngleFromEYR
{
    parameter 
        e is ship:orbit:eccentricity, 
        y is ship:orbit:semimajoraxis,
        radius is ship:position,
        mu is ship:body.
    local ans is 0.

    if mu:istype("Body")
    {
        set mu to mu:mu.
    }
    if not mu:istype("Scalar")
    {
        WarningMessage(
            "FlightPathAngle(): mu must be scalar or body, not "
            + mu:typename()
            + "  \n  mu: " + mu:tostring()).
        return ans.
    }

    if (y = 0) or (radius = 0)
    {
        WarningMessage(
            "FlightPathAngle(): Invalid y or radius value "
            + "  \n  y: " + y:tostring()
            + "  \n  radius: " + radius:tostring()).
        return ans.
    }
    local lock eq to mu*((2/radius)-(1/y)).
    if eq < 0
    {
        WarningMessage(
            "FlightPathAngle(): mu*((2/radius)-(1/y)) < 0 "
            + "  \n  mu: " + mu:tostring()
            + "  \n  radius: " + radius:tostring()
            + "  \n  y: " + y:tostring()).
        return ans.
    }
    if e = -1
    {
        WarningMessage(
            "FlightPathAngle(): e cannot be -1 "
            + "  \n  e: " + e:tostring()).
        return ans.
    }

    local speed is SpeedAtRY(radius, y, mu).
    local p is PeriapsisFromEY(e, y).
    if radius < p
    {
        WarningMessage(
            "FlightPathAngle(): radius is less than periapsis "
            + "  \n  radius: " + radius:tostring()
            + "  \n  periapsus: " + p:tostring()).
        return ans.
    }
    local pvel is SpeedAtRY(p, y, mu).
    if speed = 0
    {
        WarningMessage(
            "FlightPathAngle(): speed at radius is 0" 
            + "  \n  radius: " + radius:tostring()).
        return ans.
    }
    local lock eq0 to (p*pvel)/(radius*speed).
    if (eq0 > 1) or (eq0 < -1)
    {
        WarningMessage(
            "FlightPathAngle(): Cannot evaluate arcCos((p*pvel)/(radius*speed))" 
            + "  \n  Condition Violated: -1 < (p*pvel)/(radius*speed) < 1"
            + "  \n    Parameters:" 
            + "  \n      e: " + e:tostring()
            + "  \n      y: " + y:tostring()
            + "  \n      radius: " + radius:tostring()
            + "  \n      mu: " + mu:tostring()
            + "  \n    Derived Values:"
            + "  \n      p: " + p:tostring()
            + "  \n      pvel: " + pvel:tostring()
            + "  \n      speed: " + speed:tostring()).
        return ans.
    }
    set ans to arcCos(eq0).
    return ans.
}

function FlightPathAngleFromPosV
{
    parameter pos is ship:position-ship:body:position, v is ship:velocity.
    local uUp is pos:normalized.
    local vy is uUp*v.
    local vx is vectorExclude(uUp, v):mag.
    return arcTan2(vy,vx).
}

function VectorWithInvertedFlightPathAngle
{
    parameter pos is ship:position-ship:body:position, v is ship:velocity.
    local uUp is pos:normalized.
    local vy is (uUp*v)*uUp.
    local vx is vectorExclude(uUp, v).
    return vx-vy.
}

function InclinationFromRV
{
    parameter pos, vel, bod is ship:body.
    local ans is 0.
    local uUp to pos:normalized.
    local coord_nadir is bod:geoPositionOf(pos+bod:position).
    local uNorth is NorthVectorAtPos(pos, bod).
    local uBodAxis is ((sin(coord_nadir:lat)*uUp)+(cos(coord_nadir:lat)*uNorth)):normalized.
    local coord is FlightCoordAtRV(pos, vel).
    set ans to vAng(coord[2], uBodAxis).
    return ans.
}

function NorthVectorAtPos
{
    parameter pos, bod is ship:body.
    local uUp to pos:normalized.
    local coord_nadir is bod:geoPositionOf(pos+bod:position).
    local coord_nref is bod:geopositionlatlng(coord_nadir:lat+1,coord_nadir:lng).
    local uNorth is vectorExclude(uUp, ((coord_nref:position-bod:position) - (coord_nadir:position-bod:position))):normalized.
    return uNorth.
}

function HeadingFromPosV
{
    parameter pos is -1*ship:body:position, v is ship:velocity:orbit, bod is ship:body.
    local ans is 0.
    if v:istype("OrbitableVelocity")
    {
        set v to v:orbit.
    }
    if not v:istype("Vector")
    {
        WarningMessage(
            "HeadingFromPosV(): v must be vector or OrbitableVelocity, not "
            + v:typename()
            + "  \n  v: " + v:tostring()).
        return ans.
    }
    local uNorth is NorthVectorAtPos(pos, bod).
    local uEast is vcrs(pos, uNorth):normalized.
    set ans to arcTan2(uEast*v,uNorth*v).
    if ans < 0
    {
        set ans to 360 + ans.
    }
    return ans.
}

function ObtHeadingFromLatIncl
{
    parameter 
        lat is ship:geoPosition:lat, 
        i is ship:orbit:inclination, 
        southerly is false.
    set i to FixInclination(i).
    local ans is 90.
    if 
        (
            (i = 0) 
            or (i = 180) 
            or ((abs(lat)>i) and (i < 90))
            or ((abs(lat)>(180 - i)) and (i > 90))
        )
    {
        if i > 90 set ans to 270.
    }
    else if i = 90
    {
        set ans to 0.
    }
    else if i < 90
    {
        local i2 is i.
        set ans to 90 - arcTan(sqrt((sin(i2)^2) - ((sin(lat)^2)))/cos(i2)).
    }
    else if i > 90
    {
        local i2 is 20 - i.
        set ans to 270 + arcTan(sqrt((sin(i2)^2) - ((sin(lat)^2)))/cos(i2)).
    }
    if southerly
    {
        if ans = 0
        {
            set ans to 180.
        }
        else if ans <= 180
        {
            set ans to 180 - ans.
        }
        else
        {
            set ans to 540 - ans. // 270 + (270 - ans)
        }
    }
    return ans.
}

function FixInclination
{
    parameter i.
    set i to mod(abs(i), 360).
    if (i > 180)
    {
        set i to 360 - i.
    }
    return i.
}

local cbWarningMessage is def_WarningCallback@.

function Nodes_Set_WarningCallback
{
    parameter Callback.
    if Callback:istype("KOSDelegate")
    {
        set cbWarningMessage to Callback.
    }
}

local function WarningMessage
{
    parameter message.
    if cbWarningMessage:istype("KOSDelegate")
    {
        if not cbWarningMessage:isdead
        {
            cbWarningMessage(message).
        }
    }
}

function def_WarningCallback
{
    parameter message.
    set message to message.
}
