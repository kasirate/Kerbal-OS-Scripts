@lazyGlobal off.

parameter Program is "".

global ProgramLoaderReady is true.

local function main 
{
    init().
    Dependency("0:/ProgramLoader").
    if Program:Length > 0
    Dependency(Program).
}

local function init
{
    if not (defined DependencyList)
    {
        global DependencyList is lexicon().
    }
    if not (defined ProgramLoadingCount)
    {
        global ProgramLoadingCount is 0.
    }
}

global function isLoading
{
    if not (defined ProgramLoadingCount) return false.
    return ProgramLoadingCount > 0.
}

function Dependency
{
    parameter fpath, alias is false.
    if fpath:istype("String") set fpath to path(fpath).
    if alias:istype("Boolean")
    {
        set alias to path("1:/" + fpath:name).
    }
    local ans is true.
    init().
    local doDependencies is true.
    if addons:available("RT")
    {
        if not Addons:RT:HasKSCConnection(ship)
        {
            set doDependencies to false.
        }
    }
    if not DependencyList:haskey(alias)
    {
        //print "DependencyList:haskey(" + alias + ") = " + DependencyList:haskey(alias).
        if doDependencies
        {
            copyPath(fpath, alias).
        }
        if exists(alias)
        {    
            set ProgramLoadingCount to ProgramLoadingCount + 1.
            runOncePath(alias).
            set ProgramLoadingCount to ProgramLoadingCount - 1.
            set ans to true.
        }
        else
        {
            set ans to false.
        }
        if not DependencyList:haskey(alias)
        DependencyList:Add(alias, list(fpath, alias, ans)).
    }
    else
    {
        if not DependencyList[alias][2] and doDependencies
        {
            copyPath(fpath, alias).
        }
        if exists(alias)
        {    
            set ProgramLoadingCount to ProgramLoadingCount + 1.
            runOncePath(alias).
            set ProgramLoadingCount to ProgramLoadingCount - 1.
            set ans to true.
        }
        else
        {
            set ans to false.
        }
        set DependencyList[alias][2] to ans.
    }
    return ans.
}

function LoadDependencies
{
    init().
    local doDependencies is true.
    local ans is true.
    if addons:available("RT")
    {
        if not Addons:RT:HasKSCConnection(ship)
        {
            set doDependencies to false.
        }
    }
    switch to 1.
    if DependencyList:Length > 0
    {
        local ndx is 0.
        until ndx >= DependencyList:length
        {
            local fpath is DependencyList:values[ndx][0].
            local alias is DependencyList:values[ndx][1].
            local isLoaded is DependencyList:values[ndx][2].
            // if not exists(alias)
            if not isLoaded
            {
                if doDependencies
                {
                    copyPath(fpath, alias).
                }
                if exists(alias)
                {
                    set DependencyList:values[ndx][2] to true.
                }
                else
                {
                    set DependencyList:values[ndx][2] to false.
                    set ans to false.
                }
            }
            set ndx to ndx + 1.
        }
    }
    return ans.
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