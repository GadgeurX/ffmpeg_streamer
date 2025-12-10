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
  bool _isPlaying = false;

  double _lastFrameTimestamp = 0;
  
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
    await _decoder?.close();
    setState(() {
      _mediaInfo = null;
      _currentFrame = null;
      _isPlaying = false;
    });

    try {
      final decoder = FfmpegDecoder();
      await decoder.open(FfmpegMediaSource.fromFile(path));
      
      final info = await decoder.mediaInfo;
      
      decoder.videoFrames.listen((frame) {
        _renderFrame(frame);
      });

      setState(() {
        _decoder = decoder;
        _mediaInfo = info;
      });

      var frame = await decoder.getFrameAtIndex(0);

      if (frame != null) {
        _renderFrame(frame);
      }
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening media: $e')),
      );
    }
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

    _lastFrameTimestamp = frame.frameId / _mediaInfo!.fps;
    if (_lastFrameTimestamp >= (_mediaInfo?.duration.inSeconds ?? 0)) {
      _lastFrameTimestamp = 0;
      _decoder?.seekToFrame(0);
      _decoder?.pause();
      _isPlaying = false;
    }

    if (mounted) {
      setState(() {
        _currentFrame = image;
      });
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
              child: Text(
                  '${_mediaInfo!.width}x${_mediaInfo!.height} @ ${_mediaInfo!.fps.toStringAsFixed(2)} fps\nDuration: ${_mediaInfo!.duration} @ ${_mediaInfo?.totalFrames}'),
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
                  : const Text('No video loaded'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _pickFile,
                  child: const Text('Pick File'),
                ),
                if (_decoder != null) ...[
                  ElevatedButton(
                    onPressed: () {
                      if (_isPlaying) {
                        _decoder!.pause();
                      } else {
                        _decoder!.play();
                      }
                      setState(() => _isPlaying = !_isPlaying);
                    },
                    child: Text(_isPlaying ? 'Pause' : 'Play'),
                  ),
                ]
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
