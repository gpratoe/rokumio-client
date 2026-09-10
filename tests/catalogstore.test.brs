' CatalogStore unit tests.
'
' CatalogStore is pure transport: catalog/manifest/search are endpoint calls to
' an add-on server and nothing is stored locally. The scripted transport owns
' the exact URLs so the URL-building contract is pinned by these tests.

sub Test_Catalog_Manifest()
    Harness_Suite("CatalogStore.Manifest normalizes a manifest")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/manifest.json"
            ok: true
            status: 200
            json: {
                id: "com.linvo.cinemeta"
                name: "Cinemeta"
                version: "3.0.14"
                types: ["movie", "series"]
                catalogs: [
                    { type: "movie", id: "top", name: "Top" }
                    { type: "series", id: "top", name: "Top Series" }
                ]
                resources: ["catalog", "meta"]
            }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Manifest(address)

    Harness_Ok(result.ok, "manifest ok")
    Harness_Equal(result.manifest.id, "com.linvo.cinemeta", "id parsed")
    Harness_Equal(result.manifest.name, "Cinemeta", "name parsed")
    Harness_Equal(result.manifest.catalogs.Count(), 2, "catalogs parsed")
end sub

sub Test_Catalog_ManifestRejectsMissingId()
    Harness_Suite("CatalogStore.Manifest rejects a manifest without id")
    script = [
        { method: "GET", ok: true, status: 200, json: { name: "No id" }, error: "" }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Manifest("https://addon.example.com")

    Harness_Ok(not result.ok, "manifest rejected")
    Harness_Equal(result.error, "manifest missing id or name", "error names the missing field")
end sub

sub Test_Catalog_FetchPreservesQuery()
    Harness_Suite("CatalogStore.Catalog keeps user query args in the URL")
    script = [
        {
            method: "GET"
            url: "https://addon.example.com/catalog/movie/top/skip=0.json?provider=yts"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000001", type: "movie", name: "One" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog("https://addon.example.com?provider=yts", "movie", "top")

    Harness_Ok(result.ok, "catalog ok")
    Harness_Equal(result.metas.Count(), 1, "one meta returned")
end sub

sub Test_Catalog_Fetch()
    Harness_Suite("CatalogStore.Catalog fetches a catalog row")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/skip=0.json"
            ok: true
            status: 200
            json: {
                metas: [
                    { id: "tt0000001", type: "movie", name: "One" }
                    { id: "tt0000002", type: "movie", name: "Two" }
                ]
            }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "movie", "top")

    Harness_Ok(result.ok, "catalog ok")
    Harness_Equal(result.metas.Count(), 2, "two metas returned")
    Harness_Equal(result.metas[0].name, "One", "meta fields intact")
end sub

sub Test_Catalog_Search()
    Harness_Suite("CatalogStore.Search hits the add-on search catalog")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/search/matrix.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0133093", type: "movie", name: "The Matrix" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Search(address, "movie", "matrix")

    Harness_Ok(result.ok, "search ok")
    Harness_Equal(result.metas.Count(), 1, "one meta returned")
end sub

sub Test_Catalog_RejectsMissingMetas()
    Harness_Suite("CatalogStore.Catalog rejects a payload without metas")
    script = [
        { method: "GET", ok: true, status: 200, json: { something: "else" }, error: "" }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog("https://addon.example.com", "movie", "top")

    Harness_Ok(not result.ok, "catalog rejected")
    Harness_Equal(result.error, "catalog response missing metas", "error names the missing field")
end sub

sub Test_Catalog_NoAddress()
    Harness_Suite("CatalogStore refuses calls without an address")
    store = CatalogStore(ScriptedTransport([]))
    result = store.Catalog("", "movie", "top")

    Harness_Ok(not result.ok, "catalog rejected")
    Harness_Equal(result.error, "no addon address", "error names the missing address")
end sub