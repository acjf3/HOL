(* ========================================================================= *)
(* KEEPING TRACK OF TERM ORDERING CONSTRAINTS                                *)
(* The underlying term order is the Knuth-Bendix order                       *)
(* Created by Joe Hurd, November 2002                                        *)
(* ========================================================================= *)

signature mlibTermorder =
sig

type 'a pp = 'a mlibUseful.pp
type term  = mlibTerm.term
type subst = mlibSubst.subst

(* Parameters *)
type parameters =
  {weight     : string * int -> int,
   precedence : (string * int) * (string * int) -> order,
   stickiness : int,               (* How long we keep the inequations: 0..2 *)
   precision  : int}      (* How closely we approximate the term order: 0..1 *)

val defaults          : parameters
val update_stickiness : (int -> int) -> parameters -> parameters
val update_precision  : (int -> int) -> parameters -> parameters

(* The termorder type *)
type termorder

(*  Basic operations *)
val empty    : parameters -> termorder
val null     : termorder -> bool
val vars     : termorder -> string list
val add_leqs : (term * term) list -> termorder -> termorder
val subst    : subst -> termorder -> termorder
val merge    : termorder -> termorder -> termorder

(* Query *)
val consistent : termorder -> termorder option
val subsumes   : termorder -> termorder -> bool
val compare    : termorder -> term * term -> order option

(* Pretty-printing *)
val pp_termorder : termorder pp

end
