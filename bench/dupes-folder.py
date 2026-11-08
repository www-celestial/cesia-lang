"""A folder of files with known copies, for bench/dupes.ce and bench/dupes.py:
    python3 bench/dupes-folder.py FOLDER N SHAPE [SEED]
N files of random bytes in ten subfolders, one in ten of them a copy of an earlier file under another name. SHAPE photos
gives sizes from 4 KiB to 1 MiB, spread evenly on a log scale, as photos and downloads are; SHAPE same gives every file
64 KiB, so that their sizes tell nothing. The same seed makes the same folder. It prints how many groups of copies there
are, and how many files they hold: what both programs must find."""
import math
import os
import random
import sys


def main():
    folder, n, shape = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    rng = random.Random(int(sys.argv[4]) if len(sys.argv) > 4 else 1)
    os.makedirs(folder)
    originals = []  # (size, seed) of each file that is no copy
    copies = {}
    for k in range(n):
        if originals and rng.random() < 0.1:
            i = rng.randrange(len(originals))
            copies[i] = copies.get(i, 1) + 1
            size, seed = originals[i]
        else:
            if shape == "photos":
                size = int(math.exp(rng.uniform(math.log(4096), math.log(1 << 20))))
            else:
                size = 64 << 10
            seed = rng.getrandbits(64)
            originals.append((size, seed))
        sub = os.path.join(folder, f"d{k % 10}")
        os.makedirs(sub, exist_ok=True)
        with open(os.path.join(sub, f"f{k:05}.bin"), "wb") as f:
            f.write(random.Random(seed).randbytes(size))
    print(f"{len(copies)} groups, {sum(copies.values())} files")


main()
