' Direct-play codec hint parsing and conservative compatibility decisions.

sub Test_DirectPlay_HintsFromEncodedFilenameUrl()
    Harness_Suite("DirectPlay finds codec aliases and a filename in the URL")
    stream = {
        url: "https://cdn.example/Show.S02E04.2160p.H.265.Dolby%20Digital%20Plus.mkv?token=opaque"
    }
    hints = DirectPlayHints(stream)
    Harness_Ok(hints.isDirect, "a URL is tagged as direct during the background parse")
    Harness_Equal(hints.video.Count(), 1, "one video codec hint is found")
    Harness_Equal(hints.video[0], "hevc", "H.265 is normalized to HEVC")
    Harness_Equal(hints.audio.Count(), 1, "one audio codec hint is found")
    Harness_Equal(hints.audio[0], "eac3", "Dolby Digital Plus maps to E-AC-3")

    encodedPlus = DirectPlayHints({ url: "https://cdn.example/file?filename=Movie%20x265%20DD%2B%205.1.mkv" })
    Harness_Equal(encodedPlus.audio[0], "eac3", "percent-encoded DD+ in a link filename maps to E-AC-3")

    responseName = DirectPlayHints({ url: "https://cdn.example/object?response-content-disposition=attachment%3B%20filename%3D%22Title%20x265%20DDP5.1.mkv%22&signature=x264" })
    Harness_Equal(responseName.video.Count(), 1, "the parser reads only filename-bearing URL parameters, not signatures")
    Harness_Equal(responseName.video[0], "hevc", "an encoded response filename supplies the video hint")
    Harness_Equal(responseName.audio[0], "eac3", "an encoded response filename supplies the audio hint")

    aacLayoutStream = {
        url: "https://node1.lat-add.com/media/movie/video.mkv?sig=opaque"
        behaviorHints: {
            filename: "Teenage.Sex.and.Death.at.Camp.Miasma.2026.1080p.MUBI.WEB-DL.AAC2.0.H.264.CAST.mkv"
        }
    }
    aacLayout = DirectPlayHints(aacLayoutStream)
    Harness_Equal(aacLayout.audio.Count(), 1, "AAC with an attached 2.0 layout still produces one audio hint")
    Harness_Equal(aacLayout.audio[0], "aac", "AAC2.0 maps to AAC")
    classified = DirectPlayTestClassify(aacLayoutStream, DirectPlayTestCapabilities("", ""))
    Harness_Equal(classified.audioState, "supported", "the recognized AAC hint reaches the device capability check")

    aacLookalike = DirectPlayHints({ url: "https://cdn.example/movie.mkv", title: "AACPlus" })
    Harness_Equal(aacLookalike.audio.Count(), 0, "alphabetic AAC lookalikes do not become codec hints")

    truehdLayout = DirectPlayHints({
        url: "https://cdn.example/movie.mkv"
        behaviorHints: { filename: "Movie.2026.1080p.WEB-DL.TrueHD7.1.mkv" }
    })
    Harness_Equal(truehdLayout.audio.Count(), 1, "TrueHD with an attached channel layout still produces one audio hint")
    Harness_Equal(truehdLayout.audio[0], "truehd", "TrueHD7.1 maps to TrueHD")
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
    result = DirectPlayTestClassify(stream, caps)
    Harness_Equal(result.videoState, "unknown", "quality alone does not imply video codec support")
    Harness_Equal(result.audioState, "unknown", "quality alone does not imply audio codec support")
    result = DirectPlayTestClassify({ url: "https://cdn.example/movie.mp4", title: "H.264" }, caps)
    Harness_Equal(result.videoState, "supported", "the known video codec is still reported as supported")
    Harness_Equal(result.audioState, "unknown", "missing audio metadata is reported separately")
    result = DirectPlayTestClassify({ url: "https://cdn.example/movie", title: "H.264 AAC" }, caps)
    Harness_Equal(result.videoState, "supported", "an opaque container does not erase known video codec support")
    Harness_Equal(result.audioState, "supported", "an opaque container does not erase known audio codec support")
end sub

sub Test_DirectPlay_CompatibilityStates()
    Harness_Suite("DirectPlay reports video/audio capability independently")
    caps = DirectPlayTestCapabilities("", "")
    stream = { url: "https://cdn.example/movie.mkv", title: "H.264 AAC" }
    result = DirectPlayTestClassify(stream, caps)
    Harness_Equal(result.videoState, "supported", "known video codec is reported independently")
    Harness_Equal(result.audioState, "supported", "known audio codec is reported independently")

    eac3Caps = DirectPlayTestCapabilities("", "eac3")
    eac3Stream = { url: "https://cdn.example/movie.mkv", title: "H.264 Dolby Digital Plus" }
    result = DirectPlayTestClassify(eac3Stream, eac3Caps)
    Harness_Equal(result.videoState, "supported", "an unsupported audio codec does not downgrade supported video")
    Harness_Equal(result.audioState, "unsupported", "a rejected codec is identified as an audio issue")

    multitrackCaps = DirectPlayTestCapabilities("", "truehd")
    multitrack = { url: "https://cdn.example/movie.mkv", title: "H.264 DDP 5.1 English TrueHD Atmos" }
    result = DirectPlayTestClassify(multitrack, multitrackCaps)
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
    result = DirectPlayTestClassify(stream, unavailable)
    Harness_Equal(result.videoState, "unknown", "unavailable device probes never become a negative video verdict")
    Harness_Equal(result.audioState, "unknown", "unavailable device probes never become a negative audio verdict")

    av1 = { url: "https://cdn.example/movie.mp4", title: "AV1 AAC" }
    result = DirectPlayTestClassify(av1, caps)
    Harness_Equal(result.videoState, "unknown", "a positive chip answer without a validated direct path stays unknown")
    Harness_Equal(result.audioState, "supported", "audio capability remains independent of an uncertain video path")
end sub

sub Test_DirectPlay_TorrentsAreIncluded()
    Harness_Suite("DirectPlay labels torrents from their release metadata")
    stream = { infoHash: "abcdef123456", title: "H.264 AAC movie.mkv" }
    hints = DirectPlayHints(stream)
    Harness_Ok(hints.isTorrent, "a torrent is tagged as a direct candidate during the background parse")
    Harness_Ok(not hints.isDirect, "but it is not a direct URL")
    result = DirectPlayClassifyHints(hints, DirectPlayTestCapabilities("", ""))
    Harness_Equal(result.videoState, "supported", "a torrent's release name supplies its video verdict")
    Harness_Equal(result.audioState, "supported", "and its audio verdict")

    result = DirectPlayTestClassify({ infoHash: "abcdef123456", title: "movie" }, DirectPlayTestCapabilities("", ""))
    Harness_Equal(result.videoState, "unknown", "a torrent whose metadata names no codec stays unknown, not server")
    Harness_Equal(result.audioState, "unknown", "ditto for audio")

    direct = { url: "https://cdn.example/movie.mkv", infoHash: "abcdef123456", title: "H.264 AAC" }
    hints = DirectPlayHints(direct)
    Harness_Ok(hints.isDirect and not hints.isTorrent, "a direct URL keeps precedence when a stream also carries an infoHash")
    result = DirectPlayTestClassify(direct, DirectPlayTestCapabilities("", ""))
    Harness_Equal(result.videoState, "supported", "both codec checks apply to the direct URL")
    Harness_Equal(result.audioState, "supported", "both codec checks apply to the direct URL")
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

function DirectPlayTestClassify(stream as dynamic, capabilities as dynamic) as object
    return DirectPlayClassifyHints(DirectPlayHints(stream), capabilities)
end function
