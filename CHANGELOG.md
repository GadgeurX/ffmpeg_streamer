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