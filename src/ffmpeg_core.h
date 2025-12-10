#ifndef FFMPEG_CORE_H
#define FFMPEG_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Data Structures ---

typedef struct {
    int64_t duration_ms;
    int width;
    int height;
    double fps;
    int audio_sample_rate;
    int audio_channels;
} MediaInfo;

typedef struct {
    uint8_t* data;
    int width;
    int height;
    int linesize;
    int64_t pts_ms;
} VideoFrame;

typedef struct {
    float* data;
    int samples_count;
    int channels;
    int sample_rate;
    int64_t pts_ms;
} AudioFrame;

// --- Callback Types ---

// Callback when a video frame is available.
// The data pointer is valid only during the callback.
typedef void (*OnVideoFrameCallback)(VideoFrame* frame);

// Callback when an audio frame is available.
// The data pointer is valid only during the callback.
typedef void (*OnAudioFrameCallback)(AudioFrame* frame);

// Callback for logging. level: 0=error, 1=warning, 2=info, 3=debug
typedef void (*OnLogCallback)(int level, const char* message);

// --- Core API ---

// Global initialization of FFmpeg (network, etc).
void ffmpeg_init();

// Open media from a URL or file path.
// Returns 0 on success, negative error code on failure.
int ffmpeg_open_media(const char* url);

// Get information about the currently opened media.
// Returns a MediaInfo struct. Check duration_ms == -1 for validity if needed.
MediaInfo ffmpeg_get_media_info();

// Start decoding. This should spawn a background thread or be part of the loop.
// For this simplified version, we assume this starts the internal loop threads.
int ffmpeg_start_decoding();

// Pause decoding.
int ffmpeg_pause();

// Resume decoding.
int ffmpeg_resume();

// Stop decoding and release per-media resources (but keep core initialized).
void ffmpeg_stop();

// Seek to a timestamp in milliseconds.
int ffmpeg_seek(int64_t timestamp_ms);

// Set callbacks for Dart.
void ffmpeg_set_callbacks(OnVideoFrameCallback video_cb, OnAudioFrameCallback audio_cb, OnLogCallback log_cb);

// Global cleanup.
void ffmpeg_release();

#ifdef __cplusplus
}
#endif

#endif // FFMPEG_CORE_H
