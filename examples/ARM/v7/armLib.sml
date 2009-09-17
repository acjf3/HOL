structure armLib :> armLib =
struct

(* interactive use:
  app load ["arm_disassemblerLib", "arm_stepLib"];
*)

open HolKernel boolLib bossLib;
open armSyntax arm_astSyntax;
open arm_parserLib arm_encoderLib arm_disassemblerLib arm_stepLib;

(* ------------------------------------------------------------------------- *)

val _ = numLib.prefer_num();
val _ = wordsLib.prefer_word();

val ERR = Feedback.mk_HOL_ERR "armLib";

val trace_progress = ref 1;
val label_step_theorems = ref true;
val disassemble = ref true;

val _ = Feedback.register_trace  ("arm steps", trace_progress, 3);
val _ = Feedback.register_btrace ("label arm steps", label_step_theorems);
val _ = Feedback.register_btrace ("add disassembler comments", disassemble);

(* ------------------------------------------------------------------------- *)

val eval = rhs o concl o EVAL;

local
  fun mk_word4 i = wordsSyntax.mk_wordii (i,4)

  val is_AL = term_eq (mk_word4 14)
  val is_PC = term_eq (mk_word4 15)

  infix **

  fun opt1 ** opt2 = if opt2 = "" then opt1 else opt1 ^ "," ^ opt2

  val dest_itstate = eval o wordsSyntax.mk_word_concat o dest_If_Then

  val ITAdvance = eval o armSyntax.mk_ITAdvance

  val w2s =
    Arbnum.toString o numSyntax.dest_numeral o fst o wordsSyntax.dest_n2w

  fun condition_to_word4 tm =
    mk_word4
      (case fst (dest_var tm)
       of "eq" => 0
        | "ne" => 1
        | "cs" => 2
        | "hs" => 2
        | "cc" => 3
        | "lo" => 3
        | "mi" => 4
        | "pl" => 5
        | "vs" => 6
        | "vc" => 7
        | "hi" => 8
        | "ls" => 9
        | "ge" => 10
        | "lt" => 11
        | "gt" => 12
        | "le" => 13
        | "al" => 14
        | s    => raise ERR "condition_to_word4" (s ^ " is not a condition"));

  fun fix_condition tm = if is_var tm then condition_to_word4 tm else tm

  fun encoding tm =
        case fst (dest_const tm)
        of "Encoding_ARM"    => "; ARM"
         | "Encoding_Thumb"  => "; 16-bit Thumb"
         | "Encoding_Thumb2" => "; 32-bit Thumb"
         | _ => raise ERR "encoding" "unexpected encoding"

  val spaces = String.concat o Lib.separate " "

  fun print_progress x c opt opc =
        case x
        of NONE => arm_step opt opc
         | SOME ((m,a),e) =>
             let val label = spaces (List.filter (fn s => s <> "") [m,a,e,c])
                 val _ = if !trace_progress mod 2 = 1 then
                           print (spaces ["step:", label, "...\n"])
                         else
                           ()
                 val thm = if (!trace_progress div 2) mod 2 = 1 then
                             time (arm_step opt) opc
                           else
                             arm_step opt opc
             in
               if !label_step_theorems then
                 markerLib.MK_LABEL(label,thm)
               else
                 thm
             end
in
  fun arm_steps_from_parse s l =
    let fun arm_step_from_code (itstate,instr as Instruction (enc,cond,tm)) =
              let val opc = arm_encode instr
                  val pp = print_progress
                             (if !trace_progress mod 2 = 1 orelse
                                 !label_step_theorems
                              then
                                SOME (arm_disassemble instr,encoding enc)
                              else
                                NONE)
              in
                SOME
                  (if enc = Encoding_ARM_tm then
                     if is_AL cond orelse is_PC cond then
                       (itstate, pp "" ("arm,pass" ** s) opc, NONE)
                     else
                       (itstate,
                        pp "(pass condition)" ("arm,pass" ** s) opc,
                        SOME (pp "(fail condition)" ("arm,fail" ** s) opc))
                   else
                     let val itstate' = if is_If_Then tm then
                                          dest_itstate tm
                                        else
                                          ITAdvance itstate
                         val its = "it:" ^ w2s itstate
                         val cond' = fix_condition cond
                     in
                       if is_AL cond' orelse is_PC cond' then
                         (itstate', pp "" ("thumb,pass" ** its ** s) opc, NONE)
                       else
                         (itstate',
                          pp "(pass condition)" ("thumb,pass" ** its ** s) opc,
                          SOME (pp "(fail condition)"
                                   ("thumb,fail" ** its ** s) opc))
                     end)
              end
          | arm_step_from_code _ = NONE
        fun recurse [] _ a = List.rev a
          | recurse (h::t) itstate a =
              case arm_step_from_code (itstate,h)
              of SOME (itstate',pass,fail) =>
                   recurse t itstate' ((pass,fail)::a)
               | NONE =>
                   recurse t itstate a
    in
      recurse l (wordsSyntax.mk_wordii(0,8)) []
    end
end;

fun arm_steps_from f opt qs = arm_steps_from_parse opt (map snd (f qs));

val arm_steps_from_string = arm_steps_from arm_parse_from_string;
val arm_steps_from_file   = arm_steps_from arm_parse_from_file;
val arm_steps_from_quote  = arm_steps_from arm_parse_from_quote;

fun bits32 (n,h,l) =
let val s = StringCvt.padLeft #"0" 32 (Arbnum.toBinString n)
    val ss = Substring.slice (Substring.full s, 31 - h, SOME (h + 1 - l))
in
  Arbnum.fromBinString (Substring.string ss)
end;

fun decode_opcode itstate opc =
  if isSome itstate then
    let val n = wordsSyntax.mk_wordi (bits32 (opc,15,0),16)
        val IT = wordsSyntax.mk_wordii (valOf itstate,8)
    in
      if bits32 (opc,31,29) = Arbnum.fromBinString "111" andalso
         bits32 (opc,28,27) <> Arbnum.zero
      then
        (Encoding_Thumb2_tm,
         mk_thumb2_decode (IT,wordsSyntax.mk_wordi (bits32 (opc,31,16),16),n))
      else
        (Encoding_Thumb_tm, mk_thumb_decode (``ARMv7_A``,IT,n))
    end
  else
    (Encoding_ARM_tm,mk_arm_decode (F,wordsSyntax.mk_wordi (opc,32)));

fun decode_from_string itstate s =
let val (enc,tm) = decode_opcode itstate (Arbnum.fromHexString s)
    val (cond,tm) = tm |> eval |> pairSyntax.dest_pair
in
  Instruction (enc,cond,tm)
end;

val arm_decode = decode_from_string NONE;

fun thumb_decode i = decode_from_string (SOME i);

(* ------------------------------------------------------------------------- *)

fun output_code ostrm line (c as Instruction _) =
      let val i = arm_encoderLib.arm_encode c
          val pad = StringCvt.padRight #" "
          val comment = if !disassemble then
                          let val (m,a) = arm_disassemble c in
                            String.concat ["\t\t; ", pad 8 m, a]
                          end
                        else
                          ""
      in
        TextIO.output (ostrm, String.concat [line, " ", pad 8 i, comment, "\n"])
      end
  | output_code ostrm line c =
      TextIO.output(ostrm,
        String.concat [line, " ", arm_encoderLib.arm_encode c, "\n"]);

fun output_arm_assemble_parse ostrm s =
let open Arbnum
    val start = fromHexString s
                  handle Option =>
                    raise ERR "output_arm_assemble_parse" "expecting Hex string"
    val lower = String.map Char.toLower
    val pad   = StringCvt.padLeft #" "
    val pad0  = StringCvt.padLeft #"0"
    val count = pad 8 o pad0 4 o lower o toHexString
in
  app (fn (n,i) => output_code ostrm (count (start + n)) i)
end;

fun arm_assemble_to_file_parse start filename c =
let val ostrm = TextIO.openOut filename in
  output_arm_assemble_parse ostrm start c before TextIO.closeOut ostrm
end;

fun print_arm_assemble_from_quote s =
  output_arm_assemble_parse TextIO.stdOut s o arm_parse_from_quote;

fun print_arm_assemble_from_string s =
  output_arm_assemble_parse TextIO.stdOut s o arm_parse_from_string;

fun print_arm_assemble_from_file s =
  output_arm_assemble_parse TextIO.stdOut s o arm_parse_from_file;

fun arm_assemble_to_file_from_quote s f =
  arm_assemble_to_file_parse s f o arm_parse_from_quote;

fun arm_assemble_to_file_from_string s f =
  arm_assemble_to_file_parse s f o arm_parse_from_string;

fun arm_assemble_to_file_from_file s f =
  arm_assemble_to_file_parse s f o arm_parse_from_file;

fun join (a,b) = String.concat [a, " ", b];

val arm_disassemble_decode = join o arm_disassemble o arm_decode;
fun thumb_disassemble_decode i = join o arm_disassemble o (thumb_decode i);

end
