' AddonsStore unit tests.
'
' Cinemeta and OpenSubtitles v3 are built-in (Stremio official, protected).
' Everything else installs by fetching a full manifest URL through the scripted
' transport; installed records persist through the mock registry.

function ManifestFixture(id as string, name as string) as object
    return {
        id: id
        name: name
        version: "1.0.0"
        types: ["movie", "series"]
        catalogs: [
            { type: "movie", id: "top", name: "Top" }
            { type: "series", id: "top", name: "Top Series" }
        ]
        resources: ["catalog", "meta"]
    }
end function

sub Test_Addons_BuiltInsPresent()
    Harness_Suite("AddonsStore ships the official built-ins")
    addons = AddonsStore(ScriptedTransport([]), invalid)
    list = addons.GetAll()

    Harness_Equal(list.Count(), 2, "two built-in add-ons")
    Harness_Ok(addons.Get("com.linvo.cinemeta") <> invalid, "cinemeta present")
    Harness_Ok(addons.Get("org.stremio.opensubtitlesv3") <> invalid, "opensubtitles v3 present")
    Harness_Equal(addons.Get("com.linvo.cinemeta").builtin, true, "cinemeta marked builtin")
    Harness_Equal(addons.Get("org.stremio.opensubtitlesv3").address, "https://opensubtitles-v3.strem.io", "opensubtitles address seeded")
    Harness_Equal(addons.Get("com.stremio.torrentio"), invalid, "torrentio is not a built-in")
end sub

sub Test_Addons_BuiltInsProtected()
    Harness_Suite("AddonsStore refuses to uninstall built-ins")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Ok(not addons.Uninstall("com.linvo.cinemeta"), "cannot uninstall cinemeta")
    Harness_Ok(not addons.Uninstall("org.stremio.opensubtitlesv3"), "cannot uninstall opensubtitles")
    Harness_Equal(addons.GetAll().Count(), 2, "all built-ins remain")
end sub

sub Test_Addons_TorrentioSeededFirstRun()
    Harness_Suite("AddonsStore seeds Torrentio on first run as a removable add-on")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry)

    Harness_Equal(addons.GetAll().Count(), 3, "built-ins plus seeded torrentio")
    torrentio = addons.Get("com.stremio.torrentio")
    Harness_Ok(torrentio <> invalid, "torrentio present after first run")
    Harness_Equal(torrentio.builtin, false, "seeded torrentio is not a built-in")
    Harness_Equal(torrentio.address, "https://torrentio.strem.fun", "torrentio address seeded")
    Harness_Equal(torrentio.resources[0], "stream", "torrentio streams stream links")

    Harness_Ok(addons.Uninstall("com.stremio.torrentio"), "seeded torrentio can be removed")
    Harness_Equal(addons.Get("com.stremio.torrentio"), invalid, "torrentio gone after removal")
    Harness_Equal(addons.GetAll().Count(), 2, "back to built-ins only")

    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Equal(reopened.Get("com.stremio.torrentio"), invalid, "removal is not undone on reload")
    Harness_Equal(reopened.GetAll().Count(), 2, "no re-seed after a removal")
end sub

sub Test_Addons_Install()
    Harness_Suite("AddonsStore.Install fetches the manifest and stores the add-on")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(result.id, "com.example.addon", "returns the manifest id")
    record = addons.Get("com.example.addon")
    Harness_Equal(record.name, "Example", "name stored")
    Harness_Equal(record.address, "https://addon.example.com", "stored address is the base (no manifest.json)")
    Harness_Equal(record.builtin, false, "installed add-on not builtin")
    Harness_Equal(addons.GetAll().Count(), 3, "built-ins plus the new one")
end sub

sub Test_Addons_TorrentioNotBuiltInButSeeded()
    Harness_Suite("AddonsStore.Install keeps the seeded torrentio")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)

    Harness_Ok(addons.Install(manifestUrl).ok, "install ok")
    Harness_Ok(addons.Get("com.stremio.torrentio") <> invalid, "seeded torrentio still installed")
    Harness_Equal(addons.Get("com.stremio.torrentio").builtin, false, "seeded torrentio is removable")
    Harness_Equal(addons.GetAll().Count(), 4, "built-ins + torrentio + example")
end sub

sub Test_Addons_RejectsInvalidManifest()
    Harness_Suite("AddonsStore.Install rejects a manifest without id/name")
    script = [
        { method: "GET", ok: true, status: 200, json: { name: "Missing id" }, error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install("https://addon.example.com/manifest.json")

    Harness_Ok(not result.ok, "install rejected")
    Harness_Equal(result.error, "manifest missing id or name", "error names the missing field")
    Harness_Equal(addons.GetAll().Count(), 2, "nothing installed")
end sub

sub Test_Addons_InstallWithQueryArgs()
    Harness_Suite("AddonsStore.Install handles manifest URLs with query args")
    manifestUrl = "https://addon.example.com/manifest.json?token=abc&v=2"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(addons.transport.log.Count(), 1, "exactly one manifest fetch")
    Harness_Equal(addons.transport.log[0].url, manifestUrl, "fetches the exact URL including query args")
    record = addons.Get("com.example.addon")
    Harness_Equal(record.address, "https://addon.example.com?token=abc&v=2", "stored address keeps all query args")
end sub

sub Test_Addons_InstallSubPath()
    Harness_Suite("AddonsStore.Install handles a manifest in a sub-path")
    manifestUrl = "https://addon.example.com/path/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(addons.transport.log[0].url, manifestUrl, "fetches the exact sub-path URL")
    Harness_Equal(addons.Get("com.example.addon").address, "https://addon.example.com/path", "stored address is the sub-path base")
end sub

sub Test_Addons_NormalizesObjectResources()
    Harness_Suite("AddonsStore.Install normalizes object resources to names")
    manifestUrl = "https://addon.example.com/manifest.json"
    manifest = ManifestFixture("com.example.addon", "Example")
    manifest.resources = [
        { name: "stream", types: ["movie", "series"], idPrefixes: ["tt", "kitsu"] }
        "meta"
    ]
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: manifest, error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    resources = addons.Get("com.example.addon").resources
    Harness_Equal(resources.Count(), 2, "object + string resources kept")
    Harness_Equal(resources[0], "stream", "object resource reduced to its name")
    Harness_Equal(resources[1], "meta", "string resource passed through")
end sub

sub Test_Addons_LoadNormalizesObjectResources()
    Harness_Suite("AddonsStore.Load normalizes persisted object resources")
    registry = MockRegistry()
    stale = {
        "com.example.addon": {
            id: "com.example.addon"
            name: "Example"
            version: "1.0.0"
            types: ["movie"]
            catalogs: []
            resources: [{ name: "stream" }]
            address: "https://addon.example.com"
            builtin: false
        }
    }
    registry.values["addons"] = FormatJson(stale)
    addons = AddonsStore(ScriptedTransport([]), registry)

    resources = addons.Get("com.example.addon").resources
    Harness_Equal(resources.Count(), 1, "one resource after load")
    Harness_Equal(resources[0], "stream", "object resource normalized to its name")
end sub

sub Test_Addons_RejectsInvalidAddress()
    Harness_Suite("AddonsStore.Install rejects malformed addon addresses")
    cases = [
        ""
        "  "
        "addon.example.com"
        "not a url"
        "ftp://addon.example.com"
        "https://"
        "https://addon.example.com:abc"
        "https://:8080"
        "https://addon.example.com"
    ]
    addons = AddonsStore(ScriptedTransport([]), invalid)
    for each input in cases
        result = addons.Install(input)
        Harness_Ok(not result.ok, "rejected: " + input)
    end for
    Harness_Equal(addons.GetAll().Count(), 2, "nothing installed")
    Harness_Equal(addons.transport.log.Count(), 0, "no request dispatched for invalid input")
end sub

sub Test_Addons_RejectsDuplicate()
    Harness_Suite("AddonsStore.Install refuses an already-installed id")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    Harness_Ok(addons.Install(manifestUrl).ok, "first install ok")

    result = addons.Install(manifestUrl)
    Harness_Ok(not result.ok, "duplicate install refused")
    Harness_Equal(result.error, "addon already installed", "error names the duplicate")
    Harness_Equal(addons.transport.log.Count(), 2, "manifest fetched both times, refused after")
    Harness_Equal(addons.GetAll().Count(), 3, "still just built-ins plus the first install")
end sub

sub Test_Addons_InstallNoAddress()
    Harness_Suite("AddonsStore.Install refuses without an address")
    addons = AddonsStore(ScriptedTransport([]), invalid)
    result = addons.Install("")

    Harness_Ok(not result.ok, "install rejected")
    Harness_Equal(result.error, "no addon address", "error names the missing address")
end sub

sub Test_Addons_Uninstall()
    Harness_Suite("AddonsStore.Uninstall removes an installed add-on")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    addons.Install(manifestUrl)

    Harness_Ok(addons.Uninstall("com.example.addon"), "uninstall ok")
    Harness_Equal(addons.GetAll().Count(), 2, "back to built-ins")
    Harness_Ok(not addons.Uninstall("com.example.addon"), "second uninstall fails")
end sub

sub Test_Addons_PersistsViaRegistry()
    Harness_Suite("AddonsStore round-trips through the registry")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)
    addons.Install(manifestUrl)

    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Ok(reopened.Get("com.example.addon") <> invalid, "installed add-on reloaded")
    Harness_Equal(reopened.Get("com.example.addon").address, "https://addon.example.com", "address reloaded")
end sub

sub Test_Addons_CatalogsFlatten()
    Harness_Suite("AddonsStore.Catalogs flattens advertised catalogs")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    addons.Install(manifestUrl)
    catalogs = addons.Catalogs()

    Harness_Equal(catalogs.Count(), 2, "two catalogs advertised")
    Harness_Equal(catalogs[0].addonId, "com.example.addon", "catalog carries the add-on id")
    Harness_Equal(catalogs[0].type, "movie", "catalog type propagated")
    Harness_Equal(catalogs[0].catalogId, "top", "catalog id propagated")
end sub