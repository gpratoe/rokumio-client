' Transport unit tests.
'
' A fake client stands in for roUrlTransfer: it records every call and answers
' from a small script of { ok, status, body, error } rows, keyed by method and
' optional URL. Transport's own job — forwarding method/url/headers/body to the
' client and normalizing raw results into parsed JSON — is what we lock down
' here. The real client is a thin roUrlTransfer wrapper and is never exercised
' in the interpreter.

function ScriptedHttpClient(script as object, log as object) as object
    client = { _script: script, _log: log }
    client.request = function(method as string, url as string, headers = invalid as dynamic, body = invalid as dynamic) as object
        m._log.Push({ method: method, url: url, headers: headers, body: body })
        for each entry in m._script
            if entry.method = method and (entry.url = invalid or entry.url = url)
                return { ok: entry.ok, status: entry.status, body: entry.body, error: entry.error }
            end if
        end for
        return { ok: false, status: 0, body: "", error: "no scripted response" }
    end function
    client.requestLong = function(method as string, url as string, headers = invalid as dynamic, body = invalid as dynamic) as object
        return m.request(method, url, headers, body)
    end function
    return client
end function

' BrightScript strings cannot embed a literal double-quote, so JSON bodies for
' the fake client are assembled with Chr(34). The raw string is what Transport
' hands to ParseJson, which is exactly the code path under test.
function QuoteString(value as string) as string
    return Chr(34) + value + Chr(34)
end function

sub Test_Transport_Get_ParsesJson()
    Harness_Suite("Transport.Get parses JSON and forwards to the client")
    log = []
    body = "{" + QuoteString("ok") + ":true," + QuoteString("n") + ":3}"
    script = [
        { method: "GET", url: "http://host/health", ok: true, status: 200, body: body, error: "" }
    ]
    transport = Transport(ScriptedHttpClient(script, log))
    result = transport.Get("http://host/health", { "Accept": "application/json" })

    Harness_Ok(result.ok, "ok=true for 200 with JSON")
    Harness_Equal(result.status, 200, "status surfaced")
    Harness_Equal(result.json.ok, true, "json bool parsed")
    Harness_Equal(result.json.n, 3, "json number parsed")
    Harness_Equal(log.Count(), 1, "client called once")
    Harness_Equal(log[0].method, "GET", "method forwarded")
    Harness_Equal(log[0].url, "http://host/health", "url forwarded")
    Harness_Equal(log[0].headers.Accept, "application/json", "headers forwarded")
end sub

sub Test_Transport_RejectsBadJson()
    Harness_Suite("Transport flags a 2xx with a non-JSON body as a failure")
    script = [
        { method: "GET", ok: true, status: 200, body: "not-json", error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, [])).Get("http://host/x")

    Harness_Ok(not result.ok, "ok=false when the body is not JSON")
    Harness_Equal(result.error, "invalid JSON response", "error names the problem")
end sub

sub Test_Transport_HttpError()
    Harness_Suite("Transport surfaces HTTP errors")
    script = [
        { method: "GET", ok: false, status: 500, body: "{}", error: "HTTP 500" }
    ]
    result = Transport(ScriptedHttpClient(script, [])).Get("http://host/x")

    Harness_Ok(not result.ok, "ok=false for a 500")
    Harness_Equal(result.status, 500, "status surfaced")
    Harness_Equal(result.error, "HTTP 500", "error surfaced")
end sub

sub Test_Transport_Post_ForwardsBody()
    Harness_Suite("Transport.Post passes method, url and body to the client")
    log = []
    body = "{" + QuoteString("authKey") + ":" + QuoteString("k1") + "}"
    script = [
        { method: "POST", ok: true, status: 200, body: body, error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, log)).Post("http://host/login", { type: "guest" })

    Harness_Ok(result.ok, "post ok")
    Harness_Equal(result.json.authKey, "k1", "json parsed")
    Harness_Equal(log[0].method, "POST", "method forwarded")
    Harness_Equal(log[0].url, "http://host/login", "url forwarded")
    Harness_Equal(log[0].body.type, "guest", "body forwarded to the client")
end sub

sub Test_Transport_PostLong_RoutesLongRequest()
    Harness_Suite("Transport.PostLong rides the long-window client request")
    log = []
    body = "{" + QuoteString("guessFileIdx") + ":7}"
    script = [
        { method: "POST", ok: true, status: 200, body: body, error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, log)).PostLong("http://host/abc/create", { guessFileIdx: 7 })

    Harness_Ok(result.ok, "postLong ok")
    Harness_Equal(result.json.guessFileIdx, 7, "json parsed")
    Harness_Equal(log[0].method, "POST", "method forwarded")
    Harness_Equal(log[0].url, "http://host/abc/create", "url forwarded")
    Harness_Equal(log[0].body.guessFileIdx, 7, "body forwarded to the client")
end sub