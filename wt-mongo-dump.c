/*
 * wt-mongo-dump - reads the raw files of a MongoDB database (any WiredTiger-based mongod,
 * 3.x - 8.x) WITHOUT mongod, and writes every collection as a mongodump-style .bson file.
 *
 *   wt-mongo-dump [--allow-recovery] <dbpath> <outdir>
 *
 * It links libwiredtiger (the storage engine, no MongoDB server code) and does only what
 * mongod's storage layer does for a collection scan:
 *   1. open <dbpath> (read-only by default, so NOTHING in it can change);
 *   2. scan table:_mdb_catalog - one BSON document per namespace, holding {ns, ident};
 *   3. scan table:<ident> - key = RecordId (int64), value = the document's BSON bytes.
 * Output: <outdir>/<db>/<collection>.bson (concatenated documents, exactly what
 * mongorestore / bsondump read), plus <outdir>/_catalog.bson (raw catalog, which also
 * lists the index specs) and <outdir>/_manifest.tsv (ns, ident, documents, bytes).
 *
 * --allow-recovery: a mongod killed uncleanly leaves a journal that has to be replayed
 * before the tables are consistent; WiredTiger can only do that read-write, which changes
 * the files. Without the flag such a database is refused (and left untouched); run it on a
 * COPY with the flag.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <wiredtiger.h>

static int die(const char *what, int rc) {
  fprintf(stderr, "wt-mongo-dump: %s: %s\n", what, wiredtiger_strerror(rc));
  return 1;
}

/* BSON element sizes, enough to walk a top-level document. Returns -1 on a type we cannot size. */
static int32_t rd32(const uint8_t *p) { return (int32_t)(p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24); }
static long bson_value_size(uint8_t t, const uint8_t *v, size_t left) {
  switch (t) {
  case 0x01: return 8;                                           /* double */
  case 0x02: case 0x0D: case 0x0E: if (left < 4) return -1; return 4 + rd32(v); /* string, js, symbol */
  case 0x03: case 0x04: if (left < 4) return -1; return rd32(v); /* document, array */
  case 0x05: if (left < 4) return -1; return 4 + 1 + rd32(v);    /* binary */
  case 0x06: case 0x0A: case 0xFF: case 0x7F: return 0;          /* undefined, null, minkey, maxkey */
  case 0x07: return 12;                                          /* objectid */
  case 0x08: return 1;                                           /* bool */
  case 0x09: case 0x11: case 0x12: return 8;                     /* date, timestamp, int64 */
  case 0x10: return 4;                                           /* int32 */
  case 0x13: return 16;                                          /* decimal128 */
  case 0x0B: { size_t i = 0; int n = 0; while (i < left && n < 2) { if (v[i] == 0) n++; i++; } return n == 2 ? (long)i : -1; } /* regex */
  case 0x0C: if (left < 4) return -1; return 4 + rd32(v) + 12;   /* dbpointer */
  case 0x0F: if (left < 4) return -1; return rd32(v);            /* js with scope */
  default: return -1;
  }
}
/* Find a top-level string field; copies it into out. Returns 1 when found. */
static int bson_get_string(const uint8_t *d, size_t len, const char *name, char *out, size_t outsz) {
  size_t i = 4;
  while (i < len && d[i] != 0) {
    uint8_t t = d[i++];
    const char *key = (const char *)d + i;
    size_t kl = strnlen(key, len - i);
    i += kl + 1;
    if (i > len) return 0;
    if (t == 0x02 && strcmp(key, name) == 0) {
      int32_t sl = rd32(d + i);
      if (sl < 1 || (size_t)sl > outsz || i + 4 + sl > len) return 0;
      memcpy(out, d + i + 4, sl);
      out[sl - 1] = 0;
      return 1;
    }
    long vs = bson_value_size(t, d + i, len - i);
    if (vs < 0) return 0;
    i += vs;
  }
  return 0;
}

static void mkdirs(const char *path) {
  char tmp[4096]; snprintf(tmp, sizeof tmp, "%s", path);
  for (char *p = tmp + 1; *p; p++) if (*p == '/') { *p = 0; mkdir(tmp, 0755); *p = '/'; }
  mkdir(tmp, 0755);
}

int main(int argc, char **argv) {
  int allow_recovery = 0, repair = 0, ai = 1;
  for (; ai < argc && strncmp(argv[ai], "--", 2) == 0; ai++) {
    if (strcmp(argv[ai], "--allow-recovery") == 0) allow_recovery = 1;
    else if (strcmp(argv[ai], "--repair") == 0) { repair = 1; allow_recovery = 1; }   /* repair implies a writable COPY */
    else { fprintf(stderr, "wt-mongo-dump: unknown flag %s\n", argv[ai]); return 2; }
  }
  if (argc - ai != 2) { fprintf(stderr, "usage: wt-mongo-dump [--allow-recovery] [--repair] <dbpath> <outdir>\n"); return 2; }
  const char *dbpath = argv[ai], *outdir = argv[ai + 1];
  const char *exts = getenv("WT_EXTENSIONS");   /* e.g. .../libwiredtiger_snappy.so,.../libwiredtiger_zlib.so */
  /* The journal's compressor is NOT recorded in the files: mongod passes it at open
     (journalCompressor, snappy by default, or zstd / zlib / none), and a journal record
     compressed with a compressor that was not configured stops the open. So try the
     likely ones in turn. The block compressor of each table IS recorded per table. */
  static const char *journal_compressors[] = { "snappy", "zstd", "zlib", "none", NULL };
  WT_CONNECTION *conn = NULL; WT_SESSION *s; WT_CURSOR *cat;
  int rc = WT_ERROR;
  for (int ci = 0; journal_compressors[ci] && !conn; ci++) {
    char cfg[4096], ext[1024] = "";
    if (exts)   /* comma-separated shared objects: the block and journal compressors */
      snprintf(ext, sizeof ext, "extensions=[%s],", exts);
    snprintf(cfg, sizeof cfg,
      "%sconfig_base=false,cache_size=512MB,log=(enabled=true,path=journal%s%s%s),statistics=(none)%s",
      ext, strcmp(journal_compressors[ci], "none") ? ",compressor=" : "",
      strcmp(journal_compressors[ci], "none") ? journal_compressors[ci] : "", "",
      allow_recovery ? (repair ? ",salvage=true" : "") : ",readonly=true");
    rc = wiredtiger_open(dbpath, NULL, cfg, &conn);
    if (rc) conn = NULL;
  }
  if (!conn) return die("open (an unclean shutdown needs --allow-recovery on a copy)", rc);
  if ((rc = conn->open_session(conn, NULL, NULL, &s))) return die("session", rc);
  mkdirs(outdir);
  char p[4096];
  snprintf(p, sizeof p, "%s/_catalog.bson", outdir); FILE *cf = fopen(p, "wb");
  snprintf(p, sizeof p, "%s/_manifest.tsv", outdir); FILE *mf = fopen(p, "w");
  if (!cf || !mf) { perror("output"); return 1; }
  if ((rc = s->open_cursor(s, "table:_mdb_catalog", NULL, NULL, &cat))) return die("table:_mdb_catalog", rc);
  int failures = 0;
  while ((rc = cat->next(cat)) == 0) {
    WT_ITEM v; if ((rc = cat->get_value(cat, &v))) return die("catalog value", rc);
    fwrite(v.data, 1, v.size, cf);
    char ns[1024], ident[512];
    if (!bson_get_string(v.data, v.size, "ns", ns, sizeof ns) || !bson_get_string(v.data, v.size, "ident", ident, sizeof ident))
      continue;   /* a view or an entry without storage */
    char uri[600]; snprintf(uri, sizeof uri, "table:%s", ident);
    char db[512], coll[512]; const char *dot = strchr(ns, '.');
    if (!dot) continue;
    snprintf(db, sizeof db, "%.*s", (int)(dot - ns), ns); snprintf(coll, sizeof coll, "%s", dot + 1);
    snprintf(p, sizeof p, "%s/%s", outdir, db); mkdirs(p);
    snprintf(p, sizeof p, "%s/%s/%s.bson", outdir, db, coll);
    uint64_t n = 0, bytes = 0; int salvaged = 0;
    /* A damaged block makes the first read PANIC the whole connection, so repair has to
       happen BEFORE the table is read, exactly as `mongod --repair` salvages every table
       first. Salvage rewrites the file in the (copied) dbpath keeping the readable pages. */
    if (repair) {
      int sr = s->salvage(s, uri, NULL);
      if (sr) { fprintf(stderr, "wt-mongo-dump: salvage of %s (%s) failed: %s\n", ns, ident, wiredtiger_strerror(sr)); failures++; continue; }
      salvaged = 1;
    }
    for (int attempt = 0; attempt < 2; attempt++) {
      n = 0; bytes = 0;
      FILE *o = fopen(p, "wb"); if (!o) { perror(p); return 1; }
      WT_CURSOR *c = NULL;
      int r = s->open_cursor(s, uri, NULL, NULL, &c);
      if (r == 0) {
        while ((r = c->next(c)) == 0) {
          WT_ITEM dv; if ((r = c->get_value(c, &dv))) break;
          if (fwrite(dv.data, 1, dv.size, o) != dv.size) { perror("write"); return 1; }
          n++; bytes += dv.size;
        }
        if (r == WT_NOTFOUND) r = 0;
        c->close(c);
      }
      fclose(o);
      if (r == 0) break;
      fprintf(stderr, "wt-mongo-dump: %s (%s): %s\n", ns, ident, wiredtiger_strerror(r));
      failures++; break;
    }
    if (salvaged) fprintf(stderr, "wt-mongo-dump: %s salvaged: %llu documents recovered\n", ns, (unsigned long long)n);
    fprintf(mf, "%s\t%s\t%llu\t%llu\n", ns, ident, (unsigned long long)n, (unsigned long long)bytes);
  }
  fclose(cf); fclose(mf); cat->close(cat); conn->close(conn, NULL);
  return failures ? 3 : 0;
}
