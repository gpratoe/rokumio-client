' Thin orchestrator.
'
' MainScene owns exactly three things and nothing else:
'   1. the ScreenStack,
'   2. Back routing (top screen first; the stack pops when it declines),
'   3. store instantiation and action dispatch.
'
' Zero business logic lives here. Everything else is in a screen or a store.
sub init()
    m.stack = ScreenStack(m.top)
    m.homeScreen = m.top.FindNode("homeScreen")
    m.homeScreen.ObserveField("pushRequest", "onHomeAction")

    ' Details pushes its own actions (episode selection, movie Play) up through
    ' the same one-action channel Home uses.
    m.detailsScreen = m.top.FindNode("detailsScreen")
    m.detailsScreen.ObserveField("pushRequest", "onDetailsAction")

    ' EpisodesScreen (the series episode browser) reports episode selections
    ' through the same one-action channel.
    m.episodesScreen = m.top.FindNode("episodesScreen")
    m.episodesScreen.ObserveField("pushRequest", "onEpisodesAction")

    ' StreamsScreen reports the player push after a stream is resolved; the
    ' player itself never pushes — Back pops it. The player is NOT a static child
    ' anymore: it is built from scratch per play and destroyed on pop (see
    ' onStreamsAction), so this Scene only needs StreamsScreen here.
    m.streamsScreen = m.top.FindNode("streamsScreen")
    m.streamsScreen.ObserveField("pushRequest", "onStreamsAction")

    ' SettingsScreen, AddonsScreen and SearchScreen are content-focused (no
    ' pushes of their own; Search pushes Details like the others). SearchScreen
    ' reports its pushes through its own channel.
    m.settingsScreen = m.top.FindNode("settingsScreen")
    m.addonsScreen = m.top.FindNode("addonsScreen")
    m.searchScreen = m.top.FindNode("searchScreen")
    m.searchScreen.ObserveField("pushRequest", "onSearchAction")
    m.discoverScreen = m.top.FindNode("discoverScreen")
    m.discoverScreen.ObserveField("pushRequest", "onDiscoverAction")
    m.uiRoot = m.top.FindNode("uiRoot")

    ' Bottom-of-stack Back opens the native exit dialog through the Scene's dialog
    ' field (a StandardDialog) rather than using the ScreenStack.
    m.confirmExit = m.top.FindNode("confirmExitDialog")
    m.confirmExit.ObserveFieldScoped("wasClosed", "onExitDialogClosed")

    ' The support modal is another native dialog; the Scene owns it and decides
    ' which platform to show. Both dialogs dismiss through wasClosed.
    m.supportDialog = m.top.FindNode("supportDialog")
    m.supportDialog.ObserveFieldScoped("wasClosed", "onSupportDialogClosed")

    ' Stores are constructed once at the Scene and handed to screens later by
    ' reference. SettingsStore and AddonsStore Load() their persisted state on
    ' construction.
    http = Transport()
    m.settingsStore = SettingsStore(CreateObject("roRegistrySection", "settings"))
    m.stores = {
        transport: http
        settings: m.settingsStore
        auth: AuthStore()
        addons: AddonsStore(http, CreateObject("roRegistrySection", "addons"))
        catalog: CatalogStore(http)
        episodes: EpisodesStore(http)
        library: LibraryStore(CreateObject("roRegistrySection", "library"))
        playback: PlaybackStore(http)
    }
    m.homeScreen.callFunc("SetStores", m.stores)
    m.detailsScreen.callFunc("SetStores", m.stores)
    m.episodesScreen.callFunc("SetStores", m.stores)
    m.streamsScreen.callFunc("SetStores", m.stores)
    m.settingsScreen.callFunc("SetStores", m.stores)
    m.addonsScreen.callFunc("SetStores", m.stores)
    m.searchScreen.callFunc("SetStores", m.stores)
    m.discoverScreen.callFunc("SetStores", m.stores)
end sub

' The only action channel from Home: one push request, dispatched by the stack.
' Dialogs (the support modal) are a special case routed through scene.dialog
' instead. No business logic — the Scene stays a thin orchestrator.
sub onHomeAction()
    request = m.homeScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    if request.dialog = true
        ShowSupportDialog()
        return
    end if
    m.stack.push(request.screen, request.params)
end sub

' Details' action channel; same one-action routing.
sub onDetailsAction()
    request = m.detailsScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' EpisodesScreen's action channel; same one-action routing.
sub onEpisodesAction()
    request = m.episodesScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' SearchScreen's action channel; same one-action routing.
sub onSearchAction()
    request = m.searchScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' DiscoverScreen's action channel; same one-action routing.
sub onDiscoverAction()
    request = m.discoverScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' StreamsScreen's action channel; same one-action routing. The player is special:
' it is created here, per play, instead of being a declared child — a component
' that survives pop keeps its Video node (and the audio it is decoding) alive on
' this device no matter how thoroughly the node itself is torn down. Removing the
' whole component from the tree and dropping the reference is what actually lets
' SceneGraph destroy it. The stack teardown calls OnExit first, so the resume
' position is saved before the component dies.
sub onStreamsAction()
    request = m.streamsScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    if request.screen <> "playerScreen" then
        m.stack.push(request.screen, request.params)
        return
    end if

    player = CreateObject("roSGNode", "PlayerScreen")
    player.id = "playerScreen"
    m.uiRoot.AppendChild(player)
    player.callFunc("SetStores", m.stores)
    player.ObserveField("closeRequest", "onPlayerClose")
    m.stack.pushNode(player, request.params)
end sub

' The player requests its own pop once teardown is genuinely complete (a stop
' can be asynchronous while buffering — the leave is held open until the OS
' reports "stopped"). Only pop when it is still the top screen, so a stale
' closeRequest can never pop anything else.
sub onPlayerClose()
    if m.stack.top() <> invalid and m.stack.top().id = "playerScreen"
        m.stack.pop()
    end if
end sub

' The exit dialog signals dismissal through wasClosed (Back, Home, or its own
' close field). Clear the Scene's dialog slot so the next Back presents it
' fresh, and hand focus back to Home. Only clear when the dialog is still
' the one shown.
sub onExitDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "confirmExitDialog"
        m.top.dialog = invalid
    end if
    if m.stack.top() <> invalid and m.stack.top().id = "homeScreen"
        m.homeScreen.SetFocus(true)
    end if
end sub

' Present the support modal: pick the platform by the device's store region
' (Argentina → Cafecito, everywhere else → Buy Me a Coffee), configure the
' dialog, then show it through the Scene's dialog field.
sub ShowSupportDialog()
    m.supportDialog.callFunc("Configure", SupportPlatform())
    m.top.dialog = m.supportDialog
end sub

function SupportPlatform() as string
    device = CreateObject("roDeviceInfo")
    if device <> invalid and device.GetCountryCode() = "AR" then return "cafecito"
    return "buymeacoffee"
end function

sub onSupportDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "supportDialog"
        m.top.dialog = invalid
    end if
    if m.stack.top() <> invalid and m.stack.top().id = "homeScreen"
        m.homeScreen.SetFocus(true)
    end if
end sub

' Bootstrap the stack once the roSGScreen is shown. A field observer would not
' work here: Scene.visible is born true and never reassigned, so observing it
' never fires. Start() is deterministic, and pushing after Show() guarantees the
' tree is renderable when focus is handed out. The stack always rests on a
' bottom home screen.
sub Start()
    m.stack.push("homeScreen")
end sub

' An ECP deep link (see reference/ecp-integration.md) arrived with the launch
' args. main.brs calls this after Start(), so the stack is up and Home is
' under everything; the flow reports back through a dialog and never replaces
' the Home screen.
'
' Rokumio-import runs sequentially — one AddonsInstallTask per manifest URL,
' each parked off the render thread (a hung add-on costs a worker, not the UI,
' exactly like the Addons screen) — then applies serverAddress and shows a
' single summary. m.import doubles as the re-entrancy guard: a second deep link
' while one runs is dropped.
sub HandleDeepLink(args as object)
    if args = invalid
        print "[rokumio] HandleDeepLink: args invalid"
        return
    end if
    if m.import <> invalid
        print "[rokumio] HandleDeepLink: import already running, dropping"
        return
    end if

    keys = ""
    for each key in args
        if keys <> "" then keys = keys + ","
        keys = keys + key
    end for
    print "[rokumio] HandleDeepLink args keys: " + keys

    parse = DeepLinkStore().Parse(args)
    print "[rokumio] HandleDeepLink kind=" + parse.kind + " verb='" + parse.verb + "' ok=" + parse.ok.ToStr() + " error='" + parse.error + "' addons=" + parse.addons.Count().ToStr() + " settings=" + (parse.settings <> invalid).ToStr()

    if parse.kind = "none"
        print "[rokumio] HandleDeepLink: not a rokumio deep link, ignoring"
        return
    end if
    if parse.kind = "unknown"
        ShowImportDialog("Rokumio import", ["Unsupported request: " + parse.error + "."])
        return
    end if
    if not parse.ok
        ShowImportDialog("Rokumio import", ["Could not import: " + parse.error + "."])
        return
    end if

    m.import = {
        pending: []
        added: 0
        skipped: 0
        failed: 0
        failures: []
        task: invalid
        settings: parse.settings
        requested: parse.addons.Count()
    }
    for each url in parse.addons
        m.import.pending.Push(url)
    end for
    PumpImport()
end sub

' Start the next queued manifest fetch, or finish when the queue is empty.
sub PumpImport()
    if m.import = invalid then return
    if m.import.task <> invalid then return
    if m.import.pending.Count() > 0
        url = m.import.pending.Shift()
        print "[rokumio] PumpImport: fetching " + url
        task = CreateObject("roSGNode", "AddonsInstallTask")
        task.id = "deepLinkInstall"
        m.top.AppendChild(task)
        task.address = url
        task.observeField("result", "onImportTaskResult")
        m.import.task = task
        task.control = "RUN"
        return
    end if
    FinishImport()
end sub

' One manifest fetch settled. The task validated against a registry-less store,
' so an already-installed id still comes back ok — the real duplicate gate runs
' here, in AddonsStore.Register. That orders the counts: added, skipped
' (duplicate/built-in), or failed.
sub onImportTaskResult()
    if m.import = invalid then return
    task = m.import.task
    if task = invalid then return
    m.import.task = invalid
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    resultId = ""
    resultError = ""
    if result <> invalid
        if result.id <> invalid then resultId = result.id
        if result.error <> invalid then resultError = result.error
    end if
    print "[rokumio] import task ok=" + (result <> invalid and result.ok).ToStr() + " id='" + resultId + "' error='" + resultError + "'"

    if result <> invalid and result.ok and result.record <> invalid
        registered = false
        if m.stores <> invalid and m.stores.addons <> invalid
            registered = m.stores.addons.Register(result.record)
        end if
        print "[rokumio] AddonsStore.Register('" + resultId + "') = " + registered.ToStr()
        if registered
            m.import.added = m.import.added + 1
        else
            m.import.skipped = m.import.skipped + 1
        end if
    else
        m.import.failed = m.import.failed + 1
        line = resultError
        if line = "" then line = "could not be installed"
        if resultId <> "" then line = resultId + ": " + line
        m.import.failures.Push(line)
    end if
    print "[rokumio] import counts added=" + m.import.added.ToStr() + " skipped=" + m.import.skipped.ToStr() + " failed=" + m.import.failed.ToStr()
    PumpImport()
end sub

' All manifest fetches are done. Apply the settings through the same path the
' Settings screen uses (invalid values are rejected, not stored), then report
' the outcome in one dialog — the channel is the authority on the result; ECP
' only ever said "delivered".
sub FinishImport()
    if m.import = invalid then return

    print "[rokumio] FinishImport requested=" + m.import.requested.ToStr() + " added=" + m.import.added.ToStr() + " skipped=" + m.import.skipped.ToStr() + " failed=" + m.import.failed.ToStr()

    blocks = []
    bullets = []

    if m.import.requested > 0
        if m.import.failed = 0
            if m.import.added = 0
                blocks.Push("Add-ons already installed.")
            else
                blocks.Push(m.import.added.ToStr() + " " + AddonWord(m.import.added) + " added.")
            end if
        else if m.import.added = 0
            if m.import.failed = 1
                blocks.Push("Add-on import failed.")
            else
                blocks.Push(m.import.failed.ToStr() + " add-ons could not be installed.")
            end if
            for each line in m.import.failures
                bullets.Push(line)
            end for
        else
            blocks.Push(m.import.added.ToStr() + " " + AddonWord(m.import.added) + " added, " + m.import.failed.ToStr() + " failed.")
            for each line in m.import.failures
                bullets.Push(line)
            end for
        end if
    end if

    if m.import.settings <> invalid and m.import.settings.serverAddress <> invalid
        print "[rokumio] FinishImport serverAddress sent"
        if m.stores <> invalid and m.stores.settings <> invalid
            if m.stores.settings.SetServerAddress(m.import.settings.serverAddress)
                blocks.Push("Server linked.")
            else
                blocks.Push("Invalid server address was ignored.")
            end if
        end if
    end if

    if blocks.Count() = 0 then blocks.Push("No changes requested.")

    ShowImportDialog("Rokumio import", blocks, bullets)

    ' New add-ons landed: Home's grid was built from the pre-import catalog set,
    ' so drop its rows and re-walk them now. The fill happens off the UI thread
    ' behind the summary dialog; nothing to block on here.
    if m.import.added > 0
        print "[rokumio] FinishImport: invalidating Home rows"
        if m.homeScreen <> invalid then m.homeScreen.callFunc("RebuildRows")
    end if

    m.import = invalid
end sub

' Singular/plural for the add-on count in the import summary.
function AddonWord(count as integer) as string
    if count = 1 then return "add-on"
    return "add-ons"
end function

sub ShowImportDialog(title as string, blocks as object, bullets = invalid as object)
    print "[rokumio] ShowImportDialog title='" + title + "' message=" + FormatJson(blocks)
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "deepLinkImportDialog"
    dialog.title = title
    dialog.message = blocks
    if bullets <> invalid and bullets.Count() > 0
        dialog.bulletText = bullets
    end if
    dialog.buttons = ["OK"]
    dialog.observeField("buttonSelected", "onImportButtonSelected")
    dialog.observeField("wasClosed", "onImportDialogClosed")
    m.top.dialog = dialog
end sub

' A button press does not dismiss a StandardMessageDialog on its own — it only
' sets buttonSelected. Mirror ConfirmExitDialog: close through the dialog's own
' close field, which funnels into the same wasClosed path the scene uses to
' clear the slot and hand focus back to Home.
sub onImportButtonSelected()
    if m.top.dialog <> invalid and m.top.dialog.id = "deepLinkImportDialog"
        m.top.dialog.close = true
    end if
end sub

' The import dialog dismissed (OK, Back or Home). Clear the Scene's dialog slot
' by id — roSGNode references cannot be compared with "=" — then give focus
' back to Home.
sub onImportDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "deepLinkImportDialog"
        m.top.dialog = invalid
    end if
    if m.stack.top() <> invalid and m.stack.top().id = "homeScreen"
        m.homeScreen.SetFocus(true)
    end if
end sub

' Back routing: the top screen gets first crack; if it declines and more screens
' remain, pop. On the bottom Home screen, Back opens the exit dialog.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        if m.stack.onBackPressed() then return true
        if m.stack.count() > 1 then return m.stack.pop()
        m.top.dialog = m.confirmExit
        return true
    end if

    return false
end function
