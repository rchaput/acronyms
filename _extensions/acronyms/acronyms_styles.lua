--[[

    This file defines the "styles" to replace acronyms.

    Such styles control how to use the acronym's short name,
    long name, whether one should be between parentheses, etc.

    Styles are largely inspired from the LaTeX package "glossaries"
    (and "glossaries-extra").
    A gallery of the their styles can be found at:
    https://www.dickimaw-books.com/gallery/index.php?label=sample-abbr-styles
    A more complete document (rather long) can be found at:
    https://mirrors.chevalier.io/CTAN/macros/latex/contrib/glossaries-extra/samples/sample-abbr-styles.pdf

    More specifically, this file defines a table of functions.
    Each function takes an acronym, and return one or several Pandoc elements.
    These elements will replace the original acronym call in the Markdown 
    document.

    Most styles will depend on whether this is the acronym's first occurrence,
    ("first use") or not ("next use"), similarly to the LaTeX "glossaries".

    For example, a simple (default) style can be to return the acronym's
    long name, followed by the short name between parentheses.
    When the parser encounters `\acr{RL}`, assuming that `RL` is correctly
    defined in the acronyms database, the corresponding function would 
    return a Pandoc Link, where the text is "Reinforcement Learning (RL)",
    and pointing to the definition of "RL" in the List of Acronyms.
    
    Note: the acronym's key MUST exist in the acronyms database.
    Functions to replace a non-existing key must be handled elsewhere.

--]]

local Helpers = require("acronyms_helpers")


-- The table containing all styles, indexed by the style's name.
local styles = {}


-- Transform inlines or strings according to case_kind while preserving inline structure.
function Helpers.transform_case(value, case_kind)
    if case_kind == nil then return value end

    -- String values
    if type(value) == "string" then
        if case_kind == "upper" then return value:upper()
        elseif case_kind == "lower" then return value:lower()
        elseif case_kind == "sentence" then return Helpers.capitalize_first(value)
        else return value end
    end

    -- If it's not a plain inline array, check for Pandoc Inlines/List
    if not Helpers.is_inline_array(value) then
        if Helpers.isAtLeastVersion({2, 17}) then
            local t = pandoc.utils.type(value)
            if t ~= "Inlines" and t ~= "List" then
                return value
            end
        else
            return value
        end
    end

    local done_first = false
    local simple_containers = {
        Emph=true, Strong=true, Span=true, Strikeout=true,
        SmallCaps=true, Superscript=true, Subscript=true, Underline=true
    }

    local function transform_inlines(src)
        local dest = {}
        for _, il in ipairs(src) do
            if il.t == "Str" and (il.text or il.c) then
                local txt = il.text or il.c
                if case_kind == "upper" then
                    txt = txt:upper()
                elseif case_kind == "lower" then
                    txt = txt:lower()
                elseif case_kind == "sentence" and not done_first then
                    local i = txt:find("%a")
                    if i then
                        txt = txt:sub(1,i-1)..txt:sub(i,i):upper()..txt:sub(i+1)
                        -- set done_first to ensure only one capitalization in sentence case
                        done_first = true
                    end
                end
                dest[#dest+1] = pandoc.Str(txt)
            elseif simple_containers[il.t] and type(il.c) == "table" then
                local inner = transform_inlines(il.c)
                if il.t == "Span" then
                    dest[#dest+1] = pandoc.Span(inner, il.attr)
                else
                    local ctor = pandoc[il.t]
                    if ctor then
                        dest[#dest+1] = ctor(inner)
                    else
                        local copy = {}
                        for k, v in pairs(il) do copy[k] = v end
                        copy.c = inner
                        dest[#dest+1] = copy
                    end
                end
            else
                dest[#dest+1] = il
            end
        end
        return dest
    end

    return transform_inlines(value)
end


-- Helper to join two inline arrays as: <front> (<back>)
function make_parenthesized(front_elems, back_elems, insert_links, key)
    front_elems = Helpers.ensure_inlines(front_elems)
    back_elems = Helpers.ensure_inlines(back_elems)
    local all = {}
    for _, v in ipairs(front_elems) do table.insert(all, v) end
        table.insert(all, pandoc.Str(" ("))
    for _, v in ipairs(back_elems) do table.insert(all, v) end
        table.insert(all, pandoc.Str(")"))
    if insert_links then
        return { pandoc.Link(all, Helpers.key_to_link(key)) }
    else
        return all
    end
end


-- Create a rich element preserving inline structures; returns a table of inlines.
-- Use this function to add links to acronym occurrences.
function create_element(content, key, insert_links)
    if Helpers.isAtLeastVersion({2, 17}) and pandoc.utils.type(content) == "Inline" then
        -- content is already a single inline, use it directly
        if insert_links then
            return { pandoc.Link({content}, Helpers.key_to_link(key)) }
        else
            return {content}
        end
    else
        -- otherwise, ensure it's inlines
        local inlines = Helpers.ensure_inlines(content)
        if insert_links then
            return { pandoc.Link(inlines, Helpers.key_to_link(key)) }
        else
            return inlines
        end
    end
end


-- First use: long name (short name)
-- Next use: short name
styles["long-short"] = function(acronym, insert_links, is_first_use)
    if is_first_use then
        return make_parenthesized(acronym.longname, acronym.shortname, insert_links, acronym.key)
    else
        return create_element(acronym.shortname, acronym.key, insert_links)
    end
end


-- First use: short name (long name)
-- Next use: short name
styles["short-long"] = function(acronym, insert_links, is_first_use)
    if is_first_use then
        return make_parenthesized(acronym.shortname, acronym.longname, insert_links, acronym.key)
    else
        return create_element(acronym.shortname, acronym.key, insert_links)
    end
end

-- First use: long name
-- Next use: long name
styles["long-long"] = function(acronym, insert_links)
    return create_element(acronym.longname, acronym.key, insert_links)
end

-- First use: short name [^1]
-- [^1]: short name: long name
-- Next use: short name
styles["short-footnote"] = function(acronym, insert_links, is_first_use)
    if is_first_use then
        -- Main text: plain shortname (no link)
        local shortname_inlines = Helpers.ensure_inlines(acronym.shortname)
        -- Footnote: [shortname](link): longname
        local shortname_link = create_element(acronym.shortname, acronym.key, insert_links)
        local longname_elem = Helpers.ensure_inlines(acronym.longname)
        local plain = {}
        for _, v in ipairs(shortname_link) do table.insert(plain, v) end
        table.insert(plain, pandoc.Str(": "))
        for _, v in ipairs(longname_elem) do table.insert(plain, v) end
        local note = pandoc.Note(pandoc.Plain(plain))

        -- Build the returned list: main inline(s) followed by the note
        local result = {}
        for _, v in ipairs(shortname_inlines) do table.insert(result, v) end
        table.insert(result, note)
        return result
    else
        return create_element(acronym.shortname, acronym.key, insert_links)
    end
end


-- The "public" API of this module, the function which is returned by
-- require.
return function(acronym, style_name, insert_links, is_first_use, plural, 
    case_target, case)
    -- Check that the requested strategy exists
    assert(style_name ~= nil,
        "[acronyms] The parameter style_name must not be nil!")
    assert(styles[style_name] ~= nil,
        "[acronyms] Style " .. tostring(style_name) .. " does not exist!")

    -- Check that the acronym exists
    assert(acronym ~= nil,
        "[acronyms] The acronym must not be nil!")

    -- Determine if it is the first use (if left unspecified)
    if is_first_use == nil then
        is_first_use = acronym:isFirstUse()
    end

    -- Transform this acronym prior to rendering
    -- e.g., for plural form; and for sentence case
    acronym = acronym:clone()
    if plural then
        -- Apply plural forms (explicit provided parts already present; fallbacks safe for non-markdown components).
        acronym.shortname = acronym.plural.shortname
        acronym.longname = acronym.plural.longname
    end

    -- Delegate case transformation to Helpers.transform_case which preserves inline formatting
    if case_target == "short" or case_target == "both" then
        acronym.shortname = Helpers.transform_case(acronym.shortname, case)
    end
    if case_target == "long" or case_target == "both" then
        acronym.longname = Helpers.transform_case(acronym.longname, case)
    end

    local rendered = styles[style_name](acronym, insert_links, is_first_use, case_target)
    return rendered
end
