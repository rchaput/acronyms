--[[
    Functions to generate Pandoc elements.

    These functions are independent of the "entrypoint" script: they work
    with both:
    - filters (i.e., scripts that parse the Pandoc content and react to various
      elements);
    - shortcodes (i.e., scripts that are triggered by the new Quarto syntax,
      `{{< shortcode-name args >}}`).

    This allows **acronyms** to work with its legacy filter mode, by reacting
    to `\acr{key}` and `\printacronyms` elements, and with the new shortcode
    syntax. However, due to the way it was coded, the legacy filter mode will
    not support arguments and keyworded arguments. The shortcode mode is
    particularly suited for these new features, as it is handled by Quarto
    itself directly. It will be easier for users to customize a specific
    acronym or list of acronym, rather than specifying options in the Metadata.
]]

-- The Acronyms database
local Acronyms = require("acronyms")

-- Some helper functions
local Helpers = require("acronyms_helpers")

-- Sorting function
local sortAcronyms = require("sort_acronyms")

-- Replacement function (handling styles)
local replaceExistingAcronymWithStyle = require("acronyms_styles")

-- The options for the List Of Acronyms, as defined in the document's metadata.
local Options = require("acronyms_options")

-- The translations for some hardcoded sentences (such as the LoA Title)
local Translations = require("acronyms_translations")

-- The functions that we define here, and which will generate Pandoc elements
local AcronymsPandoc = {}


--[[
    Replace an acronym whose key is not found in the `acronyms` table with the
    corresponding Pandoc elements.

    Params:
    - acr_key: the acronym's key (identifier).
    - non_existing: controls which behaviour to use:
        - `key` => warn, and simply return the key as a Pandoc text
        - `??` => warn, and return `"??"` as a pandoc Text (similar to bibtex's
            behaviour)
        - `error` => raise an error, and stop execution
--]]
function AcronymsPandoc.replaceNonExistingAcronym(acr_key, non_existing)
    -- TODO: adding the source line to warnings would be useful.
    --  But maybe not doable in Pandoc?
    
    -- Use default option if not set
    non_existing = non_existing or Options["non_existing"]

    if non_existing == "key" then
        quarto.log.warning("[acronyms] Acronym key", acr_key, "not recognized")
        return pandoc.Str(acr_key)
    elseif non_existing == "??" then
        quarto.log.warning("[acronyms] Acronym key", acr_key, "not recognized")
        return pandoc.Str("??")
    elseif non_existing == "error" then
        quarto.log.error(
            "[acronyms] Acronym key",
            tostring(acr_key),
            "not recognized, stopping!"
        )
        assert(false)
    else
        quarto.log.error(
            "[acronyms] Unrecognized option `non_existing`=`",
            tostring(non_existing),
            "` when replacing acronyms."
        )
        assert(false)
    end
end


--[[
    Replace an acronym identified by its key, which exists in the `acronyms`
    table, and generate the corresponding Pandoc elements.

    Params:
    - key: identifies the acronym to replace.
    - style: the style to use when replacing (see the `acronyms_styles.lua` file).
    - first_use: whether we want to print this acronym as its first use, or
        a "next use". Set to `nil` to use the acronym's own counter, or override
        it directly by setting to `true` or `false`.
    - insert_links: whether to insert a link to this acronym's definition in
        the List of Acronyms.
--]]
function AcronymsPandoc.replaceExistingAcronym(acr_key, style, first_use, insert_links)
    quarto.log.debug("[acronyms] Replacing acronym", acr_key)
    local acronym = Acronyms:get(acr_key)
    acronym:incrementOccurrences()
    if acronym:isFirstUse() then
        -- This acronym never appeared! We first set its usage order.
        Acronyms:setAcronymUsageOrder(acronym)
    end

    -- Use default values from Options if not specified
    style = style or Options["style"]
    if insert_links == nil then insert_links = Options["insert_links"] end

    -- Replace the acronym with the desired style
    return replaceExistingAcronymWithStyle(
        acronym,
        style,
        insert_links,
        first_use
    )
end


--[[
    Generate the List Of Acronyms, as a Definition List.

    This method is used internally by `generateLoA`.
-- ]]
function AcronymsPandoc.generateDefinitionList(sorted_acronyms)
    local definition_list = {}
    for _, acronym in ipairs(sorted_acronyms) do
        -- The definition's name. A Span with an ID so we can create a link.
        local name = pandoc.Span(
            acronym.shortname,
            pandoc.Attr(Helpers.key_to_id(acronym.key), {}, {})
        )
        -- The definition's value.
        local definition = pandoc.Plain(acronym.longname)
        table.insert(definition_list, { name, definition })
    end
    return pandoc.DefinitionList(definition_list)
end


--[[
    Generate the List Of Acronyms with a custom (user-supplied) format.

    This method is used internally by `generateLoA`.
--]]
function AcronymsPandoc.generateCustomFormat(sorted_acronyms, loa_format)
    -- Most people will want a list; if we render each item independently,
    -- it will not look correctly in the final document. We thus concatenate
    -- all acronyms in a temporary Markdown document before rendering it.
    local document_markup = ""
    for _, acronym in ipairs(sorted_acronyms) do
        quarto.log.debug(
            "[acronyms] Generating definition for acronym", acronym.key
        )
        local id = Helpers.key_to_id(acronym.key)
        -- The acronym's name. We want it to be rendered with an ID attribute.
        local name = "[" .. acronym.shortname .. "]{#" .. id .. "}"
        -- The `loa_format` should be a Markdown template, with `{shortname}`
        -- and `{longname}` as placeholder values that we must replace.
        local acronym_markup = loa_format:gsub("{shortname}", name)
        acronym_markup = acronym_markup:gsub("{longname}", acronym.longname)
        quarto.log.debug(
            "[acronyms] Template markup processed as", acronym_markup
        )
        document_markup = document_markup .. acronym_markup .. "\n\n"
    end
    quarto.log.debug("[acronyms] Rendering Markdown markup:\n", document_markup)
    local document = pandoc.read(document_markup)
    -- We want to return all rendered blocks (potentially multiline content,
    -- such as bullet lists, divs, paragraphs, ...); but we cannot use `blocks`
    -- directly. Quarto expects a single Block, not Blocks.
    -- The `pandoc.util.blocks_to_inlines` function should be useful, but
    -- adds incorrect trailing `\` to some templates...
    -- Wrapping the blocks in a Div seems the safest option, although it
    -- adds an unnecessary (but still working) `<div> ... </div>` markup.
    return pandoc.Div(document.blocks)
end


--[[
    Generate the List Of Acronyms.

    Returns 2 values: the Header, and the list of acronyms. By default, it is
    rendered as a DefinitionList, but a custom format can be used, in which
    case it is rendered as Markdown directly.

    Params:
    - sorting: the sorting method to use.
    - include_unused: whether to include unused acronyms.
    - title: the header title ; use `''` (the empty string) to avoid generating
        a header (the user wants to create the header manually).
    - header_classes: the table of extra classes to put to the header.
--]]
function AcronymsPandoc.generateLoA(sorting, include_unused, title, header_classes)
    -- Original idea from https://gist.github.com/RLesur/e81358c11031d06e40b8fef9fdfb2682

    -- Use default options if not specified
    sorting = sorting or Options["sorting"]
    include_unused = include_unused or Options["include_unused"]
    if title == nil then
        -- No shortcode-specific value given
        if Options["loa_title"] ~= nil then
            -- A value given in the metadata (options)
            title = Options["loa_title"]
        else
            -- If neither the metadata nor the shortcode option are specified,
            -- by default we use the translation for the user's language
            title = pandoc.MetaInlines(pandoc.Str(Translations:get_loa_title(Options["lang"])))
        end
    end
    header_classes = header_classes or Options["loa_header_classes"]
    local loa_format = Options["loa_format"]

    -- We first get the list of sorted acronyms, according to the defined criteria.
    local sorted = sortAcronyms(
        Acronyms.acronyms,
        sorting,
        include_unused
    )

    -- Create the actual List of Acronyms
    local list_acronyms
    if loa_format == nil then
        -- Default format: create a DefinitionList
        list_acronyms = AcronymsPandoc.generateDefinitionList(sorted)
    else
        -- Custom format, render acronyms based on the requested format.
        list_acronyms = AcronymsPandoc.generateCustomFormat(sorted, loa_format)
    end

    -- Create the Header (only if the title is not empty)
    local header = nil
    if title ~= "" then
        local extra_classes = header_classes
        -- Create a table specifically for this LoA, and copy all "extra classes"
        -- (from the Options) to this table. The table will also contain `"loa"`.
        local loa_classes = table.move(extra_classes, 1, #extra_classes, 2, {"loa"})
        header = pandoc.Header(
            1,
            { table.unpack(title) },
            pandoc.Attr(Helpers.key_to_id("HEADER_LOA"), loa_classes, {})
        )
    end

    return header, list_acronyms
end


return AcronymsPandoc
