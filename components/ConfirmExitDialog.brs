' ConfirmExitDialog — the native confirm for quitting the app.
'
' A StandardDialog presented through the Scene's dialog field, not a stack
' screen: MainScene assigns scene.dialog on a bottom-of-stack Back, and the
' system handles the modal focus + dimming. Back/Home dismiss the dialog
' automatically (wasClosed); the app only reacts to a button pick. OK on Exit
' drops the channel via the Scene's exitApp (picked up by main.brs); Cancel
' closes the dialog through the standard close field.

sub init()
    m.top.palette = AppPalette()
    m.top.observeFieldScoped("buttonSelected", "onButtonSelected")
end sub

' One palette for both native dialogs; the app's dark/green look.
function AppPalette() as object
    palette = CreateObject("roSGNode", "RSGPalette")
    palette.colors = {
        DialogBackgroundColor: "0x101813FF"
        DialogItemColor: "0x2BD675FF"
        DialogTextColor: "0xE9F2ECFF"
        DialogFocusColor: "0x2BD675FF"
        DialogFocusItemColor: "0x0A0F0CFF"
        DialogSecondaryTextColor: "0x8FA399FF"
        DialogSecondaryItemColor: "0x2BD6754D"
        DialogInputFieldColor: "0x101813FF"
        DialogKeyboardColor: "0x101813FF"
        DialogFootprintColor: "0x2BD67533"
    }
    return palette
end function

' Buttons are ordered Cancel (0), Exit (1) in the XML button area.
sub onButtonSelected()
    if m.top.buttonSelected = 1
        m.top.getScene().exitApp = true
    else
        m.top.close = true
    end if
end sub