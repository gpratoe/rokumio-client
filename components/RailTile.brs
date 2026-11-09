' RailTile — icon+name tile for the Home left rail. The rail is a Group of
' these, focused one at a time. Collapsed, the icon sits centered; expanded,
' it slides left and the section name fades in on every tile. Focus is icon
' color plus the name's weight — no tile background.

sub init()
    m.glyph = m.top.FindNode("railGlyph")
    m.label = m.top.FindNode("railLabel")
    m.stepTimer = m.top.FindNode("stepTimer")
    m.glyphX = 40
    m.targetX = 40
    m.stepTimer.ObserveField("fire", "onStepFire")
    m.top.ObserveField("focused", "onStateChanged")
    m.top.ObserveField("expanded", "onStateChanged")
    SetLabelFonts()
end sub

sub SetLabelFonts()
    m.labelRegular = CreateObject("roSGNode", "Font")
    m.labelRegular.uri = "pkg:/fonts/OpenSans-Regular.ttf"
    m.labelRegular.size = 30
    m.top.AppendChild(m.labelRegular)
    m.labelBold = CreateObject("roSGNode", "Font")
    m.labelBold.uri = "pkg:/fonts/OpenSans-Bold.ttf"
    m.labelBold.size = 30
    m.top.AppendChild(m.labelBold)
    m.label.font = m.labelRegular
end sub

sub SetTile(glyphUri as string, sectionName as string)
    m.glyph.uri = glyphUri
    m.label.text = sectionName
    ApplyState()
end sub

sub ApplyState()
    t = Theme()
    if m.top.focused
        m.glyph.blendColor = t.accent
        m.label.color = t.navLabelActive
        m.label.font = m.labelBold
    else
        m.glyph.blendColor = t.navIdle
        m.label.color = t.navIdle
        m.label.font = m.labelRegular
    end if
end sub

sub onStateChanged()
    ApplyState()
    m.targetX = 10
    if not m.top.expanded then m.targetX = 40
    if m.glyphX <> m.targetX
        progress = (40 - m.glyphX) / 30
        if progress < 0 then progress = 0
        if progress > 1 then progress = 1
        m.label.opacity = progress
        labelScale = 0.7 + 0.3 * progress
        m.label.scale = [labelScale, labelScale]
        m.label.visible = true
        m.stepTimer.control = "stop"
        m.stepTimer.control = "start"
    else
        m.label.visible = m.top.expanded
    end if
end sub

sub onStepFire()
    if m.glyphX < m.targetX
        m.glyphX = m.glyphX + 2
    else
        m.glyphX = m.glyphX - 2
    end if
    if (m.targetX - m.glyphX) * (m.targetX - m.glyphX) <= 4 then m.glyphX = m.targetX
    m.glyph.translation = [m.glyphX, 10]
    progress = (40 - m.glyphX) / 30
    m.label.opacity = progress
    labelScale = 0.7 + 0.3 * progress
    m.label.scale = [labelScale, labelScale]
    if m.glyphX = m.targetX
        m.stepTimer.control = "stop"
        m.label.opacity = 1
        m.label.scale = [1.0, 1.0]
        m.label.visible = m.top.expanded
    end if
end sub
