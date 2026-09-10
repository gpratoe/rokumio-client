' AddonsInstallTask — fetch + install an add-on manifest off the UI thread.
' The manifest fetch rides Transport's default request timeout (REQUEST_TIMEOUT_MS,
' 15s), so a hung add-on costs the worker thread, not a frozen channel. The task
' builds its own store inside the task scope — no object created on the render
' thread crosses the thread boundary. The task's store has no registry (a fresh,
' in-memory instance), so it only validates and fetches; the WORK is returned as
' the installed record and the AddonsScreen applies it to the real store.
sub init()
    m.top.functionName = "install"
end sub

sub install()
    print "[rokumio] AddonsInstallTask starting"
    try
        http = Transport()
        store = AddonsStore(http)
        result = store.Install(m.top.address)
        record = invalid
        if result.ok and result.id <> invalid and result.id <> ""
            record = store.Get(result.id)
        end if
        print "[rokumio] AddonsInstallTask ok=" + result.ok.ToStr() + " id='" + result.id + "' error='" + result.error + "'"
        m.top.result = {
            ok: result.ok
            id: result.id
            error: result.error
            record: record
        }
    catch e
        print "[rokumio] AddonsInstallTask error: " + e.message
        m.top.result = { ok: false, id: "", error: e.message, record: invalid }
    end try
end sub