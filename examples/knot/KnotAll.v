Require Import Coqlib.
Require Import ITreelib.
Require Import Universe.
Require Import STS.
Require Import Behavior.
Require Import ModSem.
Require Import Skeleton.
Require Import PCM.
Require Import Hoare.
Require Import STB KnotHeader SimModSemL.
Require Import KnotMain0 KnotMain1 Knot0 Knot1 Mem0 Mem1.
Require Import KnotMain01proof Knot01proof Mem01proof.

Require Import HTactics TODOYJ.

Set Implicit Arguments.




Section AUX.

  Context `{Σ: GRA.t}.

  Definition refines_closed (md_tgt md_src: ModL.t): Prop :=
    Beh.of_program (ModL.compile md_tgt) <1= Beh.of_program (ModL.compile md_src)
  .

  Lemma refines_close: SimModSem.refines <2= refines_closed.
  Proof. ii. specialize (PR nil). ss. unfold Mod.add_list in *. ss. rewrite ! ModL.add_empty_l in PR. eauto. Qed.

  Definition add_list (ms: list ModL.t): ModL.t := fold_right ModL.add ModL.empty ms.

  Global Program Instance refines_closed_PreOrder: PreOrder refines_closed.

End AUX.

Section PROOF.

  Let Σ: GRA.t := GRA.of_list [invRA; knotRA; memRA].
  Local Existing Instance Σ.

  Let invRA_inG: @GRA.inG invRA Σ.
  Proof.
    exists 0. ss.
  Qed.
  Local Existing Instance invRA_inG.

  Let knotRA_inG: @GRA.inG knotRA Σ.
  Proof.
    exists 1. ss.
  Qed.
  Local Existing Instance knotRA_inG.

  Let memRA_inG: @GRA.inG memRA Σ.
  Proof.
    exists 2. ss.
  Qed.
  Local Existing Instance memRA_inG.

  Let RecStb: SkEnv.t -> list (gname * fspec) :=
    fun skenv => KnotRecStb.

  Let FunStb: SkEnv.t -> list (gname * fspec) :=
    fun skenv => MainFunStb RecStb skenv.

  Let GlobalStb: SkEnv.t -> list (gname * fspec) :=
    fun skenv => (MainStb RecStb skenv) ++ (KnotStb RecStb FunStb skenv) ++ MemStb.

  Definition KnotAll0: ModL.t := Mod.add_list [KnotMain0.Main; Knot0.Knot; Mem0.Mem].

  Definition KnotAll1: ModL.t := Mod.add_list [KnotMain1.Main RecStb GlobalStb; Knot1.Knot RecStb FunStb GlobalStb; Mem1.Mem].

  Lemma KnotAll01_correct:
    SimModSem.refines KnotAll0 KnotAll1.
  Proof.
    eapply SimModSem.adequacy_local_list. econs; [|econs; [|econs; ss]].
    - eapply KnotMain01proof.correct with (RecStb0:=RecStb) (FunStb0:=FunStb) (GlobalStb0:=GlobalStb).
      + ii. ss. rewrite ! eq_rel_dec_correct in *. des_ifs.
      + ii. econs; ss. refl.
      + ii. econs; ss. refl.
    - eapply Knot01proof.correct with (RecStb0:=RecStb) (FunStb0:=FunStb) (GlobalStb0:=GlobalStb).
      + ii. ss.
      + ii. ss. rewrite ! eq_rel_dec_correct in *. des_ifs.
      + ii. ss. rewrite ! eq_rel_dec_correct in *. des_ifs; stb_tac; ss.
    - eapply Mem01proof.correct.
  Qed.

End PROOF.