## 0.0.1

* Initial release.
* Added `FfmpegDecoder` with video and audio rendering support.
* Supported platforms: Android, iOS, macOS, Windows, Linux.

## 0.1.0

* Added `getFrameAtTimestamp` method to retrieve a frame at a specific timestamp.
* Added `getFrameAtIndex` method to retrieve a frame at a specific index.
* Added native C implementation for seeking and frame extraction with thread safety.

## 0.2.0

* **Breaking Changes**: Removed callback-based streaming API in favor of synchronous frame retrieval.
* Removed `startDecoding`, `pause`, and `resume` methods - replaced with direct frame access.
* Separated frame retrieval methods into video and audio specific functions:
  - `getVideoFrameAtTimestamp` and `getAudioFrameAtTimestamp`
  - `getVideoFrameAtIndex` and `getAudioFrameAtIndex`
* Added `freeVideoFrame` and `freeAudioFrame` methods for proper memory management.
* Simplified API for more flexible frame-by-frame control.

## 0.3.0

* **Major Update**: Added asynchronous API with native threading for high-performance video decoding.
* Added `getFrameAtIndexAsync` method for non-blocking frame retrieval with callbacks.
* Added `getFramesRangeByIndexAsync` method for ultra-fast batch frame decoding (87% faster than sequential calls).
* Implemented native pthread-based worker thread for zero UI blocking.
* Added `cancelRequest` method to cancel pending asynchronous decode operations.
* Added progress callbacks for batch operations to track decoding progress in real-time.
* Performance improvement: Decoding 100 frames reduced from ~15s to ~2s using batch API.
* Updated example app with play/pause functionality and optimized playback mode.
* Added frame scrubbing with slider control in example app.
* Maintained backward compatibility with existing synchronous API.

## 0.3.1

* Fix Warnings

## 0.4.0

* **New High-Level API**: Added `FFmpegService` - a simplified service layer that abstracts away decoder complexity.
* **Intelligent Batch Management**: Introduced `FrameBatchManager` with automatic frame caching and smart preloading:
  - Automatic batch loading and memory management
  - LRU (Least Recently Used) cache eviction strategy
  - Predictive preloading of adjacent batches for smooth playback
  - Configurable batch sizes and cache limits
  - Real-time cache statistics (batches, frames, memory usage)
* **Batch Configuration Presets**: Added `BatchConfigPresets` with 7 predefined configurations:
  - `standard` - Balanced for most use cases (~1.25 GB for 1080p)
  - `highPerformance` - Optimized for smooth playback (~2.5 GB for 1080p)
  - `memoryEfficient` - For limited devices (~375 MB for 1080p)
  - `video4K` - Optimized for 4K videos (~1.5 GB)
  - `scrubbing` - For timeline navigation (~2 GB for 1080p)
  - `editing` - Workflow optimized (~1.5 GB for 1080p)
  - `slowMotion` - For frame analysis (~1 GB for 1080p)
* **Automatic Configuration Selection**: `getRecommendedConfig()` method automatically selects optimal settings based on video resolution and available memory.
* **Enhanced Video Metadata**: New `VideoMetadata` class with comprehensive video information.
* **Memory Estimation Tools**: Added methods to estimate memory usage for different configurations and resolutions.
* **Simplified Example App**: Completely refactored example app to use `FFmpegService`:
  - Reduced code complexity by 35% (~220 lines removed)
  - Automatic batch management with no manual configuration needed
  - Real-time cache statistics display
  - Cleaner, more maintainable code structure
* **Batch Loading Events**: Stream-based event system for monitoring batch operations (loading, progress, completion, failures).
* **Better Resource Management**: Automatic cleanup of distant batches based on current playback position.
* **Export Organization**: All new services properly exported in main library file for easy access.