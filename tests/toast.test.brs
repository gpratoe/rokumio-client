' Toast unit tests — the pure sizing/duration half of components/Toast.brs.

sub Test_Toast_Duration()
    Harness_Suite("Toast duration")
    Harness_Equal(ToastDuration("error"), 6.0, "errors hold longer than information")
    Harness_Equal(ToastDuration("info"), 4.0, "information is brief")
    Harness_Equal(ToastDuration("anything"), 4.0, "an unknown kind is brief, not long")
end sub

sub Test_Toast_PlateWidth()
    Harness_Suite("Toast plate width")
    Harness_Equal(ToastPlateWidth("hi"), 300, "a short message gets the minimum plate")
    Harness_Equal(ToastPlateWidth("01234567890123456789"), 476, "twenty characters size from the estimate")
    long = ""
    for i = 1 to 200
        long = long + "x"
    end for
    Harness_Equal(ToastPlateWidth(long), 1400, "a long message is capped")
    Harness_Ok(ToastPlateWidth("a longer notification message") > ToastPlateWidth("hi"), "wider text, wider plate")
end sub

sub Test_Toast_PlateHeight()
    Harness_Suite("Toast plate height")
    Harness_Equal(ToastPlateHeight("hi", 260), 96, "one line is the base height")
    long = ""
    for i = 1 to 200
        long = long + "x"
    end for
    Harness_Equal(ToastPlateHeight(long, 260), 192, "wrapped text grows, capped at three lines")
    medium = ""
    for i = 1 to 100
        medium = medium + "x"
    end for
    Harness_Ok(ToastPlateHeight(medium, 1400) < ToastPlateHeight(medium, 260), "a wider plate wraps less")
end sub
