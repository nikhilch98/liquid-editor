# Performance Standards

This app must maintain **premium performance** at all times.

---

## Target Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Frame Rate** | 60 FPS | Consistent during video playback and UI animations |
| **App Launch** | < 2 seconds | Cold start to interactive UI |
| **Video Playback Start** | < 500ms | Time to first frame |
| **Gesture Response** | < 16ms | Touch to visual feedback |
| **Transform Interpolation** | < 1ms | Single interpolation calculation |
| **Memory Usage** | < 200MB | Peak during video editing session (excluding frame cache) |
| **Build Size** | < 100MB | App bundle size |

---

## Timeline Architecture V2 Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Timeline lookup | < 100us | O(log n) tree traversal |
| Edit operation | < 1ms | Path copying + AVL rebalance |
| Undo/Redo | < 10us | O(1) pointer swap |
| Scrub (cached) | < 2ms | Frame cache hit |
| Scrub (uncached) | < 50ms | Decode + display |
| Composition rebuild | < 20ms | Background thread |
| Frame cache | < 300MB | 120 frames at 1080p |

---

## Optimization Guidelines

### CPU

- Main thread reserved for UI only (no heavy computation)
- Background work isolated in actors (`PlaybackEngine`, export pipeline)
- Use `TaskGroup` for parallel processing where appropriate
- Minimize SwiftUI view body recomputations
- Use `@Observable` for fine-grained observation (only affected views recompute)
- Use Instruments Time Profiler to identify hotspots

### Memory

- Release video frames immediately after processing
- Use `autoreleasepool` for batch Core Foundation/Core Image operations
- Implement LRU caches with size limits (FrameCache, ThumbnailCache)
- Respond to `UIApplication.didReceiveMemoryWarningNotification`
- Structural sharing in PersistentTimeline minimizes duplicate allocations
- Monitor with Instruments Allocations and Leaks

### I/O

- Batch file operations
- Use streaming APIs for large files
- Cache expensive computations (thumbnails, waveforms)
- Async file access via actor isolation (never block main thread)
- Auto-save with debounce to avoid excessive writes

### GPU (Metal)

- Use Metal for video compositing and effects rendering
- Minimize shader complexity -- profile with Metal System Trace
- Batch draw calls where possible
- Optimize texture uploads (use shared/managed storage mode)
- Reuse command buffers and pipeline state objects
- Use CIContext with Metal device for Core Image integration

### Metal Shader Performance

- **Shader compilation:** Pre-compile shaders at build time (Metal shader archives)
- **Texture sampling:** Use bilinear filtering; avoid trilinear unless necessary
- **Memory bandwidth:** Minimize texture reads per fragment
- **Occupancy:** Keep register usage low for better GPU occupancy
- **Synchronization:** Minimize CPU-GPU sync points; use triple buffering

---

## Profiling with Instruments

### Time Profiler
- Identify CPU hotspots on main thread
- Verify < 16ms frame budget during playback
- Check for unexpected work on main thread

### Allocations
- Monitor memory growth over editing session
- Verify LRU cache eviction is working
- Check for unexpected retained objects

### Leaks
- Run periodically to verify no memory leaks
- Pay special attention to closures capturing `self`
- Verify `deinit` is called for ViewModels when views disappear

### Metal System Trace
- Profile GPU shader execution time
- Identify texture bandwidth bottlenecks
- Verify GPU is not idle waiting for CPU
- Check for pipeline stalls and bubbles

### System Trace
- Verify no main thread blocking
- Check inter-thread communication overhead
- Monitor actor hop latency

### Network (if applicable)
- iCloud sync bandwidth usage
- Media import download performance

---

## Performance Testing Checklist

- [ ] App remains responsive during all interactions (no UI jank)
- [ ] Memory usage stable over 5+ minute editing sessions (no growth over time)
- [ ] CPU usage < 50% average during idle editing
- [ ] 60fps maintained during timeline scrubbing and playback
- [ ] Gesture response < 16ms (tap, drag, pinch)
- [ ] Frame cache hit rate > 90% during normal scrubbing
- [ ] Undo/redo is instantaneous (< 10us)
- [ ] Export does not block UI
- [ ] Timeline operations with 100+ clips remain responsive
- [ ] Battery drain reasonable during extended sessions

---

## Build Performance

- **xcodegen generate:** Should complete in < 5 seconds
- **Incremental build:** Should complete in < 30 seconds for single-file changes
- **Full build:** Should complete in < 3 minutes
- **Test suite:** All 1,918 tests should complete in < 2 minutes

---

**Last Updated:** 2026-02-13
