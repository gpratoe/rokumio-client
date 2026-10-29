' MainScene — the root Scene and integration boundary.
'
' It owns the ScreenStack, screen routing, the StoreHost node, and cross-screen
' effects that need Scene authority (session transitions, dialogs, refreshes).
' Stateful asynchronous workflows live in focused coordinator components; this
' Scene forwards their inputs/results and keeps the navigation-level decisions.
sub init()
    m.stack = ScreenStack(m.top)
    m.top.palette = AppPalette()

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
    ' Add/remove toggles from Details report through libraryChange; see
    ' onLibraryChange for the write-back pipeline.
    m.detailsScreen.ObserveField("libraryChange", "onLibraryChange")

    ' EpisodesScreen (the series episode browser) reports episode selections
    ' through the same one-action channel.
    m.episodesScreen = m.top.FindNode("episodesScreen")
    m.episodesScreen.ObserveField("pushRequest", "onEpisodesAction")
    ' Watched-status edits from the episode browser report through watchedChange;
    ' see onWatchedChange for the write-back pipeline.
    m.episodesScreen.ObserveField("watchedChange", "onWatchedChange")

    ' StreamsScreen reports the player push after a stream is resolved; the
    ' player itself never pushes — Back pops it. The player reports the positions
    ' it reaches through watchStateUpdate, so the Scene watches that one field;
    ' its own pushes are its business (it declines and the stack pops).
    m.streamsScreen = m.top.FindNode("streamsScreen")
    m.streamsScreen.ObserveField("pushRequest", "onStreamsAction")
    m.playerScreen = m.top.FindNode("playerScreen")
    m.playerScreen.ObserveField("watchStateUpdate", "onWatchStateUpdate")

    ' SettingsScreen, AddonsScreen and SearchScreen are content-focused (no
    ' pushes of their own; Search pushes Details like the others). SearchScreen
    ' reports its pushes through its own channel. The exception is Settings'
    ' session rows: a guest can start the Stremio login from here, and a stremio
    ' user can log out — both are auth flows the Scene owns, so Settings reports
    ' them through its own channel too.
    m.settingsScreen = m.top.FindNode("settingsScreen")
    m.settingsScreen.ObserveField("pushRequest", "onSettingsAction")
    m.addonsScreen = m.top.FindNode("addonsScreen")
    ' Install/remove rep from the add-on manager: MainScene owns the account
    ' mirror and the collection pump, so the screen's two channels land here.
    m.addonsScreen.ObserveField("addonRemoved", "onAddonRemoved")
    m.addonsScreen.ObserveField("addonInstalled", "onAddonInstalled")
    m.searchScreen = m.top.FindNode("searchScreen")
    m.searchScreen.ObserveField("pushRequest", "onSearchAction")
    m.discoverScreen = m.top.FindNode("discoverScreen")
    m.discoverScreen.ObserveField("pushRequest", "onDiscoverAction")
    m.libraryScreen = m.top.FindNode("libraryScreen")
    m.libraryScreen.ObserveField("pushRequest", "onLibraryAction")
    m.uiRoot = m.top.FindNode("uiRoot")
    m.faultStrip = m.top.FindNode("faultStrip")
    m.libraryWriteCoordinator = m.top.FindNode("libraryWriteCoordinator")
    m.addonWriteCoordinator = m.top.FindNode("addonWriteCoordinator")
    m.importCoordinator = m.top.FindNode("importCoordinator")
    m.accountSyncCoordinator = m.top.FindNode("accountSyncCoordinator")
    m.top.FindNode("background").color = Theme().screenBg

    ' Settings can start the link-code flow; logout reuses the pairing worker.
    ' Both flags are session-flow state with no store counterpart.
    m.loginFromSettings = false
    m.logoutTask = invalid
    m.pendingLogout = false
    ' A revoked-account bounce fires at most once per login: both launch-time
    ' pulls (library + addon) fail together on a dead authKey, and only the
    ' first one tears the session down.
    m.revokedSessionHandled = false

    ' Bottom-of-stack Back opens the native exit dialog through the Scene's dialog
    ' field rather than using the ScreenStack. It is a StandardMessageDialog,
    ' built when it is shown (see ShowExitConfirm) — the same shape as the
    ' log-out confirm, and every word on it scriptable.
    '
    ' The support modal is the other native dialog; the Scene owns it and
    ' decides which platform to show. It is a StandardDialog, because its side
    ' card (the QR and its caption) is a thing a StandardMessageDialog does
    ' not have.
    '
    ' Both are BUILT IN CODE rather than declared as children in the markup.
    ' The StandardMessageDialogs (delete add-on, ECP sent, session revoked) are
    ' created in code and every one of them renders. The two custom ones
    ' declared as Scene children dimmed the background and took focus — blind
    ' OK on the Exit button still fired buttonSelected — but painted nothing
    ' at all, which rules out a broken component: their side card, QR and
    ' palette are the same code either way. The declaration was the only thing
    ' that differed. Keep the reference: a CreateObject'd node that nothing
    ' holds can be collected while it is on screen.
    '
    ' Both dialogs dismiss through wasClosed.
    m.supportDialog = CreateObject("roSGNode", "SupportDialog")
    m.supportDialog.id = "supportDialog"
    m.supportDialog.ObserveFieldScoped("wasClosed", "onSupportDialogClosed")

    ' The whole data layer lives in ONE component — StoreHost — which builds
    ' every store instance exactly once and never lets one leave. A bsc class
    ' instance is an roAssociativeArray whose members are function references,
    ' and Roku copies that array the moment it crosses a component boundary (as
    ' a callFunc argument, a callFunc return or a declared interface field),
    ' dropping every function member — so a screen handed a store held a
    ' data-only copy and its first method call died with &hf4 "Member function
    ' not found". Three architectures failed on that one fact before this one.
    '
    ' What crosses instead is the StoreHost NODE, which Roku passes by reference
    ' — the same mechanism the pairing task already uses through the declared
    ' taskNode field — and what comes back over callFunc is plain data only:
    ' strings, numbers, booleans, arrays and assoc arrays of records. A screen
    ' asks for a value and receives a value; no store instance is ever in
    ' flight, so there is nothing left to strip.
    '
    ' This is the pattern the task components already follow (see
    ' AddonsInstallTask.xml): include the store sources into the component that
    ' needs them and call them there. Those can afford a private instance
    ' because they are stateless per-request wrappers; the session-aware stores
    ' cannot, which is why they are built once, here, and shared as a node.
    '
    ' Created before the binds below and never replaced: a session switch
    ' re-targets the session-aware stores in place through SwitchSession.
    m.storeHost = CreateObject("roSGNode", "StoreHost")
    m.top.AppendChild(m.storeHost)
    m.libraryWriteCoordinator.callFunc("SetStoreHost", m.storeHost)
    m.addonWriteCoordinator.callFunc("SetDependencies", m.storeHost, m.top)
    m.importCoordinator.callFunc("SetScene", m.top)
    m.accountSyncCoordinator.callFunc("SetDependencies", m.storeHost, m.top)

    ' The keys the last add-on sync published into the strip. Held so a later
    ' sync can retract exactly what it published: the reason strings carry the
    ' transport's error text, so a clear-by-same-text would leave a stale line
    ' up whenever the wording changed.
    m.addonSyncFaults = []

    m.homeScreen.callFunc("SetStores", m.storeHost, m.top)
    m.authScreen.callFunc("SetStores", m.storeHost, m.top)
    m.linkStremioScreen.callFunc("SetStores", m.storeHost, m.top)
    m.detailsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.episodesScreen.callFunc("SetStores", m.storeHost, m.top)
    m.streamsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.settingsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.addonsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.searchScreen.callFunc("SetStores", m.storeHost, m.top)
    m.discoverScreen.callFunc("SetStores", m.storeHost, m.top)
    m.libraryScreen.callFunc("SetStores", m.storeHost, m.top)
    m.playerScreen.callFunc("SetStores", m.storeHost, m.top)
end sub

' Screens already report store faults through MainScene's interface. Keep this
' entry point stable; the FaultStrip component owns state, timer and painting.
sub ReportStoreFault(reason as string, active as boolean)
    if m.faultStrip = invalid then return
    m.faultStrip.callFunc("ReportStoreFault", reason, active)
end sub

' Transient reports stay internal to MainScene's sync paths, but use the same
' component that owns their lease and display.
sub ReportTransientFault(reason as string)
    if m.faultStrip = invalid then return
    m.faultStrip.callFunc("ReportTransientFault", reason)
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

' LibraryScreen's action channel; same one-action routing.
sub onLibraryAction()
    request = m.libraryScreen.pushRequest
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

' StreamsScreen's action channel; same one-action routing as every other screen.
sub onStreamsAction()
    request = m.streamsScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' Screens and the player still publish through their existing fields. MainScene
' is the event boundary and forwards each plain-data change to the coordinator
' that owns queueing, serialization, task lifecycle, and the deferred player
' write.
sub onWatchStateUpdate()
    if m.libraryWriteCoordinator <> invalid then m.libraryWriteCoordinator.callFunc("OnWatchStateUpdate")
end sub

sub onLibraryChange()
    if m.libraryWriteCoordinator = invalid or m.detailsScreen = invalid then return
    change = m.detailsScreen.libraryChange
    if change <> invalid then m.libraryWriteCoordinator.callFunc("OnLibraryChange", change)
end sub

sub onWatchedChange()
    if m.libraryWriteCoordinator = invalid or m.episodesScreen = invalid then return
    change = m.episodesScreen.watchedChange
    if change <> invalid then m.libraryWriteCoordinator.callFunc("OnWatchedChange", change)
end sub

' ---- the account add-on collection write-back -------------------------------
' The mirror mutation is the Scene's gateway; the writer owns the serialized
' whole-collection PUT and its task lifecycle.
sub PumpAddonWrites()
    if m.addonWriteCoordinator <> invalid then m.addonWriteCoordinator.callFunc("Pump")
end sub

' THE one gateway every local add-on change flows through, whichever flow
' produced it — the add-on manager's screen channels (below) and the import
' coordinator's registered installs land here. One place, so
' there is exactly one rule: a stremio-session change happens in the local
' registry AND reaches the account through the mirror, or the fault strip
' names why it could not. Guest sessions have no account and stay silent;
' the device-only removal of a built-in seed never touches this (the screen
' does not report it).
'
' The mirror is the verdict on whether anything must be written: "done" bumps
' its stamp and pumps one collection set; "absent" means the account cannot
' change here (the id is a device-only add-on, or installing one it already
' carries); "unknown" reports the withheld change on the fault strip.
sub AccountAddonRemoved(id as string)
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    outcome = m.storeHost.callFunc("AddonsAccountRemoveAddon", id)
    AddonMirrorFault(outcome, "removal")
    if outcome.reason = "done" then PumpAddonWrites()
end sub

' The install twin of AccountAddonRemoved. transportUrl is the manifest URL
' the account stores as the addon's descriptor (not the base the record is
' called at) and the manifest rides verbatim, unnormalized.
sub AccountAddonInstalled(transportUrl as dynamic, manifest as dynamic)
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    outcome = m.storeHost.callFunc("AddonsAccountAddAddon", transportUrl, manifest)
    AddonMirrorFault(outcome, "installation")
    if outcome.reason = "done" then PumpAddonWrites()
end sub

' The add-on manager uninstalled a non-built-in: screen rep, then gateway.
sub onAddonRemoved()
    if m.addonsScreen = invalid then return
    change = m.addonsScreen.addonRemoved
    if change <> invalid then AccountAddonRemoved(change.id)
end sub

' The add-on manager installed through a manifest URL: screen rep, then
' gateway. Descriptor rides verbatim.
sub onAddonInstalled()
    if m.addonsScreen = invalid then return
    change = m.addonsScreen.addonInstalled
    if change <> invalid then AccountAddonInstalled(change.transportUrl, change.manifest)
end sub

' Tell the fault strip when a change was withheld for a reason the user can
' act on (or at least understand). "absent" is silent on purpose: an id the
' account never carried (installing an already-synced add-on, removing a
' device-only one) needs no write and no alarm.
sub AddonMirrorFault(outcome as object, what as string)
    if outcome = invalid then return
    if outcome.reason = "unknown"
        AddAddonSyncFault("the account's add-on list is unknown; the " + what + " was not synced")
    end if
end sub

' AddonWriteCoordinator reports failed puts here so MainScene remains the
' authority for the transient sync-fault lease and its retraction list.
sub ReportAddonWriteFault(reason as string)
    AddAddonSyncFault(reason)
end sub

' The exit confirm. A StandardMessageDialog, built when it is shown: the same
' shape as the log-out confirm (a title, one line, two buttons), and every
' word on it is scriptable — so it speaks the language the settings store
' holds. It used to be a component that declared its text in the markup,
' which no language could reach.
sub ShowExitConfirm()
    RefreshSceneTexts()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "confirmExitDialog"
    dialog.title = Lang("main", "exitTitle")
    dialog.message = [Lang("main", "exitMessage")]
    dialog.buttons = [Lang("main", "exitCancel"), Lang("main", "exitButton")]
    dialog.observeField("buttonSelected", "onExitChoice")
    dialog.observeField("wasClosed", "onExitDialogClosed")
    m.top.dialog = dialog
end sub

' Exit drops the channel through the Scene's exitApp field, which main.brs
' watches; Cancel closes the dialog the standard way.
sub onExitChoice()
    if m.top.dialog <> invalid and m.top.dialog.id = "confirmExitDialog"
        if m.top.dialog.buttonSelected = 1 then
            m.top.exitApp = true
        else
            m.top.dialog.close = true
        end if
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
    RefreshSceneTexts()
    ApplySupportTexts()
    m.supportDialog.callFunc("Configure", SupportPlatform())
    m.top.dialog = m.supportDialog
end sub

' The support dialog's words live in its markup, and a StandardDialog is not
' scriptable the way a StandardMessageDialog is. They are set here, before it
' is shown, so the dialog speaks the language the settings store holds.
'
' A StandardDialog builds its content when it is created, so whether a text
' set at show time is what gets drawn is a question only the device can
' answer. The alternative — English-only here — is a hole in the language, so
' the attempt is made and the device decides.
sub ApplySupportTexts()
    if m.supportDialog = invalid then return
    titleArea = m.supportDialog.FindNode("supportTitleArea")
    if titleArea <> invalid then titleArea.primaryTitle = Lang("main", "supportTitle")
    intro = m.supportDialog.FindNode("supportIntro")
    if intro <> invalid then intro.text = Lang("main", "supportLine1")
    second = m.supportDialog.FindNode("supportLine2")
    if second <> invalid then second.text = Lang("main", "supportLine2")
    closeButton = m.supportDialog.FindNode("supportClose")
    if closeButton <> invalid then closeButton.text = Lang("main", "supportClose")
    caption = m.supportDialog.FindNode("supportQrCaption")
    if caption <> invalid then caption.text = Lang("main", "supportQrCaption")
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
    if not m.storeHost.callFunc("AuthIsLoggedIn")
        m.stack.push("authScreen")
    else if EffectiveSessionType() = "stremio"
        ' Relaunched stremio session. Both pulls run every launch, for the same
        ' reason: the library is re-pulled because only the continue-watching
        ' stack persists, and the addon collection is re-pulled because a
        ' session whose stremio_addons key is empty has no catalogs at all —
        ' AddonsStore hides the built-in seeds for a stremio session, so nothing
        ' renders until the collection lands. See StartAddonSync for how a
        ' single failed login-time sync used to make that state permanent.
        StartAddonSync()
        StartLibrarySync()
    end if
end sub

' The store session derives from the persisted auth session: guest when logged
' out or in a guest session, stremio for an account session. Never blank — the
' session-aware stores always act on a concrete session's data. The host owns
' the auth store, so it owns the answer; asking for it here keeps one derivation
' instead of a second registry read in the Scene that could disagree.
function EffectiveSessionType() as string
    if m.storeHost <> invalid and m.storeHost.callFunc("EffectiveSessionType") = "stremio" then return "stremio"
    return "guest"
end function

' The one place a session change reaches the session-aware stores: the type is
' derived from the auth authority (never a call-site literal), so it always
' matches the session the store/service were just pivoted to, and every session
' gets the same switch. The host holds that list, so login, logout and
' guest-continuation cannot leave one of its stores on the old session by
' forgetting a fan-out here. Guest and stremio stay under separate registry keys
' with a clear-and-reload swap, so the two sessions never mix.
sub ReconcileSession()
    if m.storeHost <> invalid then m.storeHost.callFunc("SwitchSession", EffectiveSessionType())
end sub

' The AuthScreen published its first-run choice.
sub onAuthAction()
    request = m.authScreen.pushRequest
    if request = invalid then return
    if request.action = "continueGuest"
        if m.storeHost <> invalid then m.storeHost.callFunc("AuthLoginGuest")
        ReconcileSession()
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
        if m.storeHost <> invalid then m.storeHost.callFunc("AuthLoginStremio", request.authKey, request.user)
        ReconcileSession()
        m.revokedSessionHandled = false
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

' The Scene's own words. The Scene is not a screen — it has no m.stores — but
' it owns the store host, so it reads its words exactly the way a screen does.
'
' It pulls them at the moment it is about to speak, not once at init: a dialog
' is built long after the Scene started (the user may have changed the
' language in the Settings screen in between), and it must speak the language
' the user has NOW. The alternative — a push from the Settings screen when the
' language changes — is a second channel to keep in sync, for text that is
' only ever read at build time.
sub RefreshSceneTexts() as void
    LoadTexts(m.storeHost)
end sub

' Confirm before leaving the account: the confirm dialog is a StandardMessageDialog
' through the Scene's dialog field, mirroring the deep-link import dialog's close
' path (buttons only set buttonSelected; the dialog's own close field funnels into
' wasClosed so the Scene clears the slot).
sub ShowLogoutConfirm()
    RefreshSceneTexts()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "logoutConfirmDialog"
    dialog.title = Lang("main", "logOutTitle")
    dialog.message = [Lang("main", "logOutMessage")]
    dialog.buttons = [Lang("main", "logOutConfirm"), Lang("common", "cancel")]
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
' never gating), then the same teardown the revoked-session bounce runs. The
' server call is fire-and-forget — the user is logged out here regardless of its
' outcome.
sub DoLogout()
    if m.storeHost <> invalid and m.storeHost.callFunc("AuthGetAuthKey") <> ""
        task = AsyncTask_Launch(m.top, "LogoutTask", "onLogoutResult", {
            authKey: m.storeHost.callFunc("AuthGetAuthKey")
        }, "logoutTask")
        m.logoutTask = task
    end if

    ResetToAuthGate()
end sub

' Clear the local session, repoint the session-aware stores at the guest data,
' then walk the stack back to Home and park the auth gate on top so the user can
' pick their next session. Shared by the manual logout and the revoked-session
' bounce; the manual logout additionally flushes the authKey at the API first
' (see DoLogout).
sub ResetToAuthGate()
    if m.storeHost <> invalid then m.storeHost.callFunc("AuthLogout")
    ReconcileSession()

    ' Pop all the way down to Home — every screen gets its normal OnExit/BlurFocus
    ' teardown, so transient tasks cancel and no stale focus survives.
    while m.stack.count() > 1
        m.stack.pop()
    end while
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RebuildRows")
    m.stack.push("authScreen")
end sub

' A launch-time pull reported that the account session no longer exists (it was
' deleted from the account's session list, or expired). The local authKey is
' dead, so there is no server logout to flush — drop to the guest gate exactly
' like the manual logout, and explain why. Guarded so the racing library/addon
' pulls can only bounce once.
sub HandleRevokedSession()
    if m.revokedSessionHandled then return
    m.revokedSessionHandled = true
    if m.accountSyncCoordinator <> invalid then m.accountSyncCoordinator.callFunc("CancelPendingLibrarySync")
    ResetToAuthGate()
    ShowSessionRevokedDialog()
end sub

' Present the revoked-session dialog over the auth gate: one OK button down to
' choosing the next session, mirroring the deep-link import dialog's wiring.
sub ShowSessionRevokedDialog()
    RefreshSceneTexts()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "sessionRevokedDialog"
    dialog.title = Lang("main", "sessionEndedTitle")
    dialog.message = [Lang("main", "sessionEndedMessage")]
    dialog.buttons = [Lang("common", "ok")]
    dialog.observeField("buttonSelected", "onSessionRevokedButtonSelected")
    dialog.observeField("wasClosed", "onSessionRevokedDialogClosed")
    m.top.dialog = dialog
end sub

sub onSessionRevokedButtonSelected()
    if m.top.dialog <> invalid and m.top.dialog.id = "sessionRevokedDialog"
        m.top.dialog.close = true
    end if
end sub

sub onSessionRevokedDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "sessionRevokedDialog"
        m.top.dialog = invalid
    end if
    if m.stack.top() <> invalid and m.stack.top().id = "authScreen"
        m.authScreen.SetFocus(true)
    end if
end sub

' The server logout settled. Reap the worker; the local session is already
' cleared, nothing to gate on.
sub onLogoutResult()
    task = m.logoutTask
    m.logoutTask = invalid
    if task = invalid then return
    AsyncTask_Reap(task, m.top, false)
end sub

' Start the account pull. The coordinator owns its Task and serializes it with
' the library pull; the Scene adopts the returned descriptors below. Called at
' both relaunch and login so a failed earlier pull can recover without re-pairing.
sub StartAddonSync()
    if m.accountSyncCoordinator <> invalid then m.accountSyncCoordinator.callFunc("StartAddonSync")
end sub

' Adopt the result produced by AccountSyncCoordinator. The coordinator owns the
' task and ordering; the Scene owns store adoption's cross-screen effects and
' the fault strip.
sub AdoptAddonSyncResult(result as object)
    if result = invalid then return
    if not result.ok
        reason = "unknown error"
        if result.error <> invalid and result.error <> "" then reason = result.error
        AddAddonSyncFault("addon sync failed: " + reason)
        return
    end if

    added = 0
    skipped = 0
    failed = 0
    if result.descriptors <> invalid
        for each descriptor in result.descriptors
            if m.storeHost <> invalid
                outcome = m.storeHost.callFunc("AddonsInstallFromDescriptor", descriptor.transportUrl, descriptor.manifest)
                if outcome.ok
                    added = added + 1
                else if outcome.error = "addon already installed"
                    skipped = skipped + 1
                else
                    failed = failed + 1
                end if
            end if
        end for
        ' Adopt the raw account collection, then prune local non-built-ins the
        ' successful pull says were removed elsewhere. Never prune on failure.
        pruned = 0
        if m.storeHost <> invalid
            m.storeHost.callFunc("AddonsSyncAccountCollection", result.raw)
            keepIds = []
            for each descriptor in result.descriptors
                if descriptor.manifest <> invalid then keepIds.Push(descriptor.manifest.id)
            end for
            pruned = m.storeHost.callFunc("AddonsPruneOutOfAccount", keepIds)
        end if
        if pruned > 0 then print "[addons] sync pruned " ; pruned.ToStr() ; " add-on(s) absent from the account"
    end if
    print "[addons] sync landed — registered " ; added ; ", already had " ; skipped ; ", rejected " ; failed
    ' Unconditional: an unchanged account still tells Home to compare its
    ' catalog signature, and the common case is one in-memory check.
    if m.homeScreen <> invalid then m.homeScreen.callFunc("EnsureCurrentRows")
    if m.playerScreen <> invalid then m.playerScreen.callFunc("EnsureSubtitleProviders")
    if failed > 0
        AddAddonSyncFault("addon sync: " + failed.ToStr() + " of " + result.descriptors.Count().ToStr() + " add-ons were rejected")
    end if
    if m.storeHost <> invalid and m.storeHost.callFunc("AddonsGetAll").Count() = 0
        AddAddonSyncFault("addon sync: the account reported no add-ons")
    end if
end sub

sub ClearAddonSyncFaults()
    if m.addonSyncFaults <> invalid
        for each key in m.addonSyncFaults
            ReportStoreFault(key, false)
            if m.faultStrip <> invalid then m.faultStrip.callFunc("ClearTransientFault", key)
        end for
    end if
    m.addonSyncFaults = []
end sub

sub ReportAddonSyncFault(reason as string)
    AddAddonSyncFault(reason)
end sub

sub AddAddonSyncFault(reason as string)
    ' Transient, deliberately: a launch-time sync failure can heal on the very
    ' next launch (flaky connection, server hiccup), and a glue-on strip is
    ' not the UX for a recoverable fault. The retraction list below stays:
    ' before every new sync attempt the previous attempt's wording goes, so
    ' the strip never names a fault the current attempt has not confirmed.
    ReportTransientFault(reason)
    m.addonSyncFaults.Push(reason)
end sub

' Kick the account library sync. Runs on every stremio launch — a fresh login
' and a relaunched session alike — because only the continue-watching stack
' persists, so the full library must be re-pulled from the account in the
' background each time. The task returns the raw library item array; MainScene
' passes it to LibraryStore.SyncFromStremio, the single mapping authority.
' Launch the library sync unless the add-on sync is still running; if it is,
' remember to run it when that settles. Both pull in the background at launch,
' and the device refuses NEW concurrent connections past a low ceiling (~4-6),
' so serializing the two account syncs keeps the launch burst under it. Whatever
' still slips through is caught by Transport's bounded retry.
sub StartLibrarySync()
    if m.accountSyncCoordinator <> invalid then m.accountSyncCoordinator.callFunc("StartLibrarySync")
end sub

' Apply the library snapshot returned by AccountSyncCoordinator. The pull/task
' lifecycle is elsewhere; this is the Scene-side store and screen adoption.
sub ApplyLibrarySyncResult(result as object)
    if result = invalid or not result.ok or result.items = invalid then return
    if m.storeHost = invalid then return
    m.storeHost.callFunc("LibrarySyncFromStremio", result.items)
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RefreshContinueWatching")
    if m.stack.top() <> invalid and m.stack.top().id = "libraryScreen" and m.libraryScreen <> invalid
        m.libraryScreen.callFunc("RefreshRows")
    end if
end sub

' An ECP deep link (see reference/ecp-integration.md) arrived with the launch
' args. main.brs calls this after Start(), so the stack is up and Home is
' under everything; the flow reports back through a dialog and never replaces
' the Home screen.
'
' Rokumio-import runs sequentially — one AddonsInstallTask per manifest URL,
' each parked off the render thread (a hung add-on costs a worker, not the UI,
' exactly like the Addons screen) — then applies serverAddress and shows a
' single summary. ImportCoordinator owns the re-entrancy guard: a second deep
' link while one runs is dropped.
sub HandleDeepLink(args as object)
    if args = invalid then return
    if m.importCoordinator.callFunc("IsBusy") then return

    parse = DeepLinkStore().Parse(args)
    if parse.kind = "none" then return
    if parse.kind = "unknown"
        ShowImportDialog("importTitle", [{ key: "importUnsupported", values: { error: parse.error } }])
        return
    end if
    if not parse.ok
        ShowImportDialog("importTitle", [{ key: "importCouldNot", values: { error: parse.error } }])
        return
    end if

    m.importCoordinator.callFunc("StartImport", parse.addons, parse.settings)
end sub

' The local setup page hands off one manifest URL. The coordinator owns the
' same busy slot as HandleDeepLink, so the page can answer 409 while an import
' is active and otherwise show its "watch the TV" response.
function ImportFromSetup(url as dynamic) as boolean
    if url = invalid or url = "" then return false
    return m.importCoordinator.callFunc("StartImport", [url], invalid)
end function

sub ShowSetupAddress(url as dynamic)
    if url = invalid then return
    if url = "" then return
    m.setupAddress = url
    if m.addonsScreen <> invalid then m.addonsScreen.callFunc("SetSetupAddress", url)
end sub

' Start the next queued manifest fetch, or finish when the queue is empty.
' The coordinator registers through this gateway, so imported add-ons reach the
' same account mirror as AddonsScreen installs. The worker only fetched and
' validated the manifest; the live AddonsStore remains the duplicate/persistence
' authority.
function ImportRegisterAddon(record as object, transportUrl as dynamic, manifest as dynamic) as boolean
    if m.storeHost = invalid then return false
    registered = m.storeHost.callFunc("AddonsRegister", record)
    if registered then AccountAddonInstalled(transportUrl, manifest)
    return registered
end function

' ImportCoordinator's finished summary. MainScene owns the cross-screen effects:
' apply the optional server setting, show the localized result dialog, and let
' Home/player re-derive data that may have changed while the import ran.
sub ImportFinished(summary as object)
    if summary = invalid then return
    lines = []
    bullets = []

    if summary.requested > 0
        if summary.failed = 0
            if summary.added = 0
                lines.Push({ key: "importAlreadyInstalled" })
            else
                lines.Push(ImportAddedLine(summary.added))
            end if
        else
            ' What landed and what did not are two lines, not one: "3 add-ons
            ' added, 2 failed." is a sentence that has to be re-ordered (and
            ' re-inflected) in every language, while two lines are two lines
            ' everywhere.
            addedLine = ImportAddedLine(summary.added)
            if addedLine <> invalid then lines.Push(addedLine)
            if summary.failed = 1
                lines.Push({ key: "importFailedOne" })
            else
                lines.Push({ key: "importFailedMany", values: { count: summary.failed.ToStr() } })
            end if
            for each failure in summary.failures
                bullets.Push(failure)
            end for
        end if
    end if

    if summary.settings <> invalid and summary.settings.serverAddress <> invalid
        if m.storeHost <> invalid
            if m.storeHost.callFunc("SettingsSetServerAddress", summary.settings.serverAddress)
                if m.storeHost.callFunc("SettingsSaveFailed") then
                    lines.Push({ key: "importServerLinkedNotSaved" })
                    ReportStoreFault("settings could not be saved", true)
                else
                    lines.Push({ key: "importServerLinked" })
                    ReportStoreFault("settings could not be saved", false)
                end if
            else
                lines.Push({ key: "importInvalidAddress" })
            end if
        end if
    end if

    if lines.Count() = 0 then lines.Push({ key: "importNoChanges" })
    ShowImportDialog("importTitle", lines, bullets)

    ' The import may have changed catalog providers or subtitle providers. These
    ' calls are unconditional: the screens compare their actual provider set and
    ' only rebuild if it moved, so an unchanged/re-registered add-on is harmless.
    if m.homeScreen <> invalid then m.homeScreen.callFunc("EnsureCurrentRows")
    if m.playerScreen <> invalid then m.playerScreen.callFunc("EnsureSubtitleProviders")
end sub

function ImportAddedLine(count as integer) as object
    if count = 0 then return invalid
    if count = 1 then return { key: "importAddedOne" }
    return { key: "importAddedMany", values: { count: count.ToStr() } }
end function

' The import result dialog. It takes the KEYS of its lines, not the words: the
' slice is pulled here, first, and the table is read afterwards, so a dialog
' built after the user changed the language speaks the language they have now.
'
' The lines are { key, values } records — the key says which sentence, the
' values fill its placeholders. The caller decides WHAT happened; this says it.
sub ShowImportDialog(titleKey as string, lines as object, bullets = invalid as object)
    RefreshSceneTexts()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "deepLinkImportDialog"
    dialog.title = Lang("main", titleKey)
    dialog.message = ImportLinesText(lines)
    if bullets <> invalid and bullets.Count() > 0
        dialog.bulletText = ImportFailuresText(bullets)
    end if
    dialog.buttons = [Lang("common", "ok")]
    dialog.observeField("buttonSelected", "onImportButtonSelected")
    dialog.observeField("wasClosed", "onImportDialogClosed")
    m.top.dialog = dialog
end sub

' The summary lines, in words.
function ImportLinesText(lines as object) as object
    out = []
    if lines = invalid then return out
    for each line in lines
        text = ImportLineText(line)
        if text <> "" then out.Push(text)
    end for
    return out
end function

' One summary line: the table's sentence for a key, with the values the caller
' supplied. A line without a key says nothing — a malformed record is dropped
' rather than painted as a blank line in the middle of the summary.
function ImportLineText(line as object) as string
    if line = invalid then return ""
    key = line.key
    if key = invalid or key = "" then return ""
    values = invalid
    if line.values <> invalid then values = line.values
    return Fill(Lang("main", key), values)
end function

' The per-add-on failure lines. The add-on's own error is the server's text
' and stays as it came; the fallback we write ourselves is ours, so it is a
' key read with the rest.
function ImportFailuresText(failures as object) as object
    out = []
    if failures = invalid then return out
    for each failure in failures
        text = ImportFailureText(failure)
        if text <> "" then out.Push(text)
    end for
    return out
end function

function ImportFailureText(failure as object) as string
    if failure = invalid then return ""
    id = failure.id
    error = failure.error
    if error = invalid or error = "" then error = Lang("main", "importItemFailed")
    if id <> invalid and id <> "" then return id + ": " + error
    return error
end function

' A button press does not dismiss a StandardMessageDialog on its own — it only
' sets buttonSelected. Mirror the exit confirm: close through the dialog's own
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
        ShowExitConfirm()
        return true
    end if

    return false
end function
