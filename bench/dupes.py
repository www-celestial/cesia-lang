"""The duplicate files under a folder, as bench/dupes.ce finds them: grouped by size, then by the BLAKE2b-256 of each file
whose size another file has. Symbolic links are left out. Prints each group on a line, its paths sorted and cut by tabs,
the groups sorted.
    python3 bench/dupes.py FOLDER"""
import hashlib
import os
import stat
import sys
from collections import defaultdict


def plain_files(folder):
    """(path, size) of each regular file under folder, at any depth, without following a link."""
    for root, dirs, files in os.walk(folder):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            info = os.lstat(path)
            if stat.S_ISREG(info.st_mode):
                yield path, info.st_size


def blake2b_256(path):
    with open(path, "rb") as f:
        return hashlib.file_digest(f, lambda: hashlib.blake2b(digest_size=32)).digest()


def duplicates(folder):
    by_size = defaultdict(list)
    for path, size in plain_files(folder):
        by_size[size].append(path)
    groups = []
    for paths in by_size.values():
        if len(paths) > 1:
            by_hash = defaultdict(list)
            for path in paths:
                by_hash[blake2b_256(path)].append(path)
            groups += [sorted(g) for g in by_hash.values() if len(g) > 1]
    return sorted(groups)


for group in duplicates(sys.argv[1]):
    print("\t".join(group))
