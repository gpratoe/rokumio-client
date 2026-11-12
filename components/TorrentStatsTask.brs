' Poll the stock Stremio server's per-engine statistics away from the render
' thread. The endpoint is the same one the official clients consume:
'   /{infoHash}/stats.json
' It reports byte/second rates plus the current number of connected peers.
sub init()
    m.top.functionName = "poll"
end sub

sub poll()
    address = m.top.serverAddress
    hash = LCase(m.top.infoHash)
    if address = "" or hash = "" then return
    while Right(address, 1) = "/"
        address = Left(address, address.Len() - 1)
    end while
    url = address + "/" + hash + "/stats.json"
    http = Transport()

    while m.top.state <> "stop"
        try
            ' A local stats read must never inherit the ordinary 15-second API
            ' wait. If it misses one sample, the next second tries again.
            response = http.GetRaw(url, 2000)
            if response.ok and response.body <> ""
                value = ParseJson(response.body)
                if value <> invalid
                    peers = 0
                    down = 0
                    up = 0
                    if value.peers <> invalid then peers = value.peers
                    if value.downloadSpeed <> invalid then down = value.downloadSpeed
                    if value.uploadSpeed <> invalid then up = value.uploadSpeed
                    m.top.stats = {
                        peers: peers
                        downloadSpeed: down
                        uploadSpeed: up
                    }
                end if
            end if
        catch e
            ' Telemetry is decoration. A malformed or temporarily unavailable
            ' stats response must never delay or fail the stream itself.
        end try

        ' Short slices make STOP responsive even though the public cadence is
        ' one sample per second.
        for i = 0 to 7
            if m.top.state = "stop" then return
            Wait(125, invalid)
        end for
    end while
end sub
