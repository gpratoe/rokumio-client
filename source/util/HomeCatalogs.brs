' HomeCatalogs — shared rules for catalogs that can be rendered as Home rows.
'
' Home and its row-picker must agree on which catalogs are usable. Home can
' browse with skip=0 only, so catalogs requiring any other extra are excluded.
' Identity matching stays tuple-based to avoid delimiter collisions in URLs or
' catalog ids.

function HomeCatalogBrowsable(catalog as dynamic) as boolean
    if catalog = invalid or Type(catalog) <> "roAssociativeArray" then return false
    if GetInterface(catalog.type, "ifString") = invalid or catalog.type = "" then return false
    if GetInterface(catalog.id, "ifString") = invalid or catalog.id = "" then return false

    required = catalog.extraRequired
    if required <> invalid and Type(required) = "roArray"
        for each name in required
            if name <> "skip" then return false
        end for
    end if

    extras = catalog.extra
    if extras <> invalid and Type(extras) = "roArray"
        for each extra in extras
            if extra <> invalid and Type(extra) = "roAssociativeArray"
                if extra.isRequired = true and extra.name <> "skip" then return false
            end if
        end for
    end if
    return true
end function

' Can this catalog meta be opened at all? A tile's whole life after the row
' lands is keyed on meta.id: Details is entered with it (the add-on meta
' endpoint, streams resolution, save/resume/watched are all addressed by it),
' and every downstream library call takes it as text. An add-on meta that ships
' without a usable id cannot be opened — so it must not be rendered either
' (a tile whose OK does nothing is a worse lie than a missing tile). Intrinsics
' only, so every screen and the test bundle share one definition.
function HomeMetaOpenable(meta as dynamic) as boolean
    if meta = invalid or Type(meta) <> "roAssociativeArray" then return false
    if GetInterface(meta.id, "ifString") = invalid or meta.id = "" then return false
    return true
end function

' Splits a raw add-on meta list into the metas that can be opened and a count
' of the ones that cannot. Pure — no logging, no UI — so Home, Discover and
' Search filter with one spelling of the rule and keep their own context for
' the warning each drop deserves. See HomeMetaOpenable for why an unusable id
' means the meta must not be rendered either.
function FilterOpenableMetas(metas as dynamic) as object
    result = { openable: [], dropped: 0 }
    if metas = invalid or Type(metas) <> "roArray" then return result
    for each meta in metas
        if HomeMetaOpenable(meta)
            result.openable.Push(meta)
        else
            result.dropped = result.dropped + 1
        end if
    end for
    return result
end function

function HomeCatalogIsHidden(addonAddress as string, metaType as string, catalogId as string, hiddenCatalogs as dynamic) as boolean
    if hiddenCatalogs = invalid or Type(hiddenCatalogs) <> "roArray" then return false
    for each hidden in hiddenCatalogs
        if hidden <> invalid and Type(hidden) = "roAssociativeArray"
            if hidden.addonAddress = addonAddress and hidden.metaType = metaType and hidden.catalogId = catalogId then return true
        end if
    end for
    return false
end function
