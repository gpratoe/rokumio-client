' Direct-play codec hint parsing and conservative compatibility decisions.

sub Test_DirectPlay_HintsFromEncodedFilenameUrl()
    Harness_Suite("DirectPlay finds codec aliases and a filename in the URL")
    stream = {
        url: "https://cdn.example/Show.S02E04.2160p.H.265.Dolby%20Digital%20Plus.mkv?token=opaque"
    }
    hints = DirectPlayHints(stream)
    Harness_Equal(hints.format, "mkv", "container is found in the link filename")
    Harness_Equal(hints.video.Count(), 1, "one video codec hint is found")
    Harness_Equal(hints.video[0], "hevc", "H.265 is normalized to HEVC")
    Harness_Equal(hints.audio.Count(), 1, "one audio codec hint is found")
    Harness_Equal(hints.audio[0], "eac3", "Dolby Digital Plus maps to E-AC-3")

    encodedPlus = DirectPlayHints({ url: "https://cdn.example/file?filename=Movie%20x265%20DD%2B%205.1.mkv" })
    Harness_Equal(encodedPlus.audio[0], "eac3", "percent-encoded DD+ in a link filename maps to E-AC-3")
end sub

sub Test_DirectPlay_BrandAndShortCodecAliases()
    Harness_Suite("DirectPlay recognizes brand and common release-name aliases")
    plus = DirectPlayHints({ url: "https://cdn.example/movie.mp4", title: "AVC DDP 5.1" })
    Harness_Equal(plus.video[0], "h264", "AVC maps to H.264")
    Harness_Equal(plus.audio[0], "eac3", "DDP maps to E-AC-3")

    digital = DirectPlayHints({ url: "https://cdn.example/movie.mkv", description: "x265 Dolby Digital 5.1" })
    Harness_Equal(digital.video[0], "hevc", "x265 maps to HEVC")
    Harness_Equal(digital.audio[0], "ac3", "Dolby Digital maps to AC-3")

    shortDigital = DirectPlayHints({ url: "https://cdn.example/movie.mkv", title: "H264 DD5.1" })
    Harness_Equal(shortDigital.audio[0], "ac3", "DD5.1 maps to Dolby Digital / AC-3")

    atmos = DirectPlayHints({ url: "https://cdn.example/movie.mp4", title: "H264 Dolby Atmos" })
    Harness_Equal(atmos.audioAlternatives.Count(), 1, "Atmos is represented as an ambiguous audio family")
    Harness_Equal(atmos.audioAlternatives[0].codecs[0], "eac3", "Atmos can be E-AC-3")
    Harness_Equal(atmos.audioAlternatives[0].codecs[1], "truehd", "Atmos can also be TrueHD")

    for each variant in ["DDP5.1", "DDP5", "DD+5.1", "DolbyDigitalPlus640"]
        hints = DirectPlayHints({ url: "https://cdn.example/movie.mkv", title: "H264 " + variant })
        foundEac3 = hints.audio.Count() = 1
        if foundEac3 then foundEac3 = hints.audio[0] = "eac3"
        Harness_Ok(foundEac3, variant + " maps to E-AC-3")
    end for
end sub

sub Test_DirectPlay_UnknownWithoutCodecHints()
    Harness_Suite("DirectPlay leaves incomplete metadata unknown")
    caps = DirectPlayTestCapabilities("", "")
    stream = { url: "https://cdn.example/movie.mp4", title: "1080p Web-DL" }
    result = DirectPlayClassify(stream, caps)
    Harness_Equal(result.state, "unknown", "container and quality alone do not imply a codec")
    result = DirectPlayClassify({ url: "https://cdn.example/movie.mp4", title: "H.264" }, caps)
    Harness_Equal(result.state, "unknown", "missing audio metadata prevents a positive claim")
    Harness_Equal(result.videoState, "supported", "the known video codec is still reported as supported")
    Harness_Equal(result.audioState, "unknown", "missing audio metadata is reported separately")
    result = DirectPlayClassify({ url: "https://cdn.example/movie", title: "H.264 AAC" }, caps)
    Harness_Equal(result.videoState, "supported", "an opaque container does not erase known video codec support")
    Harness_Equal(result.audioState, "supported", "an opaque container does not erase known audio codec support")
end sub

sub Test_DirectPlay_CompatibilityStates()
    Harness_Suite("DirectPlay distinguishes likely, unsupported and unknown")
    caps = DirectPlayTestCapabilities("", "")
    stream = { url: "https://cdn.example/movie.mkv", title: "H.264 AAC" }
    result = DirectPlayClassify(stream, caps)
    Harness_Equal(result.state, "likely", "known container and supported video/audio codecs are likely playable")

    eac3Caps = DirectPlayTestCapabilities("", "eac3")
    eac3Stream = { url: "https://cdn.example/movie.mkv", title: "H.264 Dolby Digital Plus" }
    result = DirectPlayClassify(eac3Stream, eac3Caps)
    Harness_Equal(result.videoState, "supported", "an unsupported audio codec does not downgrade supported video")
    Harness_Equal(result.audioState, "unsupported", "a rejected codec is identified as an audio issue")
    Harness_Equal(result.state, "partial", "an audio limitation is not reported as total stream incompatibility")

    multitrackCaps = DirectPlayTestCapabilities("", "truehd")
    multitrack = { url: "https://cdn.example/movie.mkv", title: "H.264 DDP 5.1 English TrueHD Atmos" }
    result = DirectPlayClassify(multitrack, multitrackCaps)
    Harness_Equal(result.videoState, "supported", "video verdict stays independent for a multi-audio file")
    Harness_Equal(result.audioState, "partial", "supported and unsupported tracks are reported as mixed")

    releaseText = "[Hindi AMZN DDP 5.1 + English TrueHD Atmos 7.1] x264"
    release = DirectPlayHints({ url: "https://cdn.example/file?filename=Title%20AVC%20DDP%205.1.mkv", description: releaseText })
    videoHintOk = release.video.Count() > 0
    if videoHintOk then videoHintOk = release.video[0] = "h264"
    Harness_Ok(videoHintOk, "AVC/x264 hints identify H.264 in release text and URL filename")
    audioHintsOk = release.audio.Count() = 2
    if audioHintsOk then audioHintsOk = release.audio[0] = "eac3" and release.audio[1] = "truehd"
    Harness_Ok(audioHintsOk, "DDP and TrueHD are kept as separate audio-track hints")

    unavailable = { available: false, video: [], audio: [] }
    result = DirectPlayClassify(stream, unavailable)
    Harness_Equal(result.state, "unknown", "unavailable device probes never become a negative verdict")

    av1 = { url: "https://cdn.example/movie.mp4", title: "AV1 AAC" }
    result = DirectPlayClassify(av1, caps)
    Harness_Equal(result.state, "unknown", "a positive chip answer without a validated direct path stays unknown")
end sub

sub Test_DirectPlay_TorrentsAreExcluded()
    Harness_Suite("DirectPlay does not label server-transcoded torrents")
    stream = { infoHash: "abcdef123456", title: "H.264 AAC movie.mkv" }
    result = DirectPlayClassify(stream, DirectPlayTestCapabilities("", ""))
    Harness_Equal(result.state, "server", "a torrent without a direct URL has no device compatibility badge")
    Harness_Equal(result.videoState, "server", "server-routed streams are marked distinctly for the tile")

    direct = { url: "https://cdn.example/movie.mkv", infoHash: "abcdef123456", title: "H.264 AAC" }
    result = DirectPlayClassify(direct, DirectPlayTestCapabilities("", ""))
    Harness_Equal(result.state, "likely", "a direct URL keeps precedence when a stream also carries an infoHash")
end sub

function DirectPlayTestCapabilities(unsupportedVideo as string, unsupportedAudio as string) as object
    video = []
    for each codec in ["h264", "hevc", "av1", "vp9", "mpeg4"]
        video.Push({ codec: codec, known: true, ok: codec <> unsupportedVideo })
    end for
    audio = []
    for each codec in ["aac", "mp3", "ac3", "eac3", "truehd", "dts", "flac", "alac", "opus", "vorbis"]
        audio.Push({ codec: codec, known: true, ok: codec <> unsupportedAudio })
    end for
    return { available: true, video: video, audio: audio }
end function
