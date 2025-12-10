#include "ffmpeg_core.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libavutil/time.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

// --- Internal State ---

typedef struct {
  AVFormatContext *fmt_ctx;

  // Video
  int video_stream_idx;
  AVCodecContext *video_codec_ctx;
  struct SwsContext *sws_ctx;
  AVFrame *video_frame;
  AVFrame *video_frame_rgba;
  uint8_t *video_buffer;

  // Audio
  int audio_stream_idx;
  AVCodecContext *audio_codec_ctx;
  struct SwrContext *swr_ctx;
  AVFrame *audio_frame;
  AVFrame *audio_frame_converted;

  // Threading control
  pthread_t decode_thread;
  bool is_running;
  bool is_paused;
  bool should_exit;
  pthread_mutex_t mutex;

  // Callbacks
  OnVideoFrameCallback on_video;
  OnAudioFrameCallback on_audio;
  OnLogCallback on_log;

} FfmpegState;

static FfmpegState g_state = {0};

// --- Helper Functions ---

static void log_msg(int level, const char *fmt, ...) {
  if (g_state.on_log) {
    char buffer[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    g_state.on_log(level, buffer);
  }
}

// --- Declaration of internal thread function
void *decoding_loop(void *arg);

// --- API Implementation ---

void ffmpeg_init() {
  // av_register_all() is deprecated/removed in newer FFmpeg versions.
  // network_init() might be needed for network streams.
  avformat_network_init();
  pthread_mutex_init(&g_state.mutex, NULL);
  log_msg(2, "FFmpeg Core Initialized");
}

void ffmpeg_release() {
  ffmpeg_stop();
  avformat_network_deinit();
  pthread_mutex_destroy(&g_state.mutex);
  log_msg(2, "FFmpeg Core Released");
}

int ffmpeg_open_media(const char *url) {
  if (g_state.fmt_ctx) {
    ffmpeg_stop();
  }

  // 1. Open Input
  if (avformat_open_input(&g_state.fmt_ctx, url, NULL, NULL) != 0) {
    log_msg(0, "Failed to open input input: %s", url);
    return -1;
  }

  // 2. Find Stream Info
  if (avformat_find_stream_info(g_state.fmt_ctx, NULL) < 0) {
    log_msg(0, "Failed to find stream info");
    return -2;
  }

  g_state.video_stream_idx = -1;
  g_state.audio_stream_idx = -1;

  // 3. Find Codecs
  for (unsigned int i = 0; i < g_state.fmt_ctx->nb_streams; i++) {
    AVStream *stream = g_state.fmt_ctx->streams[i];
    AVCodecParameters *codec_par = stream->codecpar;
    const AVCodec *codec = avcodec_find_decoder(codec_par->codec_id);

    if (!codec)
      continue;

    if (codec_par->codec_type == AVMEDIA_TYPE_VIDEO &&
        g_state.video_stream_idx == -1) {
      g_state.video_stream_idx = i;
      g_state.video_codec_ctx = avcodec_alloc_context3(codec);
      avcodec_parameters_to_context(g_state.video_codec_ctx, codec_par);
      if (avcodec_open2(g_state.video_codec_ctx, codec, NULL) < 0) {
        log_msg(0, "Failed to open video codec");
      } else {
        // Initialize scaler for RGBA conversion
        g_state.video_frame = av_frame_alloc();
        g_state.video_frame_rgba = av_frame_alloc();

        int num_bytes = av_image_get_buffer_size(
            AV_PIX_FMT_RGBA, g_state.video_codec_ctx->width,
            g_state.video_codec_ctx->height, 1);
        g_state.video_buffer =
            (uint8_t *)av_malloc(num_bytes * sizeof(uint8_t));

        av_image_fill_arrays(
            g_state.video_frame_rgba->data, g_state.video_frame_rgba->linesize,
            g_state.video_buffer, AV_PIX_FMT_RGBA,
            g_state.video_codec_ctx->width, g_state.video_codec_ctx->height, 1);

        g_state.sws_ctx = sws_getContext(
            g_state.video_codec_ctx->width, g_state.video_codec_ctx->height,
            g_state.video_codec_ctx->pix_fmt, g_state.video_codec_ctx->width,
            g_state.video_codec_ctx->height, AV_PIX_FMT_RGBA, SWS_BILINEAR,
            NULL, NULL, NULL);
      }
    } else if (codec_par->codec_type == AVMEDIA_TYPE_AUDIO &&
               g_state.audio_stream_idx == -1) {
      g_state.audio_stream_idx = i;
      g_state.audio_codec_ctx = avcodec_alloc_context3(codec);
      avcodec_parameters_to_context(g_state.audio_codec_ctx, codec_par);
      if (avcodec_open2(g_state.audio_codec_ctx, codec, NULL) < 0) {
        log_msg(0, "Failed to open audio codec");
      } else {
        g_state.audio_frame = av_frame_alloc();
        g_state.audio_frame_converted = av_frame_alloc();

        // Initialize resampler to Float32 Interleaved
        AVChannelLayout out_ch_layout =
            AV_CHANNEL_LAYOUT_STEREO; // Default to stereo
        if (g_state.audio_codec_ctx->ch_layout.nb_channels > 0) {
          // Try to keep original layout if simple, otherwise force stereo
          // For simplicity in this example, forcing Stereo Float32
        }

        swr_alloc_set_opts2(&g_state.swr_ctx, &out_ch_layout, AV_SAMPLE_FMT_FLT,
                            g_state.audio_codec_ctx->sample_rate,
                            &g_state.audio_codec_ctx->ch_layout,
                            g_state.audio_codec_ctx->sample_fmt,
                            g_state.audio_codec_ctx->sample_rate, 0, NULL);
        swr_init(g_state.swr_ctx);
      }
    }
  }

  log_msg(2, "Media opened. Video Index: %d, Audio Index: %d",
          g_state.video_stream_idx, g_state.audio_stream_idx);
  return 0;
}

MediaInfo ffmpeg_get_media_info() {
  MediaInfo info = {0};
  info.duration_ms = -1;

  if (g_state.fmt_ctx) {
    info.duration_ms = g_state.fmt_ctx->duration / (AV_TIME_BASE / 1000);
    if (g_state.video_codec_ctx) {
      info.width = g_state.video_codec_ctx->width;
      info.height = g_state.video_codec_ctx->height;
      // Best guess for fps
      if (g_state.fmt_ctx->streams[g_state.video_stream_idx]
              ->avg_frame_rate.den != 0) {
        info.fps = av_q2d(
            g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
      }
    }
    if (g_state.audio_codec_ctx) {
      info.audio_sample_rate = g_state.audio_codec_ctx->sample_rate;
      info.audio_channels = g_state.audio_codec_ctx->ch_layout.nb_channels;
    }
  }
  return info;
}

int ffmpeg_start_decoding() {
  if (g_state.is_running)
    return 0;

  g_state.should_exit = false;
  g_state.is_paused = false;
  g_state.is_running = true;

  if (pthread_create(&g_state.decode_thread, NULL, decoding_loop, NULL) != 0) {
    g_state.is_running = false;
    log_msg(0, "Failed to create decoding thread");
    return -1;
  }
  return 0;
}

int ffmpeg_pause() {
  g_state.is_paused = true;
  return 0;
}

int ffmpeg_resume() {
  g_state.is_paused = false;
  return 0;
}

void ffmpeg_stop() {
  g_state.should_exit = true;
  if (g_state.is_running) {
    pthread_join(g_state.decode_thread, NULL);
    g_state.is_running = false;
  }

  // Cleanup Resources
  if (g_state.video_codec_ctx) {
    avcodec_free_context(&g_state.video_codec_ctx);
    sws_freeContext(g_state.sws_ctx);
    av_frame_free(&g_state.video_frame);
    av_frame_free(&g_state.video_frame_rgba);
    av_free(g_state.video_buffer);
    g_state.video_buffer = NULL;
  }

  if (g_state.audio_codec_ctx) {
    avcodec_free_context(&g_state.audio_codec_ctx);
    swr_free(&g_state.swr_ctx);
    av_frame_free(&g_state.audio_frame);
    av_frame_free(&g_state.audio_frame_converted);
  }

  if (g_state.fmt_ctx) {
    avformat_close_input(&g_state.fmt_ctx);
    g_state.fmt_ctx = NULL;
  }

  g_state.video_stream_idx = -1;
  g_state.audio_stream_idx = -1;
}

int ffmpeg_seek(int64_t timestamp_ms) {
  if (!g_state.fmt_ctx)
    return -1;
  // Seek to timestamp based on AV_TIME_BASE
  int64_t ts = timestamp_ms * 1000; // micro (AV_TIME_BASE is usually 1,000,000)
  // Actually seek targets stream time bases, but av_seek_frame handles this if
  // we use AVSEEK_FLAG_BACKWARD etc? Safer to use avformat_seek_file or simply
  // rescale to stream base if needed. Simplifying: av_seek_frame with
  // AV_TIME_BASE unit if stream_index is -1.

  if (av_seek_frame(g_state.fmt_ctx, -1, ts, AVSEEK_FLAG_BACKWARD) < 0) {
    log_msg(1, "Seek failed");
    return -1;
  }
  // Flush codec buffers
  if (g_state.video_codec_ctx)
    avcodec_flush_buffers(g_state.video_codec_ctx);
  if (g_state.audio_codec_ctx)
    avcodec_flush_buffers(g_state.audio_codec_ctx);

  return 0;
}

void ffmpeg_set_callbacks(OnVideoFrameCallback video_cb,
                          OnAudioFrameCallback audio_cb, OnLogCallback log_cb) {
  g_state.on_video = video_cb;
  g_state.on_audio = audio_cb;
  g_state.on_log = log_cb;
}

void *decoding_loop(void *arg) {
  AVPacket *packet = av_packet_alloc();

  while (!g_state.should_exit) {
    if (g_state.is_paused) {
      usleep(10000); // Sleep 10ms
      continue;
    }

    int ret = av_read_frame(g_state.fmt_ctx, packet);
    if (ret < 0) {
      if (ret == AVERROR_EOF) {
        // End of file, maybe pause or trigger EOF event?
        // For now just wait.
        usleep(100000);
      } else {
        log_msg(0, "Error reading packet");
      }
      continue;
    }

    if (packet->stream_index == g_state.video_stream_idx &&
        g_state.video_codec_ctx) {
      if (avcodec_send_packet(g_state.video_codec_ctx, packet) == 0) {
        while (avcodec_receive_frame(g_state.video_codec_ctx,
                                     g_state.video_frame) == 0) {
          // Convert to RGBA
          sws_scale(g_state.sws_ctx,
                    (const uint8_t *const *)g_state.video_frame->data,
                    g_state.video_frame->linesize, 0,
                    g_state.video_codec_ctx->height,
                    g_state.video_frame_rgba->data,
                    g_state.video_frame_rgba->linesize);

          if (g_state.on_video) {
            VideoFrame vframe = {0};
            vframe.width = g_state.video_codec_ctx->width;
            vframe.height = g_state.video_codec_ctx->height;
            vframe.linesize = g_state.video_frame_rgba->linesize[0];
            vframe.data = g_state.video_frame_rgba->data[0];
            vframe.pts_ms =
                g_state.video_frame->pts *
                av_q2d(g_state.fmt_ctx->streams[g_state.video_stream_idx]
                           ->time_base) *
                1000;
            g_state.on_video(&vframe);
          }
        }
      }
    } else if (packet->stream_index == g_state.audio_stream_idx &&
               g_state.audio_codec_ctx) {
      if (avcodec_send_packet(g_state.audio_codec_ctx, packet) == 0) {
        while (avcodec_receive_frame(g_state.audio_codec_ctx,
                                     g_state.audio_frame) == 0) {
          // Resample to float/stereo
          // (Simplified for brevity - actual resampling implementation needs
          // buffer management) For now just assuming callback exists
          if (g_state.on_audio) {
            // TODO: Proper resampling to g_state.audio_frame_converted
            AudioFrame aframe = {0};
            // Stubbed
            g_state.on_audio(&aframe);
          }
        }
      }
    }

    av_packet_unref(packet);
  }

  av_packet_free(&packet);
  return NULL;
}
