cmake_minimum_required(VERSION 3.25)
project(cod29_foundation
    VERSION 0.1.0
    DESCRIPTION "COD-29 Foundation: Top-edge Workspace Drag for Rice Shell"
    LANGUAGES CXX
)

# Enforce C++23 standard
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Enable compiler warnings
add_compile_options(-Wall -Wextra -Wpedantic)

# Find PkgConfig and Hyprland dependency
find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED hyprland)

# Common include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${HYPRLAND_INCLUDE_DIRS}
)

# -----------------------------------------------------------------------------
# Milestone 2: Native Spike & ABI Check Program
# -----------------------------------------------------------------------------
add_executable(native_spike_check
    tools/cod29/native_spike_check.cpp
)

target_include_directories(native_spike_check PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${HYPRLAND_INCLUDE_DIRS}
)

target_compile_options(native_spike_check PRIVATE
    ${HYPRLAND_CFLAGS_OTHER}
)

target_link_directories(native_spike_check PRIVATE
    ${HYPRLAND_LIBRARY_DIRS}
)

target_link_libraries(native_spike_check PRIVATE
    ${HYPRLAND_LIBRARIES}
)

# -----------------------------------------------------------------------------
# Future Milestones (Phase C: State Machine & Unit Tests)
# -----------------------------------------------------------------------------
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/cod29/top_edge_drag_logic.cpp")
    add_library(top_edge_drag_logic STATIC
        src/cod29/top_edge_drag_logic.cpp
    )
    target_include_directories(top_edge_drag_logic PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/cod29/top_edge_drag_logic_test.cpp")
    add_executable(top_edge_drag_logic_test
        tools/cod29/top_edge_drag_logic_test.cpp
    )
    target_link_libraries(top_edge_drag_logic_test PRIVATE
        top_edge_drag_logic
    )
endif()
