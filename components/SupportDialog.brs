' SupportDialog — the native "buy you a coffee" modal.
'
' A StandardDialog presented through the Scene's dialog field, same as
' ConfirmExitDialog. The side card shows a QR the user scans with their phone;
' which platform appears is decided by the Scene from the device's country code
' and handed in through Configure(). A single Close button (or Back/Home)
' dismisses it.

sub init()
    m.top.width = "1380"
    m.top.palette = AppPalette()
    m.qrPoster = m.top.FindNode("qrPoster")
    m.top.observeFieldScoped("buttonSelected", "onButtonSelected")
end sub

' The Scene calls this with "cafecito" or "buymeacoffee" before showing.
sub Configure(platform as string)
    if platform = "cafecito"
        m.qrPoster.uri = "pkg:/images/qr-cafecito.png"
    else
        m.qrPoster.uri = "pkg:/images/qr-buymeacoffee.png"
    end if
end sub

' Single Close button; Back/Home are handled by the system.
sub onButtonSelected()
    m.top.close = true
end sub
