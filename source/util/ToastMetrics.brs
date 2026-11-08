' ToastMetrics — the toast's pure sizing/duration decisions, kept out of the
' component so the test suite can reach them (components do not share scope
' with the combined test script, and a second init() would collide there).

function ToastDuration(kind as string) as float
    if kind = "error" then return 6.0
    return 4.0
end function

function ToastPlateWidth(text as string) as integer
    width = 72 + text.Len() * 19
    if width > 1400 then return 1400
    if width < 280 then return 280
    return width
end function

function ToastPlateHeight(text as string, width as integer) as integer
    charsPerLine = Int((width - 40) / 19)
    if charsPerLine < 1 then charsPerLine = 1
    lines = Int((text.Len() + charsPerLine - 1) / charsPerLine)
    if lines < 1 then lines = 1
    if lines > 3 then lines = 3
    return 48 * lines + 48
end function
