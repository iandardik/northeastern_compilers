open Printf
open Exprs
open Pretty
open List

let rec is_anf (e : 'a expr) : bool =
  match e with
  | EPrim1(_, e, _) -> is_imm e
  | EPrim2(_, e1, e2, _) -> is_imm e1 && is_imm e2
  | ELet(binds, body, _) ->
     List.for_all (fun (_, e, _) -> is_anf e) binds
     && is_anf body
  | EIf(cond, thn, els, _) -> is_imm cond && is_anf thn && is_anf els
  | _ -> is_imm e
and is_imm e =
  match e with
  | ENumber _ -> true
  | EId _ -> true
  | _ -> false
;;

(* Does a binding for this symbol exist in bindings? *)
let rec bindings_contain (msym : string) (bindings : 'a bind list) : bool =
  match bindings with
  | [] -> false
  | (sym, _, _) :: tail ->
      if sym = msym
      then true
      else bindings_contain msym tail
;;


(* PROBLEM 1 *)
(* This function should encapsulate the binding-error checking from Boa *)
exception BindingError of string
let check_scope (e : (Lexing.position * Lexing.position) expr) : unit =
  let rec helper (e : (Lexing.position * Lexing.position) expr) (env : string list) : unit =
    match e with
    | ELet (bindings, expr, _) ->
        let newenv = bindings_helper bindings env
        in  helper expr newenv
    | EPrim1 (prim1, expr, _) ->
        helper expr env
    | EPrim2 (prim2, lhs, rhs, _) ->
        helper lhs env;
        helper rhs env
    | EIf (cond, tru, fals, _) ->
        helper cond env;
        helper tru env;
        helper fals env
    | ENumber (n, _) -> () (* No issue with scope here *)
    | EId (sym, pos) ->
        if List.mem sym env
        then () (* No issue with scope here *)
        else raise (BindingError(sprintf "Unbound symbol %s at %s" sym (string_of_pos pos)))
  and bindings_helper
        (bindings : (Lexing.position * Lexing.position) bind list)
        (env : string list)
       : string list =
    match bindings with
    | [] -> env
    | (sym, expr, pos) :: tail ->
        if (bindings_contain sym tail)
        then raise (BindingError(sprintf "Multiple bindings of %s, first at %s" sym (string_of_pos pos)))
        else
          helper expr env;
          bindings_helper tail (sym :: env)
  in helper e []
  
type tag = int
(* PROBLEM 2 *)
(* This function assigns a unique tag to every subexpression and let binding *)
let tag (e : 'a expr) : tag expr =
  let rec helper (e : 'a expr) (t : tag) : tag expr * tag =
    match e with
    | ELet(bindings, expr, _) ->
        let (tbind, bt) = bind_helper bindings t in
        let (texpr, et) = helper expr bt in
        (ELet(tbind, texpr, et), et+1)
    | EPrim1(prim1, expr, _) ->
        let (texpr, et) = helper expr t in
        (EPrim1(prim1, texpr, et), et+1)
    | EPrim2(prim2, lhs, rhs, _) ->
        let (tlhs, lt) = helper lhs t in
        let (trhs, rt) = helper rhs lt in
        (EPrim2(prim2, tlhs, trhs, rt), rt+1)
    | EIf(cond, tru, fals, _) ->
        let (tcond, ct) = helper cond t in
        let (ttru, tt) = helper tru ct in
        let (tfals, ft) = helper fals tt in
        (EIf(tcond, ttru, tfals, ft), ft+1)
    | ENumber(n, _) ->
        (ENumber(n, t), t+1)
    | EId(sym, _) ->
        (EId(sym, t), t+1)
  and bind_helper (bindings : 'a bind list) (t : tag) : tag bind list * tag =
    match bindings with
    | [] -> ([], t)
    | (sym, expr, _) :: tail ->
        let (texpr, et) = helper expr t in
        let tbind = (sym, texpr, et) in
        let (ttail, bt) = bind_helper tail (et+1) in
        (tbind :: ttail, bt)
  in let (te, _) = helper e 0
  in te
;;

(* This function removes all tags, and replaces them with the unit value.
   This might be convenient for testing, when you don't care about the tag info. *)
let rec untag (e : 'a expr) : unit expr =
  match e with
  | EId(x, _) -> EId(x, ())
  | ENumber(n, _) -> ENumber(n, ())
  | EPrim1(op, e, _) ->
     EPrim1(op, untag e, ())
  | EPrim2(op, e1, e2, _) ->
     EPrim2(op, untag e1, untag e2, ())
  | ELet(binds, body, _) ->
     ELet(List.map(fun (x, b, _) -> (x, untag b, ())) binds, untag body, ())
  | EIf(cond, thn, els, _) ->
     EIf(untag cond, untag thn, untag els, ())
;;

(* PROBLEM 3 *)
let rec lookup_rename (x : string) (env : (string * string) list) : string =
  match env with
  | [] -> failwith (sprintf "Failed to lookup %s" x) (* should never happen, make sure to check_scope and tag first *)
  | (k, v) :: tail ->
      if k = x
      then v
      else lookup_rename x tail
;;

let rename (e : tag expr) : tag expr =
  let rec help (env : (string * string) list) (e : tag expr) : tag expr =
    match e with
    | EId(x, tag) -> EId((lookup_rename x env), tag)
    | ELet(binds, body, tag) ->
        let (newbinds, newenv) = bind_help env binds in
        let newbody = help newenv body in
        ELet(newbinds, newbody, tag)
    | ENumber(n, tag) -> ENumber(n, tag)
    | EPrim1(op, e, t) -> EPrim1(op, (help env e), t)
    | EPrim2(op, e1, e2, t) -> EPrim2(op, (help env e1), (help env e2), t)
    | EIf(cond, thn, els, t) -> EIf((help env cond), (help env thn), (help env els), t)
  and bind_help (env : (string * string) list) (binds : tag bind list) : tag bind list * ((string * string) list) =
    match binds with
    | [] -> (binds, env)
    | (sym, expr, t) :: tail ->
        let newexpr = help env expr in
        let newsym = sprintf "%s#%d" sym t in
        let (newbinds, newenv) = bind_help ((sym, newsym) :: env) tail in
        ((newsym, newexpr, t) :: newbinds, newenv)
  in help [] e
;;


(* PROBLEM 4 & 5 *)
(* This function converts a tagged expression into an untagged expression in A-normal form *)

(* Convenience type for our context to use when ANF-ing: maps symbols to expressions *)
type context = (string * unit expr) list


(* Combines the intermediate result of anf into a single final expr (ie. consumes context into it) *)
let finish_anf (ans : unit expr) (ctx : context) : unit expr =
  List.fold_right (fun (sym, expr) acc -> ELet([(sym, expr, ())], acc, ())) ctx ans


(* Convert an expr to ANF. *)
let anf (e : tag expr) : unit expr =
  (* Converts an expr to ANF, while tracking context (see is_anf at top). *)
  let rec helpC (e : tag expr) : (unit expr * context) =
    match e with
    | EId(x, tag) -> (EId(x, ()), [])
    | ELet(binds, body, tag) ->
        let bctx = (bind_helper binds []) in
        let (newbody, newctx) = (helpC body) in
        (newbody, bctx @ newctx)
    | ENumber(n, tag) -> (ENumber(n, ()), [])
    | EPrim1(op, e, t) ->
        let (newe, newctx) = (helpI e) in
        (EPrim1(op, newe, ()), newctx)
    | EPrim2(op, e1, e2, t) ->
        let (newe1, newctx1) = (helpI e1) in
        let (newe2, newctx2) = (helpI e2) in
        (EPrim2(op, newe1, newe2, ()), newctx1 @ newctx2)
    | EIf(cond, thn, els, t) ->
        let (anfcond, condctx) = (helpI cond) in
        let (anfthn, thnctx) = (helpC thn) in
        let (anfels, elsctx) = (helpC els) in
        (EIf(anfcond, anfthn, anfels, ()), condctx @ thnctx @ elsctx)

  (* Converts an expr to an Immediate, while tracking context (see is_imm at top). *)
  and helpI (e : tag expr) : (unit expr * context) =
    match e with
    | EId(x, tag) -> (EId(x, ()), [])
    | ELet(binds, body, tag) ->
        let bctx = (bind_helper binds []) in
        let (newbody, newctx) = (helpI body) in
        (newbody, bctx @ newctx)
    | ENumber(n, tag) -> (ENumber(n, ()), [])
    | EPrim1(op, e, t) ->
        let (newe, newctx) = (helpI e) in
        let tmpname = sprintf "$prim1_%d" t in
        (EId(tmpname, ()), newctx @ [(tmpname, EPrim1(op, newe, ()))])
    | EPrim2(op, e1, e2, t) ->
        let (newe1, newctx1) = (helpI e1) in
        let (newe2, newctx2) = (helpI e2) in
        let tmpname = sprintf "$prim2_%d" t in
        (EId(tmpname, ()), newctx1 @ newctx2 @ [(tmpname, EPrim2(op, newe1, newe2, ()))])
    | EIf(cond, thn, els, t) ->
        let (anfif, ifctx) = (helpC e) in
        let tmpname = sprintf "$if_%d" t in
        (EId(tmpname, ()), ifctx @ [(tmpname, anfif)])

  (* Helper for ANF-ing a bindings list and updating the context along the way. *)
  and bind_helper (binds : tag bind list) (ctx : context) : context =
    match binds with
    | [] -> ctx
    | (sym, expr, t) :: tail ->
        let (newexpr, exprctx) = (helpC expr) in
        let tailctx = (bind_helper tail ctx) in
        exprctx @ [(sym, newexpr)] @ tailctx
  in
    let (a, c) = (helpC e) in (finish_anf a c)


(* Helper functions *)
let r_to_asm (r : reg) : string =
  match r with
  | RAX -> "rax"
  | RSP -> "rsp"

let arg_to_asm (a : arg) : string =
  match a with
  | Const(n) -> sprintf "QWORD %Ld" n
  | Reg(r) -> r_to_asm r
  | RegOffset(n, r) ->
     if n >= 0 then
       sprintf "[%s+%d]" (r_to_asm r) (word_size * n)
     else
       sprintf "[%s-%d]" (r_to_asm r) (-1 * word_size * n)

let i_to_asm (i : instruction) : string =
  match i with
  | IMov(dest, value) ->
     sprintf "  mov %s, %s" (arg_to_asm dest) (arg_to_asm value)
  | IAdd(dest, to_add) ->
     sprintf "  add %s, %s" (arg_to_asm dest) (arg_to_asm to_add)
  | IRet ->
     "  ret"
  | ISub(dest, sub) ->
     sprintf "  sub %s, %s" (arg_to_asm dest) (arg_to_asm sub)
  | IMul(dest, mul) ->
     sprintf "  imul %s, %s" (arg_to_asm dest) (arg_to_asm mul)
  | ILabel(lbl) ->
     sprintf "%s:" lbl
  | ICmp(lhs, rhs) ->
     sprintf "  cmp %s, %s" (arg_to_asm lhs) (arg_to_asm rhs)
  | IJne(lbl) ->
     sprintf "  jne %s" lbl
  | IJe(lbl) ->
     sprintf "  je %s" lbl
  | IJmp(lbl) ->
     sprintf "  jmp %s" lbl

let to_asm (is : instruction list) : string =
  List.fold_left (fun s i -> sprintf "%s\n%s" s (i_to_asm i)) "" is

let rec find ls x =
  match ls with
  | [] -> failwith (sprintf "Name %s not found" x)
  | (y,v)::rest ->
     if y = x then v else find rest x

(* PROBLEM 5 *)
(* This function actually compiles the tagged ANF expression into assembly *)
(* The si parameter should be used to indicate the next available stack index for use by Lets *)
(* The env parameter associates identifier names to stack indices *)
let rec compile_expr (e : tag expr) (si : int) (env : (string * int) list) : instruction list =
  match e with
  | ENumber(n, _) -> [ IMov(Reg(RAX), compile_imm e env) ]
  | EId(x, _) -> [ IMov(Reg(RAX), compile_imm e env) ]
  | EPrim1(op, e, _) ->
     let e_reg = compile_imm e env in
     begin match op with
     | Add1 -> [
         IMov(Reg(RAX), e_reg);
         IAdd(Reg(RAX), Const(1L))
       ]
     | Sub1 -> [
         IMov(Reg(RAX), e_reg);
         IAdd(Reg(RAX), Const(Int64.minus_one))
       ]
     end
  | EPrim2(op, left, right, _) ->
      let lhs_reg = compile_imm left env in
      let rhs_reg = compile_imm right env in
      begin match op with
      | Plus -> [
          IMov(Reg(RAX), lhs_reg);
          IAdd(Reg(RAX), rhs_reg);
        ]
      | Minus -> [
          IMov(Reg(RAX), lhs_reg);
          ISub(Reg(RAX), rhs_reg);
        ]
      | Times -> [
          IMov(Reg(RAX), lhs_reg);
          IMul(Reg(RAX), rhs_reg);
        ]
      end
  | EIf(cond, thn, els, tag) ->
      let cond_reg = compile_imm cond env in
      let compiled_thn = compile_expr thn si env in
      let compiled_els = compile_expr els si env in
      let thn_lbl = sprintf "if_then_%d" tag in
      let els_lbl = sprintf "if_else_%d" tag in
      let done_lbl = sprintf "if_done_%d" tag in
        [
          IMov(Reg(RAX), cond_reg);
          ICmp(Reg(RAX), Const(0L));
          IJe(els_lbl);
          ILabel(thn_lbl);
        ]
      @ compiled_thn
      @ [
          IJmp(done_lbl);
          ILabel(els_lbl);
        ]
      @ compiled_els
      @ [ILabel(done_lbl)]
  | ELet([id, e, _], body, _) ->
      let compiled_e = compile_expr e si env in
      let newenv = (id, si) :: env in
      compiled_e
      @ [IMov(RegOffset(~-1*si, RSP), Reg(RAX))]
      @ compile_expr body (si+1) newenv
  | _ -> failwith "Impossible: Not in ANF"
and compile_imm e env : arg =
  match e with
  | ENumber(n, _) -> Const(n)
  | EId(x, _) -> RegOffset(~-(find env x), RSP)
  | _ -> failwith "Impossible: not an immediate"


let compile_anf_to_string anfed =
  let prelude =
    "section .text
global our_code_starts_here
our_code_starts_here:" in
  let compiled = (compile_expr anfed 1 []) in
  let as_assembly_string = (to_asm (compiled @ [IRet])) in
  sprintf "%s%s\n" prelude as_assembly_string

    
let compile_to_string prog =
  check_scope prog;
  let tagged : tag expr = tag prog in
  let renamed : tag expr = rename tagged in
  let anfed : tag expr = tag (anf renamed) in
  (* printf "Prog:\n%s\n" (ast_of_expr prog); *)
  (* printf "Tagged:\n%s\n" (format_expr tagged string_of_int); *)
  (* printf "ANFed/tagged:\n%s\n" (format_expr anfed string_of_int); *)
  compile_anf_to_string anfed

