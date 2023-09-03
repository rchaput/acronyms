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

-- Replacement function (handling styles)
local replaceExistingAcronymWithStyle = require("acronyms_styles")

-- The options for the List Of Acronyms, as defined in the document's metadata.
local Options = require("acronyms_options")

--[[
The current "usage order" value.
We increment this value each time we find a new acronym, and we use it
to register the order in which acronyms appear.
--]]
local current_order = 0


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
Generate the List Of Acronyms.
Returns 2 values: the Header, and the DefinitionList.
--]]
function generateLoA()
    -- Original idea from https://gist.github.com/RLesur/e81358c11031d06e40b8fef9fdfb2682

    -- We first get the list of sorted acronyms, according to the defined criteria.
    local sorted = sortAcronyms(Acronyms.acronyms,
            Options["sorting"],
            Options["include_unused"])

    -- Create the table that represents the DefinitionList
    local definition_list = {}
    for _, acronym in ipairs(sorted) do
        -- The definition's name. A Span with an ID so we can create a link.
        local name = pandoc.Span(acronym.shortname,
            pandoc.Attr(Helpers.key_to_id(acronym.key), {}, {}))
        -- The definition's value.
        local definition = pandoc.Plain(acronym.longname)
        table.insert(definition_list, { name, definition })
    end

    -- Create the Header (only if the title is not empty)
    local header = nil
    if Options["loa_title"] ~= "" then
        local extra_classes = Options["loa_header_classes"]
        -- Create a table specifically for this LoA, and copy all "extra classes"
        -- (from the Options) to this table. The table will also contain `"loa"`.
        local loa_classes = table.move(extra_classes, 1, #extra_classes, 2, {"loa"})
        header = pandoc.Header(1,
            { table.unpack(Options["loa_title"]) },
            pandoc.Attr(Helpers.key_to_id("HEADER_LOA"), loa_classes, {})
        )
    end

    return header, pandoc.DefinitionList(definition_list)
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

    local header, definition_list = generateLoA()

    -- Insert the DefinitionList
    table.insert(doc.blocks, pos, definition_list)

    -- Insert the Header
    if header ~= nil then
        table.insert(doc.blocks, pos, header)
    end

    return pandoc.Pandoc(doc.blocks, doc.meta)
end


--[[
Place the List Of Acronyms in the document (in place of a `\printacronyms` block).
Since Header and DefinitionList are Blocks, we need to replace a Block
(Pandoc does not allow to create Blocks from Inlines).
Thus, `\printacronyms` needs to be in its own Block (no other text!).
--]]
function RawBlock(el)
    -- The block's content must be exactly "\printacronyms"
    if not (el and el.text == "\\printacronyms") then
        return nil
    end

    local header, definition_list = generateLoA()

    if header ~= nil then
        return { header, definition_list }
    else
        return definition_list
    end
end

--[[
Replace an acronym `\acr{KEY}`, where KEY is not in the `acronyms` table.
According to the options, we can either:
- warn, and return simply the KEY as text
- warn, and return "??" as text (similar to bibtex's behaviour)
- raise an error
--]]
function replaceNonExistingAcronym(acr_key)
    -- TODO: adding the source line to warnings would be useful.
    --  But maybe not doable in Pandoc?
    if Options["non_existing"] == "key" then
        quarto.log.warning("[acronyms] Acronym key", acr_key, "not recognized")
        return pandoc.Str(acr_key)
    elseif Options["non_existing"] == "??" then
        quarto.log.warning("[acronyms] Acronym key", acr_key, "not recognized")
        return pandoc.Str("??")
    elseif Options["non_existing"] == "error" then
        quarto.log.error(
            "[acronyms] Acronym key",
            tostring(acr_key),
            "not recognized, stopping!"
        )
        assert(false)
    else
        quarto.log.error(
            "[acronyms] Unrecognized option `non_existing`=`",
            tostring(Options["non_existing"]),
            "` when replacing acronyms."
        )
        assert(false)
    end
end

--[[
Replace an acronym `\acr{KEY}`, where KEY is recognized in the `acronyms` table.
--]]
function replaceExistingAcronym(acr_key)
    local acronym = Acronyms:get(acr_key)
    acronym:incrementOccurrences()
    if acronym:isFirstUse() then
        -- This acronym never appeared! We first set its usage order.
        current_order = current_order + 1
        acronym.usage_order = current_order
    end

    -- Replace the acronym with the desired style
    return replaceExistingAcronymWithStyle(
        acronym,
        Options["style"],
        Options["insert_links"]
    )
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
            return replaceExistingAcronym(acr_key)
        else
            -- The acronym does not exists
            return replaceNonExistingAcronym(acr_key)
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
