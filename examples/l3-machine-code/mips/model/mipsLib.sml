(* mipsLib - generated by L<3> - Fri Jun 21 13:50:38 2013 *)
structure mipsLib :> mipsLib =
struct

open HolKernel boolLib bossLib
open utilsLib mipsTheory

val () = (numLib.prefer_num (); wordsLib.prefer_word ())

fun mips_compset thms =
   utilsLib.theory_compset (thms, mipsTheory.inventory)

end