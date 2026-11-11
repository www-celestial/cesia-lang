# Solving a real problem

In this chapter you solve a problem that almost everyone with a computer has: a folder of downloads or photos full of
copies. `photo.jpg` and `photo (1).jpg`, a file saved twice, a backup copied back in. The question is short: *which
files in this folder are duplicates?*

You solve it the way research solves a problem, in seven steps, and each step names its method and where it comes from:

1. say exactly what *solved* means, as a property a program can check;
2. measure before changing anything;
3. make a guess that an experiment can prove wrong, and run the experiment;
4. find what is already known;
5. write the smallest solution;
6. prove that it is solved: with tests, with a bound, with times beside Python;
7. say what is left.

Every block of Cesia on this page ran when the book was built. The times come from runs on one machine, with the method
written beside them. The papers and documents are in [References](references.md#solving-a-problem).

## 1. The problem, stated precisely

George Pólya's *How to Solve It* (1945) begins every problem with the same questions: what is the unknown, what are the
data, what is the condition? Here the data are a folder; the unknown is the groups of its files that are copies of each
other; the condition is what makes two files copies. The [Heilmeier catechism](glossary.md#heilmeier-catechism), the
questions DARPA asks of a research project, adds the one that matters most at the end: what is the exam that tells
success?

Two files are *duplicates* when they hold the same bytes, whatever their names, dates or folders. The answer is a list of
groups of paths. It is right when it has two properties, and each is a check that a program can run:

- *complete*: two files with the same bytes are in the same group;
- *sound*: two files in the same group have the same bytes, and each group holds two files or more.

"Holds the same bytes" is an [equivalence relation](glossary.md#equivalence-relation): each file holds its own bytes; if
`a` holds the bytes of `b`, `b` holds those of `a`; and a copy of a copy is a copy. Such a relation splits the files into
*classes*, the sets of files that are copies of each other, and the answer is the classes of two files or more.

Out of scope: photos that look alike but differ in their bytes, as a photo and its smaller version, which is another
problem, *near* duplicates; deleting anything, since the program only tells; and the files outside the folder.

A folder to work on. A *path* names a file from a folder, as `downloads/photos/IMG_0001.jpg`:

```cesia allow=read,write
use std/sys
sys.Mkdir("downloads/photos")
sys.Write("downloads/cat.jpg", "meow meow")
sys.Write("downloads/cat (1).jpg", "meow meow")
sys.Write("downloads/photos/IMG_0001.jpg", "meow meow")
sys.Write("downloads/notes.txt", "buy bread")
sys.Write("downloads/notes copy.txt", "buy bread")
sys.Write("downloads/todo.txt", "buy milk!")
sys.Write("downloads/report.pdf", "%PDF-1.7 report")
sys.Walk("downloads") -->
```

The right answer has two groups: `cat.jpg`, `cat (1).jpg` and `photos/IMG_0001.jpg`, then `notes.txt` and
`notes copy.txt`. `todo.txt` has 9 bytes, as `notes.txt` and `cat.jpg` have, but not their bytes: it belongs to no group,
and neither does `report.pdf`.

## 2. Measure before changing anything

The first way that comes to mind is the definition itself: compare each file with each one after it, byte by byte.
[sys.Walk] gives every path under a folder, [sys.Stat] tells a file from a folder or a link, and [sys.Read] gives the bytes
of a file as a text:

```cesia
use std/list
use std/value
use std/result

defn plainFiles(folder)
  (** Each regular file under a folder, at any depth, as {Path, Size}: no folder, no link, no device. *)
  out = []
  for p in sys.Walk(folder)?
    info = sys.Stat(p)?
    if info.IsFile and not info.IsLink
      out = list.Append({Path: p, Size: info.Size}, out)
    end
  end
  result.Ok(out)
end

sorted(groups) = list.SortBy(g -> g[1], [list.Sort(g) for g in groups])   (** Each group in order, then the groups by their first path. *)

defn naive(folder, read = sys.Read)
  (** The groups of copies under a folder, the first way that comes to mind: each file against each one after it, byte
      by byte, each read with read. *)
  paths = [f.Path for f in plainFiles(folder)?]
  n = value.Len(paths)
  taken = list.Fill(false, n)
  groups = []
  for i in 1..n
    if not taken[i]
      group = [paths[i]]
      for j in (i + 1)..n
        if not taken[j] and read(paths[i])? == read(paths[j])?
          group = list.Append(paths[j], group)
          taken[j] = true
        end
      end
      if value.Len(group) > 1
        groups = list.Append(group, groups)
      end
    end
  end
  result.Ok(sorted(groups))
end

naive("downloads") -->
```

It is right, since it does what the definition says, and it will serve as the sure answer that a faster way is checked
against. Its cost: $n$ files make $n(n - 1)/2$ pairs, and each pair reads its two files, so a folder without copies is read
$n(n - 1)$ times in all, each file $n - 1$ times. That cost is *quadratic*: twice the files, four times the reads. In the
[big O notation](glossary.md#big-o-notation), it is $O(n^2)$.

### How it was measured

How long is that, in seconds? A guess is no measure, so the first time measured is the [baseline](glossary.md#baseline),
the one every change is compared with. Every time of this chapter is measured the same way, as Raj Jain's *The Art of
Computer Systems Performance Analysis* (1991) teaches:

- The same task for every program: the same folder, the same answer, which is checked at each run against the first run
  of the first program.
- Each time is the whole process, from its start to its end: what a user waits for.
- 11 runs of each program, the programs taking turns, and their order turned at each round, so that a slower minute of the
  machine falls on all of them. Andy Georges, Dries Buytaert and Lieven Eeckhout showed in 2007 that a single run, or the
  best of a few, can make the wrong program look faster; Tomas Kalibera and Richard Jones, in 2013, that the runs must be
  repeated at the level where the noise is, here the process.
- The *median* of the 11 runs, the middle one, and its 95% [confidence interval](glossary.md#confidence-interval), from
  the [order statistics](glossary.md#order-statistic): the times put in order, the 2nd and the 10th. That interval holds
  the true median with a probability of at least 95%, whatever the shape of the times, by the theorem 2.1 of Jean-Yves Le
  Boudec's *Performance Evaluation of Computer and Communication Systems* (2010). It needs no guess that the times follow
  a bell curve, which times rarely do.
- The peak memory is the largest resident size that the system counts for the process. It starts at the 13 MB of the
  program that measures, which the system counts for the process it starts, so a program that prints a number shows
  13.2 MB in Cesia as in Python: below 16 MB, a peak means little more than that.

The probability comes from counting: the true median is out of the interval when at least 10 of the 11 runs fall on one
side of it, and each run falls on either side with a chance of one half:

```cesia
defn choose(n, k)
  (** How many ways there are to pick k things among n. *)
  out = 1
  for i in 1..k
    out = out * (n - k + i) / i
  end
  out
end

defn coverage(n, j)
  (** The probability that the true median lies between the j-th and the (n + 1 - j)-th of n times in order. *)
  1 - 2 * list.Sum([choose(n, i) for i in 0..j - 1]) / 2 ^ n
end

coverage(11, 2) -->
coverage(11, 3) -->
```

The 2nd and the 10th of 11 hold it with 98.8%; the 3rd and the 9th only with 93.5%, too little for 95%.

The machine is the one of [Speed](speed.md#beside-the-giants): an Intel Core i7-4720HQ of 2015, 8 logical cores,
11 GB of memory, Linux, a SATA solid-state disk with btrfs; Cesia in its build from this repository, Python 3.14.9.
The folders come from `bench/dupes-folder.py`, with the seed 1: files of random bytes, from 4 KiB to 1 MiB, spread
evenly on a log scale, as photos and downloads are, in ten folders; one file in ten is a copy of an earlier one.

### The baseline

Medians of 11 runs, and their 95% interval, in milliseconds; the folders of photos, as the cache holds them after a first
read (a *warm* [page cache](glossary.md#page-cache)), measured on 2026-11-08, load 1.0:

| Files | Their bytes | Pairs | `naive` | 95% interval |
|---:|---:|---:|---:|---:|
| 100 | 24.4 MB | 4,950 | 1,107 | 1,094 to 1,126 |
| 200 | 41.9 MB | 19,900 | 3,204 | 3,172 to 3,391 |
| 400 | 80.7 MB | 79,800 | 16,087 | 15,989 to 16,231 |

Twice the files, three to five times the time. It is not exactly four because the folders differ in the mean size of
their files: each file is read $n - 1$ times, so the naive way reads about 2.4, 8.3 and 32.2 GB, at 2.0 to 2.6 GB a
second. At that pace a folder of 10,000 photos would take 625 times the 16 seconds of 400, about three hours.

## 3. A hypothesis that can be proved wrong

A *hypothesis* is worth something when an experiment can prove it wrong: it is
[falsifiable](glossary.md#falsifiable), in the word of Karl Popper's *The Logic of Scientific Discovery* (1934). "The
program is slow" is none. "The time goes into reading the same files again and again" is one, since it predicts what an
experiment will show: read each file once, keep it in memory, compare the same pairs in the same order, and nearly all
of the time must go, since each file is then read once instead of $n - 1$ times. If the time went instead into comparing
bytes, walking the folder or starting Cesia, it would hardly move.

An experiment changes one thing only. `naive` takes its way of reading a file as a parameter, `read`, which is
[sys.Read] unless told otherwise; `readOnce` gives another way, which reads every file once at the start and then serves
it from memory:

```cesia
defn readOnce(folder)
  (** A way to read the files of a folder from memory, where each was read once at the start. *)
  kept = {}
  for f in plainFiles(folder)?
    kept[f.Path] = sys.Read(f.Path)?
  end
  result.Ok(p -> result.Ok(kept[p]))
end

naive("downloads", read = result.Unwrap(readOnce("downloads"))) --> naive("downloads")
```

The same folders, the same method:

| Files | `naive` | `naive`, each file read once | Its peak memory |
|---:|---:|---:|---:|
| 100 | 1,107 (1,094 to 1,126) | 32.3 (31.6 to 32.5) | 44 MB |
| 200 | 3,204 (3,172 to 3,391) | 54.2 (53.1 to 59.4) | 68 MB |
| 400 | 16,087 (15,989 to 16,231) | 112.6 (111.0 to 113.8) | 131 MB |

The prediction held. At 400 files the same comparisons, in the same order, take 113 ms instead of 16.1 s: 99.3% of the
time of the naive way went into reading the same files again. The hypothesis could have failed, and didn't, so it
stands. Reading once is no solution, though: it holds the whole folder in memory at once, 131 MB for 81 MB of files,
and it still compares every pair.

### A shortcut, proved wrong

A second hypothesis comes at once, and it would save every read: *files of one size are copies*. [sys.Stat] gives the
size without reading a byte, and [list.Group] puts together the elements that share a key:

```cesia
defn bySize(folder)
  (** The shortcut: files of one size taken as copies, without reading them. *)
  groups = [[f.Path for f in g.Values] for g in list.Group(it.Size, plainFiles(folder)?) if value.Len(g.Values) > 1]
  result.Ok(sorted(groups))
end

bySize("downloads") -->
```

The folder of this page proves it wrong already: `todo.txt` lands among the photos of a cat. On a folder that one doesn't
know, a [property-based test](glossary.md#property-based-testing) finds such a case by itself: it makes folders at random,
with copies it knows of, and checks the answer on each. The test of [step 6](#properties-over-generated-folders), with
the seed 1, fails on the shortcut at its 4th folder, then [shrinks](glossary.md#shrinking) that folder as long as it
still fails, and gives the smallest it finds: two files of two bytes, `aa` and `ba`. Andreas Zeller and Ralf Hildebrandt
made this idea systematic in 2002, as [delta debugging](glossary.md#delta-debugging): a failing input, made smaller step
by step, shows the cause of the failure. Here the cause is plain: one size, two texts.

So the size can't decide alone. But it can rule out: two files of different sizes are never copies, and asking for a size
reads nothing.

## 4. Research

This kind of problem is old, and its answer is known. Three results make it.

**A cheap key first.** A *key* is a value computed from a file, and a key that depends only on the bytes never parts two
copies: equal bytes give equal keys. Grouping by such a key keeps every group of copies whole, so the answer stays
complete; it can only put too much in a group. A cheap key, the size, splits the files first; a dearer one, computed only
in the groups of two files or more, splits those again. This is a [partition refinement](glossary.md#partition-refinement):
each step splits the groups of the step before, and none joins them again. A file whose size no other file has is never
read.

**A cryptographic hash.** The dearer key is a [hash function](glossary.md#hash-function): a digest of a fixed length,
computed from all the bytes of a file. BLAKE2b, by Jean-Philippe Aumasson, Samuel Neves, Zooko Wilcox-O'Hearn and
Christian Winnerlein (2013), is a cryptographic one, as fast as MD5 and built so that nobody knows how to find two texts of
the same digest. Its 256-bit form, BLAKE2b-256, has a *collision security* of $2^{128}$, by RFC 7693: finding two texts with
one digest takes about $2^{128}$ tries of the hash, the generic attack. [cesia.Fingerprint] gives that digest, the one
`cesia.lock` keeps for each file. It needs no permission, where [crypto.Blake2b] calls libsodium; both give the same 32
bytes.

**The birthday bound.** Two different files of the same size may still get the same digest, by chance: a *collision*.
How likely is that? For $k$ different files, there are $k(k - 1)/2$ pairs. If the digests behave as random draws among the
$N = 2^{256}$ possible ones, each pair collides with the probability $1/N$, and the probability that at least one pair does is
at most the sum over the pairs, by the [union bound](glossary.md#union-bound):

$$
P(\text{some collision among } k \text{ files}) \le \frac{k(k - 1)}{2} \times 2^{-256}
$$

This is the [birthday bound](glossary.md#birthday-bound), named after the classic surprise that 23 people are enough for
two of them to share a birthday more often than not; the *Handbook of Applied Cryptography* of Menezes, van Oorschot and
Vanstone (1996) gives the exact probability, its Fact 2.27. [Step 6](#the-bound-worked-out) works the number out.

### How the established tools do it

The tools that people use for this problem do the same steps, by their documentation:

- **fdupes**: "Such files are found by comparing file sizes and MD5 signatures, followed by a byte-by-byte comparison",
  says its manual page.
- **jdupes**, derived from fdupes 1.51: files of different sizes are not compared; the first 4 KiB are hashed and
  compared, then whole files, with xxHash; "finally, actual file data is compared to verify that they are duplicates",
  says its README. Its `-Q` skips that last step, with a warning that it "may delete non-duplicates".

Both compare the bytes at the end, and for a reason: MD5 is broken, since Xiaoyun Wang and Hongbo Yu showed in 2005 how
to make two texts of one MD5, and xxHash is no cryptographic hash, made for speed, with 64 bits in jdupes (XXH64, in its
source). With 64 bits, the bound for a million files is $2.7 \times 10^{-8}$, and anyone can make two files of one xxHash on
purpose. With BLAKE2b-256, the bound is $2^{192}$ times smaller, about $6 \times 10^{57}$ times, and making two files of one digest
takes the $2^{128}$ tries of the generic attack. So this chapter takes the other choice: no comparison of bytes, one read of
each file whose size another file has, and the bound as the proof that no group is wrong.

What doesn't apply: jdupes hashes the first 4 KiB of a file before the whole file, which saves reading most of a large
file that differs early. [sys.Read] reads a file whole, so that step would read as much as the full hash.

## 5. The smallest solution

The size, then the digest, among the files of one size:

```cesia
use std/cesia

defn Duplicates(folder)
  (** The groups of files under a folder that hold the same bytes, two or more to a group: by size first, then, among
      the files of one size, by their BLAKE2b-256. *)
  groups = []
  for same in list.Group(it.Size, plainFiles(folder)?)
    if value.Len(same.Values) > 1
      hashed = []
      for f in same.Values
        hashed = list.Append({Path: f.Path, Hash: cesia.Fingerprint(sys.Read(f.Path)?)}, hashed)
      end
      for g in list.Group(it.Hash, hashed)
        if value.Len(g.Values) > 1
          groups = list.Append([h.Path for h in g.Values], groups)
        end
      end
    end
  end
  result.Ok(sorted(groups))
end

Duplicates("downloads") -->
Duplicates("downloads") --> naive("downloads")
```

Nineteen lines. Each file is read at most once, and only if another file has its size: here six of the seven, since six
have 9 bytes. In a folder of photos, whose sizes rarely meet, it reads little more than the copies.

## 6. The proof that it is solved

### A test that fails before and passes after

The folder that the shrinking found becomes a test that stays: it fails on the shortcut, the "before", and passes on
`Duplicates`, the "after". `finds` makes a folder from a list of texts, one file per text, and checks a way of finding
copies against the groups it knows:

```cesia
(* dupes.test.ce *)
use std/test
use std/gen
use std/math

defn written(contents, dir)
  (** The folder dir, emptied, then with one file per text, spread over three folders. *)
  sys.Mkdir(dir)?
  for p in sys.Walk(dir)?
    sys.Remove(p)?
  end
  for k in 1..value.Len(contents)
    sys.Mkdir("$dir/d$(math.Mod(k, 3))")?
    sys.Write("$dir/d$(math.Mod(k, 3))/f$k", contents[k])?
  end
  result.Ok(dir)
end

defn copies(contents, dir)
  (** The groups that the folder of written must give, known from the texts it was made of. *)
  at(k) = "$dir/d$(math.Mod(k, 3))/f$k"
  sorted([[at(k) for k in g.Values] for g in list.Group(k -> contents[k], 1..value.Len(contents)) if value.Len(g.Values) > 1])
end

defn finds(way, contents, dir)
  (** Does a way of finding copies give the groups of a folder made of these texts? *)
  written(contents, dir)?
  value.Equal(way(dir)?, copies(contents, dir))
end

folders = gen.List(gen.Text(max = 3, chars = "ab"), max = 12)   (** The texts of a folder: short, so that many have one size. *)

isSizeEnough() = test.ForAll(cs -> finds(bySize, cs, "$(test.Temp())/case"), folders)
isNaiveRight() = test.ForAll(cs -> finds(naive, cs, "$(test.Temp())/case"), folders)
isDuplicatesRight() = test.ForAll(cs -> finds(Duplicates, cs, "$(test.Temp())/case"), folders)
isOneSizeTwoTexts() = finds(Duplicates, ["aa", "ba"], "$(test.Temp())/case")

finds(bySize, ["aa", "ba"], "case") -->
finds(Duplicates, ["aa", "ba"], "case") -->
finds(naive, ["aa", "ba"], "case") -->
```

### Properties over generated folders

The four functions whose names start with `is` are the tests of `dupes.test.ce`: this file, after the functions of the
steps before. Three of them are properties: [test.ForAll] makes 100 folders with the generator `folders`, each a list of up
to 12 short texts of `a` and `b`, so that many texts have one size and many are equal, the empty text too; then it checks
the way on each, against the groups known from the texts. That is QuickCheck's method, by Koen Claessen and John Hughes
(2000), as the chapter [Tests](tests.md#properties) shows. `cesia test` runs them, and the repository of Cesia runs this
file in each of its checks, on both paths of the engine:

```text
$ cesia test --seed 1 dupes.test.ce
dupes.test.ce:102: isSizeEnough failed at case 4 of 100, shrunk from 17 draws to 13:
  cs = ["aa", "ba"]
  finds(bySize, cs, "$(test.Temp())/case")
  | bySize = function bySize
  | cs = ["aa", "ba"]
  | test.Temp() = "/tmp/cesia-test-3563511-9b43ea/1-isSizeEnough"
  saved, tried first next time; these cases again: cesia test dupes.test.ce --seed 1
  Its Temp folder is kept: /tmp/cesia-test-3563511-9b43ea/1-isSizeEnough
3 passed, 1 failed, seed 1
```

The shortcut fails, as it should: that failure is the proof that the test can see the mistake. With the seeds 1 to 8 it
fails each time, at the 4th to the 14th folder, and shrinks each time to two files of one size: `a` and `b`, in either
order, `aa` and `ba`, or `aaa` and `aba`. The first way and `Duplicates` hold on all 100 folders of each of the seeds 1 to
50, 5,000 folders each, and on the seeds 1 to 20 with `--no-spec` too, the engine without its versions by type. The test
also found a mistake of its own as it was written: an empty list of texts made no folder at all, and [sys.Walk] failed on
it, which is why `written` makes the folder first.

### The bound worked out

```cesia
bound(k, bits) = k * (k - 1) / 2 / 2.0 ^ bits   (** The birthday bound, for k different files and a digest of bits bits. *)
bound(1000000, 256) -->
bound(1000000, 64) -->
bound(1000000000, 256) -->
bound(1000000, 256) * 1e9 * 3600 * 24 * 365.25 * 1000 -->
```

For a million different files of one size, the chance that BLAKE2b-256 puts two of them in one group is at most
$4.3 \times 10^{-66}$; for a billion, $4.3 \times 10^{-60}$. Run a billion times a second for a thousand years, on a million files each
time, the chance that any run ever goes wrong is at most the sum over the runs, the union bound again: $1.4 \times 10^{-46}$.
The bound rests on one assumption: that the digests of files that nobody made against BLAKE2b behave as random draws.
Against files made on purpose, the guarantee is the collision security of $2^{128}$.

### Speed, before and after, beside Python

`bench/dupes.py` does the same in Python, the way a Python programmer writes it: `os.walk`, then a group by size, then
`hashlib.file_digest` with BLAKE2b of 32 bytes, which reads each file in pieces. Its output is checked to be the same as
Cesia's, line for line. The Cesia side is `bench/dupes.ce`, which holds the functions of this chapter:

```text
(** The ways of the chapter "Solving a real problem" of the book, timed on a folder:
      cesia run --allow read bench/dupes.ce naive|memory|duplicates FOLDER
    Each prints the groups of copies, one on a line, its paths cut by tabs, as bench/dupes.py does. memory is naive with
    each file read once, then kept in memory. *)
use std/sys
use std/io
use std/text
use std/list
use std/value
use std/result
use std/cesia

defn main()
  way = sys.Args[1]
  folder = sys.Args[2]
  groups = if way == "naive"
    naive(folder)?
  else if way == "memory"
    naive(folder, read = readOnce(folder)?)?
  else
    Duplicates(folder)?
  end
  for g in groups
    io.Print(text.Join("\t", g))
  end
  result.Ok(missing)
end

(* plainFiles, sorted, naive, readOnce and Duplicates, as above *)

result.Unwrap(main())
```

Medians of 11 runs and their 95% interval, in milliseconds, with a warm cache; in bold, the faster of `Duplicates` and
Python, where their intervals don't meet and they differ by more than 2%:

| Folder of photos | `naive`, before | `Duplicates`, after | Python |
|---:|---:|---:|---:|
| 100 files | 1,107 (1,094 to 1,126) | **17.2** (17.0 to 17.4) | 27.4 (26.8 to 27.9) |
| 200 files | 3,204 (3,172 to 3,391) | **25.6** (25.0 to 26.0) | 32.6 (31.8 to 33.1) |
| 400 files | 16,087 (15,989 to 16,231) | 40.3 (39.8 to 40.6) | 41.0 (40.7 to 41.5) |
| 1,000 files, 192 MB | | 94.3 (93.6 to 97.1) | **70.4** (69.8 to 70.9) |

From 16.1 s to 40 ms at 400 files: 400 times faster, and the gap grows with the folder, since one cost is $O(n^2)$ and the
other about $O(n)$. `Duplicates` reads 59 of the 400 files there, 13.2 MB of 80.7: the copies, since no two different
photos of these folders had one size. Its peak memory, as the system counts it, stays under 16 MB, as Python's does:
the largest file it holds is 1 MiB.

The worst case for the size, and a cold cache. On 1,000 files of exactly 64 KiB, the size tells nothing and every file is
hashed. *Cold* means that before each run, every file of the folder is dropped from the page cache (with
`posix_fadvise`, and `fincore` shows that none of their pages is left), so that its bytes come from the disk:

| Folder | Cache | `Duplicates` | Python |
|---|---|---:|---:|
| 1,000 photos | cold | 341 (326 to 371) | 319 (295 to 335) |
| 1,000 files of 64 KiB | warm | 161.5 (161.0 to 166.3) | **129.2** (128.3 to 131.0) |
| 1,000 files of 64 KiB | cold | 1,126 (1,045 to 1,293) | 1,118 (1,066 to 1,210) |

Where each one wins, and why, measured rather than guessed:

- On a small folder Cesia wins, 17 ms against 27 at 100 files: it starts in 3.2 ms where Python takes 14.4, the medians
  of 21 runs of a program that prints a number.
- Past 400 files Python wins, by a third on 1,000 photos and by a quarter on 1,000 files of one size. The cause is the
  hash: BLAKE2b-256 of 64 MiB held in memory takes 75.6 ms in Python and 107.2 ms in Cesia, the medians of 11 tries, so
  867 MB/s against 612. Python 3.14 takes its BLAKE2b from HACL*, a cryptographic library whose code is proved correct by
  machine, in a version for AVX2, the 256-bit vector instructions of Intel processors, which this one has: its module
  holds 1,681 of them. Cesia's is the portable C of the runtime of OCaml, whose compression function, disassembled, does
  its arithmetic without any. On 1,000 files of one size, that gap is 31.6 ms of the 32.3 between the two.
  The walk and the sizes cost the same in both, 3.5 ms for 1,000 files once the start-up is taken off: 6.7 ms for Cesia
  and 17.9 for Python, start-up in, the medians of 21 runs. So on 1,000 files of one size, Cesia gains 11 ms at the start, loses 32 in the hash,
  and 12 more in reading and grouping, which this chapter did not take apart further: Python reads each file in pieces
  into one buffer, where Cesia makes one text of each whole file.
- With a cold cache, the disk decides: the two intervals overlap, so no difference between them is shown.

In short, beside Python: Cesia is faster on small folders, they tie at 400 files, and Python's hash makes it faster on
larger ones, until the disk makes them equal. A vector version of BLAKE2b in Cesia would close the gap: it is in
[what is left](#7-what-is-left).

fdupes and jdupes are not installed on this machine, so they are compared here by their documentation only, above, and not
by a time.

### Threats to validity

A measure can be wrong without any mistake in sight: Todd Mytkowicz, Amer Diwan, Matthias Hauswirth and Peter F. Sweeney
showed in 2009 that the size of the environment variables, or the order in which a program is linked, can change its time
enough to turn a conclusion around. A *threat to validity* is such a cause, which could make the proof wrong. Each one
here, and what was done about it:

- **The other programs of the machine.** Other work ran on it, under a shared lock that keeps heavy jobs apart; the
  load average was about 1 during the runs. The programs took turns, so a slower minute fell on all of them, and the
  intervals show the noise that was left: every warm one lies within 6% of its median but one, within 10%, and the cold
  ones within 15%, the disk adding its own.
- **The writing of the folders.** The first batch of runs started just after the folders were written, while the system
  still wrote them to the disk, and its times at 100 files spread from 17 to 267 ms. That batch was thrown away: the
  numbers above come from a second one, which waited for `sync`, with 60 kB left to write.
- **A warm or a cold cache.** A user who runs the program twice gets the warm times; the first run after a restart gets
  the cold ones, both measured. Cold here means the bytes of the files only: the names and sizes of the folder stay in
  memory, so a first run after a restart would also pay the walk on the disk. A spinning disk, which moves its head for
  each file, would make every cold time longer; it was not measured, as the folders are on a solid-state disk.
- **The shape of the folder.** It decides how much is read. Photos rarely share a size, so `Duplicates` reads about the
  copies only; files of one size are the worst case, and both were measured. A real folder lies between, and its share of
  copies, one in ten here, changes the reading in proportion.
- **Random bytes.** A read and BLAKE2b take the same time whatever the bytes are, and the file system here compresses
  nothing, so random bytes stand for photos, which are compressed already. The folders are made again, the same, from
  the same seed by `bench/dupes-folder.py`.
- **The start of a process.** Each time includes it, a few milliseconds for Cesia and more for Python: what a user waits
  for, and the reason of most of the gap at 100 files, said above.
- **The setup itself.** The environment and the order of linking were not varied, so a bias of the kind Mytkowicz and
  his coauthors found may remain in every number. The conclusions rest on ratios of 1.25 to 400; the one close
  comparison, Cesia and Python at 400 files, 2% apart, is called a tie, not a win.
- **The same answer.** Every run printed the same groups as the first run of the first program, line for line; a
  different answer would have stopped the measure.

## 7. What is left

The solution answers the question for the folders it was proved on. Its limits, said plainly:

- **Hard links.** A [hard link](glossary.md#hard-and-symbolic-links) is a second name of the same file, not a copy:
  deleting one name frees no space. [sys.Stat] doesn't say which file a name leads to, so two names of one file are
  reported as duplicates. They do hold the same bytes, so the answer is still sound, but it can mislead whoever deletes.
  fdupes and jdupes treat such names as non-duplicates by default.
- **Symbolic links** are left out: a link is no copy, and following one could leave the folder or loop.
- **Files that change while they are read.** The size comes from [sys.Stat], the bytes from [sys.Read] later: a file that
  grows in between is hashed as it is when read. The answer describes the folder at no single moment; for a folder in use,
  run it again, or compare the size read with the size seen.
- **Permissions.** A file that Cesia may not read, or that the system refuses, ends the program with an `Err` that names
  it: `?` passes it on. A version that skips such files and lists them at the end is a few lines more.
- **Memory.** [sys.Read] holds a whole file in memory, so a film of 4 GB needs 4 GB at once. Python's `file_digest` reads
  by pieces. Cesia has no reading of a file by pieces yet; with one, the hash would read a piece at a time, and the first
  4 KiB of jdupes would apply too.
- **The speed of the hash.** Cesia's BLAKE2b, the portable C of OCaml's runtime, hashes 612 MB a second on this machine,
  where Python's, with AVX2, reaches 867: past a few hundred files, Python is a quarter to a third faster. A version
  with vector instructions would close that gap.
- **Empty files** are duplicates of each other, by the definition, and are grouped. jdupes leaves them out unless asked,
  with `-z`; fdupes keeps them unless asked, with `-n`.
- **An attacker's files.** Against files made to collide, the proof is no longer the bound but BLAKE2b's collision
  security; comparing the bytes of each group at the end, as fdupes does, would make it unconditional, for one more read
  of each copy.
- **Near duplicates**, a photo and its smaller version, are another problem, out of scope from step 1.

## Further reading

- George Pólya, *How to Solve It*, 1945, and the Heilmeier catechism of DARPA: stating a problem; Karl Popper, *The Logic
  of Scientific Discovery*, 1934: a hypothesis that can be proved wrong.
- Raj Jain, *The Art of Computer Systems Performance Analysis*, 1991; Andy Georges, Dries Buytaert and Lieven Eeckhout,
  *Statistically Rigorous Java Performance Evaluation*, 2007; Tomas Kalibera and Richard Jones, *Rigorous Benchmarking in
  Reasonable Time*, 2013; Jean-Yves Le Boudec, *Performance Evaluation of Computer and Communication Systems*, 2010:
  measuring.
- Andreas Zeller and Ralf Hildebrandt, *Simplifying and Isolating Failure-Inducing Input*, 2002: shrinking a failure to
  its cause.
- Jean-Philippe Aumasson and others, *BLAKE2: Simpler, Smaller, Fast as MD5*, 2013, and RFC 7693; Menezes, van Oorschot and
  Vanstone, *Handbook of Applied Cryptography*, 1996; Xiaoyun Wang and Hongbo Yu, *How to Break MD5 and Other Hash
  Functions*, 2005: the hash and its bound; Jean-Karim Zinzindohoué and others, *HACL\*: A Verified Modern Cryptographic
  Library*, 2017: the BLAKE2b of Python.
- Todd Mytkowicz and others, *Producing Wrong Data Without Doing Anything Obviously Wrong!*, 2009: threats to validity.
- The manual page of fdupes and the README of jdupes.

Each with its link in [References](references.md#solving-a-problem).

## Next

You can go from a problem to the proof that it is solved. The next chapter, [How Cesia works](internals.md), looks inside
Cesia itself.
