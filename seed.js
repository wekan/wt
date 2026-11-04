// Runs inside the mongod container's shell (mongo or mongosh). Creates the same data in
// every MongoDB version: text collections of several sizes, nested values and dates, and
// BOTH GridFS layouts WeKan has used - CollectionFS (cfs_gridfs.<bucket>.files/chunks, old
// WeKan) and Meteor-Files-in-GridFS (<bucket>.files/chunks). File bytes are a repeatable
// pattern so the reader's output can be compared byte for byte.
var d = db.getSiblingDB('wekan');
var HAS_MANY = typeof d.users.insertMany === 'function';
function ins(c, doc) { return HAS_MANY ? c.insertOne(doc) : c.insert(doc); }
function insMany(c, docs) { return HAS_MANY ? c.insertMany(docs) : docs.forEach(function (x) { c.insert(x); }); }
function pattern(len, seed) {            // base64 of `len` bytes
  var s = '';
  for (var i = 0; i < len; i++) s += String.fromCharCode((i * 31 + seed) & 255);
  return s;
}
function rep(c, n) { var r = ''; for (var i = 0; i < n; i++) r += c; return r; }
var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function b64(s) {                         // btoa for shells that have none (mongo 3.x - 5.0)
  var o = '', i = 0;
  for (; i + 2 < s.length; i += 3) {
    var n = (s.charCodeAt(i) << 16) | (s.charCodeAt(i + 1) << 8) | s.charCodeAt(i + 2);
    o += B64.charAt(n >> 18 & 63) + B64.charAt(n >> 12 & 63) + B64.charAt(n >> 6 & 63) + B64.charAt(n & 63);
  }
  if (s.length - i === 1) { var a = s.charCodeAt(i) << 16; o += B64.charAt(a >> 18 & 63) + B64.charAt(a >> 12 & 63) + '=='; }
  else if (s.length - i === 2) { var b = (s.charCodeAt(i) << 16) | (s.charCodeAt(i + 1) << 8); o += B64.charAt(b >> 18 & 63) + B64.charAt(b >> 12 & 63) + B64.charAt(b >> 6 & 63) + '='; }
  return o;
}
ins(d.users, { _id: 'u1', username: 'xet7', emails: [{ address: 'x@example.com', verified: true }], createdAt: new Date(1700000000000), profile: { language: 'fi', n: NumberLong('9007199254740993') } });
ins(d.boards, { _id: 'b1', title: 'Board ä ö €', slug: 'board', members: [{ userId: 'u1', isAdmin: true }], when: new Date(1700000000123) });
var many = [];
for (var i = 0; i < 20000; i++) many.push({ _id: 'c' + i, title: 'Card ' + i, boardId: 'b1', sort: i, tags: ['a', 'b'], big: i % 1000 === 0 ? rep('x', 20000) : 'y' });
insMany(d.cards, many);
(d.cards.createIndex || d.cards.ensureIndex).call(d.cards, { boardId: 1, sort: 1 });
// CollectionFS GridFS: 3 chunks of 255 KiB + a short one
var CH = 261120;
function gridfs(bucket, fileId, name, chunks, lastLen, extraFile) {
  var total = (chunks - 1) * CH + lastLen;
  var f = { _id: fileId, length: total, chunkSize: CH, uploadDate: new Date(1700000000999), md5: 'x', filename: name };
  for (var k in extraFile) f[k] = extraFile[k];
  ins(d.getCollection(bucket + '.files'), f);
  for (var n = 0; n < chunks; n++) {
    var len = n === chunks - 1 ? lastLen : CH;
    ins(d.getCollection(bucket + '.chunks'), { files_id: fileId, n: n, data: BinData(0, b64(pattern(len, n + 7))) });
  }
}
gridfs('cfs_gridfs.attachments', ObjectId('650000000000000000000001'), 'cfs-a.bin', 4, 1000, {});
gridfs('cfs_gridfs.avatars', ObjectId('650000000000000000000002'), 'cfs-av.png', 1, 500, {});
gridfs('attachments', ObjectId('650000000000000000000003'), 'mf-a.bin', 3, 777, {});
var frec = function (copies) { return { _id: 'fr1', original: { name: 'cfs-a.bin', type: 'application/octet-stream', size: 3 * CH + 1000 }, copies: copies, boardId: 'b1', cardId: 'c1', userId: 'u1' }; };
var dotted = {}; dotted['cfs_gridfs.attachments'] = { key: ObjectId('650000000000000000000001'), name: 'cfs-a.bin' };
try { ins(d.getCollection('cfs.attachments.filerecord'), frec(dotted)); }
catch (e) {   // MongoDB before 3.6 refuses a dot in a field name: the legacy layout then
  ins(d.getCollection('cfs.attachments.filerecord'), frec({ gridfs: { key: ObjectId('650000000000000000000001'), name: 'cfs-a.bin' } }));
}
print('seeded ' + d.cards.count() + ' cards');
