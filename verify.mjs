// verify.mjs <run dir> - checks what pipeline.sh produced against what seed.js created.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(process.env.WEKAN_ROOT + '/package.json');
const { MongoClient } = require('mongodb');
const run = process.argv[2];
const CH = 261120;
const expected = (chunks, lastLen) => {          // seed.js: byte i of chunk n = (i*31 + n + 7) & 255
  const parts = [];
  for (let n = 0; n < chunks; n++) {
    const len = n === chunks - 1 ? lastLen : CH;
    const b = Buffer.alloc(len);
    for (let i = 0; i < len; i++) b[i] = (i * 31 + n + 7) & 255;
    parts.push(b);
  }
  return Buffer.concat(parts);
};
let bad = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' - ' + detail : ''}`); if (!ok) bad++; };
const client = await MongoClient.connect('mongodb://127.0.0.1:27071/?directConnection=true');
const d = client.db('wekan');
check('cards: 20000', await d.collection('cards').countDocuments() === 20000);
const card = await d.collection('cards').findOne({ _id: 'c1000' });
check('a 20000 character field survives', card && card.big.length === 20000);
const board = await d.collection('boards').findOne({ _id: 'b1' });
check('text, nested array and date survive', board && board.title === 'Board ä ö €' && board.members[0].userId === 'u1' && +board.when === 1700000000123);
const user = await d.collection('users').findOne({ _id: 'u1' });
check('int64 beyond 2^53 survives', user && String(user.profile.n) === '9007199254740993', String(user && user.profile.n));
const files = path.join(run, 'files', 'files');
const att = fs.readdirSync(path.join(files, 'attachments'));
const av = fs.readdirSync(path.join(files, 'avatars'));
check('CollectionFS attachment bytes identical', att.length === 1 && Buffer.compare(fs.readFileSync(path.join(files, 'attachments', att[0])), expected(4, 1000)) === 0, att.join());
check('CollectionFS avatar bytes identical', av.length === 1 && Buffer.compare(fs.readFileSync(path.join(files, 'avatars', av[0])), expected(1, 500)) === 0, av.join());
await client.close();
process.exit(bad ? 1 : 0);
