(** What a running server tells of itself: [std/log], a JSON object per line, and [std/metrics], the counters and
    histograms that Prometheus reads. *)
open Cesia

(** [log.Info], [log.Warn] and [log.Error]. *)
val log_natives : (string * Types.t) list

(** [metrics.Add], [metrics.Observe] and [metrics.Text], with their own counts: one set for each program. *)
val natives : unit -> (string * Types.t) list

(** std/otel's hooks: [Some (world, f)] once its [onLog] or [onEngine] set them. *)
val log_hook : (Types.world * Types.t) option ref
val engine_hook : (Types.world * Types.t) option ref

(** std/otel's private natives: [context], [setContext], [onLog], [onEngine]. *)
val otel_natives : (string * Types.t) list
