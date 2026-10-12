"""Minimal MPQ v0/v1 reader (read-only), enough to pull DBC files out of WoW 1.12 archives."""
import struct, zlib, bz2, sys

def _crypt_table():
    t = [0] * 0x500
    seed = 0x00100001
    for i in range(0x100):
        idx = i
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            t1 = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            t2 = seed & 0xFFFF
            t[idx] = t1 | t2
            idx += 0x100
    return t
CRYPT = _crypt_table()

def hash_string(s, htype):
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\'):
        c = ord(ch)
        seed1 = (CRYPT[(htype << 8) + c] ^ (seed1 + seed2)) & 0xFFFFFFFF
        seed2 = (c + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1

def decrypt(data, key):
    n = len(data) // 4
    vals = struct.unpack('<%dI' % n, data[:n * 4])
    out = []
    seed = 0xEEEEEEEE
    for v in vals:
        seed = (seed + CRYPT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        d = (v ^ ((key + seed) & 0xFFFFFFFF)) & 0xFFFFFFFF
        key = ((((~key & 0xFFFFFFFF) << 0x15) + 0x11111111) & 0xFFFFFFFF) | (key >> 0x0B)
        seed = (d + seed + (seed << 5) + 3) & 0xFFFFFFFF
        out.append(d)
    return struct.pack('<%dI' % n, *out) + data[n * 4:]

# --- PKWARE DCL explode (port of zlib's contrib/blast) ---
_LITLEN = bytes([11, 124, 8, 7, 28, 7, 188, 13, 76, 4, 10, 8, 12, 10, 12, 10, 8, 23, 8,
    9, 7, 6, 7, 8, 7, 6, 55, 8, 23, 24, 12, 11, 7, 9, 11, 12, 6, 7, 22, 5,
    7, 24, 6, 11, 9, 6, 7, 22, 7, 11, 38, 7, 9, 8, 25, 11, 8, 11, 9, 12,
    8, 12, 5, 38, 5, 38, 5, 11, 7, 5, 6, 21, 6, 10, 53, 8, 7, 24, 10, 27,
    44, 253, 253, 253, 252, 252, 252, 13, 12, 45, 12, 45, 12, 61, 12, 45,
    44, 173])
_LENLEN = bytes([2, 35, 36, 53, 38, 23])
_DISTLEN = bytes([2, 20, 53, 230, 247, 151, 248])
_BASE = [3, 2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 24, 40, 72, 136, 264]
_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]

def _construct(rep):
    lengths = []
    for b in rep:
        lengths += [(b & 15)] * ((b >> 4) + 1)
    n = len(lengths)
    count = [0] * 14
    for l in lengths:
        count[l] += 1
    offs = [0] * 14
    for l in range(1, 13):
        offs[l + 1] = offs[l] + count[l]
    symbol = [0] * n
    for s in range(n):
        if lengths[s]:
            symbol[offs[lengths[s]]] = s
            offs[lengths[s]] += 1
    return count, symbol

class _Blast:
    def __init__(self, data):
        self.data, self.pos, self.bitbuf, self.bitcnt = data, 0, 0, 0
    def bits(self, need):
        val, cnt = self.bitbuf, self.bitcnt
        while cnt < need:
            val |= self.data[self.pos] << cnt
            self.pos += 1
            cnt += 8
        self.bitbuf, self.bitcnt = val >> need, cnt - need
        return val & ((1 << need) - 1)
    def decode(self, h):
        count, symbol = h
        code = first = index = 0
        for l in range(1, 14):
            code |= self.bits(1) ^ 1
            c = count[l]
            if code < first + c:
                return symbol[index + (code - first)]
            index += c
            first = (first + c) << 1
            code <<= 1
        raise ValueError('bad code')

_LITCODE = _construct(_LITLEN); _LENCODE = _construct(_LENLEN); _DISTCODE = _construct(_DISTLEN)

def explode(data):
    s = _Blast(data)
    lit = s.bits(8)
    dictbits = s.bits(8)
    out = bytearray()
    while True:
        if s.bits(1):
            sym = s.decode(_LENCODE)
            length = _BASE[sym] + s.bits(_EXTRA[sym])
            if length == 519:
                break
            sym = 2 if length == 2 else dictbits
            dist = (s.decode(_DISTCODE) << sym) + s.bits(sym) + 1
            for _ in range(length):
                out.append(out[-dist])
        else:
            out.append(s.decode(_LITCODE) if lit else s.bits(8))
    return bytes(out)

def decompress_sector(data, expected):
    if len(data) >= expected:
        return data
    mask, body = data[0], data[1:]
    if mask & 0x10:
        body = bz2.decompress(body)
    if mask & 0x08:
        body = explode(body)
    if mask & 0x02:
        body = zlib.decompress(body)
    if mask & ~(0x10 | 0x08 | 0x02):
        raise ValueError('unsupported compression 0x%02x' % mask)
    return body

class MPQ:
    def __init__(self, path):
        self.f = open(path, 'rb')
        off = 0
        while True:
            self.f.seek(off)
            magic = self.f.read(4)
            if magic == b'MPQ\x1a':
                break
            if not magic:
                raise ValueError('no MPQ header')
            off += 512
        self.base = off
        hdr = self.f.read(28)
        (hsize, asize, ver, shift, hoff, boff, hcount, bcount) = struct.unpack('<IIHHIIII', hdr)
        self.sector = 512 << shift
        self.f.seek(off + hoff); ht = decrypt(self.f.read(hcount * 16), hash_string('(hash table)', 3))
        self.f.seek(off + boff); bt = decrypt(self.f.read(bcount * 16), hash_string('(block table)', 3))
        self.hashes = [struct.unpack_from('<IIHHI', ht, i * 16) for i in range(hcount)]
        self.blocks = [struct.unpack_from('<IIII', bt, i * 16) for i in range(bcount)]

    def find(self, name):
        n = len(self.hashes)
        i = hash_string(name, 0) % n
        a, b = hash_string(name, 1), hash_string(name, 2)
        for _ in range(n):
            ha, hb, loc, plat, bidx = self.hashes[i]
            if bidx == 0xFFFFFFFF:
                return None
            if ha == a and hb == b and bidx != 0xFFFFFFFE:
                return bidx
            i = (i + 1) % n
        return None

    def read(self, name):
        bidx = self.find(name)
        if bidx is None:
            return None
        boff, csize, fsize, flags = self.blocks[bidx]
        if not flags & 0x80000000:
            return None
        self.f.seek(self.base + boff)
        raw = self.f.read(csize)
        key = None
        if flags & 0x10000:
            key = hash_string(name.replace('/', '\\').split('\\')[-1], 3)
            if flags & 0x20000:
                key = ((key + boff) ^ fsize) & 0xFFFFFFFF
        compressed = flags & 0x0300
        if flags & 0x01000000 or not compressed:
            if key is not None:
                raw = decrypt(raw, key)
            if flags & 0x0200:
                return decompress_sector(raw, fsize)
            if flags & 0x0100:
                return explode(raw) if csize < fsize else raw
            return raw
        nsect = (fsize + self.sector - 1) // self.sector
        tbl = raw[:(nsect + 1) * 4]
        if key is not None:
            tbl = decrypt(tbl, (key - 1) & 0xFFFFFFFF)
        offs = struct.unpack('<%dI' % (nsect + 1), tbl)
        out = bytearray()
        for s in range(nsect):
            chunk = raw[offs[s]:offs[s + 1]]
            if key is not None:
                chunk = decrypt(chunk, (key + s) & 0xFFFFFFFF)
            expect = min(self.sector, fsize - s * self.sector)
            if flags & 0x0200:
                out += decompress_sector(chunk, expect)
            else:
                out += explode(chunk) if len(chunk) < expect else chunk
        return bytes(out)
