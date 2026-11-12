' SettingsScreen — app preferences.
'
' The settings are grouped into SECTIONS: one chip per section along the top,
' the rows of the selected section in the list below. A flat list of
' everything the app can be told to do stops being readable as soon as it
' holds more than one topic, and the topics here are genuinely different — who
' you are signed in as, what language the app speaks, where the streaming
' server lives and whether it answers. Each topic gets its own chip and its
' own short list, so adding a setting is adding a row to a section, never
' renumbering a flat list that other rows depend on.
'
' SectionDefinitions() is the one place the screen's shape is decided. A row
' is {action, title, value}: the action is what OK does, the title is the
' label, the value is the right-hand column. The values come from the live
' stores when the rows are built, so the list shows what is persisted rather
' than what was persisted when the screen was opened.
'
' The rows are PrefRows backed by SettingsStore: streaming server address
' (edited through a system KeyboardDialog), UI language (cycled on OK), plus a
' Test-server row that hearts the configured streaming server so a playback
' dead-end is caught before pressing play. Every value is rebuilt on entry so
' the rows always reflect the persisted values.
'
' A hidden Network-diagnostics row sits behind NETDIAG_REVEAL_TAPS presses of
' the Test-server row. It is TEMPORARY: it exists to locate the intermittent
' outbound-connect failures (status -7) as DNS, radio, or concurrency, and it
' goes away — with NetDiagTask itself — once that is known.
'
' A second hidden row, Device codecs, comes up with the same gesture. It is
' likewise TEMPORARY (see DeviceCapTask.brs): it prints what this Roku reports
' through CanDecodeVideo/CanDecodeAudio, so the codec names the streaming server
' is asked to pass through can be checked against the device before any hint is
' sent. Both rows are diagnostics of the same kind and are revealed together.

' Five consecutive presses of the Test-server row reveal the hidden
' Network-diagnostics row. Test-server is the right host for the gesture: it is
' already the row about connectivity, so a diagnostic living one row below it
' reads as a continuation rather than as a stray debug affordance. The count is
' inlined at its one use because standard BrightScript has no file-scope const
' (that is a BrighterScript feature, and this is a .brs file).

sub init()
    m.title = m.top.FindNode("settingsTitle")
    m.sub = m.top.FindNode("settingsSub")
    m.status = m.top.FindNode("settingsStatus")
    m.chips = m.top.FindNode("settingsChips")
    m.list = m.top.FindNode("settingsList")
    m.infoTitle = m.top.FindNode("infoTitle")
    m.infoWarn = m.top.FindNode("infoWarn")
    m.infoBody = m.top.FindNode("infoBody")
    m.infoPlate = m.top.FindNode("infoPlate")

    palette = Theme()
    m.title.color = palette.accent
    m.sub.color = palette.textSecondary
    m.status.color = palette.accent
    m.infoPlate.color = palette.screenBg
    m.infoTitle.color = palette.accent
    m.infoWarn.color = palette.danger
    m.infoBody.color = palette.textSecondary

    ' The panel body mixes styles so the codec names can be bold inside the
    ' sentence. The styles come from the palette, because a colour literal in
    ' markup is a colour nobody can change.
    m.infoBody.drawingStyles = {
        "default": { fontUri: "font:SmallSystemFont", color: palette.textSecondary }
        "bold": { fontUri: "font:MediumBoldSystemFont", color: palette.accent }
    }

    m.list.ObserveField("rowItemSelected", "onRowSelected")
    m.list.ObserveField("rowItemFocused", "onRowFocused")
    m.chips.ObserveField("selection", "onChipSelected")

    m.rows = []
    ' The content node of each row, by action. A value change is written into
    ' these, so the list is never rebuilt over the user's cursor.
    m.rowNodes = {}
    m.sections = []
    m.activeSection = 0
    ' The row the cursor is on, for the side panel. The list has no focused-row
    ' field, so the index comes from the rowItemFocused observer.
    m.focusedRow = -1
    ' Invalid until the probe lands: the row says "On" rather than claiming the
    ' device takes nothing before anyone has asked it.
    m.passthruCodecs = invalid
    m.transmuxCodecs = invalid
    m.audioCapTask = invalid
    ' The torrent profile is the SERVER's, not this Roku's: the row says what
    ' the server reports. "" means the answer has not landed yet, "unknown"
    ' means the server could not be asked, "custom" means it is running limits
    ' that match no Stremio profile.
    m.serverProfile = ""
    m.serverCacheSize = invalid
    m.serverCacheSizeChoices = []
    m.serverCacheSizeIndex = -1
    m.serverCacheSizeState = "" ' "unknown", "notavailable", "custom", or ""
    m.serverSettingsTask = invalid
    m.pendingProfile = ""
    m.pendingCacheSize = invalid
    m.pendingWriteType = ""
    ' The status line's own state: the key its words came from, the values
    ' that filled it, and the optional suffix key. Initialized here for the
    ' same reason the flags above are: an unassigned read is invalid, and
    ' invalid is a crash when it reaches a subscript.
    m.statusKey = ""
    m.statusValues = invalid
    m.statusSuffixKey = ""
    ' The languages under the row, in cycle order. The cycle covers exactly the
    ' languages the text table carries a complete Settings screen for: a code
    ' that would land the row on Lang() fallback keys is not a choice to offer
    ' yet, and more arrive here with their texts.json section.
    m.languages = ["en", "es"]
    m.heartbeatTask = invalid
    ' Component fields outlive OnEnter, so once the diagnostics row is revealed it
    ' stays revealed for the rest of the session instead of vanishing every time
    ' the screen is left and re-entered.
    m.showNetDiag = false
    m.testServerTaps = 0
    m.netDiagTask = invalid
    m.showDeviceCap = false
    m.deviceCapTask = invalid
    m.restoreStateOnReturn = false
end sub

function OnEnter(params as object) as void
    ' The language of the visit is settled FIRST, so the title and every row
    ' the rebuild below paints are already in the language the store has: a
    ' language changed anywhere since the last visit adopts here, the same
    ' moment, on entry. The title is set through the table rather than the
    ' node's XML default for the same reason — the XML literal is the English
    ' fallback, the table decides what is shown.
    RefreshTexts()
    m.title.text = Lang("settings", "title")
    CancelTestServer()
    CancelNetDiag()
    CancelDeviceCap()
    CancelAudioCap()
    CancelServerSettings()
    m.serverProfile = ""
    m.serverCacheSize = invalid
    m.serverCacheSizeChoices = []
    m.serverCacheSizeIndex = -1
    m.serverCacheSizeState = ""
    m.pendingCacheSize = invalid
    m.pendingWriteType = ""
    ' Fresh visits start at General. Returning from the Home Rows picker keeps
    ' the section and focused row that opened it, so Back lands in the same place.
    restoreState = false
    if params = invalid then restoreState = m.restoreStateOnReturn
    m.restoreStateOnReturn = false
    if not restoreState
        m.activeSection = 0
        m.focusedRow = -1
    end if
    ' The sections are rebuilt on entry rather than kept: the set of rows
    ' changes under the screen — the diagnostics appear, the account row
    ' changes what it does — and a section built when the screen was opened
    ' would show the state of that moment.
    RefreshSections()
    SetStatus("")
    m.list.callFunc("SetListFocus")
    UpdatePanel()
    ' The device is asked on entry, not on the toggle: the answer changes with
    ' the Roku's own audio settings, and the panel says what the device can do
    ' whether the option is on or off.
    StartAudioCap()
    ' The server is asked what profile it is running under, so the row tells
    ' the truth even when the profile was changed from another device.
    StartServerSettingsRead()
end function

function OnExit() as void
    CancelTestServer()
    CancelNetDiag()
    CancelDeviceCap()
    CancelAudioCap()
    CancelServerSettings()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' The status line, with the key it was written from.
'
' The line goes through SetStatus so the key travels with the words: a language
' change re-renders it from the key, instead of leaving a line in the language
' it happened to be written in. SetStatusRaw is for a line that is not ours to
' translate — a probe summary like "A=200 B=301 C=-7" — and it clears the key
' so a language change leaves that line alone.
'
' The optional suffix is a second key: "— not saved" rides along with a line
' that is about a write, and it is a word of its own, so it is a word of its
' own in the table.
'
' It lives here because the Settings screen is the only one with a status line
' today; the next screen that grows one moves this to Helpers.brs, which is
' included per component.
sub SetStatus(key as string, values = invalid as object, suffixKey = "" as string) as void
    m.statusKey = key
    m.statusValues = values
    m.statusSuffixKey = suffixKey
    m.status.text = StatusText()
end sub

sub SetStatusRaw(text as string) as void
    m.statusKey = ""
    m.statusValues = invalid
    m.statusSuffixKey = ""
    m.status.text = text
end sub

' A finished outcome as a toast instead of the status line: the line is for
' work still running, the toast for what it came back with. Clears the line
' it replaces.
sub NotifyStatus(key as string, values = invalid as object, kind = "info" as string, suffixKey = "" as string) as void
    m.statusKey = ""
    m.statusValues = invalid
    m.statusSuffixKey = ""
    m.status.text = ""
    text = Fill(Lang("settings", key), values)
    if suffixKey <> "" then text = text + Lang("common", suffixKey)
    if key = "statusInvalidAddress" then kind = "error"
    scene = m.top.getScene()
    if scene <> invalid then scene.callFunc("Notify", text, kind)
end sub

function StatusText() as string
    if m.statusKey = "" then return ""
    text = Fill(Lang("settings", m.statusKey), m.statusValues)
    if m.statusSuffixKey <> "" then text = text + Lang("common", m.statusSuffixKey)
    return text
end function

' Rebuild the sections and redraw the screen: the chips (whose names do not
' change, but whose selected one is marked on the content) and the list under
' them.
'
' This is for a change to the SET of rows — another section, or the
' diagnostics being revealed. A change to a VALUE goes through
' RefreshValues, which writes into the rows it already has.
sub RefreshSections()
    m.sections = SectionDefinitions()
    if m.activeSection >= m.sections.Count() then m.activeSection = 0
    BuildChips()
    BuildRows()
end sub

' The sections, in chip order. A section is an id and the ACTIONS of its
' rows — not what the rows say, and not what the section is called either.
' Both of those are read live (RowLabel, SectionLabel), so a section rebuilt
' in one language and painted in another cannot disagree with itself.
function SectionDefinitions() as object
    sections = []
    sections.Push({ id: "general", rows: ["account", "language"] })
    sections.Push({ id: "home", rows: ["homeRows"] })
    server = ["server", "audioPassthrough", "audioTransmux", "directPlay", "torrentProfile", "cacheSize", "testServer"]
    ' The two diagnostic rows are appended last and only once the gesture has
    ' revealed them, so they stay out of the way of the rows people use.
    if m.showNetDiag then server.Push("netdiag")
    if m.showDeviceCap then server.Push("devicecap")
    sections.Push({ id: "server", rows: server })
    return sections
end function

' What a section is called. Read live, for the same reason the row labels
' are: a label captured when the section was built goes stale the moment the
' language changes under it, and the chip row would keep speaking the old one
' while the rows beside it already speak the new one.
function SectionLabel(id as string) as string
    if id = "general" then return Lang("settings", "sectionGeneral")
    if id = "home" then return Lang("settings", "sectionHome")
    if id = "server" then return Lang("settings", "sectionServer")
    return id
end function

' What a row is called. The account row is the one whose name depends on the
' session, and it is a different NAME for the same row — the action is
' "account" either way, so the row set does not change when the user signs in.
function RowLabel(action as string) as string
    if action = "account" then
        if SignedIn() then return Lang("settings", "rowLogout")
        return Lang("settings", "rowLogin")
    else if action = "language" then
        return Lang("settings", "rowLanguage")
    else if action = "homeRows" then
        return Lang("settings", "rowHomeRows")
    else if action = "server" then
        return Lang("settings", "rowServer")
    else if action = "audioPassthrough" then
        return Lang("settings", "rowAudioPassthrough")
    else if action = "audioTransmux" then
        return Lang("settings", "rowAudioTransmux")
    else if action = "directPlay" then
        return Lang("settings", "rowDirectPlay")
    else if action = "torrentProfile" then
        return Lang("settings", "rowTorrentProfile")
    else if action = "cacheSize" then
        return Lang("settings", "rowCacheSize")
    else if action = "testServer" then
        return Lang("settings", "rowTestServer")
    else if action = "netdiag" then
        return Lang("settings", "rowNetDiag")
    else if action = "devicecap" then
        return Lang("settings", "rowDeviceCap")
    end if
    return action
end function

' What a row shows on the right. Read live, so the row and the panel beside
' it can never disagree.
'
' The account row says NOTHING on a guest session: the sentence explaining
' what signing in brings is too long to sit in a row's right-hand column
' (it does not even fit), and the side panel beside the row already says it
' — the panel is where a sentence belongs. A signed-in account shows who you
' are, which is short enough to fit and worth showing.
function RowValue(action as string) as string
    if action = "account" then
        if SignedIn() then return SessionValue()
        return ""
    else if action = "language" then
        return LanguageValue()
    else if action = "homeRows" then
        return Lang("settings", "valueHomeRows")
    else if action = "server" then
        return ServerValue()
    else if action = "audioPassthrough" then
        return AudioPassthroughValue()
    else if action = "audioTransmux" then
        return AudioTransmuxValue()
    else if action = "directPlay" then
        return DirectPlayValue()
    else if action = "torrentProfile" then
        return TorrentProfileValue()
    else if action = "cacheSize" then
        return CacheSizeValue()
    else if action = "testServer" then
        return Lang("settings", "valueTestServer")
    else if action = "netdiag" then
        return Lang("settings", "valueNetDiag")
    else if action = "devicecap" then
        return Lang("settings", "valueDeviceCap")
    end if
    return ""
end function

function SignedIn() as boolean
    if m.stores = invalid then return false
    return m.stores.auth.callFunc("AuthGetSession") = "stremio"
end function

' The chip row: one chip per section, in the order the sections are defined.
' The selected chip is marked `active`, and ChipTile paints that one in the
' accent — so the row above and the list below always agree about which
' section is on screen, even when the focus is somewhere else.
sub BuildChips()
    entries = []
    for i = 0 to m.sections.Count() - 1
        entries.Push({ title: SectionLabel(m.sections[i].id), active: (i = m.activeSection) })
    end for
    m.chips.callFunc("SetChips", entries)
end sub

' The list under the chips: the rows of the selected section and nothing else.
' Built once per section, and each row's content node is kept, so a value
' that changes can be written into the row instead of rebuilding the list.
sub BuildRows()
    m.rows = []
    m.rowNodes = {}
    if m.sections.Count() = 0 then
        m.sub.text = ""
        return
    end if
    section = m.sections[m.activeSection]
    for each action in section.rows
        m.rows.Push(action)
    end for

    content = CreateObject("roSGNode", "ContentNode")
    for each action in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("ContentNode")
        item.title = RowLabel(action)
        item.description = RowValue(action)
        m.rowNodes[action] = item
    end for
    m.list.focusRow = m.focusedRow
    if m.list.focusRow < 0 then m.list.focusRow = 0
    m.list.content = content
    UpdateSectionTitle()
end sub

' Write the current values into the rows. The list is NOT rebuilt: replacing
' a list's content resets its focus to the first row, and a setting that
' changes is not a reason to move the cursor. The rows watch their own
' content nodes, so writing into them is enough to repaint.
sub RefreshValues()
    for each action in m.rows
        node = m.rowNodes[action]
        if node = invalid then continue for
        node.title = RowLabel(action)
        node.description = RowValue(action)
    end for
end sub

' The subtitle names the section on screen and says what the keys do. It is
' rebuilt with the rows, because a screen whose subtitle says "General" while
' it shows the server rows is worse than no subtitle at all.
'
' It says OK twice on purpose: OK on a chip and OK on a row are different
' presses on different things, and the sentence that blurred them ("OK edits a
' row's value") is what a reader has to un-apply to the chip row.
sub UpdateSectionTitle()
    if m.sections.Count() = 0 then return
    m.sub.text = Fill(Lang("settings", "subTitleLine"), { section: SectionLabel(m.sections[m.activeSection].id) })
end sub

' OK on a chip: show that section's rows. The focus stays on the chips, so
' another section is one press away and the rows are one press down — the
' same travel Discover uses between its filter chips and its results.
sub onChipSelected()
    index = m.chips.selection
    if index < 0 or index >= m.sections.Count() then return
    if index = m.activeSection then return
    m.activeSection = index
    ' A new section starts at its first row: the old index meant a different
    ' row over there, and keeping it would put the cursor on whatever happens
    ' to sit at that number in the new list.
    m.focusedRow = -1
    RefreshSections()
    UpdatePanel()
end sub

' Focus travel between the sections and the rows under them. Up from the rows
' reaches the chips and Down from the chips comes back; the asterisk key is a
' one-press way up from anywhere in the list. Discover travels the same way
' between its filter chips and its results, and the same question applies to
' both: a screen that owns a secondary focus has to say where the focus is
' allowed to go, or the user is stuck in one of the two places.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up" and m.list.callFunc("HasListFocus") then
        m.chips.callFunc("FocusChip", -1)
        return true
    else if key = "down" and m.chips.callFunc("HoldingFocus") then
        m.chips.callFunc("Blur")
        m.list.callFunc("SetListFocus")
        return true
    else if key = "options" and m.list.callFunc("HasListFocus") then
        m.chips.callFunc("FocusChip", -1)
        return true
    end if
    return false
end function

' The signed-in-account label for the logout row. Prefer the profile email;
' fall back to a neutral label when the fetch that fills it is still running or
' the profile is otherwise absent.
function SessionValue() as string
    if m.stores <> invalid
        user = m.stores.auth.callFunc("AuthGetUser")
        if user <> invalid and user.email <> invalid and user.email <> "" then return user.email
    end if
    return Lang("settings", "valueSessionDefault")
end function

function ServerValue() as string
    if m.stores = invalid then return "—"
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = "" then return Lang("common", "notSet")
    return address
end function

' The language row's right column: the language under its own name. The names
' come from the table (kept identical in every language — a language is called
' what it calls itself), so an untranslated code still shows its name once its
' entries land. An entry the table does not name shows the raw code; there is
' nothing else honest to say.
function LanguageValue() as string
    if m.stores = invalid then return ""
    language = m.stores.settings.callFunc("SettingsGetLanguage")
    if language = "es" then return Lang("common", "langEs")
    if language = "en" then return Lang("common", "langEn")
    return language
end function

' One of the audio copy options: the codecs it would offer, or Off. The
' codecs come from the probe, and they are what the option is FOR — the value
' is the consequence, not a boolean.
'
' The callFunc names are literals on purpose: the static check that catches a
' mistyped callFunc is what stands between a typo and the device's &hf4.
function AudioPassthroughValue() as string
    if m.stores = invalid then return Lang("common", "off")
    if not m.stores.settings.callFunc("SettingsGetAudioPassthrough") then return Lang("common", "off")
    return AudioCodecsValue(m.passthruCodecs)
end function

function AudioTransmuxValue() as string
    if m.stores = invalid then return Lang("common", "off")
    if not m.stores.settings.callFunc("SettingsGetAudioTransmux") then return Lang("common", "off")
    return AudioCodecsValue(m.transmuxCodecs)
end function

function DirectPlayValue() as string
    if m.stores = invalid then return Lang("common", "off")
    mode = m.stores.settings.callFunc("SettingsGetDirectPlayMode")
    if mode = "on" then return Lang("common", "on")
    if mode = "ask" then return Lang("settings", "valueDirectAsk")
    return Lang("common", "off")
end function

' The codecs an option would offer, or the state of the probe that answers it.
function AudioCodecsValue(codecs as object) as string
    if codecs = invalid then return Lang("common", "on")
    if codecs.Count() = 0 then return Lang("common", "nothingToCopy")
    return CodecLabelList(codecs)
end function

' The display names of a codec list, comma separated. The names the server
' compares against are ffprobe's, and "ac3" is not how a person writes Dolby
' Digital.
function CodecLabelList(codecs as object) as string
    text = ""
    for each codec in codecs
        if text <> "" then text = text + ", "
        text = text + AudioCodecLabel(codec)
    end for
    return text
end function

' The side panel follows the focused row and explains it. The audio options
' are the ones that need it: what they do, which codecs they would offer, and
' — for the transmux one — what has not been tested.
'
' The panel is a reader, not a narrator: the row already says what the option
' is set to, so the body says what the option MEANS.
sub onRowFocused()
    data = m.list.rowItemFocused
    if data = invalid or data.Count() < 2 then return
    m.focusedRow = data[0]
    UpdatePanel()
end sub

sub UpdatePanel()
    if m.sections.Count() = 0 then return
    section = m.sections[m.activeSection]
    action = PanelActionForFocus()
    if action = "" then
        m.infoTitle.text = SectionLabel(section.id)
        m.infoBody.text = ""
        m.infoWarn.text = ""
        m.infoWarn.visible = false
        return
    end if
    m.infoTitle.text = RowLabel(action)
    m.infoBody.text = PanelBody(action)
    warning = PanelWarning(action)
    m.infoWarn.text = warning
    m.infoWarn.visible = warning <> ""
end sub

' The action of the focused row, or "" when the focus is not on a row of the
' current section. The list's focus index is not a field, so the row is found
' by the one the screen last focused on.
function PanelActionForFocus() as string
    if m.focusedRow < 0 or m.focusedRow >= m.rows.Count() then return ""
    return m.rows[m.focusedRow]
end function

' The body of the panel for one row. The text is the app's only chance to say
' what an option does, so the audio ones carry the honest version: what it
' does, who decodes it, and what is untested.
'
' The codec names are wrapped in the bold style, so the sentence reads as a
' sentence and the names read as names.
function PanelBody(action as string) as string
    if action = "audioPassthrough" then
        body = Lang("settings", "panelPassthrough")
        body = body + " " + AudioEligibility("eligibilitySubjectPassthru", m.passthruCodecs)
        body = body + " " + Lang("settings", "panelPassthroughNote")
        return body
    else if action = "audioTransmux" then
        body = Lang("settings", "panelTransmux")
        body = body + " " + AudioEligibility("eligibilitySubjectTransmux", m.transmuxCodecs)
        return body
    else if action = "directPlay" then
        return Lang("settings", "panelDirectPlay")
    else if action = "torrentProfile" then
        body = Lang("settings", "panelTorrentProfile")
        body = body + " " + TorrentProfileLimitsText()
        return body
    else if action = "cacheSize" then
        return Lang("settings", "panelCacheSize")
    else if action = "server" then
        return Lang("settings", "panelServer")
    else if action = "language" then
        return Lang("settings", "panelLanguage")
    else if action = "homeRows" then
        return Lang("settings", "panelHomeRows")
    else if action = "testServer" then
        return Lang("settings", "panelTestServer")
    else if action = "account" then
        if SignedIn() then return Lang("settings", "panelAccountOut")
        return Lang("settings", "panelAccountIn")
    else if action = "netdiag" then
        return Lang("settings", "panelNetDiag")
    else if action = "devicecap" then
        return Lang("settings", "panelDeviceCap")
    end if
    return ""
end function

' Whether the device can use an option at all, and what it reports. The empty
' case is worth saying out loud: a row that cannot do anything is a question
' the user would otherwise have to ask somewhere else.
'
' The subject travels as a key, not a sentence — both subjects are sentences of
' the table ("Your sound system reports…", "This Roku reports…"), so a language
' that orders them differently has as much freedom as any other string.
function AudioEligibility(subjectKey as string, codecs as object) as string
    subject = Lang("settings", subjectKey)
    if codecs = invalid then return Lang("common", "askingDevice")
    if codecs.Count() = 0 then
        return Fill(Lang("settings", "eligibilityEmptyLine"), { subject: subject, empty: Lang("settings", "eligibilityEmpty") })
    end if
    return Fill(Lang("settings", "eligibilityCodecs"), { subject: subject, codecs: CodecLabelList(codecs) })
end function

' Whether the focused option is one this device cannot use. The line is a
' warning, so it is red and separate from the sentence below it.
function PanelWarning(action as string) as string
    if action = "audioPassthrough" then
        if m.passthruCodecs = invalid or m.passthruCodecs.Count() > 0 then return ""
        return Lang("settings", "warnNotEligible")
    else if action = "audioTransmux" then
        if m.transmuxCodecs = invalid or m.transmuxCodecs.Count() > 0 then return ""
        return Lang("settings", "warnNotEligible")
    else if action = "torrentProfile" then
        if m.serverProfile = "custom" then return Lang("settings", "warnProfileCustom")
        if m.serverProfile = "unknown" then return Lang("settings", "warnProfileUnknown")
    else if action = "cacheSize" then
        if m.serverCacheSizeState = "notavailable" then return Lang("settings", "warnCacheNotAvailable")
        if m.serverCacheSizeState = "unknown" then return Lang("settings", "warnProfileUnknown")
        if m.serverCacheSizeState = "custom" then return Lang("settings", "warnCacheCustom")
    end if
    return ""
end function

' The display name of a codec.
function AudioCodecLabel(codec as string) as string
    if codec = "ac3" then return "AC-3"
    if codec = "eac3" then return "E-AC-3"
    if codec = "dts" then return "DTS"
    if codec = "aac" then return "AAC"
    if codec = "mp3" then return "MP3"
    if codec = "flac" then return "FLAC"
    if codec = "alac" then return "ALAC"
    if codec = "opus" then return "Opus"
    if codec = "vorbis" then return "Vorbis"
    return codec
end function

' The two audio copy options, on and off. Both are off by default: the
' device reports AC-3 and some sound systems do not reproduce it, so this is
' the user's call.
'
' The device is NOT asked again here. It was asked when the screen was opened,
' and its answer does not change because a setting was flipped — asking again
' put the panel back to "asking the device" for a moment and rebuilt the list
' a second time, which is what threw the cursor to the first row.
sub ToggleAudioPassthrough()
    if m.stores = invalid then return
    current = m.stores.settings.callFunc("SettingsGetAudioPassthrough")
    if m.stores.settings.callFunc("SettingsSetAudioPassthrough", not current)
        ReportSaveFault()
        RefreshValues()
        UpdatePanel()
    end if
end sub

sub ToggleAudioTransmux()
    if m.stores = invalid then return
    current = m.stores.settings.callFunc("SettingsGetAudioTransmux")
    if m.stores.settings.callFunc("SettingsSetAudioTransmux", not current)
        ReportSaveFault()
        RefreshValues()
        UpdatePanel()
    end if
end sub

' Cycle the three direct-play states forward: On -> Ask first -> Off. The
' cycle order puts Ask first in the middle, so one extra press from On
' lands on the safe choice rather than on always-remux.
sub ToggleDirectPlay()
    if m.stores = invalid then return
    current = m.stores.settings.callFunc("SettingsGetDirectPlayMode")
    nextMode = "ask"
    if current = "on"
        nextMode = "ask"
    else if current = "ask"
        nextMode = "off"
    else if current = "off"
        nextMode = "on"
    end if
    if m.stores.settings.callFunc("SettingsSetDirectPlayMode", nextMode)
        ReportSaveFault()
        RefreshValues()
        UpdatePanel()
    end if
end sub

' The torrent profile is the SERVER's setting, not this Roku's: it is a set of
' limits for the server's BitTorrent engine, and the server keeps them in its
' own settings. So the row writes the profile's six limits into the server and
' then says what the server reports — the row never remembers what it wrote
' and calls that the truth.
'
' OK moves to the next profile, the same way the language row moves to the
' next language.
sub CycleTorrentProfile()
    if m.stores = invalid then return
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = ""
        NotifyStatus("statusSetServerFirst")
        return
    end if
    nextId = TorrentProfileNext(m.serverProfile)
    profile = TorrentProfileById(nextId)
    if profile = invalid then return
    ' One write at a time. A second press would launch a second task and
    ' leave the first one running with nobody watching its answer.
    if m.serverSettingsTask <> invalid then return
    m.pendingProfile = nextId
    SetStatus("statusSettingProfile", { profile: profile.full })
    m.serverSettingsTask = AsyncTask_Launch(m.top, "ServerSettingsTask", "onServerSettingsWritten", {
        address: address
        mode: "set"
        values: profile.values
    }, "serverSettingsTask")
end sub

' Current value written back by the server, not what was asked for.
sub onServerSettingsWritten()
    if m.serverSettingsTask = invalid then return
    task = m.serverSettingsTask
    result = task.result
    ' The alwaysNotify result can arrive before the worker has written
    ' anything, so an empty one is dropped and the task waits for the real one.
    if result = invalid then return
    m.serverSettingsTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if not result.ok
        if m.pendingWriteType = "cacheSize"
            NotifyStatus("statusCouldNotCache", { error: result.error }, "error")
        else
            NotifyStatus("statusCouldNotProfile", { error: result.error }, "error")
        end if
        m.pendingWriteType = ""
        return
    end if
    ' The row reports the new value itself, so the status line only speaks on
    ' a fault — a success line here would repeat the row one line below it.
    if m.pendingWriteType = "cacheSize"
        if m.pendingCacheSize <> invalid
            value = m.pendingCacheSize.value
            if value = invalid then value = -1
            ApplyCacheSize(m.serverCacheSizeChoices, value)
            SetStatus("")
        end if
        m.pendingWriteType = ""
        RefreshValues()
        UpdatePanel()
        return
    end if
    m.serverProfile = m.pendingProfile
    SetStatus("")
    m.pendingWriteType = ""
    RefreshValues()
    UpdatePanel()
end sub

' Ask the server what profile it is running under.
'
' The row is built before the answer lands, so it says "…" until it does. A
' server that cannot be asked is not an error the user has to act on here —
' the row says "Unknown" and the panel's warning line says why.
sub StartServerSettingsRead()
    CancelServerSettings()
    if m.stores = invalid then return
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = ""
        m.serverProfile = ""
        m.serverCacheSizeState = "unknown"
        return
    end if
    m.serverProfile = ""
    m.serverCacheSizeState = ""
    m.serverSettingsTask = AsyncTask_Launch(m.top, "ServerSettingsTask", "onServerSettingsRead", {
        address: address
        mode: "get"
    }, "serverSettingsTask")
end sub

' The server's answer.
sub onServerSettingsRead()
    if m.serverSettingsTask = invalid then return
    task = m.serverSettingsTask
    result = task.result
    if result = invalid then return
    m.serverSettingsTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if not result.ok
        m.serverProfile = "unknown"
        m.serverCacheSizeState = "unknown"
        m.serverCacheSizeChoices = []
        m.serverCacheSizeIndex = -1
    else
        m.serverProfile = TorrentProfileMatch(result.values)
        if m.serverProfile = "" then m.serverProfile = "custom"
        ApplyCacheSize(CacheSizeChoices(result.options), result.cacheSize)
    end if
    RefreshValues()
    UpdatePanel()
end sub

sub CycleCacheSize()
    if m.stores = invalid then return
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = ""
        NotifyStatus("statusSetServerFirst")
        return
    end if
    if m.serverCacheSizeChoices = invalid or m.serverCacheSizeChoices.Count() = 0
        NotifyStatus("warnCacheNotAvailable", invalid, "error")
        return
    end if
    if m.serverSettingsTask <> invalid then return
    nextIdx = CacheSizeNextIndex(m.serverCacheSizeChoices, m.serverCacheSizeIndex)
    choice = m.serverCacheSizeChoices[nextIdx]
    m.pendingCacheSize = choice
    m.pendingWriteType = "cacheSize"
    SetStatus("statusSettingCache", { size: choice.label })
    m.serverSettingsTask = AsyncTask_Launch(m.top, "ServerSettingsTask", "onServerSettingsWritten", {
        address: address
        mode: "set"
        bodyText: CacheSizeBody(choice)
    }, "serverSettingsTask")
end sub

' Where the server's cache size stands against its own choices: the fields
' the row and the panel read, set in one place so the read and the write
' paths cannot drift apart.
sub ApplyCacheSize(choices as object, current as dynamic)
    m.serverCacheSizeChoices = choices
    m.serverCacheSize = current
    m.serverCacheSizeIndex = CacheSizeIndexForValue(choices, current)
    m.serverCacheSizeState = ""
    if choices = invalid or choices.Count() = 0
        m.serverCacheSizeState = "notavailable"
    else if m.serverCacheSizeIndex < 0
        m.serverCacheSizeState = "custom"
        if current = invalid then m.serverCacheSizeState = "unknown"
    end if
end sub

sub CancelServerSettings()
    if m.serverSettingsTask = invalid then return
    task = m.serverSettingsTask
    m.serverSettingsTask = invalid
    AsyncTask_Reap(task, m.top, true)
end sub

' What the server is running under, in the row's own words.
'
' The server holds this, not the Roku: the row says what the server reports
' and never what it last wrote, so the two cannot disagree.
function TorrentProfileValue() as string
    if m.stores = invalid then return Lang("common", "noServer")
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = "" then return Lang("common", "noServer")
    if m.serverProfile = "" then return "…"
    if m.serverProfile = "unknown" then return Lang("common", "unknown")
    if m.serverProfile = "custom" then return Lang("common", "custom")
    label = TorrentProfileLabel(m.serverProfile)
    if label = "" then return Lang("common", "custom")
    return label
end function

function CacheSizeValue() as string
    if m.stores = invalid then return Lang("common", "noServer")
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = "" then return Lang("common", "noServer")
    if m.serverCacheSizeState = "unknown" then return Lang("common", "unknown")
    if m.serverCacheSizeState = "notavailable" then return Lang("common", "notAvailable")
    if m.serverCacheSizeIndex >= 0
        choice = m.serverCacheSizeChoices[m.serverCacheSizeIndex]
        if choice <> invalid then return choice.label
    end if
    if m.serverCacheSize <> invalid and m.serverCacheSize < 0 then return Chr(8734)
    if m.serverCacheSizeState = "custom" then return Lang("common", "custom")
    if m.serverCacheSize <> invalid then return CacheSizeBytesToLabel(m.serverCacheSize)
    if m.serverCacheSizeState = "" then return "…"
    return Lang("common", "unknown")
end function

' The limits the server is running under, in the panel's words. Nothing to say
' when the server is running limits that match no profile.
function TorrentProfileLimitsText() as string
    profile = TorrentProfileById(m.serverProfile)
    if profile = invalid then return ""
    values = profile.values
    return Fill(Lang("settings", "profileLimits"), {
        connections: values.btMaxConnections.ToStr()
        peers: values.btMinPeersForStable.ToStr()
        soft: TorrentSpeedText(values.btDownloadSpeedSoftLimit)
        hard: TorrentSpeedText(values.btDownloadSpeedHardLimit)
    })
end function

' A byte rate in MB/s, the way a person would say it.
'
' Tenths of a megabyte, worked out in whole numbers: the byte rates are exact
' multiples of a tenth of a megabyte, and a float division of them is not
' (2.5 comes out as 2.4999999 and rounds to the wrong tenth).
function TorrentSpeedText(bytes as dynamic) as string
    if bytes = invalid then return "?"
    tenths = Int(bytes * 10 / 1048576)
    whole = Int(tenths / 10)
    frac = tenths - whole * 10
    return whole.ToStr() + "." + frac.ToStr() + " MB/s"
end function

' Ask the device which codecs it takes. roDeviceInfo is Task-only, so this is
' a task. It runs on entry whether an option is on or off, because the panel
' says what the device can do either way.
sub StartAudioCap()
    CancelAudioCap()
    if m.stores = invalid then return
    m.audioCapTask = AsyncTask_Launch(m.top, "AudioCapTask", "onAudioCapResult", {}, "audioCapTask")
end sub

' The probe landed. The rows show the codecs, so the list is rebuilt.
'
' The alwaysNotify result can arrive before the worker has written anything, so
' an invalid result is dropped and only a finished one reaps the task — the
' same dance as every other alwaysNotify field in this app.
sub onAudioCapResult()
    if m.audioCapTask = invalid then return
    task = m.audioCapTask
    result = task.result
    if result = invalid then return
    if not result.done then return
    m.audioCapTask = invalid
    AsyncTask_Reap(task, m.top, false)
    m.passthruCodecs = result.passthru
    if m.passthruCodecs = invalid then m.passthruCodecs = []
    m.transmuxCodecs = result.transmux
    if m.transmuxCodecs = invalid then m.transmuxCodecs = []
    RefreshValues()
    UpdatePanel()
end sub

sub CancelAudioCap()
    if m.audioCapTask <> invalid
        task = m.audioCapTask
        m.audioCapTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    ' Remembered so a rebuild can put the cursor back on this row.
    m.focusedRow = index
    action = m.rows[index]
    if action = "account"
        if SignedIn() then SignOut() else SignIn()
    else if action = "homeRows"
        OpenHomeRows()
    else if action = "server"
        EditServer()
    else if action = "language"
        CycleLanguage()
    else if action = "audioPassthrough"
        ToggleAudioPassthrough()
    else if action = "audioTransmux"
        ToggleAudioTransmux()
    else if action = "directPlay"
        ToggleDirectPlay()
    else if action = "torrentProfile"
        CycleTorrentProfile()
    else if action = "cacheSize"
        CycleCacheSize()
    else if action = "testServer"
        ' Counted here rather than inside TestServer so every press is counted,
        ' including the presses that TestServer itself declines to act on —
        ' a tap that gets rejected for a missing address is still a tap, and the
        ' gesture should not need the server to be configured to reach.
        m.testServerTaps = m.testServerTaps + 1
        if m.testServerTaps >= 5 and not m.showNetDiag
            m.showNetDiag = true
            m.showDeviceCap = true
            ' The diagnostics are rows of the Server section, and the section
            ' was built before the gesture revealed them — so the section is
            ' rebuilt, not just the list, or the new rows never appear.
            RefreshSections()
            NotifyStatus("statusDiagAdded")
        end if
        TestServer()
    else if action = "netdiag"
        RunNetDiag()
    else if action = "devicecap"
        RunDeviceCap()
    end if
end sub

' The session actions hand off to the Scene, the only place that owns auth.
' Publishing through pushRequest keeps this screen a pure reporter — the Scene
' runs the link-code flow or the logout confirm/teardown.
sub SignIn()
    m.top.pushRequest = { action: "login" }
end sub

sub SignOut()
    m.top.pushRequest = { action: "logout" }
end sub

' The catalog picker is a separate screen because its rows are dynamic and can
' be numerous; Settings remains a concise list of setting categories.
sub OpenHomeRows()
    m.restoreStateOnReturn = true
    m.top.pushRequest = { screen: "homeRowsScreen", params: {} }
end sub

' Open the streaming server editor. Empty input clears the address (clearing is
' a deliberate action); anything else is validated by SettingsStore.
sub EditServer()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    ' A StandardDialog takes its colours from its own palette field and, with
    ' none set, from whatever is higher in the scene graph. Nothing in this app
    ' sets one — the Scene included — so without this the prompt comes up in
    ' Roku's default grey over a themed app. Same palette the exit and support
    ' dialogs already ask for.
    dialog.title = Lang("settings", "serverAddressTitle")
    ' message is an ARRAY of strings on StandardKeyboardDialog. A bare string is
    ' a wrong-typed field set: discarded with a warning, leaving the prompt with
    ' no help text under the title and nothing on screen to explain why.
    dialog.message = [Lang("settings", "serverAddressHelp")]
    dialog.text = ""
    if m.stores <> invalid then dialog.text = m.stores.settings.callFunc("SettingsGetServerAddress")
    dialog.buttons = [Lang("common", "ok"), Lang("common", "cancel")]
    dialog.observeField("buttonSelected", "onServerChoice")
    ' Caret after the address rather than at 0, so editing it does not start by
    ' arrowing past the whole value. Before the dialog is shown: the internal
    ' edit box is built at CreateObject time, so this is the earliest the setting
    ' can land. See ApplyServerKeyboard.
    ApplyServerKeyboard(dialog)
    m.top.getScene().dialog = dialog
end sub

' Configures the dialog's internal VoiceTextEditBox, which StandardKeyboardDialog
' builds for itself and which is therefore reached through the dialog rather than
' owned here. The box exists as soon as the node is created — confirmed on
' device — so this is called inline and needs nothing to wait for.
'
' No try, deliberately. A throw here prints the offending field and line to the
' device console, and the console is where this is read. The previous version
' swallowed the error, which is how a caret fix that never took became
' indistinguishable from one that did.
sub ApplyServerKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = dialog.textEditBox
    if editor = invalid then return

    ' Dictation mode, and the reason voice came out one letter at a time.
    ' DynamicKeyboard builds its internal edit box with voiceEntryType
    ' "alphanumeric" — letter-by-letter, meant for street addresses — which
    ' beats the node class default of "generic". The dialog's own
    ' keyboardDomain defaults to "generic" too but does not reach this field.
    ' "generic" is full word input, which is what a text prompt wants. First, so
    ' it lands even if the caret write below is the thing being rejected.
    editor.voiceEntryType = "generic"
    ' Caret after the text rather than at 0, so backspace and the left arrow have
    ' something to act on: a caret parked at 0 makes both of them no-ops by
    ' definition while typing still appends, which from the outside is
    ' indistinguishable from a dead keyboard.
    editor.cursorPosition = Len(dialog.text)
end sub

sub onServerChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        chosen = dialog.text
        ' StandardDialog's own dismissal, and the one the exit confirm already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        dialog.close = true
        if index = 0
            if chosen = invalid or chosen.Trim() = ""
                m.stores.settings.callFunc("SettingsClearServerAddress")
                statusKey = "statusServerCleared"
            else if m.stores.settings.callFunc("SettingsSetServerAddress", chosen)
                statusKey = "statusServerUpdated"
            else
                statusKey = "statusInvalidAddress"
            end if
            ' Every branch above ends in a write, so the result is the same
            ' question on all of them: did the registry take it? Asked here
            ' rather than after each setter because the store saves itself now
            ' and there is no per-setter answer to check. The "— not saved" is
            ' a suffix of its own, so it is a key of its own: the line is
            ' written once, from the key, and the suffix rides along with it.
            suffixKey = ""
            if m.stores.settings.callFunc("SettingsSaveFailed") then suffixKey = "notSavedSuffix"
            NotifyStatus(statusKey, invalid, "info", suffixKey)
            ReportSaveFault()
            RefreshValues()
        end if
    end if
    m.list.callFunc("SetListFocus")
end sub

' Mirrors the store's last write result into the Scene's fault strip, clearing
' it on the next success. The status line says what just happened on this
' screen; the strip is what a refused write looks like from anywhere else in the
' app, including after the user has navigated away — which is the only place a
' setting that did not save can be noticed, since nothing about it is wrong
' until the next launch.
sub ReportSaveFault()
    if m.stores = invalid then return
    failed = m.stores.settings.callFunc("SettingsSaveFailed")
    scene = m.top.getScene()
    if scene <> invalid and failed then scene.callFunc("Notify", "settings could not be saved", "error")
end sub

' Repaint the whole screen in the language the store holds.
'
' The one place a language change is acted on. The title, the section chips,
' the rows, the subtitle and the side panel all read their words from the
' table, so re-pulling the slices and asking every one of them to paint again
' is the whole job — and it is the same job on entry (OnEnter refreshes the
' slices and then rebuilds the screen anyway).
'
' The LIST is not rebuilt: the rows write into their own content nodes
' (RefreshValues), so the cursor stays exactly where the user pressed —
' including on the language row itself. The chips are rebuilt because a chip
' holds its own title, and the chip row is not where the cursor is.
sub ApplyLanguage() as void
    RefreshTexts()
    m.title.text = Lang("settings", "title")
    BuildChips()
    RefreshValues()
    UpdateSectionTitle()
    UpdatePanel()
    ' The status line is re-rendered from its key — but only when it HAS one:
    ' a raw line (a probe summary) is not ours to translate and must survive
    ' the language change as it is.
    if m.statusKey <> "" then m.status.text = StatusText()
end sub

' Cycle the language row's options forward.
'
' The toggle repaints the screen IN THE MOMENT, because the row the user just
' pressed is also the proof the setting applied: the slices are re-pulled, and
' the title, chips, rows, subtitle and side panel re-read them. Nothing is
' rebuilt as a LIST (the row values still go through RefreshValues into their
' own content nodes), so the cursor stays exactly where the user pressed —
' including on the language row itself. The other screens adopt the language
' on their next entry, which is where their OnEnter will RefreshTexts().
sub CycleLanguage() as void
    current = m.stores.settings.callFunc("SettingsGetLanguage")
    index = 0
    for i = 0 to m.languages.Count() - 1
        if m.languages[i] = current then index = i
    end for
    nextLanguage = m.languages[(index + 1) mod m.languages.Count()]
    if m.stores.settings.callFunc("SettingsSetLanguage", nextLanguage)
        ReportSaveFault()
        ApplyLanguage()
    end if
end sub

' Report the streaming server's reachability through the status line. Verifying
' the address before trying to play a torrent stream turns a 90-second playback
' dead-end into a quick, obvious check. The heartbeat rides the default request
' timeout, so it runs through HeartbeatTask — a dead address costs the worker
' thread, not a frozen Settings screen.
sub TestServer() as void
    if m.stores = invalid then return
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = ""
        NotifyStatus("statusSetServerFirst")
        return
    end if
    if m.heartbeatTask <> invalid then return

    SetStatus("statusTesting")
    task = AsyncTask_Launch(m.top, "HeartbeatTask", "onTestServerResult", { address: address }, "heartbeatTask")
    m.heartbeatTask = task
end sub

' The heartbeat finished. A stale result that landed after CancelTestServer is
' dropped by the m.heartbeatTask guard.
sub onTestServerResult()
    if m.heartbeatTask = invalid then return
    task = m.heartbeatTask
    m.heartbeatTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result.alive
        NotifyStatus("statusServerOk")
    else
        NotifyStatus("statusServerUnreachable", { error: result.error }, "error")
    end if
end sub

sub CancelTestServer()
    if m.heartbeatTask <> invalid
        task = m.heartbeatTask
        m.heartbeatTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' TEMPORARY. Launch the four-probe HTTPS diagnostic. The server address is read
' here and handed over rather than read inside the task, because the task is
' scoped to the component and SettingsStore is not — this is the same handoff
' HeartbeatTask's "address" field exists for.
sub RunNetDiag()
    if m.netDiagTask <> invalid then return
    address = ""
    if m.stores <> invalid then address = m.stores.settings.callFunc("SettingsGetServerAddress")

    SetStatus("statusRunningDiag")
    m.netDiagTask = AsyncTask_Launch(m.top, "NetDiagTask", "onNetDiagResult", { serverAddress: address }, "netDiagTask")
end sub

' Fires once per probe as well as once at the end, so the summary fills in
' progressively instead of appearing all at once. The done flag is what
' distinguishes the two: an alwaysNotify field with no value can notify before
' the worker has written anything, and reaping on that would pull the task out
' from under a run that is still going. An invalid result is the same case and is
' dropped for the same reason.
'
' Only the compact "A=200 B=301 C=-7 D=200" summary goes on screen. The verdict
' is a full sentence and settingsStatus is a single unfilled line, so the prose
' would be clipped; it is printed to the console instead, where the reader
' already is. C against D is readable from the summary either way.
sub onNetDiagResult()
    if m.netDiagTask = invalid then return
    task = m.netDiagTask
    result = task.result
    if result = invalid then return
    if result.done
        m.netDiagTask = invalid
        AsyncTask_Reap(task, m.top, false)
    end if
    SetStatusRaw(result.summary)
end sub

sub CancelNetDiag()
    if m.netDiagTask <> invalid
        task = m.netDiagTask
        m.netDiagTask = invalid
        ' Best effort. STOP and RemoveChild are synchronous on this thread while
        ' the worker checks the flag on its own, so it may or may not see this
        ' before the node goes away. It is worth setting because the flag is
        ' checked BETWEEN probes, and the alternative is a reaped node running
        ' three more five-second transfers against a screen nobody is watching.
        task.cancelRequested = true
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' TEMPORARY. Launch the device capability probe. Unlike NetDiag there is no
' per-device input to hand over — the task reads roDeviceInfo itself — so the
' launch carries no fields.
sub RunDeviceCap()
    if m.deviceCapTask <> invalid then return
    SetStatus("statusProbingCodecs")
    m.deviceCapTask = AsyncTask_Launch(m.top, "DeviceCapTask", "onDeviceCapResult", {}, "deviceCapTask")
end sub

' The same alwaysNotify / done dance as onNetDiagResult, for the same reason: an
' alwaysNotify field can notify before the worker has written anything, so an
' invalid result is dropped and only done = true reaps the task. The summary is a
' single unfilled line and would clip the per-codec detail, so only the compact
' list goes on screen; the raw replies stay on the console, where the reader is.
sub onDeviceCapResult()
    if m.deviceCapTask = invalid then return
    task = m.deviceCapTask
    result = task.result
    if result = invalid then return
    if result.done
        m.deviceCapTask = invalid
        AsyncTask_Reap(task, m.top, false)
    end if
    SetStatusRaw(result.summary)
end sub

sub CancelDeviceCap()
    if m.deviceCapTask <> invalid
        task = m.deviceCapTask
        m.deviceCapTask = invalid
        ' Best effort, as with CancelNetDiag: STOP does not reach a probe already
        ' in flight, but the flag is read between probes, so a cancelled run ends
        ' after the current one rather than finishing the whole sweep.
        task.cancelRequested = true
        AsyncTask_Reap(task, m.top, true)
    end if
end sub
