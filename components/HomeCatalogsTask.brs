' HomeCatalogsTask — walk every installed add-on's catalogs off the UI thread.
' Manifests are resolved here where the registry has none (built-ins), and each
' browsable catalog is fetched. One completed catalog is published per result
' notification; the Task never republishes all previous rows. That keeps
' cross-thread copies proportional to the catalogs fetched, while Home fills
' progressively. A hung add-on costs the worker thread, not a frozen channel.
' Only plain add-on descriptors and the hidden-catalog selection cross in from
' HomeScreen; no store object crosses the task boundary.

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
                    if HomeCatalogBrowsable(descriptor)
                        if not HomeCatalogIsHidden(addon.address, descriptor.type, descriptor.id, m.top.hiddenCatalogs)
                            response = catalog.Catalog(addon.address, descriptor.type, descriptor.id)
                            if response.ok and response.metas <> invalid and response.metas.Count() > 0
                                row = {
                                    index: index
                                    addonAddress: addon.address
                                    catalogId: descriptor.id
                                    title: CatalogTitle(descriptor, addon)
                                    metaType: descriptor.type
                                    metas: response.metas
                                }
                                index = index + 1
                                m.top.result = { row: row, done: false }
                            end if
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
