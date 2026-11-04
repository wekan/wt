// restore-bson.mjs <dump dir> <mongodb url> - inserts a wt-mongo-dump output (one .bson file
// per collection, in <dump dir>/<db>/<collection>.bson) into a server speaking the MongoDB
// wire protocol, the way mongorestore does. Used to stage a raw read for the WeKan importer.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(process.env.WEKAN_ROOT + '/package.json');
const { MongoClient } = require('mongodb');
const BSON = require('bson');

const [dump, url, onlyDb = 'wekan'] = process.argv.slice(2);
const client = await MongoClient.connect(url, { directConnection: true });
const dir = path.join(dump, onlyDb);
for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.bson')).sort()) {
  const coll = file.slice(0, -5);
  if (coll.startsWith('system.')) continue;
  const buf = fs.readFileSync(path.join(dir, file));
  const docs = [];
  for (let off = 0; off < buf.length;) {          // each document starts with its own int32 length
    const size = buf.readInt32LE(off);
    if (size < 5 || off + size > buf.length) throw new Error(`${file}: bad document size ${size} at ${off}`);
    docs.push(BSON.deserialize(buf.subarray(off, off + size), { promoteLongs: false }));
    off += size;
  }
  const c = client.db(onlyDb).collection(coll);
  for (let i = 0; i < docs.length; i += 500) await c.insertMany(docs.slice(i, i + 500), { ordered: false });
  console.log(`restored ${coll}: ${docs.length}`);
}
await client.close();
