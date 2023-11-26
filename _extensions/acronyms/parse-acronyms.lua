--[[
    Lua Filter to parse acronyms in a Markdown document.

    Acronyms must be in the form `\acr{key}` where key is the acronym key.
    The first occurrence of an acronym is replaced by its long name, as
    defined by a list of acronyms in the document's metadata.
    Other occurrences are simply replaced by the acronym's short name.

    A List of Acronym is also generated (similar to a Glossary in LaTeX),
    and all occurrences contain a link to the acronym's definition in this
    List.
]]

-- Some helper functions
local Helpers = require("acronyms_helpers")

-- The Acronyms database
local Acronyms = require("acronyms")

-- Sorting function
local sortAcronyms = require("sort_acronyms")

-- Replacement function
local AcronymsPandoc = require("acronyms_pandoc")

-- The options for the List Of Acronyms, as defined in the document's metadata.
local Options = require("acronyms_options")


--[[
    Parse the document's metadata, including options, and acronyms' definitions.
    It does not change the metadata.
--]]
function Meta(m)
    Options:parseOptionsFromMetadata(m)

    -- Parse acronyms directly from the metadata (`acronyms.keys`)
    Acronyms:parseFromMetadata(m, Options["on_duplicate"])

    -- Parse acronyms from external files
    if (m and m.acronyms and m.acronyms.fromfile) then
        if Helpers.isMetaList(m.acronyms.fromfile) then
            -- We have several files to read
            for _, filepath in ipairs(m.acronyms.fromfile) do
                filepath = pandoc.utils.stringify(filepath)
                Acronyms:parseFromYamlFile(filepath, Options["on_duplicate"])
            end
        else
            -- We have a single file
            local filepath = pandoc.utils.stringify(m.acronyms.fromfile)
            Acronyms:parseFromYamlFile(filepath, Options["on_duplicate"])
        end
    end

    return nil
end


--[[
    Append the List Of Acronyms to the document (at the beginning).
--]]
function appendLoA(doc)
    local pos
    if not Options["insert_loa"] then
        -- If disabled, do nothing
        return nil
    elseif Options["insert_loa"] == "beginning" then
        -- Insert at the first block in the document
        pos = 1
    elseif Options["insert_loa"] == "end" then
        -- Insert at the last block in the document
        pos = #doc.blocks + 1
    else
        quarto.log.error(
            "[acronyms] Unrecognized option `insert_loa`=`",
            tostring(Options["insert_loa"]),
            "` in `appendLoA`."
        )
        assert(false)
    end

    local header, definition_list = AcronymsPandoc.generateLoA()

    -- Insert the DefinitionList
    table.insert(doc.blocks, pos, definition_list)

    -- Insert the Header
    if header ~= nil then
        table.insert(doc.blocks, pos, header)
    end

    return pandoc.Pandoc(doc.blocks, doc.meta)
end


--[[
    Place the List of Acronyms in the document, in place of a `\printacronysm`.

    This is used when the user wants to generate the LoA at a very specific
    place (instead of "simply" at the beginning or end).
    Because the Header (title) and DefinitionList (LoA itself) are Blocks,
    we must replace a Block as well (Pandoc does not allow to create Blocks
    from Inlines). Thus, `\printacronyms` needs to be in its own Block (no
    other text!).
--]]
function RawBlock(el)
    -- The block's content must be exactly "\printacronyms"
    if not (el and el.text == "\\printacronyms") then
        return nil
    end

    local header, definition_list = AcronymsPandoc.generateLoA()

    if header ~= nil then
        return { header, definition_list }
    else
        return definition_list
    end
end


--[[
Replace each `\acr{KEY}` with the correct text and link to the list of acronyms.
--]]
function replaceAcronym(el)
    local acr_key = string.match(el.text, "\\acr{(.+)}")
    if acr_key then
        -- This is an acronym, we need to parse it.
        if Acronyms:contains(acr_key) then
            -- The acronym exists (and is recognized)
            return AcronymsPandoc.replaceExistingAcronym(acr_key)
        else
            -- The acronym does not exists
            return AcronymsPandoc.replaceNonExistingAcronym(acr_key)
        end
    else
        -- This is not an acronym, return nil to leave it unchanged.
        return nil
    end
end


-- Force the execution of the Meta filter before the RawInline
-- (we need to load the acronyms first!)
-- RawBlock and Doc happen after RawInline so that the actual usage order
-- of acronyms is known (and we can sort the List of Acronyms accordingly)
return {
    { Meta = Meta },
    { RawInline = replaceAcronym },
    { RawBlock = RawBlock },
    { Pandoc = appendLoA },
}
