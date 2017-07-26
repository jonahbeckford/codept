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

let parse_sig format lexbuf=
  match format with
  | Sexp -> Sexp.( (list Module.sexp).parse )
    @@ Sexp_parse.many Sexp_lex.main
    @@ lexbuf
  | Json | Sexp2 ->
    Scheme.retype (Array Module.sch) @@ Sparser.main Slex.main lexbuf

let read_sigfile fmt filename =
  let chan = open_in filename in
  let lexbuf = Lexing.from_channel chan in
  let sigs = parse_sig fmt lexbuf in
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
        | Json -> Scheme.minify ppf "%a@.\n" (Scheme.json sm2l) m2l
        | Sexp2 ->  Scheme.minify ppf "%a@.\n" (Scheme.sexp sm2l) m2l

      );
    sign =
      (fun format _ ppf (mds: Module.t list) ->
         match format with
         | Sexp ->
           mds
           |> Sexp.( embed @@ list Module.sexp)
           |> Pp.fp ppf "@[%a@]@." Sexp.pp
         | Sexp2 ->  Scheme.minify ppf "%a@.\n" (Scheme.sexp ssign) mds
         | Json ->  Scheme.minify ppf "%a@.\n" (Scheme.json ssign) mds
      )
  }
}
