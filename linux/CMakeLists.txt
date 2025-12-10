cmake_minimum_required(VERSION 3.10)

project(ffmpeg_streamer_plugin LANGUAGES C)

# List of source files
set(SOURCE_FILES
  "../src/ffmpeg_core.c"
)

add_library(ffmpeg_streamer SHARED
  ${SOURCE_FILES}
)

# Include directories
target_include_directories(ffmpeg_streamer PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../src")

# Find FFmpeg using PkgConfig
find_package(PkgConfig REQUIRED)

pkg_check_modules(AVCODEC REQUIRED libavcodec)
pkg_check_modules(AVFORMAT REQUIRED libavformat)
pkg_check_modules(AVUTIL REQUIRED libavutil)
pkg_check_modules(SWSCALE REQUIRED libswscale)
pkg_check_modules(SWRESAMPLE REQUIRED libswresample)

target_include_directories(ffmpeg_streamer PRIVATE
    ${AVCODEC_INCLUDE_DIRS}
    ${AVFORMAT_INCLUDE_DIRS}
    ${AVUTIL_INCLUDE_DIRS}
    ${SWSCALE_INCLUDE_DIRS}
    ${SWRESAMPLE_INCLUDE_DIRS}
)

target_link_libraries(ffmpeg_streamer PRIVATE
    ${AVCODEC_LIBRARIES}
    ${AVFORMAT_LIBRARIES}
    ${AVUTIL_LIBRARIES}
    ${SWSCALE_LIBRARIES}
    ${SWRESAMPLE_LIBRARIES}
)

target_compile_options(ffmpeg_streamer PRIVATE -Wall -Werror)
