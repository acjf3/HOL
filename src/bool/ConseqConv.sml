(*===================================================================== *)
(* FILE          : ConseqConv.sml                                        *)
(* DESCRIPTION   : Infrastructure for 'Consequence Conversions'.         *)
(*                 A ConseqConv is a conversion that turns a term        *)
(*                 t into a theorem of the form "t' ==> t"               *)
(*                                                                       *)
(* AUTHORS       : Thomas Tuerk                                          *)
(* DATE          : July 3, 2008                                          *)
(* ===================================================================== *)


structure ConseqConv :> ConseqConv =
struct

(*
quietdec := true;
*)

open HolKernel Parse boolLib Drule ConseqConvTheory;

(*
quietdec := false;
*)



(*---------------------------------------------------------------------------
 * generalise a variable in an implication of ==>
 *
 *   A |- t1 v ==> t2 v
 * ---------------------------------------------
 *   A |- (!v. t1 v) ==> (!v. t2 v)
 *
 *---------------------------------------------------------------------------*)

fun GEN_IMP v thm =
  let
     val thm1 = GEN v thm;
     val thm2 = HO_MATCH_MP MONO_ALL thm1;
  in
     thm2
  end;

fun LIST_GEN_IMP vL thm =
   foldr (uncurry GEN_IMP) thm vL


(*---------------------------------------------------------------------------
 * Introduces EXISTS on both sides of an implication
 *
 *   A |- t1 v ==> t2 v
 * ---------------------------------------------
 *   A |- (?v. t1 v) ==> (?v. t2 v)
 *
 *---------------------------------------------------------------------------*)
fun EXISTS_INTRO_IMP v thm =
  let
     val thm1 = GEN v thm;
     val thm2 = HO_MATCH_MP boolTheory.MONO_EXISTS thm1;
  in
     thm2
  end;

fun LIST_EXISTS_INTRO_IMP vL thm =
   foldr (uncurry EXISTS_INTRO_IMP) thm vL


(*---------------------------------------------------------------------------
 * REFL for implications
 *
 * REFL_CONSEQ_CONV t = (t ==> t)
 *---------------------------------------------------------------------------*)
fun REFL_CONSEQ_CONV t = DISCH t (ASSUME t);


(*---------------------------------------------------------------------------
 * generalises a thm body and as well the ASSUMPTIONS
 *
 *   A |- body
 * ---------------------------------------------
 *   (!v. A) |- !v. body
 *
 *---------------------------------------------------------------------------*)

fun GEN_ASSUM v thm =
  let
    val assums = filter (fn t => mem v (free_vars t)) (hyp thm);
    val thm2 = foldl (fn (t,thm) => DISCH t thm) thm assums;
    val thm3 = GEN v thm2;
    val thm4 = foldl (fn (_,thm) => UNDISCH (HO_MATCH_MP MONO_ALL thm))
                     thm3 assums;
  in
    thm4
  end




(*Introduces allquantification for all free variables*)
val SPEC_ALL_TAC:tactic = fn (asm,t) =>
let
   val asm_vars = FVL asm empty_tmset;
   val t_vars = FVL [t] empty_tmset;
   val free_vars = HOLset.difference (t_vars,asm_vars);

   val free_varsL = HOLset.listItems free_vars;
in
   ([(asm,list_mk_forall (free_varsL,t))],
    fn thmL => (SPECL free_varsL (hd thmL)))
end;







(*---------------------------------------------------------------------------
 * A normal conversion converts a term t to a theorem of
 * the form t = t'. In contrast a CONSEQ_CONV converts it to
 * a theorem of the form t' ==> t, i.e. it tries to strengthen a boolean expression
 *---------------------------------------------------------------------------*)



(*---------------------------------------------------------------------------
 * Converts a conversion returning theorems of the form
 *    t' ==> t, t = t' or t
 * to a CONSEQ_CONV. Also some checks are performed that the resulting
 * theorem is really of the form t' ==> t with t being the original input
 * and t' not being equal to t
 *---------------------------------------------------------------------------*)

datatype CONSEQ_CONV_direction =
         CONSEQ_CONV_STRENGTHEN_direction
       | CONSEQ_CONV_WEAKEN_direction
       | CONSEQ_CONV_UNKNOWN_direction;

datatype CONSEQ_CONV_context =
         CONSEQ_CONV_NO_CONTEXT
       | CONSEQ_CONV_IMP_CONTEXT
       | CONSEQ_CONV_FULL_CONTEXT;

type conseq_conv = term -> thm;
type directed_conseq_conv = CONSEQ_CONV_direction -> conseq_conv;


(*---------------------------------------------------------------------------
 - Test cases
 ----------------------------------------------------------------------------

val t = ``x > 5``;
val thm1 = prove (``x > 6 ==> x > 5``, DECIDE_TAC);
val thm2 = prove (``x > 5 ==> x > 4``, DECIDE_TAC);
val thm3 = prove (``(x > 5) = (x >= 6)``, DECIDE_TAC);
val thm4 = prove (``(x > 5) = (x > 5)``, DECIDE_TAC);



CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_STRENGTHEN_direction thm1 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_WEAKEN_direction thm1 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_UNKNOWN_direction thm1 t

CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_STRENGTHEN_direction thm2 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_WEAKEN_direction thm2 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_UNKNOWN_direction thm2 t

CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_STRENGTHEN_direction thm3 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_WEAKEN_direction thm3 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_UNKNOWN_direction thm3 t

CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_STRENGTHEN_direction thm4 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_WEAKEN_direction thm4 t
CONSEQ_CONV_WRAPPER___CONVERT_RESULT CONSEQ_CONV_UNKNOWN_direction thm4 t


 ----------------------------------------------------------------------------*)

fun CONSEQ_CONV_WRAPPER___CONVERT_RESULT dir thm t =
let
   val thm_term = concl thm;
in
   if (aconv thm_term t) then
      CONSEQ_CONV_WRAPPER___CONVERT_RESULT dir (EQT_INTRO thm) t
   else if (is_imp_only thm_term) then
      let
         val (t1, t2) = dest_imp thm_term;
         val _ = if (aconv t1 t2) then raise UNCHANGED else ();

         val g' = if (aconv t2 t) then CONSEQ_CONV_STRENGTHEN_direction else
                  if (aconv t1 t) then CONSEQ_CONV_WEAKEN_direction else
                  raise UNCHANGED;
         val g'' = if (dir = CONSEQ_CONV_UNKNOWN_direction) then g' else dir;
         val _ = if not (g' = g'') then raise UNCHANGED else ();
      in
         (g'', thm)
      end
   else if (is_eq thm_term) then
      (dir,
        if ((lhs thm_term = t) andalso not (rhs thm_term = t)) then
           if (dir = CONSEQ_CONV_UNKNOWN_direction) then
              thm
           else if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
              snd (EQ_IMP_RULE thm)
           else
              fst (EQ_IMP_RULE thm)
        else raise UNCHANGED)
   else
      raise UNCHANGED
end;


fun CONSEQ_CONV_WRAPPER conv dir t =
let
   val _ = if (type_of t = bool) then () else raise UNCHANGED;
   val thm = conv dir t;
in
   snd (CONSEQ_CONV_WRAPPER___CONVERT_RESULT dir thm t)
end;


fun CHANGED_CHECK_CONSEQ_CONV conv t =
    let
       val thm = conv t;
       val (t1,t2) = dest_imp (concl thm) handle HOL_ERR _ =>
                     dest_eq (concl thm);
       val _ = if (aconv t1 t2) then raise UNCHANGED else ();
    in
       thm
    end;


(*like CHANGED_CONV*)
fun QCHANGED_CONSEQ_CONV conv t =
    conv t handle UNCHANGED => raise mk_HOL_ERR "bool" "ConseqConv" "QCHANGED_CONSEQ_CONV"

fun CHANGED_CONSEQ_CONV conv =
    QCHANGED_CONSEQ_CONV (CHANGED_CHECK_CONSEQ_CONV conv)


(*like ORELSEC*)
fun ORELSE_CONSEQ_CONV (c1:conv) c2 t =
    ((c1 t handle HOL_ERR _ => raise UNCHANGED) handle UNCHANGED =>
     (c2 t handle HOL_ERR _ => raise UNCHANGED));


(*like FIRST_CONV*)
fun FIRST_CONSEQ_CONV [] t = raise UNCHANGED
  | FIRST_CONSEQ_CONV ((c1:conv)::L) t =
    ORELSE_CONSEQ_CONV c1 (FIRST_CONSEQ_CONV L) t;




fun CONSEQ_CONV___GET_SIMPLIFIED_TERM thm t =
   if (concl thm = t) then T else
   let
      val (t1,t2) = dest_imp (concl thm) handle HOL_ERR _ =>
                    dest_eq (concl thm);
   in
      if (aconv t1 t) then t2 else t1
   end;


fun CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM NONE dir t = t
  | CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM (SOME thm) dir t = 
    if dir = CONSEQ_CONV_STRENGTHEN_direction then
       (fst (dest_imp (concl thm)))
    else
       (snd (dest_imp (concl thm)));


fun CONSEQ_CONV___GET_DIRECTION thm t =
   if (concl thm = t) then CONSEQ_CONV_UNKNOWN_direction else
   if (is_eq (concl thm)) then CONSEQ_CONV_UNKNOWN_direction else
   let
      val (t1,t2) = dest_imp (concl thm);
   in
      if (aconv t1 t) andalso (aconv t2 t) then CONSEQ_CONV_UNKNOWN_direction else
      if (aconv t2 t) then CONSEQ_CONV_STRENGTHEN_direction else
      if (aconv t1 t) then CONSEQ_CONV_WEAKEN_direction else
      raise UNCHANGED
   end;



(*---------------------------------------------------------------------------
 - Test cases
 ----------------------------------------------------------------------------

val t1 = ``x > 5``;
val t2 = ``x > 3``;
val t3 = ``x > 4``;

val thm1 = prove (``x > 5 ==> x > 4``, DECIDE_TAC);
val thm2 = prove (``x > 4 ==> x > 3``, DECIDE_TAC);

val thm3 = prove (``(x > 4) = (x >= 5)``, DECIDE_TAC);
val thm4 = prove (``(x >= 5) = (5 <= x)``, DECIDE_TAC);


val thm1 = prove (``X ==> T``, REWRITE_TAC[]);
val thm2 = prove (``T ==> T``, REWRITE_TAC[]);
val t1 = ``X:bool``

val thm1 =  prove (``(?r:'b. P (z:'a)) <=> P z``, PROVE_TAC[]);
val thm2 =  prove (``P (z:'a) ==> P z``, PROVE_TAC[]);
val t = ``(?r:'b. P (z:'a))``

THEN_CONSEQ_CONV___combine thm1 thm2 t



THEN_CONSEQ_CONV___combine thm1 thm2 t1
THEN_CONSEQ_CONV___combine thm2 thm1 t2

THEN_CONSEQ_CONV___combine thm1 thm3 t1
THEN_CONSEQ_CONV___combine thm3 thm4 t3

 ----------------------------------------------------------------------------*)

fun is_refl_imp t =
let
   val (l1,l2) = dest_imp_only t;
in
  (aconv l1 l2)
end handle HOL_ERR _ => false;

fun is_refl_eq t =
let
   val (l1,l2) = dest_eq t;
in
  (aconv l1 l2)
end handle HOL_ERR _ => false;

fun is_refl_imp_eq t = is_refl_imp t orelse is_refl_eq t;


fun THEN_CONSEQ_CONV___combine thm1 thm2 t =
  if (is_refl_imp_eq (concl thm1)) then thm2
  else if (is_refl_imp_eq (concl thm2)) then thm1
  else if (concl thm1 = t) then THEN_CONSEQ_CONV___combine (EQT_INTRO thm1) thm2 t
  else if (is_eq (concl thm1)) andalso (rhs (concl thm1) = (concl thm2)) then
     THEN_CONSEQ_CONV___combine thm1 (EQT_INTRO thm2) t
  else if (is_eq (concl thm1)) andalso (is_eq (concl thm2)) then
     TRANS thm1 thm2
  else
     let
        val d1 = CONSEQ_CONV___GET_DIRECTION thm1 t;
        val t2 = CONSEQ_CONV___GET_SIMPLIFIED_TERM thm1 t;
        val d2 = if not (d1 = CONSEQ_CONV_UNKNOWN_direction) then d1 else
                 CONSEQ_CONV___GET_DIRECTION thm2 t2;

        val thm1_imp = snd (CONSEQ_CONV_WRAPPER___CONVERT_RESULT d2 thm1 t)
                       handle UNCHANGED => REFL_CONSEQ_CONV t;
        val thm2_imp = snd (CONSEQ_CONV_WRAPPER___CONVERT_RESULT d2 thm2 t2)
                       handle UNCHANGED => REFL_CONSEQ_CONV t2;
     in
        if (d2 = CONSEQ_CONV_STRENGTHEN_direction) then
            IMP_TRANS thm2_imp thm1_imp
        else
            IMP_TRANS thm1_imp thm2_imp
     end



(*like THENC*)
fun THEN_CONSEQ_CONV (c1:conv) c2 t =
    let
       val thm0_opt = SOME (c1 t) handle HOL_ERR _ => NONE
                                        | UNCHANGED => NONE

       val t2 = if (isSome thm0_opt) then CONSEQ_CONV___GET_SIMPLIFIED_TERM (valOf thm0_opt) t else t;

       val thm1_opt = SOME (c2 t2) handle HOL_ERR _ => NONE
                                        | UNCHANGED => NONE
    in
       if (isSome thm0_opt) andalso (isSome thm1_opt) then
         THEN_CONSEQ_CONV___combine (valOf thm0_opt) (valOf thm1_opt) t else
       if (isSome thm0_opt) then valOf thm0_opt else
       if (isSome thm1_opt) then valOf thm1_opt else
       raise UNCHANGED
    end;


fun EVERY_CONSEQ_CONV [] t = raise UNCHANGED
  | EVERY_CONSEQ_CONV ((c1:conv)::L) t =
    THEN_CONSEQ_CONV c1 (EVERY_CONSEQ_CONV L) t;




fun CONSEQ_CONV___APPLY_CONV_RULE thm t conv =
let
   val r = CONSEQ_CONV___GET_SIMPLIFIED_TERM thm t;
   val r_thm = conv r;
in
   THEN_CONSEQ_CONV___combine thm r_thm t
end;





val FORALL_EQ___CONSEQ_CONV = HO_PART_MATCH (snd o dest_imp) forall_eq_thm;
val EXISTS_EQ___CONSEQ_CONV = HO_PART_MATCH (snd o dest_imp) exists_eq_thm;



   (*Like QUANT_CONV for CONSEQ_CONVS. Explicit versions
     for FORALL and EXISTS are exported, since they have
     to be handeled separately anyhow.*)

fun FORALL_CONSEQ_CONV conv t =
      let
         val (var, body) = dest_forall t;
         val thm_body = conv body;
         val thm = GEN var thm_body;
         val thm2 = if (is_eq (concl thm_body)) then
                        forall_eq_thm
                    else boolTheory.MONO_ALL;
         val thm3 = HO_MATCH_MP thm2 thm;
      in
         thm3
      end;

fun EXISTS_CONSEQ_CONV conv t =
      let
         val (var, body) = dest_exists t;
         val thm_body = conv body;
         val thm = GEN var thm_body;
         val thm2 = if (is_eq (concl thm_body)) then
                       exists_eq_thm
                    else boolTheory.MONO_EXISTS;
         val thm3 = HO_MATCH_MP thm2 thm;
      in
         thm3
      end;








fun QUANT_CONSEQ_CONV conv t =
    if (is_forall t) then
       FORALL_CONSEQ_CONV conv t
    else if (is_exists t) then
       EXISTS_CONSEQ_CONV conv t
    else
       NO_CONV t;


fun TRUE_CONSEQ_CONV t = SPEC t true_imp;
fun FALSE_CONSEQ_CONV t = SPEC t false_imp;

fun TRUE_FALSE_REFL_CONSEQ_CONV CONSEQ_CONV_STRENGTHEN_direction = FALSE_CONSEQ_CONV
    | TRUE_FALSE_REFL_CONSEQ_CONV CONSEQ_CONV_WEAKEN_direction = TRUE_CONSEQ_CONV
    | TRUE_FALSE_REFL_CONSEQ_CONV CONSEQ_CONV_UNKNOWN_direction = REFL



(*Like DEPTH_CONV for CONSEQ_CONVS. The conversion
  may generate theorems containing assumptions. These
  assumptions are propagated to the top level*)


fun CONSEQ_CONV_DIRECTION_NEGATE CONSEQ_CONV_UNKNOWN_direction = CONSEQ_CONV_UNKNOWN_direction
  | CONSEQ_CONV_DIRECTION_NEGATE CONSEQ_CONV_STRENGTHEN_direction = CONSEQ_CONV_WEAKEN_direction
  | CONSEQ_CONV_DIRECTION_NEGATE CONSEQ_CONV_WEAKEN_direction = CONSEQ_CONV_STRENGTHEN_direction;



(******************************************************************************)
(* conseq_conv_congruences are used for moving consequence conversions        *)
(* through boolean terms. They get a system callback and a term.              *)
(*                                                                            *)
(* Given the number of already performed step, a direction and a term t       *)
(* sys n t will return the number of steps it performed and a theorem option. *)
(* If this option is NULL, nothing could be done (and the returned number of  *)
(* steps is 0). Otherwise thm_opt is a theorem of the form                    *)
(* |- t ==> t' or |- t' ==> t                                                 *)
(*                                                                            *)
(* The congruence itself get's a term t and is supposed to return a           *)
(* similar theorem option. Moreover, it has to add up all the steps done by   *)
(* calling sys and return this sum.                                           *)
(******************************************************************************)


type conseq_conv_congruence_syscall =
   term list -> thm list -> int -> CONSEQ_CONV_direction -> term -> (int * thm option)

type conseq_conv_congruence =
   thm list -> conseq_conv_congruence_syscall ->
   CONSEQ_CONV_direction -> term -> (int * thm)


fun conseq_conv_congruence_EXPAND_THM_OPT (thm_opt,t,ass_opt) =
  let
     val thm = if isSome thm_opt then valOf thm_opt else REFL_CONSEQ_CONV t;
     val thm' = if isSome ass_opt then DISCH (valOf ass_opt) thm else thm
  in
     thm'
  end;


(*
   val sys:conseq_conv_congruence_syscall =
      fn n => K (K ((n+1), NONE));

   val dir = CONSEQ_CONV_STRENGTHEN_direction
   val t = ``b1 /\ b2``;
CONSEQ_CONV_CONGRUENCE___conj sys dir t

*)

fun dir_conv dir =
   if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
      (RATOR_CONV o RAND_CONV) else RAND_CONV;

fun check_sys_call sys new_context old_context n dir t =
   let
      val (n, thm_opt) = sys new_context old_context n dir t;
      val _ = if (isSome thm_opt) then () else raise UNCHANGED;
   in
      (n, valOf thm_opt)
   end;

exception CONSEQ_CONV_congruence_expection;

fun trivial_neg_simp t =
let
   val t1 = dest_neg t
in
   if (same_const t1 T) then
      NOT_CLAUSES_T
   else if (same_const t1 F) then
      NOT_CLAUSES_F
   else
      ((K (SPEC (dest_neg t1) NOT_CLAUSES_X)) THENC
       (TRY_CONV trivial_neg_simp)) F
end


fun CONSEQ_CONV_CONGRUENCE___neg context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val b1 = dest_neg t;
     val (n1, thm1) = check_sys_call sys [] context 0  (CONSEQ_CONV_DIRECTION_NEGATE dir) b1;

     val thm2 = MATCH_MP MONO_NOT thm1
     val thm3 = CONV_RULE (dir_conv dir trivial_neg_simp) thm2 handle HOL_ERR _ => thm2
  in
     (n1, thm3)
  end  handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection



fun trivial_conj_simp t =
let
   val (t1, t2) = dest_conj t
in
   if (same_const t1 T) then
      SPEC t2 AND_CLAUSES_TX
   else if (same_const t2 T) then
      SPEC t1 AND_CLAUSES_XT
   else if (same_const t1 F) then
      SPEC t2 AND_CLAUSES_FX
   else if (same_const t2 F) then
      SPEC t1 AND_CLAUSES_XF
   else if (aconv t1 t2) then
      SPEC t1 AND_CLAUSES_XX
   else Feedback.fail()
end


fun CONSEQ_CONV_CONGRUENCE___conj context sys dir t =
  let
     val (b1,b2) = dest_conj t;

     val (n1, thm1_opt) = sys [b2] context 0  dir b1;
     val a2 = CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt dir b1;
     val (n2, thm2_opt) = sys [a2] context n1 dir b2;

     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) then () else raise UNCHANGED;
     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b1, SOME b2);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b2, SOME a2);

     val cong_thm = if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
             IMP_CONG_conj_strengthen else IMP_CONG_conj_weaken

     val thm3 = MATCH_MP cong_thm (CONJ thm1 thm2)
     val thm4 = CONV_RULE (dir_conv dir trivial_conj_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection




fun CONSEQ_CONV_CONGRUENCE___conj_no_context context sys dir t =
  let
     val (b1,b2) = dest_conj t;

     val (n1, thm1_opt) = sys [] context 0  dir b1;
     val a2 = CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt dir b1;       
     val abort_cond = same_const a2 F;
     val (n2, thm2_opt) = if abort_cond then (n1, NONE) else sys [] context n1 dir b2;      
     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) orelse abort_cond then () else raise UNCHANGED;

     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b1, NONE);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b2, NONE);

     val thm3 = MATCH_MP boolTheory.MONO_AND (CONJ thm1 thm2)
     val thm4 = CONV_RULE (dir_conv dir trivial_conj_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection



fun trivial_disj_simp t =
let
   val (t1, t2) = dest_disj t
in
   if (same_const t1 T) then
      SPEC t2 OR_CLAUSES_TX
   else if (same_const t2 T) then
      SPEC t1 OR_CLAUSES_XT
   else if (same_const t1 F) then
      SPEC t2 OR_CLAUSES_FX
   else if (same_const t2 F) then
      SPEC t1 OR_CLAUSES_XF
   else if (aconv t1 t2) then
      SPEC t1 OR_CLAUSES_XX
   else Feedback.fail()
end


fun CONSEQ_CONV_CONGRUENCE___disj context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (b1,b2) = dest_disj t;

     val a1 = mk_neg b2;
     val (n1, thm1_opt) = sys [a1] context 0  dir b1;
     val a2 = mk_neg (CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt dir b1);       
     val (n2, thm2_opt) = sys [a2] context n1 dir b2;

     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) then () else raise UNCHANGED;

     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b1, SOME a1);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b2, SOME a2);

     val cong_thm =
         if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
            IMP_CONG_disj_strengthen else IMP_CONG_disj_weaken
     val thm3 = MATCH_MP cong_thm (CONJ thm1 thm2)
     val thm4 = CONV_RULE (dir_conv dir trivial_disj_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection


fun CONSEQ_CONV_CONGRUENCE___disj_no_context context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (b1,b2) = dest_disj t;

     val (n1, thm1_opt) = sys [] context 0  dir b1;
     val a2 = CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt dir b1;       
     val abort_cond = same_const a2 T;
     val (n2, thm2_opt) = if abort_cond then (n1, NONE) else sys [] context n1 dir b2;

     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) then () else raise UNCHANGED;
     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b1, NONE);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b2, NONE);

     val thm3 = MATCH_MP MONO_OR (CONJ thm1 thm2)
     val thm4 = CONV_RULE (dir_conv dir trivial_disj_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection


fun trivial_imp_simp t =
let
   val (t1, t2) = dest_imp_only t
in
   if (same_const t1 T) then
      SPEC t2 IMP_CLAUSES_TX
   else if (same_const t2 T) then
      SPEC t1 IMP_CLAUSES_XT
   else if (same_const t1 F) then
      SPEC t2 IMP_CLAUSES_FX
   else if (same_const t2 F) then
      CONV_RULE (RHS_CONV trivial_neg_simp)
         (SPEC t1 IMP_CLAUSES_XF)
   else if (aconv t1 t2) then
      SPEC t1 IMP_CLAUSES_XX
   else Feedback.fail()

end


fun CONSEQ_CONV_CONGRUENCE___imp_full_context context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (b1,b2) = dest_imp t;

     val a1 = b1;
     val (n1, thm1_opt) = sys [a1] context 0 dir b2;
     val a2 = mk_neg (CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt dir b1);       
     val (n2, thm2_opt) = sys [a2] context n1 (CONSEQ_CONV_DIRECTION_NEGATE dir) b1;

     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) then () else raise UNCHANGED;
     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b2, SOME a1);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b1, SOME a2);

     val cong_thm =
         if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
             IMP_CONG_imp_strengthen else IMP_CONG_imp_weaken
     val thm3 = MATCH_MP cong_thm (CONJ thm1 thm2)
     val thm4 = CONV_RULE (dir_conv dir trivial_imp_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection;



fun CONSEQ_CONV_CONGRUENCE___imp_no_context context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (b1,b2) = dest_imp t;

     val (n1, thm1_opt) = sys [] context 0 dir b2;
     val a2 = CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt dir b2;       
     val abort_cond = same_const a2 T;
     val (n2, thm2_opt) = if abort_cond then (n1, NONE) else sys [] context n1 (CONSEQ_CONV_DIRECTION_NEGATE dir) b1;

     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) orelse abort_cond then () else raise UNCHANGED;
     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b2, NONE);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b1, NONE);

     val thm3 = MATCH_MP MONO_IMP (CONJ thm2 thm1)
     val thm4 = CONV_RULE (dir_conv dir trivial_imp_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection;


fun CONSEQ_CONV_CONGRUENCE___imp_simple_context context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (b1,b2) = dest_imp t;

     val (n1, thm1_opt) = sys [] context 0 (CONSEQ_CONV_DIRECTION_NEGATE dir) b1;
     val a2 = CONSEQ_CONV___OPT_GET_SIMPLIFIED_TERM thm1_opt (CONSEQ_CONV_DIRECTION_NEGATE dir) b1;       
     val abort_cond = same_const a2 F;
     val (n2, thm2_opt) = if abort_cond then (n1, NONE) else
            sys [a2] context n1 dir b2;

     val _ = if (isSome thm1_opt) orelse (isSome thm2_opt) orelse abort_cond then () else raise UNCHANGED;
     val thm1 = conseq_conv_congruence_EXPAND_THM_OPT (thm1_opt, b1, NONE);
     val thm2 = conseq_conv_congruence_EXPAND_THM_OPT (thm2_opt, b2, SOME a2);

     val cong_thm =
         if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
             IMP_CONG_simple_imp_strengthen else IMP_CONG_simple_imp_weaken
     val thm3 = MATCH_MP cong_thm (CONJ thm1 thm2)
     val thm4 = CONV_RULE (dir_conv dir trivial_imp_simp) thm3 handle HOL_ERR _ => thm3
  in
     (n2, thm4)
  end handle HOL_ERR _ => raise CONSEQ_CONV_congruence_expection;


fun var_filter_context v =
  filter (fn thm =>
    let
       val fv = FVL ((concl thm)::(hyp thm)) empty_varset;
    in
       not (HOLset.member (fv, v))
    end)

fun trivial_forall_simp t =
let
   val (x,t1) = dest_forall t
in
   if (free_in x t1) then Feedback.fail() else
      REWR_CONV FORALL_SIMP t
end;

fun CONSEQ_CONV_CONGRUENCE___forall context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (v, b1) = dest_forall t;
     val (n1, thm1_opt) = sys [] (var_filter_context v context) 0 dir b1;
     val _ = if (isSome thm1_opt) then () else raise UNCHANGED;

     val thm2 = HO_MATCH_MP MONO_ALL (GEN_ASSUM v (valOf thm1_opt))
     val thm3 = CONV_RULE (dir_conv dir trivial_forall_simp) thm2 handle HOL_ERR _ => thm2
  in
     (n1, thm3)
  end


fun trivial_exists_simp t =
let
   val (x,t1) = dest_exists t
in
   if (free_in x t1) then Feedback.fail () else
      REWR_CONV EXISTS_SIMP t
end

fun CONSEQ_CONV_CONGRUENCE___exists context (sys:conseq_conv_congruence_syscall) dir t =
  let
     val (v, b1) = dest_exists t;
     val (n1, thm1_opt) = sys [] (var_filter_context v context) 0 dir b1;
     val _ = if (isSome thm1_opt) then () else raise UNCHANGED;

     val thm2 = HO_MATCH_MP boolTheory.MONO_EXISTS (GEN_ASSUM v (valOf thm1_opt))
     val thm3 = CONV_RULE (dir_conv dir trivial_exists_simp) thm2 handle HOL_ERR _ => thm2
  in
     (n1, thm3)
  end



val CONSEQ_CONV_CONGRUENCE___basic_list___full_context = [
   CONSEQ_CONV_CONGRUENCE___conj,
   CONSEQ_CONV_CONGRUENCE___disj,
   CONSEQ_CONV_CONGRUENCE___neg,
   CONSEQ_CONV_CONGRUENCE___imp_full_context,
   CONSEQ_CONV_CONGRUENCE___forall,
   CONSEQ_CONV_CONGRUENCE___exists]


val CONSEQ_CONV_CONGRUENCE___basic_list___no_context = [
   CONSEQ_CONV_CONGRUENCE___conj_no_context,
   CONSEQ_CONV_CONGRUENCE___disj_no_context,
   CONSEQ_CONV_CONGRUENCE___neg,
   CONSEQ_CONV_CONGRUENCE___imp_no_context,
   CONSEQ_CONV_CONGRUENCE___forall,
   CONSEQ_CONV_CONGRUENCE___exists]

val CONSEQ_CONV_CONGRUENCE___basic_list = [
   CONSEQ_CONV_CONGRUENCE___conj_no_context,
   CONSEQ_CONV_CONGRUENCE___disj_no_context,
   CONSEQ_CONV_CONGRUENCE___neg,
   CONSEQ_CONV_CONGRUENCE___imp_simple_context,
   CONSEQ_CONV_CONGRUENCE___forall,
   CONSEQ_CONV_CONGRUENCE___exists]


fun CONSEQ_CONV_get_context_congruences 
   CONSEQ_CONV_NO_CONTEXT = CONSEQ_CONV_CONGRUENCE___basic_list___no_context
 | CONSEQ_CONV_get_context_congruences 
   CONSEQ_CONV_IMP_CONTEXT = CONSEQ_CONV_CONGRUENCE___basic_list
 | CONSEQ_CONV_get_context_congruences 
   CONSEQ_CONV_FULL_CONTEXT = CONSEQ_CONV_CONGRUENCE___basic_list___full_context


fun step_opt_sub NONE n = NONE
  | step_opt_sub (SOME m) n = SOME (m - n)

fun step_opt_allows_steps NONE n = true
  | step_opt_allows_steps (SOME m) n = (n <= m);

(*
   some test data for debugging

val congruence_list = CONSEQ_CONV_CONGRUENCE___basic_list

fun my_conv t =
   if (aconv t ``xxx:bool``) then
      mk_thm ([], ``xxx /\ xxx ==> xxx``)
   else
      Feedback.fail()

val step_opt = SOME 2;
val redepth = true
val conv = (K my_conv)

val t = ``xxx:bool``
val n = 0
val dir = CONSEQ_CONV_STRENGTHEN_direction

*)


val NOT_CLAUSES_NEG = CONJUNCT1 NOT_CLAUSES
val NOT_CLAUSES_T = CONJUNCT1 (CONJUNCT2 NOT_CLAUSES)
val DE_MORGAN_THM_OR = el 2
     (CONJUNCTS (Ho_Rewrite.PURE_REWRITE_RULE [FORALL_AND_THM] DE_MORGAN_THM))
val NOT_EXISTS_THM2 = CONV_RULE (DEPTH_CONV ETA_CONV) NOT_EXISTS_THM


fun mk_context2 l [] = l
|   mk_context2 l (thm::thmL) =
  if (is_neg (concl thm)) then (
  let
     val body = dest_neg (concl thm);
  in
     if (same_const body T) then
        [CONV_RULE (K NOT_CLAUSES_T) thm]
     else if (same_const body F) then
        mk_context2 l thmL
     else if (is_neg body) then
        let
          val thm0 = SPEC (dest_neg body) NOT_CLAUSES_NEG
          val thm1 = CONV_RULE (K thm0) thm
        in
          mk_context2 l (thm1::thmL)
        end
     else if (is_disj body) then
        let
          val (t1,t2) = dest_disj body
          val thm0 = SPECL [t1,t2] DE_MORGAN_THM_OR;
          val thm1 = CONV_RULE (K thm0) thm
        in
          mk_context2 l (thm1::thmL)
        end
     else if (is_imp_only body) then
        let
          val (t1,t2) = dest_imp_only body
          val thm0 = SPECL [t1,t2] NOT_IMP;
          val thm1 = CONV_RULE (K thm0) thm
        in
          mk_context2 l (thm1::thmL)
        end
     else if (is_exists body) then
        let
          val thm0 = ISPEC (rand body) NOT_EXISTS_THM2
          val thm1 = CONV_RULE (RHS_CONV (QUANT_CONV (
                        RAND_CONV BETA_CONV))) thm0
          val thm2 = CONV_RULE (K thm1) thm
        in
          mk_context2 l (thm2::thmL)
        end
     else mk_context2 (thm::l) thmL
  end)
  else if (same_const (concl thm) F) then [thm]
  else if (same_const (concl thm) T) then
       mk_context2 l thmL
  else if ((is_forall (concl thm) orelse
                (is_conj (concl thm)))) then
      mk_context2 l ((BODY_CONJUNCTS thm)@thmL)
  else mk_context2 (thm::l) thmL


fun mk_context t = mk_context2 [] [ASSUME t]




(*
fun mk_context t = profile "mk_context" (fn t => filter_context []
   (BODY_CONJUNCTS (CONV_RULE mk_context_CONV (ASSUME t)))) t


fun mk_context t = profile "mk_context 2" (fn t => filter_context []
   (BODY_CONJUNCTS (ASSUME t))) t

fun mk_context t = profile "mk_context 3" (fn t => []) t
*)

fun false_context_sys_call n cthm dir t =
let
  val thm_t =
      if dir = CONSEQ_CONV_STRENGTHEN_direction then
         mk_imp (T, t)
      else mk_imp (t, F)
  val thm = MP (SPEC thm_t FALSITY) cthm
in
  (n:int, SOME thm)
end;


fun get_cache_result NONE m step_opt dir t = NONE
  | get_cache_result (SOME (cache_ref, _)) m step_opt dir t =
let
   val (cache_str, cache_weak) = !cache_ref;
   val cached_result =
       if (same_const t T) orelse (same_const t F) then
          SOME (0, NONE)
       else if dir = CONSEQ_CONV_STRENGTHEN_direction then
            Redblackmap.peek (cache_str, t)
       else
            Redblackmap.peek (cache_weak, t);
   val cached_result' = if isSome cached_result then
       let
          val (n, thm_opt) = valOf cached_result;
       in
          if step_opt_allows_steps step_opt (n+m) then
             SOME (true, n+m, thm_opt)
          else
             NONE
       end else NONE
in
   cached_result'
end;

fun store_cache_result NONE m step_opt dir t (n, thm_opt) = ()
  | store_cache_result (SOME (cache_ref, cache_pred)) m step_opt dir t (n, thm_opt) =
let
   (* ajust needed steps *)
   val result' = (n - m, thm_opt);

   (* was it perhaps aborded early ? *)
   val aborted = (isSome step_opt) andalso not (isSome thm_opt);

   val no_assums_used = (not (isSome thm_opt)) orelse (null (hyp (valOf thm_opt)));
   val cache_result = no_assums_used andalso (not aborted) andalso
                      (cache_pred (t, result'))

in
   if not cache_result then () else
   let
      val (cache_str, cache_weak) = !cache_ref;
      val _ = cache_ref := (
            if dir = CONSEQ_CONV_STRENGTHEN_direction then
               (Redblackmap.insert (cache_str, t, result'), cache_weak)
            else
               (cache_str, Redblackmap.insert (cache_weak, t, result')))
   in
      ()
   end
end;



fun STEP_CONSEQ_CONV congruence_list convL =
let
  fun conv_trans (_,w,c) =
     (w, true, fn sys => fn context => fn dir => fn t =>
     (true, (w, CONSEQ_CONV_WRAPPER (c context) dir t)))

  val (beforeL, afterL) = partition (fn (b,w,c) => b) convL
  val fL =
          (map conv_trans beforeL)@
          (map (fn c => (0, false, fn sys => fn context => fn dir => fn t => (false, c context sys dir t))) congruence_list)@
          (map conv_trans afterL)

  fun check_fun n step_opt sys context use_congs dir t (w,is_not_cong,c) =
  if not (is_not_cong orelse use_congs) then Feedback.fail() else
  if not (step_opt_allows_steps step_opt (n+w)) then Feedback.fail() else
  let
     val (rec_flag, (w', thm)) = c sys context dir t handle UNCHANGED => Feedback.fail();
  in
     (rec_flag, n+w', SOME thm)
  end
in
  (fn n => fn step_opt => fn sys => fn context => fn use_congs => fn dir => fn t =>
    ((tryfind (check_fun n step_opt sys context use_congs dir t) fL)
    handle HOL_ERR _ => (false, n, NONE)))
end


(*
val congruence_list = CONSEQ_CONV_CONGRUENCE___basic_list
val use_context = true
val (cf, p) = valOf CONSEQ_CONV_default_cache_opt
val cache_opt = SOME (cf (), p)
val step_opt = SOME 3
val redepth = true
val convL = [(true,1,K (K c_conv))]
val t = ``c 0``
val dir = CONSEQ_CONV_STRENGTHEN_direction
val n = 3
*)

fun DEPTH_CONSEQ_CONV_num step_conv cache_opt
   redepth context n step_opt use_congs dir t =
  let
     val _ = if (same_const t T) orelse (same_const t F) then raise UNCHANGED else ();
     fun sys new_context old_context m dir t =
        let
           val _ = if (same_const t T) orelse (same_const t F) then raise UNCHANGED else ();
           val context' = flatten (map mk_context new_context);
           val false_context =
                (not (null context')) andalso
                (same_const (concl (hd context')) F)
           val context'' = context'@ old_context
        in
           if false_context then false_context_sys_call m (hd context') dir t else
           DEPTH_CONSEQ_CONV_num step_conv cache_opt redepth context'' m
              (step_opt_sub step_opt n) true dir t
        end handle UNCHANGED => (m, NONE)
                 | HOL_ERR _ => (m, NONE);

     (* try to get it from cache *)
     val result_opt = get_cache_result cache_opt n step_opt dir t;
     val (congs_flag, n1, thm1_opt) = if isSome result_opt then 
         valOf result_opt else
         step_conv n step_opt sys context use_congs dir t

     val do_depth_call = redepth andalso isSome thm1_opt;
     val (n2, thm2_opt) = if not do_depth_call then (n1, thm1_opt) else
         let
           val thm1 = valOf thm1_opt;
           val t2 = CONSEQ_CONV___GET_SIMPLIFIED_TERM thm1 t
           val (n2, thm2_opt) =
                 DEPTH_CONSEQ_CONV_num step_conv cache_opt
                     redepth context n1 step_opt congs_flag dir t2
           val thm3_opt =
               if isSome thm2_opt then
                  SOME (THEN_CONSEQ_CONV___combine thm1 (valOf thm2_opt) t)
               else thm1_opt
         in
           (n2, thm3_opt)
         end

     val _ = store_cache_result cache_opt n step_opt dir t (n2, thm2_opt)
  in
    (n2, thm2_opt)
  end handle UNCHANGED => (n, NONE);

type depth_conseq_conv_cache =
    ((term, (int * thm option)) Redblackmap.dict * (term, (int * thm option)) Redblackmap.dict) ref
type depth_conseq_conv_cache_opt =
   ((unit -> depth_conseq_conv_cache) * ((term * (int * thm option)) -> bool)) option

(* for debugging
fun dest_cache NONE = ([], [])
  | dest_cache (SOME (cf, _)) =
 let
    val (str, weak) = !(cf ())
 in
    (Redblackmap.listItems str,
     Redblackmap.listItems weak)
 end;
*)


fun mk_DEPTH_CONSEQ_CONV_CACHE_dict () =
   (Redblackmap.mkDict (Term.compare), Redblackmap.mkDict (Term.compare))

fun mk_DEPTH_CONSEQ_CONV_CACHE () =
   (ref (mk_DEPTH_CONSEQ_CONV_CACHE_dict ())):depth_conseq_conv_cache

fun mk_DEPTH_CONSEQ_CONV_CACHE_OPT p =
   SOME (mk_DEPTH_CONSEQ_CONV_CACHE, p):depth_conseq_conv_cache_opt

fun mk_PERSISTENT_DEPTH_CONSEQ_CONV_CACHE_OPT p =
   SOME (K (mk_DEPTH_CONSEQ_CONV_CACHE ()), p):depth_conseq_conv_cache_opt

val CONSEQ_CONV_default_cache_opt:depth_conseq_conv_cache_opt = 
       SOME (mk_DEPTH_CONSEQ_CONV_CACHE, K true);

fun clear_CONSEQ_CONV_CACHE (cr:depth_conseq_conv_cache) = 
     (cr := mk_DEPTH_CONSEQ_CONV_CACHE_dict())

fun clear_CONSEQ_CONV_CACHE_OPT (NONE:depth_conseq_conv_cache_opt) = ()
  | clear_CONSEQ_CONV_CACHE_OPT (SOME (cr_f, _)) =
    ((cr_f ()) := mk_DEPTH_CONSEQ_CONV_CACHE_dict())

(*
val c_def = Define `c (n:num) = T`
val c_thm = prove (``!n. (c (SUC n))==> c n``, SIMP_TAC std_ss [c_def])
val c_conv = PART_MATCH (snd o dest_imp) c_thm

val congruence_list = CONSEQ_CONV_CONGRUENCE___basic_list
val cache = NONE
val step_opt = SOME 4;
val redepth = true;
val thm = EXT_DEPTH_CONSEQ_CONV
val convL = [(true,1,K (K c_conv))]
val n = 0;
val context = []
val dir = CONSEQ_CONV_STRENGTHEN_direction;
val t = ``c 0``
*)

fun EXT_DEPTH_CONSEQ_CONV congruence_list (cache:depth_conseq_conv_cache_opt) step_opt redepth convL context =
 let
    val step_conv = STEP_CONSEQ_CONV congruence_list convL;
    fun internal_call cache_opt = DEPTH_CONSEQ_CONV_num step_conv cache_opt
                           redepth context 0 step_opt true;

 in
    fn dir => fn t =>
       let
          val cache_opt = if isSome cache then SOME ((fst (valOf cache)) (), snd (valOf cache)) else NONE
          val (_, thm_opt) = internal_call cache_opt dir t;
          val _ = if isSome thm_opt then () else raise UNCHANGED;
       in
          valOf thm_opt
       end
 end;


fun CONTEXT_DEPTH_CONSEQ_CONV context conv =
  EXT_DEPTH_CONSEQ_CONV (CONSEQ_CONV_get_context_congruences context)
     NONE NONE false [(true, 1, conv)] []
fun DEPTH_CONSEQ_CONV conv = 
  CONTEXT_DEPTH_CONSEQ_CONV CONSEQ_CONV_NO_CONTEXT (K conv)



fun CONTEXT_REDEPTH_CONSEQ_CONV context conv =
   EXT_DEPTH_CONSEQ_CONV (CONSEQ_CONV_get_context_congruences context)
     CONSEQ_CONV_default_cache_opt NONE true [(true,1,conv)] []
fun REDEPTH_CONSEQ_CONV conv = 
   CONTEXT_REDEPTH_CONSEQ_CONV CONSEQ_CONV_NO_CONTEXT (K conv)

fun CONTEXT_NUM_DEPTH_CONSEQ_CONV context conv n =
  EXT_DEPTH_CONSEQ_CONV (CONSEQ_CONV_get_context_congruences context)
     CONSEQ_CONV_default_cache_opt (SOME n) true [(true, 1, conv)] []
fun NUM_DEPTH_CONSEQ_CONV conv = CONTEXT_NUM_DEPTH_CONSEQ_CONV CONSEQ_CONV_NO_CONTEXT (K conv)

fun CONTEXT_NUM_REDEPTH_CONSEQ_CONV conv n =
  EXT_DEPTH_CONSEQ_CONV CONSEQ_CONV_CONGRUENCE___basic_list 
     CONSEQ_CONV_default_cache_opt (SOME n) true [(true, 1, conv)] []
fun NUM_REDEPTH_CONSEQ_CONV conv = CONTEXT_NUM_REDEPTH_CONSEQ_CONV (K conv)

fun CONTEXT_ONCE_DEPTH_CONSEQ_CONV context conv = CONTEXT_NUM_DEPTH_CONSEQ_CONV context conv 1
fun ONCE_DEPTH_CONSEQ_CONV conv = NUM_DEPTH_CONSEQ_CONV conv 1


(*A tactic that strengthens a boolean goal*)
fun CONSEQ_CONV_TAC conv (asm,t) =
    ((HO_MATCH_MP_TAC ((CHANGED_CONSEQ_CONV (conv CONSEQ_CONV_STRENGTHEN_direction)) t)
     THEN TRY (ACCEPT_TAC TRUTH)) (asm,t) handle UNCHANGED =>
     ALL_TAC (asm,t))

fun ASM_CONSEQ_CONV_TAC conv (asm,t) =
    CONSEQ_CONV_TAC (conv (mk_context2 [] (map ASSUME asm))) (asm, t)

fun DEPTH_CONSEQ_CONV_TAC conv =
    CONSEQ_CONV_TAC (DEPTH_CONSEQ_CONV conv)

fun REDEPTH_CONSEQ_CONV_TAC conv =
    CONSEQ_CONV_TAC (REDEPTH_CONSEQ_CONV conv)

fun ONCE_DEPTH_CONSEQ_CONV_TAC conv =
    CONSEQ_CONV_TAC (ONCE_DEPTH_CONSEQ_CONV conv)



fun STRENGTHEN_CONSEQ_CONV conv dir =
    if dir = CONSEQ_CONV_WEAKEN_direction then raise UNCHANGED else conv;

fun WEAKEN_CONSEQ_CONV conv dir =
    if dir = CONSEQ_CONV_STRENGTHEN_direction then raise UNCHANGED else conv;






fun DEPTH_STRENGTHEN_CONSEQ_CONV conv =
    DEPTH_CONSEQ_CONV (K conv) CONSEQ_CONV_STRENGTHEN_direction;


fun REDEPTH_STRENGTHEN_CONSEQ_CONV conv =
    REDEPTH_CONSEQ_CONV (K conv) CONSEQ_CONV_STRENGTHEN_direction;







(*---------------------------------------------------------------------------
 * if conv ``A`` = |- (A' ==> A) then
 * STRENGTHEN_CONSEQ_CONV_RULE ``(A ==> B)`` = |- (A' ==> B)
 *---------------------------------------------------------------------------*)

fun STRENGTHEN_CONSEQ_CONV_RULE conv thm = let
   val (imp_term,_) = dest_imp (concl thm);
   val imp_thm = conv CONSEQ_CONV_STRENGTHEN_direction imp_term;
  in
   IMP_TRANS imp_thm thm
  end




(*---------------------------------------------------------------------------
 * if conv ``A`` = |- (A' ==> A) then
 * WEAKEN_CONSEQ_CONV_RULE ``(A ==> B)`` = |- (A' ==> B)
 *---------------------------------------------------------------------------*)

fun WEAKEN_CONSEQ_CONV_RULE conv thm = let
   val (_, imp_term) = dest_imp (concl thm);
   val imp_thm = conv CONSEQ_CONV_WEAKEN_direction imp_term;
  in
   IMP_TRANS thm imp_thm
  end












(*---------------------------------------------------------------------------
 * A kind of REWRITE conversion for implications.
 *
 * CONSEQ_REWR_CONV thm takes thms of either the form
 * "|- a ==> c", "|- c = a" or "|- c"
 *
 * c is handled exactly as "c = T"
 *
 * If the thm is an equation, a "normal" rewrite is attempted. Otherwise,
 * CONDSEQ_REWR_CONV tries to match c or a with the input t and then returns a theorem
 * "|- (instantiated a) ==> t" or "|- t ==> (instantiated c)". Which ones happens
 * depends on the value of strengten.
 *---------------------------------------------------------------------------*)

fun CONSEQ_REWR_CONV___with_match ho strengten thm =
  if (is_imp_only (concl thm)) then
     ((if ho then HO_PART_MATCH else PART_MATCH) ((if strengten then snd else fst) o dest_imp) thm,
      ((if strengten then snd else fst) o dest_imp o concl) thm)
  else
     if (is_eq (concl thm)) then
        (PART_MATCH lhs thm,
         (lhs o concl) thm)
     else
        (EQT_INTRO o PART_MATCH I thm,
         concl thm)


fun CONSEQ_REWR_CONV strengten thm =
    fst (CONSEQ_REWR_CONV___with_match false strengten thm);


(*---------------------------------------------------------------------------
 * His one does multiple rewrites, can handle theorems that
 * contain alquantification and multiple conjuncted rewrite rules and
 * goes down into subterms.
 *---------------------------------------------------------------------------*)

fun CONSEQ_TOP_REWRITE_CONV___EQT_EQF_INTRO thm =
   if (is_eq (concl thm) andalso (type_of (lhs (concl thm)) = bool)) then thm else
   if (is_imp (concl thm)) then thm else
   if (is_neg (concl thm)) then EQF_INTRO thm else
   EQT_INTRO thm;

fun IMP_EXISTS_PRECOND_CANON thm =
   let val th = GEN_ALL thm
       val tm = concl th;
       val (avs,bod) = strip_forall tm
       val (ant,conseq) = dest_imp_only bod
       val th1 = SPECL avs (ASSUME tm)
       val th2 = UNDISCH th1
       val evs = filter(fn v => free_in v ant andalso not(free_in v conseq)) avs
       val th3 = itlist SIMPLE_CHOOSE evs (DISCH tm th2)
       val tm3 = Lib.trye hd(hyp th3)
   in MP (DISCH tm (DISCH tm3 (UNDISCH th3))) th end
   handle HOL_ERR _ => thm;


fun IMP_FORALL_CONCLUSION_CANON thm =
   let val th = GEN_ALL thm
       val tm = concl th;
       val (avs,bod) = strip_forall tm
       val (ant,conseq) = dest_imp_only bod
       val th1 = SPECL avs (ASSUME tm)
       val th2 = UNDISCH th1
       val evs = filter(fn v => not(free_in v ant) andalso free_in v conseq) avs
       val th3 = GENL evs th2
       val th4 = DISCH ant th3;
       val th5 = DISCH tm th4;
       val th6 = MP th5 th
   in th6 end
   handle HOL_ERR _ => thm;


fun IMP_QUANT_CANON thm =
   let val th = GEN_ALL thm
       val tm = concl th;
       val (avs,bod) = strip_forall tm
       val (ant,conseq) = dest_imp_only bod
       val th1 = SPECL avs (ASSUME tm)
       val th2 = UNDISCH th1
       val evs = filter(fn v => not(free_in v ant) andalso free_in v conseq) avs
       val evs2 = filter(fn v => free_in v ant andalso not(free_in v conseq)) avs
       val th3 = GENL evs th2
       val th4 = itlist SIMPLE_CHOOSE evs2 (DISCH tm th3)
       val tm4 = Lib.trye hd(hyp th4)

       val th5 = UNDISCH th4;
       val th6 = DISCH tm4 th5;
       val th7 = DISCH tm th6;
       val th8 = MP th7 th
   in th8 end
   handle HOL_ERR _ => thm;




fun CONSEQ_TOP_REWRITE_CONV___PREPARE_STRENGTHEN_THMS thmL =
let
   val thmL1 = map IMP_EXISTS_PRECOND_CANON thmL;
in
   thmL1
end;


fun CONSEQ_TOP_REWRITE_CONV___PREPARE_WEAKEN_THMS thmL =
let
   val thmL1 = map IMP_FORALL_CONCLUSION_CANON thmL;
in
   thmL1
end;

(* val thm0 = prove (``(SUC 1 = 2) = (2 = 2)``, DECIDE_TAC)
   val t = ``X ==> (SUC 1 = 2)``
   val (both_thmL,strengthen_thmL,weaken_thmL) = ([thm0], [], []);
   val ho = false
   val thmL = (append strengthen_thmL both_thmL)
*)
fun CONSEQ_TOP_REWRITE_CONV___ho_opt ho (both_thmL,strengthen_thmL,weaken_thmL) =
   let
     fun prepare_general_thmL thmL =
           let
               val thmL1 = flatten (map BODY_CONJUNCTS thmL);
               val thmL2 = map (CONV_RULE (TRY_CONV (REDEPTH_CONV LEFT_IMP_EXISTS_CONV))) thmL1;
               val thmL3 = map (CONV_RULE (REDEPTH_CONV RIGHT_IMP_FORALL_CONV)) thmL2;
               val thmL4 = map SPEC_ALL thmL3
           in
               map CONSEQ_TOP_REWRITE_CONV___EQT_EQF_INTRO thmL4
           end;
     val thmL_st = CONSEQ_TOP_REWRITE_CONV___PREPARE_STRENGTHEN_THMS
                       (prepare_general_thmL (append strengthen_thmL both_thmL));
     val thmL_we = CONSEQ_TOP_REWRITE_CONV___PREPARE_WEAKEN_THMS
                       (prepare_general_thmL (append weaken_thmL both_thmL));


     val net_st = foldr (fn ((conv,t),net) => Net.insert (t,conv) net) Net.empty
         (map (CONSEQ_REWR_CONV___with_match ho true) thmL_st);
     val net_we = foldr (fn ((conv,t),net) => Net.insert (t,conv) net) Net.empty
         (map (CONSEQ_REWR_CONV___with_match ho false) thmL_we);
   in
     (fn dir => fn t =>
        let
          val convL = if (dir = CONSEQ_CONV_STRENGTHEN_direction) then
                          Net.match t net_st
                      else if (dir = CONSEQ_CONV_WEAKEN_direction) then
                          Net.match t net_we
                      else
                          append (Net.match t net_st) (Net.match t net_we);

        in
          FIRST_CONSEQ_CONV convL t
        end)
   end;



fun FULL_EXT_CONSEQ_REWRITE_CONV congruence_list cache step_opt redepth ho
       context convL thmLs =
   EXT_DEPTH_CONSEQ_CONV congruence_list cache step_opt redepth
      (((false, 1, K (CONSEQ_TOP_REWRITE_CONV___ho_opt ho thmLs)))::
        (map (fn (b,w,c) =>
            (b,w, (fn context => K (CHANGED_CONV (c context))))) convL)) context;



val CONSEQ_REWRITE_CONV =
    FULL_EXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_CONGRUENCE___basic_list
       CONSEQ_CONV_default_cache_opt NONE true false [] [] 

val ONCE_CONSEQ_REWRITE_CONV =
    FULL_EXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_CONGRUENCE___basic_list
       NONE (SOME 1) true false [] []

fun CONSEQ_REWRITE_TAC thmLs =
    CONSEQ_CONV_TAC (CONSEQ_REWRITE_CONV thmLs);

fun ONCE_CONSEQ_REWRITE_TAC thmLs =
    CONSEQ_CONV_TAC (ONCE_CONSEQ_REWRITE_CONV thmLs);

val CONSEQ_HO_REWRITE_CONV =
    FULL_EXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_CONGRUENCE___basic_list
       CONSEQ_CONV_default_cache_opt NONE true true [] []

val ONCE_CONSEQ_HO_REWRITE_CONV =
    FULL_EXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_CONGRUENCE___basic_list
       NONE (SOME 1) true true [] []

fun CONSEQ_HO_REWRITE_TAC thmLs =
    CONSEQ_CONV_TAC (CONSEQ_HO_REWRITE_CONV thmLs);

fun ONCE_CONSEQ_HO_REWRITE_TAC thmLs =
    CONSEQ_CONV_TAC (ONCE_CONSEQ_HO_REWRITE_CONV thmLs);


fun EXT_CONTEXT_CONSEQ_REWRITE_CONV___ho_opt congruence_list cache step_opt ho context convL thmL =
    FULL_EXT_CONSEQ_REWRITE_CONV congruence_list
       cache step_opt true ho context
       ((map (fn c => (true, 1, c)) convL)@
       [(false, 0, K (REWRITE_CONV thmL)), (false, 0, fn context =>
           REWRITE_CONV (context@thmL))]);


fun EXT_CONTEXT_CONSEQ_REWRITE_CONV context =
    EXT_CONTEXT_CONSEQ_REWRITE_CONV___ho_opt
       (CONSEQ_CONV_get_context_congruences context)
       CONSEQ_CONV_default_cache_opt NONE false []

val EXT_CONSEQ_REWRITE_CONV =
    EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_IMP_CONTEXT;

fun EXT_CONTEXT_CONSEQ_REWRITE_TAC context convL thmL thmLs =
    CONSEQ_CONV_TAC (EXT_CONTEXT_CONSEQ_REWRITE_CONV context convL thmL thmLs);

val EXT_CONSEQ_REWRITE_TAC =
    EXT_CONTEXT_CONSEQ_REWRITE_TAC CONSEQ_CONV_IMP_CONTEXT


fun EXT_CONTEXT_CONSEQ_HO_REWRITE_CONV context =
    EXT_CONTEXT_CONSEQ_REWRITE_CONV___ho_opt 
       (CONSEQ_CONV_get_context_congruences context)
       CONSEQ_CONV_default_cache_opt NONE true []

val EXT_CONSEQ_HO_REWRITE_CONV =
    EXT_CONTEXT_CONSEQ_HO_REWRITE_CONV CONSEQ_CONV_IMP_CONTEXT

fun EXT_CONTEXT_CONSEQ_HO_REWRITE_TAC context convL thmL thmLs =
    CONSEQ_CONV_TAC (EXT_CONTEXT_CONSEQ_HO_REWRITE_CONV context convL thmL thmLs);

val EXT_CONSEQ_HO_REWRITE_TAC  =
    EXT_CONTEXT_CONSEQ_HO_REWRITE_TAC CONSEQ_CONV_IMP_CONTEXT




(*
fun CONSEQ_SIMP_CONV impThmL ss eqThmL dir =
   DEPTH_CONSEQ_CONV (fn d => ORELSE_CONSEQ_CONV (CONSEQ_TOP_REWRITE_CONV impThmL d)
                                        (SIMP_CONV ss eqThmL)) dir
*)


(*---------------------------------------------------------------------------
 * EXAMPLES

Some theorems about finite maps.

open pred_setTheory;
open finite_mapTheory;

val rewrite_every_thm =
prove (``FEVERY P FEMPTY /\
         ((FEVERY P f /\ P (x,y)) ==>
          FEVERY P (f |+ (x,y)))``,

SIMP_TAC std_ss [FEVERY_DEF, FDOM_FEMPTY,
                 NOT_IN_EMPTY, FAPPLY_FUPDATE_THM,
                 FDOM_FUPDATE, IN_INSERT] THEN
METIS_TAC[]);


val FEXISTS_DEF = Define `!P f. FEXISTS P f = ?x. x IN FDOM f /\ P (x,f ' x)`;

val rewrite_exists_thm =
prove (``(~(FEXISTS P FEMPTY)) /\
         ((FEXISTS P (f |+ (x,y))) ==>
         (FEXISTS P f \/ P (x,y)))
          ``,


SIMP_TAC std_ss [FEXISTS_DEF, FDOM_FEMPTY,
                 NOT_IN_EMPTY, FAPPLY_FUPDATE_THM,
                 FDOM_FUPDATE, IN_INSERT] THEN
METIS_TAC[]);



You can use the FEVERY-theorem to strengthen expressions:

CONSEQ_REWRITE_CONV ([],[rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``T ==> FEVERY P (g |+ (3, x) |+ (7,z))``

This should result in:

val it =
    |- (FEVERY P g /\ P (3,x)) /\ P (7,z) ==> FEVERY P (g |+ (3,x) |+ (7,z)) :
  thm


It works in substructures as well

CONSEQ_REWRITE_CONV ([], [rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``!g. ?x. Q (g, x) /\ FEVERY P (g |+ (3, x) |+ (7,z)) \/ (z = 12)``

> val it =
    |- (!g.
          ?x. Q (g,x) /\ (FEVERY P g /\ P (3,x)) /\ P (7,z) \/ (z = 12)) ==>
       !g. ?x. Q (g,x) /\ FEVERY P (g |+ (3,x) |+ (7,z)) \/ (z = 12) : thm


You can use the FEXISTS-theorem to weaken them:

CONSEQ_REWRITE_CONV ([], [], [rewrite_exists_thm]) CONSEQ_CONV_WEAKEN_direction
``FEXISTS P (g |+ (3, x) |+ (7,z))``
val thm = it
> val it =
    |- FEXISTS P (g |+ (3,x) |+ (7,z)) ==>
       (FEXISTS P g \/ P (3,x)) \/ P (7,z) : thm



Whether to weaken or strengthen subterms is figured out by their position

CONSEQ_REWRITE_CONV ([rewrite_exists_thm,rewrite_every_thm],[],[]) CONSEQ_CONV_WEAKEN_direction
    ``FEVERY P (g |+ (3, x) |+ (7,z)) ==> FEXISTS P (g |+ (3, x) |+ (7,z))``

> val it =
    |- (FEVERY P (g |+ (3,x) |+ (7,z)) ==>
        FEXISTS P (g |+ (3,x) |+ (7,z))) ==>
       (FEVERY P g /\ P (3,x)) /\ P (7,z) ==>
       (FEXISTS P g \/ P (3,x)) \/ P (7,z) : thm
(not a useful theorem, ... :-(()


However, you can mark some theorem for just beeing used for strengthening / or weakening.
The first list contains theorems used for both, then a list of ones used only
for strengthening follows and finally one just for weakening.


Full context is automatically used with EXT_CONTEXT_CONSEQ_REWRITE_CONV

EXT_CONSEQ_REWRITE_CONV [] [] ([],[rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A /\ ((A ==> B) /\ FEVERY P (g |+ (3, x) |+ (7,z)))``

EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_FULL_CONTEXT [] [] ([],[rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A /\ ((A ==> B) /\ FEVERY P (g |+ (3, x) |+ (7,z)))``

val thm =
EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_FULL_CONTEXT [] [] ([],[rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A \/ ((X A ==> B) /\ FEVERY P (g |+ (3, x) |+ (7,z)))``

EXT_CONSEQ_REWRITE_CONV [] [] ([],[rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A ==> A ==> (A /\ FEVERY P (g |+ (3, x) |+ (7,z)))``

EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_FULL_CONTEXT [] [] ([],[rewrite_every_thm],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A ==> A ==> (A /\ FEVERY P (g |+ (3, x) |+ (7,z)))``


(*Variables in Context*)


EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_FULL_CONTEXT [] [] ([],[],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A ==> A``

EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_FULL_CONTEXT [] [] ([],[],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A n ==> ?n. A n``

show_assums := true
EXT_CONTEXT_CONSEQ_REWRITE_CONV CONSEQ_CONV_FULL_CONTEXT [] [] ([],[],[]) CONSEQ_CONV_STRENGTHEN_direction
   ``A n ==> ?m. A n``

Test the recursion

val c_def = Define `c (n:num) = T`
val c_thm = prove (``!n. (c (SUC n))==> c n``, SIMP_TAC std_ss [c_def])
val c_conv = PART_MATCH (snd o dest_imp) c_thm

val cache = mk_DEPTH_CONSEQ_CONV_CACHE ()
val cache_opt = SOME (K cache,
                      default_depth_conseq_conv_cache_PRED);

val thm = EXT_DEPTH_CONSEQ_CONV CONSEQ_CONV_CONGRUENCE___basic_list true
   NONE (SOME 3) true [(true,1,K (K c_conv))]
   CONSEQ_CONV_STRENGTHEN_direction ``B /\ A ==> c 0``;


*)


end
