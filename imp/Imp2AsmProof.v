From compcert Require Import
     Smallstep AST Events Behaviors Errors Csharpminor Linking Compiler Asm.
Require Import Coqlib.
Require Import ITreelib.
Require Import Universe.
Require Import Skeleton.
Require Import PCM.
Require Import STS Behavior.
Require Import Any.
Require Import ModSem.
Require Import Imp.
Require Import Imp2Csharpminor.
Require Import SimSTS2.

Require Import Imp2CsharpminorLink.
Require Import Imp2CsharpminorSepComp.
Require Import Imp2Asm.

Set Implicit Arguments.

Section PROOF.

  Context `{Σ: GRA.t}.
  Context `{builtins : builtinsTy}.

  (* Lemma nlist_list_eq {A} : *)
  (*   forall (nl: @Coqlib.nlist A) (a: A) t *)
  (*     (NLIST: nlist2list nl = a :: t), *)
  (*     (nl = list2nlist a t). *)
  (* Proof. *)
  (*   i. depgen a. depgen t. clear. induction nl; i; ss; clarify. *)
  (* Admitted. *)

  Lemma n2l_one {A} :
    forall (nl: @Coqlib.nlist A) (a: A)
      (ONE: [a] = nlist2list nl),
      nl = Coqlib.nbase a.
  Proof.
    i. depgen a. clear. induction nl; i; ss; clarify.
    sym in H0; apply n2l_not_nil in H0. clarify.
  Qed.

  Theorem compile_behavior_improves
          (imps : list Imp.program) (asms : Coqlib.nlist Asm.program)
          (COMP: Forall2 (fun imp asm => compile_imp imp = OK asm) imps asms)
          (LINKSRC: exists impl, link_imps imps = Some impl)
    :
      exists asml, ((link_list asms = Some asml) /\
               (improves2 (imps_sem imps) (Asm.semantics asml))).
  Proof.
    assert (CSM: exists csms, Forall2 (fun imp csm => Imp2Csharpminor.compile_imp imp = OK csm) imps (nlist2list csms)).
    { depgen LINKSRC. induction COMP; ss; clarify.
      { i. des. ss. }
      unfold compile_imp, compile in H. des_ifs.
      i. destruct l.
      { unfold link_imps in LINKSRC. ss. des. clarify. exists (Coqlib.nbase p); eauto. econs; eauto. }
      des.
      assert (exists srcl2, link_imps (p0 :: l) = Some srcl2).
      { unfold link_imps in LINKSRC. ss. des_ifs. exists p1. ss. }
      apply IHCOMP in H0. des. exists (Coqlib.ncons p csms). econs; eauto. }
    des. hexploit compile_behavior_improves; eauto. i.
    des. rename tgtl into csml, H into LINKCSM, H0 into IMP2.

    assert (C2A: Coqlib.nlist_forall2 (fun csm asm => transf_csharpminor_program csm = OK asm) csms asms).
    { clear IMP2. clear LINKCSM. depgen asms. depgen csms. clear. induction imps; i; ss; clarify.
      { inv CSM; inv COMP. sym in H; apply n2l_not_nil in H. clarify. }
      destruct csms as [| csm csms ].
      { inv CSM. inv H4. inv COMP. inv H4. apply n2l_one in H1. clarify. econs; eauto.
        unfold compile_imp, compile in H3. des_ifs.
        unfold Imp2Csharpminor.compile_imp in H2. rewrite H2 in Heq. clarify. }
      destruct asms as [| asm asms ].
      { inv COMP. inv H4. inv CSM. inv H5. sym in H; apply n2l_not_nil in H. clarify. }
      inv CSM; inv COMP. econs; eauto.
      unfold compile_imp, compile in H3. des_ifs.
      unfold Imp2Csharpminor.compile_imp in H2. rewrite H2 in Heq. clarify. }

    move C2A after IMP2. unfold improves2 in *. unfold improves_state2 in *.

    

      



    
  Qed.

End PROOF.
