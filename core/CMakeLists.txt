cmake_minimum_required(VERSION 3.16)
project(bubiz_core CXX)

# エミュレーションコア(CSP EmuZ-2500) + ホスト層 + C APIを静的ライブラリにする
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Windows(MSVC): OdinはC標準ライブラリを静的(libcmt)でリンクするため、コアも静的ランタイム(/MT)に揃える
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

set(CSP ${CMAKE_CURRENT_SOURCE_DIR}/csp)

set(VM_DEVICES
  cmu800 datarec disk event harddisk i8253 i8255 io mb8877 midi mz1p17 noise
  pcm1bit prnfile rp5c01 scsi_dev scsi_hdd scsi_host w3100a ym2203 z80 z80pio z80sio)
set(VM_SOURCES)
foreach(d ${VM_DEVICES})
  list(APPEND VM_SOURCES ${CSP}/vm/${d}.cpp)
endforeach()

file(GLOB FMGEN_SOURCES ${CSP}/vm/fmgen/*.cpp)
file(GLOB MZ2500_SOURCES ${CSP}/vm/mz2500/*.cpp)

add_library(bubiz_core STATIC
  ${CSP}/common.cpp ${CSP}/config.cpp ${CSP}/emu.cpp ${CSP}/fifo.cpp ${CSP}/fileio.cpp
  ${VM_SOURCES} ${FMGEN_SOURCES} ${MZ2500_SOURCES}
  host/osd.cpp bubiz_core.cpp)

target_compile_definitions(bubiz_core PRIVATE _MZ2500 BUBIZ_HOST)
if(MSVC)
  # MSVC: CSPの本来のビルド環境。警告は抑止し、強制インクルードで不足ヘッダを補う
  target_compile_definitions(bubiz_core PRIVATE _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_WARNINGS)
  target_compile_options(bubiz_core PRIVATE /w /FI${CMAKE_CURRENT_SOURCE_DIR}/compat/bubiz_prelude.h)
else()
  # Linux/macOS: Windows専用ヘッダio.hの代替を置いたcompatを優先し、不足ヘッダを強制インクルードで補う
  target_include_directories(bubiz_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/compat)
  target_compile_options(bubiz_core PRIVATE
    -include ${CMAKE_CURRENT_SOURCE_DIR}/compat/bubiz_prelude.h
    -w -Wno-register -fno-strict-aliasing)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(bubiz_core PRIVATE -fpermissive)
  endif()
endif()
target_include_directories(bubiz_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
if(NOT MSVC)
  find_package(Threads REQUIRED)
  target_link_libraries(bubiz_core PUBLIC Threads::Threads)
endif()

# 煙テスト(ROM無しで生成・駆動・描画・音声取得ができること)
add_executable(bubiz_smoke tests/smoke.cpp)
target_link_libraries(bubiz_smoke PRIVATE bubiz_core)
