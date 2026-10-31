cmake_minimum_required(VERSION 3.18.1)
project(writing_opentype LANGUAGES C CXX)
get_filename_component(WRITING_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
add_library(writing_harfbuzz SHARED
  "${WRITING_ROOT}/native/opentype_bridge.cc"
  "${WRITING_ROOT}/third_party/harfbuzz/src/harfbuzz.cc")
target_include_directories(writing_harfbuzz PRIVATE "${WRITING_ROOT}/third_party/harfbuzz/src")
target_compile_features(writing_harfbuzz PRIVATE cxx_std_17)
