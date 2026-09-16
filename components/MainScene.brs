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

    ' AuthScreen publishes the first-run choice (continue as guest, or log in
    ' with Stremio). The Scene signs the session in, points the session-aware
    ' stores at the right data and pops the gate — or starts the link-code flow.
    m.authScreen = m.top.FindNode("authScreen")
    m.authScreen.ObserveField("pushRequest", "onAuthAction")

    ' LinkStremioScreen publishes the pairing outcome: completeLogin (authKey +
    ' user) or cancelLogin (user backed out). The Scene owns the LinkStremioTask
    ' lifecycle; LinkStremioScreen only observes it and reports.
    m.linkStremioScreen = m.top.FindNode("linkStremioScreen")
    m.linkStremioScreen.ObserveField("pushRequest", "onLinkCodeAction")

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
    ' reports its pushes through its own channel. The exception is Settings'
    ' session rows: a guest can start the Stremio login from here, and a stremio
    ' user can log out — both are auth flows the Scene owns, so Settings reports
    ' them through its own channel too.
    m.settingsScreen = m.top.FindNode("settingsScreen")
    m.settingsScreen.ObserveField("pushRequest", "onSettingsAction")
    m.addonsScreen = m.top.FindNode("addonsScreen")
    m.searchScreen = m.top.FindNode("searchScreen")
    m.searchScreen.ObserveField("pushRequest", "onSearchAction")
    m.discoverScreen = m.top.FindNode("discoverScreen")
    m.discoverScreen.ObserveField("pushRequest", "onDiscoverAction")
    m.uiRoot = m.top.FindNode("uiRoot")
    ' Settings can start the link-code flow; logout reuses the pairing worker.
    ' Both flags are session-flow state with no store counterpart.
    m.loginFromSettings = false
    m.logoutTask = invalid
    m.pendingLogout = false

    ' Bottom-of-stack Back opens the native exit dialog through the Scene's dialog
    ' field (a StandardDialog) rather than using the ScreenStack.
    m.confirmExit = m.top.FindNode("confirmExitDialog")
    m.confirmExit.ObserveFieldScoped("wasClosed", "onExitDialogClosed")

    ' The support modal is another native dialog; the Scene owns it and decides
    ' which platform to show. Both dialogs dismiss through wasClosed.
    m.supportDialog = m.top.FindNode("supportDialog")
    m.supportDialog.ObserveFieldScoped("wasClosed", "onSupportDialogClosed")

    ' Stores are constructed once at the Scene and handed to screens later by
    ' reference. SettingsStore, AddonsStore and LibraryStore Load() their
    ' persisted state on construction; the add-on/library stores are built for
    ' the current session (guest or stremio) so every screen reads the right
    ' session's data from the first frame.
    http = Transport()
    m.authStore = AuthStore(CreateObject("roRegistrySection", "auth"))
    m.settingsStore = SettingsStore(CreateObject("roRegistrySection", "settings"))
    sessionType = EffectiveSessionType()
    m.stores = {
        transport: http
        settings: m.settingsStore
        auth: m.authStore
        addons: AddonsStore(http, CreateObject("roRegistrySection", "addons"), sessionType)
        catalog: CatalogStore(http)
        episodes: EpisodesStore(http)
        library: LibraryStore(CreateObject("roRegistrySection", "library"), sessionType)
        playback: PlaybackStore(http)
    }
    m.homeScreen.callFunc("SetStores", m.stores)
    m.authScreen.callFunc("SetStores", m.stores)
    m.linkStremioScreen.callFunc("SetStores", m.stores)
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

' SettingsScreen's session rows route here: the linked login is the same
' link-code flow as the AuthScreen start, while logout goes through a confirm
' dialog then the teardown in DoLogout. No business logic — the Scene stays a
' thin orchestrator.
sub onSettingsAction()
    request = m.settingsScreen.pushRequest
    if request = invalid or request.action = invalid then return
    if request.action = "login"
        m.loginFromSettings = true
        StartLinkCodeFlow()
    else if request.action = "logout"
        ShowLogoutConfirm()
    end if
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
    player.ObserveField("watchStateUpdate", "onWatchStateUpdate")
    m.activePlayer = player
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
    ' Drop the node reference so SceneGraph can destroy the whole component (and
    ' release the platform media player) — the last watch-state packet is safe
    ' because the player also records it in the library store, which lives on.
    m.activePlayer = invalid
end sub

' The player published a position update (pause or leave) through
' watchStateUpdate. MainScene owns the write-back pipeline: gate on a stremio
' session (guest never touches the API), drop a repeat of the last accepted
' update (same video, same position — nothing new), and coalesce the rest so at
' most one WatchStatePushTask runs at a time. The packet is read from the
' library store, not the player node, so the async callback can land even after
' onPlayerClose released the component.
sub onWatchStateUpdate()
    if m.stores = invalid or m.stores.auth = invalid or m.stores.library = invalid then return
    if m.stores.auth.GetSession() <> "stremio" then return
    packet = m.stores.library.LatestWatchStatePacket()
    if packet = invalid then return
    videoId = packet.videoId
    if videoId = invalid or videoId = "" then return
    if packet.position = invalid then return
    key = videoId + "|" + packet.position.ToStr()
    if m.lastPacketKey = key then return
    m.lastPacketKey = key
    m.pendingWatchState = packet
    PumpWatchStatePush()
end sub

' Start one push for the pending state if none is in flight. The pending slot is
' consumed into the worker; a state that arrives while this worker runs lands
' back in the slot and is pumped by onWatchStatePushResult. The LibraryItem to
' send is built by the store (the merge into the freshest cached copy), so no
' merge logic lives here.
sub PumpWatchStatePush()
    if m.pushingWatchState then return
    if m.pendingWatchState = invalid then return
    if m.stores = invalid or m.stores.auth = invalid or m.stores.library = invalid then return
    packet = m.pendingWatchState
    item = m.stores.library.BuildWatchStateItem(packet)
    if item = invalid then return
    m.pendingWatchState = invalid

    task = CreateObject("roSGNode", "WatchStatePushTask")
    task.id = "watchStatePushTask"
    m.top.AppendChild(task)
    task.authKey = m.stores.auth.GetAuthKey()
    task.item = item
    task.observeField("result", "onWatchStatePushResult")
    m.watchStatePushTask = task
    m.inFlightWatchState = packet
    m.pushingWatchState = true
    task.control = "RUN"
end sub

' One push settled. Free the worker and pump any state that arrived meanwhile.
' The latest update's videoId+position was already suppressed at accept time, so
' no record is needed here. Failures are non-fatal: the local continue-watching
' cache stays authoritative and the next position save retries naturally.
sub onWatchStatePushResult()
    task = m.watchStatePushTask
    m.watchStatePushTask = invalid
    m.pushingWatchState = false
    if task = invalid then return
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    if result <> invalid and result.ok
        print "[rokumio] watch state pushed videoId='" + m.inFlightWatchState.videoId + "'"
    else
        print "[rokumio] watch state push failed"
    end if
    m.inFlightWatchState = invalid
    PumpWatchStatePush()
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
' bottom home screen; a not-logged-in launch parks the auth gate on top, so
' "Continue as guest" simply pops it to reveal the guest home.
sub Start()
    m.stack.push("homeScreen")
    if not m.stores.auth.IsLoggedIn()
        m.stack.push("authScreen")
    else if EffectiveSessionType() = "stremio"
        ' Relaunched stremio session: addons are already in the registry key
        ' from the login that synced them, but the library always re-syncs from
        ' the account in the background — the persisted Continue Watching stack
        ' renders first, then freshens when the sync lands.
        StartLibrarySync()
    end if
end sub

' The store session derives from the persisted auth session: guest when logged
' out or in a guest session, stremio for an account session. Never blank — the
' session-aware stores always act on a concrete session's data.
function EffectiveSessionType() as string
    if m.authStore <> invalid and m.authStore.GetSession() = "stremio" then return "stremio"
    return "guest"
end function

' The AuthScreen published its first-run choice.
sub onAuthAction()
    request = m.authScreen.pushRequest
    if request = invalid then return
    if request.action = "continueGuest"
        if m.stores <> invalid and m.stores.auth <> invalid then m.stores.auth.LoginGuest()
        if m.stores <> invalid and m.stores.addons <> invalid then m.stores.addons.SwitchSession("guest")
        if m.stores <> invalid and m.stores.library <> invalid then m.stores.library.SwitchSession("guest")
        if m.stack.top() <> invalid and m.stack.top().id = "authScreen"
            m.stack.pop()
        end if
    else if request.action = "startLogin"
        StartLinkCodeFlow()
    end if
end sub

' Build the pairing worker, hand it to the LinkStremioScreen and start it. The
' task is created dynamically (like the player) so it lives exactly as long as
' the flow; teardown on success, Back or failure is handled in
' CleanupStremioPairTask. Publishes the fresh node through taskNode so the
' screen can (re)bind, resetting its spinner and countdown.
function NewPairingTask() as object
    task = CreateObject("roSGNode", "LinkStremioTask")
    task.id = "linkStremioTask"
    m.top.AppendChild(task)
    m.linkStremioTask = task
    m.linkStremioScreen.taskNode = task
    task.control = "RUN"
    return task
end function

' Start the link-code pairing: spawn the worker task, then push the pairing
' screen on top of whatever presented it (AuthScreen or Settings).
sub StartLinkCodeFlow()
    NewPairingTask()
    m.stack.push("linkStremioScreen")
end sub

' Request a new code while the pairing screen is already up: clear the old worker
' (freeing its thread and observer) and swap in a fresh one. No stack push — the
' screen stays put and rebinds through the taskNode field change.
sub RefreshLinkCode()
    CleanupStremioPairTask()
    NewPairingTask()
end sub

' The LinkStremioScreen published its outcome. completeLogin carries the paired
' authKey + user: persist the stremio session, repoint the session-aware stores
' and drop back to Home, cleaning up the flow. cancelLogin just washes out.
sub onLinkCodeAction()
    request = m.linkStremioScreen.pushRequest
    if request = invalid then return
    if request.action = "refreshCode"
        ' The screen stays up; only the worker is replaced.
        RefreshLinkCode()
        return
    end if
    if request.action = "completeLogin"
        if m.stores <> invalid and m.stores.auth <> invalid then m.stores.auth.LoginStremio(request.authKey, request.user)
        if m.stores <> invalid and m.stores.addons <> invalid then m.stores.addons.SwitchSession("stremio")
        if m.stores <> invalid and m.stores.library <> invalid then m.stores.library.SwitchSession("stremio")
        StartAddonSync()
        StartLibrarySync()
        if m.stack.top() <> invalid and m.stack.top().id = "linkStremioScreen"
            m.stack.pop()
        end if
        if m.stack.top() <> invalid and m.stack.top().id = "authScreen"
            m.stack.pop()
        end if
        if m.loginFromSettings and m.stack.top() <> invalid and m.stack.top().id = "settingsScreen"
            m.stack.pop()
        end if
        m.loginFromSettings = false
    end if
    CleanupStremioPairTask()
    if request.action = "cancelLogin" and m.stack.top() <> invalid and m.stack.top().id = "linkStremioScreen"
        m.stack.pop()
    end if
    if request.action = "cancelLogin" then m.loginFromSettings = false
end sub

' Reap the task: stop the worker, drop references and remove it from the tree.
' The STOP signal is the real cancel — the read-poll loop watches control and
' exits mid-sleep — because removing a running Task node does NOT kill its
' worker thread (a removed-but-running puller keeps polling, which showed up as
' the old link code being read alongside the new one after a refresh). Keep the
' removal too so the node is freed once the thread exits.
sub CleanupStremioPairTask()
    task = m.linkStremioTask
    m.linkStremioTask = invalid
    if task = invalid then return
    task.control = "STOP"
    if task.getParent() <> invalid then m.top.RemoveChild(task)
end sub

' Confirm before leaving the account: the confirm dialog is a StandardMessageDialog
' through the Scene's dialog field, mirroring the deep-link import dialog's close
' path (buttons only set buttonSelected; the dialog's own close field funnels into
' wasClosed so the Scene clears the slot).
sub ShowLogoutConfirm()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "logoutConfirmDialog"
    dialog.title = "Log out?"
    dialog.message = ["This signs the Stremio account out of this device. Your saved items and continue watching stay here; the library re-syncs if you log back in."]
    dialog.buttons = ["Log out", "Cancel"]
    dialog.observeField("buttonSelected", "onLogoutChoice")
    dialog.observeField("wasClosed", "onLogoutDialogClosed")
    m.top.dialog = dialog
end sub

sub onLogoutChoice()
    if m.top.dialog <> invalid and m.top.dialog.id = "logoutConfirmDialog"
        ' Record the intent and let the dialog dismiss first: acting while the
        ' dialog still owns scene.dialog loses the focus race — a screen pushed
        ' now would render unfocused (the SceneGraph restores focus to the
        ' pre-dialog node when the slot finally clears). DoLogout runs in
        ' onLogoutDialogClosed, after the dialog is gone.
        m.pendingLogout = m.top.dialog.buttonSelected = 0
        m.top.dialog.close = true
    end if
end sub

' The logout dialog dismissed (Log out, Cancel, Back or Home). Clear the Scene's
' dialog slot, then act: a confirmed logout runs the teardown now that no dialog
' competes for focus (DoLogout's pushes land focused); otherwise focus returns to
' Settings.
sub onLogoutDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "logoutConfirmDialog"
        m.top.dialog = invalid
    end if
    wasPending = m.pendingLogout
    m.pendingLogout = false
    if wasPending
        DoLogout()
    else if m.stack.top() <> invalid and m.stack.top().id = "settingsScreen"
        m.settingsScreen.SetFocus(true)
    end if
end sub

' The actual logout, on confirm: flush the account key at the API (best-effort,
' never gating), clear the local session, repoint the session-aware stores at the
' guest data, then walk the stack back to Home and park the auth gate on top so
' the user can pick their next session. The server call is fire-and-forget — the
' user is logged out here regardless of its outcome.
sub DoLogout()
    print "[rokumio] DoLogout"
    if m.stores <> invalid and m.stores.auth <> invalid and m.stores.auth.GetAuthKey() <> ""
        task = CreateObject("roSGNode", "LogoutTask")
        task.id = "logoutTask"
        m.top.AppendChild(task)
        task.authKey = m.stores.auth.GetAuthKey()
        task.observeField("result", "onLogoutResult")
        m.logoutTask = task
        task.control = "RUN"
    end if

    if m.stores <> invalid and m.stores.auth <> invalid then m.stores.auth.Logout()
    if m.stores <> invalid and m.stores.addons <> invalid then m.stores.addons.SwitchSession("guest")
    if m.stores <> invalid and m.stores.library <> invalid then m.stores.library.SwitchSession("guest")

    ' Pop all the way down to Home — every screen gets its normal OnExit/BlurFocus
    ' teardown, so transient tasks cancel and no stale focus survives.
    while m.stack.count() > 1
        m.stack.pop()
    end while
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RebuildRows")
    m.stack.push("authScreen")
end sub

' The server logout settled. Log the outcome and reap the worker; the local
' session is already cleared, nothing to gate on.
sub onLogoutResult()
    task = m.logoutTask
    m.logoutTask = invalid
    if task = invalid then return
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)
    if result <> invalid and result.ok
        print "[rokumio] account logged out at api.strem.io"
    else
        error = ""
        if result <> invalid and result.error <> invalid then error = result.error
        print "[rokumio] server logout failed: " + error
    end if
end sub

' Kick the account addon sync for a freshly-logged-in stremio session. The API
' answers with the full collection incl. each manifest, so no per-addon fetches
' follow — the task returns the descriptors and MainScene adopts them through
' AddonsStore (the single writer for installed records). Created per sync like
' the pairing task; a relaunched stremio session skips this (its addons are
' already in the stremio_addons registry key from the login that synced them).
sub StartAddonSync()
    task = CreateObject("roSGNode", "AddonSyncTask")
    task.id = "addonSyncTask"
    m.top.AppendChild(task)
    m.addonSyncTask = task
    if m.stores <> invalid and m.stores.auth <> invalid
        task.authKey = m.stores.auth.GetAuthKey()
    end if
    task.observeField("result", "onAddonSyncResult")
    task.control = "RUN"
end sub

' One sync settled. Register every descriptor through AddonsStore (duplicates
' are skipped, so re-syncing is idempotent) and rebuild Home's rows from the
' new catalog set. Failures are non-fatal — whatever synced registers, the rest
' is logged and the session proceeds (an empty collection is a legit outcome).
sub onAddonSyncResult()
    task = m.addonSyncTask
    m.addonSyncTask = invalid
    if task = invalid then return
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    added = 0
    skipped = 0
    failed = 0
    if result <> invalid and result.ok and result.descriptors <> invalid
        for each descriptor in result.descriptors
            if m.stores <> invalid and m.stores.addons <> invalid
                outcome = m.stores.addons.InstallFromDescriptor(descriptor.transportUrl, descriptor.manifest)
                if outcome.ok
                    added = added + 1
                else if outcome.error = "addon already installed"
                    skipped = skipped + 1
                else
                    failed = failed + 1
                    print "[rokumio] addon sync dropped '" + outcome.id + "': " + outcome.error
                end if
            end if
        end for
    end if
    print "[rokumio] addon sync added=" + added.ToStr() + " skipped=" + skipped.ToStr() + " failed=" + failed.ToStr()
    if added > 0 and m.homeScreen <> invalid
        m.homeScreen.callFunc("RebuildRows")
    end if
end sub

' Kick the account library sync. Runs on every stremio launch — a fresh login
' and a relaunched session alike — because only the continue-watching stack
' persists, so the full library must be re-pulled from the account in the
' background each time. The task returns the raw library item array; MainScene
' passes it to LibraryStore.SyncFromStremio, the single mapping authority.
sub StartLibrarySync()
    task = CreateObject("roSGNode", "LibrarySyncTask")
    task.id = "librarySyncTask"
    m.top.AppendChild(task)
    m.librarySyncTask = task
    if m.stores <> invalid and m.stores.auth <> invalid
        task.authKey = m.stores.auth.GetAuthKey()
    end if
    task.observeField("result", "onLibrarySyncResult")
    task.control = "RUN"
end sub

' One library sync settled. Reconcile the store with the remote collection and
' update Home's Continue Watching row in place — the persisted cache (if any)
' keeps rendering until then. Failures are non-fatal: on a login the CW row
' just stays empty, on a relaunch the persisted cache keeps rendering.
sub onLibrarySyncResult()
    task = m.librarySyncTask
    m.librarySyncTask = invalid
    if task = invalid then return
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    if result = invalid or not result.ok or result.items = invalid
        print "[rokumio] library sync failed"
        return
    end if
    if m.stores = invalid or m.stores.library = invalid then return
    m.stores.library.SyncFromStremio(result.items)
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RefreshContinueWatching")
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
