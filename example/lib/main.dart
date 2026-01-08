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
  final FFmpegService _service = FFmpegService();
  VideoMetadata? _metadata;
  ui.Image? _currentFrame;
  int _currentFrameIndex = 0;
  bool _isLoading = false;
  bool _isPlaying = false;
  Timer? _playTimer;

  @override
  void dispose() {
    _playTimer?.cancel();
    _service.release();
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

    setState(() {
      _metadata = null;
      _currentFrame = null;
      _currentFrameIndex = 0;
    });

    try {
      // Open video with FFmpegService (batch system is automatic)
      final metadata = await _service.openVideo(path);

      if (metadata == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to open media file')),
          );
        }
        return;
      }

      setState(() {
        _metadata = metadata;
      });

      // Get first frame
      await _loadFrame(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening media: $e')),
        );
      }
    }
  }

  Future<void> _loadFrame(int frameIndex) async {
    if (_metadata == null) return;

    // Clamp frame index
    frameIndex = frameIndex.clamp(0, _metadata!.totalFrames - 1);

    setState(() {
      _isLoading = true;
    });

    try {
      // Get frame using FFmpegService (uses batch manager automatically)
      final frameData = await _service.getFrameAtIndex(frameIndex);

      if (frameData != null && mounted) {
        // Convert to Flutter image
        final image = await FFmpegService.convertToFlutterImage(frameData);

        setState(() {
          _currentFrame = image;
          _currentFrameIndex = frameIndex;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading frame: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _goToPreviousFrame() {
    if (_currentFrameIndex <= 0) return;
    _loadFrame(_currentFrameIndex - 1);
  }

  void _goToNextFrame() {
    if (_metadata == null || _currentFrameIndex >= _metadata!.totalFrames - 1) return;
    _loadFrame(_currentFrameIndex + 1);
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _stopPlaying();
    } else {
      _startPlaying();
    }
  }

  void _startPlaying() {
    if (_metadata == null || _isPlaying) return;

    setState(() {
      _isPlaying = true;
    });

    // Calculate frame duration based on FPS
    final frameDurationMs = (1000 / _metadata!.fps).round();

    _playTimer = Timer.periodic(Duration(milliseconds: frameDurationMs), (timer) {
      if (!_isPlaying || _metadata == null) {
        timer.cancel();
        return;
      }

      // Skip if already loading a frame
      if (_isLoading) {
        return;
      }

      // Go to next frame
      final nextFrame = _currentFrameIndex + 1;

      if (nextFrame >= _metadata!.totalFrames) {
        // End of video, stop playing
        _stopPlaying();
        return;
      }

      _loadFrame(nextFrame);
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

  @override
  Widget build(BuildContext context) {
    // Get cache stats for display
    final cacheStats = _service.getCacheStats();

    return Scaffold(
      appBar: AppBar(
        title: const Text('FFmpeg Streamer Example'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          if (_metadata != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.deepPurple.shade50,
              child: Column(
                children: [
                  Text(
                    '${_metadata!.width}x${_metadata!.height} @ ${_metadata!.fps.toStringAsFixed(2)} fps',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total frames: ${_metadata!.totalFrames} | Duration: ${(_metadata!.durationMs / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current frame: $_currentFrameIndex',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isPlaying ? Colors.green : Colors.blue,
                      fontWeight: _isPlaying ? FontWeight.bold : FontWeight.normal,
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
                            'PLAYING',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (cacheStats != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '📦 Cache: ${cacheStats.cachedBatches} batches, ${cacheStats.totalFramesInCache} frames (${cacheStats.memoryUsageMB.toStringAsFixed(1)} MB)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
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
                          aspectRatio: _metadata!.width / _metadata!.height,
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
          if (_metadata != null && _currentFrame != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Slider(
                    value: _currentFrameIndex.toDouble(),
                    min: 0,
                    max: (_metadata!.totalFrames - 1).toDouble(),
                    divisions: _metadata!.totalFrames > 1 ? _metadata!.totalFrames - 1 : 1,
                    label: 'Frame $_currentFrameIndex',
                    onChanged: (value) {
                      if (_isPlaying) {
                        _stopPlaying();
                      }
                      _loadFrame(value.toInt());
                    },
                  ),
                  Text(
                    'Frame $_currentFrameIndex / ${_metadata!.totalFrames - 1}',
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
                if (_metadata != null)
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
                              hintText: '0-${_metadata!.totalFrames - 1}',
                              contentPadding: const EdgeInsets.all(8),
                            ),
                            onSubmitted: (value) {
                              final frameIndex = int.tryParse(value);
                              if (frameIndex != null) {
                                if (_isPlaying) {
                                  _stopPlaying();
                                }
                                _loadFrame(frameIndex);
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
                                        _metadata!.totalFrames)
                                    .toInt();
                            _loadFrame(randomIndex);
                          },
                          icon: const Icon(Icons.shuffle, size: 18),
                          label: const Text('Random'),
                        ),
                      ],
                    ),
                  ),
                // Play/Pause button
                if (_metadata != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: _togglePlayPause,
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      label: Text(_isPlaying ? 'Pause' : 'Play'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                      ),
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
                    if (_metadata != null) ...[
                      ElevatedButton.icon(
                        onPressed: _isPlaying ? null : _goToPreviousFrame,
                        icon: const Icon(Icons.skip_previous),
                        label: const Text('Prev'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isPlaying ? null : _goToNextFrame,
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
