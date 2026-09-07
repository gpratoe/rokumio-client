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
        message = Wait(0, port)
        if Type(message) = "roSGScreenEvent" and message.IsScreenClosed()
            return
        else if Type(message) = "roSGNodeEvent" and message.GetField() = "exitApp" and scene.exitApp = true
            return
        end if
    end while
end sub