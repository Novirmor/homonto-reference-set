#!/usr/bin/env python3
"""Print homonto's content pin (sha256:<hex>) for a package directory.

Mirrors internal/remote.CanonicalDigest: files in lexical path order, each as
path | 0x00 | exec-bit byte | 8-byte big-endian length | bytes. Archive
framing, mtimes and ownership do not affect it, so the pin of a directory
equals the pin of its .tar.gz.
"""
import hashlib
import os
import struct
import sys


def digest(root):
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                sys.exit(f"{full}: symlinks are rejected by homonto")
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            files.append((rel, full))
    h = hashlib.sha256()
    for rel, full in sorted(files, key=lambda f: f[0].encode()):
        with open(full, "rb") as f:
            data = f.read()
        h.update(rel.encode())
        h.update(b"\x00")
        h.update(b"\x01" if os.stat(full).st_mode & 0o111 else b"\x00")
        h.update(struct.pack(">Q", len(data)))
        h.update(data)
    return "sha256:" + h.hexdigest()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: digest.py <package-dir>")
    print(digest(sys.argv[1]))
