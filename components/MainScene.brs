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

    ' Bottom-of-stack Back pushes the confirm-exit dialog; the dialog's
    ' closeRequest is how it asks the Scene to dismiss it.
    m.confirmExit = m.top.FindNode("confirmExitDialog")
    m.confirmExit.ObserveField("closeRequest", "onConfirmExitClose")

    ' Stores are constructed once at the Scene and handed to screens later by
    ' reference. SettingsStore and AddonsStore Load() their persisted state on
    ' construction.
    m.transport = Transport()
    m.settingsStore = SettingsStore(CreateObject("roRegistrySection", "settings"))
    m.authStore = AuthStore()
    m.addonsStore = AddonsStore(m.transport, CreateObject("roRegistrySection", "addons"))
    m.catalogStore = CatalogStore(m.transport)
    m.episodesStore = EpisodesStore(m.transport)
    m.stores = {
        transport: m.transport
        settings: m.settingsStore
        auth: m.authStore
        addons: m.addonsStore
        catalog: m.catalogStore
        episodes: m.episodesStore
    }
    m.homeScreen.callFunc("SetStores", m.stores)
end sub

' The only action channel from Home: one push request, dispatched by the stack.
' No business logic — the Scene stays a thin orchestrator.
sub onHomeAction()
    request = m.homeScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

sub onConfirmExitClose()
    if m.stack.top() <> invalid and m.stack.top().id = "confirmExitDialog"
        if m.stack.count() > 1 then m.stack.pop()
        m.confirmExit.closeRequest = ""
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
