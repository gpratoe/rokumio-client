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
    transport.Post = function(url as string, body = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respond("POST", url, body)
    end function
    transport.PostLong = function(url as string, body = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respond("POST", url, body)
    end function
    return transport
end function