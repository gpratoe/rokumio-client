' AddonJson — normalize an add-on's JSON once, where it arrives.
'
' CHARTER: this file exists because add-ons are not obliged to honour the Stremio
' spec's types, and every store and screen that reads a manifest/meta/stream/
' subtitle field used to have to defend itself at the point of use. One of them
' did not, and the whole app noticed: `EpisodesStore.NeedsMetaFetch` compared
' `meta.imdbRating` to "", Cinemeta answers that field with the JSON NUMBER 8.1,
' and `8.1 = ""` is "Type Mismatch. Operator '=' can't be applied to 'roFloat'
' and 'String'" (runtime error &h18) — thrown out of the Details screen that
' asked. The same shape sat in a dozen other places, waiting for the one add-on
' that sends a duration as a number.
'
' The checks at the point of use were the wrong shape of fix: they are per field,
' per read, and a field nobody remembered to guard is a crash nobody can test for
' (the add-on that triggers it is not the one you have installed). This file
' moves the work to the boundary instead — every payload is walked once, right
' after ParseJson, and the fields the app treats as TEXT are coerced to text.
' After that the stores compare strings to strings and the screens render text,
' and the platform's number-where-text-belongs has nowhere left to throw.
'
' OPT-IN, BY FIELD NAME, AND THAT IS THE POINT. A blanket "turn every scalar into
' a string" pass would break the fields that are numbers and are MEANT to be:
' video.season and video.episode reach EpisodesStore's season arithmetic and
' PlaybackStore's EpisodeFilters, fileIdx reaches Int() in DirectFileIdx, and the
' library's progress is compared to 0. So a name is coerced only if the app reads
' it as text, and everything unlisted — including every field an add-on invents —
' passes through exactly as it arrived. Nothing here validates; unknown keys are
' none of this file's business.
'
' The two tables below ARE the contract, and tests/run.js holds them to it:
' checkAddonJsonContract() parses every store and screen with brighterscript's own
' parser and fails the suite when a payload field is compared to a string, passed
' to a string method, concatenated into a string, or written into a typed node
' text field without being named here. So the failure mode of "we added a text
' read and forgot the table" is a red suite, not a device crash with the one
' add-on nobody had installed at review time.
'
' What is deliberately NOT listed, and why:
'   url, infoHash          PlaybackStore reads both through its own AsText, which
'                          answers "" for anything that is not text, and that is
'                          the right answer: a number there is not a URL, and
'                          coercing it would manufacture a plausible-looking one
'                          ("1234") and try to play it.
'   sources, announce       tracker lists, read through AsText entry by entry.
'   types, idPrefixes       read only by HasType/MatchesIdPrefixes, which skip a
'                          non-text entry by contract — see the array table.
'   season, episode, fileIdx, progress
'                          numbers by meaning — see the OPT-IN note above.
'   behaviorHints.filename read through AsText; the stream-format detector is the
'                          only caller and it wants "" for a non-filename.
'   everything else        an add-on's own keys are left exactly as they came.
'
' Included per component like Helpers.brs/Theme.bs — Roku scopes user-defined
' global functions per component, and a store method resolves a bare global
' against the component that INVOKED it. Every component that includes one of the
' add-on-facing stores (CatalogStore, EpisodesStore, AddonsStore, PlaybackStore,
' SubtitlesStore) therefore has to include this file too; checkAddonJsonContract()
' reads the XMLs and fails when one does not, because the device failure is
' "attempted call of a non-function" in whichever screen asked.

' The scalar fields the app reads as text. Grouped by the payload they come from.
function AddonJsonTextFieldNames() as object
    return [
        ' meta and the video entries inside meta.videos
        "id", "type", "name", "poster", "posterShape", "background", "logo",
        "description", "overview", "releaseInfo", "imdbRating", "runtime",
        "released", "firstAired", "thumbnail",
        ' streams — the four the stream card renders (name is in the meta group)
        "title", "quality", "source",
        ' subtitle tracks — lang is the code the picker matches on, langName its label
        "lang", "langName",
        ' the manifest and its catalogs
        "version"
    ]
end function

' The array fields whose elements are text: a catalog's genre list (the Discover
' chip labels) and the extra-name lists. Each is read one element at a time,
' sometimes through a comparison its reader cannot guard — HomeCatalogsTask
' compares an extraRequired element to "skip", DiscoverScreen compares a genre
' option to the current year — so a number inside one is the same crash one level
' down, and coercing the element is what removes it.
'
' types and idPrefixes are deliberately NOT here. Their only readers are HasType
' and MatchesIdPrefixes, and skipping a non-text entry is what those are
' specified to do ("a declared type that is not text cannot be a match"). Coercing
' the list would make a declared `8` a type HasType answers true for when asked
' for "8" — a behaviour change with nothing unsafe left behind it. A field is
' listed here when a RAW read of it can throw, not merely because it is a list of
' names.
function AddonJsonTextArrayFieldNames() as object
    return [
        "genres", "options",
        "extraSupported", "extraRequired"
    ]
end function

' The entry point: normalize a freshly parsed add-on payload in place and return
' it. Called at every ingress (the five add-on-facing stores) and again over
' persisted registry records on Load(), so data written by an older build is
' covered on the way back in.
'
' In place, never a rebuild: on a device this runs over every catalog row and
' every metas array, and a copy of a 100-meta payload is real memory on a Roku
' for no benefit. Only existing keys are ever written (never added or deleted),
' which is what makes walking and writing in the same pass safe.
function NormalizeAddonJson(value as dynamic) as dynamic
    textScalars = AddonJsonLookup(AddonJsonTextFieldNames())
    textArrays = AddonJsonLookup(AddonJsonTextArrayFieldNames())
    return AddonJsonWalk(value, textScalars, textArrays)
end function

' A name -> true map so the walk can ask "is this a text field" with one lookup
' instead of a linear scan of the tables per key (a catalog row is hundreds of
' keys, and the tables are rebuilt per key otherwise).
function AddonJsonLookup(names as object) as object
    map = {}
    for each name in names
        map[name] = true
    end for
    return map
end function

' The walk. Recursion is unconditional — catalogs inside a manifest, videos
' inside a meta, extra entries inside a catalog — because the coercion is what is
' opt-in, not the descent. Only a listed name is rewritten:
'   scalar field named in the text table   -> text
'   array field named in the array table   -> each scalar element text
'   anything else                          -> left exactly as it arrived
function AddonJsonWalk(value as dynamic, textScalars as object, textArrays as object) as dynamic
    if value = invalid then return invalid
    kind = Type(value)

    if kind = "roAssociativeArray"
        for each key in value
            if textScalars[key] = true
                value[key] = AddonJsonAsText(value[key])
            else if textArrays[key] = true
                value[key] = AddonJsonArrayAsText(value[key])
            else
                child = value[key]
                if child <> invalid
                    childKind = Type(child)
                    ' The old walk called itself for every leaf too; most meta
                    ' fields are scalars, so a large catalog paid a BrightScript
                    ' function call per field just to discover that the leaf had
                    ' no children. Only containers can contain another listed
                    ' field, so recurse only into those and leave scalar leaves
                    ' exactly as they arrived.
                    if childKind = "roAssociativeArray" or childKind = "roArray"
                        AddonJsonWalk(child, textScalars, textArrays)
                    end if
                end if
            end if
        end for
        return value
    end if

    if kind = "roArray"
        for i = 0 to value.Count() - 1
            child = value[i]
            if child <> invalid
                childKind = Type(child)
                if childKind = "roAssociativeArray" or childKind = "roArray"
                    AddonJsonWalk(child, textScalars, textArrays)
                end if
            end if
        end for
        return value
    end if

    return value
end function

' A listed scalar as text, with the two answers that are not a cast:
'   invalid   stays invalid. An absent field has to stay absent — the stores ask
'             "is there a value here" (NeedsMetaFetch's hero fields) and "" would
'             answer yes to a field the add-on never sent.
'   container stays a container. An object where text belongs is not a text, and
'             ToStr on it throws; the store guards that case where it reads it.
' Everything else is the runtime's own ToStr: a string comes back as itself, and
' 8.1 renders "8.1" — the exact text the hero line wanted.
function AddonJsonAsText(value as dynamic) as dynamic
    if value = invalid then return invalid
    if GetInterface(value, "ifString") <> invalid then return value
    if Type(value) = "roArray" or Type(value) = "roAssociativeArray" then return value
    return value.ToStr()
end function

' Each scalar element of a listed array as text. Containers inside it are left
' alone (a manifest's `options` may be objects), so the array keeps its shape and
' gains text where it had numbers.
function AddonJsonArrayAsText(value as dynamic) as dynamic
    if Type(value) <> "roArray" then return value
    for i = 0 to value.Count() - 1
        item = value[i]
        if item = invalid then continue for
        if GetInterface(item, "ifString") <> invalid then continue for
        if Type(item) = "roArray" or Type(item) = "roAssociativeArray" then continue for
        value[i] = item.ToStr()
    end for
    return value
end function
