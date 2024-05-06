--[[

This file defines the Options table.

--]]


-- The table that holds all options, with their default values.
-- We will also add a few methods to this table, to handle these options
-- (parse them from configuration files, get them, ...).
local Options = {

    -- The language used in this document (Quarto standard option), following
    -- the IETF BCP47 standard, i.e., a tag composed of subtags, separated by
    -- hyphens (`-`). For example: `en-US`. The first subtag represent the
    -- language itself (`en`, `fr`, `zh`, ...), other subtags represent
    -- more precise information (region, script, ...).
    lang = "",

    -- The prefix to prepend to all acronym's ID (to ensure their uniqueness).
    -- IDs are especially used to link an acronym to its definition in the List
    -- of Acronyms.
    id_prefix = "acronyms_",

    -- How to sort acronyms in the List of Acronyms.
    -- Please refer to the `sort_acronyms.lua` file for allowed values.
    sorting = "alphabetical",

    -- The title (header) that precedes the List of Acronyms (LoA).
    loa_title = nil,

    -- Whether to include in the LoA acronyms that have not been used.
    include_unused = true,

    -- Whether to insert the LoA, and where.
    insert_loa = "beginning",

    -- How to deal with non-existing acronyms.
    non_existing = "key",

    -- How to deal with duplicate definitions of acronyms.
    on_duplicate = "warn",

    -- The style to use when replacing an acronym.
    -- Please refer to the `acronyms_styles.lua` for allowed values.
    style = "long-short",

    -- Whether to insert a link to the acronym's definition in the LoA when
    -- replacing (rendering) an acronym.
    insert_links = true,

    -- Additional classes to add to the List of Acronyms header.
    loa_header_classes = {},

    -- Custom format for the List of Acronyms, as a Markdown template in which
    -- the `{shortname}` and `{longname}` placeholders will be replaced.
    loa_format = nil,

}


--[[
Parse the options from the Metadata (i.e., the YAML fields).
--]]
function Options:parseOptionsFromMetadata(m)
    quarto.log.debug("[acronyms] Parsing options from metadata...", m.acronyms)
    -- Load the lang (can be `nil`); this is the only option outside `acronyms`.
    if m.lang ~= nil then
        self.lang = pandoc.utils.stringify(m.lang)
    end

    -- The options that we are interested in are all grouped under `acronyms`.
    -- If it does not exist, use an empty table.
    options = m.acronyms or {}

    if options["id_prefix"] ~= nil then
        self.id_prefix = pandoc.utils.stringify(options["id_prefix"])
    end

    if options["sorting"] ~= nil then
        self.sorting = pandoc.utils.stringify(options["sorting"])
    end

    if options["loa_title"] ~= nil then
        if pandoc.utils.stringify(options["loa_title"]) == "" then
            -- Writing `loa_title: ""` in the YAML returns `{}` (an empty table).
            -- `pandoc.utils.stringify({})` returns `""` as well.
            -- This value indicates that the user does not want a Header.
            self.loa_title = ""
        else
            -- For any other case, we want to use the exact same value,
            -- (not stringified!), i.e., a Pandoc object.
            self.loa_title = options["loa_title"]
        end
    end

    if options["include_unused"] ~= nil then
        -- This value should be a boolean here, we do not need to stringify it.
        self.include_unused = options["include_unused"]
    end

    if options["insert_loa"] ~= nil then
        if options["insert_loa"] == false then
            -- Special value: keep it exactly as-is.
            self.insert_loa = false
        else
            -- Default case: it should be "beginning", or "end", we want it
            -- as a string.
            self.insert_loa = pandoc.utils.stringify(options["insert_loa"])
        end
    end

    if options["non_existing"] ~= nil then
        self.non_existing = pandoc.utils.stringify(options["non_existing"])
    end

    if options["on_duplicate"] ~= nil then
        self.on_duplicate = pandoc.utils.stringify(options["on_duplicate"])
    end

    if options["style"] ~= nil then
        self.style = pandoc.utils.stringify(options["style"])
    end

    if options["insert_links"] ~= nil then
        -- This value should be a boolean here, we do not need to stringify it.
        self.insert_links = options["insert_links"]
    end

    if options["loa_header_classes"] ~= nil then
        for _, v in ipairs(options["loa_header_classes"]) do
            table.insert(self.loa_header_classes, pandoc.utils.stringify(v))
        end
    end

    if options["loa_format"] ~= nil then
        if pandoc.utils.type(options["loa_format"]) == "Inlines" then
            self.loa_format = options["loa_format"][1].text
        else
            self.loa_format = pandoc.utils.stringify(options["loa_format"])
        end
    end
end


return Options
