open Types

let frame_keys = Trie.names [| "Function"; "File"; "Line"; "Vars" |]
let var_keys = Trie.names [| "Name"; "Value" |]
let stop_keys = Trie.names [| "File"; "Line"; "Reason"; "Frames"; "Fiber"; "Error" |]

let record keys fields = Trie.record keys fields

let row items =
  let a = Array.of_list items in
  Array { rows = 1; cols = Array.length a; store = V a; a_owned = true; a_tip = true }

let read ctx base (ver : version) (s : slot) =
  if s.cell >= 0 then ctx.w.modules.(ver.owner.pm).cells.(s.cell)
  else begin
    let p = base + s.at in
    match s.sty with
    | TI -> Int ctx.i.(p)
    | TF -> Float (Float.Array.get ctx.f p)
    | _ -> ctx.v.(p)
  end

(* A variable not yet assigned has no value to show: its slot holds anything, except for those that can be read before
   assignment, which the prologue sets to Undef. *)
let vars ctx base (site : site) =
  match site.sver with
  | None -> []
  | Some ver ->
    let func = ver.owner.func in
    let known i = i < Bytes.length site.slive && Bytes.get site.slive i = '\001' in
    let visible i (s : slot) =
      (not (String.contains s.vname '#'))
      && (s.cell >= 0 || ((not site.shidden) && (known i || func.maybe_undef.(i))))
    in
    List.filter_map
      (fun i ->
         let s = ver.slots.(i) in
         if not (visible i s) then None
         else
           match read ctx base ver s with
           | Undef -> None
           | v -> Some (record var_keys [| Text s.vname; Value.share v |]))
      (List.init (Array.length ver.slots) Fun.id)

let frame ctx base at =
  let w = ctx.w in
  let site = Dynarray.get w.sites at in
  let path, _ = Dynarray.get w.files site.sfile in
  let name = if site.sfn = "" then "<file>" else site.sfn in
  record frame_keys
    [| Text name; Text path; Int (Pos.line site.spos); row (vars ctx base site) |]

(* From the current frame to the file, following the links. *)
let stop_value ctx s reason error =
  let w = ctx.w in
  (* The first frame of a fiber links back to the site of its spawn, which lives on another stack. *)
  let rec walk base at acc =
    let acc = frame ctx base at :: acc in
    let caller = Runtime.link_base ctx.i.(base) in
    if base = 0 || (ctx.fiber && caller = 0) then List.rev acc else walk caller ctx.i.(base + 1) acc
  in
  (* An error inside a library stops at the line of the program that called it: the line to change. *)
  let site = Dynarray.get w.sites (Runtime.user_site ctx s) in
  let path, _ = Dynarray.get w.files site.sfile in
  let error = match error with Some text -> Text text | None -> Missing in
  record stop_keys [| Text path; Int (Pos.line site.spos); Text reason; row (walk ctx.b s []); Int ctx.id; error |]

(* Native code runs no hook: after a stop, which may have set a breakpoint or asked for steps, it all goes back to the
   interpreter, as after a reload, and becomes native again once hot, if the debugger lets it run (Tier). *)
let back_to_interpreter w =
  if Option.is_some !Tier.jit then begin
    w.reloads <- w.reloads + 1;
    Compile.retire_all w
  end

(* The debugger runs on the same ctx, just above what is alive in the current frame. *)
let stop ?error ctx s reason =
  let w = ctx.w in
  let d = w.debug in
  let value = stop_value ctx s reason error in
  let base = (Dynarray.get w.sites s).soff in
  d.stopped <- true;
  ctx.site <- s;
  (* A wrong answer is an error of the debugger, which doesn't stop again. *)
  Fun.protect
    ~finally:(fun () -> d.stopped <- false)
    (fun () ->
       let answer = Compile.call_value ctx ~base d.on_stop [| value |] in
       ctx.site <- s;
       back_to_interpreter w;
       d.mode <-
         (match answer with
          | Text "continue" -> Running
          | Text "step" -> Stepping
          | Text "next" -> Until (Runtime.frames ctx)
          | Text "out" -> Until (Runtime.frames ctx - 1)
          | v -> Runtime.fail ctx Type (Messages.bad_answer (Value.describe v))))

let same_file path file =
  String.equal (Runtime.normalize path) (Runtime.normalize file)
  || ((not (String.contains file '/')) && String.equal (Filename.basename path) file)

let armed w file line =
  let path, _ = Dynarray.get w.files file in
  List.exists (fun (f, l, _) -> l = line && same_file path f) w.debug.breaks

let marked w s =
  let site = Dynarray.get w.sites s in
  armed w site.sfile (Pos.line site.spos)

let hook ctx s first =
  let w = ctx.w in
  let d = w.debug in
  if not d.stopped then begin
    let site = Dynarray.get w.sites s in
    let line = Pos.line site.spos in
    let path, _ = Dynarray.get w.files site.sfile in
    (* A line with several statements stops once on its breakpoint, at its first one. *)
    let on_break =
      first && List.exists (fun (f, l, c) -> l = line && same_file path f && (c = "" || d.test ctx s c)) d.breaks
    in
    if on_break then stop ctx s "break"
    else
      match d.mode with
      | Starting -> stop ctx s "start"
      | Stepping -> stop ctx s "step"
      | Until depth -> if Runtime.frames ctx <= depth then stop ctx s "step"
      | Running -> ()
  end

(* A panic stops where it happens, with every variable, before it leaves: but in the debugger itself. *)
let on_error ctx text =
  let w = ctx.w in
  if (not w.debug.stopped) && ctx.site >= 0 && ctx.site < Dynarray.length w.sites then stop ~error:text ctx ctx.site "error"

let hooks_compiled w = w.hook_count

let line_arg ctx name v =
  match v with
  | Int i -> i
  | _ -> Runtime.fail ctx Type (Messages.want_int name (Value.describe v))

(* One breakpoint per line: a new condition replaces the one before. *)
let set_break ctx (a : t array) =
  let d = ctx.w.debug in
  let file = Native.text_arg ctx "SetBreak" a.(0) and line = line_arg ctx "SetBreak" a.(1) in
  let cond = if Array.length a > 2 then Native.text_arg ctx "SetBreak" a.(2) else "" in
  d.breaks <- (file, line, cond) :: List.filter (fun (f, l, _) -> f <> file || l <> line) d.breaks;
  d.stamp <- d.stamp + 1;
  (* Set from the prompt while the program runs, native code may hold that line. *)
  back_to_interpreter ctx.w;
  Missing

let clear_break ctx (a : t array) =
  let d = ctx.w.debug in
  let file = Native.text_arg ctx "ClearBreak" a.(0) and line = line_arg ctx "ClearBreak" a.(1) in
  d.breaks <- List.filter (fun (f, l, _) -> f <> file || l <> line) d.breaks;
  d.stamp <- d.stamp + 1;
  Missing

let break_keys = Trie.names [| "File"; "Line"; "Condition" |]

let breaks ctx _ =
  row
    (List.rev_map
       (fun (f, l, c) -> record break_keys [| Text f; Int l; (if c = "" then Missing else Text c) |])
       ctx.w.debug.breaks)

(* The watches live with the program, as the breakpoints: a debugger keeps nothing from one stop to the next. *)
let watch ctx (a : t array) =
  let d = ctx.w.debug and code = Native.text_arg ctx "Watch" a.(0) in
  if not (List.mem code d.watches) then d.watches <- d.watches @ [ code ];
  Missing

let unwatch ctx (a : t array) =
  let d = ctx.w.debug and code = Native.text_arg ctx "Unwatch" a.(0) in
  d.watches <- List.filter (fun c -> c <> code) d.watches;
  Missing

(* A command line into words: the core has no text functions. A number becomes an integer. *)
let words ctx (a : t array) =
  let word w = match int_of_string_opt w with Some i -> Int i | None -> Text w in
  let spaced = String.map (fun c -> if c = '\t' || c = '\r' then ' ' else c) (Native.text_arg ctx "Words" a.(0)) in
  row (List.map word (List.filter (fun w -> w <> "") (String.split_on_char ' ' spaced)))

let natives =
  [ "SetBreak", Native.nat ~perm:Debug ~params:[| "file"; "line"; "condition" |] "SetBreak" 2 3 set_break;
    "ClearBreak", Native.nat ~perm:Debug "ClearBreak" 2 2 clear_break;
    "Breaks", Native.nat ~perm:Debug "Breaks" 0 0 breaks;
    "Watch", Native.nat ~perm:Debug ~params:[| "code" |] "Watch" 1 1 watch;
    "Unwatch", Native.nat ~perm:Debug ~params:[| "code" |] "Unwatch" 1 1 unwatch;
    "Watches", Native.nat ~perm:Debug "Watches" 0 0 (fun ctx _ -> row (List.map (fun c -> Text c) ctx.w.debug.watches));
    "Words", Native.nat "Words" 1 1 words ]
