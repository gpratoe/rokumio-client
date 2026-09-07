' AddonsStore unit tests.
'
' Cinemeta and OpenSubtitles v3 are built-in (Stremio official, protected).
' Everything else installs by fetching {address}/manifest.json through the
' scripted transport; installed records persist through the mock registry.

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
end sub

sub Test_Addons_BuiltInsProtected()
    Harness_Suite("AddonsStore refuses to uninstall built-ins")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Ok(not addons.Uninstall("com.linvo.cinemeta"), "cannot uninstall cinemeta")
    Harness_Equal(addons.GetAll().Count(), 2, "both built-ins remain")
end sub

sub Test_Addons_Install()
    Harness_Suite("AddonsStore.Install fetches the manifest and stores the add-on")
    address = "https://addon.example.com"
    script = [
        { method: "GET", url: address + "/manifest.json", ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(address)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(result.id, "com.example.addon", "returns the manifest id")
    record = addons.Get("com.example.addon")
    Harness_Equal(record.name, "Example", "name stored")
    Harness_Equal(record.address, address, "address stored")
    Harness_Equal(record.builtin, false, "installed add-on not builtin")
    Harness_Equal(addons.GetAll().Count(), 3, "built-ins plus the new one")
end sub

sub Test_Addons_RejectsInvalidManifest()
    Harness_Suite("AddonsStore.Install rejects a manifest without id/name")
    script = [
        { method: "GET", ok: true, status: 200, json: { name: "Missing id" }, error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install("https://addon.example.com")

    Harness_Ok(not result.ok, "install rejected")
    Harness_Equal(result.error, "manifest missing id or name", "error names the missing field")
    Harness_Equal(addons.GetAll().Count(), 2, "nothing installed")
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
    address = "https://addon.example.com"
    script = [
        { method: "GET", url: address + "/manifest.json", ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    addons.Install(address)

    Harness_Ok(addons.Uninstall("com.example.addon"), "uninstall ok")
    Harness_Equal(addons.GetAll().Count(), 2, "back to built-ins")
    Harness_Ok(not addons.Uninstall("com.example.addon"), "second uninstall fails")
end sub

sub Test_Addons_PersistsViaRegistry()
    Harness_Suite("AddonsStore round-trips through the registry")
    address = "https://addon.example.com"
    script = [
        { method: "GET", url: address + "/manifest.json", ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)
    addons.Install(address)

    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Ok(reopened.Get("com.example.addon") <> invalid, "installed add-on reloaded")
    Harness_Equal(reopened.Get("com.example.addon").address, address, "address reloaded")
end sub

sub Test_Addons_CatalogsFlatten()
    Harness_Suite("AddonsStore.Catalogs flattens advertised catalogs")
    address = "https://addon.example.com"
    script = [
        { method: "GET", url: address + "/manifest.json", ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    addons.Install(address)
    catalogs = addons.Catalogs()

    Harness_Equal(catalogs.Count(), 2, "two catalogs advertised")
    Harness_Equal(catalogs[0].addonId, "com.example.addon", "catalog carries the add-on id")
    Harness_Equal(catalogs[0].type, "movie", "catalog type propagated")
    Harness_Equal(catalogs[0].catalogId, "top", "catalog id propagated")
end sub