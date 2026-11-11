' SearchKeyboard — the DynamicMiniKeyboard extension that makes the search
' pane escapable. The built-in keyboard consumes its arrows natively, and
' consumed keys never bubble past the node (a screen-level onKeyEvent never
' sees them), so pane hand-off has to be detected inside the node's own
' onKeyEvent — the one scope extended components get native keys in.
'
' The mechanism is "no move means edge": arrows are passed to the native
' handler (return false), and a 0.06s probe timer afterwards checks whether
' the key grid's focus actually moved. If it did not, the grid was already
' at that edge, and the key is published to the screen as a pane escape
' instead of being lost. The counter of keyFocused changes is monotonic
' rather than label-based, so identical labels cannot fake or mask a move.
'
' The pane has two focus states and the extension routes between them:
'   edit-field state — the internal VoiceTextEditBox (the visible query box)
'       holds focus. This is the dictation-ready state: the OS routes the
'       remote's mic button to the FOCUSED voice-enabled field, and an
'       unfocused one falls through to the system-wide voice search. Down
'       steps into the key grid; OK fires the query immediately.
'   grid state — the key grid holds focus; typing works, arrows travel the
'       grid, and the bottom/right edges escape to the results. The top
'       edge returns to the edit-field state.

sub init()
    m.keyGrid = m.top.keyGrid
    ' Voice config is deliberately NOT set here. The internal VoiceTextEditBox
    ' is NOT voice-enabled at creation on-device (it reads false, docs
    ' notwithstanding), and writes to it at creation time are dropped — the
    ' dictation UI is not listening yet, the reason the dialog-era code
    ' applied its config only after the node was built. The entry path
    ' asserts voiceEnabled and the mode post-creation in SearchScreen's
    ' FocusQueryBox.
    m.focusSeq = 0
    m.seqBefore = -1
    m.pendingKey = ""
    m.keyGrid.ObserveField("keyFocused", "onKeyFocused")
    m.edgeTimer = m.top.FindNode("edgeTimer")
    if m.edgeTimer <> invalid then m.edgeTimer.ObserveField("fire", "onEdgeTimer")
end sub

' Every real focus move inside the grid advances the counter. A press that
' leaves it standing is the edge signal.
sub onKeyFocused()
    m.focusSeq = m.focusSeq + 1
end sub

' The probe window closed: if the press produced no focus movement, the grid
' was at the edge — hand the key to the screen as a pane escape.
sub onEdgeTimer()
    if m.pendingKey = "" then return
    if m.focusSeq = m.seqBefore then m.top.escape = m.pendingKey
    m.pendingKey = ""
    m.seqBefore = -1
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "options"
        m.top.escape = "options"
        return true
    end if

    if m.top.textEditBox.HasFocus()
        ' Edit-field state: Down steps into the key grid (typing), OK fires
        ' the query at once. Caret arrows stay with the field.
        if key = "down"
            m.keyGrid.SetFocus(true)
            return true
        else if key = "OK"
            m.top.escape = "OK"
            return true
        end if
        return false
    end if

    if key = "down" or key = "right"
        m.pendingKey = key
        m.seqBefore = m.focusSeq
        if m.edgeTimer <> invalid
            m.edgeTimer.control = "stop"
            m.edgeTimer.control = "start"
        end if
    else if key = "up"
        ' Probe the top edge the same way: no movement up there means the
        ' user wants back to the dictation-ready query box.
        m.pendingKey = "up"
        m.seqBefore = m.focusSeq
        if m.edgeTimer <> invalid
            m.edgeTimer.control = "stop"
            m.edgeTimer.control = "start"
        end if
    end if

    return false
end function
