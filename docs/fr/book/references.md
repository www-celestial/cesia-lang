# Références

Les articles, les normes et les livres que suit la conception de Cesia, ou face auxquels il a été mesuré. Chaque entrée
donne ses auteurs, son titre, où et quand elle a paru, un lien, et en une ligne ce que Cesia en a pris. Chaque entrée a
été vérifiée auprès de son éditeur, de son DOI ou de la page de ses auteurs ; une œuvre qui n'a pas pu être vérifiée
n'est pas ici. Un *DOI*, un digital object identifier, est un lien permanent vers une œuvre publiée : `https://doi.org/`
suivi du DOI mène à l'œuvre, où que son éditeur la déplace.

## Valeurs et maps

- James R. Driscoll, Neil Sarnak, Daniel D. Sleator, Robert E. Tarjan. "Making data structures persistent". *Journal of
  Computer and System Sciences* 38(1):86–124, 1989. <https://doi.org/10.1016/0022-0000(89)90034-2>. Le mot *persistent*
  et l'idée d'une structure qui garde ses anciennes versions : chaque liste et chaque map de Cesia, comme le montre
  [Maps](maps.md).
- Chris Okasaki. *Purely Functional Data Structures*. Cambridge University Press, 1998.
  <https://doi.org/10.1017/CBO9780511530104>. Les persistent data structures et leurs coûts ; [std/heap] est son leftist
  heap (un heap en arbre dont le chemin le plus court vers le bas est toujours à droite, si bien que deux heaps se
  fusionnent vite).
- Phil Bagwell. "Ideal Hash Trees". Rapport technique, EPFL, 2001. <https://infoscience.epfl.ch/record/64398>. Le hash
  array mapped trie, un nœud de 32 enfants choisis par 5 bits du hash et gardé compact par un bitmap (une suite de bits
  qui dit lesquels existent) : la façon de ranger une map de plus de 32 clés dès qu'une écriture doit garder
  l'ancienne map, dans [Comment Cesia fonctionne](internals.md#maps--une-hash-table-puis-un-hash-trie).
- Michael J. Steindorfer, Jurgen J. Vinju. "Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM
  Collections". *OOPSLA 2015*, ACM, 783–800. <https://doi.org/10.1145/2814270.2814312>. CHAMP : un nœud à deux bitmaps,
  ses propres clés rangées sur place et ses enfants à part, aucune clé seule sous un nœud, une suppression qui fait
  remonter une clé : les nœuds d'une map de Cesia de plus de 32 clés, une fois devenue un trie.
- Python Software Foundation. "What's New In Python 3.6", le dict « reimplemented to use a more compact representation
  based on a proposal by Raymond Hettinger » (réécrit avec une représentation plus compacte, d'après une proposition de
  Raymond Hettinger), ses entrées dans l'ordre d'insertion. <https://docs.python.org/3/whatsnew/3.6.html>. La
  disposition de la hash table d'une map de Cesia de plus de 32 clés que tient un seul nom : un index de slots (des
  places de taille fixe) au-dessus des entrées rangées dans leur ordre.
- Donald E. Knuth. *The Art of Computer Programming*, vol. 3, *Sorting and Searching*, 2e édition, Addison-Wesley, 1998,
  section 6.4. Le linear probing (en cas de collision, on essaie le slot suivant) et son coût, $(1 + 1/(1 - a))/2$ slots
  pour une clé présente et $(1 + 1/(1 - a)^2)/2$ pour une clé absente, au taux de remplissage $a$ : 1,5 et 2,5 à moitié
  pleine, le plus qu'une table de Cesia accepte.
- Carl Friedrich Bolz, Lukas Diekmann, Laurence Tratt. "Storage Strategies for Collections in Dynamically Typed
  Languages". *OOPSLA 2013*, ACM, 167–182. <https://doi.org/10.1145/2509136.2509531>. Une collection d'entiers gardée
  sous forme d'entiers nus, passée une fois pour toutes à un stockage général quand une autre sorte de valeur arrive :
  les listes de Cesia, et les valeurs de ses tables.
- Rich Hickey. "A History of Clojure". *Proceedings of the ACM on Programming Languages* 4(HOPL), article 71, 2020.
  <https://doi.org/10.1145/3386321>. Les persistent maps de Clojure, bâties sur le trie de Bagwell, comme dictionnaire
  de tous les jours d'un langage : le modèle de celles de Cesia.
- Scott A. Crosby, Dan S. Wallach. "Denial of Service via Algorithmic Complexity Attacks". *12th USENIX Security
  Symposium*, 29–44, 2003.
  <https://www.usenix.org/conference/12th-usenix-security-symposium/denial-service-algorithmic-complexity-attacks>. Le
  hash flooding (envoyer beaucoup de clés de même hash pour ralentir un programme) : pourquoi le hash d'une map prend un
  seed tiré à chaque run, et pourquoi les clés d'un même hash vont dans un arbre équilibré.
- David S. Wise, Daniel P. Friedman. "The one-bit reference count". *BIT* 17(3):351–359, 1977.
  <https://doi.org/10.1007/BF01932156>. Un bit qui dit si une valeur est partagée : le bit *owned* de Cesia, qui permet à
  une écriture de changer une valeur sur place quand rien d'autre ne la tient.
- Sebastian Ullrich, Leonardo de Moura. "Counting Immutable Beans: Reference Counting Optimized for Purely Functional
  Programming". *IFL 2019*, ACM, 2019. <https://doi.org/10.1145/3412932.3412935>. Des valeurs immutable (qu'aucune
  fonction ne change) mises à jour sur place quand elles sont uniques, comme le fait Lean 4 avec des comptes complets :
  la même idée que le copy-on-write de Cesia (partager une valeur et ne la copier qu'à la première écriture), avec un
  seul bit.
- Xavier Leroy. "Unboxed Objects and Polymorphic Typing". *POPL 1992*, ACM, 177–188.
  <https://doi.org/10.1145/143165.143205>. Pourquoi OCaml garde un float (un nombre à virgule) dans un bloc à lui, sauf
  dans un array ou un record (l'équivalent OCaml d'une struct) faits seulement de floats : une valeur float de Cesia fait
  deux blocs, et le stockage d'une map ou d'une struct de floats est un array de doubles (des nombres machine de 64 bits,
  nus).
- IEEE. "IEEE Standard for Floating-Point Arithmetic", IEEE Std 754-2019, 2019.
  <https://doi.org/10.1109/IEEESTD.2019.8766229>. Les floats de 64 bits de Cesia, leur arrondi, leurs infinis et NaN.

## L'interpréteur

- Peter J. Landin. "The Mechanical Evaluation of Expressions". *The Computer Journal* 6(4):308–320, 1964.
  <https://doi.org/10.1093/comjnl/6.4.308>. La closure, une fonction avec l'environnement où elle a été créée.
- Marc Feeley, Guy Lapalme. "Using Closures for Code Generation". *Computer Languages* 12(1):47–66, 1987.
  <https://doi.org/10.1016/0096-0551(87)90012-9>. Un syntax tree (le programme sous forme d'arbre) compilé en closures qui
  l'exécutent, plus vite que de parcourir l'arbre : l'interpréteur de Cesia, `src/lib/compile.ml`.

## Le JIT

- L. Peter Deutsch, Allan M. Schiffman. "Efficient Implementation of the Smalltalk-80 System". *POPL 1984*, ACM, 297–302.
  <https://doi.org/10.1145/800017.800542>. L'inline cache : la dernière classe rencontrée à un appel, gardée à côté de
  lui, pour que l'appel suivant de la même classe aille droit à sa méthode. Les caches de formes et de clés de Cesia.
- Craig Chambers, David Ungar. "Customization: Optimizing Compiler Technology for SELF, a Dynamically-Typed
  Object-Oriented Programming Language". *PLDI 1989*, 146–160. <https://doi.org/10.1145/73141.74831>. Une fonction
  compilée une fois pour chaque sorte de ses arguments : les versions de Cesia, une par tuple de types d'arguments.
- Craig Chambers, David Ungar, Elgin Lee. "An Efficient Implementation of SELF, a Dynamically-Typed Object-Oriented
  Language Based on Prototypes". *OOPSLA 1989*, 49–70. <https://doi.org/10.1145/74877.74884>. Les *maps* au sens de Self,
  que V8 a plus tard appelées hidden classes : la disposition d'un objet, partagée par tous les objets de sa forme. Les
  formes des structs de Cesia et les clés partagées de ses petites maps.
- Urs Hölzle, Craig Chambers, David Ungar. "Optimizing Dynamically-Typed Object-Oriented Languages With Polymorphic Inline
  Caches". *ECOOP 1991*, LNCS 512, 21–38. <https://doi.org/10.1007/BFb0057013>. Des inline caches à chaque endroit du
  code ; ceux des champs de Cesia gardent la dernière forme rencontrée, la sorte monomorphic (à une seule forme) dont part
  cet article, et son JIT fait la sorte polymorphic (à plusieurs) de cet article pour un appel à travers une valeur : un
  test de chaque fonction rencontrée, jusqu'à quatre.
- Urs Hölzle, Craig Chambers, David Ungar. "Debugging Optimized Code with Dynamic Deoptimization". *PLDI 1992*, 32–43.
  <https://doi.org/10.1145/143095.143114>. Quitter le code optimisé pour l'interpréteur, avec l'état reconstruit : les
  bails de Cesia.
- Urs Hölzle, David Ungar. "Optimizing Dynamically-Dispatched Calls with Run-Time Type Feedback". *PLDI 1994*, 326–336.
  <https://doi.org/10.1145/178243.178478>. Compiler pour les types vraiment rencontrés pendant que le programme tournait :
  les suppositions que le JIT de Cesia tire de la frame (les slots des variables d'un appel).
- Andreas Gal et d'autres. "Trace-based Just-in-Time Type Specialization for Dynamic Languages". *PLDI 2009*, 465–478.
  <https://doi.org/10.1145/1542476.1542528>. Le tracing JIT, qui compile un seul chemin hot à travers le programme. Cesia
  compile plutôt des fonctions et des boucles entières, avec des guards (les tests que le code machine fait avant de se
  servir d'un pari), ce qui garde sa vitesse régulière sur du code plein de branches.
- Stephen J. Fink, Feng Qian. "Design, Implementation and Evaluation of Adaptive Recompilation with On-Stack
  Replacement". *CGO 2003*, IEEE, 241–252. <https://researchr.org/publication/FinkQ03>. Entrer dans du code optimisé au
  milieu d'une boucle qui tourne, par une entrée qui reconstruit son état et va à la tête de la boucle : on entre dans le
  code machine de Cesia avant une boucle, quelle que soit la cause qui y ramène l'exécution, jamais dans son corps.
- Benoit Boissinot, Alain Darte, Fabrice Rastello, Benoît Dupont de Dinechin, Christophe Guillon. "Revisiting Out-of-SSA
  Translation for Correctness, Code Quality and Efficiency". *CGO 2009*, IEEE, 114–125.
  <https://dblp.org/rec/conf/cgo/BoissinotDRDG09>. Sortir de la SSA form (où chaque variable reçoit sa valeur à un seul
  endroit) met une copie sur chaque chemin qui entre dans un bloc où des versions d'une variable se rejoignent, et seul
  le coalescing (la fusion de variables copiées l'une dans l'autre) l'enlève : pourquoi une boucle entrée en son milieu
  copiait chaque variable à chaque tour.
- Rastislav Bodík, Rajiv Gupta, Vivek Sarkar. "ABCD: Eliminating Array Bounds Checks on Demand". *PLDI 2000*, ACM,
  321–333. <https://doi.org/10.1145/349299.349342>. Des bornes prouvées à partir des tests qui gardent chaque branche, et
  les vérifications qu'elles rendent inutiles retirées : le JIT de Cesia retire la vérification d'overflow (le
  dépassement de la taille d'un entier) de `n - 1` dans le `else` de `if n < 2`.
- Peng Zhao, José Nelson Amaral. "Function Outlining and Partial Inlining". *SBAC-PAD 2005*, IEEE, 101–108.
  <https://doi.org/10.1109/CAHPC.2005.26>. Ne faire l'inlining (recopier le code d'une fonction à l'endroit de l'appel)
  que de la partie hot d'une fonction dans ses appelants : le JIT de Cesia recopie dans chaque appel le test d'une
  fonction appelée qui rend tout de suite, comme le `if n < 2 then n` de `fib`.
- Lukas Stadler, Thomas Würthinger, Hanspeter Mössenböck. "Partial Escape Analysis and Scalar Replacement for Java".
  *CGO 2014*, ACM. <https://doi.org/10.1145/2544137.2544157>. Un objet gardé sous forme de ses champs là où il ne
  s'échappe pas (là où rien hors du code ne peut le voir), et construit seulement sur les chemins où il s'échappe : la map
  que le code machine de Cesia lit dans une liste pour ses champs tient dans quatre registres, et n'est construite qu'à
  un bail ou à la fin du run.
- Mike Pall. "Allocation Sinking Optimization". Wiki de LuaJIT, 2012, livré dans LuaJIT 2.0 ; le texte est conservé à
  <https://ujit.readthedocs.io/en/latest/public/tut-allocation-sinking.html>. Une allocation déplacée hors du chemin
  rapide, vers la sortie qui en a besoin : la même chose pour les maps et les structs de floats de Cesia dans une boucle.
- Andreas Wöß, Christian Wirth, Daniele Bonetta, Chris Seaton, Christian Humer, Hanspeter Mössenböck. "An Object Storage
  Model for the Truffle Language Implementation Framework". *PPPJ 2014*, ACM, 133–144.
  <https://doi.org/10.1145/2647508.2647517>. Les champs d'un objet gardés selon leur sorte, un double unboxed (nu, sans
  bloc de mémoire autour), un champ écrit avec une autre sorte généralisé : le stockage F d'une map ou d'une struct de
  floats de Cesia, avec une seule sorte pour tout le stockage.
- Anton Lorenzen, Daan Leijen, Wouter Swierstra. "FP²: Fully in-Place Functional Programming". *Proceedings of the ACM on
  Programming Languages* 7(ICFP), article 198, 275–304, 2023. <https://doi.org/10.1145/3607840>. Une valeur que rien
  d'autre ne tient peut être reconstruite sur place sans changer ce que veut dire le programme : pourquoi le code machine
  de Cesia écrit les doubles d'une nouvelle map dans la map owned (tenue par un seul nom) qu'elle remplace.
- Vladimir Makarov. MIR, a lightweight JIT compiler. <https://github.com/vnmakarov/mir>, et "MIR: A lightweight JIT
  compiler project", Red Hat Developer, 2020.
  <https://developers.redhat.com/blog/2020/01/20/mir-a-lightweight-jit-compiler-project>. Le backend (la partie d'un
  compilateur qui produit le code machine) qui fabrique le code machine de Cesia à partir du texte de son IR (la forme du
  programme entre sa source et le code machine), copié dans `src/sys/mir/`.

## Fibers et channels

- C. A. R. Hoare. "Communicating Sequential Processes". *Communications of the ACM* 21(8):666–677, 1978.
  <https://doi.org/10.1145/359576.359585>. Des processus qui ne partagent aucune mémoire et se parlent par des channels
  (ce qui porte des valeurs de l'un à l'autre), un envoi et une réception qui se rencontrent : [fiber.Channel], et sa
  taille 0.
- The Go Programming Language Specification. <https://go.dev/ref/spec>, sections "Channel types", "Close" et "Select
  statements". Les buffered channels (qui gardent des valeurs en attente), close et select : le modèle de [std/fiber],
  avec une différence : `Select` essaie ses channels dans l'ordre, là où Go en choisit un au hasard.
- KC Sivaramakrishnan, Stephen Dolan, Leo White, Tom Kelly, Sadiq Jaffer, Anil Madhavapeddy. "Retrofitting Effect
  Handlers onto OCaml". *PLDI 2021*, 206–221. <https://doi.org/10.1145/3453483.3454039>. Les effect handlers (la partie
  d'un programme qui attrape un effect et peut reprendre le code qui l'a lancé) et les petites stacks (la pile des
  appels en cours) qui grandissent derrière eux, dans OCaml 5 : ce qu'est chaque fiber de Cesia.
- Henry G. Baker Jr., Carl Hewitt. "The Incremental Garbage Collection of Processes". *Symposium on Artificial
  Intelligence and Programming Languages*, ACM, 55–59, 1977. <https://doi.org/10.1145/800228.806932>. Le *future*, une
  valeur qu'un calcul donne plus tard : une tâche de [fiber.Spawn], que [fiber.Wait] lit.
- The Go Authors. Go 1.3 and Go 1.4 Release Notes, 2014. <https://go.dev/doc/go1.3>, <https://go.dev/doc/go1.4>, et le
  document de conception "Contiguous stacks", 2013. <https://go.dev/s/contigstacks>. La stack d'une goroutine commence à
  2 048 octets et est recopiée dans une plus grande quand elle est pleine : ce à quoi les fibers de Cesia sont comparées
  dans leurs mesures, et pourquoi leurs stacks commencent à 8 slots et doublent.
- Joe Armstrong. "A History of Erlang". *HOPL III*, ACM, 2007. <https://doi.org/10.1145/1238844.1238850>. Des processus
  relayés après un compte de réductions (de pas d'exécution), des supervisors qui redémarrent un processus tombé, et du
  code remplacé pendant qu'il tourne : les checkpoints de Cesia tous les millions de pas, le supervisor de `--workers`,
  et `--watch`.

## La mémoire

- KC Sivaramakrishnan, Stephen Dolan, Leo White, Sadiq Jaffer, Tom Kelly, Anmol Sahoo, Sudha Parimala, Atul Dhiman, Anil
  Madhavapeddy. "Retrofitting Parallelism onto OCaml". *Proceedings of the ACM on Programming Languages* 4(ICFP), article
  113, 2020. <https://doi.org/10.1145/3408995>. Le garbage collector d'OCaml 5 (la partie qui libère la mémoire que plus
  rien n'utilise), et ses domains (des fils d'exécution qui tournent en parallèle, chacun sur son cœur) : ce qui libère la
  mémoire de Cesia, et ce qui fait tourner sur plusieurs cœurs le travail sur des colonnes entières.

## Le serveur et le réseau

- John D. C. Little. "A Proof for the Queuing Formula: L = λW". *Operations Research* 9(3), 1961, 383–387.
  <https://doi.org/10.1287/opre.9.3.383>. Les requêtes en attente sont le débit multiplié par le temps que chacune
  attend : le plancher de la latence d'un serveur à 1 000 connexions, quel que soit son scheduler.
- R. Fielding, M. Nottingham, J. Reschke (éditeurs). "HTTP Semantics", RFC 9110, 2022.
  <https://www.rfc-editor.org/rfc/rfc9110>, et "HTTP/1.1", RFC 9112, 2022. <https://www.rfc-editor.org/rfc/rfc9112>.
  Les méthodes, les statuts, les en-têtes, les connexions persistantes (gardées ouvertes d'une requête à l'autre) :
  [std/http].
- A. Barth. "The Web Origin Concept", RFC 6454, 2011. <https://www.rfc-editor.org/rfc/rfc6454>. Le header `Origin`,
  scheme, hôte et port, son hôte en ASCII : ce que [http.SameOrigin] compare au `Host`.
- W3C. "Fetch Metadata Request Headers", Working Draft. <https://www.w3.org/TR/fetch-metadata/>. Le header
  `Sec-Fetch-Site`, qu'aucune page ne peut écrire ; F. Valsorda. "Cross-Site Request Forgery", 13 août 2025.
  <https://words.filippo.io/csrf/>, et `net/http.CrossOriginProtection` de Go 1.25.
  <https://pkg.go.dev/net/http#CrossOriginProtection>. Les étapes de [http.SameOrigin], et leur limite avec le scheme.
- I. Fette, A. Melnikov. "The WebSocket Protocol", RFC 6455, 2011. <https://www.rfc-editor.org/rfc/rfc6455>. Le serveur
  et le client de [std/websocket].
- Y. Bernier. "Latency Compensating Methods in Client/Server In-game Protocol Design and Optimization". Valve, GDC 2001.
  <https://www.gamedevs.org/uploads/latency-compensation-in-client-server-protocols.pdf> ; G. Gambetta. "Fast-Paced
  Multiplayer (Part II): Client-Side Prediction and Server Reconciliation".
  <https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html> ; Replicache, "How it works".
  <https://doc.replicache.dev/concepts/how-it-works>. Les coups d'un joueur dessinés aussitôt, puis l'état du serveur,
  avec par-dessus les coups auxquels il n'a pas encore répondu, rejoués : les effets des actions d'une page de
  [std/live].
- D. L. Mills. "Internet Time Synchronization: The Network Time Protocol". *IEEE Transactions on Communications* 39(10),
  1991, 1482–1493. <https://doi.org/10.1109/26.103043>. L'écart entre deux horloges tiré d'un aller-retour, avec une
  erreur d'au plus la moitié de ce trajet : comment `live.js` lit l'heure que l'application inscrit sur chacun de ses
  changements.
- crossbar.io. Autobahn|Testsuite 25.10.1, la suite de référence de la RFC 6455. <https://github.com/crossbario/autobahn-testsuite>.
  Son fuzzing server (le serveur qui envoie des cas difficiles) joue ses cas contre le client de [std/websocket] dans la CI.
- E. Rescorla. "The Transport Layer Security (TLS) Protocol Version 1.3", RFC 9846, 2026, qui a remplacé la RFC 8446.
  <https://www.rfc-editor.org/rfc/rfc9846>. Le chiffrement de `https`, que [std/tls] tient d'OpenSSL.
- The Linux man-pages project. epoll(7) <https://man7.org/linux/man-pages/man7/epoll.7.html>, et epoll_ctl(2), dont
  le `EPOLLEXCLUSIVE` est arrivé dans Linux 4.5 <https://man7.org/linux/man-pages/man2/epoll_ctl.2.html>. Comment le
  scheduler attend les sockets sous Linux, et comment une connexion réveille un seul worker.
- Prometheus. "Exposition formats". <https://prometheus.io/docs/instrumenting/exposition_formats/>. Le texte que donne
  [metrics.Text].
- Deno. "Security and permissions". <https://docs.deno.com/runtime/fundamentals/security/>. Un runtime sans aucun accès
  par défaut, et des flags `--allow` limités à un chemin, un hôte ou un nom : les [permissions](permissions.md) de Cesia
  marchent de la même façon, et, comme là-bas, une bibliothèque C est hors de la sandbox (l'endroit où un programme
  tourne avec les seuls droits qu'on lui a donnés).

## Textes et formats

- Ken Thompson. "Programming Techniques: Regular expression search algorithm". *Communications of the ACM* 11(6):419–422,
  1968. <https://doi.org/10.1145/363347.363387>. Faire correspondre une regular expression (un petit texte qui décrit un
  ensemble de textes) en faisant avancer tous ses états à la fois, en un temps linéaire en la longueur du texte.
- Russ Cox. "Regular Expression Matching Can Be Simple And Fast", 2007. <https://swtch.com/~rsc/regexp/regexp1.html>, et
  "Regular Expression Matching: the Virtual Machine Approach", 2009. <https://swtch.com/~rsc/regexp/regexp2.html>. La Pike
  machine, la méthode de Thompson avec les positions des groupes, tirée du code de sam, l'éditeur de Rob Pike :
  [std/regex], dont le temps reste linéaire quel que soit le pattern.
- F. Yergeau. "UTF-8, a transformation format of ISO 10646", RFC 3629, STD 63, 2003.
  <https://www.rfc-editor.org/info/rfc3629>. De l'UTF-8 valide, sans overlong forms (un caractère écrit avec plus
  d'octets qu'il n'en faut), surrogates (U+D800 à U+DFFF, gardés par UTF-16) ni code points (numéros de caractère dans
  Unicode) au-delà de U+10FFFF : ce que vérifie [text.IsUtf8], et ce que le lexer de Cesia (la partie qui découpe le
  texte en mots) demande à une source.
- Randall J. Fisher, Henry G. Dietz. "Compiling for SIMD Within a Register". *Languages and Compilers for Parallel
  Computing, LCPC'98*, LNCS 1656, Springer, 1999, 290–305. <https://doi.org/10.1007/3-540-48319-5_19>. SWAR, le travail
  sur plusieurs octets tenus dans un seul mot machine, un nom que ses auteurs ont créé en 1996 : la façon dont
  [text.Count] compte un octet et dont [text.IsUtf8] saute l'ASCII, huit octets à la fois.
- Henry S. Warren, Jr. *Hacker's Delight*, 2e édition, Addison-Wesley, 2013, section 6–1, "Find First 0-Byte". ISBN
  978-0-321-84268-8. Le test qui met à 1 le bit de poids fort des octets nuls d'un mot, et d'eux seuls, que
  [text.Count] additionne et dont [text.ByteFind] se sert pour trouver l'octet le plus rare d'une partie cherchée.
- Donald E. Knuth, James H. Morris Jr., Vaughan R. Pratt. "Fast Pattern Matching in Strings". *SIAM Journal on
  Computing* 6(2):323–350, 1977. <https://doi.org/10.1137/0206024>. Une recherche en un temps linéaire en la longueur du
  texte et de la partie cherchée, qui ne lit jamais deux fois un octet du texte : [text.ByteFind] et les autres
  recherches de [std/text] pour une partie de 32 octets ou plus.
- T. Bray (éditeur). "The JavaScript Object Notation (JSON) Data Interchange Format", RFC 8259, 2017.
  <https://www.rfc-editor.org/rfc/rfc8259>. [std/json].
- Y. Shafranovich. "Common Format and MIME Type for Comma-Separated Values (CSV) Files", RFC 4180, 2005.
  <https://www.rfc-editor.org/rfc/rfc4180>. [std/csv] et le CSV de [std/frame].
- S. Josefsson. "The Base16, Base32, and Base64 Data Encodings", RFC 4648, 2006. <https://www.rfc-editor.org/rfc/rfc4648>.
  L'hexadécimal et le Base64 dans [std/encode].
- T. Berners-Lee, R. Fielding, L. Masinter. "Uniform Resource Identifier (URI): Generic Syntax", RFC 3986, 2005.
  <https://www.rfc-editor.org/rfc/rfc3986>. Les escapes (l'écriture d'un caractère qu'une URL ne peut pas contenir tel
  quel) de [encode.UrlEncode].
- John MacFarlane. CommonMark Spec, version 0.31.2, 2024. <https://spec.commonmark.org/0.31.2/>, et la GitHub Flavored
  Markdown Spec, version 0.29-gfm, 2019, pour les tables. <https://github.github.com/gfm/#tables-extension->.
  [std/markdown].
- Tom Preston-Werner, Pradyun Gedam et d'autres. TOML v1.0.0, 2021. <https://toml.io/en/v1.0.0>. `cesia.toml` est lu
  comme un sous-ensemble strict de TOML : un fichier que Cesia accepte veut dire la même chose pour tout lecteur de TOML.
- Howard Hinnant. "chrono-Compatible Low-Level Date Algorithms". <https://howardhinnant.github.io/date_algorithms.html>.
  Les jours à partir d'une date, et l'inverse, par ères de 400 ans, dans [std/date].

## Tests

- Koen Claessen, John Hughes. "QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs". *ICFP 2000*,
  268–279. <https://doi.org/10.1145/351240.351266>. Des propriétés essayées sur des cas tirés au hasard : [test.ForAll].
- David R. MacIver, Alastair F. Donaldson. "Test-Case Reduction via Test-Case Generation: Insights from the Hypothesis
  Reducer (Tool Insights Paper)". *ECOOP 2020*, LIPIcs 166, 13:1–13:27. <https://doi.org/10.4230/LIPIcs.ECOOP.2020.13>.
  Le shrinking (la réduction) d'un échec par celle des tirages qui l'ont produit, sa tape (la bande des tirages) : la
  façon dont [test.ForAll] trouve le plus petit cas qui échoue.
- Guy L. Steele Jr., Doug Lea, Christine H. Flood. "Fast Splittable Pseudorandom Number Generators". *OOPSLA 2014*,
  453–472. <https://doi.org/10.1145/2660193.2660195>. SplitMix64, le générateur de [std/random] : le même seed (le nombre
  dont part le générateur) donne les mêmes nombres sur chaque système.

## Résoudre un problème

Les méthodes de [Résoudre un vrai problème](duplicates.md), étape par étape, et les documents des outils auxquels il est
comparé. BLAKE2 est sous [Cryptographie](#cryptographie), QuickCheck et le shrinking d'Hypothesis sous [Tests](#tests).

- George Pólya. *How to Solve It: A New Aspect of Mathematical Method*. Princeton University Press, 1945. Les questions
  qui commencent un problème : l'inconnue, les données, la condition ; et le regard en arrière, à la fin.
- DARPA. "The Heilmeier Catechism". <https://www.darpa.mil/about/heilmeier-catechism>. Les questions de George Heilmeier,
  directeur de la DARPA de 1975 à 1977 : avant tout, l'examen qui dit la réussite, que le chapitre écrit sous la forme
  d'une propriété.
- Karl R. Popper. *Logik der Forschung*. Julius Springer, Vienna, 1934 ; en anglais, *The Logic of Scientific
  Discovery*, Hutchinson, London, 1959. Une affirmation est scientifique quand une expérience pourrait la réfuter :
  l'hypothèse falsifiable de l'étape 3.
- Raj Jain. *The Art of Computer Systems Performance Analysis: Techniques for Experimental Design, Measurement,
  Simulation, and Modeling*. Wiley, 1991. ISBN 978-0-471-50336-1. Mesurer avant de changer, la même tâche pour chaque
  système, et les erreurs d'une mesure.
- Andy Georges, Dries Buytaert, Lieven Eeckhout. "Statistically Rigorous Java Performance Evaluation". *OOPSLA 2007*, ACM,
  57–76. <https://doi.org/10.1145/1297027.1297033>. Un seul run, ou le meilleur de quelques-uns, peut mal classer deux
  systèmes : donnez un confidence interval (l'intervalle qui contient la vraie valeur avec une probabilité donnée).
- Tomas Kalibera, Richard Jones. "Rigorous Benchmarking in Reasonable Time". *ISMM 2013*, ACM, 63–74.
  <https://doi.org/10.1145/2464157.2464160>. Répétez les runs au niveau où se trouve le bruit : ici le processus entier.
- Jean-Yves Le Boudec. *Performance Evaluation of Computer and Communication Systems*. EPFL Press, 2010.
  <https://leboudec.github.io/perfeval/>. Son théorème 2.1 : le confidence interval d'une médiane entre deux order
  statistics (deux des mesures mises en ordre), quelle que soit la distribution, tel que chaque temps du chapitre le
  donne.
- Andreas Zeller, Ralf Hildebrandt. "Simplifying and Isolating Failure-Inducing Input". *IEEE Transactions on Software
  Engineering* 28(2):183–200, 2002. <https://doi.org/10.1109/32.988498>. Le delta debugging : une entrée qui fait échouer,
  rendue plus petite jusqu'à ce qu'elle montre la cause, ici deux fichiers d'une même taille.
- Alfred J. Menezes, Paul C. van Oorschot, Scott A. Vanstone. *Handbook of Applied Cryptography*. CRC Press, 1996, §2.1.5,
  Fact 2.27. <https://cacr.uwaterloo.ca/hac/>. Le problème des anniversaires, sa probabilité exacte et son approximation
  $1 - \exp(-n(n - 1)/(2m))$, d'où suit la borne du chapitre.
- M-J. Saarinen (éditeur), J-P. Aumasson. "The BLAKE2 Cryptographic Hash and Message Authentication Code (MAC)", RFC 7693,
  2015. <https://www.rfc-editor.org/rfc/rfc7693>. BLAKE2b de 1 à 64 octets, et la sécurité contre les collisions de
  $2^{128}$ de sa forme de 32 octets, le digest (l'empreinte) de [cesia.Fingerprint].
- Xiaoyun Wang, Hongbo Yu. "How to Break MD5 and Other Hash Functions". *EUROCRYPT 2005*, LNCS 3494, Springer, 19–35.
  <https://doi.org/10.1007/11426639_2>. Des collisions de MD5 en moins d'une heure : pourquoi un outil qui hashe avec MD5
  doit comparer les octets ensuite.
- Jean-Karim Zinzindohoué, Karthikeyan Bhargavan, Jonathan Protzenko, Benjamin Beurdouche. "HACL*: A Verified Modern
  Cryptographic Library". *CCS 2017*, ACM, 1789–1806. <https://doi.org/10.1145/3133956.3134043>. La bibliothèque dont
  Python utilise le BLAKE2b depuis le changement gh-119316 de CPython, 2024, <https://github.com/python/cpython/pull/119316>,
  avec une version pour les instructions AVX2 : pourquoi Python hashe plus vite que Cesia sur la machine du chapitre.
- Todd Mytkowicz, Amer Diwan, Matthias Hauswirth, Peter F. Sweeney. "Producing Wrong Data Without Doing Anything Obviously
  Wrong!". *ASPLOS 2009*, ACM, 265–276. <https://doi.org/10.1145/1508244.1508275>. Le biais de mesure qui vient du
  dispositif, comme la taille de l'environnement ou l'ordre de l'édition de liens : les threats to validity du chapitre.
- Adrian Lopez. fdupes, sa page de manuel `fdupes.1`. <https://github.com/adrianlopezroche/fdupes>. Les tailles, MD5,
  puis les octets comparés ; les fichiers vides gardés sauf avec `-n`, les hard links non doublons sauf avec `-H`.
- Jody Bruchon. jdupes, son README et `filehash.c`. <https://codeberg.org/jbruchon/jdupes>. Les tailles, les 4 premiers
  KiB, le fichier entier avec XXH64, puis les octets comparés sauf avec `-Q` ; les fichiers vides seulement avec `-z`,
  les hard links non doublons sauf avec `-H`.

## Données et nombres

- Wes McKinney. "Data Structures for Statistical Computing in Python". *Proceedings of the 9th Python in Science
  Conference*, 56–61, 2010. <https://doi.org/10.25080/Majora-92bf1922-00a>. La data frame de pandas (une table de
  colonnes nommées) : [std/frame].
- Charles R. Harris et d'autres. "Array programming with NumPy". *Nature* 585:357–362, 2020.
  <https://doi.org/10.1038/s41586-020-2649-2>. Les opérations sur des arrays entiers : [std/num] et l'arithmétique des
  arrays.
- E. Anderson et d'autres. *LAPACK Users' Guide*, troisième édition. SIAM, 1999. <https://doi.org/10.1137/1.9780898719604>.
  La résolution de systèmes, la décomposition QR et les valeurs propres : [std/lapack], quand la machine l'a.
- James W. Cooley, John W. Tukey. "An Algorithm for the Machine Calculation of Complex Fourier Series". *Mathematics of
  Computation* 19(90):297–301, 1965. <https://doi.org/10.1090/S0025-5718-1965-0178586-1>. La transformée de Fourier
  rapide en base 2 de [num.Fft].
- E. W. Dijkstra. "A note on two problems in connexion with graphs". *Numerische Mathematik* 1:269–271, 1959.
  <https://doi.org/10.1007/BF01386390>. [algo.Dijkstra].
- V. I. Levenshtein. "Binary codes capable of correcting deletions, insertions, and reversals". *Soviet Physics Doklady*
  10(8):707–710, 1966 ; l'original russe, 1965 : <https://www.mathnet.ru/eng/dan31411>. L'edit distance (le plus petit
  nombre d'insertions, de suppressions et de remplacements qui changent un texte en un autre) de [algo.Levenshtein].

## Bases de données

- Kevin P. Gaffney, Martin Prammer, Larry Brasfield, D. Richard Hipp, Dan Kennedy, Jignesh M. Patel. "SQLite: Past,
  Present, and Future". *Proceedings of the VLDB Endowment* 15(12):3535–3547, 2022.
  <https://doi.org/10.14778/3554821.3554842>. Le moteur derrière [std/sql], et comment il est construit.
- SQLite. "Write-Ahead Logging". <https://www.sqlite.org/wal.html>. Le mode dans lequel Cesia ouvre chaque fichier de
  base de données : les lecteurs ne bloquent pas celui qui écrit, et chaque lecture voit la base telle qu'elle était
  quand elle a commencé.
- SQLite. "Isolation In SQLite". <https://www.sqlite.org/isolation.html>. Des transactions serializable (dont le
  résultat est celui d'une exécution une par une), par des écritures faites une à la fois, et la snapshot isolation
  (chaque lecture voit l'état figé pris à son début) pour les lecteurs d'une base en mode WAL.
- SQLite. "Pragma statements", `synchronous`. <https://www.sqlite.org/pragma.html#pragma_synchronous>. `FULL` est ACID
  en mode WAL, `NORMAL` peut perdre les derniers commits (les transactions confirmées) lors d'une coupure de courant :
  pourquoi un commit de Cesia est durable.
- Hal Berenson, Phil Bernstein, Jim Gray, Jim Melton, Elizabeth O'Neil, Patrick O'Neil. "A Critique of ANSI SQL Isolation
  Levels". *SIGMOD 1995*, 1–10. <https://doi.org/10.1145/223784.223785>. Le sens exact de l'isolation, snapshot et
  serializable, utilisé dans [SQLite](sqlite.md).

## Cryptographie

[std/crypto] appelle libsodium, <https://doc.libsodium.org/>, et n'écrit lui-même aucune primitive (aucune des
opérations de base de la cryptographie). Les algorithmes derrière ses fonctions :

- Daniel J. Bernstein. "The Salsa20 Family of Stream Ciphers". Dans *New Stream Cipher Designs*, LNCS 4986, 84–97, 2008.
  <https://doi.org/10.1007/978-3-540-68351-3_8>, et "The Poly1305-AES Message-Authentication Code". *FSE 2005*, LNCS 3557,
  32–49. <https://doi.org/10.1007/11502760_3>. XSalsa20 et Poly1305, le chiffrement et la vérification de [crypto.Seal]
  et de [crypto.BoxSeal].
- Daniel J. Bernstein, Niels Duif, Tanja Lange, Peter Schwabe, Bo-Yin Yang. "High-speed high-security signatures".
  *Journal of Cryptographic Engineering* 2(2):77–89, 2012. <https://doi.org/10.1007/s13389-012-0027-1>. Ed25519 :
  [crypto.Sign] et [crypto.Verify].
- Jean-Philippe Aumasson, Samuel Neves, Zooko Wilcox-O'Hearn, Christian Winnerlein. "BLAKE2: Simpler, Smaller, Fast as
  MD5". *ACNS 2013*, LNCS 7954, 119–135. <https://doi.org/10.1007/978-3-642-38980-1_8>. [crypto.Blake2b], et les
  fingerprints (les empreintes) de `cesia.lock` et de `cesia upgrade`.
- Alex Biryukov, Daniel Dinu, Dmitry Khovratovich. "Argon2: New Generation of Memory-Hard Functions for Password Hashing
  and Other Applications". *IEEE EuroS&P 2016*, 292–302. <https://doi.org/10.1109/EuroSP.2016.31>. Argon2id, le hash de
  [crypto.HashPassword].
- NIST. "Secure Hash Standard (SHS)", FIPS PUB 180-4, 2015. <https://doi.org/10.6028/NIST.FIPS.180-4>. SHA-256 et
  SHA-512 : [crypto.Sha256], [crypto.Sha512].
- H. Krawczyk, M. Bellare, R. Canetti. "HMAC: Keyed-Hashing for Message Authentication", RFC 2104, 1997.
  <https://www.rfc-editor.org/rfc/rfc2104>. [crypto.HmacSha256].

## Éditeurs

- Microsoft. Language Server Protocol Specification 3.17.
  <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>. Ce que parle
  `cesia lsp`, les positions comptées en code units UTF-16 (les unités de 16 bits du codage UTF-16), comme elle le dit :
  voir [Éditeurs](editors.md).
