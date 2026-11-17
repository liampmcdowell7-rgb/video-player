#ifndef CLIBNFS_H
#define CLIBNFS_H
// Apple platforms: exposes the NFSKit Libnfs.xcframework headers (nfsc/) to Swift as module `CLibnfs`.
// Nothing here is our own C code; CLibnfs.c is empty and only exists so SwiftPM builds a C target
// that links the binary target.
// libnfs.h uses struct timeval and fixed-width integers without including their headers.
#include <stdint.h>
#include <sys/types.h>
#include <sys/time.h>
#include <nfsc/libnfs.h>
#endif
