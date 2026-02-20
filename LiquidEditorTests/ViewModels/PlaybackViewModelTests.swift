import Testing
@testable import LiquidEditor

// MARK: - PlaybackViewModel Tests

@Suite("PlaybackViewModel Tests")
@MainActor
struct PlaybackViewModelTests {

    // MARK: - Helpers

    private func makeVM() -> PlaybackViewModel {
        PlaybackViewModel()
    }

    // MARK: - Initial State

    @Suite("Initial State")
    @MainActor
    struct InitialStateTests {

        @Test("Not playing on init")
        func notPlaying() {
            let vm = PlaybackViewModel()
            #expect(vm.isPlaying == false)
        }

        @Test("Current time is 0 on init")
        func currentTimeZero() {
            let vm = PlaybackViewModel()
            #expect(vm.currentTime == 0)
        }

        @Test("Total duration is 0 on init")
        func totalDurationZero() {
            let vm = PlaybackViewModel()
            #expect(vm.totalDuration == 0)
        }

        @Test("Playback rate is 1.0 on init")
        func defaultRate() {
            let vm = PlaybackViewModel()
            #expect(vm.playbackRate == 1.0)
        }

        @Test("Volume is 1.0 on init")
        func defaultVolume() {
            let vm = PlaybackViewModel()
            #expect(vm.volume == 1.0)
        }

        @Test("Not muted on init")
        func notMuted() {
            let vm = PlaybackViewModel()
            #expect(vm.isMuted == false)
        }

        @Test("Not looping on init")
        func notLooping() {
            let vm = PlaybackViewModel()
            #expect(vm.isLooping == false)
        }
    }

    // MARK: - Toggle Play/Pause (without engine)

    @Test("togglePlayPause without engine does nothing to isPlaying")
    func togglePlayPauseNoEngine() {
        let vm = makeVM()
        // Without an engine, togglePlayPause dispatches an async Task
        // that short-circuits at the guard. isPlaying is not toggled directly.
        vm.togglePlayPause()
        // isPlaying is set by engine events, not by togglePlayPause directly
        #expect(vm.isPlaying == false)
    }

    @Test("play without engine does not crash")
    func playNoEngine() {
        let vm = makeVM()
        vm.play()
        // No crash - early return due to nil engine
        #expect(vm.isPlaying == false)
    }

    @Test("pause without engine does not crash")
    func pauseNoEngine() {
        let vm = makeVM()
        vm.pause()
        #expect(vm.isPlaying == false)
    }

    // MARK: - Formatted Time Strings

    @Test("formattedCurrentTime at 0 returns 00:00.00")
    func formattedCurrentTimeZero() {
        let vm = makeVM()
        #expect(vm.formattedCurrentTime == "00:00.00")
    }

    @Test("formattedCurrentTime formats 90.5 seconds correctly")
    func formattedCurrentTime90s() {
        let vm = makeVM()
        vm.updateCurrentTime(90_500_000) // 1 min 30.5 sec
        #expect(vm.formattedCurrentTime == "01:30.50")
    }

    @Test("formattedTotalDuration at 0 returns 00:00.00")
    func formattedTotalDurationZero() {
        let vm = makeVM()
        #expect(vm.formattedTotalDuration == "00:00.00")
    }

    @Test("formattedTotalDuration formats 120 seconds correctly")
    func formattedTotalDuration120s() {
        let vm = makeVM()
        vm.updateTotalDuration(120_000_000) // 2 minutes
        #expect(vm.formattedTotalDuration == "02:00.00")
    }

    // MARK: - Progress Computed Property

    @Test("progress is 0 when totalDuration is 0")
    func progressZeroDuration() {
        let vm = makeVM()
        #expect(vm.progress == 0.0)
    }

    @Test("progress is 0 when currentTime is 0")
    func progressZeroTime() {
        let vm = makeVM()
        vm.updateTotalDuration(10_000_000)
        #expect(vm.progress == 0.0)
    }

    @Test("progress at halfway is 0.5")
    func progressHalfway() {
        let vm = makeVM()
        vm.updateTotalDuration(10_000_000)
        vm.updateCurrentTime(5_000_000)
        #expect(vm.progress == 0.5)
    }

    @Test("progress is clamped to 1.0")
    func progressClamped() {
        let vm = makeVM()
        vm.updateTotalDuration(10_000_000)
        vm.updateCurrentTime(15_000_000) // Exceeds total
        #expect(vm.progress == 1.0)
    }

    @Test("progress at end is 1.0")
    func progressAtEnd() {
        let vm = makeVM()
        vm.updateTotalDuration(10_000_000)
        vm.updateCurrentTime(10_000_000)
        #expect(vm.progress == 1.0)
    }

    // MARK: - Mute

    @Test("toggleMute toggles isMuted")
    func toggleMute() {
        let vm = makeVM()
        #expect(vm.isMuted == false)

        vm.toggleMute()
        #expect(vm.isMuted == true)

        vm.toggleMute()
        #expect(vm.isMuted == false)
    }

    @Test("effectiveVolume is 0 when muted")
    func effectiveVolumeMuted() {
        let vm = makeVM()
        vm.toggleMute()
        #expect(vm.effectiveVolume == 0.0)
    }

    @Test("effectiveVolume matches volume when not muted")
    func effectiveVolumeNotMuted() {
        let vm = makeVM()
        vm.setVolume(0.75)
        #expect(vm.effectiveVolume == 0.75)
    }

    // MARK: - Set Rate

    @Test("setRate changes playback rate")
    func setRate() {
        let vm = makeVM()
        vm.setRate(2.0)
        #expect(vm.playbackRate == 2.0)
    }

    @Test("setRate to 0.5")
    func setRateHalf() {
        let vm = makeVM()
        vm.setRate(0.5)
        #expect(vm.playbackRate == 0.5)
    }

    // MARK: - Formatted Rate

    @Test("formattedRate at 1.0 is '1x'")
    func formattedRate1x() {
        let vm = makeVM()
        #expect(vm.formattedRate == "1x")
    }

    @Test("formattedRate at 2.0 is '2x'")
    func formattedRate2x() {
        let vm = makeVM()
        vm.setRate(2.0)
        #expect(vm.formattedRate == "2x")
    }

    @Test("formattedRate at 0.5 is '0.5x'")
    func formattedRateHalf() {
        let vm = makeVM()
        vm.setRate(0.5)
        #expect(vm.formattedRate == "0.5x")
    }

    @Test("formattedRate at 0.25 is '0.25x'")
    func formattedRateQuarter() {
        let vm = makeVM()
        vm.setRate(0.25)
        #expect(vm.formattedRate == "0.25x")
    }

    @Test("formattedRate at 1.5 is '1.5x'")
    func formattedRate1Point5() {
        let vm = makeVM()
        vm.setRate(1.5)
        #expect(vm.formattedRate == "1.5x")
    }

    // MARK: - Cycle Rate

    @Test("cycleRate cycles through available rates")
    func cycleRate() {
        let vm = makeVM()
        let rates = PlaybackViewModel.availableRates

        // Start at 1.0
        #expect(vm.playbackRate == 1.0)

        // Find index of 1.0 and cycle forward
        guard let idx = rates.firstIndex(of: 1.0) else {
            Issue.record("1.0 not found in available rates")
            return
        }

        vm.cycleRate()
        let nextIdx = (idx + 1) % rates.count
        #expect(vm.playbackRate == rates[nextIdx])
    }

    @Test("cycleRate from unknown rate resets to 1.0")
    func cycleRateFromUnknown() {
        let vm = makeVM()
        vm.setRate(3.5) // Not in availableRates
        vm.cycleRate()
        #expect(vm.playbackRate == 1.0)
    }

    // MARK: - Looping

    @Test("toggleLooping toggles isLooping")
    func toggleLooping() {
        let vm = makeVM()
        #expect(vm.isLooping == false)

        vm.toggleLooping()
        #expect(vm.isLooping == true)

        vm.toggleLooping()
        #expect(vm.isLooping == false)
    }

    // MARK: - Volume

    @Test("setVolume clamps to 0.0-1.0 range")
    func setVolumeClamps() {
        let vm = makeVM()

        vm.setVolume(-0.5)
        #expect(vm.volume == 0.0)

        vm.setVolume(1.5)
        #expect(vm.volume == 1.0)

        vm.setVolume(0.5)
        #expect(vm.volume == 0.5)
    }

    // MARK: - External Updates

    @Test("updateCurrentTime sets current time directly")
    func updateCurrentTime() {
        let vm = makeVM()
        vm.updateCurrentTime(3_000_000)
        #expect(vm.currentTime == 3_000_000)
    }

    @Test("updateTotalDuration sets total duration")
    func updateTotalDuration() {
        let vm = makeVM()
        vm.updateTotalDuration(60_000_000)
        #expect(vm.totalDuration == 60_000_000)
    }

    // MARK: - Seek (without engine)

    @Test("seek without engine does not change currentTime")
    func seekWithoutEngine() {
        let vm = makeVM()
        vm.seek(to: 5_000_000)
        // seek guards on engine, so without one currentTime stays at 0
        #expect(vm.currentTime == 0)
    }

    // MARK: - Available Rates

    @Test("Available rates contain expected presets")
    func availableRatesPresets() {
        let rates = PlaybackViewModel.availableRates
        #expect(rates.contains(0.25))
        #expect(rates.contains(0.5))
        #expect(rates.contains(1.0))
        #expect(rates.contains(1.5))
        #expect(rates.contains(2.0))
        #expect(rates.count == 5)
    }
}
