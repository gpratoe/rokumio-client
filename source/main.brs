sub Main(args as object)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    scene.ObserveField("exitApp", port)
    screen.Show()
    scene.callFunc("Start")
    scene.SignalBeacon("AppLaunchComplete")

    while true
        message = Wait(300, port)
        if message = invalid
            ' Poll fallback: field polling does not depend on port delivery, so
            ' the exit dialog always closes the channel even if the event path
            ' dies.
            if scene.exitApp = true
                return
            end if
        else
            if Type(message) = "roSGScreenEvent" and message.IsScreenClosed()
                return
            else if Type(message) = "roSGNodeEvent" and message.GetField() = "exitApp" and scene.exitApp = true
                return
            end if
        end if
    end while
end sub
