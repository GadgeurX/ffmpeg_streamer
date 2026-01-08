import 'dart:async';
import 'dart:ui' as ui;
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  FfmpegDecoder? _decoder;
  MediaInfo? _mediaInfo;
  ui.Image? _currentFrame;
  int _currentFrameIndex = 0;
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isPlayingOptimized = false;
  Timer? _playTimer;
  int? _currentRequestId;
  int? _rangeRequestId;
  final List<VideoFrame> _frameBuffer = [];
  int _bufferPlayIndex = 0;

  @override
  void dispose() {
    _playTimer?.cancel();
    _decoder?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      await _openMedia(result.files.single.path!);
    }
  }

  Future<void> _openMedia(String path) async {
    // Stop playing if playing
    _stopPlaying();
    _stopPlayingOptimized();

    // Cleanup previous
    await _decoder?.release();
    setState(() {
      _mediaInfo = null;
      _currentFrame = null;
      _currentFrameIndex = 0;
    });

    try {
      final decoder = FfmpegDecoder();
      final success = await decoder.openMedia(path);

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to open media file')),
          );
        }
        return;
      }

      setState(() {
        _decoder = decoder;
        _mediaInfo = _createMediaInfo(decoder);
      });

      // Get first frame async
      _getFrameAsync(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening media: $e')),
        );
      }
    }
  }

  MediaInfo _createMediaInfo(FfmpegDecoder decoder) {
    return MediaInfo(
      width: decoder.videoWidth,
      height: decoder.videoHeight,
      fps: decoder.fps,
      duration: Duration(milliseconds: decoder.durationMs),
      totalFrames: decoder.totalFrames,
      audioSampleRate: decoder.audioSampleRate,
      audioChannels: decoder.audioChannels,
    );
  }

  void _getFrameAsync(int frameIndex) {
    if (_decoder == null || _mediaInfo == null) return;
    
    // Clamp frame index
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= _mediaInfo!.totalFrames) {
      frameIndex = _mediaInfo!.totalFrames - 1;
      if (_isPlaying) {
        _stopPlaying();
      }
    }

    // Cancel previous request if any
    if (_currentRequestId != null) {
      _decoder!.cancelRequest(_currentRequestId!);
    }

    setState(() {
      _isLoading = true;
    });

    final requestedFrameIndex = frameIndex; // Capture the requested index
    
    print('Requesting frame $requestedFrameIndex'); // Debug
    
    _currentRequestId = _decoder!.getFrameAtIndexAsync(frameIndex, (frame) async {
      _currentRequestId = null;
      
      print('Received frame for request $requestedFrameIndex: ${frame != null}'); // Debug
      
      if (frame?.video != null) {
        await _renderFrame(frame!.video!, requestedFrameIndex);
      } else {
        print('WARNING: No video frame received for index $requestedFrameIndex');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _renderFrame(VideoFrame frame, int requestedFrameIndex) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.rgbaBytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        completer.complete(image);
      },
    );
    final image = await completer.future;

    if (mounted) {
      setState(() {
        _currentFrame = image;
        // Use the requested frame index instead of frame.frameId which might be unreliable
        _currentFrameIndex = requestedFrameIndex;
      });
    }
  }

  void _goToPreviousFrame() {
    if (_decoder == null || _currentFrameIndex <= 0) return;
    _getFrameAsync(_currentFrameIndex - 1);
  }

  void _goToNextFrame() {
    if (_decoder == null || _mediaInfo == null) return;
    if (_currentFrameIndex >= _mediaInfo!.totalFrames - 1) return;
    _getFrameAsync(_currentFrameIndex + 1);
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _stopPlaying();
    } else {
      _startPlaying();
    }
  }

  void _startPlaying() {
    if (_decoder == null || _mediaInfo == null || _isPlaying) return;

    setState(() {
      _isPlaying = true;
    });

    // Calculate frame duration based on FPS
    final frameDurationMs = (1000 / _mediaInfo!.fps).round();

    _playTimer = Timer.periodic(Duration(milliseconds: frameDurationMs), (timer) {
      if (!_isPlaying || _decoder == null || _mediaInfo == null) {
        timer.cancel();
        return;
      }

      // Skip if already loading a frame
      if (_isLoading) {
        return;
      }

      // Go to next frame
      final nextFrame = _currentFrameIndex + 1;
      
      if (nextFrame >= _mediaInfo!.totalFrames) {
        // End of video, stop playing
        _stopPlaying();
        return;
      }

      _getFrameAsync(nextFrame);
    });
  }

  void _stopPlaying() {
    if (!_isPlaying) return;

    setState(() {
      _isPlaying = false;
    });

    _playTimer?.cancel();
    _playTimer = null;
  }

  // ==================== OPTIMIZED PLAY MODE ====================

  void _togglePlayPauseOptimized() {
    if (_isPlayingOptimized) {
      _stopPlayingOptimized();
    } else {
      _startPlayingOptimized();
    }
  }

  void _startPlayingOptimized() {
    if (_decoder == null || _mediaInfo == null || _isPlayingOptimized) return;

    // Stop normal play if active
    if (_isPlaying) {
      _stopPlaying();
    }

    setState(() {
      _isPlayingOptimized = true;
      _frameBuffer.clear();
      _bufferPlayIndex = 0;
    });

    print('🚀 Starting optimized play from frame $_currentFrameIndex');

    // Load frames in batches
    _loadNextBatch();
  }

  void _loadNextBatch() {
    if (!_isPlayingOptimized || _decoder == null || _mediaInfo == null) return;

    final batchSize = 30; // Load 30 frames at a time
    final startFrame = _currentFrameIndex;
    final endFrame = (startFrame + batchSize - 1).clamp(0, _mediaInfo!.totalFrames - 1);

    if (startFrame >= _mediaInfo!.totalFrames) {
      _stopPlayingOptimized();
      return;
    }

    print('📦 Loading batch: frames $startFrame to $endFrame');

    _rangeRequestId = _decoder!.getFramesRangeByIndexAsync(
      startFrame,
      endFrame,
      (frame) {
        // This callback is called for EACH frame as it's decoded
        if (!_isPlayingOptimized) return;

        if (frame?.video != null) {
          _frameBuffer.add(frame!.video!);
          
          // Start playing from buffer if we have enough frames
          if (_frameBuffer.isNotEmpty && _playTimer == null) {
            _startBufferPlayback();
          }
        }
      },
      progressCallback: (current, total) {
        print('📊 Progress: $current/$total frames loaded');
      },
    );
  }

  void _startBufferPlayback() {
    if (_playTimer != null) return;

    // Calculate frame duration based on FPS
    final frameDurationMs = (1000 / _mediaInfo!.fps).round();

    _playTimer = Timer.periodic(Duration(milliseconds: frameDurationMs), (timer) {
      if (!_isPlayingOptimized) {
        timer.cancel();
        _playTimer = null;
        return;
      }

      // Display next frame from buffer
      if (_bufferPlayIndex < _frameBuffer.length) {
        final frame = _frameBuffer[_bufferPlayIndex];
        _renderFrameSync(frame, _currentFrameIndex);
        _bufferPlayIndex++;
        _currentFrameIndex++;

        // Check if we're near the end of buffer - load next batch
        if (_bufferPlayIndex >= _frameBuffer.length - 5 && _currentFrameIndex < _mediaInfo!.totalFrames) {
          print('🔄 Buffer running low, loading next batch...');
          _frameBuffer.clear();
          _bufferPlayIndex = 0;
          _loadNextBatch();
        }
      } else if (_currentFrameIndex >= _mediaInfo!.totalFrames) {
        // End of video
        _stopPlayingOptimized();
      }
    });
  }

  void _renderFrameSync(VideoFrame frame, int frameIndex) {
    // Synchronous version for buffer playback
    ui.decodeImageFromPixels(
      frame.rgbaBytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) {
          setState(() {
            _currentFrame = image;
            _currentFrameIndex = frameIndex;
          });
        }
      },
    );
  }

  void _stopPlayingOptimized() {
    if (!_isPlayingOptimized) return;

    print('⏹️ Stopping optimized play');

    setState(() {
      _isPlayingOptimized = false;
    });

    _playTimer?.cancel();
    _playTimer = null;

    if (_rangeRequestId != null) {
      _decoder?.cancelRequest(_rangeRequestId!);
      _rangeRequestId = null;
    }

    _frameBuffer.clear();
    _bufferPlayIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FFmpeg Streamer'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          if (_mediaInfo != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.deepPurple.shade50,
              child: Column(
                children: [
                  Text(
                    '${_mediaInfo!.width}x${_mediaInfo!.height} @ ${_mediaInfo!.fps.toStringAsFixed(2)} fps',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Duration: ${_mediaInfo!.duration} | Total frames: ${_mediaInfo!.totalFrames}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current frame: $_currentFrameIndex',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isPlaying || _isPlayingOptimized ? Colors.green : Colors.blue,
                      fontWeight: _isPlaying || _isPlayingOptimized ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (_isPlaying)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow, size: 16, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'PLAYING (Normal)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_isPlayingOptimized)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.flash_on, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            'PLAYING (Optimized) - Buffer: ${_frameBuffer.length} frames',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: _isLoading && _currentFrame == null
                  ? const CircularProgressIndicator()
                  : _currentFrame != null
                      ? AspectRatio(
                          aspectRatio: _mediaInfo!.width / _mediaInfo!.height,
                          child: CustomPaint(
                            painter: VideoPainter(_currentFrame!),
                          ),
                        )
                      : const Text(
                          'No video loaded - Pick a file to start',
                          style: TextStyle(fontSize: 16),
                        ),
            ),
          ),
          
          // Slider for scrubbing
          if (_mediaInfo != null && _currentFrame != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Slider(
                    value: _currentFrameIndex.toDouble(),
                    min: 0,
                    max: (_mediaInfo!.totalFrames - 1).toDouble(),
                    divisions: _mediaInfo!.totalFrames > 1 ? _mediaInfo!.totalFrames - 1 : 1,
                    label: 'Frame $_currentFrameIndex',
                    onChanged: (value) {
                      if (_isPlaying) {
                        _stopPlaying();
                      }
                      if (_isPlayingOptimized) {
                        _stopPlayingOptimized();
                      }
                      _getFrameAsync(value.toInt());
                    },
                  ),
                  Text(
                    'Frame $_currentFrameIndex / ${_mediaInfo!.totalFrames - 1}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Frame index input
                if (_mediaInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Go to frame',
                              border: const OutlineInputBorder(),
                              hintText: '0-${_mediaInfo!.totalFrames - 1}',
                              contentPadding: const EdgeInsets.all(8),
                            ),
                            onSubmitted: (value) {
                              final frameIndex = int.tryParse(value);
                              if (frameIndex != null) {
                                if (_isPlaying) {
                                  _stopPlaying();
                                }
                                _getFrameAsync(frameIndex);
                              }
                            },
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_isPlaying) {
                              _stopPlaying();
                            }
                            final randomIndex =
                                (DateTime.now().millisecondsSinceEpoch %
                                        _mediaInfo!.totalFrames)
                                    .toInt();
                            _getFrameAsync(randomIndex);
                          },
                          icon: const Icon(Icons.shuffle, size: 18),
                          label: const Text('Random'),
                        ),
                      ],
                    ),
                  ),
                // Play/Pause buttons
                if (_decoder != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _togglePlayPause,
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                          label: Text(_isPlaying ? 'Pause' : 'Play'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _togglePlayPauseOptimized,
                          icon: Icon(_isPlayingOptimized ? Icons.pause : Icons.flash_on),
                          label: Text(_isPlayingOptimized ? 'Pause' : 'Play ⚡'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPlayingOptimized ? Colors.deepOrange : Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Navigation buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pick File'),
                    ),
                    if (_decoder != null) ...[
                      ElevatedButton.icon(
                        onPressed: (_isPlaying || _isPlayingOptimized) ? null : _goToPreviousFrame,
                        icon: const Icon(Icons.skip_previous),
                        label: const Text('Prev'),
                      ),
                      ElevatedButton.icon(
                        onPressed: (_isPlaying || _isPlayingOptimized) ? null : _goToNextFrame,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Next'),
                      ),
                    ]
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPainter extends CustomPainter {
  final ui.Image image;

  VideoPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant VideoPainter oldDelegate) {
    return image != oldDelegate.image;
  }
}
