(** The engine of std/quad: QUADPACK's adaptive integration, QAGS, QAGP and QAGI with Wynn's epsilon algorithm, as the
    private native [quad.engine], which calls the function to integrate back. *)

val natives : (string * Types.t) list
