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
