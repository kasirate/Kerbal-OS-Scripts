//function CreateCircularizeNode
//{
    parameter epoch is "apoapsis".

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
    set mnv to node(epoch, 0, 0, 0).
    Add(mnv).

    // determine altitude
    set altofburn to mnv:orbit:body:altitudeof(positionAt(ship, epoch)).
    set posofburn to positionAt(ship, epoch) - positionat(mnv:orbit:body, time:seconds).

    // speed data
    set velatburn to velocityAt(ship, epoch).
    set targetspeed to sqrt(mnv:orbit:body:mu*(1/(altofburn+mnv:orbit:body:radius))).
    set finalvel to vectorExclude(posofburn, velatburn:orbit):normalized * targetspeed.
    set dv to finalvel - velatburn:orbit.

    // edit node
    set mnv:prograde to velatburn:orbit:normalized * dv.
    set mnv:radialout to posofburn:normalized * dv.
    set mnv:normal to sqrt((dv:mag^2)-(mnv:prograde^2)-(mnv:radialout^2)).

    //ADD(mnv).
//}