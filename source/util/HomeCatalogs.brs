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

function HomeCatalogIsHidden(addonAddress as string, metaType as string, catalogId as string, hiddenCatalogs as dynamic) as boolean
    if hiddenCatalogs = invalid or Type(hiddenCatalogs) <> "roArray" then return false
    for each hidden in hiddenCatalogs
        if hidden <> invalid and Type(hidden) = "roAssociativeArray"
            if hidden.addonAddress = addonAddress and hidden.metaType = metaType and hidden.catalogId = catalogId then return true
        end if
    end for
    return false
end function
