/// Contains information about the media, such as duration, resolution, and frame rate.
class MediaInfo {
  /// The duration of the media.
  final Duration duration;
  
  /// The width of the video in pixels.
  final int width;
  
  /// The height of the video in pixels.
  final int height;
  
  /// The frame rate of the video (frames per second).
  final double fps;
  
  /// The audio sample rate in Hertz.
  final int audioSampleRate;
  
  /// The number of audio channels.
  final int audioChannels;

  /// The estimated total number of frames in the video.
  final int totalFrames;

  MediaInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.audioSampleRate,
    required this.audioChannels,
    required this.totalFrames,
  });

  @override
  String toString() {
    return 'MediaInfo(duration: $duration, video: ${width}x$height @ $fps fps, totalFrames: $totalFrames, audio: $audioChannels ch @ $audioSampleRate Hz)';
  }
}
