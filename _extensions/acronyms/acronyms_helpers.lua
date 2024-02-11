--[[

This file defines a few helper functions, in particular with respect to pandoc.

--]]

local Options = require("acronyms_options")


local Helpers = {}


-- Helper function to determine pandoc's version.
-- `version` must be a table of numbers, e.g., `{2, 17, 0, 1}`
function Helpers.isAtLeastVersion(version)
    -- `PANDOC_VERSION` exists since 2.1, but we never know...
    if PANDOC_VERSION == nil then
        return false
    end
    -- Loop up over the components
    -- e.g., `2.17.0.1` => [0]=2, [1]=17, [2]=0, [3]=1
    for k, v in ipairs(version) do
        if PANDOC_VERSION[k] == nil or PANDOC_VERSION[k] < version[k] then
            -- Examples: 2.17 < 2.17.0.1, or 2.16 < 2.17
            return false
        elseif PANDOC_VERSION[k] > version[k] then
            -- Example: 2.17 > 2.16.2 (we do not need to check the next!)
            return true
        end
    end
    -- At this point, all components are equal
    return true
end


-- Helper function to determine whether a metadata field is a list.
function Helpers.isMetaList(field)
    -- We want to know whether we have multiple values (MetaList).
    -- Pandoc 2.17 introduced a compatibility-breaking change for this:
    --  the `.tag` is no longer present in >= 2.17 ;
    --  the `pandoc.utils.type` function is only available in >= 2.17
    if Helpers.isAtLeastVersion({2, 17}) then
        -- Use the new `pandoc.utils.type` function
        return pandoc.utils.type(field) == "List"
    else
        -- Use the (old) `.tag` type attribute
        return field.t == "MetaList"
    end
end


-- Helper function to generate the ID (identifier) from an acronym key.
-- The ID can be used for, e.g., links.
function Helpers.key_to_id(key)
    return Options["id_prefix"] .. key
end


-- Similar helper but for the link itself (based on the ID).
function Helpers.key_to_link(key)
    return "#" .. Helpers.key_to_id(key)
end


-- Helper to print a Pandoc Metadata.
-- From a metadata (e.g., a YAML map), it returns a table-like string:
-- `{ key1: value1 ; key2: value2 ; ... }`.
function Helpers.metadata_to_str(metadata)
    -- We need to reformat a bit the table
    local t = {}
    for k, v in pairs(metadata) do
        table.insert(t, k .. ": " .. pandoc.utils.stringify(v))
    end
    return "{ " .. table.concat(t, " ; ") .. " }"
end


-- Helper to convert a (case-insensitive) string to a boolean
-- Recognized values: `true`, `false`, `yes`, `no`, `y`, `n`
function Helpers.str_to_boolean(value)
    local converts = {
        ["true"] = true,
        ["false"] = false,
        ["yes"] = true,
        ["no"] = false,
        ["y"] = true,
        ["n"] = false,
    }
    local result = converts[string.lower(value)]
    if result == nil then
        quarto.log.warning(
            "[acronyms] Could not convert string to boolean, unrecognized value:",
            value,
            " ! Assuming `false`."
        )
        result = false
    end
    return result
end


return Helpers
