
--- Class structure

-- Simple class

-- A less common type of class that solely consists of a list of specifications. Common examples are:
-- - TrashBag
-- - BaseManager
-- - OpAI

-- Inheriting class

-- The most often used class type. A class that inherits properties from other classes while being able 
-- to define its own specifications. Common examples are:
-- - Unit = Class(moho.unit_methods) { ... }
-- - DefaultProjectileWeapon = Class(Weapon) { ... }
-- - Projectile = Class(moho.projectile_methods, Entity) { ... }

-- Because of the structure chosen we have three function calls:
-- - First function call receives (and stores) the base classes, returning a new function 
-- - Second function call receives (and processes) the class-specific specifications, returning a meta table that can be called
-- - Third function call creates an instance of the class, this is done by the engine

--- State

-- A state shares the same principle as a class: there is a simple state and a state that inherits from other states. A state is an 'intermediate' class
-- with a few (typically one or two) changed values or functions. By default the metatable hierarchy of an instance is:
-- - instance
-- - class

-- A state can put itself 'in between', like so:
-- - instance
-- - state
-- - class 

--- Debug utilities

local debug = false 

local HierarchyDebugLookup = { }
local HierarchyDebugLookupCFunctions = { }
local HierarchyDebugLookupCount = { }

local function PrintHierarchy()

    -- cache for performance
    local LOG = LOG 
    local tostring = tostring 

    local function Format(key)
        if HierarchyDebugLookupCFunctions[key] then 
            return "base instance (cfunction)"
        elseif HierarchyDebugLookup[key] then 
            return tostring(key) .. " (" .. tostring(HierarchyDebugLookup[key].func)  .. ", id = " .. tostring(HierarchyDebugLookup[key].identity) .. ")"
        else 
            return "base instance (lua function)"
        end
    end

    -- write out the hierarchy
    LOG("{ ")
    for k, v in Hierarchy do 

        local intermediate = ""
        for l = 1, v.h - 1 do 
            intermediate = intermediate .. " " .. Format(v[l])
        end

        LOG( Format(k) .. " = {" .. intermediate .. " }")
    end
    LOG("} ")
end

--- Class functionality

-- upvalue for performance
local next = next 
local unpack = unpack
local getmetatable = getmetatable
local setmetatable = setmetatable

local TableEmpty = table.empty 
local TableGetn = table.getn 

local Exclusions = { 
    __index = true,
    n = true,
}

local function Deepcopy(other)
    local copy = { }
    local type = type 
    for k, v in other do 
        if not Exclusions[k] then 
            if type(v) == "table" then 
                copy[k] = Deepcopy(v)
            else 
                copy[k] = v 
            end
        end
    end

    return copy 
end

--- Determines whether we have a simple class: one that has no base classes
local emptyMetaTable = getmetatable { }
local function IsSimpleClass(arg)
    return arg.n == 1 and getmetatable(arg[1]) == emptyMetaTable
end

--- Prepares the construction of a state, , referring to the paragraphs of text at the top of this file.
local StateIdentifier = 0
function State(...)

    -- arg = { 
    --     { 
    --         -- { table with information of base 1 } OR { specifications }
    --         -- { table with information of base 2 }
    --         -- ...
    --         -- { table with information of base n }
    --     }, 
    --     n=1 -- number of bases
    -- }

    -- State ({ field=value, field=value, ... })
    if IsSimpleClass(arg) then 
        local state = ConstructClass(nil, arg[1] )
        state.__State = true 
        state.__StateIdentifier = StateIdentifier
        StateIdentifier = StateIdentifier + 1
        return state 

    -- State (Base1, Base2, ...) ({field = value, field = value, ...})
    else 
        local bases = { unpack (arg) }
        return function(specs)
            local state = ConstructClass(bases, specs)
            state.__State = true 
            state.__StateIdentifier = StateIdentifier
            StateIdentifier = StateIdentifier + 1
            return state 
        end
    end
end

--- Prepares the construction of a class, referring to the paragraphs of text at the top of this file.
function Class(...)

    -- arg = { 
    --     { 
    --         -- { table with information of base 1 } OR { specifications }
    --         -- { table with information of base 2 }
    --         -- ...
    --         -- { table with information of base n }
    --     }, 
    --     n=1 -- number of bases
    -- }

    -- Class ({ field=value, field=value, ... })
    if IsSimpleClass(arg) then 
        local class = ConstructClass(nil, arg[1] )

        -- set the meta table and return it
        setmetatable(class, ClassFactory)
        return class

    -- Class(Base1, Base2, ...) ({field = value, field = value, ...})
    else 
        local bases = { unpack (arg) }
        return function(specs)
            local class = ConstructClass(bases, specs)

            -- set the meta table and return it
            setmetatable(class, ClassFactory)
            return class
        end
    end
end

--- look up hierarchy to help determine the relationships between classes. Can be printed using 'PrintHierarchy' 
-- defined in the debug module. An example output is:

-- function: 1E0F3E00 (OnDestroy, id = 1) = { base instance }
-- function: 1F45AA80 (OnGotTarget, id = 1) = { base instance }
-- function: 1F3902D8 (OnCreate, id = 1) = { function: 1F37B500 (OnCreate, id = 1) }
-- function: 1F40F0E0 (OnKilled, id = 1) = { function: 1F3D3EE0 (OnKilled, id = 1) }
-- function: 1DE7E1C0 (BuilderParamCheck, id = 1) = { base instance }

-- It allows us to track a function back to the base instance.
local Hierarchy = { }

--- Computes the hierarchy chain of a function: determine the path from the current function back to 
-- the base instance. Note that this assumes that the base is always called, which is not always the case.
local ChainStack = { }
local ChainCache = { }
local function ComputeHierarchyChain(a, cache)

    -- clear out the cache
    for k, v in cache do 
        cache[k] = nil 
    end

    -- populate the cache
    local stack = ChainStack 
    stack[1] = a
    local stackHead = 2 

    while stackHead > 1 do 
        -- retrieve an element from the stack
        stackHead = stackHead - 1
        local elem = stack[stackHead]

        -- add it to the hierarchy chain lookup table
        cache[elem] = true 

        -- extend the stack until we're at a base instance
        local overrides = Hierarchy[elem]
        if overrides then 
            for k = 1, overrides.h - 1 do 
                stack[stackHead] = overrides[k] 
                stackHead = stackHead + 1 
            end
        end
    end

    if debug then 
        LOG("Chain for: " .. tostring(a) .. " (" .. tostring(HierarchyDebugLookup[a].func)  .. ", id = " .. tostring(HierarchyDebugLookup[a].identity) .. ")")
        for k, v in cache do 
            LOG(tostring(k) .. ": " .. tostring(v))
        end
    end
end

--- Checks whether a is part of the hierarchy of b, or b being part of the hierarchy of a.
local function CheckHierarchy(a, b)

    local c = ChainCache

    -- populate the hierarchy chains
    ComputeHierarchyChain(a, c)

    -- if the head of chain b is part of ca, then ca is longer
    if c[b] then 
        return a
    end

    ComputeHierarchyChain(b, c)

    -- if the head of chain a is part of cb, then cb is longer
    if c[a] then 
        return b
    end 

    -- not part of a hierarchy
    return false
end

--- Constructs a class or state, referring to the paragraphs of text at the top of this file.
local Seen = { }
function ConstructClass(bases, specs)

    -- cache as locals for performance
    local type = type 
    local exclusions = Exclusions
    local hierarchy = Hierarchy
    local seen = Seen 
    local class = specs

    if bases then 

        -- special case: we have only one base and an empty specification: just return the base. There are a lot of empty classes
        -- being created, an example is: 

        -- UEL0001 = Class(ACUUnit) {
        --     Weapons = {
        --         DeathWeapon = Class(DeathNukeWeapon) {},
        --         RightZephyr = Class(TDFZephyrCannonWeapon) {},
        --         OverCharge = Class(TDFOverchargeWeapon) {},
        --         AutoOverCharge = Class(TDFOverchargeWeapon) {},
        --         TacMissile = Class(TIFCruiseMissileLauncher) {},
        --         TacNukeMissile = Class(TIFCruiseMissileLauncher) {},
        --     },
        --     (...)
        -- }

        -- there is no need to allocate a unique table for all those sub classes that have no specifications!
        if TableEmpty(specs) and TableGetn(bases) == 1 then
            return bases[1]
        end

        -- regular case: we have a specification or multiple bases: work to do!

        -- keep track of hierarchy chains
        for ks, s in specs do 
            local t = type(s)
            if t == "function" or t == "cfunction" then 
                for kb, base in bases do 
                    -- we're trying to override something here
                    if base[ks] ~= nil then 

                        -- keep track of the names and give them some unique identifier
                        if debug then 
                            HierarchyDebugLookupCount[ks] = HierarchyDebugLookupCount[ks] or 0
                            HierarchyDebugLookupCount[ks] = HierarchyDebugLookupCount[ks] + 1
                            HierarchyDebugLookup[s] = { func = ks, identity = HierarchyDebugLookupCount[ks] }  
                        end

                        -- link to or create a table
                        hierarchy[s] = hierarchy[s] or { h = 1 }

                        -- put table into a local scope and append the thing we're inheriting from
                        local elem = hierarchy[s]
                        elem[elem.h] = base[ks] 
                        elem.h = elem.h + 1 
                    end
                end
            end
        end

        -- check for collisions 
        for k, base in bases do 
            for l, element in base do 
                -- todo, refine this a bit
                if not exclusions[l] then 
                    -- first time we've seen this key, keep track of it
                    if seen[l] == nil then 
                        seen[l] = element 

                    -- we've seen this key before and it has the same matching element: we're good
                    elseif seen[l] == element then
                        -- do nothing 

                    -- we've got two elements with the same key but different values, but our specs has a function to define the behavior: we're good
                    elseif specs[l] ~= nil then
                        -- do nothing

                    -- we've got two elements with the same key but different values, check if they're not secretly a state with matching identifiers
                    elseif type(element) == "table" and (seen[l].__StateIdentifier == element.__StateIdentifier) then
                        -- do nothing 

                    else 
                        -- check if one is part of the hierarchy of the other
                        local hierarchy = CheckHierarchy(seen[l], element)
                        if hierarchy then 
                            class[l] = hierarchy 
                            seen[l] = hierarchy 

                        -- we've got two elements with the same key but they're not part of each others hierarchy chain: ambigious!
                        else    
                            error("Class initialisation: field '" .. tostring(l).. "' is ambigious between the bases. They use the same field for different values. You need to create a field in the specifications that defines the behavior.")
                            LOG(repr(debug.traceback()))
                        end
                    end
                end
            end
        end

        -- clean up seen
        for k, element in seen do 
            seen[k] = nil 
        end

        -- populate class 
        for k, base in bases do 
            for l, element in base do 
                if class[l] == nil then 
                    class[l] = element 
                end
            end
        end

        -- post-process the states to make sure that they're unique and have the correct meta table set
        for k, v in class do 
            -- any member that has a meta table set is by definition a state
            if type(v) == "table" and v.__State then 

                -- copy the content into a new table
                local d = Deepcopy(v) 

                -- set meta table information
                d.__index = d 
                setmetatable(d, class)

                -- override previous entry
                class[k] = d
            end
        end
    end

    class.__index = class

    return class
end

--- Instantiation of a class, referring to the paragraphs of text at the top of this file. 
ClassFactory = { }
function ClassFactory:__call(...)

    -- create the new entity with us as its meta table
    local instance = { }
    setmetatable(instance, self)

    -- call class initialisation functions, if they exist
    local initfn = self.__init
    local postinitfn = self.__post_init
    if initfn or postinitfn then
        if initfn then 
            initfn(instance, unpack(arg))
        end

        if postinitfn then 
            postinitfn(instance, unpack(arg))
        end
    end

    return instance
end

--- Switches up the sate of a class instance by inserting the new state between the instance and its class
-- @param instance The current instance we want to switch states for
-- @param newState the state we want to insert between the instance and its base class
function ChangeState(instance, newstate)

    -- call on-exit function
    if instance.OnExitState then
        instance.OnExitState(instance)
    end

    -- keep track of the original thread and forget about it inside the object
    local old_main_thread = instance.__mainthread
    instance.__mainthread = nil

    -- change the state accordingly by switching up the meta tables:
    -- - entity
    -- - state      <-- introduced as an intermediate, prevents a lot of duplicated values and tables
    -- - class
    setmetatable(instance, newstate)

    -- call on-enter function
    if instance.OnEnterState then
        instance.OnEnterState(instance)
    end

    -- start the new main thread if it wasn't already created during an OnEnterState
    if instance.Main and not instance.__mainthread then
        instance.__mainthread = ForkThread(instance.Main, instance)
    end

    -- remove the old main thread, threads are de-allocated when they've completed their computation chain
    if old_main_thread then
        old_main_thread:Destroy()
    end
end

--- Flattens a list of elements.
-- @param flattee output table
-- @param hierarchy table to be flattened
-- @param seen table to prevents duplications
local function Flatten (flattee, hierarchy, seen)
    -- cache for performance
    local type = type 

    for k, entry in hierarchy do 
        if type(entry) == "table"  then 
            if not seen[entry] then 
                seen[entry] = true 
                Flatten(flattee, entry, seen)
            end
        else 
            flattee[k] = entry 
        end
    end
end

--- Converts a C class into a simplified Lua class with no bases. This must adjust the cclass in place as the reference
-- to the table appears to be hardcoded in the engine.
function ConvertCClassToLuaSimplifiedClass(cclass)

    if getmetatable(cclass) == ClassFactory then
        LOG("Already populated class: " .. tostring(cclass))
        return
    end

    local seen = { }
    local flatten = { }
    Flatten(flatten, cclass, seen )

    -- the reference to the table is hardcoded in the engine, therefore we need to re-populate the cclass or functions
    -- such as CreateAimManipulator that return a table with the metatable attached won't work properly :sad_cowboy:

    -- remove all entries in the class
    for k, val in cclass do 
        cclass[k] = nil 
    end

    -- re-populate it
    for k, val in flatten do 
        cclass[k] = val 

        -- allow us to print it out
        if debug then 
            HierarchyDebugLookupCFunctions[val] = true
        end
    end

    -- allow tables to search the meta table
    cclass.__index = cclass 
    setmetatable(cclass, ClassFactory)
end