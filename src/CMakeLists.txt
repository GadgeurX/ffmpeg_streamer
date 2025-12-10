# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(ffmpeg_streamer_library VERSION 0.0.1 LANGUAGES C)

add_library(ffmpeg_streamer SHARED
  "ffmpeg_streamer.c"
)

set_target_properties(ffmpeg_streamer PROPERTIES
  PUBLIC_HEADER ffmpeg_streamer.h
  OUTPUT_NAME "ffmpeg_streamer"
)

target_compile_definitions(ffmpeg_streamer PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(ffmpeg_streamer PRIVATE "-Wl,-z,max-page-size=16384")
endif()
