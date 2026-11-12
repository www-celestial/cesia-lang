# Variables d'environnement

Les variables d'environnement que Cesia lui-même lit. Un programme en lit d'autres avec [sys.Env], et `--allow env`.

| Variable | Ce qu'elle change |
|---|---|
| `CESIA_CORES` | combien de cœurs le travail sur des arrays (des listes de nombres sur lesquelles on calcule d'un coup) et des colonnes entiers peut utiliser, de 1 à 64 ; sans elle, la moitié de ceux de la machine, 16 au plus |
| `CESIA_BLAS` | la bibliothèque d'algèbre linéaire que [std/num] utilise pour les grandes matrices, par son nom, ou `none` pour n'utiliser que le code de Cesia lui-même |
| `CESIA_JIT` | `off` lance dans l'interpréteur seulement, comme `--no-jit` ; `always` fait du code natif de chaque fonction tout de suite, et de chaque boucle à son premier pas, pour les tests |
| `CESIA_JIT_SHOW` | quand elle est définie, affiche pourquoi chaque fonction est devenue du code natif, ou non |
| `CESIA_STD` | un dossier qui contient les sources de `std/` à utiliser au lieu de celles du binaire : pour travailler sur Cesia lui-même |
| `CESIA_RELEASES` | où `cesia upgrade` cherche les releases (les versions publiées) : `file:///folder` lit `folder/latest.json` au lieu de GitHub, ou `folder/nightly.json` pour `cesia upgrade --nightly` : pour un miroir |
| `XDG_CACHE_HOME` | le dossier des caches (des copies gardées pour ne pas refaire un travail), `~/.cache` sans elle : les packages récupérés par `cesia pkg`, et les runs (les exécutions) des blocs du livre |
| `HOME` | le dossier personnel, pour la valeur par défaut de `XDG_CACHE_HOME` |
| `CESIA_WORKER` | définie par le supervisor (le processus qui démarre et redémarre les workers) de `cesia run --workers` pour chaque worker qu'il démarre : le chemin de sa socket (un bout d'une connexion), le port et l'hôte. Un worker la lit une fois et la vide, pour que les programmes qu'il démarre ne la prennent pas. Ne la définissez jamais à la main |

Les scripts d'installation, `install.sh` et `install.ps1`, en lisent trois de plus :

| Variable | Ce qu'elle change |
|---|---|
| `CESIA_HOME` | où va la release, `~/.cesia` sans elle |
| `CESIA_BIN` | où vont les noms `cesia` et `ce`, `~/.local/bin` sans elle |
| `CESIA_RELEASES` | où sont les releases, comme pour `cesia upgrade` plus haut |

```bash
CESIA_CORES=4 cesia run stats.ce
CESIA_JIT=off cesia run fib.ce
```
