' HomeCatalogsTask — walk every installed add-on's catalogs off the UI thread.
' Manifests are resolved here where the registry has none (built-ins), and each
' browsable catalog is fetched. One completed catalog is published per result
' notification; the Task never republishes all previous rows. That keeps
' cross-thread copies proportional to the catalogs fetched, while Home fills
' progressively. A hung add-on costs the worker thread, not a frozen channel.
' Only plain { address, catalogs } descriptors cross in from HomeScreen.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    try
        http = Transport()
        catalog = CatalogStore(http)
        index = 0

        for each addon in m.top.addons
            catalogs = addon.catalogs
            if catalogs = invalid or Type(catalogs) <> "roArray"
                if addon.address <> invalid and addon.address <> ""
                    answer = catalog.Manifest(addon.address)
                    if answer.ok and answer.manifest.catalogs <> invalid then catalogs = answer.manifest.catalogs
                end if
            end if
            if catalogs <> invalid and Type(catalogs) = "roArray"
                for each descriptor in catalogs
                    if CatalogBrowsable(descriptor)
                        response = catalog.Catalog(addon.address, descriptor.type, descriptor.id)
                        if response.ok and response.metas <> invalid and response.metas.Count() > 0
                            row = {
                                index: index
                                addonAddress: addon.address
                                title: CatalogTitle(descriptor, addon)
                                metaType: descriptor.type
                                metas: response.metas
                            }
                            index = index + 1
                            m.top.result = { row: row, done: false }
                        end if
                    end if
                end for
            end if
        end for

        m.top.result = { done: true }
    catch e
        m.top.result = { done: true, error: e.message }
    end try
end sub

' A catalog is browsable when none of its required extras demand more than the
' plain skip=0 browse supplies (the same rule the old synchronous Home walk
' applied).
function CatalogBrowsable(catalog as object) as boolean
    if catalog = invalid then return false
    required = catalog.extraRequired
    if required <> invalid and Type(required) = "roArray"
        for each name in required
            if name <> "skip" then return false
        end for
    end if
    extras = catalog.extra
    if extras <> invalid and Type(extras) = "roArray"
        for each extra in extras
            if extra.isRequired = true and extra.name <> "skip" then return false
        end for
    end if
    return true
end function

' A row title that is always a non-empty string. Real-world manifests (Stremio's
' own Channels addon included) ship catalogs with only type/id and no name, and
' an invalid title crashes the Home title pipeline (an associative array cannot
' be keyed by invalid). Fall back: catalog name -> catalog id -> addon name ->
' "Unknown". The addon packet carries name so a nameless catalog still gets a
' recognizable label.
function CatalogTitle(catalog as object, addon as object) as string
    title = catalog.name
    if title = invalid or title.Trim() = ""
        title = catalog.id
    end if
    if title = invalid or title.Trim() = ""
        title = addon.name
    end if
    if title = invalid or title.Trim() = ""
        title = "Unknown"
    end if
    return title
end function
