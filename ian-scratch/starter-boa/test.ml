open Compile
open Runner
open Printf
open OUnit2
open Pretty
open Exprs

(* Runs a function true if throws correct exception *)
let tbind_except (name : string) (func : (unit -> unit)) (expected_msg : string) = name>::fun _ ->
  try (func() ; assert false) with
    | BindingError s -> assert_equal s expected_msg
	| _ -> assert false
;;

(* Runs a program, given as a source string, and compares its output to expected *)
let t (name : string) (program : string) (expected : string) = name>::test_run program name expected;;

(* Runs a program, given as an ANFed expr, and compares its output to expected *)
let ta (name : string) (program : tag expr) (expected : string) = name>::test_run_anf program name expected;;

(* Runs a program, given as a source string, and compares its error to expected *)
let te (name : string) (program : string) (expected_err : string) = name>::test_err program name expected_err;;

(* Transforms a program into ANF, and compares the output to expected *)
let tanf (name : string) (program : 'a expr) (expected : unit expr) = name>::fun _ ->
  assert_equal expected (anf (tag program)) ~printer:string_of_expr;;

(* Checks if two strings are equal *)
let teq (name : string) (actual : string) (expected : string) = name>::fun _ ->
  assert_equal expected actual ~printer:(fun s -> s);;

(* Runs a program, given as the name of a file in the input/ directory, and compares its output to expected *)
let tprog (filename : string) (expected : string) = filename>::test_run_input filename expected;;

(* Runs a program, given as the name of a file in the input/ directory, and compares its error to expected *)
let teprog (filename : string) (expected : string) = filename>::test_err_input filename expected;;

let forty_one = "41";;

let forty_one_a = (ENumber(41L, ()))

let suite1 =
"check_scope_suite">:::
 [

  (*tbind_except "test1" (fun () -> (ignore (check_scope (parse_string "scratch" "(add1 1)")))) "saDSA"*)

   te "check_scope_err1" "x" "unbound symbol x";

  ]
;;

let suite =
"suite">:::
 [

  tanf "forty_one_anf"
       (ENumber(41L, ()))
       forty_one_a;

  (* For CS4410 students, with unnecessary let-bindings *)
  tanf "prim1_anf_4410"
       (EPrim1(Sub1, ENumber(55L, ()), ()))
       (ELet(["unary_1", EPrim1(Sub1, ENumber(55L, ()), ()), ()],
             EId("unary_1", ()),
             ()));

  (* For CS6410 students, with optimized let-bindings *)
  tanf "prim1_anf_6410"
       (EPrim1(Sub1, ENumber(55L, ()), ()))
       (EPrim1(Sub1, ENumber(55L, ()), ()));

  ta "forty_one_run_anf" (tag forty_one_a) "41";
 
  t "forty_one" forty_one "41";


  tprog "test1.boa" "3";
      
    (* Some useful if tests to start you off *)

  t "if1" "if 5: 4 else: 2" "4";
  t "if2" "if 0: 4 else: 2" "2";

  ]
;;


let () =
  run_test_tt_main suite1
  (* run_test_tt_main suite *)
;;
