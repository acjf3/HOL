(*---------------------------------------------------------------------------*
 * This file is an attempt to write code to mimic the effect of              *
 * Phil Windley's datatype code, to enable me (Michael Norrish) to write     *
 * maintainable model code for HOL "records".                                *
 *---------------------------------------------------------------------------*)


structure RecordType :> RecordType =
struct

local open HolKernel Parse basicHol90Lib
      infix THEN

fun map3 f ([], _, _) = []
  | map3 f (x::xs, ys, zs) = f (x, hd ys, hd zs) :: map3 f (xs, tl ys, tl zs)

fun insert n e l =
    if n < 1 then raise Fail "Bad position to insert at" else
    if n = 1 then e::l else (hd l)::(insert (n-1) e (tl l));
fun delete n l =
    if n < 1 then raise Fail "Bad position to delete at" else
    if n = 1 then tl l
    else (hd l)::(delete (n-1) (tl l));
fun update n e = (insert n e) o (delete n);
fun findi e [] = raise Fail "Couldn't find element"
  | findi e (x::xs) = if e = x then 1 else 1 + findi e xs;
fun get_const_type str = type_of (#const (Term.const_decl str));
fun foldr f zero []      = zero
  | foldr f zero (x::xs) = f x (foldr f zero xs);
fun foldl f zero []      = zero
  | foldl f zero (x::xs) = foldl f (f zero x) xs;

(* The copy right notice applies only to dest_all_type and type2string. *)
(* Copyright 1993, Laboratory for Applied Logic, Brigham Young
   University. All rights reserved. Reproduction of all or part of this
   work is permitted for educational or research use provided that this
   copyright notice is included in any copy.  *)

  fun dest_all_type ty =
    if is_vartype ty then
      (dest_vartype ty,[]: hol_type list)
    else
      Psyntax.dest_type ty;
  fun type2string ty =
    let
      fun string_aux ty =
        let
          val (s,terml) = dest_all_type ty in
            if null terml then
              s
            else
              let
                val sl         = map string_aux terml
                fun comapp x y = x^","^y in
                  "("^(foldl comapp (hd sl) (tl sl))^")"^s
              end
        end
    in
      (string_aux ty)
    end;

  (* end of PW's copyrighted stuff *)

  (* app_letter = "appropriate letter" *)
  fun app_letter ty =
    if is_vartype ty then
      List.nth(Portable.explode(dest_vartype ty), 1)
    else let
      val (operator,l) = dest_all_type ty
    in
      hd (Portable.explode operator)
    end;

  (* Given a list of variables l, this returns a list of           *)
  (* variable-variable list pairs, such that for each element      *)
  (* (x,xl), xl is just the same as l except one element will have *)
  (* been replaced by x.                                           *)
  fun gen_update_pairs tls =
    let fun rec_upd_pairs [] front = []
          | rec_upd_pairs (hd::tl) front =
            let val newvar = variant tls hd
              val newhd = (newvar,front@(newvar::tl))
            in
              newhd :: (rec_upd_pairs tl (front @ [hd]))
            end
    in
      rec_upd_pairs tls []
    end;

  (* given two lists of equal length n, produce a list of length *)
  (* n(n-1) where each element of the first list is paired with  *)
  (* each of the second, except the one that corresponds to it   *)
  local
    fun nrecfilter fnc [] n       = []
      | nrecfilter fnc (hd::tl) n =
        if (not (fnc (n,hd))) then
          nrecfilter fnc tl (n+1)
        else
          hd::(nrecfilter fnc tl (n+1))
  in
    fun nfilter fnc l = nrecfilter fnc l 1
  end;

  fun crossprod l1 l2 =
    let
      fun pairer x y = x @ map (fn item => (y,item)) l2 in
        foldl pairer [] l1
    end;

  fun crosslessdiag l1 l2 =
    let
      val cross = crossprod l1 l2 and
        diaglength = List.length l1 + 1 in
        nfilter (fn (n,_) => not (n mod diaglength = 1)) cross
    end;

(* The following function is huge and revolting.  I don't attempt to  *)
(* make any excuses for it.  However, it's very much a function in    *)
(* an imperative style, as its result is not as important as the side *)
(* effect it brings about in the state.                               *)
in
  fun create_record typename fieldtypelist = let
    open Psyntax
    val app2 = C (curry op^)
    val (fields, types) = split fieldtypelist
    val typthm =
      Define_type.dtype {save_name = typename^"_Axiom",
                         ty_name = typename,
                         clauses = [{constructor = typename,
                                     args = map SOME types,
                                     fixity = Prefix}]}
    val type_case_def = Prim_rec.define_case_constant typthm
    val tyinfo = TypeBase.gen_tyinfo {ax = typthm, case_def = type_case_def}

    (* we now have the type actually defined in typthm *)
    fun letgen x y = x @ [variant x (Psyntax.mk_var (app_letter y,y))]
    val typeletters = foldl letgen [] types
    val typ = mk_type (typename, Lib.mk_set(Type.type_varsl types))

    (* now generate accessor functions *)
    val accfn_types = map (fn x => Type.-->(typ, x)) types
    val constype = List.foldr Type.--> typ types
    val constructor = Psyntax.mk_const(typename, constype)
    local
      fun constructor_args [] = let
        fun mkarb typ = Psyntax.mk_const("ARB", typ)
      in
        map mkarb types
      end
        | constructor_args ((f,t)::xs) = let
            val rest = constructor_args xs
            val posn = findi f fields handle _ =>
              raise Fail "Bad field name"
          in
            update posn t rest
          end
      in
        fun create_term ftl =
          list_mk_comb(constructor, constructor_args ftl)
      end
      val cons_comb = list_mk_comb(constructor,  typeletters)
      val access_fn_names = map (fn n => typename^"_"^n) fields
      val access_defn_terms =
        map3 (fn (afn_name, typeletter, accfn_type) =>
              mk_eq(mk_comb(mk_var(afn_name, accfn_type),
                            cons_comb),
                    typeletter))
        (access_fn_names, typeletters, accfn_types)
      val access_defns =
        ListPair.map
        (fn (name, tm) => Rsyntax.new_recursive_definition
         {def = tm, fixity = Prefix, name = name, rec_axiom = typthm})
        (access_fn_names, access_defn_terms)
      val accessor_thm =
        save_thm(typename^"_accessors", LIST_CONJ access_defns)
      val accfn_terms = ListPair.map mk_const (access_fn_names, accfn_types)

      (* now generate update functions *)
      val update_type = mk_type("fun", [typ,typ])
      val update_pairs = gen_update_pairs typeletters
      val updfn_names = map (fn s => s^ "_update") access_fn_names
      val updfn_terms =
        ListPair.map (fn (n, t) => mk_var(n,Type.-->(t,update_type)))
        (updfn_names, types)
      val updfn_defn_terms =
        ListPair.map
        (fn (updfn_term, (newvar,newvlist)) =>
         mk_eq (list_mk_comb(updfn_term, [newvar, cons_comb]),
                list_mk_comb(constructor, newvlist)))
        (updfn_terms, update_pairs)
      val updfn_defns =
        ListPair.map
        (fn (name, tm) =>
         Rsyntax.new_recursive_definition
         {fixity = Prefix, rec_axiom = typthm, name = name, def = tm})
        (updfn_names, updfn_defn_terms)
      val updfn_thm =
        save_thm(typename^"_updates",  LIST_CONJ updfn_defns)
      (* updfn_terms is a list of variables, not constants, so we need to *)
      (* convert them into constants                                      *)
      val updfn_terms = map (mk_const o dest_var) updfn_terms

      (* generate functional update functions *)
      (* these are of the form :
       field_fupd f o = field_update (f (field o)) o
       *)
      val fupd_names = map (fn s => s ^ "_fupd") access_fn_names
      val fupd_fun_types = map (fn t => Type.-->(t,t)) types
      val fupd_types = map (fn t => Type.-->(t, update_type)) fupd_fun_types
      val fupd_terms = ListPair.map mk_var (fupd_names, fupd_types)
      fun combine (fld, fldupd, fldfupd) =
        (--`^fldfupd f x = ^fldupd (f (^fld x)) x`--)
      val fupd_def_terms = map3 combine (accfn_terms, updfn_terms, fupd_terms)
      val fupdfn_thms =
        ListPair.map new_definition (fupd_names, fupd_def_terms)
      val fupdfn_thm =
        save_thm(typename^"_fn_updates", LIST_CONJ fupdfn_thms)
      val fupdfn_terms = map (mk_const o dest_var) fupd_terms


      (* do cases and induction theorem *)
      val induction_thm = TypeBase.induction_of tyinfo
      val cases_thm = TypeBase.nchotomy_of tyinfo

      fun gen_var_domty(name, tm, avoids) = let
        val v0 = mk_var(name, #1 (dom_rng (type_of tm)))
      in
        variant avoids v0
      end

      (* do access of updates theorems *)
      val var = Psyntax.mk_var(app_letter typ, typ)
      val tactic = STRUCT_CASES_TAC (SPEC var cases_thm) THEN
                REWRITE_TAC [accessor_thm,updfn_thm]
      val combinations = crosslessdiag accfn_terms updfn_terms
      fun create_goal (acc, upd) = let
        val x = gen_var_domty("x", upd, [var])
      in
        (--`^acc (^upd ^x ^var) = ^acc ^var`--)
      end
      val goals = map create_goal combinations
      fun create_goal (acc, upd) = let
        val x = gen_var_domty("x", upd, [var])
      in
        Term`^acc (^upd ^x ^var) = ^x`
      end
      val diag_goals = ListPair.map create_goal (accfn_terms, updfn_terms)
      val thms = map (C (curry prove) tactic) (goals@diag_goals)
      val accupd_thm =
        save_thm(typename^"_accupds", LIST_CONJ (map GEN_ALL thms))

      (* do acc of fupdates theorems *)
      (* i.e. thms of the form
           (r with fld1 updated by val).fld2 = r.fld2
         ( ==
             fld1 (fld2_fupd val r) = fld1 r
         )
      *)
      fun create_goal (acc, fupd) = let
        val f = gen_var_domty("f", fupd, [var])
      in
        Term`^acc (^fupd ^f ^var) = ^acc ^var`
      end
      val combinations = crosslessdiag accfn_terms fupdfn_terms
      val goals = map create_goal combinations
      fun create_goal (acc, fupd) = let
        val f = gen_var_domty("f", fupd, [var])
      in
        Term`^acc (^fupd ^f ^var) = ^f (^acc ^var)`
      end
      val diag_goals = ListPair.map create_goal (accfn_terms, fupdfn_terms)
      val tactic = STRUCT_CASES_TAC (SPEC var cases_thm) THEN
                   REWRITE_TAC [accessor_thm, fupdfn_thm, updfn_thm]
      val thms = map (C (curry prove) tactic) (goals @ diag_goals)
      val accfupd_thm =
        save_thm(typename^"_accfupds", LIST_CONJ (map GEN_ALL thms))

      (* do updates of access theorems *)
      (* theorems of the form: fld_upd (fld r) r = r *)
      fun mk_accfn_and_arg t = mk_comb(t,var)
      val accessfns_and_args = map mk_accfn_and_arg accfn_terms
      val map_mk_comb = curry Psyntax.mk_comb
      val lhses = map2 map_mk_comb updfn_terms accessfns_and_args
      val goals = map (fn t => (--`^t ^var = ^var`--)) lhses
      val thms = map (C (curry prove) tactic) goals
      val updacc_thm =
        save_thm(typename^"_updaccs", LIST_CONJ (map GEN_ALL thms))

      (* a more useful form of the same thing, given the conditional *)
      (* rewrite tools available to us is: *)
      (*   (val = fld s) ==> (fld_upd val s = s) *)
      val valvars = map (fn ty => Psyntax.mk_var("val", ty)) types
      val conditions = map2 (curry mk_eq) valvars accessfns_and_args
      val lhses = map2 map_mk_comb updfn_terms valvars
      fun mk_goal c lhs = (--`^c ==> (^lhs ^var = ^var)`--)
      val goals = map2 mk_goal conditions lhses
      val thms =
        map (C (curry prove) (DISCH_THEN SUBST1_TAC THEN tactic)) goals
      val updacc_c_thm =
        save_thm(typename^"_cupdaccs", LIST_CONJ (map GEN_ALL thms))

      (* do updates of (same) updates *)
      fun create_goal upd =
        (--`^upd x1 (^upd x2 ^var) = ^upd x1 ^var`--)
      val goals = map create_goal updfn_terms
      val thms = map (C (curry prove) tactic) goals
      val updupd_thm =
        save_thm(typename^"_updupds", LIST_CONJ (map GEN_ALL thms))

      (* do updates of (different) updates *)
      (* this is for canonicalisation of update sequences *)
      val combinations = crossprod updfn_terms updfn_terms
      val size = List.length updfn_terms
      val filterfn = (fn (n,_) => let val m = n - 1
                                      val d =  m div size
                                      val m = m - (d * size) in
                                        d > m end)
      val lower_triangle = nfilter filterfn combinations
      fun create_goal (f1,f2) =
        (--`^f1 x (^f2 z ^var) = ^f2 z (^f1 x ^var)`--)
      val goals = map create_goal lower_triangle
      val thms = map (C (curry prove) tactic) goals
      (* in the case where there is only one constructor, goals and thms
       will both be empty.  In this case, we don't want to apply LIST_CONJ
       to them *)
      val updcanon_thm =
        if (List.length thms > 0) then
          save_thm(typename^"_updcanon", (LIST_CONJ (map GEN_ALL thms)))
        else
          TRUTH

      val oneone_thm = valOf (TypeBase.one_one_of tyinfo)

      fun prove_semi11 upd_t = let
        fun tac s = STRUCT_CASES_TAC (SPEC (Psyntax.mk_var(s,typ)) cases_thm)
      in
        store_thm(#Name (Rsyntax.dest_const upd_t)^ "_semi11",
                  --`!x y r1 r2. (^upd_t x r1 = ^upd_t y r2) ==> (x = y)`--,
                  REPEAT GEN_TAC THEN MAP_EVERY tac ["r1", "r2"] THEN
                  REWRITE_TAC [updfn_thm, oneone_thm] THEN STRIP_TAC)
        end
      val _ = map prove_semi11 updfn_terms

      (* add to the TypeBase's simpls entry for the record type *)
      val existing_simpls = TypeBase.simpls_of tyinfo
      val new_simpls = [accupd_thm, accessor_thm, updfn_thm, updacc_thm,
                        updupd_thm, updcanon_thm, accfupd_thm]
      val new_tyinfo =
        TypeBase.put_simpls (existing_simpls @ new_simpls) tyinfo
      val _ = TypeBase.write new_tyinfo

      (* set up parsing for the record type *)
      (* want to overload fieldnames as synonyms for the field functions,
         by doing this before the add_record, this will make the overloading
         resolution prefer the latter option. *)
      fun do_accfn (name, tm) = let
      in
        Parse.allow_for_overloading_on (name, Type`:'a -> 'b`);
        Parse.overload_on(name, tm)
      end
      val _ = ListPair.app do_accfn (fields, accfn_terms)
      val _ = ListPair.app add_record_field (fields, accfn_terms)

      fun do_updfn (name0, tm) = let
        val name = name0 ^ "_update"
      in
        Parse.allow_for_overloading_on (name, Type`:'a -> 'b -> 'b`);
        Parse.overload_on(name, tm)
      end
      val _ = ListPair.app do_updfn (fields, updfn_terms)
      val _ = ListPair.app add_record_update (fields, updfn_terms)

      fun do_fupdfn (name0, tm) = let
        val name = name0 ^ "_fupd"
      in
        Parse.allow_for_overloading_on (name, Type`:('a -> 'a) -> 'b -> 'b`);
        Parse.overload_on(name, tm)
      end
      val _ = ListPair.app do_fupdfn (fields, fupdfn_terms)
      val _ = ListPair.app add_record_fupdate (fields, fupdfn_terms)

    in
      {type_axiom = typthm,
       accessor_fns = accessor_thm,
       update_fns = updfn_thm,
       cases_thm = cases_thm,
       fn_upd_thm = fupdfn_thms,
       acc_upd_thm = accupd_thm,
       upd_acc_thm = updacc_thm,
       upd_upd_thm = updupd_thm,
       upd_canon_thm = updcanon_thm,
       cons_11_thm = oneone_thm,
       create_fn = create_term}
    end;

  fun create_term_fn_base arb str accthm = let
    (* str is the name of a type in theory, we can pull out the appropriate
     theorem to get a list of accessor functions, and then create a function
     just like the create_fn field of the type returned by the function
     above *)
    val getfn = fst o strip_comb o lhs o snd o strip_forall o concl
    val fldtyps = map (Psyntax.dest_const o getfn) (CONJUNCTS accthm)
    val (fields,types) = split fldtyps
    val types = map (el 2 o #Args o Rsyntax.dest_type) types
    val constructor = #const (Term.const_decl str)
    local
      fun letgen x y = x @ [variant x (Psyntax.mk_var (app_letter y,y))]
      val typeletters = foldl letgen [] types
      fun constructor_args args =
        case args of
          [] => let
            fun mkarb typ = Psyntax.mk_const("ARB", typ)
          in
            if (arb) then map mkarb types
            else typeletters
          end
        | ((f,t)::xs) => let
            val rest = constructor_args xs
            val posn = findi f fields handle _ =>
              raise Fail "Bad field name"
          in
            update posn t rest
          end
    in
      fun create_term ftl =
        list_mk_comb(constructor, constructor_args ftl)
    end
  in
    create_term
  end;

  val create_term_fn = create_term_fn_base true
  val create_term_fn_vars = create_term_fn_base false

end;

end;
