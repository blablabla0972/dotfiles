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
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

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
# Milestone 3: Pure C++ State Machine & Deterministic Unit Tests (Phase C)
# -----------------------------------------------------------------------------
add_library(top_edge_drag_logic STATIC
    src/cod29/top_edge_drag_logic.cpp
)
target_include_directories(top_edge_drag_logic PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
set_target_properties(top_edge_drag_logic PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

add_executable(top_edge_drag_logic_test
    tools/cod29/top_edge_drag_logic_test.cpp
)
target_link_libraries(top_edge_drag_logic_test PRIVATE
    top_edge_drag_logic
)

# -----------------------------------------------------------------------------
# Milestone 4: Native Hyprland Plugin Shared Library (Phase D)
# -----------------------------------------------------------------------------
add_library(cod29_top_edge_drag SHARED
    src/cod29/plugin_entry.cpp
    src/cod29/drag_hook_adapter.cpp
    src/cod29/ipc_server.cpp
)

set_target_properties(cod29_top_edge_drag PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "cod29_top_edge_drag"
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(cod29_top_edge_drag PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${HYPRLAND_INCLUDE_DIRS}
)

target_compile_options(cod29_top_edge_drag PRIVATE
    ${HYPRLAND_CFLAGS_OTHER}
    $<$<CXX_COMPILER_ID:Clang>:-Wno-return-type-c-linkage>
)

target_link_directories(cod29_top_edge_drag PRIVATE
    ${HYPRLAND_LIBRARY_DIRS}
)

target_link_libraries(cod29_top_edge_drag PRIVATE
    top_edge_drag_logic
    ${HYPRLAND_LIBRARIES}
)

# -----------------------------------------------------------------------------
# Milestone 4: Automated Integration Test Harness (IT01-IT10) (Phase D)
# -----------------------------------------------------------------------------
add_executable(cod29_integration_test
    tools/cod29/cod29_integration_test.cpp
    src/cod29/drag_hook_adapter.cpp
    src/cod29/ipc_server.cpp
)

target_include_directories(cod29_integration_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_options(cod29_integration_test PRIVATE
    $<$<CXX_COMPILER_ID:Clang>:-Wno-return-type-c-linkage>
)

target_link_libraries(cod29_integration_test PRIVATE
    top_edge_drag_logic
    pthread
)
