# Environment variables

The environment variables that Cesia itself reads. A program reads others with [sys.Env], and `--allow env`.

| Variable | What it changes |
|---|---|
| `CESIA_CORES` | how many cores the work on whole arrays and columns may use, from 1 to 64; half the machine's, at most 16, without it |
| `CESIA_BLAS` | the library of linear algebra that [std/num] uses for large matrices, by its name, or `none` to use Cesia's own code only |
| `CESIA_JIT` | `off` runs in the interpreter only, as `--no-jit`; `always` makes native code of every function at once, and of every loop at its first step, for tests |
| `CESIA_JIT_SHOW` | when it is set, prints why each function did or didn't become native code |
| `CESIA_STD` | a folder that holds the sources of `std/` to use instead of those in the binary: for work on Cesia itself |
| `CESIA_RELEASES` | where `cesia upgrade` looks for releases: `file:///folder` reads `folder/latest.json` instead of GitHub, or `folder/nightly.json` for `cesia upgrade --nightly`: for a mirror |
| `XDG_CACHE_HOME` | the folder of caches, `~/.cache` without it: packages fetched by `cesia pkg`, and the runs of the book's blocks |
| `HOME` | the home folder, for the default of `XDG_CACHE_HOME` |
| `CESIA_WORKER` | set by the supervisor of `cesia run --workers` for each worker it starts: the path of its socket, the port and the host. A worker reads it once and empties it, so the programs it starts don't take it. Never set it by hand |

The install scripts, `install.sh` and `install.ps1`, read three more:

| Variable | What it changes |
|---|---|
| `CESIA_HOME` | where the release goes, `~/.cesia` without it |
| `CESIA_BIN` | where the names `cesia` and `ce` go, `~/.local/bin` without it |
| `CESIA_RELEASES` | where the releases are, as for `cesia upgrade` above |

```bash
CESIA_CORES=4 cesia run stats.ce
CESIA_JIT=off cesia run fib.ce
```
