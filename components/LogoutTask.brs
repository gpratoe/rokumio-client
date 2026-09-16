' LogoutTask — best-effort server-side logout of the Stremio session.
'
' One POST /api/logout with {type:"Logout", authKey}. The local logout always
' proceeds regardless of this worker's outcome (server-side cleanup is hygiene,
' not gating), so it fires lazily: MainScene spawns it, logs the result and moves
' on. A blank authKey short-circuits to success — there is nothing to revoke.

sub init()
    m.top.functionName = "logout"
end sub

sub logout()
    if m.top.authKey = invalid or m.top.authKey = ""
        print "[rokumio] LogoutTask nothing to revoke"
        m.top.result = { ok: true, error: "" }
        return
    end if
    print "[rokumio] LogoutTask starting"
    try
        http = Transport()
        res = http.Post("https://api.strem.io/api/logout", { type: "Logout", authKey: m.top.authKey })
        if res.ok and res.json <> invalid
            print "[rokumio] LogoutTask body=" + FormatJson(res.json)
        else
            print "[rokumio] LogoutTask failed ok=" + res.ok.ToStr() + " error='" + res.error + "'"
        end if
        success = false
        if res.ok and res.json <> invalid and res.json.result <> invalid and res.json.result.success = true then success = true
        if success
            print "[rokumio] LogoutTask success"
            m.top.result = { ok: true, error: "" }
            return
        end if
        error = "Could not log out of the account"
        if res.ok and res.json <> invalid and res.json.error <> invalid and res.json.error.message <> invalid
            error = res.json.error.message
        end if
        print "[rokumio] LogoutTask failed: " + error
        m.top.result = { ok: false, error: error }
    catch e
        print "[rokumio] LogoutTask error: " + e.message
        m.top.result = { ok: false, error: e.message }
    end try
end sub