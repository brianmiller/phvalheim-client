#!/usr/bin/env python3
"""Read an MSI table straight out of the OLE compound document.

msiinfo export renders a NULL cell and an empty-string cell identically (both a
blank field).  They are not the same thing to Windows Installer: a NULL means
"no value", a non-zero string ref pointing at "" means "the string whose name is
the empty string".  For Control_Next that is the difference between "not in the
tab order" and error 2814, "names a nonexistent control".

This prints the raw string-pool reference for every cell, so the two are
distinguishable.

Usage: msi_rawtable.py <file.msi> <TableName> [FilterCol=Value]
"""
import sys
import struct
import olefile

B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._"

# MSI column type bits (libmsi / wine msipriv.h)
MSITYPE_STRING = 0x0800
MSITYPE_NULLABLE = 0x1000
MSITYPE_KEY = 0x2000


def demangle(name):
    """MSI mangles stream names into the 0x3800-0x484F private-use range."""
    out = []
    for ch in name:
        c = ord(ch)
        if 0x3800 <= c < 0x4800:
            c -= 0x3800
            out.append(B64[c & 0x3F])
            out.append(B64[(c >> 6) & 0x3F])
        elif c == 0x4840:
            # table-stream marker, not part of the name
            continue
        elif 0x4800 <= c < 0x4840:
            out.append(B64[c - 0x4800])
        else:
            out.append(ch)
    return "".join(out)


class MsiDb:
    def __init__(self, path):
        self.ole = olefile.OleFileIO(path)
        self.streams = {}
        for entry in self.ole.listdir():
            raw = entry[-1]
            self.streams[demangle(raw)] = entry
        self._load_strings()
        self._load_schema()

    def _read(self, logical):
        return self.ole.openstream(self.streams[logical]).read()

    def _load_strings(self):
        pool = self._read("_StringPool")
        data = self._read("_StringData")
        n = len(pool) // 4
        codepage = struct.unpack_from("<H", pool, 0)[0]
        flags = struct.unpack_from("<H", pool, 2)[0]
        # high bit of the second word => string refs are 3 bytes wide, not 2
        self.long_refs = bool(flags & 0x8000)
        self.codepage = codepage or 1252
        enc = "utf-8" if self.codepage == 65001 else "cp%d" % self.codepage

        self.strings = {0: None}  # id 0 is NULL, always
        self.raw_len = {0: None}
        offset = 0
        i = 1
        while i < n:
            ln, refs = struct.unpack_from("<HH", pool, i * 4)
            if ln == 0 and refs != 0 and (i + 1) < n:
                # large string: real length lives in the following pair
                lo, hi = struct.unpack_from("<HH", pool, (i + 1) * 4)
                ln = (hi << 16) | lo
                i += 1
            chunk = data[offset:offset + ln]
            offset += ln
            try:
                self.strings[i] = chunk.decode(enc, "replace")
            except LookupError:
                self.strings[i] = chunk.decode("cp1252", "replace")
            self.raw_len[i] = ln
            i += 1

    def _load_schema(self):
        cols = self._raw_rows("_Columns", [("Table", MSITYPE_STRING),
                                           ("Number", 2),
                                           ("Name", MSITYPE_STRING),
                                           ("Type", 2)])
        self.schema = {}
        for table_ref, number, name_ref, ctype in cols:
            # _raw_rows hands back raw string-pool refs; resolve them here
            table = self.strings.get(table_ref)
            name = self.strings.get(name_ref)
            if table is None or name is None:
                continue
            self.schema.setdefault(table, []).append((number, name, ctype))
        for t in self.schema:
            self.schema[t].sort()

    def _refwidth(self):
        return 3 if self.long_refs else 2

    def _cellwidth(self, ctype):
        if ctype & MSITYPE_STRING:
            return self._refwidth()
        size = ctype & 0xFF
        return 4 if size == 4 else 2

    def _raw_rows(self, logical, coldefs):
        """coldefs: list of (name, type). Returns list of decoded tuples."""
        blob = self._read(logical)
        widths = [self._cellwidth(t) for _, t in coldefs]
        rowsize = sum(widths)
        if rowsize == 0:
            return []
        nrows = len(blob) // rowsize
        # MSI stores tables COLUMN-major
        offsets = []
        pos = 0
        for w in widths:
            offsets.append(pos)
            pos += w * nrows
        rows = []
        for r in range(nrows):
            row = []
            for ci, (_, ctype) in enumerate(coldefs):
                w = widths[ci]
                at = offsets[ci] + r * w
                if w == 2:
                    v = struct.unpack_from("<H", blob, at)[0]
                elif w == 3:
                    v = struct.unpack_from("<H", blob, at)[0] | (blob[at + 2] << 16)
                else:
                    v = struct.unpack_from("<I", blob, at)[0]
                if ctype & MSITYPE_STRING:
                    row.append(v)  # raw string ref, resolved by caller
                else:
                    # integers are stored biased by the sign bit
                    if w == 4:
                        row.append(v ^ 0x80000000 if v else None)
                    else:
                        row.append((v ^ 0x8000) if v else None)
            rows.append(tuple(row))
        return rows

    def table(self, name):
        """Yield dicts of {col: (rawref_or_int, resolved)} for a real table."""
        defs = [(n, t) for _, n, t in self.schema[name]]
        rows = self._raw_rows(name, defs)
        for row in rows:
            out = {}
            for (cname, ctype), val in zip(defs, row):
                if ctype & MSITYPE_STRING:
                    out[cname] = (val, self.strings.get(val, "<BAD REF %d>" % val))
                else:
                    out[cname] = (val, val)
            yield out


def describe(ref, value):
    if ref == 0:
        return "NULL (ref=0)"
    if value == "":
        return "EMPTY STRING (ref=%d)  <-- 2814 candidate" % ref
    return "%r (ref=%d)" % (value, ref)


def main():
    path, table = sys.argv[1], sys.argv[2]
    filt = None
    if len(sys.argv) > 3:
        k, v = sys.argv[3].split("=", 1)
        filt = (k, v)

    db = MsiDb(path)
    print("codepage=%d long_string_refs=%s pool_entries=%d"
          % (db.codepage, db.long_refs, len(db.strings)))
    print()

    empties = 0
    nulls = 0
    for row in db.table(table):
        if filt and row[filt[0]][1] != filt[1]:
            continue
        name = row.get("Control", row.get("Dialog", ("", "?")))[1]
        nxt = row.get("Control_Next")
        if nxt is None:
            print(name)
            continue
        ref, val = nxt
        if ref == 0:
            nulls += 1
        elif val == "":
            empties += 1
        print("  %-20s type=%-16s next=%s"
              % (name, row["Type"][1], describe(ref, val)))

    print()
    print("Control_Next: %d NULL, %d empty-string" % (nulls, empties))


if __name__ == "__main__":
    main()
