' AuthStore.brs
'
' A single point of truth for the Stremio account session: the auth key, the
' pending link-pairing state (code + URL), registry persistence, and the
' network round-trips that create / read the link pairing.
'
' MainScene still owns the SceneGraph Timer (linkPollTimer) and the dialog
' nodes because the store intentionally knows nothing about the view layer.
' It returns request specs for MainScene to fire through the shared HTTP
' transport, and it accepts raw responses back via the handle* methods.

function CreateAuthStore() as object
    store = {
        _authKey: ""
        _linkCode: ""
        _linkUrl: ""
    }

    ' --- state accessors ------------------------------------------------------

    store.getAuthKey = function() as string
        return m._authKey
    end function

    store.isSignedIn = function() as boolean
        return m._authKey <> ""
    end function

    store.hasActiveLink = function() as boolean
        return m._linkCode <> ""
    end function

    store.getLinkUrl = function() as string
        return m._linkUrl
    end function

    store.getLinkCode = function() as string
        return m._linkCode
    end function

    ' --- lifecycle ------------------------------------------------------------

    ' Read the persisted auth key from the registry. Returns the key so
    ' MainScene can decide whether to FetchLibrary immediately.
    store.load = function() as string
        section = CreateObject("roRegistrySection", "Rokumio")
        if section.Exists("stremioAuthKey")
            m._authKey = section.Read("stremioAuthKey")
        end if
        return m._authKey
    end function

    ' Persist a newly obtained auth key to the registry and into the store.
    store.save = function(authKey as string)
        section = CreateObject("roRegistrySection", "Rokumio")
        section.Write("stremioAuthKey", authKey)
        section.Flush()
        m._authKey = authKey
    end function

    ' Wipe the persisted auth key and reset all auth state. Called on
    ' disconnect.
    store.clear = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        section.Delete("stremioAuthKey")
        section.Flush()
        m._authKey = ""
        m._linkCode = ""
        m._linkUrl = ""
    end function

    ' --- network: create a link pairing ---------------------------------------

    store.buildLinkCreate = function() as object
        return {
            url: "https://link.stremio.com/api/v2/create?type=Create"
            id: "linkCreate|stremio"
        }
    end function

    ' Process the create response. Returns { success, message }.
    ' On success the store remembers the code + URL for the poll phase.
    store.handleLinkCreateResponse = function(data as dynamic) as object
        if data = invalid or data.DoesExist("error") or not data.DoesExist("result")
            return { success: false, message: TrText("status.link.createFailed") }
        end if

        result = data.result
        code = SafeString(result, "code")
        link = SafeString(result, "link")
        if code = "" or link = ""
            return { success: false, message: TrText("status.link.incomplete") }
        end if

        m._linkCode = code
        m._linkUrl = link
        return { success: true, message: "" }
    end function

    ' --- network: poll the link pairing ---------------------------------------

    store.buildLinkRead = function() as object
        return {
            url: "https://link.stremio.com/api/v2/read?type=Read&code=" + m._linkCode
            id: "linkRead|stremio"
        }
    end function

    ' Process the poll response. Returns the authKey string when the user
    ' completed pairing, or "" if pairing is still pending. Persists the
    ' key on success.
    store.handleLinkReadResponse = function(data as dynamic) as string
        if data = invalid or data.DoesExist("error") or not data.DoesExist("result") then return ""
        authKey = SafeString(data.result, "authKey")
        if authKey = "" then return ""

        m.save(authKey)
        m._linkCode = ""
        m._linkUrl = ""
        return authKey
    end function

    ' --- pairing lifecycle (called from MainScene) ----------------------------

    ' Cancel an in-progress pairing attempt (e.g. user presses Cancel on the
    ' link dialog). Returns true when there was something to cancel.
    store.cancelLink = function() as boolean
        if m._linkCode = "" then return false
        m._linkCode = ""
        m._linkUrl = ""
        return true
    end function

    ' Clear all auth state (registry + in-memory) and signal disconnection.
    store.disconnect = function()
        m.clear()
    end function

    return store
end function
