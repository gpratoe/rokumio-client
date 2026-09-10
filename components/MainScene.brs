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

    ' SettingsScreen is content-focused (no pushes); MainScene only needs its
    ' live UI-scale signal. AddonsScreen is also content-only.
    m.settingsScreen = m.top.FindNode("settingsScreen")
    m.settingsScreen.ObserveField("scaleChanged", "onScaleChanged")
    m.addonsScreen = m.top.FindNode("addonsScreen")
    m.uiRoot = m.top.FindNode("uiRoot")

    ' Bottom-of-stack Back pushes the confirm-exit dialog; the dialog's
    ' closeRequest is how it asks the Scene to dismiss it.
    m.confirmExit = m.top.FindNode("confirmExitDialog")
    m.confirmExit.ObserveField("closeRequest", "onConfirmExitClose")

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

    ApplyScale()
end sub

' The only action channel from Home: one push request, dispatched by the stack.
' No business logic — the Scene stays a thin orchestrator.
sub onHomeAction()
    request = m.homeScreen.pushRequest
    if request = invalid or request.screen = invalid then return
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

sub onConfirmExitClose()
    if m.stack.top() <> invalid and m.stack.top().id = "confirmExitDialog"
        if m.stack.count() > 1 then m.stack.pop()
        m.confirmExit.closeRequest = ""
    end if
end sub

' Apply the persisted UI scale to the whole uiRoot (100 default = no scaling).
' Scaling rotates around the screen center so a scale-up clips edges symmetrically
' instead of growing off the top-left corner. SceneGraph handles the transformed
' focus math, so scaling the root is all it takes for every screen to scale.
sub ApplyScale() as void
    scale = 1.0
    if m.settingsStore <> invalid
        value = m.settingsStore.GetUiScale()
        if value > 0 then scale = value / 100.0
    end if
    m.uiRoot.scaleRotateCenter = [960, 540]
    m.uiRoot.scale = [scale, scale]
end sub

' The Settings screen flipped scaleChanged after a successful scale change:
' reapply uiRoot.scale live so the new size takes effect immediately.
sub onScaleChanged()
    ApplyScale()
end sub

' Bootstrap the stack once the roSGScreen is shown. A field observer would not
' work here: Scene.visible is born true and never reassigned, so observing it
' never fires. Start() is deterministic, and pushing after Show() guarantees the
' tree is renderable when focus is handed out. The stack always rests on a
' bottom home screen.
sub Start()
    m.stack.push("homeScreen")
end sub

' Back routing: the top screen gets first crack; if it declines and more screens
' remain, pop. On the bottom Home screen, Back pushes the confirm-exit dialog.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        if m.stack.onBackPressed() then return true
        if m.stack.count() > 1 then return m.stack.pop()
        m.stack.push("confirmExitDialog", invalid, true)
        return true
    end if

    return false
end function
