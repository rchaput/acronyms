--[[
    Quarto Shortcodes to replace acronyms in a Quarto document.

    Acronyms must be in the form `{{< acr key >}}` where key is the acronym key.
    The shortcode format (contrary to filters) allows specifying keyworded
    arguments to better control the output (e.g., specific style, forcing first
    or next occurrence, etc.).

    The List of Acronyms can also be generated with the `{{< printacronyms >}}`
    shortcode.

    The filter (`parse-acronyms.lua`) remains useful even if only shortcodes
    are used (i.e., no `\acr{key}`): it is responsible for parsing the metadata
    once, and automatically appending the LoA (if the user sets the Options
    accordingly).
]]

-- Some helper functions
local Helpers = require("acronyms_helpers")

-- The Acronyms database
local Acronyms = require("acronyms")

-- Replacement functions
local AcronymsPandoc = require("acronyms_pandoc")

-- The options for the List Of Acronyms, as defined in the document's metadata.
local Options = require("acronyms_options")


--[[
    Define the "main" shortcode behaviour: replacing an acronym.

    This function is associated to shortcodes `acronym` and `acr` so that it is
    invoked through `{{< acr KEY >}}` or `{{< acronym KEY >}}`.
--]]
function replaceAcronym (args, kwargs, meta)
    -- We want exactly 1 (unnamed) argument for the shortcode.
    if #args == 0 or #args > 1 then
        quarto.log.error(
            "[acronyms] Incorrect number of arguments in shortcode `acronym`!\n",
            "! Expected exactly 1 argument (the acronym key).\n",
            "x Found ", tostring(#args), ".\n",
            "i The arguments were: `", pandoc.utils.stringify(args), "`.\n"
        )
        assert(false)
    end

    local acronym_key = pandoc.utils.stringify(args[1])
    if Acronyms:contains(acronym_key) then
        -- The acronym exists (and is recognized)
        return AcronymsPandoc.replaceExistingAcronym(acronym_key)
    else
        -- The acronym does not exists
        return AcronymsPandoc.replaceNonExistingAcronym(acronym_key)
    end
end


--[[
    Generate the List of Acronyms in the document.
--]]
function generateListOfAcronyms (args, kwargs, meta)
    if #args ~= 0 then
        quarto.log.warning(
            "[acronyms] Unused arguments passed to shortcode `printacronyms`:",
            "expected 0, found", tostring(#args), "."
        )
    end

    local header, definition_list = AcronymsPandoc.generateLoA()

    if header ~= nil then
        return { header, definition_list }
    else
        return definition_list
    end
end


--[[
    Define the possible shortcodes for Quarto.
--]]
return {
    ["acronym"] = replaceAcronym,
    -- Same function but with a shorter name.
    ["acr"] = replaceAcronym,
    ["print-acronyms"] = generateListOfAcronyms,
}
