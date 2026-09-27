' Shared test doubles for the store suites.
'
' MockRegistry mirrors the roRegistrySection surface (Read/Write/Flush) so
' persistence is testable in the interpreter. ScriptedTransport serves both
' Get and Post from a script of pre-parsed transport results, matching on HTTP
' method + URL (a blank method or url in an entry matches anything), and logs
' every request made. Suites assert against the log and inject via the script.

function MockRegistry() as object
    registry = { values: {} }
    registry.Read = function(key as string) as string
        if m.values[key] <> invalid then return m.values[key]
        return ""
    end function
    registry.Write = function(key as string, value as string)
        m.values[key] = value
    end function
    registry.Flush = function() as void
    end function
    return registry
end function

function ScriptedTransport(script as object) as object
    transport = { _script: script, log: [] }
    transport._respond = function(method as string, url as string, body as dynamic) as object
        for each entry in m._script
            if (entry.method = invalid or entry.method = method) and (entry.url = invalid or entry.url = url)
                m.log.Push({ method: method, url: url, body: body })
                return { ok: entry.ok, status: entry.status, json: entry.json, error: entry.error }
            end if
        end for
        m.log.Push({ method: method, url: url, body: body })
        return { ok: false, status: 0, json: invalid, error: "no scripted response" }
    end function
    transport.Get = function(url as string, headers = invalid as dynamic) as object
        return m._respond("GET", url, invalid)
    end function
    ' The raw twin of _respond: the body comes back as text rather than as parsed
    ' json, which is the shape Transport.GetRaw speaks. An entry that scripts no
    ' `body` yields an empty one rather than a fabricated body.
    transport._respondRaw = function(method as string, url as string) as object
        for each entry in m._script
            if (entry.method = invalid or entry.method = method) and (entry.url = invalid or entry.url = url)
                m.log.Push({ method: method, url: url, body: entry.body })
                return { ok: entry.ok, status: entry.status, body: entry.body, error: entry.error }
            end if
        end for
        m.log.Push({ method: method, url: url, body: invalid })
        return { ok: false, status: 0, body: invalid, error: "no scripted response" }
    end function
    ' timeoutMs is accepted and ignored, matching Transport.GetRaw's signature.
    ' A mock that declared one parameter and was called with two is how a seam
    ' starts lying about what the real client accepts.
    transport.GetRaw = function(url as string, timeoutMs = invalid as dynamic) as object
        return m._respondRaw("GET", url)
    end function
    transport.Post = function(url as string, body = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respond("POST", url, body)
    end function
    transport.PostLong = function(url as string, body = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respond("POST", url, body)
    end function
    transport.EndpointUrl = function(storedAddress as string, endpointPath as string) as string
        at = storedAddress.InStr("?")
        if at < 0 then return storedAddress + endpointPath
        return storedAddress.Left(at) + endpointPath + storedAddress.Mid(at)
    end function
    ' Forwards to the real implementation in Transport.bs rather than repeating
    ' it. A copy here would let the suite assert an encoding the device never
    ' produces, which is precisely the failure this file exists to prevent.
    transport.UrlEncode = function(value as string) as string
        return PercentEncode(value)
    end function
    return transport
end function