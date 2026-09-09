' SettingsStore unit tests.
'
' MockRegistry is shared with the other store suites (tests/mocks.brs):
' persistence is testable in the interpreter, and constructing a second store
' over the same registry must restore the saved state — that is Load().

sub Test_Settings_Defaults()
    Harness_Suite("SettingsStore defaults")
    settings = SettingsStore(invalid)

    Harness_Equal(settings.ServerAddressSet(), false, "no server address by default")
    Harness_Equal(settings.GetUiScale(), 100, "uiScale defaults to 100")
    Harness_Equal(settings.GetLanguage(), "en", "language defaults to en")
end sub

sub Test_Settings_SetServerAddress()
    Harness_Suite("SettingsStore.SetServerAddress validates and normalizes")
    settings = SettingsStore(invalid)

    Harness_Ok(settings.SetServerAddress("http://10.0.0.2:4141/"), "accepts http host + port")
    Harness_Equal(settings.GetServerAddress(), "http://10.0.0.2:4141", "strips a trailing slash")
    Harness_Ok(settings.SetServerAddress("https://addon.example.com"), "accepts https host")
    Harness_Ok(settings.SetServerAddress("http://host/base/path"), "accepts a path prefix")

    Harness_Ok(not settings.SetServerAddress(""), "rejects empty")
    Harness_Ok(not settings.SetServerAddress("host:4141"), "rejects a missing scheme")
    Harness_Ok(not settings.SetServerAddress("ftp://host"), "rejects a non-http(s) scheme")
    Harness_Ok(not settings.SetServerAddress("http://host:41xx"), "rejects a non-digit port")
    Harness_Equal(settings.GetServerAddress(), "http://host/base/path", "failed attempts leave the address unchanged")
end sub

sub Test_Settings_UiScaleBounds()
    Harness_Suite("SettingsStore.SetUiScale bounds")
    settings = SettingsStore(invalid)

    Harness_Ok(settings.SetUiScale(200), "accepts 200")
    Harness_Ok(not settings.SetUiScale(-1), "rejects negative")
    Harness_Ok(not settings.SetUiScale(201), "rejects >200")
    Harness_Equal(settings.GetUiScale(), 200, "only the accepted value took")
end sub

sub Test_Settings_ClearServerAddress()
    Harness_Suite("SettingsStore.ClearServerAddress blanks and persists")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    settings.SetServerAddress("http://10.0.0.2:4141")
    settings.ClearServerAddress()

    Harness_Equal(settings.GetServerAddress(), "", "address blanked")
    Harness_Equal(settings.ServerAddressSet(), false, "no longer set")

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "", "blank persisted")
end sub

sub Test_Settings_PersistsViaRegistry()
    Harness_Suite("SettingsStore round-trips through the registry")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    settings.SetServerAddress("http://192.168.1.5:4141")
    settings.SetUiScale(90)
    settings.SetLanguage("es")
    settings.Save()

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "http://192.168.1.5:4141", "address reloaded")
    Harness_Equal(reopened.GetUiScale(), 90, "uiScale reloaded")
    Harness_Equal(reopened.GetLanguage(), "es", "language reloaded")
end sub

sub Test_Settings_InMemoryOnlyWithoutRegistry()
    Harness_Suite("SettingsStore without a registry is in-memory only")
    settings = SettingsStore(invalid)
    settings.SetServerAddress("http://192.168.1.5:4141")
    settings.Save()

    Harness_Equal(SettingsStore(invalid).GetServerAddress(), "", "nothing persisted without a registry")
end sub