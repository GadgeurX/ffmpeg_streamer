#include "ffmpeg_core.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <stdlib.h>
#include <string.h>

static FFmpegState g_state = {0};

void ffmpeg_init(void) {
  g_state.video_stream_idx = -1;
  g_state.audio_stream_idx = -1;
  g_state.is_initialized = 1;
}

int ffmpeg_open_media(const char *file_path) {
  if (!file_path)
    return -1;

  // Clean up any previous state
  if (g_state.fmt_ctx) {
    ffmpeg_stop();
  }

  // 1. Open Input File
  if (avformat_open_input(&g_state.fmt_ctx, file_path, NULL, NULL) != 0) {
    return -2;
  }

  // 2. Get Stream Info
  if (avformat_find_stream_info(g_state.fmt_ctx, NULL) < 0) {
    avformat_close_input(&g_state.fmt_ctx);
    g_state.fmt_ctx = NULL;
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
      if (!g_state.video_codec_ctx) {
        avformat_close_input(&g_state.fmt_ctx);
        g_state.fmt_ctx = NULL;
        return -3;
      }
      if (avcodec_parameters_to_context(g_state.video_codec_ctx, codec_par) < 0) {
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }
      if (avcodec_open2(g_state.video_codec_ctx, codec, NULL) < 0) {
        // Failed to open video codec
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }

      // Initialize scaler for RGBA conversion
      g_state.video_frame = av_frame_alloc();
      g_state.video_frame_rgba = av_frame_alloc();

      if (!g_state.video_frame || !g_state.video_frame_rgba) {
        // Failed to allocate frames
        if (g_state.video_frame) av_frame_free(&g_state.video_frame);
        if (g_state.video_frame_rgba) av_frame_free(&g_state.video_frame_rgba);
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }

      int num_bytes = av_image_get_buffer_size(
          AV_PIX_FMT_RGBA, g_state.video_codec_ctx->width,
          g_state.video_codec_ctx->height, 1);
      if (num_bytes < 0) {
        // Invalid video dimensions
        av_frame_free(&g_state.video_frame);
        av_frame_free(&g_state.video_frame_rgba);
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }

      g_state.video_buffer =
          (uint8_t *)av_malloc(num_bytes * sizeof(uint8_t));
      if (!g_state.video_buffer) {
        av_frame_free(&g_state.video_frame);
        av_frame_free(&g_state.video_frame_rgba);
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }

      av_image_fill_arrays(
          g_state.video_frame_rgba->data, g_state.video_frame_rgba->linesize,
          g_state.video_buffer, AV_PIX_FMT_RGBA,
          g_state.video_codec_ctx->width, g_state.video_codec_ctx->height, 1);

      g_state.sws_ctx = sws_getContext(
          g_state.video_codec_ctx->width, g_state.video_codec_ctx->height,
          g_state.video_codec_ctx->pix_fmt, g_state.video_codec_ctx->width,
          g_state.video_codec_ctx->height, AV_PIX_FMT_RGBA, SWS_BILINEAR,
          NULL, NULL, NULL);

      if (!g_state.sws_ctx) {
        // Failed to create scaler
        av_free(g_state.video_buffer);
        g_state.video_buffer = NULL;
        av_frame_free(&g_state.video_frame);
        av_frame_free(&g_state.video_frame_rgba);
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
      }
    } else if (codec_par->codec_type == AVMEDIA_TYPE_AUDIO &&
               g_state.audio_stream_idx == -1) {
      g_state.audio_stream_idx = i;
      g_state.audio_codec_ctx = avcodec_alloc_context3(codec);
      if (!g_state.audio_codec_ctx) {
        avformat_close_input(&g_state.fmt_ctx);
        g_state.fmt_ctx = NULL;
        return -3;
      }
      if (avcodec_parameters_to_context(g_state.audio_codec_ctx, codec_par) < 0) {
        avcodec_free_context(&g_state.audio_codec_ctx);
        g_state.audio_codec_ctx = NULL;
        g_state.audio_stream_idx = -1;
        continue;
      }
      if (avcodec_open2(g_state.audio_codec_ctx, codec, NULL) < 0) {
        // Failed to open audio codec
        avcodec_free_context(&g_state.audio_codec_ctx);
        g_state.audio_codec_ctx = NULL;
        g_state.audio_stream_idx = -1;
        continue;
      } else {
        g_state.audio_frame = av_frame_alloc();
        g_state.audio_frame_converted = av_frame_alloc();

        if (!g_state.audio_frame || !g_state.audio_frame_converted) {
          if (g_state.audio_frame) av_frame_free(&g_state.audio_frame);
          if (g_state.audio_frame_converted) av_frame_free(&g_state.audio_frame_converted);
          avcodec_free_context(&g_state.audio_codec_ctx);
          g_state.audio_codec_ctx = NULL;
          g_state.audio_stream_idx = -1;
          continue;
        }

        // Allocate buffer for audio frame conversion
        int max_samples = g_state.audio_codec_ctx->frame_size;
        if (max_samples <= 0)
          max_samples = 1024; // Default buffer size

        uint8_t **audio_data = NULL;
        if (av_samples_alloc_array_and_samples(
            &audio_data,
            NULL,
            2, // Output stereo
            max_samples,
            AV_SAMPLE_FMT_FLT,
            0) < 0) {
          // Failed to allocate audio buffer
          av_frame_free(&g_state.audio_frame);
          av_frame_free(&g_state.audio_frame_converted);
          g_state.audio_frame = NULL;
          g_state.audio_frame_converted = NULL;
          avcodec_free_context(&g_state.audio_codec_ctx);
          g_state.audio_codec_ctx = NULL;
          g_state.audio_stream_idx = -1;
          continue;
        }

        // Set frame properties
        g_state.audio_frame_converted->format = AV_SAMPLE_FMT_FLT;
        g_state.audio_frame_converted->nb_samples = 0;
        AVChannelLayout stereo_layout = AV_CHANNEL_LAYOUT_STEREO;
        av_channel_layout_copy(&g_state.audio_frame_converted->ch_layout, &stereo_layout);
        g_state.audio_frame_converted->data[0] = audio_data[0];
        g_state.audio_frame_converted->linesize[0] = max_samples * 2 * sizeof(float);

        // Initialize resampler to Float32 Interleaved
        AVChannelLayout out_ch_layout =
            AV_CHANNEL_LAYOUT_STEREO; // Default to stereo

        if (swr_alloc_set_opts2(&g_state.swr_ctx, &out_ch_layout, AV_SAMPLE_FMT_FLT,
                            g_state.audio_codec_ctx->sample_rate,
                            &g_state.audio_codec_ctx->ch_layout,
                            g_state.audio_codec_ctx->sample_fmt,
                            g_state.audio_codec_ctx->sample_rate, 0, NULL) < 0) {
          // Failed to allocate resampler
          av_freep(&g_state.audio_frame_converted->data[0]);
          av_frame_free(&g_state.audio_frame);
          av_frame_free(&g_state.audio_frame_converted);
          avcodec_free_context(&g_state.audio_codec_ctx);
          g_state.audio_codec_ctx = NULL;
          g_state.audio_stream_idx = -1;
          continue;
        }

        if (swr_init(g_state.swr_ctx) < 0) {
          // Failed to initialize resampler
          swr_free(&g_state.swr_ctx);
          av_freep(&g_state.audio_frame_converted->data[0]);
          av_frame_free(&g_state.audio_frame);
          av_frame_free(&g_state.audio_frame_converted);
          avcodec_free_context(&g_state.audio_codec_ctx);
          g_state.audio_codec_ctx = NULL;
          g_state.audio_stream_idx = -1;
          continue;
        }
      }
    }
  }

  // 4. Allocate work packet
  g_state.work_packet = av_packet_alloc();
  if (!g_state.work_packet) {
    ffmpeg_stop();
    return -3;
  }

  return 0;
}

MediaInfo ffmpeg_get_media_info(void) {
  MediaInfo info = {0};
  info.duration_ms = -1;

  if (g_state.fmt_ctx) {
    info.duration_ms = g_state.fmt_ctx->duration / (AV_TIME_BASE / 1000);
    if (g_state.video_codec_ctx) {
      info.width = g_state.video_codec_ctx->width;
      info.height = g_state.video_codec_ctx->height;

      double fps = 0.0;
      if (g_state.fmt_ctx->streams[g_state.video_stream_idx]
              ->avg_frame_rate.den != 0) {
        fps = av_q2d(
            g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
      }
      info.fps = fps;

      int64_t frames =
          g_state.fmt_ctx->streams[g_state.video_stream_idx]->nb_frames;
      if (frames <= 0 && fps > 0 && info.duration_ms > 0) {
        frames = (int64_t)((info.duration_ms / 1000.0) * fps);
      }
      info.total_frames = frames;
    }
    if (g_state.audio_codec_ctx) {
      info.audio_sample_rate = g_state.audio_codec_ctx->sample_rate;
      info.audio_channels = g_state.audio_codec_ctx->ch_layout.nb_channels;
    }
  }
  return info;
}

void ffmpeg_stop(void) {
  // Cleanup Resources
  if (g_state.video_codec_ctx) {
    avcodec_free_context(&g_state.video_codec_ctx);
    g_state.video_codec_ctx = NULL;
  }

  if (g_state.audio_codec_ctx) {
    avcodec_free_context(&g_state.audio_codec_ctx);
    g_state.audio_codec_ctx = NULL;
  }

  if (g_state.sws_ctx) {
    sws_freeContext(g_state.sws_ctx);
    g_state.sws_ctx = NULL;
  }

  if (g_state.swr_ctx) {
    swr_free(&g_state.swr_ctx);
    g_state.swr_ctx = NULL;
  }

  if (g_state.video_frame) {
    av_frame_free(&g_state.video_frame);
    g_state.video_frame = NULL;
  }

  if (g_state.video_frame_rgba) {
    av_frame_free(&g_state.video_frame_rgba);
    g_state.video_frame_rgba = NULL;
  }

  if (g_state.video_buffer) {
    av_free(g_state.video_buffer);
    g_state.video_buffer = NULL;
  }

  if (g_state.audio_frame) {
    av_frame_free(&g_state.audio_frame);
    g_state.audio_frame = NULL;
  }

  if (g_state.audio_frame_converted) {
    if (g_state.audio_frame_converted->data[0]) {
      av_freep(&g_state.audio_frame_converted->data[0]);
    }
    av_frame_free(&g_state.audio_frame_converted);
    g_state.audio_frame_converted = NULL;
  }

  if (g_state.work_packet) {
    av_packet_free(&g_state.work_packet);
    g_state.work_packet = NULL;
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

  int64_t timestamp = timestamp_ms * (AV_TIME_BASE / 1000);

  if (av_seek_frame(g_state.fmt_ctx, -1, timestamp,
                     AVSEEK_FLAG_BACKWARD | AVSEEK_FLAG_ANY) < 0)
    return -1;

  if (g_state.audio_codec_ctx) {
    avcodec_flush_buffers(g_state.audio_codec_ctx);
  }
  if (g_state.video_codec_ctx) {
    avcodec_flush_buffers(g_state.video_codec_ctx);
  }

  return 0;
}

int ffmpeg_seek_frame(int frame_index) {
  if (!g_state.fmt_ctx || g_state.video_stream_idx < 0)
    return -1;

  int64_t timestamp =
      frame_index *
      (g_state.fmt_ctx->streams[g_state.video_stream_idx]->duration /
       g_state.fmt_ctx->streams[g_state.video_stream_idx]->nb_frames);

  return ffmpeg_seek(timestamp / (AV_TIME_BASE / 1000));
}

// Helper to seek to nearest frame before timestamp
static int seek_to_frame_before_ts(int64_t target_ts_ms) {
  if (!g_state.fmt_ctx)
    return -1;

  int64_t target_ts = target_ts_ms * (AV_TIME_BASE / 1000);

  // Seek backward to find first keyframe before target
  if (av_seek_frame(g_state.fmt_ctx, -1, target_ts,
                     AVSEEK_FLAG_BACKWARD) < 0) {
    return -1;
  }

  // Flush buffers
  if (g_state.video_codec_ctx) {
    avcodec_flush_buffers(g_state.video_codec_ctx);
  }
  if (g_state.audio_codec_ctx) {
    avcodec_flush_buffers(g_state.audio_codec_ctx);
  }

  return 0;
}

static int decode_video_until_ts(int64_t target_ts_ms, VideoFrame **out_frame) {
  if (!g_state.video_codec_ctx || !g_state.video_frame) return -1;

  while (av_read_frame(g_state.fmt_ctx, g_state.work_packet) >= 0) {
    if (g_state.work_packet->stream_index == g_state.video_stream_idx) {
      int ret = avcodec_send_packet(g_state.video_codec_ctx, g_state.work_packet);
      if (ret < 0) {
        av_packet_unref(g_state.work_packet);
        continue;
      }

      while (ret >= 0) {
        ret = avcodec_receive_frame(g_state.video_codec_ctx, g_state.video_frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
          break;
        } else if (ret < 0) {
          av_packet_unref(g_state.work_packet);
          return -1;
        }

        // Calculate frame timestamp in milliseconds
        AVRational time_base = g_state.fmt_ctx->streams[g_state.video_stream_idx]->time_base;
        int64_t frame_ts_ms = g_state.video_frame->pts * 1000 * time_base.num / time_base.den;

        // Convert to RGBA
        sws_scale(g_state.sws_ctx,
                  (const uint8_t *const *)g_state.video_frame->data,
                  g_state.video_frame->linesize, 0,
                  g_state.video_codec_ctx->height,
                  g_state.video_frame_rgba->data,
                  g_state.video_frame_rgba->linesize);

        // Calculate frame ID
        int64_t frame_id = 0;
        double fps = 0.0;
        if (g_state.fmt_ctx->streams[g_state.video_stream_idx]
                ->avg_frame_rate.den != 0) {
          fps = av_q2d(
              g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
        }
        if (fps > 0) {
          frame_id = (int64_t)(frame_ts_ms * fps / 1000.0);
        }

        // If we've reached or passed the target timestamp, return this frame
        if (frame_ts_ms >= target_ts_ms) {
          // Calculate proper buffer size for RGBA (4 bytes per pixel)
          int buffer_size = g_state.video_codec_ctx->width * g_state.video_codec_ctx->height * 4;

          *out_frame = (VideoFrame *)malloc(sizeof(VideoFrame));
          if (!*out_frame) {
            av_packet_unref(g_state.work_packet);
            return -1;
          }

          (*out_frame)->data = (uint8_t *)malloc(buffer_size);
          if (!(*out_frame)->data) {
            free(*out_frame);
            *out_frame = NULL;
            av_packet_unref(g_state.work_packet);
            return -1;
          }

          // Copy row by row to handle potential line size differences
          for (int y = 0; y < g_state.video_codec_ctx->height; y++) {
            memcpy(
                (*out_frame)->data + y * g_state.video_codec_ctx->width * 4,
                g_state.video_frame_rgba->data[0] + y * g_state.video_frame_rgba->linesize[0],
                g_state.video_codec_ctx->width * 4  // Target is always width*4 for RGBA
            );
          }

          (*out_frame)->width = g_state.video_codec_ctx->width;
          (*out_frame)->height = g_state.video_codec_ctx->height;
          (*out_frame)->linesize = g_state.video_codec_ctx->width * 4;  // linesize for output
          (*out_frame)->pts_ms = frame_ts_ms;
          (*out_frame)->frame_id = frame_id;

          av_packet_unref(g_state.work_packet);
          return 0; // Success
        }
      }
    }
    av_packet_unref(g_state.work_packet);
  }

  return -1; // Not found
}

int ffmpeg_get_video_frame_at_timestamp(int64_t timestamp_ms,
                                        VideoFrame **out_frame) {
  if (!g_state.fmt_ctx || g_state.video_stream_idx < 0)
    return -1;

  // Seek to nearest frame before target
  if (seek_to_frame_before_ts(timestamp_ms) < 0)
    return -1;

  // Decode until we find the frame at or after target timestamp
  return decode_video_until_ts(timestamp_ms, out_frame);
}

int ffmpeg_get_video_frame_at_index(int frame_index, VideoFrame **out_frame) {
  if (!g_state.fmt_ctx || g_state.video_stream_idx < 0)
    return -1;

  // Calculate timestamp for this frame
  double fps = 0.0;
  if (g_state.fmt_ctx->streams[g_state.video_stream_idx]
          ->avg_frame_rate.den != 0) {
    fps = av_q2d(
        g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
  }
  if (fps <= 0)
    return -1;

  int64_t target_ts_ms = (int64_t)((frame_index / fps) * 1000.0);

  // Seek and decode
  return ffmpeg_get_video_frame_at_timestamp(target_ts_ms, out_frame);
}

static int decode_audio_until_ts(int64_t target_ts_ms, AudioFrame **out_frame) {
  if (!g_state.audio_codec_ctx || !g_state.audio_frame || !g_state.swr_ctx)
    return -1;

  while (av_read_frame(g_state.fmt_ctx, g_state.work_packet) >= 0) {
    if (g_state.work_packet->stream_index == g_state.audio_stream_idx) {
      int ret = avcodec_send_packet(g_state.audio_codec_ctx, g_state.work_packet);
      if (ret < 0) {
        av_packet_unref(g_state.work_packet);
        continue;
      }

      while (ret >= 0) {
        ret = avcodec_receive_frame(g_state.audio_codec_ctx, g_state.audio_frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
          break;
        } else if (ret < 0) {
          av_packet_unref(g_state.work_packet);
          return -1;
        }

        // Calculate frame timestamp in milliseconds
        AVRational time_base = g_state.fmt_ctx->streams[g_state.audio_stream_idx]->time_base;
        int64_t frame_ts_ms = g_state.audio_frame->pts * 1000 * time_base.num / time_base.den;

        // Convert to Float32 Interleaved
        int dst_nb_samples = swr_convert(
            g_state.swr_ctx,
            g_state.audio_frame_converted->data,
            g_state.audio_frame->nb_samples,
            (const uint8_t **)g_state.audio_frame->data,
            g_state.audio_frame->nb_samples);

        if (dst_nb_samples < 0) {
          av_packet_unref(g_state.work_packet);
          return -1;
        }

        // If we've reached or passed the target timestamp, return this frame
        if (frame_ts_ms >= target_ts_ms && dst_nb_samples > 0) {
          *out_frame = (AudioFrame *)malloc(sizeof(AudioFrame));
          if (!*out_frame) {
            av_packet_unref(g_state.work_packet);
            return -1;
          }

          // Use the number of channels from the converted frame
          int num_channels = g_state.audio_frame_converted->ch_layout.nb_channels;
          size_t data_size = dst_nb_samples * num_channels * sizeof(float);
          (*out_frame)->data = (float *)malloc(data_size);
          if (!(*out_frame)->data) {
            free(*out_frame);
            *out_frame = NULL;
            av_packet_unref(g_state.work_packet);
            return -1;
          }

          memcpy((*out_frame)->data, g_state.audio_frame_converted->data[0],
                 data_size);

          (*out_frame)->samples_count = dst_nb_samples;
          (*out_frame)->channels = num_channels;
          (*out_frame)->sample_rate = g_state.audio_codec_ctx->sample_rate;
          (*out_frame)->pts_ms = frame_ts_ms;

          av_packet_unref(g_state.work_packet);
          return 0; // Success
        }
      }
    }
    av_packet_unref(g_state.work_packet);
  }

  return -1; // Not found
}

int ffmpeg_get_audio_frame_at_timestamp(int64_t timestamp_ms,
                                        AudioFrame **out_frame) {
  if (!g_state.fmt_ctx || g_state.audio_stream_idx < 0)
    return -1;

  // Seek to nearest frame before target
  if (seek_to_frame_before_ts(timestamp_ms) < 0)
    return -1;

  // Decode until we find the frame at or after target timestamp
  return decode_audio_until_ts(timestamp_ms, out_frame);
}

int ffmpeg_get_audio_frame_at_index(int frame_index, AudioFrame **out_frame) {
  if (!g_state.fmt_ctx || g_state.audio_stream_idx < 0)
    return -1;

  // For audio, we estimate based on sample rate
  if (!g_state.audio_codec_ctx)
    return -1;

  int samples_per_frame = g_state.audio_codec_ctx->frame_size;
  if (samples_per_frame <= 0)
    samples_per_frame = 1024;

  int64_t frame_duration_ms =
      (samples_per_frame * 1000) / g_state.audio_codec_ctx->sample_rate;
  int64_t target_ts_ms = frame_index * frame_duration_ms;

  return ffmpeg_get_audio_frame_at_timestamp(target_ts_ms, out_frame);
}

void ffmpeg_free_video_frame(VideoFrame *frame) {
  if (frame) {
    if (frame->data)
      free(frame->data);
    free(frame);
  }
}

void ffmpeg_free_audio_frame(AudioFrame *frame) {
  if (frame) {
    if (frame->data)
      free(frame->data);
    free(frame);
  }
}

void ffmpeg_release(void) {
  // Per-media cleanup is done by ffmpeg_stop(), but ensure that's called
  ffmpeg_stop();
  g_state.is_initialized = 0;
}