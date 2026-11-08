' Toast — the Scene's transient notification. A small rounded plate,
' bottom-center, with a soft shadow and an accent edge, fading in and out.
' The rounding rides a nine-patch image, so no Effect node is needed.

sub init()
    palette = Theme()
    m.group = m.top.FindNode("toastGroup")
    m.shadow = CreateObject("roSGNode", "Poster")
    m.shadow.uri = "pkg:/images/toast.9.png"
    m.shadow.loadWidth = 84
    m.shadow.loadHeight = 84
    m.shadow.blendColor = "0x00000066"
    m.group.AppendChild(m.shadow)
    m.border = CreateObject("roSGNode", "Poster")
    m.border.uri = "pkg:/images/toast.9.png"
    m.border.loadWidth = 84
    m.border.loadHeight = 84
    m.border.blendColor = palette.borderSoft
    m.group.AppendChild(m.border)
    m.plate = CreateObject("roSGNode", "Poster")
    m.plate.uri = "pkg:/images/toast.9.png"
    m.plate.loadWidth = 84
    m.plate.loadHeight = 84
    m.plate.blendColor = palette.dropdownBg
    m.group.AppendChild(m.plate)
    m.label = CreateObject("roSGNode", "Label")
    m.label.font = "font:MediumBoldSystemFont"
    m.label.color = palette.textWhite
    m.label.wrap = true
    m.label.horizAlign = "center"
    m.label.vertAlign = "center"
    m.group.AppendChild(m.label)
    m.shownText = ""
    m.shownKind = ""
    m.timer = m.top.FindNode("dismissTimer")
    m.timer.ObserveField("fire", "onDismissTimerFire")
    m.hideTimer = m.top.FindNode("hideTimer")
    m.hideTimer.ObserveField("fire", "onHideTimerFire")
    m.fadeIn = m.top.FindNode("toastFadeIn")
    m.fadeOut = m.top.FindNode("toastFadeOut")
end sub

sub Notify(text as string, kind = "info" as string)
    if text = "" then return
    if text = m.shownText and kind = m.shownKind
        RestartTimer(kind)
        return
    end if
    m.shownText = text
    m.shownKind = kind
    Paint()
    RestartTimer(kind)
end sub

sub RestartTimer(kind as string)
    m.hideTimer.control = "stop"
    if m.fadeOut <> invalid then m.fadeOut.control = "stop"
    m.group.opacity = 1
    m.group.visible = true
    if m.fadeIn <> invalid
        m.fadeIn.control = "stop"
        m.fadeIn.control = "start"
    end if
    m.timer.duration = ToastDuration(kind)
    m.timer.control = "stop"
    m.timer.control = "start"
end sub

sub Paint()
    width = ToastPlateWidth(m.shownText)
    height = ToastPlateHeight(m.shownText, width)
    x = (1920 - width) / 2
    y = 1000 - height
    m.shadow.width = width
    m.shadow.height = height
    m.shadow.translation = [x, y + 8]
    m.border.width = width + 6
    m.border.height = height + 6
    m.border.translation = [x - 3, y - 3]
    if m.shownKind = "error"
        m.border.blendColor = Theme().danger
    else
        m.border.blendColor = Theme().borderSoft
    end if
    m.plate.width = width
    m.plate.height = height
    m.plate.translation = [x, y]
    m.label.text = m.shownText
    m.label.width = width - 64
    m.label.height = height - 28
    m.label.translation = [x + 32, y + 14]
end sub

sub onDismissTimerFire()
    if m.fadeOut <> invalid
        m.fadeOut.control = "stop"
        m.fadeOut.control = "start"
    end if
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

sub onHideTimerFire()
    m.shownText = ""
    m.shownKind = ""
    m.group.visible = false
    m.group.opacity = 1
end sub
