' Codec-hint unit tests — the pure half of source/util/CodecProbe.brs that
' decides WHAT the streaming server is told.
'
' Everything here is the part that could be wrong on every device while looking
' perfectly right in a log: the intersection of the transport's valid codecs with
' the device's answer, the server's floors surviving the replacement rule, and the
' transport flag that keeps every audio candidate but the floor out of a request.
' The roDeviceInfo calls that produce the answers live in
' components/StreamResolveTask.brs (and the spike) and are deliberately not
' exercised: the interpreter has no device, so a test that called CanDecodeVideo
' would only prove the mock agrees with itself.

sub Test_CodecHints_FloorAlwaysPresent()
    Harness_Suite("Codec hints keep the server's floors")

    ' No device answer at all: the request must still carry the codecs the server
    ' would have copied on its own. An advertised list REPLACES the defaults, so a
    ' list that dropped h264/aac/mp3 would turn the service's one sure stream-copy
    ' into a re-encode — and a transcode is a valid response, so nothing would say
    ' so.
    Harness_Equal(CodecJoin(CodecHints(CodecVideoFloor(), CodecVideoCandidates(), []), ","), "h264", "an empty video answer still advertises h264")
    Harness_Equal(CodecJoin(CodecAudioFloor(), ","), "aac,mp3", "an audio list with no switch on still advertises aac and mp3")

    ' The floor also survives an all-no answer, which is the shape a device that
    ' answered every probe with false produces.
    denied = [{ codec: "h264", ok: false }, { codec: "hevc", ok: false }]
    Harness_Equal(CodecJoin(CodecHints(CodecVideoFloor(), CodecVideoCandidates(), denied), ","), "h264", "a rejected h264 is still advertised by the floor")
end sub

sub Test_CodecHints_AddsOnlyCarriableAccepted()
    Harness_Suite("Codec hints add only device-accepted, HLS-carriable codecs")

    ' The trap the Phase 0 run exposed: the test stick answered true for av1 and
    ' vp9, neither of which an HLS stream can carry. Advertising them would force
    ' a remux the player cannot open — a black screen — so an accepted candidate
    ' with hls false must stay out.
    video = [
        { codec: "h264", ok: true },
        { codec: "hevc", ok: true },
        { codec: "av1", ok: true },
        { codec: "vp9", ok: true },
        { codec: "mpeg4", ok: true }
    ]
    Harness_Equal(CodecJoin(CodecHints(CodecVideoFloor(), CodecVideoCandidates(), video), ","), "h264,hevc", "accepted av1/vp9/mpeg4 are not advertised — HLS cannot carry them")

    ' The same on the audio side, but there is no intersection there any more:
    ' the audio list is a switch, not a probe, so the device's answer does not
    ' narrow it. The floor is what the app asks for with the switch off.
    Harness_Equal(CodecJoin(CodecAudioFloor(), ","), "aac,mp3", "the audio floor is aac and mp3")

    ' The switch may only offer the codecs the Roku's own Dolby/DTS passthrough
    ' setting is about: a codec the attached HDMI device never claimed is the
    ' Roku's own to decode, which is the server re-encoding case.
    passthru = []
    for each entry in CodecDolbyCandidates()
        passthru.Push(entry.codec)
    end for
    Harness_Equal(CodecJoin(passthru, ","), "ac3,eac3", "the switch may offer Dolby Digital and Dolby Digital Plus")

    ' And the advertised list is the floor plus what the sink claimed.
    Harness_Equal(CodecJoin(CodecAudioHints(CodecAudioFloor(), []), ","), "aac,mp3", "nothing claimed keeps the floor")
    Harness_Equal(CodecJoin(CodecAudioHints(CodecAudioFloor(), ["ac3", "dts"]), ","), "aac,mp3,ac3,dts", "the claimed codecs are added after the floor")
    Harness_Equal(CodecJoin(CodecAudioHints(CodecAudioFloor(), ["aac", "ac3"]), ","), "aac,mp3,ac3", "a codec already in the floor is not repeated")

    ' An accepted but unadvertised candidate must not appear even when the probe
    ' list is the only source of names.
    only = CodecHints([], CodecVideoCandidates(), [{ codec: "vp9", ok: true }])
    Harness_Equal(CodecJoin(only, ","), "", "nothing is advertised when the only accepted codec is unadvertisable")
end sub

sub Test_CodecHints_OrderAndDuplicates()
    Harness_Suite("Codec hints order and duplicates")

    ' h264 is both the floor and an accepted candidate. It must appear once, and
    ' the floor must come first so a request reads defaults-then-additions.
    video = [{ codec: "h264", ok: true }, { codec: "hevc", ok: true }]
    Harness_Equal(CodecJoin(CodecHints(CodecVideoFloor(), CodecVideoCandidates(), video), ","), "h264,hevc", "the floor is not duplicated by an accepted candidate of the same name")

    ' An accepted codec not present in the candidate list cannot be named — the
    ' list is built from the candidates, so a stray name is simply not there.
    stray = CodecHints([], CodecVideoCandidates(), [{ codec: "theora", ok: true }])
    Harness_Equal(CodecJoin(stray, ","), "", "a name with no candidate entry is not advertised")
end sub

sub Test_CodecFingerprint_ShapeAndVariance()
    Harness_Suite("Codec fingerprint")

    ' Readable, path-safe, and a function of everything the converter id has to
    ' change with. The server keys its converter cache by the id, so two different
    ' hint sets sharing a fingerprint would serve the first set's converter and
    ' silently ignore the second's hints.
    Harness_Equal(CodecFingerprint(["h264"], ["aac", "mp3"], 2), "vh264.aaac-mp3.c2", "the fingerprint names both lists and the cap")

    a = CodecFingerprint(["h264"], ["aac", "mp3"], 2)
    b = CodecFingerprint(["h264", "hevc"], ["aac", "mp3"], 2)
    c = CodecFingerprint(["h264"], ["aac"], 2)
    d = CodecFingerprint(["h264"], ["aac", "mp3"], 6)
    Harness_Ok(a <> b, "a different video list changes the fingerprint")
    Harness_Ok(a <> c, "a different audio list changes the fingerprint")
    Harness_Ok(a <> d, "a different channel cap changes the fingerprint")
end sub

sub Test_CodecCandidates_CarriableFlags()
    Harness_Suite("Codec candidates carry the transport flag")

    ' The flag is what separates "the chip can do this" from "this request may ask
    ' for it", and it is the only thing standing between a device that answers true
    ' for AV1/VP9 and a request that offers them.
    for each entry in CodecVideoCandidates()
        expected = (entry.codec = "h264" or entry.codec = "hevc")
        Harness_Equal(entry.hls, expected, "video candidate " + entry.codec + " carriable = " + HintsFlag(expected))
    end for

    ' The audio candidates carry no flag: the audio list is a switch, not a
    ' probe, and the sink's answer decides what is in it.
    for each entry in CodecAudioCandidates()
        Harness_Ok(not entry.DoesExist("hls"), "audio candidate " + entry.codec + " carries no transport flag")
    end for
end sub

sub Test_CodecListContains_Finds()
    Harness_Suite("Codec list containment")

    Harness_Ok(CodecListContains(["a", "b"], "a"), "a present entry is found")
    Harness_Ok(not CodecListContains(["a", "b"], "c"), "an absent entry is not found")
    Harness_Ok(not CodecListContains([], "a"), "nothing is found in an empty list")
end sub

' A stable "true"/"false" for the flag assertions, because Harness_Equal's
' message would otherwise print the interpreter's own rendering of a boolean.
function HintsFlag(value as boolean) as string
    if value then return "true"
    return "false"
end function
