#!/usr/bin/env node
// wt - reads the raw data files of a MongoDB (3.0 - 8.x, WiredTiger) WITHOUT mongod.
//
//   wt detect <dbpath>                  what wrote these files, and which reader opens them
//   wt dump   <dbpath> <outdir>         every collection as <outdir>/<db>/<collection>.bson
//
// It finds out which MongoDB wrote the files, picks the WiredTiger that can open them, and
// escalates only as far as the files need - never touching the original:
//   1. open the dbpath READ-ONLY (a cleanly stopped mongod's files need nothing more);
//   2. unclean shutdown (a journal to replay) or no read-only mode (WiredTiger 2.5, mongod
//      3.0): replay the journal on a COPY;
//   3. damaged files: `repair` = WiredTiger salvage of every table, on a fresh COPY, which
//      is what `mongod --repair` does. What cannot be read is reported, not hidden.
// The reader binaries and WiredTiger libraries are laid out as $WT_HOME/<lib>/wt-mongo-dump
// and $WT_HOME/<lib>/lib/*.so (default: the directory of this file).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HOME = process.env.WT_HOME || path.dirname(fileURLToPath(import.meta.url));

// WiredTiger version in WiredTiger.turtle -> the library that reads it and the mongod it means.
// The ranges were run against real data of every mongod listed (tests/ in the wekan/wt repo).
export function readerFor(major, minor) {
  if (major === 2 && minor <= 5) return { lib: '2.5', readonly: false, mongod: '3.0' };
  if (major === 2 && minor <= 9) return { lib: '3.1', readonly: true, mongod: '3.2 or 3.4' };
  if (major === 3 && minor <= 1) return { lib: '3.1', readonly: true, mongod: '3.6 or 4.0' };
  if (major === 3 && minor <= 3) return { lib: '3.1', readonly: true, mongod: '4.2' };
  if (major === 10) return { lib: '11.3', readonly: true, mongod: '4.4, 5.0 or 6.0' };
  if (major === 11 && minor <= 2) return { lib: '11.3', readonly: true, mongod: '7.0' };
  if (major >= 11) return { lib: '11.3', readonly: true, mongod: '8.0 or newer' };
  return null;
}

export function detect(dbpath) {
  const names = fs.existsSync(dbpath) ? fs.readdirSync(dbpath) : [];
  const info = { dbpath, engine: 'unknown', wiredTiger: null, mongod: null, lib: null, readonly: null,
    journal: names.includes('journal'), mongodLock: false, notes: [] };
  if (!names.length) { info.notes.push('the directory is empty or does not exist'); return info; }
  try { info.mongodLock = fs.statSync(path.join(dbpath, 'mongod.lock')).size > 0; } catch { /* none */ }
  const turtle = path.join(dbpath, 'WiredTiger.turtle');
  if (fs.existsSync(turtle)) {
    const m = /WiredTiger version\s+major=(\d+),minor=(\d+),patch=(\d+)/.exec(fs.readFileSync(turtle, 'utf8'));
    if (m) {
      info.engine = 'wiredtiger';
      info.wiredTiger = `${m[1]}.${m[2]}.${m[3]}`;
      const r = readerFor(Number(m[1]), Number(m[2]));
      if (r) Object.assign(info, { mongod: r.mongod, lib: r.lib, readonly: r.readonly });
      else info.notes.push(`WiredTiger ${info.wiredTiger} is not one this tool has a reader for`);
    }
  } else if (names.some(n => /\.ns$/.test(n)) || names.some(n => /\.\d+$/.test(n))) {
    info.engine = 'mmapv1';
    info.notes.push('MMAPv1 files (mongod 3.0 and older default engine): not WiredTiger, wt cannot read them');
  } else {
    info.notes.push('no WiredTiger.turtle: this is not a mongod WiredTiger dbpath');
  }
  if (info.mongodLock) info.notes.push('mongod.lock is not empty: mongod did not stop cleanly, the journal may need replaying');
  return info;
}

function dirSize(p) {
  let n = 0;
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    const f = path.join(p, e.name);
    n += e.isDirectory() ? dirSize(f) : fs.statSync(f).size;
  }
  return n;
}

// What differs between operating systems for running a reader that sits beside its libraries.
export function platformInfo(platform = process.platform) {
  return {
    exe: platform === 'win32' ? 'wt-mongo-dump.exe' : 'wt-mongo-dump',
    // where the loader looks for libwiredtiger when the binary's own rpath is not enough
    libVar: platform === 'win32' ? 'PATH' : platform === 'darwin' ? 'DYLD_LIBRARY_PATH' : 'LD_LIBRARY_PATH',
    sep: platform === 'win32' ? ';' : ':',
    // the block and journal compressors WiredTiger loads as extensions
    extension: /^(lib)?wiredtiger_(snappy|zlib|zstd)\.(so|dylib|dll)$/,
  };
}

function runReader(lib, flags, dbpath, outdir) {
  const info = platformInfo();
  const dir = path.join(HOME, lib);
  const libdir = path.join(dir, 'lib');
  const exts = fs.existsSync(libdir)
    ? fs.readdirSync(libdir).filter(f => info.extension.test(f)).map(f => path.join(libdir, f).replace(/\\/g, '/')).join(',') : '';
  const env = { ...process.env, WT_EXTENSIONS: exts };
  env[info.libVar] = libdir + (process.env[info.libVar] ? info.sep + process.env[info.libVar] : '');
  const r = spawnSync(path.join(dir, info.exe), [...flags, dbpath, outdir], { encoding: 'utf8', maxBuffer: 64 << 20, env });
  if (r.error || /error while loading shared libraries|cannot execute|dyld: |Library not loaded/.test(`${r.stderr}`)) {
    // not a refusal by the data: the tool itself is incomplete, and no escalation can fix that
    throw new Error(`the reader ${lib} cannot run: ${r.error ? r.error.message : String(r.stderr).split('\n')[0]}`);
  }
  const log = `${r.stdout || ''}${r.stderr || ''}`.split('\n').filter(l => l && !/\[WT_VERB_DEFAULT\]\[ERROR\]/.test(l)).join('\n');
  return { ok: r.status === 0, status: r.status, log };
}

function withCopy(dbpath, tmpRoot, fn) {
  const need = dirSize(dbpath) * 1.1;
  const free = fs.statfsSync(tmpRoot);
  if (free.bavail * free.bsize < need) {
    return { ok: false, log: `not enough free space in ${tmpRoot} for a copy (${Math.round(need / 1048576)} MB needed)` };
  }
  const copy = fs.mkdtempSync(path.join(tmpRoot, 'wt-copy-'));
  try {
    fs.cpSync(dbpath, copy, { recursive: true });
    return fn(copy);
  } finally {
    fs.rmSync(copy, { recursive: true, force: true });
  }
}

// The feature compatibility version mongod recorded: the exact answer to "which MongoDB".
export function readFcv(outdir) {
  const f = path.join(outdir, 'admin', 'system.version.bson');
  if (!fs.existsSync(f)) return null;
  const b = fs.readFileSync(f);
  for (let off = 0; off + 4 <= b.length;) {
    const size = b.readInt32LE(off);
    const doc = b.subarray(off, off + size);
    if (doc.includes('featureCompatibilityVersion')) {
      const i = doc.indexOf(Buffer.from('\x02version\0'));
      if (i >= 0) { const l = doc.readInt32LE(i + 9); return doc.toString('utf8', i + 13, i + 13 + l - 1); }
    }
    off += size;
  }
  return null;
}

export function dump(dbpath, outdir, { tmp = process.env.TMPDIR || os.tmpdir(), repair = false, say = console.log } = {}) {
  const info = detect(dbpath);
  if (info.engine !== 'wiredtiger' || !info.lib) { say(`wt: ${info.notes.join('; ') || 'cannot read these files'}`); return { ok: false, info }; }
  say(`wt: WiredTiger ${info.wiredTiger} (mongod ${info.mongod}); reader ${info.lib}`);
  if (!fs.existsSync(path.join(HOME, info.lib, platformInfo().exe))) {
    // e.g. WiredTiger 2.5 (mongod 3.0) does not build on arm64: say so instead of failing obscurely
    say(`wt: this build of wt has no reader ${info.lib} for ${os.platform()}/${os.arch()}, so mongod ${info.mongod} data cannot be read here`);
    return { ok: false, info };
  }
  const done = (how, res) => {
    const fcv = readFcv(outdir);
    say(`wt: dumped ${how}${fcv ? `; the database's feature compatibility version is ${fcv}` : ''}`);
    return { ok: true, how, fcv, info, log: res.log };
  };
  if (!repair) {
    if (info.readonly) {
      fs.rmSync(outdir, { recursive: true, force: true });
      const r = runReader(info.lib, [], dbpath, outdir);
      if (r.ok) return done('read-only, nothing was written to the source', r);
      say('wt: read-only open refused (unclean shutdown?); replaying the journal on a copy');
    } else say('wt: this WiredTiger has no read-only mode; replaying the journal on a copy');
    fs.rmSync(outdir, { recursive: true, force: true });
    const r = withCopy(dbpath, tmp, copy => runReader(info.lib, ['--allow-recovery'], copy, outdir));
    if (r.ok) return done('from a copy with the journal replayed', r);
    say(`wt: recovery failed: ${r.log.split('\n').slice(-2).join(' | ')}`);
  }
  say('wt: salvaging every table on a copy (what mongod --repair does)');
  fs.rmSync(outdir, { recursive: true, force: true });
  const r = withCopy(dbpath, tmp, copy => runReader(info.lib, ['--repair'], copy, outdir));
  if (r.ok) return done('after salvage on a copy (documents in unreadable pages are lost)', r);
  say(`wt: repair failed: ${r.log.split('\n').slice(-3).join(' | ')}`);
  return { ok: false, info, log: r.log };
}

// Real paths, not resolved ones: run through a symlink (/var -> /private/var on a Mac, or a `wt` link in
// /usr/local/bin) the two names differ and the command line silently did nothing.
const isMain = () => {
  try { return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url)); }
  catch { return false; }
};
if (process.argv[1] && isMain()) {
  const [cmd, ...args] = process.argv.slice(2);
  if (cmd === 'detect' && args[0]) console.log(JSON.stringify(detect(args[0]), null, 2));
  else if (cmd === 'dump' && args.length >= 2) {
    const repair = args.includes('--repair');
    const [dbpath, outdir] = args.filter(a => !a.startsWith('--'));
    process.exit(dump(dbpath, outdir, { repair }).ok ? 0 : 1);
  } else {
    console.error('usage: wt detect <dbpath> | wt dump [--repair] <dbpath> <outdir>');
    process.exit(2);
  }
}
