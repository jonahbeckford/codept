type format =
  | Sexp
  | Json
  | Sexp2

type reader = {
  sign: format -> string -> Module.t list option;
  m2l: format -> Fault.Policy.t -> Read.kind -> string -> Namespaced.t -> Unit.s;
  findlib: Common.task -> Findlib.query -> Common.task ;
  env: Module.dict
}

type writer = {
  sign: format -> string -> Format.formatter -> Module.t list -> unit;
  m2l: format -> (Read.kind * string) -> Format.formatter -> M2l.t -> unit
}

type t = {
  reader: reader;
  writer: writer;
}

module Findlib = struct
(** Small import *)
let add_ppx ppx =
  let first_ppx = Compenv.first_ppx in
  first_ppx := ppx :: !first_ppx

let lib (task:Common.task ref) f =
  task := { !task with libs = f :: (!task).libs }

let expand task query =
  let task = ref task in
  let result = Findlib.process query in
  Option.iter (fun pp -> Clflags.preprocessor := Some pp) result.pp;
  List.iter (lib task) result.libs; List.iter add_ppx result.ppxs;
  !task
end

let parse_sig lexbuf=
  Sexp.( (list Module.sexp).parse )
  @@ Sexp_parse.many Sexp_lex.main
  @@ lexbuf

let read_sigfile _ filename =
  let chan = open_in filename in
  let lexbuf = Lexing.from_channel chan in
  let sigs = parse_sig lexbuf in
  close_in chan;
  sigs


let sm2l = { Scheme.title = "codept/m2l/0.10";
            description = "module level ocaml file skeleton";
            sch = M2l.sch
          }

let ssign = { Scheme.title = "codept/sig/0.10";
             description = "module level ocaml signature";
             sch = Array Module.sch
           }

let minify ppf =
  let f = Format.pp_get_formatter_out_functions ppf () in
  let space_needed = ref false in
  let out_string s start stop =
    let special c =
      match c with
      | '(' | ',' |'{' | '"' |'[' | ')'| ']'| '}' -> true
      | _ -> false in
    if !space_needed && not (special s.[start]) then
      f.out_string " " 0 1;
    f.out_string s start stop;
    space_needed := not (special s.[stop-1]) in
  let basic =
    { f with Format.out_newline = (fun () -> ());
             out_spaces = (fun _ -> ());
             out_string } in
  Format.pp_set_formatter_out_functions ppf basic;
  Format.kfprintf (fun _ -> Format.pp_set_formatter_out_functions ppf f;
                    Format.pp_flush_formatter ppf) ppf

let direct = {
  reader = {
    sign = read_sigfile;
    m2l = (fun _ -> Unit.read_file);
    env = Name.Map.empty;
    findlib = Findlib.expand
  };
  writer = {
    m2l =  (fun format _filename ppf m2l ->
        match format with
        | Sexp -> Pp.fp ppf  "%a@." Sexp.pp (M2l.sexp.embed m2l)
        | Json -> minify ppf "%a@.\n" (Scheme.json sm2l) m2l
        | Sexp2 -> minify ppf "%a@.\n" (Scheme.sexp sm2l) m2l

      );
    sign =
      (fun format _ ppf (mds: Module.t list) ->
         match format with
         | Sexp ->
           mds
           |> Sexp.( embed @@ list Module.sexp)
           |> Pp.fp ppf "@[%a@]@." Sexp.pp
         | Sexp2 -> minify ppf "%a@.\n" (Scheme.sexp ssign) mds
         | Json -> minify ppf "%a@.\n" (Scheme.json ssign) mds
      )
  }
}
