#ifndef FFMPEG_CORE_H
#define FFMPEG_CORE_H

#include <stdbool.h>
#include <stdint.h>
#include <pthread.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Data Structures ---

// Forward declarations
typedef struct VideoFrame VideoFrame;
typedef struct AudioFrame AudioFrame;

// Callback types for async operations
typedef void (*OnVideoFrameCallback)(void *user_data, VideoFrame *frame, int error_code);
typedef void (*OnAudioFrameCallback)(void *user_data, AudioFrame *frame, int error_code);
typedef void (*OnFrameRangeProgressCallback)(void *user_data, int current, int total);

// Internal state structure for FFmpeg streaming
typedef struct {
  AVFormatContext *fmt_ctx;
  AVCodecContext *video_codec_ctx;
  AVCodecContext *audio_codec_ctx;
  SwsContext *sws_ctx;
  SwrContext *swr_ctx;
  AVFrame *video_frame;
  AVFrame *video_frame_rgba;
  AVFrame *audio_frame;
  AVFrame *audio_frame_converted;
  AVPacket *work_packet;
  uint8_t *video_buffer;
  int video_stream_idx;
  int audio_stream_idx;
  int is_initialized;
  
  // Thread safety
  pthread_mutex_t mutex;
} FFmpegState;

typedef struct {
  int64_t duration_ms;
  int width;
  int height;
  double fps;
  int audio_sample_rate;
  int audio_channels;
  int64_t total_frames;
} MediaInfo;

struct VideoFrame {
  uint8_t *data;
  int width;
  int height;
  int linesize;
  int64_t pts_ms;
  int64_t frame_id;
};

struct AudioFrame {
  float *data;
  int samples_count;
  int channels;
  int sample_rate;
  int64_t pts_ms;
  int64_t frame_id;
};

// --- Core API ---

// Global initialization of FFmpeg (network, etc).
void ffmpeg_init(void);

// Open media from a URL or file path.
// Returns 0 on success, negative error code on failure.
int ffmpeg_open_media(const char *url);

// Get information about the currently opened media.
// Returns a MediaInfo struct. Check duration_ms == -1 for validity if needed.
MediaInfo ffmpeg_get_media_info(void);

// Stop and release per-media resources (but keep core initialized).
void ffmpeg_stop(void);

// Free a VideoFrame allocated by async callbacks.
void ffmpeg_free_video_frame(VideoFrame *frame);

// Free an AudioFrame allocated by async callbacks.
void ffmpeg_free_audio_frame(AudioFrame *frame);

// --- Async Frame Retrieval with Callbacks ---

// Request ID for tracking async operations
typedef int64_t RequestId;

// Async: Get video frame at timestamp with callback
// Returns request ID (positive) or negative error code
RequestId ffmpeg_get_video_frame_at_timestamp_async(
    int64_t timestamp_ms,
    OnVideoFrameCallback callback,
    void *user_data);

// Async: Get video frame at index with callback
// Returns request ID (positive) or negative error code
RequestId ffmpeg_get_video_frame_at_index_async(
    int frame_index,
    OnVideoFrameCallback callback,
    void *user_data);

// Async: Get audio frame at timestamp with callback
// Returns request ID (positive) or negative error code
RequestId ffmpeg_get_audio_frame_at_timestamp_async(
    int64_t timestamp_ms,
    OnAudioFrameCallback callback,
    void *user_data);

// Async: Get audio frame at index with callback
// Returns request ID (positive) or negative error code
RequestId ffmpeg_get_audio_frame_at_index_async(
    int frame_index,
    OnAudioFrameCallback callback,
    void *user_data);

// --- Optimized Batch Frame Retrieval ---

// Batch request structure
typedef struct {
  VideoFrame **video_frames;   // Array of video frame pointers (allocated by caller)
  AudioFrame **audio_frames;   // Array of audio frame pointers (allocated by caller)
  int *result_codes;           // Array of result codes (0 = success, negative = error)
  int count;                   // Number of frames retrieved
} FrameRangeBatch;

// Get range of video frames by index (optimized, no seeking per frame)
// start_index: first frame index
// end_index: last frame index (inclusive)
// out_batch: output batch structure (caller allocates, function fills arrays)
// Returns number of frames retrieved, or negative error code
int ffmpeg_get_video_frames_range_by_index(
    int start_index,
    int end_index,
    FrameRangeBatch *out_batch);

// Get range of video frames by timestamp (optimized)
// start_ms: start timestamp in milliseconds
// end_ms: end timestamp in milliseconds
// step_ms: step between frames in milliseconds
// out_batch: output batch structure (caller allocates, function fills arrays)
// Returns number of frames retrieved, or negative error code
int ffmpeg_get_video_frames_range_by_timestamp(
    int64_t start_ms,
    int64_t end_ms,
    int64_t step_ms,
    FrameRangeBatch *out_batch);

// Async version with progress callback
RequestId ffmpeg_get_video_frames_range_async(
    int start_index,
    int end_index,
    OnVideoFrameCallback frame_callback,
    OnFrameRangeProgressCallback progress_callback,
    void *user_data);

// Free a batch of frames
void ffmpeg_free_frame_range_batch(FrameRangeBatch *batch);

// Cancel an async request (best effort)
void ffmpeg_cancel_request(RequestId request_id);

// Global cleanup.
void ffmpeg_release(void);

#ifdef __cplusplus
}
#endif

#endif // FFMPEG_CORE_H