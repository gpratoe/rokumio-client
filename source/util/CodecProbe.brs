' CodecProbe — which codecs to advertise as pass-through to the streaming server.
'
' The HLS2 converter takes `videoCodecs` / `audioCodecs` as its remux
' (pass-through) allow-list: a source stream whose codec is in the list is
' stream-copied, anything else is re-encoded. The server's own defaults are
' ["h264"] and ["aac","mp3"], so today an HEVC file is re-encoded even on a 4K
' Roku that decodes HEVC natively. The list also REPLACES the default, so it has
' to be complete — advertising `hevc` without `h264` would evict H.264 and force
' it to be re-encoded.
'
' The VIDEO half is advertised from what THIS device reports. The AUDIO half
' is a switch the user owns: off, the request keeps audio on the server's own
' floor (aac, mp3); on, every audio codec is offered and the server copies what
' it can carry. The switch is a setting, not a probe, because the device cannot
' answer it — the test Roku reports AC-3 over HDMI and does not reproduce it
' (the same content, sent straight to the Roku as a raw MKV with no remux in
' the path, was just as silent), so no CanDecodeAudio reply separates "will
' play" from "claims it and stays quiet". See reference/hls2.md.
'
' The right video list is whatever THIS device reports through roDeviceInfo's
' CanDecodeVideo — but the raw answer is NOT the list, and this module exists
' to keep that distinction. CanDecode* answers a chip-capability question, not
' "can the HLS player play this": the test Roku answered true for both av1 and
' vp9, and neither can travel in an HLS/fMP4 stream at all (AV1 is DASH-only,
' VP9 is not a Roku video codec). Advertising them would have forced a remux
' the player then cannot decode — a black screen where the old transcode at
' least produced pictures. So the advertised video list is an INTERSECTION: the
' codecs HLS can carry AND the device says it decodes. The two halves are
' exactly what this module holds — the candidates and the transport flag — and
' the roDeviceInfo calls themselves live in the component that owns a Task scope
' (components/DeviceCapTask.brs for the spike, StreamResolveTask.brs for
' playback), so this stays runnable under the test interpreter, which has no
' device.
'
' The names below are the SERVER's, i.e. ffprobe's `stream.codec` values, because
' that is the string the converter compares against. Roku's vocabulary is not
' guaranteed to match (its own documentation lists "mpeg4 avc" for H.264), which
' is exactly what the Phase 0 spike measured: the raw reply of a rejected probe
' carries the list of names Roku does know, so a mismatch shows up as data
' instead of as a silently ignored hint. The spike has since run and Roku
' accepted every name below, printing its own vocabulary back only in `raw`.

' Video candidates, in the order they are probed. h264 and hevc are the only two
' video codecs an HLS stream can carry on Roku (HEVC on 4K devices), so only they
' are marked `hls`; the rest are probed so the spike can show what the chip
' claims rather than assume it, and are kept out of any advertised list by that
' flag. Profiles/levels are the highest each codec documents, so a "yes" means
' the codec family at full quality, not just at some lowest common denominator —
' and for HEVC, "main/5.1" is literally Roku's own documented CanPlay4K recipe.
'
' h264 is not merely the first candidate, it is the server's default: dropping it
' from an advertised list would evict the one codec the service could already
' stream-copy, so its place is also pinned by CodecVideoFloor() below.
function CodecVideoCandidates() as object
    return [
        { codec: "h264", hls: true, profile: "high", level: "4.2" },
        { codec: "hevc", hls: true, profile: "main", level: "5.1" },
        { codec: "av1", hls: false, profile: "", level: "" },
        { codec: "vp9", hls: false, profile: "", level: "" },
        { codec: "mpeg4", hls: false, profile: "", level: "" }
    ]
end function

' Audio candidates — the vocabulary of codecs to ask about, not a list to
' advertise. There is no transport flag on them: the user decides whether to
' ask for the audio to be copied (see CodecDolbyCandidates) and the server decides
' what it can carry.
'
' aac and mp3 are the server's own defaults and are what the app asks for
' unless the user turns passthrough on. The rest are here so the request can
' offer them and so the Phase 0 spike has one vocabulary to report on.
function CodecAudioCandidates() as object
    return [
        { codec: "aac" },
        { codec: "mp3" },
        { codec: "ac3" },
        { codec: "eac3" },
        { codec: "truehd" },
        { codec: "dts" },
        { codec: "flac" },
        { codec: "alac" },
        { codec: "opus" },
        { codec: "vorbis" }
    ]
end function

' Shared device probes. Server-hint generation and the direct-play indicator
' must use the same Roku answers rather than growing separate capability rules.
' `strictProfile` keeps the server's full-profile check intact; direct-play
' classification asks whether the device recognizes the codec family at all.
function CodecProbeVideo(di as object, candidate as object, strictProfile = true as boolean) as object
    request = { codec: candidate.codec }
    if strictProfile
        if candidate.profile <> "" then request.profile = candidate.profile
        if candidate.level <> "" then request.level = candidate.level
    end if
    return CodecProbeVideoRequest(di, candidate.codec, request)
end function

function CodecProbeVideoRequest(di as object, codec as string, request as object) as object
    probe = { codec: codec, ok: false, known: false }
    raw = invalid
    try
        raw = di.CanDecodeVideo(request)
    catch e
        return probe
    end try
    flag = CodecFlag(raw)
    if flag = "true"
        probe.ok = true
        probe.known = true
    else if flag = "false"
        probe.known = true
    end if
    return probe
end function

' A negative passthru value omits the filter and asks the platform's general
' codec question; 0/1 retain the existing Roku-versus-HDMI queries.
function CodecProbeAudio(di as object, candidate as object, passthru = -1 as integer) as object
    probe = { codec: candidate.codec, ok: false, known: false }
    request = { codec: candidate.codec }
    if passthru >= 0 then request.passthru = passthru
    raw = invalid
    try
        raw = di.CanDecodeAudio(request)
    catch e
        return probe
    end try
    flag = CodecFlag(raw)
    if flag = "true"
        probe.ok = true
        probe.known = true
    else if flag = "false"
        probe.known = true
    end if
    return probe
end function

' The codecs the two audio options may offer: Dolby Digital and Dolby Digital
' Plus. DTS is left out until it is tested — the platform accepts it and the
' muxer has a tag for it, but this ffmpeg cannot mux a DTS track into a
' fragmented MP4 here, and a failed copy breaks the stream rather than
' quieting it.
'
' The two options ask about the SAME codecs and differ only in the question:
' passthru 1 asks about the attached HDMI device (the sound system that
' decodes it), passthru 0 asks about the Roku itself (the decoder that would
' decode a copy the server does not re-encode).
function CodecDolbyCandidates() as object
    return [
        { codec: "ac3" },
        { codec: "eac3" }
    ]
end function

' The audio list to advertise: the floor, plus the codecs the sink takes. The
' floor comes first and is never dropped — an advertised list REPLACES the
' server's defaults, so a list without aac and mp3 would turn the service's
' sure copy into a re-encode.
function CodecAudioHints(floor as object, accepted as object) as object
    hints = []
    for each name in floor
        if not CodecListContains(hints, name) then hints.Push(name)
    end for
    for each name in accepted
        if not CodecListContains(hints, name) then hints.Push(name)
    end for
    return hints
end function

' The server's own default pass-through lists, and the floor of every advertised
' one. They matter because an advertised list REPLACES the defaults rather than
' extending them: a request that dropped h264, aac or mp3 would not fall back to
' the server's copy rule for them, it would turn the service's one sure
' stream-copy into a re-encode on every file — silently, since a transcode is a
' valid response.
function CodecVideoFloor() as object
    return ["h264"]
end function

function CodecAudioFloor() as object
    return ["aac", "mp3"]
end function

' The video list to advertise: the floor, plus every candidate the device
' accepted that this transport can actually carry. Order follows the candidate
' list, and the floor comes first so a glance at a request reads the defaults
' before the additions.
'
' The two conditions are not redundant. `accepted` is the device's answer;
' `candidate.hls` is the transport's. Only both together are a promise the
' server can keep — the chips that answered true for av1/vp9 are the ones that
' would otherwise be handed a stream the HLS player cannot open.
function CodecHints(floor as object, candidates as object, probes as object) as object
    accepted = {}
    for each probe in probes
        if probe.ok then accepted[probe.codec] = true
    end for

    hints = []
    for each name in floor
        if not CodecListContains(hints, name) then hints.Push(name)
    end for
    for each candidate in candidates
        if candidate.hls and accepted.DoesExist(candidate.codec) then
            if not CodecListContains(hints, candidate.codec) then hints.Push(candidate.codec)
        end if
    end for
    return hints
end function

' The converter id's discriminator: a readable fingerprint of everything the id
' has to change with. It exists because the server caches a converter BY ID and
' only builds one when the id is new — so reusing an id with new hints does not
' apply the new hints, it silently serves the cached converter built from the old
' ones. Two devices, or one device after an HDMI change, must therefore not share
' an id. Charset is alnum plus "-" and "." so the result is safe as a path
' segment without escaping.
function CodecFingerprint(videoCodecs as object, audioCodecs as object, maxAudioChannels as integer) as string
    return "v" + CodecJoin(videoCodecs, "-") + ".a" + CodecJoin(audioCodecs, "-") + ".c" + maxAudioChannels.ToStr()
end function

' Whether a list of names holds this one. Local for the same reason CodecJoin
' is: components do not share function scope, and the hint builder must not
' depend on a neighbour's helper.
function CodecListContains(list as object, name as string) as boolean
    for each entry in list
        if entry = name then return true
    end for
    return false
end function

' One word for what a CanDecode* reply said. A probe is only "true" when the reply
' is a real assocarray whose `result` is exactly boolean true; every other shape —
' invalid, the wrong type, a reply with no `result` — is reported distinctly so
' the console log says WHY it was not a yes instead of flattening every failure
' to "false". NetDiag learned the same lesson: a diagnostic that cannot tell one
' failure from another is not a measurement.
function CodecFlag(raw as dynamic) as string
    if raw = invalid then return "invalid"
    if Type(raw) <> "roAssociativeArray" then return "not-object"
    if not raw.DoesExist("result") then return "absent"
    value = raw.result
    kind = Type(value)
    if kind = "Boolean" or kind = "roBoolean" then
        if value then return "true"
        return "false"
    end if
    return "non-bool"
end function

' The actionable form: true only for an explicit yes.
function CodecResult(raw as dynamic) as boolean
    return CodecFlag(raw) = "true"
end function

' Comma-joined names of the probes that said yes, empty string when none did.
' Kept separate from the summary so a caller that only needs the list does not
' have to own the display format.
function CodecSupportedList(probes as object) as string
    names = []
    for each probe in probes
        if probe.ok then names.Push(probe.codec)
    end for
    return CodecJoin(names, ",")
end function

' The compact line the Settings row shows: which video and audio codecs the device
' reports, or "(none)" when a probe list is empty or all-no.
function CodecSummary(videoProbes as object, audioProbes as object) as string
    video = CodecSupportedList(videoProbes)
    audio = CodecSupportedList(audioProbes)
    if video = "" then video = "(none)"
    if audio = "" then audio = "(none)"
    return "video: " + video + "  audio: " + audio
end function

' Plain join for BrightScript string arrays. The device-side component cannot use
' whichever Join the NetDiag component defines — components do not share function
' scope — so this module owns its own rather than depending on a neighbour.
function CodecJoin(parts as object, glue as string) as string
    out = ""
    for each part in parts
        if out <> "" then out = out + glue
        out = out + part
    end for
    return out
end function
