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

  @override
  void dispose() {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open media file')),
        );
        return;
      }

      // Get the first frame (contains both video and audio)
      final mediaFrame = await decoder.getFrameAtIndex(0);

      if (mediaFrame != null && mediaFrame.video != null) {
        _renderFrame(mediaFrame.video!);

        setState(() {
          _decoder = decoder;
          _mediaInfo = _createMediaInfo(decoder);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No video data found in media')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening media: $e')),
      );
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

  Future<void> _renderFrame(VideoFrame frame) async {
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
        _currentFrameIndex = frame.frameId;
      });
    }
  }

  Future<void> _goToFrame(int frameIndex) async {
    if (_decoder == null) return;

    final mediaFrame = await _decoder!.getFrameAtIndex(frameIndex);

    if (mediaFrame != null && mediaFrame.video != null) {
      _renderFrame(mediaFrame.video!);
    }
  }

  Future<void> _goToPreviousFrame() async {
    if (_decoder == null) return;

    final mediaFrame = await _decoder!.previousFrame();

    if (mediaFrame != null && mediaFrame.video != null) {
      _renderFrame(mediaFrame.video!);
    }
  }

  Future<void> _goToNextFrame() async {
    if (_decoder == null) return;

    final mediaFrame = await _decoder!.nextFrame();

    if (mediaFrame != null && mediaFrame.video != null) {
      _renderFrame(mediaFrame.video!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FFmpeg Streamer Example')),
      body: Column(
        children: [
          if (_mediaInfo != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(
                      '${_mediaInfo!.width}x${_mediaInfo!.height} @ ${_mediaInfo!.fps.toStringAsFixed(2)} fps'),
                  Text(
                      'Duration: ${_mediaInfo!.duration} | Total frames: ${_mediaInfo!.totalFrames}'),
                  Text('Current frame: $_currentFrameIndex'),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: _currentFrame != null
                  ? AspectRatio(
                      aspectRatio: _mediaInfo!.width / _mediaInfo!.height,
                      child: CustomPaint(
                        painter: VideoPainter(_currentFrame!),
                      ),
                    )
                  : const Text('No video loaded - Pick a file to start'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Frame index input
                if (_mediaInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
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
                            ),
                            onSubmitted: (value) {
                              final frameIndex = int.tryParse(value);
                              if (frameIndex != null) {
                                _goToFrame(frameIndex);
                              }
                            },
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            // Go to random frame
                            final randomIndex =
                                (DateTime.now().millisecondsSinceEpoch %
                                        _mediaInfo!.totalFrames)
                                    .toInt();
                            await _goToFrame(randomIndex);
                          },
                          child: const Text('Random Frame'),
                        ),
                      ],
                    ),
                  ),
                // Navigation buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _pickFile,
                      child: const Text('Pick File'),
                    ),
                    if (_decoder != null) ...[
                      ElevatedButton(
                        onPressed: _goToPreviousFrame,
                        child: const Text('Previous Frame'),
                      ),
                      ElevatedButton(
                        onPressed: _goToNextFrame,
                        child: const Text('Next Frame'),
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