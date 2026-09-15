' LinkStremioScreen — displays the link-code pairing UI.
'
' Observes the LinkStremioTask's code/link fields to show the pairing info, and
' the result field to detect completion or failure. Back publishes a cancelLogin
' pushRequest; MainScene cancels the task and pops back to AuthScreen.

sub init()
    m.codeLabel = m.top.FindNode("pairCode")
    m.urlLabel = m.top.FindNode("pairUrl")
    m.statusLabel = m.top.FindNode("pairStatus")
    m.qrPoster = m.top.FindNode("pairQr")
    m.qrFallback = m.top.FindNode("pairQrFallback")
    m.taskNode = invalid
end sub

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    m.taskNode = m.top.taskNode
    if m.taskNode = invalid then return
    m.codeLabel.text = m.taskNode.code
    m.urlLabel.text = m.taskNode.link
    m.statusLabel.text = "Waiting for link..."
    m.taskNode.ObserveField("code", "onTaskCode")
    m.taskNode.ObserveField("link", "onTaskLink")
    m.taskNode.ObserveField("qrcode", "onTaskQrcode")
    m.taskNode.ObserveField("result", "onTaskResult")

    ' The task runs on a worker thread and may finish pairing or fail before
    ' this screen starts observing, and a result written before registration
    ' never refires. Re-read it so a settled task still lands on screen.
    if m.taskNode.qrcode <> invalid and m.taskNode.qrcode <> "" and m.qrPoster.uri <> m.taskNode.qrcode
        ShowQr(m.taskNode.qrcode)
    end if
    result = m.taskNode.result
    if result <> invalid then onTaskResult()
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    m.top.pushRequest = { action: "cancelLogin" }
    return true
end function

sub BlurFocus()
end sub

sub onTaskCode()
    if m.taskNode = invalid then return
    m.codeLabel.text = m.taskNode.code
end sub

sub onTaskLink()
    if m.taskNode = invalid then return
    m.urlLabel.text = m.taskNode.link
end sub

sub onTaskQrcode()
    if m.taskNode = invalid then return
    qrcode = m.taskNode.qrcode
    if qrcode <> invalid and qrcode <> ""
        ShowQr(qrcode)
    end if
end sub

sub ShowQr(url as string)
    m.qrFallback.visible = false
    m.qrPoster.uri = url
    m.qrPoster.ObserveField("loadStatus", "onQrLoadStatus")
end sub

sub onQrLoadStatus()
    status = m.qrPoster.loadStatus
    if status = "error"
        m.qrPoster.visible = false
        m.qrFallback.visible = true
    else
        m.qrPoster.visible = true
        m.qrFallback.visible = false
    end if
end sub

sub onTaskResult()
    if m.taskNode = invalid then return
    result = m.taskNode.result
    if result = invalid then return
    if result.ok
        m.statusLabel.text = "Logged in!"
        m.top.pushRequest = { action: "completeLogin", authKey: result.authKey, user: result.user }
    else
        ' Failure stays on screen so the user can read the error; Back is the
        ' exit (it publishes cancelLogin). A transient network hiccup must not
        ' boot the user off the pairing screen.
        msg = result.error
        if msg = invalid or msg = "" then msg = "Login failed"
        m.statusLabel.text = msg
    end if
end sub
