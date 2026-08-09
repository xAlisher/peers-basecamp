cmake_minimum_required(VERSION 3.14)
project(PeersUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# NAME must match metadata.json "name"; "main" is "<name>_plugin".
logos_module(
    NAME peers_ui
    REP_FILE src/peers_ui.rep
    SOURCES
        src/PeersUiBackend.h
        src/PeersUiBackend.cpp
        src/ContentMarkers.h
        src/ContentMarkers.cpp
        src/BackupReader.h
        src/BackupReader.cpp
    INCLUDE_DIRS
        src
)
