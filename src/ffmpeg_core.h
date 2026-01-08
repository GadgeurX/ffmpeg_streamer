#ifndef FFMPEG_CORE_H
#define FFMPEG_CORE_H

#include <stdbool.h>
#include <stdint.h>

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

typedef struct {
  uint8_t *data;
  int width;
  int height;
  int linesize;
  int64_t pts_ms;
  int64_t frame_id;
} VideoFrame;

typedef struct {
  float *data;
  int samples_count;
  int channels;
  int sample_rate;
  int64_t pts_ms;
  int64_t frame_id;
} AudioFrame;

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

// Seek to a timestamp in milliseconds.
int ffmpeg_seek(int64_t timestamp_ms);

// Seek to a specific frame index.
int ffmpeg_seek_frame(int frame_index);

// Retrieve a single video frame at the specified timestamp.
// The caller is responsible for freeing the frame using ffmpeg_free_video_frame.
// Returns 0 on success, negative on error.
int ffmpeg_get_video_frame_at_timestamp(int64_t timestamp_ms, VideoFrame **out_frame);

// Retrieve a single video frame by index.
// The caller is responsible for freeing the frame using ffmpeg_free_video_frame.
// Returns 0 on success, negative on error.
int ffmpeg_get_video_frame_at_index(int frame_index, VideoFrame **out_frame);

// Retrieve a single audio frame at the specified timestamp.
// The caller is responsible for freeing the frame using ffmpeg_free_audio_frame.
// Returns 0 on success, negative on error.
int ffmpeg_get_audio_frame_at_timestamp(int64_t timestamp_ms, AudioFrame **out_frame);

// Retrieve a single audio frame by index.
// The caller is responsible for freeing the frame using ffmpeg_free_audio_frame.
// Returns 0 on success, negative on error.
int ffmpeg_get_audio_frame_at_index(int frame_index, AudioFrame **out_frame);

// Free a VideoFrame allocated by the get_frame functions.
void ffmpeg_free_video_frame(VideoFrame *frame);

// Free an AudioFrame allocated by the get_frame functions.
void ffmpeg_free_audio_frame(AudioFrame *frame);

// Global cleanup.
void ffmpeg_release(void);

#ifdef __cplusplus
}
#endif

#endif // FFMPEG_CORE_H