--[[

    This file defines the sorting strategies.

    A sorting strategy (or comparator) is a function that receives 2
    acronyms, and returns a boolean which indicates whether the first
    one should be before the second one (according to its criterion).

    Sorting strategies are leveraged using `table.sort(table, comp)`
    where `comp` is one of these strategies.

--]]


-- The table containing all the sorting strategies.
local sorting_strategies = {}


-- Sort acronyms by their shortname, in case-sensitive alphabetical order.
sorting_strategies["alphabetical"] = function(acronym1, acronym2)
    -- TODO: check that this works with UTF-8 characters
    return acronym1.shortname < acronym2.shortname
end


-- Sort acronyms by their shortname, in case-insensitive alphabetical order.
sorting_strategies["alphabetical-case-insensitive"] = function(acronym1, acronym2)
    return acronym1.shortname:upper() < acronym2.shortname:upper()
end


-- Sort acronyms by their definition order (first to last).
sorting_strategies["initial"] = function(acronym1, acronym2)
    return acronym1.definition_order < acronym2.definition_order
end


-- Sort acronyms by their usage order.
-- Unused acronyms must NOT be included! (Their order is `nil`)
sorting_strategies["usage"] = function(acronym1, acronym2)
    return acronym1.usage_order < acronym2.usage_order
end


-- The "public" API, i.e., the function returned by `require`.
function sort_acronyms(acronyms, criterion, include_unused)
    assert(acronyms ~= nil,
        "[acronyms] The acronyms table must not be nil in sort_acronyms!")
    assert(criterion ~= nil,
        "[acronyms] The criterion must be not nil in sort_acronyms!")
    local comparator = sorting_strategies[criterion]
    if (comparator == nil) then
        local msg = "[acronyms] Error when sorting acronyms:\n"
        msg = msg .. "! Sorting criterion unrecognized: " .. tostring(criterion) .. "\n"
        msg = msg .. "i Please check the `acronyms.sorting` metadata option.\n"
        quarto.log.error(msg)
        assert(false)
    end

    -- Special rule: cannot use `usage` criterion if `include_unused` is true.
    -- Otherwise, comparison of potentially nil values will crash.
    if criterion == "usage" and include_unused then
        local msg = "[acronyms] Error when sorting acronyms:\n"
        msg = msg .. "! Cannot sort by `usage` when `include_unused` is true\n"
        msg = msg .. "i Please set another sorting or set `include_unused` to `false`."
        quarto.log.error(msg)
        assert(false)
    end

    -- The acronyms table is indexed by keys, not by ints. Thus,
    -- we cannot use `ipairs` to walk over it in a specific order.
    -- To sort the table, we need to create a second table first,
    -- indexed by ints (i.e., a sequence).
    local sequence_acronyms = {}
    for _, acronym in pairs(acronyms) do
        if include_unused or acronym.usage_order ~= nil then
            table.insert(sequence_acronyms, acronym)
        end
    end

    -- Sort the keys according to the criterion
    table.sort(sequence_acronyms, comparator)

    return sequence_acronyms
end

return sort_acronyms
