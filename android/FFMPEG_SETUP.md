# Android FFmpeg Setup

To build this plugin, you must provide prebuilt FFmpeg shared libraries (`.so`) and headers.

## 1. Libraries
Place the `.so` files for each ABI (armeabi-v7a, arm64-v8a, x86, x86_64) in:
`android/src/main/jniLibs/<ABI>/`

Required libraries:
- libavformat.so
- libavcodec.so
- libavutil.so
- libswscale.so
- libswresample.so

## 2. Headers
Place the FFmpeg include directories (libavcodec/, libavformat/, etc.) in:
`android/src/main/cpp/include/`

So you should have `android/src/main/cpp/include/libavcodec/avcodec.h`, etc.
