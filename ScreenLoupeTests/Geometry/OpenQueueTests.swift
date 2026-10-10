import Foundation
import Testing

struct OpenQueueTests {
    private let a = URL(fileURLWithPath: "/a.png")
    private let b = URL(fileURLWithPath: "/b.png")
    private let c = URL(fileURLWithPath: "/c.png")

    @Test func whileLaunchingNothingOpens() {
        var queue = OpenQueue()
        #expect(queue.receive([a, b]) == [])
    }

    @Test func launchingOpensWhatWaited() {
        var queue = OpenQueue()
        _ = queue.receive([a, b])
        #expect(queue.finishLaunching() == [a, b])
    }

    @Test func requestsWhileLaunchingWaitInOrder() {
        var queue = OpenQueue()
        _ = queue.receive([a])
        _ = queue.receive([b, c])
        #expect(queue.finishLaunching() == [a, b, c])
    }

    @Test func aLaunchWithoutFilesOpensNone() {
        var queue = OpenQueue()
        #expect(queue.finishLaunching() == [])
    }

    @Test func afterLaunchingARequestOpensAtOnce() {
        var queue = OpenQueue()
        _ = queue.finishLaunching()
        #expect(queue.receive([a, b]) == [a, b])
    }

    @Test func whatWaitedOpensOnce() {
        var queue = OpenQueue()
        _ = queue.receive([a])
        _ = queue.finishLaunching()
        #expect(queue.finishLaunching() == [])
    }

    @Test func afterLaunchingNothingWaits() {
        var queue = OpenQueue()
        _ = queue.finishLaunching()
        _ = queue.receive([a])
        #expect(queue.finishLaunching() == [])
    }

    @Test func anEmptyRequestOpensNone() {
        var queue = OpenQueue()
        _ = queue.finishLaunching()
        #expect(queue.receive([]) == [])
    }
}
