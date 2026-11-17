#ifndef CDOLBYVISIONRPU_H
#define CDOLBYVISIONRPU_H
// Apple platforms: exposes the header of the prebuilt RPU library (Frameworks/DolbyVisionRPULib.xcframework, MIT,
// provenance in docs/DOLBY_VISION.md) to Swift as module `CDolbyVisionRPU`. Nothing here is our own C code;
// CDolbyVisionRPU.c is empty and only exists so SwiftPM builds a C target that links the binary target.
#include <rpu_parser.h>
#endif
