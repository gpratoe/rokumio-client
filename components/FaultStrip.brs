' FaultStrip — the Scene's shared sticky/transient fault display.
'
' The strip owns its state, its one dismissal timer, and the two nodes it
' paints. MainScene keeps the reporting functions screens already call and
' forwards to this component, so this extraction does not widen the screen
' contract or make every screen learn about the strip.

sub init()
    m.top.width = 1920
    m.top.height = 1080
    m.storeFaults = {}
    m.transientFaults = {}

    palette = Theme()

    m.bar = CreateObject("roSGNode", "Rectangle")
    m.bar.width = 1920
    m.bar.height = 80
    m.bar.translation = [0, 1000]
    m.bar.color = palette.danger
    m.bar.visible = false
    m.top.AppendChild(m.bar)

    m.label = CreateObject("roSGNode", "Label")
    m.label.translation = [40, 1020]
    m.label.width = 1840
    m.label.height = 44
    m.label.font = "font:MediumBoldSystemFont"
    m.label.color = palette.textWhite
    m.label.visible = false
    m.top.AppendChild(m.label)

    m.timer = m.top.FindNode("dismissTimer")
    m.timer.ObserveField("fire", "onDismissTimerFire")
end sub

' Faults keyed by reason, not by screen: a dozen screens hitting the same
' hand-off failure should produce one line. active=false clears the sticky
' reason.
sub ReportStoreFault(reason as string, active as boolean)
    if reason = "" then return
    if active then
        m.storeFaults[reason] = true
    else
        m.storeFaults.Delete(reason)
    end if
    Refresh()
end sub

' A transient fault holds the strip for a few seconds and then dismisses
' itself. Every report restarts the same deadline, so a stream of related
' faults gets one lease rather than one timer per line.
sub ReportTransientFault(reason as string)
    if reason = "" then return
    m.transientFaults[reason] = true
    m.timer.control = "stop"
    m.timer.control = "start"
    Refresh()
end sub

' Retract one transient reason when its owner gets a newer authoritative
' result. A sticky fault with the same wording is unaffected.
sub ClearTransientFault(reason as string)
    if reason = "" then return
    m.transientFaults.Delete(reason)
    Refresh()
end sub

' The one transient lease expired; sticky faults remain visible.
sub onDismissTimerFire()
    m.transientFaults = {}
    Refresh()
end sub

' Paint the union of sticky and transient faults. Sorting keeps a stable order;
' concatenation and direct node fields are deliberate: the first version's
' Join/FindNode shape painted the red bar but left its label blank on device.
sub Refresh()
    shown = {}
    for each reason in m.storeFaults
        shown[reason] = true
    end for
    for each reason in m.transientFaults
        shown[reason] = true
    end for

    reasons = []
    for each reason in shown
        reasons.Push(reason)
    end for
    reasons.Sort()
    line = ""
    for each reason in reasons
        if line <> "" then line = line + "     "
        line = line + reason
    end for

    if line = "" then
        m.bar.visible = false
        m.label.visible = false
        return
    end if
    m.label.text = line
    m.label.visible = true
    m.bar.visible = true
end sub
