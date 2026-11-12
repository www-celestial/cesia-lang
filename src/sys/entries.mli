(** The files of the cache of loaded packages, in [$XDG_CACHE_HOME/cesia/load], else [~/.cache/cesia/load]. The folder is
    made for the person alone, 0700, and used only if it is theirs alone; an entry is a file of theirs that no one else can
    read or write, 0600, read only if it is no link and still the file looked at, written beside under a new name, then
    renamed over the old one. Every failure is silent: the package then loads without the cache. *)

(** The store of this build, for {!Cesia.Cache.store}. Nothing is looked at before the first entry is read or written. *)
val store : string -> Cesia.Cache.store

(** Past [limit] bytes of entries, the ones used least lately go, down to half of it; temporary files that a run cut short
    left go after a day. Run once by a run that writes. *)
val prune : limit:int -> string -> unit

(** At the end of a run, [save] runs in a copy of the process that the end doesn't wait for: the run ends as soon as
    without a cache. The copy closes every descriptor of the program before anything else, puts its input and output on
    /dev/null, leaves its session, takes none of its signal handlers and ends within 10 s, without running the program's
    end a second time. A run killed, a system without
    [fork], or one with work still running on other cores, writes nothing; the next run reads its packages as without a
    cache. *)
val after : (unit -> unit) -> unit
