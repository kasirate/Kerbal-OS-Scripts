@lazyGlobal off.

function OpenConsole
{
    core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
}

function Banner
{
    parameter message.
    print "==============================".
    print "".
    print "  " + message.
    print "".
    print "==============================".
}
