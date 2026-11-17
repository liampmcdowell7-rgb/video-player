// Linux tests only: the locally built codec library (scripts/test-audio.sh). Nothing imports this module from Swift; it
// exists so that CMediaCodecs links the shared libraries found through pkg-config.
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
