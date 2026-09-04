' SettingsStore.brs
'
' A single source of truth for every global preference this app reads, plus the
' pure rules and the persistence for them. It covers the interface prefs
' (language, UI scale, blur-unwatched, display description), the player prefs
' (subtitle language/mode/sync defaults, audio track), the subtitle style prefs
' (render mode, font, size, colours, position), and the optional streaming
' server URL.
'
' It is a plain associative-array "class" in Roku's documented style: the
' instance captures its own fields through m, and MainScene owns one instance
' (m.settingsStore) that it asks for data and hands operations to.
'
' Unlike the add-on store, this store ALSO owns its registry persistence
' (load()/save*()) because roRegistrySection access is synchronous and global --
' no nodes, no callbacks, no scene chrome -- so it stays self-contained without
' pulling in any MainScene glue. MainScene keeps only the I/O that genuinely
' binds to the scene: dialogs, HTTP tasks, video-node pushes, chrome/renders.
'
' The subtitle-sync per-title offsets and the Stremio auth key are NOT here:
' they live in MainScene (per-title playback state and a separate auth domain).

function CreateSettingsStore() as object
    store = {
        _interfaceLanguage: "English"
        _blurUnwatchedEpisodes: true
        _uiScalePercent: UiScaleDefaultPercent()
        _uiScalePendingPercent: UiScaleDefaultPercent()
        _uiScaleSavedPercent: UiScaleDefaultPercent()
        _uiScaleReturnMode: "home"
        _displayDescription: ""
        _defaultSubtitleLanguage: "English"
        _subtitleDefaultMode: "Default language"
        _lastSubtitleSelection: "off"
        _subtitleOutlineColor: "Black"
        _defaultAudioTrack: "English"
        _subtitleRenderMode: "Below video"
        _subtitleFont: "Default"
        _subtitleTextSize: "Medium"
        _subtitleTextColor: "White"
        _subtitleBackdropOpacity: "75%"
        _subtitlePosition: "Bottom bar"
        _subtitlesEnabledByDefault: false
        _streamingServerUrl: ""
    }

    ' --- state accessor -------------------------------------------------------

    ' The dict pushed into the Settings component on every render. The keys match
    ' the component's m.state reads exactly.
    store.getState = function() as object
        return {
            streamingServerDisplay: m.StreamingServerDisplay()
            streamingServerConfigured: m.StreamingServerConfigured()
            interfaceLanguage: m._interfaceLanguage
            uiScalePercent: m._uiScalePercent
            displayDescription: m._displayDescription
            blurUnwatched: m._blurUnwatchedEpisodes
            defaultSubtitleLanguage: m._defaultSubtitleLanguage
            subtitleTextSize: m._subtitleTextSize
            subtitleTextColor: m._subtitleTextColor
            subtitleBackdropOpacity: m._subtitleBackdropOpacity
            subtitleOutlineColor: m._subtitleOutlineColor
            defaultAudioTrack: m._defaultAudioTrack
        }
    end function

    ' --- interface getters / setters ------------------------------------------

    store.getInterfaceLanguage = function() as string
        return m._interfaceLanguage
    end function

    store.setInterfaceLanguage = function(value as string)
        m._interfaceLanguage = value
    end function

    store.getBlurUnwatched = function() as boolean
        return m._blurUnwatchedEpisodes
    end function

    store.setBlurUnwatched = function(value as boolean)
        m._blurUnwatchedEpisodes = value
    end function

    store.getDisplayDescription = function() as string
        return m._displayDescription
    end function

    store.setDisplayDescription = function(value as string)
        m._displayDescription = value
    end function

    store.getUiScalePercent = function() as integer
        return m._uiScalePercent
    end function

    store.setUiScalePercent = function(value as integer)
        m._uiScalePercent = value
    end function

    store.getUiScalePendingPercent = function() as integer
        return m._uiScalePendingPercent
    end function

    store.setUiScalePendingPercent = function(value as integer)
        m._uiScalePendingPercent = value
    end function

    store.getUiScaleSavedPercent = function() as integer
        return m._uiScaleSavedPercent
    end function

    store.setUiScaleSavedPercent = function(value as integer)
        m._uiScaleSavedPercent = value
    end function

    store.getUiScaleReturnMode = function() as string
        return m._uiScaleReturnMode
    end function

    store.setUiScaleReturnMode = function(value as string)
        m._uiScaleReturnMode = value
    end function

    ' --- player getters / setters ---------------------------------------------

    store.getDefaultSubtitleLanguage = function() as string
        return m._defaultSubtitleLanguage
    end function

    store.setDefaultSubtitleLanguage = function(value as string)
        m._defaultSubtitleLanguage = value
    end function

    store.getSubtitleDefaultMode = function() as string
        return m._subtitleDefaultMode
    end function

    store.setSubtitleDefaultMode = function(value as string)
        m._subtitleDefaultMode = value
    end function

    store.getLastSubtitleSelection = function() as string
        return m._lastSubtitleSelection
    end function

    store.setLastSubtitleSelection = function(value as string)
        m._lastSubtitleSelection = value
    end function

    store.getSubtitleOutlineColor = function() as string
        return m._subtitleOutlineColor
    end function

    store.setSubtitleOutlineColor = function(value as string)
        m._subtitleOutlineColor = value
    end function

    store.getDefaultAudioTrack = function() as string
        return m._defaultAudioTrack
    end function

    store.setDefaultAudioTrack = function(value as string)
        m._defaultAudioTrack = value
    end function

    store.getSubtitlesEnabledByDefault = function() as boolean
        return m._subtitlesEnabledByDefault
    end function

    store.setSubtitlesEnabledByDefault = function(value as boolean)
        m._subtitlesEnabledByDefault = value
    end function

    ' --- subtitle style getters / setters -------------------------------------

    store.getSubtitleRenderMode = function() as string
        return m._subtitleRenderMode
    end function

    store.setSubtitleRenderMode = function(value as string)
        m._subtitleRenderMode = value
    end function

    store.getSubtitleFont = function() as string
        return m._subtitleFont
    end function

    store.setSubtitleFont = function(value as string)
        m._subtitleFont = value
    end function

    store.getSubtitleTextSize = function() as string
        return m._subtitleTextSize
    end function

    store.setSubtitleTextSize = function(value as string)
        m._subtitleTextSize = value
    end function

    store.getSubtitleTextColor = function() as string
        return m._subtitleTextColor
    end function

    store.setSubtitleTextColor = function(value as string)
        m._subtitleTextColor = value
    end function

    store.getSubtitleBackdropOpacity = function() as string
        return m._subtitleBackdropOpacity
    end function

    store.setSubtitleBackdropOpacity = function(value as string)
        m._subtitleBackdropOpacity = value
    end function

    store.getSubtitlePosition = function() as string
        return m._subtitlePosition
    end function

    store.setSubtitlePosition = function(value as string)
        m._subtitlePosition = value
    end function

    ' --- streaming server ------------------------------------------------------

    store.getStreamingServerUrl = function() as string
        return m._streamingServerUrl
    end function

    store.setStreamingServerUrl = function(value as string)
        m._streamingServerUrl = value
    end function

    ' The dedicated streaming server is optional: without it torrent-only add-ons
    ' keep being shown as unplayable, exactly as before this setting existed.
    store.StreamingServerConfigured = function() as boolean
        return m._streamingServerUrl <> ""
    end function

    store.StreamingServerDisplay = function() as string
        if not m.StreamingServerConfigured() then return TrText("settings.general.notConfigured")
        return m._streamingServerUrl
    end function

    ' Resolve a torrent-only stream to the streaming server's HLS playlist. The
    ' server lazily creates the torrent engine on first request and uses the file
    ' id (or -1 to auto-guess) to pick the file. Empty when unusable.
    store.StreamingServerStreamUrl = function(stream as object) as string
        if not m.StreamingServerConfigured() then return ""
        if stream = invalid or not stream.DoesExist("infoHash") then return ""
        infoHash = LCase(stream.infoHash.ToStr()).Trim()
        if Len(infoHash) <> 40 then return ""

        fileId = "-1"
        if stream.DoesExist("fileIdx") and stream.fileIdx <> invalid
            fileId = stream.fileIdx.ToStr()
        end if

        return m._streamingServerUrl + "/" + infoHash + "/" + fileId + "/hls.m3u8"
    end function

    ' --- persistence (synchronous registry, safe to own here) ------------------

    store.load = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        if section.Exists("interfaceLanguage") then m._interfaceLanguage = section.Read("interfaceLanguage")
        if section.Exists("uiScalePercent")
            storedScale = Int(Val(section.Read("uiScalePercent")))
            if storedScale >= UiScaleMinPercent() and storedScale <= UiScaleMaxPercent()
                m._uiScalePercent = storedScale
                m._uiScalePendingPercent = storedScale
                m._uiScaleSavedPercent = storedScale
            end if
        end if
        if section.Exists("blurUnwatchedEpisodes")
            m._blurUnwatchedEpisodes = section.Read("blurUnwatchedEpisodes") = "true"
        end if

        if section.Exists("defaultSubtitleLanguage") then m._defaultSubtitleLanguage = section.Read("defaultSubtitleLanguage")
        if section.Exists("subtitleDefaultMode") then m._subtitleDefaultMode = section.Read("subtitleDefaultMode")
        if section.Exists("lastSubtitleSelection") then m._lastSubtitleSelection = section.Read("lastSubtitleSelection")
        if section.Exists("subtitleOutlineColor") then m._subtitleOutlineColor = section.Read("subtitleOutlineColor")
        if section.Exists("defaultAudioTrack") then m._defaultAudioTrack = section.Read("defaultAudioTrack")

        if section.Exists("subtitleRenderMode") then m._subtitleRenderMode = section.Read("subtitleRenderMode")
        if section.Exists("subtitleFont") then m._subtitleFont = section.Read("subtitleFont")
        if section.Exists("subtitleTextSize") then m._subtitleTextSize = section.Read("subtitleTextSize")
        if section.Exists("subtitleTextColor") then m._subtitleTextColor = section.Read("subtitleTextColor")
        if section.Exists("subtitleBackdropOpacity") then m._subtitleBackdropOpacity = section.Read("subtitleBackdropOpacity")
        if section.Exists("subtitlePosition") then m._subtitlePosition = section.Read("subtitlePosition")
        if section.Exists("subtitlesEnabledByDefault")
            m._subtitlesEnabledByDefault = section.Read("subtitlesEnabledByDefault") = "true"
        end if

        if section.Exists("streamingServerUrl") then m._streamingServerUrl = section.Read("streamingServerUrl")
    end function

    store.saveInterfacePreferences = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        section.Write("interfaceLanguage", m._interfaceLanguage)
        section.Write("uiScalePercent", m._uiScalePercent.ToStr())
        if m._blurUnwatchedEpisodes
            section.Write("blurUnwatchedEpisodes", "true")
        else
            section.Write("blurUnwatchedEpisodes", "false")
        end if
        section.Flush()
    end function

    store.savePlayerPreferences = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        section.Write("defaultSubtitleLanguage", m._defaultSubtitleLanguage)
        section.Write("subtitleDefaultMode", m._subtitleDefaultMode)
        section.Write("lastSubtitleSelection", m._lastSubtitleSelection)
        section.Write("subtitleOutlineColor", m._subtitleOutlineColor)
        section.Write("defaultAudioTrack", m._defaultAudioTrack)
        section.Flush()
    end function

    store.saveSubtitlePreferences = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        section.Write("subtitleRenderMode", m._subtitleRenderMode)
        section.Write("subtitleFont", m._subtitleFont)
        section.Write("subtitleTextSize", m._subtitleTextSize)
        section.Write("subtitleTextColor", m._subtitleTextColor)
        section.Write("subtitleBackdropOpacity", m._subtitleBackdropOpacity)
        section.Write("subtitlePosition", m._subtitlePosition)
        section.Write("subtitleDefaultMode", m._subtitleDefaultMode)
        if m._subtitlesEnabledByDefault
            section.Write("subtitlesEnabledByDefault", "true")
        else
            section.Write("subtitlesEnabledByDefault", "false")
        end if
        section.Flush()
    end function

    store.saveStreamingServerConfig = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        if m._streamingServerUrl = ""
            section.Delete("streamingServerUrl")
        else
            section.Write("streamingServerUrl", m._streamingServerUrl)
        end if
        section.Flush()
    end function

    return store
end function

' The streaming server is reached over plain HTTP on the local network, so the
' rules are looser than IsValidManifestUrl: the scheme defaults to http, the
' port is optional, and no /manifest.json suffix is expected.
function NormalizeStreamingServerUrl(url as string) as string
    url = url.Trim()
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    if Instr(1, url, "://") = 0
        url = "http://" + url
    end if
    return url
end function

function IsValidStreamingServerUrl(url as string) as boolean
    lower = LCase(url)
    if Left(lower, 7) <> "http://" and Left(lower, 8) <> "https://" then return false

    host = url
    marker = "://"
    schemeEnd = Instr(1, url, marker)
    if schemeEnd > 0 then host = Mid(url, schemeEnd + Len(marker))
    if host = "" or Left(host, 1) = "/" then return false
    if Instr(1, host, "@") > 0 or Instr(1, host, "#") > 0 or Instr(1, host, " ") > 0 then return false
    return true
end function
