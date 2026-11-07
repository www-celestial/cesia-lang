(** What a running server tells of itself: [std/log], a JSON object per line, and [std/metrics], the counters and
    histograms that Prometheus reads. *)
open Cesia

(** [log.Info], [log.Warn] and [log.Error]. *)
val log_natives : (string * Types.t) list

(** [metrics.Add], [metrics.Observe] and [metrics.Text], with their own counts: one set for each program. *)
val natives : unit -> (string * Types.t) list
