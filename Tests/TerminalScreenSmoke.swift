import Foundation

@main
enum TerminalScreenSmoke {
    static func main() {
        let screen = TerminalScreen()
        screen.resize(columns: 100, rows: 30)
        screen.consume("\u{001B}[?2004hruiqian@FnNas:~$ pwd\r\n\u{001B}[?2004l/home/ruiqian\r\n\u{001B}[?2004h")

        let output = screen.render()
        precondition(output.contains("ruiqian@FnNas:~$ pwd"))
        precondition(output.contains("/home/ruiqian"))
        precondition(!output.contains("[?2004"))

        screen.consume("\u{001B}[H\u{001B}[2Jclean")
        precondition(screen.render() == "clean")
        precondition(screen.cursorLocation == 5)

        screen.consume("\u{001B}[?25l")
        precondition(!screen.isCursorVisible)
        screen.consume("\u{001B}[?25h")
        precondition(screen.isCursorVisible)

        let splitSequenceScreen = TerminalScreen()
        splitSequenceScreen.consume("\u{001B}[?")
        splitSequenceScreen.consume("2004hprompt")
        splitSequenceScreen.consume("\u{001B}[")
        splitSequenceScreen.consume("K")
        precondition(splitSequenceScreen.render() == "prompt")

        let c1Screen = TerminalScreen()
        c1Screen.consume("\u{009B}?2004hprompt\u{009B}K")
        precondition(c1Screen.render() == "prompt")

        let topScreen = TerminalScreen()
        topScreen.resize(columns: 80, rows: 5)
        topScreen.consume("shell prompt")
        topScreen.consume("\u{001B}[?1049h\u{001B}[H\u{001B}[2Jtop frame 1\r\nprocess A")
        precondition(topScreen.usesFixedScreen)
        precondition(topScreen.render().contains("top frame 1"))
        precondition(!topScreen.render().contains("shell prompt"))

        topScreen.consume("\u{001B}[H\u{001B}[2Jtop frame 2\r\nprocess B")
        let refreshed = topScreen.render()
        precondition(refreshed.contains("top frame 2"))
        precondition(refreshed.contains("process B"))
        precondition(!refreshed.contains("top frame 1"))
        precondition(!refreshed.contains("process A"))

        topScreen.consume("\u{001B}[?1049l")
        precondition(!topScreen.usesFixedScreen)
        precondition(topScreen.render() == "shell prompt")

        let fnNasTop = TerminalScreen()
        fnNasTop.resize(columns: 80, rows: 5)
        fnNasTop.consume("shell prompt\r\n")
        fnNasTop.consume("\u{001B}[?1h\u{001B}=\u{001B}[H\u{001B}[2Jtop frame 1\r\nprocess A\r\nrow 3")
        fnNasTop.consume("\u{001B}[Htop frame 2\r\nprocess B\r\nrow 3")
        let fnNasRefreshed = fnNasTop.render()
        precondition(fnNasRefreshed.contains("top frame 2"))
        precondition(fnNasRefreshed.contains("process B"))
        precondition(!fnNasRefreshed.contains("top frame 1"))
        precondition(!fnNasRefreshed.contains("process A"))
        precondition(fnNasRefreshed.split(whereSeparator: \.isNewline).count <= 5)

        let alignedTop = TerminalScreen()
        alignedTop.resize(columns: 80, rows: 5)
        alignedTop.consume("\u{001B}[?1049h\u{001B}[H  PID USER      %CPU  COMMAND   \r\n    1 root       0.0  systemd   ")
        let alignedRows = alignedTop.render().split(separator: "\n", omittingEmptySubsequences: false)
        precondition(alignedRows[0] == "  PID USER      %CPU  COMMAND")
        precondition(alignedRows[1] == "    1 root       0.0  systemd")

        let lineFeedScreen = TerminalScreen()
        lineFeedScreen.resize(columns: 20, rows: 5)
        lineFeedScreen.consume("\u{001B}[?1049h12345\u{001B}[2D\nX")
        let lineFeedRows = lineFeedScreen.render().split(separator: "\n", omittingEmptySubsequences: false)
        precondition(lineFeedRows[0] == "12345")
        precondition(lineFeedRows[1] == "   X")

        let editScreen = TerminalScreen()
        editScreen.resize(columns: 20, rows: 5)
        editScreen.consume("\u{001B}[?1049habcdef\u{001B}[3D\u{001B}[2PXY")
        precondition(editScreen.render().split(separator: "\n", omittingEmptySubsequences: false)[0] == "abcXY")

        let insertScreen = TerminalScreen()
        insertScreen.resize(columns: 20, rows: 5)
        insertScreen.consume("\u{001B}[?1049habcdef\u{001B}[3D\u{001B}[2@XY")
        precondition(insertScreen.render().split(separator: "\n", omittingEmptySubsequences: false)[0] == "abcXYdef")

        let scrollingScreen = TerminalScreen()
        scrollingScreen.resize(columns: 20, rows: 5)
        scrollingScreen.consume("\u{001B}[?1049h1\r\n2\r\n3\r\n4\r\n5")
        scrollingScreen.consume("\u{001B}[2;4r\u{001B}[4;1H\nX")
        let scrollingRows = scrollingScreen.render().split(separator: "\n", omittingEmptySubsequences: false)
        precondition(scrollingRows[0] == "1")
        precondition(scrollingRows[1] == "3")
        precondition(scrollingRows[2] == "4")
        precondition(scrollingRows[3] == "X")
        precondition(scrollingRows[4] == "5")

        let resizedScreen = TerminalScreen()
        resizedScreen.resize(columns: 20, rows: 5)
        resizedScreen.consume("\u{001B}[?1049h")
        resizedScreen.resize(columns: 20, rows: 8)
        resizedScreen.consume("\u{001B}[8;1Hbottom\r\nnext")
        let resizedRows = resizedScreen.render().split(separator: "\n", omittingEmptySubsequences: false)
        precondition(resizedRows.count == 8)
        precondition(resizedRows[6] == "bottom")
        precondition(resizedRows[7] == "next")
    }
}
