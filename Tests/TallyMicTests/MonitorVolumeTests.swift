import Testing
@testable import TallyMic

@Suite("Monitor volume")
struct MonitorVolumeTests {
    /// 32 steps (twice macOS's 16), snapping to the nearest step first, and stopping at the ends.
    @Test func stepsInThirtySeconds() {
        #expect(MonitorVolume(level: 0.5).pressing(.up).level == 17.0 / 32)
        #expect(MonitorVolume(level: 0.5).pressing(.down).level == 15.0 / 32)
        #expect(MonitorVolume(level: 0.51).pressing(.up).level == 17.0 / 32)
        #expect(MonitorVolume(level: 1).pressing(.up).level == 1)
        #expect(MonitorVolume(level: 0).pressing(.down).level == 0)
        // A monitor at 13 of 100 when it's found: the next step up is 5/32, which it gets as 16.
        #expect(MonitorVolume(level: 0.13).pressing(.up).ddcValue(max: 100) == 16)
    }

    /// ⇧⌥ steps by the monitor's own smallest step, often 1 of 100.
    @Test func fineStepsAreTheMonitorsOwn() {
        #expect(MonitorVolume(level: 0.5).pressing(.up, steps: 100).ddcValue(max: 100) == 51)
        #expect(MonitorVolume(level: 0.13).pressing(.down, steps: 100).ddcValue(max: 100) == 12)
    }

    /// The mute key toggles and keeps the level; volume up or down unmutes.
    @Test func muteLikeMacOS() {
        let muted = MonitorVolume(level: 0.5).pressing(.mute)
        #expect(muted == MonitorVolume(level: 0.5, muted: true))
        #expect(muted.pressing(.mute) == MonitorVolume(level: 0.5))
        #expect(muted.pressing(.up) == MonitorVolume(level: 17.0 / 32))
        #expect(muted.pressing(.down) == MonitorVolume(level: 15.0 / 32))
    }

    @Test func whatTheMonitorAndBubbleGet() {
        #expect(MonitorVolume(level: 0.5).ddcValue(max: 100) == 50)
        #expect(MonitorVolume(level: 0.5, muted: true).ddcValue(max: 100) == 0)
        #expect(MonitorVolume(level: 0.5).litSegments == 8)
        #expect(MonitorVolume(level: 17.0 / 32).litSegments == 8.5)
        #expect(MonitorVolume(level: 0.5, muted: true).litSegments == 0)
        #expect(MonitorVolume(level: 0.5).symbol == "speaker.wave.2.fill")
        #expect(MonitorVolume(level: 0.1).symbol == "speaker.wave.1.fill")
        #expect(MonitorVolume(level: 0.9).symbol == "speaker.wave.3.fill")
        #expect(MonitorVolume(level: 0).symbol == "speaker.slash.fill")
        #expect(MonitorVolume(level: 0.5, muted: true).symbol == "speaker.slash.fill")
    }

    /// The bytes after the host address, as the DDC/CI standard lays them out.
    @Test func ddcRequests() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x62 ^ 0x00 ^ 0x32
        #expect(DDC.setRequest(0x62, 50) == [0x84, 0x03, 0x62, 0x00, 0x32, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x62 ^ 0x32])
        #expect(DDC.getRequest(0x62) == [0x82, 0x01, 0x62, 0x6E ^ 0x82 ^ 0x01 ^ 0x62])
        #expect(DDC.getRequest(0x62, standard: true) == [0x82, 0x01, 0x62, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x62])
    }

    @Test func ddcReplies() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 0x64, 0x00, 0x28]
        reply.append(DDC.checksum(0x50, reply))
        #expect(DDC.parseReply(reply, code: 0x62).map { [$0.current, $0.max] } == [40, 100])

        var corrupted = reply
        corrupted[9] = 0x29
        #expect(DDC.parseReply(corrupted, code: 0x62) == nil)
        #expect(DDC.parseReply(reply, code: 0x10) == nil)
        #expect(DDC.parseReply(Array(reply.prefix(5)), code: 0x62) == nil)
    }

    /// A made-up display's sound output: vendor 0xABCD, then product 0x1234 low byte first.
    @Test func matchesADisplaysSoundOutput() {
        let ids = DisplayAudio.displayIDs(fromOutputUID: "ABCD3412-0000-0000-0000-000000000000")
        #expect(ids?.vendor == 0xABCD)
        #expect(ids?.product == 0x1234)
        #expect(DisplayAudio.displayIDs(fromOutputUID: "BuiltInSpeakerDevice") == nil)
        #expect(DisplayAudio.displayIDs(fromOutputUID: "AA-BB-CC-DD-EE-FF:output") == nil)
        #expect(DisplayAudio.displayIDs(fromOutputUID: "AppleUSBAudioEngine:Unknown Manufacturer:Wireless Headset Receiver:0123456789abcdef:2") == nil)
    }
}
