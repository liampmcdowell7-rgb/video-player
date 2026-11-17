// libnfs.h uses struct timeval and fixed-width integers without including their headers.
#include <stdint.h>
#include <sys/types.h>
#include <sys/time.h>
#include <nfsc/libnfs.h>
