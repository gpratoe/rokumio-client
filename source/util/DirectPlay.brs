' DirectPlay — conservative, metadata-only compatibility estimates for direct
' links. Codec names are read from the add-on's stream hints; hardware answers
' are supplied by DirectPlayCapsTask through the shared CodecProbe helpers.

' Classify parsed hints against one device capability snapshot. Parsing is kept
' separate so it can run once in StreamsLoaderTask, not on every provider switch.
function DirectPlayClassifyHints(hints as dynamic, capabilities as dynamic) as object
    result = {
        videoState: "unknown"
        audioState: "unknown"
        video: []
        audio: []
        audioAlternatives: []
    }
    if Type(hints) <> "roAssociativeArray" then return result
    if hints.isDirect <> true
        result.videoState = "server"
        result.audioState = "server"
        return result
    end if

    result.video = hints.video
    result.audio = hints.audio
    result.audioAlternatives = hints.audioAlternatives

    if capabilities = invalid or Type(capabilities) <> "roAssociativeArray" then return result
    if capabilities.available <> true then return result

    videoSupported = 0
    videoUnsupported = 0
    videoUnknown = 0
    for each codec in result.video
        probe = DirectPlayCapability(capabilities.video, codec)
        if probe = invalid or probe.known <> true
            videoUnknown = videoUnknown + 1
        else if probe.ok <> true
            videoUnsupported = videoUnsupported + 1
        else if not DirectPlayVideoHasDirectPath(codec)
            ' The chip may know a codec that Roku's Video node does not support
            ' through a verified direct-file path; keep that case Unknown.
            videoUnknown = videoUnknown + 1
        else
            videoSupported = videoSupported + 1
        end if
    end for
    result.videoState = DirectPlayAggregateState(videoSupported, videoUnsupported, videoUnknown)

    ' Add-on release text can describe multiple audio tracks, not multiple
    ' codecs that are all required to start the video. Keep audio verdicts
    ' separate so one incompatible track never makes the whole stream look
    ' unplayable when another track is supported.
    audioSupported = 0
    audioUnsupported = 0
    audioUnknown = 0
    for each codec in result.audio
        probe = DirectPlayCapability(capabilities.audio, codec)
        if probe = invalid or probe.known <> true
            audioUnknown = audioUnknown + 1
        else if probe.ok = true
            audioSupported = audioSupported + 1
        else
            audioUnsupported = audioUnsupported + 1
        end if
    end for

    ' Some brand labels (notably Atmos) are ambiguous: one track may be either
    ' E-AC-3 or TrueHD. This is one alternative group, not two required tracks.
    for each group in result.audioAlternatives
        groupSupported = false
        groupUnknown = false
        for each codec in group.codecs
            probe = DirectPlayCapability(capabilities.audio, codec)
            if probe = invalid or probe.known <> true
                groupUnknown = true
            else if probe.ok = true
                groupSupported = true
            end if
        end for
        if groupSupported
            audioSupported = audioSupported + 1
        else if groupUnknown
            audioUnknown = audioUnknown + 1
        else
            audioUnsupported = audioUnsupported + 1
        end if
    end for
    result.audioState = DirectPlayAggregateState(audioSupported, audioUnsupported, audioUnknown)
    return result
end function

' Aggregate the evidence for one media dimension. Multiple known tracks can
' coexist; if some are supported and others are not, call out mixed support.
function DirectPlayAggregateState(supported as integer, unsupported as integer, unknown as integer) as string
    if supported > 0
        if unsupported > 0 or unknown > 0 then return "partial"
        return "supported"
    end if
    if unsupported > 0
        if unknown > 0 then return "partial"
        return "unsupported"
    end if
    return "unknown"
end function

' Extract codec-family hints from fields stream providers commonly use for a
' filename or release label. This pure parser also runs in StreamsLoaderTask.
function DirectPlayHints(stream as dynamic) as object
    hints = { isDirect: false, video: [], audio: [], audioAlternatives: [] }
    if Type(stream) <> "roAssociativeArray" then return hints

    url = DirectPlayText(stream.url)
    if url.Trim() = "" then return hints
    hints.isDirect = true

    text = ""
    text = DirectPlayAppend(text, DirectPlayUrlHintText(url))
    text = DirectPlayAppend(text, stream.name)
    text = DirectPlayAppend(text, stream.title)
    text = DirectPlayAppend(text, stream.description)
    text = DirectPlayAppend(text, stream.source)
    text = DirectPlayAppend(text, stream.quality)
    if Type(stream.behaviorHints) = "roAssociativeArray"
        text = DirectPlayAppend(text, stream.behaviorHints.filename)
    end if
    normalized = DirectPlayNormalize(text)

    video = []
    audio = []
    alternatives = []
    hasAc3 = false
    hasEac3 = false
    hasTruehd = false
    hasAtmos = false

    for each rule in DirectPlayCodecRules()
        if not DirectPlayRuleMatches(normalized, rule) then continue for
        if rule.family = "video"
            DirectPlayPushUnique(video, rule.codec)
        else if rule.family = "audioAlternative"
            hasAtmos = true
        else if rule.codec = "ac3"
            ' Resolve this after E-AC-3 so the shorter Dolby Digital alias can
            ' never shadow Dolby Digital Plus in the same release label.
            hasAc3 = true
        else
            DirectPlayPushUnique(audio, rule.codec)
            if rule.codec = "eac3" then hasEac3 = true
            if rule.codec = "truehd" then hasTruehd = true
        end if
    end for

    if hasAc3 and not hasEac3 and not hasAtmos then DirectPlayPushUnique(audio, "ac3")
    if hasAtmos and not hasEac3 and not hasTruehd
        alternatives.Push({ codecs: ["eac3", "truehd"] })
    end if

    hints.video = video
    hints.audio = audio
    hints.audioAlternatives = alternatives
    return hints
end function

' Used only if a loader returns a stream without the matching parsed-hint slot.
' Preserve direct-versus-server routing but avoid falling back to a costly UI
' thread parse.
function DirectPlayUnknownHints(stream as dynamic) as object
    url = ""
    if Type(stream) = "roAssociativeArray" then url = DirectPlayText(stream.url)
    return { isDirect: url.Trim() <> "", video: [], audio: [], audioAlternatives: [] }
end function

function DirectPlayCodecRules() as object
    ' Cache the immutable alias table in this component's script scope. The
    ' StreamsLoaderTask calls DirectPlayHints many times in one worker run, and
    ' rebuilding the rule arrays for each stream would add needless allocations.
    if m._directPlayCodecRules = invalid
        m._directPlayCodecRules = [
            { family: "video", codec: "h264", exact: ["h264", "h 264", "avc", "avc1", "x264"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "video", codec: "hevc", exact: ["h265", "h 265", "hevc", "x265"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "video", codec: "av1", exact: ["av1"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "video", codec: "vp9", exact: ["vp9"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "video", codec: "mpeg4", exact: ["mpeg4", "mpeg 4", "xvid"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "eac3", exact: ["eac3", "eac 3", "e ac3", "e ac 3", "ec3", "ec 3", "dd plus", "ddpplus", "dolbydigitalplus", "dolby digital plus"], tokenPrefixes: ["ddp", "dolbydigitalplus"], phrasePrefixes: ["dd plus", "dolby digital plus"] },
            { family: "audio", codec: "ac3", exact: ["ac3", "ac 3", "dolbydigital", "dolby digital", "dd"], tokenPrefixes: ["dd"], phrasePrefixes: [] },
            { family: "audioAlternative", codec: "atmos", exact: ["atmos", "dolby atmos"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "truehd", exact: ["truehd", "true hd", "dolby truehd"], tokenPrefixes: ["truehd"], phrasePrefixes: [] },
            { family: "audio", codec: "aac", exact: ["aac", "he aac"], tokenPrefixes: ["aac"], phrasePrefixes: [] },
            { family: "audio", codec: "mp3", exact: ["mp3", "mpeg audio layer 3"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "dts", exact: ["dts", "dts hd", "dts x"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "flac", exact: ["flac"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "alac", exact: ["alac"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "opus", exact: ["opus"], tokenPrefixes: [], phrasePrefixes: [] },
            { family: "audio", codec: "vorbis", exact: ["vorbis"], tokenPrefixes: [], phrasePrefixes: [] }
        ]
    end if
    return m._directPlayCodecRules
end function

' One rule shape handles exact aliases and the two suffix forms. Keeping the
' data here makes new provider spellings explicit without duplicating matcher
' logic in the parser.
function DirectPlayRuleMatches(text as string, rule as object) as boolean
    if DirectPlayHasAny(text, rule.exact) then return true
    for each prefix in rule.tokenPrefixes
        if DirectPlayHasTokenPrefix(text, prefix) then return true
    end for
    for each phrase in rule.phrasePrefixes
        if DirectPlayHasPhrasePrefix(text, phrase) then return true
    end for
    return false
end function

' Keep the URL path and filename-bearing query values, but discard credentials,
' signatures and unrelated parameters. This matters because signed links can be
' much longer than the actual release filename.
function DirectPlayUrlHintText(url as string) as string
    query = ""
    queryIndex = url.InStr("?")
    if queryIndex >= 0
        path = url.Left(queryIndex)
        query = url.Mid(queryIndex + 1)
    else
        path = url
    end if

    text = path
    if query = "" then return text
    for each parameter in query.Split("&")
        equals = parameter.InStr("=")
        if equals < 0 then continue for
        key = LCase(parameter.Left(equals))
        carriesFilename = key.InStr("filename") >= 0 or key.InStr("content-disposition") >= 0 or key = "file" or key = "name"
        if carriesFilename then text = DirectPlayAppend(text, parameter.Mid(equals + 1))
    end for
    return text
end function

' Convert release-name punctuation and common encoded URL separators into
' spaces, retaining alphanumeric codec tokens. A literal '+' in a query/title
' is expanded to "plus" so labels such as DD+ remain distinguishable from DD.
function DirectPlayNormalize(text as string) as string
    result = ""
    i = 0
    while i < text.Len()
        encoded = LCase(text.Mid(i, 3))
        if encoded = "%2b"
            result = result + " plus "
            i = i + 3
            continue while
        else if encoded = "%20" or encoded = "%2e" or encoded = "%2d" or encoded = "%5f" or encoded = "%2f" or encoded = "%28" or encoded = "%29" or encoded = "%22" or encoded = "%3b" or encoded = "%3d" or encoded = "%5b" or encoded = "%5d"
            result = result + " "
            i = i + 3
            continue while
        end if

        ch = text.Mid(i, 1)
        code = Asc(ch)
        if (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or (code >= 65 and code <= 90)
            result = result + LCase(ch)
        else if ch = "+"
            result = result + " plus "
        else
            result = result + " "
        end if
        i = i + 1
    end while
    return result
end function

function DirectPlayCapability(probes as dynamic, codec as string) as dynamic
    if probes = invalid then return invalid
    for each probe in probes
        if probe.codec = codec then return probe
    end for
    return invalid
end function

function DirectPlayVideoHasDirectPath(codec as string) as boolean
    ' These are the video families for which the app has a known native direct
    ' file path. Other positive CanDecodeVideo answers stay Unknown: the chip's
    ' answer alone is not proof that Roku's player can open the stream/container.
    return codec = "h264" or codec = "hevc"
end function

function DirectPlayHasAny(text as string, phrases as object) as boolean
    for each phrase in phrases
        if DirectPlayHas(text, phrase) then return true
    end for
    return false
end function

function DirectPlayHas(text as string, phrase as string) as boolean
    padded = " " + text + " "
    return padded.InStr(" " + phrase + " ") >= 0
end function

' Release labels often append channel layout or bitrate digits directly to the
' codec token (DDP5.1, DolbyDigitalPlus640). Accept a numeric suffix without
' turning unrelated words sharing the prefix into codec matches.
function DirectPlayHasTokenPrefix(text as string, prefix as string) as boolean
    padded = " " + text + " "
    needle = " " + prefix
    cursor = 0
    while cursor < padded.Len()
        found = padded.Mid(cursor).InStr(needle)
        if found < 0 then return false
        start = cursor + found
        after = start + 1 + prefix.Len()
        followingChar = padded.Mid(after, 1)
        code = Asc(followingChar)
        if followingChar = " " or (code >= 48 and code <= 57) then return true
        cursor = start + 1
    end while
    return false
end function

function DirectPlayHasPhrasePrefix(text as string, phrase as string) as boolean
    padded = " " + text + " "
    needle = " " + phrase
    cursor = 0
    while cursor < padded.Len()
        found = padded.Mid(cursor).InStr(needle)
        if found < 0 then return false
        start = cursor + found
        after = start + 1 + phrase.Len()
        followingChar = padded.Mid(after, 1)
        code = Asc(followingChar)
        if followingChar = " " or (code >= 48 and code <= 57) then return true
        cursor = start + 1
    end while
    return false
end function

sub DirectPlayPushUnique(items as object, value as string)
    for each item in items
        if item = value then return
    end for
    items.Push(value)
end sub

function DirectPlayAppend(text as string, value as dynamic) as string
    if Type(value) <> "roString" and Type(value) <> "String" then return text
    if value.Trim() = "" then return text
    if text <> "" then text = text + " "
    return text + value
end function

function DirectPlayText(value as dynamic) as string
    if Type(value) = "roString" or Type(value) = "String" then return value
    return ""
end function
