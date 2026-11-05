' DirectPlayCapsTask — one read-only snapshot of Roku's decoder answers while
' the stream picker loads. The shared CodecProbe helpers are also used when
' StreamResolveTask builds the codec hints sent to the streaming server.
sub init()
    m.top.functionName = "probeDirectPlayCapabilities"
end sub

sub probeDirectPlayCapabilities()
    report = { done: false, available: false, video: [], audio: [] }
    di = invalid
    try
        di = CreateObject("roDeviceInfo")
    catch e
        di = invalid
    end try

    if di <> invalid
        report.available = true
        for each candidate in CodecVideoCandidates()
            if m.top.state = "stop" then return
            report.video.Push(CodecProbeVideo(di, candidate, false))
        end for
        for each candidate in CodecAudioCandidates()
            if m.top.state = "stop" then return
            report.audio.Push(CodecProbeAudio(di, candidate))
        end for
    end if

    report.done = true
    m.top.result = report
end sub
