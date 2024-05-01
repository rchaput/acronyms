--[[
    Functions to translate some (hardcoded) sentences to the language
    that is both available and closest to the user's preference.

    Matching algorithm in this file are based on RFC4647; languages are
    based on RFC5646 (see Quarto's documentation about the `lang` option).
--]]


local Translations = {
    -- Add custom translations here.
    -- Each table refers to one given "sentence" to translate.
    -- The table's contents must be the translations, indexed by a language.
    -- Languages can be specified using subtags, for example, `en-GB` or `en-US`.
    loa_title = {
        [""] = "List Of Acronyms", -- Default value
        ["en"] = "List Of Acronyms",
        ["fr"] = "Liste des Acronymes",
    }
}


-- Simplified Lookup, based on RFC4647; does not explicitly support private
-- subtags (`x-...`) but they should not be used in Quarto anyway.
-- `lang` must be the user's preferred language range (e.g., `zh-Hant-CN`).
-- `translations` must be a table, indexed by language tags.
-- Returns a table { lang, translation }, where `lang` is the closest language
-- found, and `translation` is the desired string in the found language.
function Translations:find_best(lang, translations)
    quarto.log.debug("[acronyms] Request translation for ", lang)

    -- We will need to iterate over the subtags; for example, for `zh-Hant-CN`,
    -- it should yield `zh-Hant-CN`, then `zh-Hant`, then `zh` (and finally ``).
    -- This loop populates the table with `{ "", "zh", "zh-Hant", "zh-Hant-CN" }`.
    local lang_components = {""}
    local previous = ""
    for component in string.gmatch(lang, "[^-]+") do
        if previous == "" then
            previous = component
        else
            previous = previous .. "-" .. component
        end
        table.insert(lang_components, previous)
    end

    -- Now, we iterate over the (reversed) table, because we want to start with
    -- the most specific lang. If this lang is found, we return it immediately.
    for i = #lang_components, 1, -1 do
        if translations[lang_components[i]] ~= nil then
            local found_lang = lang_components[i]
            local found_translation = translations[lang_components[i]]
            quarto.log.debug("[acronyms] Found translation ", found_translation,
                " for lang ", found_lang)
            return {
                ["lang"] = found_lang,
                ["translation"] = found_translation
            }
        end
    end
    return nil
end

function Translations:get_loa_title(lang)
    local found = self:find_best(lang, self.loa_title)
    if found == nil then
        quarto.log.error(
            "[acronyms] Could not find a suitable translation for ", lang, "!",
            "Please ensure that a default translation is available for loa_title"
        )
        assert(false)
    end
    return found["translation"]
end

return Translations
