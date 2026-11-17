// Proves libnfs (NFSv3) can mount, list, stat and read ranges from `rclone serve nfs`, with no Swift involved.
// Build and run: see the comment block at the top of scripts/test-nfs.sh (libnfs prefix), then
//   gcc -o /tmp/nfs-harness scripts/nfs-harness.c -I$PFX/include -L$PFX/lib -lnfs -Wl,-rpath,$PFX/lib
//   /tmp/nfs-harness "nfs://127.0.0.1/?version=3&nfsport=12049&mountport=12049&auto-traverse-mounts=0"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <nfsc/libnfs.h>
#include <nfsc/libnfs-raw.h>
static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { printf("FAIL: %s\n", msg); fails++; } else printf("ok: %s\n", msg); } while (0)
int main(int argc, char **argv) {
  const char *url = argc > 1 ? argv[1] : "nfs://127.0.0.1/?version=3&nfsport=12049&mountport=12049&auto-traverse-mounts=0";
  struct nfs_context *nfs = nfs_init_context();
  struct nfs_url *u = nfs_parse_url_dir(nfs, url);
  if (!u) { printf("parse failed: %s\n", nfs_get_error(nfs)); return 2; }
  printf("server=%s path=%s\n", u->server, u->path);
  nfs_set_version(nfs, 3);
  nfs_set_timeout(nfs, 5000);
  if (nfs_mount(nfs, u->server, u->path) != 0) { printf("mount failed: %s\n", nfs_get_error(nfs)); return 3; }
  CHECK(1, "mount");
  struct nfsdir *d; struct nfsdirent *e; int n = 0, sawMovies = 0;
  if (nfs_opendir(nfs, "/", &d) != 0) { printf("opendir failed: %s\n", nfs_get_error(nfs)); return 4; }
  while ((e = nfs_readdir(nfs, d))) { printf("  entry %s type=%d size=%llu\n", e->name, e->type, (unsigned long long)e->size); n++; if (!strcmp(e->name, "Movies")) sawMovies = 1; }
  nfs_closedir(nfs, d);
  CHECK(sawMovies && n >= 5, "readdir root lists Movies and others");
  struct nfs_stat_64 st;
  CHECK(nfs_stat64(nfs, "/big/Large Sample.mkv", &st) == 0, "stat64 big file");
  CHECK(st.nfs_size == 41943040, "size is 41943040");
  struct nfsfh *fh;
  CHECK(nfs_open(nfs, "/big/Large Sample.mkv", O_RDONLY, &fh) == 0, "open");
  uint64_t offs[] = {0, 1000, 1048576 + 17, 41943040 - 64};
  for (int i = 0; i < 4; i++) {
    unsigned char buf[64]; int r = nfs_pread(nfs, fh, offs[i], 64, (char*)buf);
    int ok = (r == 64);
    for (int k = 0; ok && k < 64; k++) if (buf[k] != (unsigned char)(((offs[i] + k) * 7 + 3) % 251)) ok = 0;
    char m[80]; snprintf(m, sizeof m, "pread 64 @%llu matches pattern (r=%d)", (unsigned long long)offs[i], r); CHECK(ok, m);
  }
  unsigned char tail[64]; int r = nfs_pread(nfs, fh, 41943040 - 10, 64, (char*)tail);
  CHECK(r == 10, "pread across EOF returns 10 bytes");
  nfs_close(nfs, fh);
  CHECK(nfs_stat64(nfs, "/nope.mkv", &st) != 0, "missing file errors");
  nfs_destroy_url(u); nfs_destroy_context(nfs);
  printf("%s (%d failures)\n", fails ? "HARNESS FAILED" : "HARNESS PASSED", fails);
  return fails ? 1 : 0;
}