sub Main(args as object)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    ' ECP "input" (POST /input?<query params>) marshals its arguments straight
    ' to the running app as an roInputEvent (see reference/ecp-integration.md).
    ' Unlike /launch it does NOT relaunch the channel, so a deep link can land
    ' on the live instance. The port is shared with the screen; the loop below
    ' type-dispatches the events. The reference is deliberately held for the
    ' whole Main lifetime.
    input = CreateObject("roInput")
    input.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    scene.ObserveField("exitApp", port)
    screen.Show()
    scene.callFunc("Start")
    ' An ECP deep link (rokumio-<verb>, see reference/ecp-integration.md) rides
    ' the launch args. Handle it after Start so the stack is up and Home is the
    ' base; the flow reports through a dialog and never replaces Home.
    scene.callFunc("HandleDeepLink", args)
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
            if Type(message) = "roInputEvent"
                scene.callFunc("HandleDeepLink", message.GetInfo())
            else if Type(message) = "roSGScreenEvent" and message.IsScreenClosed()
                return
            else if Type(message) = "roSGNodeEvent" and message.GetField() = "exitApp" and scene.exitApp = true
                return
            end if
        end if
    end while
end sub
