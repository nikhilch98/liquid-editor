import Foundation

// MARK: - ViewportState

/// Immutable viewport state for timeline visualization.
struct ViewportState: Codable, Equatable, Hashable, Sendable {
    /// Scroll position (microseconds at left edge of viewport).
    let scrollPosition: TimeMicros

    /// Zoom level (microseconds per pixel).
    let microsPerPixel: Double

    /// Viewport width in pixels.
    let viewportWidth: Double

    /// Viewport height in pixels.
    let viewportHeight: Double

    /// Vertical scroll offset (for multi-track scrolling).
    let verticalOffset: Double

    /// Ruler height in pixels.
    let rulerHeight: Double

    /// Track header width in pixels.
    let trackHeaderWidth: Double

    init(
        scrollPosition: TimeMicros,
        microsPerPixel: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        verticalOffset: Double = 0,
        rulerHeight: Double = 30,
        trackHeaderWidth: Double = 80
    ) {
        self.scrollPosition = scrollPosition
        self.microsPerPixel = microsPerPixel
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.verticalOffset = verticalOffset
        self.rulerHeight = rulerHeight
        self.trackHeaderWidth = trackHeaderWidth
    }

    /// Default viewport state.
    static func initial(
        viewportWidth: Double = 400,
        viewportHeight: Double = 300
    ) -> ViewportState {
        ViewportState(
            scrollPosition: 0,
            microsPerPixel: defaultMicrosPerPixel,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
    }

    // MARK: - Zoom Constants

    /// Maximum zoom in (~10ms per pixel, frame-level detail).
    static let minMicrosPerPixel: Double = 100.0

    /// Maximum zoom out (~100ms per pixel, overview).
    static let maxMicrosPerPixel: Double = 100000.0

    /// Default zoom level (~10ms per pixel).
    static let defaultMicrosPerPixel: Double = 10000.0

    // MARK: - Computed Properties

    /// Visible time range.
    var visibleTimeRange: TimeRange {
        let startMicros = scrollPosition
        let endMicros = scrollPosition + TimeMicros((contentWidth * microsPerPixel).rounded())
        return TimeRange(startMicros, endMicros)
    }

    /// Content area width (viewport minus track header).
    var contentWidth: Double { viewportWidth - trackHeaderWidth }

    /// Content area height (viewport minus ruler).
    var contentHeight: Double { viewportHeight - rulerHeight }

    /// Visible duration in microseconds.
    var visibleDuration: TimeMicros { TimeMicros((contentWidth * microsPerPixel).rounded()) }

    /// Pixels per microsecond (inverse of zoom).
    var pixelsPerMicrosecond: Double { 1.0 / microsPerPixel }

    // MARK: - Coordinate Conversion

    /// Convert time to pixel X coordinate (relative to content area).
    func timeToPixelX(_ time: TimeMicros) -> Double {
        Double(time - scrollPosition) / microsPerPixel
    }

    /// Convert time to absolute pixel X (including track header offset).
    func timeToAbsolutePixelX(_ time: TimeMicros) -> Double {
        trackHeaderWidth + timeToPixelX(time)
    }

    /// Convert pixel X coordinate to time (relative to content area).
    func pixelXToTime(_ pixelX: Double) -> TimeMicros {
        scrollPosition + TimeMicros((pixelX * microsPerPixel).rounded())
    }

    /// Convert absolute pixel X to time (accounting for track header).
    func absolutePixelXToTime(_ absolutePixelX: Double) -> TimeMicros {
        pixelXToTime(absolutePixelX - trackHeaderWidth)
    }

    /// Convert track index to pixel Y.
    func trackIndexToPixelY(_ trackIndex: Int, trackHeight: Double) -> Double {
        rulerHeight + Double(trackIndex) * trackHeight - verticalOffset
    }

    /// Convert pixel Y to track index.
    func pixelYToTrackIndex(_ pixelY: Double, trackHeight: Double) -> Int {
        Int(((pixelY - rulerHeight + verticalOffset) / trackHeight).rounded(.down))
    }

    // MARK: - State Updates (return new instances)

    /// Create copy with updated values.
    func with(
        scrollPosition: TimeMicros? = nil,
        microsPerPixel: Double? = nil,
        viewportWidth: Double? = nil,
        viewportHeight: Double? = nil,
        verticalOffset: Double? = nil,
        rulerHeight: Double? = nil,
        trackHeaderWidth: Double? = nil
    ) -> ViewportState {
        ViewportState(
            scrollPosition: scrollPosition ?? self.scrollPosition,
            microsPerPixel: microsPerPixel ?? self.microsPerPixel,
            viewportWidth: viewportWidth ?? self.viewportWidth,
            viewportHeight: viewportHeight ?? self.viewportHeight,
            verticalOffset: verticalOffset ?? self.verticalOffset,
            rulerHeight: rulerHeight ?? self.rulerHeight,
            trackHeaderWidth: trackHeaderWidth ?? self.trackHeaderWidth
        )
    }

    /// Update scroll position with bounds checking.
    func withScrollPosition(_ newPosition: TimeMicros, maxPosition: TimeMicros? = nil) -> ViewportState {
        var clamped = newPosition
        if clamped < 0 { clamped = 0 }
        if let maxPos = maxPosition, clamped > maxPos { clamped = maxPos }
        return with(scrollPosition: clamped)
    }

    /// Update zoom level with bounds checking.
    func withZoom(_ newMicrosPerPixel: Double) -> ViewportState {
        let clamped = min(max(newMicrosPerPixel, ViewportState.minMicrosPerPixel), ViewportState.maxMicrosPerPixel)
        return with(microsPerPixel: clamped)
    }

    /// Zoom centered on a specific time.
    func zoomCenteredOnTime(_ newMicrosPerPixel: Double, centerTime: TimeMicros) -> ViewportState {
        let clamped = min(max(newMicrosPerPixel, ViewportState.minMicrosPerPixel), ViewportState.maxMicrosPerPixel)
        let pixelX = timeToPixelX(centerTime)
        let newScrollPosition = centerTime - TimeMicros((pixelX * clamped).rounded())
        return with(
            scrollPosition: newScrollPosition < 0 ? 0 : newScrollPosition,
            microsPerPixel: clamped
        )
    }

    /// Zoom centered on viewport center.
    func zoomCenteredOnViewport(_ newMicrosPerPixel: Double) -> ViewportState {
        let centerTime = pixelXToTime(contentWidth / 2)
        return zoomCenteredOnTime(newMicrosPerPixel, centerTime: centerTime)
    }

    /// Update viewport dimensions.
    func withDimensions(width: Double, height: Double) -> ViewportState {
        with(viewportWidth: width, viewportHeight: height)
    }

    /// Scroll to center a specific time.
    func scrollToCenter(_ time: TimeMicros) -> ViewportState {
        let newScrollPosition = time - TimeMicros((contentWidth / 2 * microsPerPixel).rounded())
        return withScrollPosition(newScrollPosition < 0 ? 0 : newScrollPosition)
    }

    /// Scroll by pixel delta.
    func scrollByPixels(_ deltaPixels: Double, maxPosition: TimeMicros? = nil) -> ViewportState {
        let timeDelta = TimeMicros((deltaPixels * microsPerPixel).rounded())
        return withScrollPosition(scrollPosition + timeDelta, maxPosition: maxPosition)
    }

    /// Scroll vertically by pixel delta.
    func scrollVertically(_ deltaPixels: Double, maxOffset: Double? = nil) -> ViewportState {
        var newOffset = verticalOffset + deltaPixels
        if newOffset < 0 { newOffset = 0 }
        if let maxOff = maxOffset, newOffset > maxOff { newOffset = maxOff }
        return with(verticalOffset: newOffset)
    }

    // MARK: - Utility Methods

    /// Check if a time range is visible.
    func isTimeRangeVisible(_ range: TimeRange) -> Bool {
        visibleTimeRange.overlaps(range)
    }

    /// Check if a time is visible.
    func isTimeVisible(_ time: TimeMicros) -> Bool {
        visibleTimeRange.contains(time)
    }

    /// Calculate zoom to fit a duration in the viewport.
    func zoomToFitDuration(_ duration: TimeMicros, margin: Double = 0.1) -> Double {
        let availableWidth = contentWidth * (1 - margin * 2)
        return Double(duration) / availableWidth
    }
}
