' AddAddonDialog — hybrid add-on install dialog (SupportDialog-style).
' Shows browser install info (local setup URL) and offers manual manifest URL entry.

sub init()
    m.top.width = "900"
    m.titleArea = m.top.FindNode("titleArea")
    m.contentText = m.top.FindNode("contentText")
    m.manualButton = m.top.FindNode("manualButton")
    m.closeButton = m.top.FindNode("closeButton")
    m.top.observeFieldScoped("buttonSelected", "onButtonSelected")
end sub

sub Configure(setupUrl as dynamic, texts = invalid as dynamic)
    url = ""
    if setupUrl <> invalid then url = setupUrl.ToStr().Trim()
    t = {}
    if texts <> invalid then t = texts

    if m.titleArea <> invalid then m.titleArea.primaryTitle = GetText(t, "title")
    if m.manualButton <> invalid then m.manualButton.text = GetText(t, "manualButton")
    if m.closeButton <> invalid then m.closeButton.text = GetText(t, "closeButton")

    if m.contentText <> invalid
        if url <> ""
            m.contentText.text = GetText(t, "browserInstallPrefix") + url
        else
            m.contentText.text = GetText(t, "manualInstallOnly")
        end if
    end if
end sub

function GetText(texts as object, key as string) as string
    if texts <> invalid and texts[key] <> invalid then return texts[key].ToStr()
    return ""
end function

sub onButtonSelected()
    m.top.close = true
end sub
