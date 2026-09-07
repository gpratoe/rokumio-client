' ConfirmExitDialog — the modal confirm for quitting the app.
'
' Pushed as a regular stack screen, so it gets the same contract and focus
' handling as any other screen. Left/right (or up/down) move between the two
' buttons; OK activates the focused one. Exit drops the channel via the Scene's
' exitApp (picked up by main.brs), Cancel and Back dismiss the dialog.
'
' Exiting via the Scene, not a pop: exitApp closes the channel, which is all
' the dialog wants. Cancel signals MainScene through closeRequest so the Scene
' pops the dialog and refocuses Home.

sub init()
    m.buttons = [
        { id: "btnCancel", node: m.top.FindNode("btnCancel") }
        { id: "btnExit", node: m.top.FindNode("btnExit") }
    ]
    m.focusedButton = 0
end sub

function OnEnter(params as object) as void
    SetActiveButton(0)
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

sub SetActiveButton(index as integer)
    m.focusedButton = (index + m.buttons.Count()) mod m.buttons.Count()
    for i = 0 to m.buttons.Count() - 1
        entry = m.buttons[i]
        border = entry.node.FindNode(entry.id + "Border")
        face = entry.node.FindNode(entry.id + "Face")
        if i = m.focusedButton
            border.color = "0x5BEF95FF"
            face.color = "0x233329FF"
        else
            border.color = "0x2BD67500"
            face.color = "0x18231CFF"
        end if
    end for
    m.buttons[m.focusedButton].node.SetFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "left" or key = "up"
        SetActiveButton(m.focusedButton - 1)
        return true
    else if key = "right" or key = "down"
        SetActiveButton(m.focusedButton + 1)
        return true
    else if key = "OK"
        if m.focusedButton = 1
            m.top.getScene().exitApp = true
        else
            m.top.closeRequest = "cancel"
        end if
        return true
    end if

    return false
end function