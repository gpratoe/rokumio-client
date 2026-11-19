' AuthStore persistence + stremio-session tests.
'
' AuthStore is registry-backed like the other stores: guest and stremio sessions
' survive relaunches through the "session" key, and books are kept on device.
' Guest login stays purely local (no transport anywhere) — signing in still
' makes zero network calls.

sub Test_Auth_GuestPersistsAcrossReload()
    Harness_Suite("AuthStore persists a guest session across reloads")
    registry = MockRegistry()
    first = AuthStore(registry)
    result = first.LoginGuest()
    Harness_Ok(result.saved, "guest login persisted")

    second = AuthStore(registry)
    Harness_Ok(second.IsLoggedIn(), "session restored")
    Harness_Equal(second.GetSession(), "guest", "guest session restored")
end sub

sub Test_Auth_LoginStremio()
    Harness_Suite("AuthStore.LoginStremio records the account session")
    auth = AuthStore()
    user = { _id: "u123", email: "x@example.com" }
    result = auth.LoginStremio("authKey123", user)

    Harness_Ok(result.ok, "login ok")
    Harness_Ok(result.saved, "login persisted in memory-only mode")
    Harness_Equal(auth.GetSession(), "stremio", "stremio session set")
    Harness_Equal(auth.GetAuthKey(), "authKey123", "auth key stored")
    Harness_Equal(auth.GetUser().email, "x@example.com", "user profile stored")
end sub

sub Test_Auth_StremioPersistsAcrossReload()
    Harness_Suite("AuthStore persists the stremio session across reloads")
    registry = MockRegistry()
    first = AuthStore(registry)
    result = first.LoginStremio("authKey123", { _id: "u123", email: "x@example.com" })
    Harness_Ok(result.saved, "stremio login persisted")

    second = AuthStore(registry)
    Harness_Equal(second.GetSession(), "stremio", "stremio session restored")
    Harness_Equal(second.GetAuthKey(), "authKey123", "auth key restored")
    Harness_Equal(second.GetUser().email, "x@example.com", "user profile restored")
    Harness_Equal(second.GetUser()._id, "u123", "user id restored")
end sub

sub Test_Auth_PersistsSanitizedUserOnly()
    Harness_Suite("AuthStore persists only the needed user fields")
    registry = MockRegistry()
    first = AuthStore(registry)
    richUser = {
        _id: "u123"
        email: "x@example.com"
        fbId: "fb"
        fullname: "Full Name"
        avatar: "http://avatar"
        anonymous: false
        gdpr_consent: { marketing: false, privacy: true, tos: true }
        premiumPrefs: { userProfiles: { u123: { name: "Master Profile", hasPin: false } } }
        features: { profiles: 1, catalogWeights: false }
        trakt: { access_token: "secret", refresh_token: "secret2", expires_in: 604800 }
        taste: invalid
        stremio_addons: ""
    }
    result = first.LoginStremio("authKey123", richUser)
    Harness_Ok(result.saved, "stremio login persisted")
    Harness_Equal(first.GetUser().email, "x@example.com", "full user kept in memory for the session")

    raw = registry.Read("session")
    parsed = ParseJson(raw)
    Harness_Ok(parsed <> invalid, "stored session is valid json")
    Harness_Equal(parsed.user.email, "x@example.com", "email persisted")
    Harness_Equal(parsed.user._id, "u123", "id persisted")
    Harness_Ok(parsed.user.trakt = invalid, "trakt data not persisted")
    Harness_Ok(parsed.user.premiumPrefs = invalid, "premium prefs not persisted")
    Harness_Ok(parsed.user.features = invalid, "features not persisted")
    Harness_Ok(parsed.user.gdpr_consent = invalid, "gdpr consent not persisted")
    Harness_Ok(parsed.user.fbId = invalid, "extra profile fields not persisted")

    second = AuthStore(registry)
    Harness_Equal(second.GetUser().email, "x@example.com", "sanitized user restored")
    Harness_Ok(second.GetUser().trakt = invalid, "no trakt data after reload")
end sub

sub Test_Auth_LogoutClearsPersisted()
    Harness_Suite("AuthStore.Logout clears the persisted session")
    registry = MockRegistry()
    first = AuthStore(registry)
    first.LoginStremio("authKey123", { _id: "u123" })

    saved = first.Logout()
    Harness_Ok(saved, "logout persisted")
    Harness_Ok(not first.IsLoggedIn(), "logged out in memory")
    Harness_Equal(first.GetAuthKey(), "", "auth key cleared")

    second = AuthStore(registry)
    Harness_Ok(not second.IsLoggedIn(), "reload still sees logged out")
    Harness_Equal(second.GetSession(), "", "no session leaks after logout")
end sub

sub Test_Auth_LoginGuestClearsStremioData()
    Harness_Suite("AuthStore.LoginGuest drops any previous account data")
    auth = AuthStore()
    auth.LoginStremio("authKey123", { _id: "u123" })
    result = auth.LoginGuest()

    Harness_Ok(result.saved, "guest login persisted in memory-only mode")
    Harness_Equal(auth.GetSession(), "guest", "guest session set")
    Harness_Equal(auth.GetAuthKey(), "", "auth key cleared")
    Harness_Ok(auth.GetUser() = invalid, "user profile cleared")
end sub

sub Test_Auth_ReportsRefusedWrite()
    Harness_Suite("AuthStore reports a write the registry refuses")
    registry = MockRegistry()
    registry.failWrites = true
    auth = AuthStore(registry)

    result = auth.LoginStremio("authKey123", { _id: "u123", email: "x@example.com" })
    Harness_Ok(result.ok, "login still applied in memory")
    Harness_Ok(not result.saved, "login reports persistence failure")
    Harness_Ok(auth.SaveFailed(), "save failure is reported")
    Harness_Equal(auth.SaveFailureReason(), "write", "failure reason identifies a write refusal")
    Harness_Ok(auth.IsLoggedIn(), "session remains active in memory")
    Harness_Ok(not AuthStore(registry).IsLoggedIn(), "and nothing reached the registry")

    registry.failWrites = false
    guest = auth.LoginGuest()
    Harness_Ok(guest.saved, "a later successful save clears the failure")
    Harness_Ok(not auth.SaveFailed(), "save failure cleared after success")
    Harness_Equal(auth.SaveFailureReason(), "", "failure reason cleared after success")
    Harness_Equal(AuthStore(registry).GetSession(), "guest", "successful save persisted")
end sub

sub Test_Auth_NoRegistryIsNotAFailedWrite()
    Harness_Suite("AuthStore without a registry does not report a failure")
    auth = AuthStore(invalid)
    result = auth.LoginGuest()
    Harness_Ok(result.saved, "in-memory mode is treated as saved")
    Harness_Ok(not auth.SaveFailed(), "nowhere to write is not a refused write")
    Harness_Equal(auth.SaveFailureReason(), "", "no failure reason in memory-only mode")
    logoutSaved = auth.Logout()
    Harness_Ok(logoutSaved, "logout in memory-only mode succeeds")
end sub