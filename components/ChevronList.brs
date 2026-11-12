' ChevronList — a single-column vertical list of custom row components with a
' fixed visible window and chevron indicators when items are hidden above/below.
'
' Custom-node implementation (no RowList): rows are instantiated from
' rowComponent and driven via itemContent/itemHasFocus/rowHasFocus. Navigation
' and selection are handled here; consumers observe rowItemFocused/rowItemSelected
' ([row, col]) and set content/focusRow as before.

sub init()
    m.rowsClip = m.top.FindNode("rowsClip")
    m.rowsGroup = m.rowsClip.CreateChild("Group")
    m.chevronUp = m.top.FindNode("chevronUp")
    m.chevronDown = m.top.FindNode("chevronDown")

    m.chevronUp.width = 48
    m.chevronUp.height = 28
    m.chevronDown.width = 48
    m.chevronDown.height = 28

    m.rowNodes = []
    m.itemNodes = []
    m.focusedIndex = -1
    m.firstVisible = 0
    m.hasFocus = false
    m.pendingFocus = -1
    m.suppressFocusEmit = false
    m.rowSlot = 118

    m.top.ObserveField("content", "onContent")
    m.top.ObserveField("numRows", "onGeometry")
    m.top.ObserveField("itemWidth", "onGeometry")
    m.top.ObserveField("rowHeight", "onGeometry")
    m.top.ObserveField("rowComponent", "onGeometry")
    m.top.ObserveField("showChevrons", "UpdateWindow")
    m.top.ObserveField("focusedChild", "onFocusChildChanged")

    RecomputeGeometry()
end sub

function HasListFocus() as boolean
    return m.hasFocus or m.top.IsInFocusChain()
end function

sub SetListFocus()
    m.hasFocus = true
    m.top.SetFocus(true)
    ApplyFocusState()
end sub

sub BlurListFocus()
    m.hasFocus = false
    ApplyFocusState()
end sub

sub onFocusChildChanged()
    ' Track focus entering/leaving this component.
    if m.top.IsInFocusChain()
        m.hasFocus = true
    else
        m.hasFocus = false
    end if
    ApplyFocusState()
end sub

sub onGeometry()
    RecomputeGeometry()
    RebuildRows()
    EnsureVisible(m.focusedIndex)
    ApplyLayout()
    ApplyFocusState()
    UpdateWindow()
end sub

sub RecomputeGeometry()
    numVisible = m.top.numRows
    if numVisible < 1 then numVisible = 1
    m.rowSlot = m.top.rowHeight + 8
    clipH = numVisible * m.rowSlot - 8
    if clipH < m.rowSlot then clipH = m.rowSlot
    m.rowsClip.clippingRect = [0, 0, m.top.itemWidth, clipH]
    listHeight = clipH
    cx = (m.top.itemWidth - 48) / 2
    if cx < 0 then cx = 0
    m.chevronUp.translation = [cx, -36]
    m.chevronDown.translation = [cx, listHeight + 8]
end sub

sub onContent()
    ' Remember target before rebuild/reset so focus can be restored without
    ' forwarding a spurious reset to row 0.
    m.pendingFocus = m.top.focusRow
    if m.pendingFocus = invalid then m.pendingFocus = 0
    RebuildRows()
    ApplyInitialFocus()
    EnsureVisible(m.focusedIndex)
    ApplyLayout()
    ApplyFocusState()
    UpdateWindow()
end sub

sub RebuildRows()
    while m.rowsGroup.GetChildCount() > 0
        m.rowsGroup.RemoveChildIndex(0)
    end while
    m.rowNodes = []
    m.itemNodes = []

    root = m.top.content
    total = 0
    if root <> invalid then total = root.GetChildCount()

    y = 0
    for i = 0 to total - 1
        rowContent = root.GetChild(i)
        item = invalid
        if rowContent <> invalid
            if rowContent.GetChildCount() > 0
                item = rowContent.GetChild(0)
            else
                item = rowContent
            end if
        end if
        m.itemNodes.Push(item)

        row = m.rowsGroup.CreateChild(m.top.rowComponent)
        row.translation = [0, y]
        if item <> invalid then row.itemContent = item
        row.itemHasFocus = false
        row.rowHasFocus = false
        m.rowNodes.Push(row)
        y = y + m.rowSlot
    end for
end sub

sub ApplyInitialFocus()
    total = m.rowNodes.Count()
    if total = 0
        m.focusedIndex = -1
        m.firstVisible = 0
        m.pendingFocus = -1
        return
    end if

    target = m.pendingFocus
    if target < 0 then target = 0
    if target >= total then target = total - 1
    m.pendingFocus = -1

    ' Set focus state without emitting intermediate reset events.
    m.suppressFocusEmit = true
    m.focusedIndex = target
    m.suppressFocusEmit = false
    EmitFocused()
end sub

sub EnsureVisible(index as integer)
    total = m.rowNodes.Count()
    if total = 0 or index < 0
        m.firstVisible = 0
        return
    end if
    visible = m.top.numRows
    if visible < 1 then visible = 1
    if index < m.firstVisible
        m.firstVisible = index
    else if index >= m.firstVisible + visible
        m.firstVisible = index - visible + 1
    end if
    maxFirst = total - visible
    if maxFirst < 0 then maxFirst = 0
    if m.firstVisible > maxFirst then m.firstVisible = maxFirst
    if m.firstVisible < 0 then m.firstVisible = 0
end sub

sub ApplyLayout()
    m.rowsGroup.translation = [0, -(m.firstVisible * m.rowSlot)]
end sub

sub ApplyFocusState()
    focused = HasListFocus()
    for i = 0 to m.rowNodes.Count() - 1
        row = m.rowNodes[i]
        if row = invalid then continue for
        row.rowHasFocus = focused
        row.itemHasFocus = focused and i = m.focusedIndex
    end for
end sub

sub MoveFocus(delta as integer)
    total = m.rowNodes.Count()
    if total = 0 then return
    nextIndex = m.focusedIndex + delta
    if nextIndex < 0 then nextIndex = 0
    if nextIndex >= total then nextIndex = total - 1
    if nextIndex = m.focusedIndex then return
    m.focusedIndex = nextIndex
    EnsureVisible(m.focusedIndex)
    ApplyLayout()
    ApplyFocusState()
    UpdateWindow()
    EmitFocused()
end sub

sub EmitFocused()
    if m.suppressFocusEmit then return
    if m.focusedIndex < 0 then return
    m.top.rowItemFocused = [m.focusedIndex, 0]
end sub

sub EmitSelected()
    if m.focusedIndex < 0 then return
    m.top.rowItemSelected = [m.focusedIndex, 0]
end sub

sub EmitFocusExit(direction as string)
    BlurListFocus()
    m.top.focusExit = direction
end sub

sub UpdateWindow()
    total = m.rowNodes.Count()
    visible = m.top.numRows
    if visible < 1 then visible = 1
    lastVisible = m.firstVisible + visible - 1
    if lastVisible > total - 1 then lastVisible = total - 1
    show = m.top.showChevrons = true and total > 0
    if m.chevronUp <> invalid then m.chevronUp.visible = show and m.firstVisible > 0
    if m.chevronDown <> invalid then m.chevronDown.visible = show and lastVisible < total - 1
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if not HasListFocus() then return false
    if key = "up"
        if m.top.exitUp and (m.focusedIndex <= 0 or m.rowNodes.Count() = 0)
            EmitFocusExit("up")
        else
            MoveFocus(-1)
        end if
        return true
    else if key = "down"
        MoveFocus(1)
        return true
    else if key = "OK"
        EmitSelected()
        return true
    else if key = "options" and m.top.exitOptions
        EmitFocusExit("options")
        return true
    end if
    return false
end function
