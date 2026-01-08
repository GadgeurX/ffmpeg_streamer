#include "ffmpeg_core.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

// --- Async Task Queue ---

typedef enum {
  TASK_VIDEO_AT_TIMESTAMP,
  TASK_VIDEO_AT_INDEX,
  TASK_AUDIO_AT_TIMESTAMP,
  TASK_AUDIO_AT_INDEX,
  TASK_VIDEO_RANGE
} TaskType;

typedef struct AsyncTask {
  RequestId id;
  TaskType type;
  
  // Task parameters
  union {
    struct {
      int64_t timestamp_ms;
      int frame_index;
    } single;
    struct {
      int start_index;
      int end_index;
    } range;
  } params;
  
  // Callbacks
  OnVideoFrameCallback video_callback;
  OnAudioFrameCallback audio_callback;
  OnFrameRangeProgressCallback progress_callback;
  void *user_data;
  
  // Control
  bool cancelled;
  
  struct AsyncTask *next;
} AsyncTask;

typedef struct {
  AsyncTask *head;
  AsyncTask *tail;
  pthread_mutex_t mutex;
  pthread_cond_t cond;
  pthread_t worker_thread;
  bool should_exit;
  RequestId next_request_id;
} TaskQueue;

// --- Global State ---

static FFmpegState g_state = {0};
static TaskQueue g_task_queue = {0};

// --- Helper Functions ---

static VideoFrame* create_video_frame_copy(void) {
  if (!g_state.video_codec_ctx || !g_state.video_frame || !g_state.video_frame_rgba) {
    return NULL;
  }
  
  // Convert to RGBA
  sws_scale(g_state.sws_ctx,
            (const uint8_t *const *)g_state.video_frame->data,
            g_state.video_frame->linesize, 0,
            g_state.video_codec_ctx->height,
            g_state.video_frame_rgba->data,
            g_state.video_frame_rgba->linesize);
  
  // Calculate frame timestamp and ID
  AVRational time_base = g_state.fmt_ctx->streams[g_state.video_stream_idx]->time_base;
  int64_t frame_ts_ms = g_state.video_frame->pts * 1000 * time_base.num / time_base.den;
  
  int64_t frame_id = 0;
  double fps = 0.0;
  if (g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate.den != 0) {
    fps = av_q2d(g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
  }
  if (fps > 0) {
    frame_id = (int64_t)(frame_ts_ms * fps / 1000.0);
  }
  
  // Allocate and copy frame data
  int buffer_size = g_state.video_codec_ctx->width * g_state.video_codec_ctx->height * 4;
  
  VideoFrame *vf = (VideoFrame *)malloc(sizeof(VideoFrame));
  if (!vf) return NULL;
  
  vf->data = (uint8_t *)malloc(buffer_size);
  if (!vf->data) {
    free(vf);
    return NULL;
  }
  
  // Copy row by row to handle potential line size differences
  for (int y = 0; y < g_state.video_codec_ctx->height; y++) {
    memcpy(
        vf->data + y * g_state.video_codec_ctx->width * 4,
        g_state.video_frame_rgba->data[0] + y * g_state.video_frame_rgba->linesize[0],
        g_state.video_codec_ctx->width * 4
    );
  }
  
  vf->width = g_state.video_codec_ctx->width;
  vf->height = g_state.video_codec_ctx->height;
  vf->linesize = g_state.video_codec_ctx->width * 4;
  vf->pts_ms = frame_ts_ms;
  vf->frame_id = frame_id;
  
  return vf;
}

static AudioFrame* create_audio_frame_copy(void) {
  if (!g_state.audio_codec_ctx || !g_state.audio_frame || !g_state.swr_ctx) {
    return NULL;
  }
  
  // Calculate frame timestamp
  AVRational time_base = g_state.fmt_ctx->streams[g_state.audio_stream_idx]->time_base;
  int64_t frame_ts_ms = g_state.audio_frame->pts * 1000 * time_base.num / time_base.den;
  
  // Convert audio to Float32 Interleaved
  int dst_nb_samples = swr_convert(
      g_state.swr_ctx,
      g_state.audio_frame_converted->data,
      g_state.audio_frame->nb_samples,
      (const uint8_t **)g_state.audio_frame->data,
      g_state.audio_frame->nb_samples);
  
  if (dst_nb_samples < 0) return NULL;
  
  AudioFrame *af = (AudioFrame *)malloc(sizeof(AudioFrame));
  if (!af) return NULL;
  
  int num_channels = g_state.audio_frame_converted->ch_layout.nb_channels;
  size_t data_size = dst_nb_samples * num_channels * sizeof(float);
  
  af->data = (float *)malloc(data_size);
  if (!af->data) {
    free(af);
    return NULL;
  }
  
  memcpy(af->data, g_state.audio_frame_converted->data[0], data_size);
  
  af->samples_count = dst_nb_samples;
  af->channels = num_channels;
  af->sample_rate = g_state.audio_codec_ctx->sample_rate;
  af->pts_ms = frame_ts_ms;
  af->frame_id = 0; // Audio doesn't have a clear frame ID
  
  return af;
}

static int seek_to_frame_before_ts(int64_t target_ts_ms) {
  if (!g_state.fmt_ctx) return -1;
  
  int64_t target_ts = target_ts_ms * (AV_TIME_BASE / 1000);
  
  if (av_seek_frame(g_state.fmt_ctx, -1, target_ts, AVSEEK_FLAG_BACKWARD) < 0) {
    return -1;
  }
  
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
        
        AVRational time_base = g_state.fmt_ctx->streams[g_state.video_stream_idx]->time_base;
        int64_t frame_ts_ms = g_state.video_frame->pts * 1000 * time_base.num / time_base.den;
        
        if (frame_ts_ms >= target_ts_ms) {
          *out_frame = create_video_frame_copy();
          av_packet_unref(g_state.work_packet);
          return *out_frame ? 0 : -1;
        }
      }
    }
    av_packet_unref(g_state.work_packet);
  }
  
  return -1;
}

static int decode_audio_until_ts(int64_t target_ts_ms, AudioFrame **out_frame) {
  if (!g_state.audio_codec_ctx || !g_state.audio_frame || !g_state.swr_ctx) return -1;
  
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
        
        AVRational time_base = g_state.fmt_ctx->streams[g_state.audio_stream_idx]->time_base;
        int64_t frame_ts_ms = g_state.audio_frame->pts * 1000 * time_base.num / time_base.den;
        
        if (frame_ts_ms >= target_ts_ms) {
          *out_frame = create_audio_frame_copy();
          av_packet_unref(g_state.work_packet);
          return *out_frame ? 0 : -1;
        }
      }
    }
    av_packet_unref(g_state.work_packet);
  }
  
  return -1;
}

// --- Task Queue Implementation ---

static void task_queue_init(void) {
  g_task_queue.head = NULL;
  g_task_queue.tail = NULL;
  g_task_queue.should_exit = false;
  g_task_queue.next_request_id = 1;
  pthread_mutex_init(&g_task_queue.mutex, NULL);
  pthread_cond_init(&g_task_queue.cond, NULL);
}

static void task_queue_destroy(void) {
  pthread_mutex_lock(&g_task_queue.mutex);
  
  AsyncTask *task = g_task_queue.head;
  while (task) {
    AsyncTask *next = task->next;
    free(task);
    task = next;
  }
  
  g_task_queue.head = NULL;
  g_task_queue.tail = NULL;
  
  pthread_mutex_unlock(&g_task_queue.mutex);
  pthread_mutex_destroy(&g_task_queue.mutex);
  pthread_cond_destroy(&g_task_queue.cond);
}

static RequestId task_queue_add(AsyncTask *task) {
  pthread_mutex_lock(&g_task_queue.mutex);
  
  task->id = g_task_queue.next_request_id++;
  task->next = NULL;
  task->cancelled = false;
  
  if (g_task_queue.tail) {
    g_task_queue.tail->next = task;
  } else {
    g_task_queue.head = task;
  }
  g_task_queue.tail = task;
  
  RequestId id = task->id;
  
  pthread_cond_signal(&g_task_queue.cond);
  pthread_mutex_unlock(&g_task_queue.mutex);
  
  return id;
}

static AsyncTask* task_queue_pop(void) {
  pthread_mutex_lock(&g_task_queue.mutex);
  
  while (!g_task_queue.head && !g_task_queue.should_exit) {
    pthread_cond_wait(&g_task_queue.cond, &g_task_queue.mutex);
  }
  
  if (g_task_queue.should_exit) {
    pthread_mutex_unlock(&g_task_queue.mutex);
    return NULL;
  }
  
  AsyncTask *task = g_task_queue.head;
  g_task_queue.head = task->next;
  if (!g_task_queue.head) {
    g_task_queue.tail = NULL;
  }
  
  pthread_mutex_unlock(&g_task_queue.mutex);
  
  return task;
}

static void process_video_task(AsyncTask *task) {
  if (task->cancelled) return;
  
  pthread_mutex_lock(&g_state.mutex);
  
  VideoFrame *frame = NULL;
  int result = -1;
  
  if (task->type == TASK_VIDEO_AT_TIMESTAMP) {
    int64_t timestamp_ms = task->params.single.timestamp_ms;
    if (seek_to_frame_before_ts(timestamp_ms) >= 0) {
      result = decode_video_until_ts(timestamp_ms, &frame);
    }
  } else if (task->type == TASK_VIDEO_AT_INDEX) {
    int frame_index = task->params.single.frame_index;
    
    // Calculate timestamp for this frame
    double fps = 0.0;
    if (g_state.video_stream_idx >= 0 &&
        g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate.den != 0) {
      fps = av_q2d(g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
    }
    
    if (fps > 0) {
      int64_t target_ts_ms = (int64_t)((frame_index / fps) * 1000.0);
      if (seek_to_frame_before_ts(target_ts_ms) >= 0) {
        result = decode_video_until_ts(target_ts_ms, &frame);
      }
    }
  }
  
  pthread_mutex_unlock(&g_state.mutex);
  
  if (task->video_callback && !task->cancelled) {
    task->video_callback(task->user_data, frame, result);
  } else if (frame) {
    ffmpeg_free_video_frame(frame);
  }
}

static void process_audio_task(AsyncTask *task) {
  if (task->cancelled) return;
  
  pthread_mutex_lock(&g_state.mutex);
  
  AudioFrame *frame = NULL;
  int result = -1;
  
  if (task->type == TASK_AUDIO_AT_TIMESTAMP) {
    int64_t timestamp_ms = task->params.single.timestamp_ms;
    if (seek_to_frame_before_ts(timestamp_ms) >= 0) {
      result = decode_audio_until_ts(timestamp_ms, &frame);
    }
  } else if (task->type == TASK_AUDIO_AT_INDEX) {
    int frame_index = task->params.single.frame_index;
    
    if (g_state.audio_codec_ctx) {
      int samples_per_frame = g_state.audio_codec_ctx->frame_size;
      if (samples_per_frame <= 0) samples_per_frame = 1024;
      
      int64_t frame_duration_ms = (samples_per_frame * 1000) / g_state.audio_codec_ctx->sample_rate;
      int64_t target_ts_ms = frame_index * frame_duration_ms;
      
      if (seek_to_frame_before_ts(target_ts_ms) >= 0) {
        result = decode_audio_until_ts(target_ts_ms, &frame);
      }
    }
  }
  
  pthread_mutex_unlock(&g_state.mutex);
  
  if (task->audio_callback && !task->cancelled) {
    task->audio_callback(task->user_data, frame, result);
  } else if (frame) {
    ffmpeg_free_audio_frame(frame);
  }
}

static void process_video_range_task(AsyncTask *task) {
  if (task->cancelled) return;
  
  pthread_mutex_lock(&g_state.mutex);
  
  int start_index = task->params.range.start_index;
  int end_index = task->params.range.end_index;
  int total = end_index - start_index + 1;
  
  // Calculate FPS
  double fps = 0.0;
  if (g_state.video_stream_idx >= 0 &&
      g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate.den != 0) {
    fps = av_q2d(g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
  }
  
  if (fps <= 0) {
    pthread_mutex_unlock(&g_state.mutex);
    return;
  }
  
  // Optimized: seek once to start, then decode sequentially
  int64_t start_ts_ms = (int64_t)((start_index / fps) * 1000.0);
  int64_t end_ts_ms = (int64_t)((end_index / fps) * 1000.0);
  
  if (seek_to_frame_before_ts(start_ts_ms) < 0) {
    pthread_mutex_unlock(&g_state.mutex);
    return;
  }
  
  int processed = 0;
  int current_index = start_index;
  
  while (current_index <= end_index && !task->cancelled) {
    int64_t target_ts_ms = (int64_t)((current_index / fps) * 1000.0);
    
    VideoFrame *frame = NULL;
    int result = decode_video_until_ts(target_ts_ms, &frame);
    
    if (result >= 0 && frame && task->video_callback && !task->cancelled) {
      pthread_mutex_unlock(&g_state.mutex);
      task->video_callback(task->user_data, frame, result);
      pthread_mutex_lock(&g_state.mutex);
      
      processed++;
      if (task->progress_callback && !task->cancelled) {
        pthread_mutex_unlock(&g_state.mutex);
        task->progress_callback(task->user_data, processed, total);
        pthread_mutex_lock(&g_state.mutex);
      }
    } else {
      if (frame) ffmpeg_free_video_frame(frame);
      break;
    }
    
    current_index++;
  }
  
  pthread_mutex_unlock(&g_state.mutex);
}

static void* worker_thread_func(void *arg) {
  (void)arg;
  
  while (true) {
    AsyncTask *task = task_queue_pop();
    if (!task) break;
    
    switch (task->type) {
      case TASK_VIDEO_AT_TIMESTAMP:
      case TASK_VIDEO_AT_INDEX:
        process_video_task(task);
        break;
      case TASK_AUDIO_AT_TIMESTAMP:
      case TASK_AUDIO_AT_INDEX:
        process_audio_task(task);
        break;
      case TASK_VIDEO_RANGE:
        process_video_range_task(task);
        break;
    }
    
    free(task);
  }
  
  return NULL;
}

// --- Public API Implementation ---

void ffmpeg_init(void) {
  avformat_network_init();
  pthread_mutex_init(&g_state.mutex, NULL);
  
  task_queue_init();
  
  g_state.video_stream_idx = -1;
  g_state.audio_stream_idx = -1;
  g_state.is_initialized = 1;
  
  // Start worker thread
  pthread_create(&g_task_queue.worker_thread, NULL, worker_thread_func, NULL);
}

int ffmpeg_open_media(const char *file_path) {
  if (!file_path) return -1;
  
  pthread_mutex_lock(&g_state.mutex);
  
  // Clean up any previous state
  if (g_state.fmt_ctx) {
    pthread_mutex_unlock(&g_state.mutex);
    ffmpeg_stop();
    pthread_mutex_lock(&g_state.mutex);
  }
  
  // 1. Open Input File
  if (avformat_open_input(&g_state.fmt_ctx, file_path, NULL, NULL) != 0) {
    pthread_mutex_unlock(&g_state.mutex);
    return -2;
  }
  
  // 2. Get Stream Info
  if (avformat_find_stream_info(g_state.fmt_ctx, NULL) < 0) {
    avformat_close_input(&g_state.fmt_ctx);
    g_state.fmt_ctx = NULL;
    pthread_mutex_unlock(&g_state.mutex);
    return -2;
  }
  
  g_state.video_stream_idx = -1;
  g_state.audio_stream_idx = -1;
  
  // 3. Find Codecs
  for (unsigned int i = 0; i < g_state.fmt_ctx->nb_streams; i++) {
    AVStream *stream = g_state.fmt_ctx->streams[i];
    AVCodecParameters *codec_par = stream->codecpar;
    const AVCodec *codec = avcodec_find_decoder(codec_par->codec_id);
    
    if (!codec) continue;
    
    if (codec_par->codec_type == AVMEDIA_TYPE_VIDEO &&
        g_state.video_stream_idx == -1) {
      g_state.video_stream_idx = i;
      g_state.video_codec_ctx = avcodec_alloc_context3(codec);
      if (!g_state.video_codec_ctx) {
        avformat_close_input(&g_state.fmt_ctx);
        g_state.fmt_ctx = NULL;
        pthread_mutex_unlock(&g_state.mutex);
        return -3;
      }
      if (avcodec_parameters_to_context(g_state.video_codec_ctx, codec_par) < 0) {
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }
      if (avcodec_open2(g_state.video_codec_ctx, codec, NULL) < 0) {
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }
      
      // Initialize scaler for RGBA conversion
      g_state.video_frame = av_frame_alloc();
      g_state.video_frame_rgba = av_frame_alloc();
      
      if (!g_state.video_frame || !g_state.video_frame_rgba) {
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
        av_frame_free(&g_state.video_frame);
        av_frame_free(&g_state.video_frame_rgba);
        avcodec_free_context(&g_state.video_codec_ctx);
        g_state.video_codec_ctx = NULL;
        g_state.video_stream_idx = -1;
        continue;
      }
      
      g_state.video_buffer = (uint8_t *)av_malloc(num_bytes * sizeof(uint8_t));
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
        pthread_mutex_unlock(&g_state.mutex);
        return -3;
      }
      if (avcodec_parameters_to_context(g_state.audio_codec_ctx, codec_par) < 0) {
        avcodec_free_context(&g_state.audio_codec_ctx);
        g_state.audio_codec_ctx = NULL;
        g_state.audio_stream_idx = -1;
        continue;
      }
      if (avcodec_open2(g_state.audio_codec_ctx, codec, NULL) < 0) {
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
        
        int max_samples = g_state.audio_codec_ctx->frame_size;
        if (max_samples <= 0) max_samples = 1024;
        
        uint8_t **audio_data = NULL;
        if (av_samples_alloc_array_and_samples(
            &audio_data, NULL, 2, max_samples, AV_SAMPLE_FMT_FLT, 0) < 0) {
          av_frame_free(&g_state.audio_frame);
          av_frame_free(&g_state.audio_frame_converted);
          g_state.audio_frame = NULL;
          g_state.audio_frame_converted = NULL;
          avcodec_free_context(&g_state.audio_codec_ctx);
          g_state.audio_codec_ctx = NULL;
          g_state.audio_stream_idx = -1;
          continue;
        }
        
        g_state.audio_frame_converted->format = AV_SAMPLE_FMT_FLT;
        g_state.audio_frame_converted->nb_samples = 0;
        AVChannelLayout stereo_layout = AV_CHANNEL_LAYOUT_STEREO;
        av_channel_layout_copy(&g_state.audio_frame_converted->ch_layout, &stereo_layout);
        g_state.audio_frame_converted->data[0] = audio_data[0];
        g_state.audio_frame_converted->linesize[0] = max_samples * 2 * sizeof(float);
        
        AVChannelLayout out_ch_layout = AV_CHANNEL_LAYOUT_STEREO;
        
        if (swr_alloc_set_opts2(&g_state.swr_ctx, &out_ch_layout, AV_SAMPLE_FMT_FLT,
                            g_state.audio_codec_ctx->sample_rate,
                            &g_state.audio_codec_ctx->ch_layout,
                            g_state.audio_codec_ctx->sample_fmt,
                            g_state.audio_codec_ctx->sample_rate, 0, NULL) < 0) {
          av_freep(&g_state.audio_frame_converted->data[0]);
          av_frame_free(&g_state.audio_frame);
          av_frame_free(&g_state.audio_frame_converted);
          avcodec_free_context(&g_state.audio_codec_ctx);
          g_state.audio_codec_ctx = NULL;
          g_state.audio_stream_idx = -1;
          continue;
        }
        
        if (swr_init(g_state.swr_ctx) < 0) {
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
    pthread_mutex_unlock(&g_state.mutex);
    ffmpeg_stop();
    return -3;
  }
  
  pthread_mutex_unlock(&g_state.mutex);
  return 0;
}

MediaInfo ffmpeg_get_media_info(void) {
  MediaInfo info = {0};
  info.duration_ms = -1;
  
  pthread_mutex_lock(&g_state.mutex);
  
  if (g_state.fmt_ctx) {
    info.duration_ms = g_state.fmt_ctx->duration / (AV_TIME_BASE / 1000);
    if (g_state.video_codec_ctx) {
      info.width = g_state.video_codec_ctx->width;
      info.height = g_state.video_codec_ctx->height;
      
      double fps = 0.0;
      if (g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate.den != 0) {
        fps = av_q2d(g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
      }
      info.fps = fps;
      
      int64_t frames = g_state.fmt_ctx->streams[g_state.video_stream_idx]->nb_frames;
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
  
  pthread_mutex_unlock(&g_state.mutex);
  return info;
}

void ffmpeg_stop(void) {
  pthread_mutex_lock(&g_state.mutex);
  
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
  
  pthread_mutex_unlock(&g_state.mutex);
}

void ffmpeg_free_video_frame(VideoFrame *frame) {
  if (frame) {
    if (frame->data) free(frame->data);
    free(frame);
  }
}

void ffmpeg_free_audio_frame(AudioFrame *frame) {
  if (frame) {
    if (frame->data) free(frame->data);
    free(frame);
  }
}

// Async API Implementation
RequestId ffmpeg_get_video_frame_at_timestamp_async(
    int64_t timestamp_ms,
    OnVideoFrameCallback callback,
    void *user_data) {
  
  AsyncTask *task = (AsyncTask *)malloc(sizeof(AsyncTask));
  if (!task) return -1;
  
  task->type = TASK_VIDEO_AT_TIMESTAMP;
  task->params.single.timestamp_ms = timestamp_ms;
  task->video_callback = callback;
  task->audio_callback = NULL;
  task->progress_callback = NULL;
  task->user_data = user_data;
  
  return task_queue_add(task);
}

RequestId ffmpeg_get_video_frame_at_index_async(
    int frame_index,
    OnVideoFrameCallback callback,
    void *user_data) {
  
  AsyncTask *task = (AsyncTask *)malloc(sizeof(AsyncTask));
  if (!task) return -1;
  
  task->type = TASK_VIDEO_AT_INDEX;
  task->params.single.frame_index = frame_index;
  task->video_callback = callback;
  task->audio_callback = NULL;
  task->progress_callback = NULL;
  task->user_data = user_data;
  
  return task_queue_add(task);
}

RequestId ffmpeg_get_audio_frame_at_timestamp_async(
    int64_t timestamp_ms,
    OnAudioFrameCallback callback,
    void *user_data) {
  
  AsyncTask *task = (AsyncTask *)malloc(sizeof(AsyncTask));
  if (!task) return -1;
  
  task->type = TASK_AUDIO_AT_TIMESTAMP;
  task->params.single.timestamp_ms = timestamp_ms;
  task->video_callback = NULL;
  task->audio_callback = callback;
  task->progress_callback = NULL;
  task->user_data = user_data;
  
  return task_queue_add(task);
}

RequestId ffmpeg_get_audio_frame_at_index_async(
    int frame_index,
    OnAudioFrameCallback callback,
    void *user_data) {
  
  AsyncTask *task = (AsyncTask *)malloc(sizeof(AsyncTask));
  if (!task) return -1;
  
  task->type = TASK_AUDIO_AT_INDEX;
  task->params.single.frame_index = frame_index;
  task->video_callback = NULL;
  task->audio_callback = callback;
  task->progress_callback = NULL;
  task->user_data = user_data;
  
  return task_queue_add(task);
}

RequestId ffmpeg_get_video_frames_range_async(
    int start_index,
    int end_index,
    OnVideoFrameCallback frame_callback,
    OnFrameRangeProgressCallback progress_callback,
    void *user_data) {
  
  AsyncTask *task = (AsyncTask *)malloc(sizeof(AsyncTask));
  if (!task) return -1;
  
  task->type = TASK_VIDEO_RANGE;
  task->params.range.start_index = start_index;
  task->params.range.end_index = end_index;
  task->video_callback = frame_callback;
  task->audio_callback = NULL;
  task->progress_callback = progress_callback;
  task->user_data = user_data;
  
  return task_queue_add(task);
}

// Optimized batch retrieval (synchronous)
int ffmpeg_get_video_frames_range_by_index(
    int start_index,
    int end_index,
    FrameRangeBatch *out_batch) {
  
  if (!out_batch || !g_state.fmt_ctx || g_state.video_stream_idx < 0) return -1;
  
  pthread_mutex_lock(&g_state.mutex);
  
  double fps = 0.0;
  if (g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate.den != 0) {
    fps = av_q2d(g_state.fmt_ctx->streams[g_state.video_stream_idx]->avg_frame_rate);
  }
  
  if (fps <= 0) {
    pthread_mutex_unlock(&g_state.mutex);
    return -1;
  }
  
  int64_t start_ts_ms = (int64_t)((start_index / fps) * 1000.0);
  
  if (seek_to_frame_before_ts(start_ts_ms) < 0) {
    pthread_mutex_unlock(&g_state.mutex);
    return -1;
  }
  
  int count = 0;
  int current_index = start_index;
  
  while (current_index <= end_index) {
    int64_t target_ts_ms = (int64_t)((current_index / fps) * 1000.0);
    
    VideoFrame *frame = NULL;
    int result = decode_video_until_ts(target_ts_ms, &frame);
    
    if (result >= 0 && frame) {
      if (out_batch->video_frames) {
        out_batch->video_frames[count] = frame;
      }
      if (out_batch->result_codes) {
        out_batch->result_codes[count] = result;
      }
      count++;
    } else {
      break;
    }
    
    current_index++;
  }
  
  out_batch->count = count;
  
  pthread_mutex_unlock(&g_state.mutex);
  return count;
}

int ffmpeg_get_video_frames_range_by_timestamp(
    int64_t start_ms,
    int64_t end_ms,
    int64_t step_ms,
    FrameRangeBatch *out_batch) {
  
  if (!out_batch || !g_state.fmt_ctx || g_state.video_stream_idx < 0) return -1;
  
  pthread_mutex_lock(&g_state.mutex);
  
  if (seek_to_frame_before_ts(start_ms) < 0) {
    pthread_mutex_unlock(&g_state.mutex);
    return -1;
  }
  
  int count = 0;
  int64_t current_ts = start_ms;
  
  while (current_ts <= end_ms) {
    VideoFrame *frame = NULL;
    int result = decode_video_until_ts(current_ts, &frame);
    
    if (result >= 0 && frame) {
      if (out_batch->video_frames) {
        out_batch->video_frames[count] = frame;
      }
      if (out_batch->result_codes) {
        out_batch->result_codes[count] = result;
      }
      count++;
    } else {
      break;
    }
    
    current_ts += step_ms;
  }
  
  out_batch->count = count;
  
  pthread_mutex_unlock(&g_state.mutex);
  return count;
}

void ffmpeg_free_frame_range_batch(FrameRangeBatch *batch) {
  if (!batch) return;
  
  if (batch->video_frames) {
    for (int i = 0; i < batch->count; i++) {
      if (batch->video_frames[i]) {
        ffmpeg_free_video_frame(batch->video_frames[i]);
      }
    }
  }
  
  if (batch->audio_frames) {
    for (int i = 0; i < batch->count; i++) {
      if (batch->audio_frames[i]) {
        ffmpeg_free_audio_frame(batch->audio_frames[i]);
      }
    }
  }
}

void ffmpeg_cancel_request(RequestId request_id) {
  pthread_mutex_lock(&g_task_queue.mutex);
  
  AsyncTask *task = g_task_queue.head;
  while (task) {
    if (task->id == request_id) {
      task->cancelled = true;
      break;
    }
    task = task->next;
  }
  
  pthread_mutex_unlock(&g_task_queue.mutex);
}

void ffmpeg_release(void) {
  ffmpeg_stop();
  
  // Stop worker thread
  pthread_mutex_lock(&g_task_queue.mutex);
  g_task_queue.should_exit = true;
  pthread_cond_signal(&g_task_queue.cond);
  pthread_mutex_unlock(&g_task_queue.mutex);
  
  pthread_join(g_task_queue.worker_thread, NULL);
  
  task_queue_destroy();
  avformat_network_deinit();
  pthread_mutex_destroy(&g_state.mutex);
  
  g_state.is_initialized = 0;
}
