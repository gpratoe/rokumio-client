' Helpers — the cross-component value and format helpers.
'
' Charter: a function lives here only when more than one component needs it AND
' its meaning is identical in each. Same-named functions with different meanings
' do NOT belong here: TypeLabel is defined four times over (DetailsScreen says
' singular "Movie", LibraryScreen falls back to "All" as its chip filter,
' DiscoverScreen titlecases free-form types, HomeScreen is plural) and unifying
' those would silently rewrite UI wording. They stay where they are, and this
' file deliberately has no opinion about labels.
'
' Included per component like Theme.bs/TileSize.bs — Roku scopes global
' functions per component, so sharing happens through the script include, never
' by importing.

' Coerce any add-on-supplied value to something a string path can hold.
'
' Add-ons are not obliged to honour the Stremio meta spec's types, and the render
' paths used to assume they did: an imdbRating arriving as the JSON number 8.1
' made `kind + " · ★ " + meta.imdbRating` throw — the interpreter's words are
' "Type Mismatch. Operator '+' can't be applied to 'String' and 'Float'" — and
' the whole header line died with it. The same shape hides wherever an add-on
' value reaches a "+" (EpisodesScreen built an episode label), a string method
' (StreamsScreen called .Trim() on a stream name), or a typed node field.
'
' There is no single native cast for this, which is why the first fix was a
' Type() ladder enumerating "Integer"/"Float"/"String"/"Boolean". That ladder is
' not sound: Type() spells a parsed JSON value differently per runtime — the
' interpreter answers "Integer"/"Float"/"String", while values that arrived
' through ParseJson on a device report the "ro" spellings (the codebase already
' leans on the other spelling at StreamsScreen.brs's roString guard). A ladder
' written against one runtime silently drops the value on the other, which for
' a rating means it quietly disappears rather than crashing.
'
' The runtime's own ToStr() is the cast that does not care: every intrinsic
' implements it, a string comes back as itself, and its number formatting needs
' no padding trimmed (8.1 renders "8.1", 8.0 renders "8", 7 stays "7"). The two
' things it cannot answer are guarded around it:
'   - invalid: ToStr answers the literal "invalid" — never something a field
'     should show — so it returns "" first.
'   - the containers: an associative array has no ToStr value at all and throws.
'     An object where text belongs is not a text, so that is "" too.
function StringOf(value as dynamic) as string
    if value = invalid then return ""
    try
        return value.ToStr()
    catch e
        return ""
    end try
end function

' Runtime echoed straight from the meta JSON — Cinemeta ships plain minutes, so
' no parsing and no "2h 5m" conversion.
'
' This used to be duplicated byte-for-byte in DetailsScreen and StreamsScreen,
' each with a comment apologising for it ("Per-component function scope:
' duplicated from StreamsScreen, since Roku does not share globals across
' components"). An add-on shipping runtime as a string or a float is the same
' coercion as every other field, so it reduces to StringOf.
function FormatRuntime(runtime as dynamic) as string
    return StringOf(runtime).Trim()
end function

' A compact genre line shared by the Home and Details heroes. Keep only a few
' entries so a noisy add-on cannot take over the hero copy.
function HeroGenresText(genres as dynamic) as string
    if Type(genres) <> "roArray" then return ""
    text = ""
    count = 0
    for each value in genres
        genre = StringOf(value).Trim()
        if genre = "" then continue for
        if text <> "" then text = text + "  ·  "
        text = text + genre
        count = count + 1
        if count >= 5 then exit for
    end for
    if text.Len() > 96 then text = Left(text, 93) + "..."
    return text
end function

' ---------------------------------------------------------------------------
' The UI-language helpers. The Settings screen speaks them first; every other
' screen and the Scene adopt the same calls as they migrate.
'
' A component holds its own copies of the two slices on m._texts (the display
' language's) and m._textsEn (the fallback's), pulled out of the Texts store.
' The copies are data, not the store instance: an associative array crossing a
' callFunc boundary arrives by value either way, so nothing here can be a
' second source of truth — the store stays the only owner of the table and a
' language change re-pulls both slices through the host.
'
' Charter note: these are cross-component AND identical in meaning wherever
' they run, so they belong here despite touching component locals (m._texts) —
' they read only what the including component is already bound to.

' Pull the two slices for the calling component from a store host NODE.
'
' The host is the argument because it is the one thing that crosses a
' component boundary: a screen holds it under an alias (m.stores.texts) and the
' Scene owns it outright (m.storeHost), and both read their words the same way
' from here. The language is read from the settings store through the same
' host, so the display language and the text can never disagree about which
' one is current.
sub LoadTexts(host as object) as void
    m._texts = invalid
    m._textsEn = invalid
    if host = invalid then return
    language = host.callFunc("SettingsGetLanguage")
    if language = invalid or language = "" then language = "en"
    m._texts = host.callFunc("TextsFor", language)
    m._textsEn = host.callFunc("TextsFor", "en")
end sub

' The language the display is in, as the settings store holds it. A screen that
' builds its words once — the Home's grid, the Episodes list — remembers the
' language it built them in and compares: the words it painted are right for
' the language they were painted in, and a change of it is what makes the
' screen rebuild.
function TextsLanguage() as string
    if m.stores = invalid then return ""
    return m.stores.settings.callFunc("SettingsGetLanguage")
end function

' A screen's slices: the same pull, through the host under the texts alias.
' A screen without a bound host gets NO slices — LoadTexts clears them — so
' Lang() degrades to English then to the key rather than crashing on an
' invalid subscript, and rather than answering with the last screen's words.
sub RefreshTexts() as void
    if m.stores = invalid then
        LoadTexts(invalid)
        return
    end if
    LoadTexts(m.stores.texts)
end sub

' One user-visible string: the display language's text, falling back through
' the English slice to the key itself. A total miss paints "section.key", which
' is self-diagnosing on the screen and in no way blank — the two failure modes
' a label has that a key in bold serif cannot be confused with. An empty value
' counts as a miss because the texts parity check in tests/run.js forbids empty
' values: anything empty in the data is a broken row, not a copy decision.
function Lang(section as string, key as string) as string
    value = invalid
    if Type(m._texts) = "roAssociativeArray" then value = TextsFromSlice(m._texts, section, key)
    if Type(value) = "String" or Type(value) = "roString" then
        if value <> "" then return value
    end if
    value = invalid
    if Type(m._textsEn) = "roAssociativeArray" then value = TextsFromSlice(m._textsEn, section, key)
    if Type(value) = "String" or Type(value) = "roString" then
        if value <> "" then return value
    end if
    return section + "." + key
end function

' One list of words from the table — the month names are the only list today,
' but a list is a thing the table can hold, so it gets the same fallback
' chain as a single word: the display language's list, then the English one,
' then invalid (the caller decides what a missing list means).
function LangList(section as string, key as string) as object
    value = invalid
    if Type(m._texts) = "roAssociativeArray" then value = TextsFromSlice(m._texts, section, key)
    if Type(value) = "roArray" then return value
    value = invalid
    if Type(m._textsEn) = "roAssociativeArray" then value = TextsFromSlice(m._textsEn, section, key)
    if Type(value) = "roArray" then return value
    return invalid
end function

' One lookup inside a slice, guarded at every level: a slice the store dropped
' (malformed data), a section a language hasn't translated yet, or a key of the
' same kind all answer invalid and let the caller's fallback chain continue.
' The value comes back as it is — a word or a list — and the caller asks for
' the kind it wants.
function TextsFromSlice(slice as dynamic, section as string, key as string) as dynamic
    if Type(slice) <> "roAssociativeArray" then return invalid
    found = slice[section]
    if Type(found) <> "roAssociativeArray" then return invalid
    value = found[key]
    if value = invalid then return invalid
    return value
end function

' Substitute {name} tokens in a template with the values given. Values arrive
' as dynamic to match data that came out of roSGNode fields or parsed JSON, and
' go through StringOf so a number or a boolean never breaks a "+" — the same
' coercion rule every other render path here runs under.
'
' Each key replaces every occurrence (a loop, since BrightScript has no
' replace-all), and untouched tokens are left visible in the text, which the
' parity linter then reads as an unfinished translation.
function Fill(template as string, values as object) as string
    text = template
    if values <> invalid
        for each name in values
            token = "{" + name + "}"
            replacement = StringOf(values[name])
            head = ""
            at = Instr(1, text, token)
            while at > 0
                head = head + Mid(text, 1, at - 1) + replacement
                text = Mid(text, at + Len(token))
                at = Instr(1, text, token)
            end while
            text = head + text
        end for
    end if
    return text
end function
