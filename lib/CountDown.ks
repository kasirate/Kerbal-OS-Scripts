@lazyGlobal off.


function doCountDown
{
    parameter Count.
    from {Count.} 
    until Count = 0 
    step { set Count to Count - 1.}
    do
    {
        print "T-" + Count.
        wait 1.
    }
    print "T-" + 0.
}