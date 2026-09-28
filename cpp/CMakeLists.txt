cmake_minimum_required(VERSION 3.16)
project(paredao_cpp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(SDL2 REQUIRED CONFIG)

add_executable(paredao main.cpp)
target_link_libraries(paredao PRIVATE SDL2::SDL2)
target_compile_options(paredao PRIVATE -Wall -Wextra)
