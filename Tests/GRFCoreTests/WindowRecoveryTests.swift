import Testing
import GRFDesktop

@MainActor
private final class TestWindow: MainWindowHandle {
    var isMiniaturized = false
    var restored = 0
    var broughtForward = 0
    func deminiaturize(_ sender: Any?) { isMiniaturized = false; restored += 1 }
    func makeKeyAndOrderFront(_ sender: Any?) { broughtForward += 1 }
}

@MainActor
struct WindowRecoveryTests {
    @Test func dockReopenRestoresMinimizedWindowWithoutLosingItsState() {
        var created = 0, activated = 0
        let recovery = WindowRecovery(createWindow: { created += 1 }, activate: { activated += 1 })
        let window = TestWindow()
        window.isMiniaturized = true
        recovery.window = window
        recovery.reopen()
        #expect(!window.isMiniaturized)
        #expect(window.restored == 1 && window.broughtForward == 1)
        #expect(created == 0 && activated == 1)
        #expect(recovery.window === window)
    }

    @Test func visibleWindowIsBroughtForwardWithoutCreatingADuplicate() {
        var created = 0
        let recovery = WindowRecovery(createWindow: { created += 1 })
        let window = TestWindow()
        recovery.window = window
        recovery.reopen()
        recovery.reopen()
        #expect(window.broughtForward == 2 && window.restored == 0)
        #expect(created == 0)
    }

    @Test func closingTheLastWindowCanOpenTheMainSceneAgain() {
        var created = 0, activated = 0
        let recovery = WindowRecovery(createWindow: { created += 1 }, activate: { activated += 1 })
        recovery.reopen()
        #expect(created == 1 && activated == 1)
    }
}
