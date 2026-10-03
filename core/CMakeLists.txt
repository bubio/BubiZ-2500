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
target_include_directories(bubiz_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/compat)
# CSPのソースがWindows/Qt環境で暗黙に取得していたヘッダを補う
target_compile_options(bubiz_core PRIVATE
  -include ${CMAKE_CURRENT_SOURCE_DIR}/compat/bubiz_prelude.h
  -w -fno-strict-aliasing -fpermissive)
target_include_directories(bubiz_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
find_package(Threads REQUIRED)
target_link_libraries(bubiz_core PUBLIC Threads::Threads)
