' SettingsStore unit tests.
'
' MockRegistry is shared with the other store suites (tests/mocks.brs):
' persistence is testable in the interpreter, and constructing a second store
' over the same registry must restore the saved state — that is Load().

sub Test_Settings_Defaults()
    Harness_Suite("SettingsStore defaults")
    settings = SettingsStore(invalid)

    Harness_Equal(settings.ServerAddressSet(), false, "no server address by default")
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

' The setters persist themselves, so no Save() call appears anywhere below. That
' is the point of the suite: the ECP import path set the server address and
' omitted the save, which no existing test could see, because the one test that
' checked persistence made the Save() call itself.
sub Test_Settings_SettersPersistWithoutAnExplicitSave()
    Harness_Suite("SettingsStore setters persist on their own")
    registry = MockRegistry()
    settings = SettingsStore(registry)

    Harness_Ok(settings.SetServerAddress("http://192.168.1.5:4141"), "address accepted")
    Harness_Ok(settings.SetLanguage("es"), "language accepted")

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "http://192.168.1.5:4141", "address reloaded with no Save() call")
    Harness_Equal(reopened.GetLanguage(), "es", "language reloaded with no Save() call")
end sub

' roRegistrySection.Write answers with a boolean, and the answer used to be
' discarded — so a refused write flushed nothing and reverted on the next
' launch with nothing recording that it had been refused.
sub Test_Settings_ReportsARefusedWrite()
    Harness_Suite("SettingsStore reports a write the registry refuses")
    registry = MockRegistry()
    registry.failWrites = true
    settings = SettingsStore(registry)

    Harness_Ok(settings.SetServerAddress("http://192.168.1.5:4141"), "the value is still set in memory")
    Harness_Ok(settings.SaveFailed(), "the refused write is reported")
    Harness_Equal(SettingsStore(registry).GetServerAddress(), "", "and nothing reached the registry")

    registry.failWrites = false
    Harness_Ok(settings.SetServerAddress("http://192.168.1.5:4141"), "a retry still sets the value")
    Harness_Ok(not settings.SaveFailed(), "and the failure clears itself once a write lands")
    Harness_Equal(SettingsStore(registry).GetServerAddress(), "http://192.168.1.5:4141", "the retry persisted")
end sub

' A missing registry is the in-memory-only mode, not a write that failed.
sub Test_Settings_NoRegistryIsNotAFailedWrite()
    Harness_Suite("SettingsStore without a registry does not report a failure")
    settings = SettingsStore(invalid)
    settings.SetServerAddress("http://192.168.1.5:4141")
    Harness_Ok(not settings.SaveFailed(), "nowhere to write is not the same as a refused write")
end sub

sub Test_Settings_PersistsViaRegistry()
    Harness_Suite("SettingsStore round-trips through the registry")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    settings.SetServerAddress("http://192.168.1.5:4141")
    settings.SetLanguage("es")
    settings.Save()

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "http://192.168.1.5:4141", "address reloaded")
    Harness_Equal(reopened.GetLanguage(), "es", "language reloaded")
end sub

sub Test_Settings_InMemoryOnlyWithoutRegistry()
    Harness_Suite("SettingsStore without a registry is in-memory only")
    settings = SettingsStore(invalid)
    settings.SetServerAddress("http://192.168.1.5:4141")
    settings.Save()

    Harness_Equal(SettingsStore(invalid).GetServerAddress(), "", "nothing persisted without a registry")
end sub

' The audio passthrough switch. Off by default — the device reports AC-3 and
' some sinks do not reproduce it, so it is the user's call, not the device's.
sub Test_Settings_AudioPassthrough()
    Harness_Suite("SettingsStore audio passthrough")
    registry = MockRegistry()
    settings = SettingsStore(registry)

    Harness_Equal(settings.GetAudioPassthrough(), false, "off by default")

    settings.SetAudioPassthrough(true)
    Harness_Equal(settings.GetAudioPassthrough(), true, "turned on")

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetAudioPassthrough(), true, "persisted across a reopen")

    settings.SetAudioPassthrough(false)
    Harness_Equal(SettingsStore(registry).GetAudioPassthrough(), false, "and off again persists too")
end sub

' The registry keeps strings, so the flag goes out as text. Only an explicit
' "true" turns it on: a missing key, or anything else, leaves the default.
sub Test_Settings_AudioPassthroughReadsOnlyTrue()
    Harness_Suite("SettingsStore audio passthrough only turns on for true")
    registry = MockRegistry()
    registry.values["audioPassthrough"] = "false"
    Harness_Equal(SettingsStore(registry).GetAudioPassthrough(), false, "false leaves it off")

    registry.values["audioPassthrough"] = "true"
    Harness_Equal(SettingsStore(registry).GetAudioPassthrough(), true, "true turns it on")

    registry.values["audioPassthrough"] = "yes"
    Harness_Equal(SettingsStore(registry).GetAudioPassthrough(), false, "anything else leaves it off")
end sub

' The transmux flag is a second, separate setting: the server copies the audio
' so that THIS ROKU decodes it, rather than the sound system. It has its own
' key so that turning one does not turn the other.
sub Test_Settings_AudioTransmuxIsItsOwnSetting()
    Harness_Suite("SettingsStore audio transmux is separate")
    registry = MockRegistry()
    settings = SettingsStore(registry)

    Harness_Equal(settings.GetAudioTransmux(), false, "off by default")

    settings.SetAudioTransmux(true)
    Harness_Equal(settings.GetAudioTransmux(), true, "turned on")
    Harness_Equal(settings.GetAudioPassthrough(), false, "and the passthrough is untouched")

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetAudioTransmux(), true, "persisted across a reopen")
    Harness_Equal(reopened.GetAudioPassthrough(), false, "and the passthrough is still off")
end sub

' Direct play is a three-state mode, deactivated by default: nothing about
' torrent playback changes until the user opts in. An unknown stored value
' must never turn an experimental feature on.
sub Test_Settings_DirectPlay()
    Harness_Suite("SettingsStore direct play mode")
    registry = MockRegistry()
    settings = SettingsStore(registry)

    Harness_Equal(settings.GetDirectPlayMode(), "off", "deactivated by default")

    Harness_Ok(settings.SetDirectPlayMode("on"), "on is accepted")
    Harness_Equal(settings.GetDirectPlayMode(), "on", "turned on")
    Harness_Equal(SettingsStore(registry).GetDirectPlayMode(), "on", "persisted across a reopen")

    Harness_Ok(settings.SetDirectPlayMode("off"), "off is accepted")
    Harness_Equal(SettingsStore(registry).GetDirectPlayMode(), "off", "off persists too")
    Harness_Ok(not settings.SetDirectPlayMode("always"), "an unknown mode is rejected")
    Harness_Equal(settings.GetDirectPlayMode(), "off", "and leaves the stored mode alone")
end sub

sub Test_Settings_DirectPlayMigratesOldBoolean()
    Harness_Suite("SettingsStore direct play migrates the old boolean")
    registry = MockRegistry()
    registry.values["directPlay"] = "false"
    Harness_Equal(SettingsStore(registry).GetDirectPlayMode(), "off", "the old false reads as off")

    registry.values["directPlay"] = "true"
    Harness_Equal(SettingsStore(registry).GetDirectPlayMode(), "on", "the old true reads as on")

    registry.values["directPlay"] = "yes"
    Harness_Equal(SettingsStore(registry).GetDirectPlayMode(), "off", "anything else falls to the default")
end sub

sub Test_Settings_HomeCatalogVisibilityPersists()
    Harness_Suite("SettingsStore hides Home catalogs by stable identity")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    address = "https://catalog.example/addon?token=a|b"

    Harness_Ok(settings.IsHomeCatalogVisible(address, "movie", "top"), "catalogs are visible by default")
    Harness_Ok(settings.SetHomeCatalogVisible(address, "movie", "top", false), "catalog can be hidden")
    Harness_Ok(not settings.IsHomeCatalogVisible(address, "movie", "top"), "hidden state applies to the exact catalog")
    Harness_Ok(settings.IsHomeCatalogVisible(address, "series", "top"), "the other content type stays visible")
    Harness_Ok(settings.IsHomeCatalogVisible("https://catalog.example/addon", "movie", "top"), "similar addresses do not collide")

    reopened = SettingsStore(registry)
    Harness_Ok(not reopened.IsHomeCatalogVisible(address, "movie", "top"), "hidden state survives reopening")
    Harness_Equal(reopened.GetHiddenHomeCatalogs().Count(), 1, "one exclusion is persisted")

    Harness_Ok(reopened.SetHomeCatalogVisible(address, "movie", "top", true), "catalog can be shown again")
    Harness_Ok(SettingsStore(registry).IsHomeCatalogVisible(address, "movie", "top"), "showing it removes the exclusion")
end sub

sub Test_Settings_HomeCatalogVisibilityRejectsInvalidIdentity()
    Harness_Suite("SettingsStore rejects incomplete Home catalog identities")
    settings = SettingsStore(invalid)
    Harness_Ok(not settings.SetHomeCatalogVisible("", "movie", "top", false), "missing add-on address is rejected")
    Harness_Ok(not settings.SetHomeCatalogVisible("https://catalog.example", "", "top", false), "missing type is rejected")
    Harness_Ok(not settings.SetHomeCatalogVisible("https://catalog.example", "movie", "", false), "missing catalog id is rejected")
    Harness_Equal(settings.GetHiddenHomeCatalogs().Count(), 0, "invalid identities do not alter state")
end sub
