(* ========================================================================= *)
(* SOME SAMPLE PROBLEMS TO TEST PROOF PROCEDURES                             *)
(* Created by Joe Hurd, September 2001                                       *)
(* Partly ported from the CAML-Light code accompanying John Harrison's book  *)
(* ========================================================================= *)

signature mlibProblem =
sig

type 'a quotation = 'a frag list
type 'a problem   = {name : string, comment : string, goal : 'a quotation}
type 'a set       = {name : string, blurb : string, probs : 'a problem list}

(* Accessing individual problems *)
val get : (unit -> 'a set) -> string -> 'a quotation

(* The master collections *)
val nonequality : unit -> 'a set
val equality    : unit -> 'a set
val tptp        : unit -> 'a set
val hol         : unit -> 'a set
val puzzle      : unit -> 'a set

(* Compilations *)
val nothing         : unit -> 'a set
val instant         : unit -> 'a set
val quick           : unit -> 'a set
val std             : unit -> 'a set
val meson_benchmark : unit -> 'a set

end
