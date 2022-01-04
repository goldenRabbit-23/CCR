Require Import Coqlib.
Require Import STS.
Require Import Behavior.
Require Import ModSem.
Require Import Skeleton.
Require Import PCM.
Require Import Any.
Require Import HoareDef OpenDef STB SimModSem.

Require Import Relation_Definitions.
Require Import Relation_Operators.
Require Import RelationPairs.
From ExtLib Require Import
     Data.Map.FMapAList.
Require Import Red IRed.
Require Import ProofMode Invariant.
Require Import HTactics.

Set Implicit Arguments.

Ltac ired_l := try (prw _red_gen 2 1 0).
Ltac ired_r := try (prw _red_gen 1 1 0).

Ltac ired_both := ired_l; ired_r.



Section SIM.
  Context `{Σ: GRA.t}.
  Variable world: Type.
  Variable le: relation world.
  Variable I: world -> Any.t -> Any.t -> iProp.

  Variable mn: mname.
  Variable stb: gname -> option fspec.
  Variable o: ord.

  Variant fn_has_spec (fn: gname)
          (pre: Any.t -> Any.t -> iProp)
          (post: Any.t -> Any.t -> iProp)
          (tbr: bool): Prop :=
  | fn_has_spec_intro
      fsp (x: fsp.(meta))
      (STB: stb fn = Some fsp)
      (MEASURE: ord_lt (fsp.(measure) x) o)
      (PRE: forall arg_src arg_tgt, bi_entails (pre arg_src arg_tgt) (#=> fsp.(precond) (Some mn) x arg_src arg_tgt))
      (POST: forall ret_src ret_tgt, bi_entails (fsp.(postcond) (Some mn) x ret_src ret_tgt: iProp) (#=> post ret_src ret_tgt))
      (TBR: tbr = is_pure (fsp.(measure) x))
  .

  Definition option_Ord_lt (o0 o1: option Ord.t): Prop :=
    match o0, o1 with
    | None, Some _ => True
    | Some o0, Some o1 => Ord.lt o0 o1
    | _, _ => False
    end.

  Lemma option_Ord_lt_well_founded: well_founded option_Ord_lt.
  Proof.
    ii. destruct a.
    { induction (Ord.lt_well_founded t). econs.
      i. destruct y; ss.
      { eapply H0; eauto. }
      { econs. ii. destruct y; ss. }
    }
    { econs; ii. destruct y; ss. }
  Qed.

  Definition option_Ord_le (o0 o1: option Ord.t): Prop :=
    match o0, o1 with
    | None, _ => True
    | Some o0, Some o1 => Ord.le o0 o1
    | _, _ => False
    end.

  Global Program Instance option_Ord_le_PreOrder: PreOrder option_Ord_le.
  Next Obligation.
  Proof.
    ii. destruct x; ss. refl.
  Qed.
  Next Obligation.
  Proof.
    ii. destruct x, y, z; ss. etrans; eauto.
  Qed.

  Lemma option_Ord_lt_le o0 o1
        (LT: option_Ord_lt o0 o1)
    :
      option_Ord_le o0 o1.
  Proof.
    destruct o0, o1; ss. apply Ord.lt_le; auto.
  Qed.

  Lemma option_Ord_lt_le_lt o0 o1 o2
        (LT: option_Ord_lt o0 o1)
        (LE: option_Ord_le o1 o2)
    :
      option_Ord_lt o0 o2.
  Proof.
    destruct o0, o1, o2; ss. eapply Ord.lt_le_lt; eauto.
  Qed.

  Lemma option_Ord_le_lt_lt o0 o1 o2
        (LE: option_Ord_le o0 o1)
        (LT: option_Ord_lt o1 o2)
    :
      option_Ord_lt o0 o2.
  Proof.
    destruct o0, o1, o2; ss. eapply Ord.le_lt_lt; eauto.
  Qed.

  Inductive _hsim
            (hsim: forall R_src R_tgt
                          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                          (ctx: Σ),
                option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
            {R_src R_tgt}
            (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
            (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hsim_ret
      v_src v_tgt
      st_src st_tgt
      fuel f_src f_tgt
      (RET: current_iProp ctx (Q st_src st_tgt v_src v_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, (Ret v_src)) (st_tgt, (Ret v_tgt))
  | hsim_call
      fsp (x: fsp.(meta)) w0 FR
      fn arg_src arg_tgt
      st_src0 st_tgt0 ktr_src ktr_tgt
      fuel f_src f_tgt
      (SPEC: stb fn = Some fsp)
      (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
      (MEASURE: o = ord_top)
      (NPURE: fsp.(measure) x = ord_top)
      (POST: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                    (LE: le w0 w1)
                    (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
          hsim _ _ Q ctx1 None true true (st_src1, ktr_src ret_src) (st_tgt1, ktr_tgt ret_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src0, trigger (Call fn arg_src) >>= ktr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt)
  | hsim_apc_start
      fuel1
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx (fuel1) true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, trigger (hAPC) >>= ktr_src) (st_tgt, itr_tgt)
  | hsim_apc_step
      fsp (x: fsp.(meta)) w0 FR arg_src
      fn arg_tgt
      st_src0 st_tgt0 itr_src ktr_tgt
      fuel0 f_src f_tgt
      (SPEC: stb fn = Some fsp)
      (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
      (MEASURE: ord_lt (fsp.(measure) x) o)
      (PURE: is_pure (fsp.(measure) x))
      (POST: exists fuel1,
          (<<FUEL: Ord.lt fuel1 fuel0>>) /\
          (<<SIM: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                         (LE: le w0 w1)
                         (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
              hsim _ _ Q ctx1 (Some fuel1) true true (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt)>>))
    :
      _hsim hsim Q ctx (Some fuel0) f_src f_tgt (st_src0, itr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt)
  | hsim_syscall
      fn arg rvs
      st_src st_tgt ktr_src ktr_tgt
      fuel f_src f_tgt
      (POST: forall ret,
          hsim _ _ Q ctx None true true (st_src, ktr_src ret) (st_tgt, ktr_tgt ret))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, trigger (Syscall fn arg rvs) >>= ktr_src) (st_tgt, trigger (Syscall fn arg rvs) >>= ktr_tgt)
  | hsim_tau_src
      st_src st_tgt itr_src itr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, tau;; itr_src) (st_tgt, itr_tgt)
  | hsim_tau_tgt
      st_src st_tgt itr_src itr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, tau;; itr_tgt)
  | hsim_choose_src
      X
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: exists x, _hsim hsim Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, trigger (Choose X) >>= ktr_src) (st_tgt, itr_tgt)
  | hsim_choose_tgt
      X
      st_src st_tgt itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: forall x, _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Choose X) >>= ktr_tgt)
  | hsim_take_src
      X
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: forall x, _hsim hsim Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, trigger (Take X) >>= ktr_src) (st_tgt, itr_tgt)
  | hsim_take_tgt
      X
      st_src st_tgt itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: exists x, _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Take X) >>= ktr_tgt)
  | hsim_pput_src
      st_src1
      st_src0 st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src0, trigger (PPut st_src1) >>= ktr_src) (st_tgt, itr_tgt)
  | hsim_pput_tgt
      st_tgt1
      st_src st_tgt0 itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt0, trigger (PPut st_tgt1) >>= ktr_tgt)
  | hsim_pget_src
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, trigger (PGet) >>= ktr_src) (st_tgt, itr_tgt)
  | hsim_pget_tgt
      st_src st_tgt itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt))
    :
      _hsim hsim Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (PGet) >>= ktr_tgt)
  | hsim_progress
      st_src st_tgt itr_src itr_tgt
      fuel
      (SIM: hsim _ _ Q ctx fuel false false (st_src, itr_src) (st_tgt, itr_tgt))
    :
      _hsim hsim Q ctx fuel true true (st_src, itr_src) (st_tgt, itr_tgt)
  .

  Lemma _hsim_ind2
        (hsim: forall R_src R_tgt
                      (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                      (ctx: Σ),
            option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
        R_src R_tgt Q ctx
        (P: option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
        (RET: forall
            v_src v_tgt
            st_src st_tgt
            fuel f_src f_tgt
            (RET: current_iProp ctx (Q st_src st_tgt v_src v_tgt)),
            P fuel f_src f_tgt (st_src, (Ret v_src)) (st_tgt, (Ret v_tgt)))
        (CALL: forall
            fsp (x: fsp.(meta)) w0 FR
            fn arg_src arg_tgt
            st_src0 st_tgt0 ktr_src ktr_tgt
            fuel f_src f_tgt
            (SPEC: stb fn = Some fsp)
            (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
            (MEASURE: o = ord_top)
            (NPURE: fsp.(measure) x = ord_top)
            (POST: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                          (LE: le w0 w1)
                          (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
                hsim _ _ Q ctx1 None true true (st_src1, ktr_src ret_src) (st_tgt1, ktr_tgt ret_tgt)),
            P fuel f_src f_tgt (st_src0, trigger (Call fn arg_src) >>= ktr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt))
        (APCSTART: forall
            fuel1
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx (fuel1) true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt))
            (IH: P (fuel1) true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src, trigger (hAPC) >>= ktr_src) (st_tgt, itr_tgt))
        (APCSTEP: forall
            fsp (x: fsp.(meta)) w0 FR arg_src
            fn arg_tgt
            st_src0 st_tgt0 itr_src ktr_tgt
            fuel0 f_src f_tgt
            (SPEC: stb fn = Some fsp)
            (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
            (MEASURE: ord_lt (fsp.(measure) x) o)
            (PURE: is_pure (fsp.(measure) x))
            (POST: exists fuel1,
                (<<FUEL: Ord.lt fuel1 fuel0>>) /\
                (<<SIM: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                               (LE: le w0 w1)
                               (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
                    hsim _ _ Q ctx1 (Some fuel1) true true (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt)>>)),
            P (Some fuel0) f_src f_tgt (st_src0, itr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt))
        (SYSCALL: forall
            fn arg rvs
            st_src st_tgt ktr_src ktr_tgt
            fuel f_src f_tgt
            (POST: forall ret,
                hsim _ _ Q ctx None true true (st_src, ktr_src ret) (st_tgt, ktr_tgt ret)),
            P fuel f_src f_tgt (st_src, trigger (Syscall fn arg rvs) >>= ktr_src) (st_tgt, trigger (Syscall fn arg rvs) >>= ktr_tgt))
        (TAUSRC: forall
            st_src st_tgt itr_src itr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
            (IH: P None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
          ,
            P fuel f_src f_tgt (st_src, tau;; itr_src) (st_tgt, itr_tgt))
        (TAUTGT: forall
            st_src st_tgt itr_src itr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt))
            (IH: P fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, tau;; itr_tgt))
        (CHOOSESRC: forall
            X
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: exists x, (<<SIM: _hsim hsim Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>) /\ (<<IH: P None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>)),
            P fuel f_src f_tgt (st_src, trigger (Choose X) >>= ktr_src) (st_tgt, itr_tgt))
        (CHOOSETGT: forall
            X
            st_src st_tgt itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: forall x, (<<SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>) /\ (<<IH: P fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Choose X) >>= ktr_tgt))
        (TAKESRC: forall
            X
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: forall x, (<<SIM: _hsim hsim Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>) /\ (<<IH: P None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>)),
            P fuel f_src f_tgt (st_src, trigger (Take X) >>= ktr_src) (st_tgt, itr_tgt))
        (TAKETGT: forall
            X
            st_src st_tgt itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: exists x, (<<SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>) /\ (<<IH: P fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Take X) >>= ktr_tgt))
        (PPUTSRC: forall
            st_src1
            st_src0 st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt))
            (IH: P None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src0, trigger (PPut st_src1) >>= ktr_src) (st_tgt, itr_tgt))
        (PPUTTGT: forall
            st_tgt1
            st_src st_tgt0 itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt))
            (IH: P fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt0, trigger (PPut st_tgt1) >>= ktr_tgt))
        (PGETSRC: forall
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt))
            (IH: P None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src, trigger (PGet) >>= ktr_src) (st_tgt, itr_tgt))
        (PGETTGT: forall
            st_src st_tgt itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: _hsim hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt))
            (IH: P fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (PGet) >>= ktr_tgt))
        (PROGRESS: forall
            st_src st_tgt itr_src itr_tgt
            fuel
            (SIM: hsim _ _ Q ctx fuel false false (st_src, itr_src) (st_tgt, itr_tgt)),
            P fuel true true (st_src, itr_src) (st_tgt, itr_tgt))
    :
      forall fuel f_src f_tgt st_src st_tgt
             (SIM: @_hsim hsim _ _ Q ctx fuel f_src f_tgt st_src st_tgt),
        P fuel f_src f_tgt st_src st_tgt.
  Proof.
    fix IH 6. i. inv SIM.
    { eapply RET; eauto. }
    { eapply CALL; eauto. }
    { eapply APCSTART; eauto. }
    { des. eapply APCSTEP; eauto. }
    { eapply SYSCALL; eauto. }
    { eapply TAUSRC; eauto. }
    { eapply TAUTGT; eauto. }
    { des. eapply CHOOSESRC; eauto. }
    { eapply CHOOSETGT; eauto. }
    { eapply TAKESRC; eauto. }
    { des. eapply TAKETGT; eauto. }
    { eapply PPUTSRC; eauto. }
    { eapply PPUTTGT; eauto. }
    { eapply PGETSRC; eauto. }
    { eapply PGETTGT; eauto. }
    { eapply PROGRESS; eauto. }
  Qed.

  Definition hsim := paco9 _hsim bot9.
  Arguments hsim [_ _] _ _ _ _ _ _ _.

  Lemma _hsim_mon: monotone9 _hsim.
  Proof.
    ii. induction IN using _hsim_ind2.
    { econs 1; eauto. }
    { econs 2; eauto. }
    { econs 3; eauto. }
    { des. econs 4; eauto. esplits; eauto. }
    { econs 5; eauto. }
    { econs 6; eauto. }
    { econs 7; eauto. }
    { econs 8; eauto. des. esplits; eauto. }
    { econs 9; eauto. i. hexploit SIM; eauto. i. des. eauto. }
    { econs 10; eauto. i. hexploit SIM; eauto. i. des. eauto. }
    { econs 11; eauto. des. esplits; eauto. }
    { econs 12; eauto. }
    { econs 13; eauto. }
    { econs 14; eauto. }
    { econs 15; eauto. }
    { econs 16; eauto. }
  Qed.
  Hint Resolve _hsim_mon: paco.

  Lemma hsim_ind
        R_src R_tgt Q ctx
        (P: option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
        (RET: forall
            v_src v_tgt
            st_src st_tgt
            fuel f_src f_tgt
            (RET: current_iProp ctx (Q st_src st_tgt v_src v_tgt)),
            P fuel f_src f_tgt (st_src, (Ret v_src)) (st_tgt, (Ret v_tgt)))
        (CALL: forall
            fsp (x: fsp.(meta)) w0 FR
            fn arg_src arg_tgt
            st_src0 st_tgt0 ktr_src ktr_tgt
            fuel f_src f_tgt
            (SPEC: stb fn = Some fsp)
            (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
            (MEASURE: o = ord_top)
            (NPURE: fsp.(measure) x = ord_top)
            (POST: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                          (LE: le w0 w1)
                          (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
                hsim Q ctx1 None true true (st_src1, ktr_src ret_src) (st_tgt1, ktr_tgt ret_tgt)),
            P fuel f_src f_tgt (st_src0, trigger (Call fn arg_src) >>= ktr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt))
        (APCSTART: forall
            fuel1
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx (fuel1) true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt))
            (IH: P (fuel1) true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src, trigger (hAPC) >>= ktr_src) (st_tgt, itr_tgt))
        (APCSTEP: forall
            fsp (x: fsp.(meta)) w0 FR arg_src
            fn arg_tgt
            st_src0 st_tgt0 itr_src ktr_tgt
            fuel0 f_src f_tgt
            (SPEC: stb fn = Some fsp)
            (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
            (MEASURE: ord_lt (fsp.(measure) x) o)
            (PURE: is_pure (fsp.(measure) x))
            (POST: exists fuel1,
                (<<FUEL: Ord.lt fuel1 fuel0>>) /\
                (<<SIM: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                               (LE: le w0 w1)
                               (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
                    hsim Q ctx1 (Some fuel1) true true (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt)>>)),
            P (Some fuel0) f_src f_tgt (st_src0, itr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt))
        (SYSCALL: forall
            fn arg rvs
            st_src st_tgt ktr_src ktr_tgt
            fuel f_src f_tgt
            (POST: forall ret,
                hsim Q ctx None true true (st_src, ktr_src ret) (st_tgt, ktr_tgt ret)),
            P fuel f_src f_tgt (st_src, trigger (Syscall fn arg rvs) >>= ktr_src) (st_tgt, trigger (Syscall fn arg rvs) >>= ktr_tgt))
        (TAUSRC: forall
            st_src st_tgt itr_src itr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
            (IH: P None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
          ,
            P fuel f_src f_tgt (st_src, tau;; itr_src) (st_tgt, itr_tgt))
        (TAUTGT: forall
            st_src st_tgt itr_src itr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt))
            (IH: P fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, tau;; itr_tgt))
        (CHOOSESRC: forall
            X
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: exists x, (<<SIM: hsim Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>) /\ (<<IH: P None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>)),
            P fuel f_src f_tgt (st_src, trigger (Choose X) >>= ktr_src) (st_tgt, itr_tgt))
        (CHOOSETGT: forall
            X
            st_src st_tgt itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: forall x, (<<SIM: hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>) /\ (<<IH: P fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Choose X) >>= ktr_tgt))
        (TAKESRC: forall
            X
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: forall x, (<<SIM: hsim Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>) /\ (<<IH: P None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt)>>)),
            P fuel f_src f_tgt (st_src, trigger (Take X) >>= ktr_src) (st_tgt, itr_tgt))
        (TAKETGT: forall
            X
            st_src st_tgt itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: exists x, (<<SIM: hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>) /\ (<<IH: P fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x)>>)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Take X) >>= ktr_tgt))
        (PPUTSRC: forall
            st_src1
            st_src0 st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt))
            (IH: P None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src0, trigger (PPut st_src1) >>= ktr_src) (st_tgt, itr_tgt))
        (PPUTTGT: forall
            st_tgt1
            st_src st_tgt0 itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt))
            (IH: P fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt0, trigger (PPut st_tgt1) >>= ktr_tgt))
        (PGETSRC: forall
            st_src st_tgt ktr_src itr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt))
            (IH: P None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt)),
            P fuel f_src f_tgt (st_src, trigger (PGet) >>= ktr_src) (st_tgt, itr_tgt))
        (PGETTGT: forall
            st_src st_tgt itr_src ktr_tgt
            fuel f_src f_tgt
            (SIM: hsim Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt))
            (IH: P fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt)),
            P fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (PGet) >>= ktr_tgt))
        (PROGRESS: forall
            st_src st_tgt itr_src itr_tgt
            fuel
            (SIM: hsim Q ctx fuel false false (st_src, itr_src) (st_tgt, itr_tgt)),
            P fuel true true (st_src, itr_src) (st_tgt, itr_tgt))
    :
      forall fuel f_src f_tgt st_src st_tgt
             (SIM: hsim Q ctx fuel f_src f_tgt st_src st_tgt),
        P fuel f_src f_tgt st_src st_tgt.
  Proof.
    i. punfold SIM. induction SIM using _hsim_ind2.
    { eapply RET; eauto. }
    { eapply CALL; eauto. i. hexploit POST; eauto. i. pclearbot. eauto. }
    { eapply APCSTART; eauto. pfold. eauto. }
    { des. eapply APCSTEP; eauto. esplits; eauto. i. hexploit SIM; eauto. i. pclearbot. eauto. }
    { eapply SYSCALL; eauto. i. hexploit POST; eauto. i. pclearbot. eauto. }
    { eapply TAUSRC; eauto. pfold. eauto. }
    { eapply TAUTGT; eauto. pfold. eauto. }
    { des. eapply CHOOSESRC; eauto. esplits; eauto. pfold. eauto. }
    { eapply CHOOSETGT; eauto. i. hexploit SIM; eauto. i. des. pclearbot. splits; eauto. pfold. eauto. }
    { eapply TAKESRC; eauto. i. hexploit SIM; eauto. i. des. pclearbot. splits; eauto. pfold. eauto. }
    { des. eapply TAKETGT; eauto. esplits; eauto. pfold. eauto. }
    { eapply PPUTSRC; eauto. pfold. eauto. }
    { eapply PPUTTGT; eauto. pfold. eauto. }
    { eapply PGETSRC; eauto. pfold. eauto. }
    { eapply PGETTGT; eauto. pfold. eauto. }
    { eapply PROGRESS; eauto. pclearbot. eauto. }
  Qed.

  Definition mylift (fuel: option Ord.t) (mn_caller: option mname) X (x: X)
             ctx
             (Q: option mname -> X -> Any.t -> Any.t -> iProp) (itr_src: itree hEs Any.t): itree Es Any.t :=
    match fuel with
    | None =>
      (interp_hCallE_tgt mn stb o (interp_hEs_tgt itr_src) ctx) >>= (HoareFunRet Q mn_caller x)
    | Some fuel =>
      r0 <- (interp_hCallE_tgt mn stb o (_APC fuel) ctx);;
      r1 <- (interp_hCallE_tgt mn stb o (tau;; Ret (snd r0)) (fst r0));;
      r2 <- (interp_hCallE_tgt mn stb o (interp_hEs_tgt itr_src) (fst r1));;
      (HoareFunRet Q mn_caller x r2)
    end.

  Lemma current_iPropL_convert ctx P
        (CUR: current_iProp ctx P)
    :
      current_iPropL ctx [("H", P)].
  Proof.
    unfold current_iPropL. ss. unfold from_iPropL.
    eapply current_iProp_entail; eauto.
  Qed.

  Lemma hsim_adequacy_aux:
    forall
      f_src f_tgt st_src st_tgt (itr_src: itree (hAPCE +' Es) Any.t) itr_tgt mr_src ctx X (x: X) Q mn_caller fuel w0
      (SIM: hsim (fun st_src st_tgt ret_src ret_tgt =>
                    (∃ w1, ⌜le w0 w1⌝ ** I w1 st_src st_tgt) ** (Q mn_caller x ret_src ret_tgt: iProp)) ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)),
      paco8 (_sim_itree (mk_wf I) le) bot8 Any.t Any.t (lift_rel (mk_wf I) le w0 (@eq Any.t))
            f_src f_tgt w0
            (Any.pair st_src mr_src,
             mylift fuel mn_caller x ctx Q itr_src)
            (st_tgt, itr_tgt).
  Proof.
    ginit. gcofix CIH. i.
    remember (st_src, itr_src). remember (st_tgt, itr_tgt).
    revert st_src st_tgt itr_src itr_tgt Heqp Heqp0 CIH.
    induction SIM using hsim_ind; i; clarify.
    { eapply current_iPropL_convert in RET. mDesAll. destruct fuel; steps.
      { astop. steps. hret _; eauto. iModIntro. iSplitL "A1"; auto. }
      { hret _; eauto. iModIntro. iSplitL "A1"; auto. }
    }
    { eapply current_iPropL_convert in PRE. mDesAll. destruct fuel; steps.
      { astop. steps. rewrite SPEC. steps. destruct fsp. ss. hcall _ _ with "A A1".
        { iModIntro. iSplitL "A1"; eauto. iApply "A". }
        { rewrite MEASURE in *. splits; ss. unfold ord_lt. des_ifs. }
        { steps. gbase. hexploit CIH.
          { eapply POST; [eauto|]. eapply current_iProp_entail; [eauto|].
            start_ipm_proof. iSplitR "POST".
            { iSplitL "H"; eauto. }
            { iApply "POST". }
          }
          i. ss. eauto.
        }
      }
      { rewrite SPEC. steps. destruct fsp. ss. hcall _ _ with "A A1".
        { iModIntro. iSplitL "A1"; eauto. iApply "A". }
        { rewrite MEASURE in *. splits; ss. unfold ord_lt. des_ifs. }
        { steps. gbase. hexploit CIH.
          { eapply POST; [eauto|]. eapply current_iProp_entail; [eauto|].
            start_ipm_proof. iSplitR "POST".
            { iSplitL "H"; eauto. }
            { iApply "POST". }
          }
          i. ss. eauto.
        }
      }
    }
    { destruct fuel; steps.
      { astop. steps. exploit IHSIM; eauto. i. destruct fuel1; ss.
        { astart t0.
          match goal with
          | |- ?P0 (_, ?itr1) _ =>
            match (type of x0) with
            | ?P1 (_, ?itr0) _ =>
              replace itr1 with itr0
            end
          end; auto.
          grind. destruct x1, x2. destruct u, u0. grind.
        }
        { astop. steps. }
      }
      { exploit IHSIM; eauto. i. destruct fuel1; ss.
        { astart t.
          match goal with
          | |- ?P0 (_, ?itr1) _ =>
            match (type of x0) with
            | ?P1 (_, ?itr0) _ =>
              replace itr1 with itr0
            end
          end; auto.
          grind. destruct x1, x2. destruct u, u0. grind.
        }
        { astop. steps. }
      }
    }
    { des. steps. rewrite unfold_APC. steps.
      force_l. exists false. steps.
      force_l. exists fuel1. steps.
      force_l; [eauto|..]. steps.
      force_l. exists (fn, arg_src). steps.
      rewrite SPEC. steps.
      eapply current_iPropL_convert in PRE. mDesAll.
      destruct fsp. ss. hcall _ _ with "A A1".
      { iModIntro. iSplitL "A1"; eauto. iApply "A". }
      { splits; ss. }
      { steps. gbase. hexploit CIH.
        { eapply SIM; [eauto|]. eapply current_iProp_entail; [eauto|].
          start_ipm_proof. iSplitR "POST".
          { iSplitL "H"; eauto. }
          { iApply "POST". }
        }
        i. ss. eauto.
      }
    }
    { destruct fuel; steps.
      { astop. steps. gbase. hexploit CIH; eauto. }
      { gbase. hexploit CIH; eauto. }
    }
    { destruct fuel; steps.
      { astop. steps. exploit IHSIM; eauto. }
      { exploit IHSIM; eauto. }
    }
    { steps. exploit IHSIM; eauto. }
    { des. exploit IH; eauto. i. destruct fuel; steps.
      { astop. steps. force_l. eexists. steps. eauto. }
      { force_l. eexists. steps. eauto. }
    }
    { steps. exploit SIM; eauto. i. des. eauto. }
    { destruct fuel; steps.
      { astop. steps. exploit SIM; eauto. i. des. eauto. }
      { exploit SIM; eauto. i. des. eauto. }
    }
    { des. exploit IH; eauto. i. force_r. eexists. eauto. }
    { destruct fuel; steps.
      { astop. steps. exploit IHSIM; eauto. }
      { exploit IHSIM; eauto. }
    }
    { steps. exploit IHSIM; eauto. }
    { destruct fuel; steps.
      { astop. steps. exploit IHSIM; eauto. }
      { exploit IHSIM; eauto. }
    }
    { steps. exploit IHSIM; eauto. }
    { deflag. gbase. eapply CIH; eauto. }
  Qed.

  Lemma hsim_adequacy:
    forall
      f_src f_tgt st_src st_tgt (itr_src: itree (hAPCE +' Es) Any.t) itr_tgt mr_src ctx X (x: X) Q mn_caller w0
      (SIM: hsim (fun st_src st_tgt ret_src ret_tgt =>
                    (∃ w1, ⌜le w0 w1⌝ ** I w1 st_src st_tgt) ** (Q mn_caller x ret_src ret_tgt: iProp)) ctx None f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)),
      paco8 (_sim_itree (mk_wf I) le) bot8 Any.t Any.t (lift_rel (mk_wf I) le w0 (@eq Any.t))
            f_src f_tgt w0
            (Any.pair st_src mr_src,
             (interp_hCallE_tgt mn stb o (interp_hEs_tgt itr_src) ctx) >>= (HoareFunRet Q mn_caller x))
            (st_tgt, itr_tgt).
  Proof.
    i. hexploit hsim_adequacy_aux; eauto.
  Qed.

  Lemma hsim_progress_flag R_src R_tgt r g Q ctx fuel st_src st_tgt
        (SIM: gpaco9 _hsim (cpn9 _hsim) g g R_src R_tgt Q ctx fuel false false st_src st_tgt)
    :
      gpaco9 _hsim (cpn9 _hsim) r g _ _ Q ctx fuel true true st_src st_tgt.
  Proof.
    destruct st_src, st_tgt. gstep. eapply hsim_progress; eauto.
  Qed.

  Lemma _hsim_flag_mon
        r
        R_src R_tgt Q ctx
        fuel f_src0 f_tgt0 f_src1 f_tgt1 st_src st_tgt
        (SIM: @_hsim r R_src R_tgt Q ctx fuel f_src0 f_tgt0 st_src st_tgt)
        (SRC: f_src0 = true -> f_src1 = true)
        (TGT: f_tgt0 = true -> f_tgt1 = true)
    :
      @_hsim r R_src R_tgt Q ctx fuel f_src1 f_tgt1 st_src st_tgt.
  Proof.
    revert f_src1 f_tgt1 SRC TGT.
    induction SIM using _hsim_ind2; i; clarify.
    { econs 1; eauto. }
    { econs 2; eauto. }
    { econs 3. eapply IHSIM; eauto. }
    { econs 4; eauto. }
    { econs 5; eauto. }
    { econs 6. eapply IHSIM; eauto. }
    { econs 7; eauto. }
    { econs 8; eauto. des. esplits. eapply IH; eauto. }
    { econs 9; eauto. i. hexploit SIM; eauto. i. des. eauto. }
    { econs 10; eauto. i. hexploit SIM; eauto. i. des. eapply IH; eauto. }
    { econs 11; eauto. des. esplits; eauto. }
    { econs 12. eapply IHSIM; auto. }
    { econs 13. eapply IHSIM; auto. }
    { econs 14. eapply IHSIM; auto. }
    { econs 15. eapply IHSIM; auto. }
    { exploit SRC; auto. exploit TGT; auto. i. clarify. econs 16; eauto. }
  Qed.

  Variant fuelC (r: forall R_src R_tgt
                           (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                           (ctx: Σ),
                    option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | fuelC_intro
      f_src f_tgt fuel0 fuel1
      st_src st_tgt
      (SIM: r _ _ Q ctx fuel0 f_src f_tgt st_src st_tgt)
      (ORD: option_Ord_le fuel0 fuel1)
    :
      fuelC r Q ctx fuel1 f_src f_tgt st_src st_tgt
  .

  Lemma fuelC_mon:
    monotone9 fuelC.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve fuelC_mon: paco.

  Lemma fuelC_spec: fuelC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply wrespect9_uclo; eauto with paco.
    econs; eauto with paco. i. inv PR. eapply GF in SIM.
    revert x4 ORD. induction SIM using _hsim_ind2; i; clarify.
    { econs 1; eauto. }
    { econs 2; eauto. i. eapply rclo9_base. eauto. }
    { econs 3; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. auto. }
    { destruct x4; ss. econs 4; eauto. des. esplits; eauto.
      { eapply Ord.lt_le_lt; eauto. }
      { i. eapply rclo9_base. eauto. }
    }
    { econs 5; eauto. i. eapply rclo9_base. auto. }
    { econs 6; eauto. eapply _hsim_mon; eauto. i. apply rclo9_base. auto. }
    { econs 7; eauto. }
    { econs 8; eauto. des. esplits; eauto. eapply _hsim_mon; eauto. i. apply rclo9_base. auto. }
    { econs 9; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { econs 10; eauto. i. hexploit SIM; eauto. i. des. eapply _hsim_mon; eauto. i. eapply rclo9_base; auto. }
    { econs 11; eauto. des. esplits; eauto. }
    { econs 12; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base; eauto. }
    { econs 13; eauto. }
    { econs 14; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base; eauto. }
    { econs 15; eauto. }
    { econs 16; eauto. eapply rclo9_clo_base. econs; eauto. }
  Qed.

  Variant hflagC (r: forall R_src R_tgt
                            (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                            (ctx: Σ),
                     option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hflagC_intro
      f_src0 f_src1 f_tgt0 f_tgt1 fuel0 fuel1
      st_src st_tgt
      (SIM: r _ _ Q ctx fuel0 f_src0 f_tgt0 st_src st_tgt)
      (SRC: f_src0 = true -> f_src1 = true)
      (TGT: f_tgt0 = true -> f_tgt1 = true)
      (ORD: option_Ord_le fuel0 fuel1)
    :
      hflagC r Q ctx fuel1 f_src1 f_tgt1 st_src st_tgt
  .

  Lemma hflagC_mon:
    monotone9 hflagC.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve hflagC_mon: paco.

  Structure grespectful clo : Prop :=
    grespect_intro {
        grespect_mon: monotone9 clo;
        grespect_respect :
          forall l r
                 (LE: l <9= r)
                 (GF: l <9= @_hsim r),
            clo l <9= gpaco9 _hsim (cpn9 _hsim) bot9 (rclo9 (clo \10/ gupaco9 _hsim (cpn9 _hsim)) r);
      }.

  Lemma grespect_uclo clo
        (RESPECT: grespectful clo)
    :
      clo <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply grespect9_uclo; eauto with paco.
    econs.
    { eapply RESPECT. }
    i. hexploit grespect_respect.
    { eauto. }
    { eapply LE. }
    { eapply GF. }
    { eauto. }
    i. inv H. eapply rclo9_mon.
    { eauto. }
    i. ss. des; ss. eapply _paco9_unfold in PR0.
    2:{ ii. eapply _hsim_mon; [eapply PR1|]. i. eapply rclo9_mon; eauto. }
    ss. eapply _hsim_mon.
    { eapply PR0; eauto. }
    i. eapply rclo9_clo. right. econs.
    eapply rclo9_mon; eauto. i. inv PR2.
    { left. eapply paco9_mon; eauto. i. ss. des; ss.
      left. auto. }
    { des; ss. right. auto. }
  Qed.

  Lemma hflagC_spec: hflagC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply grespect_uclo; eauto with paco.
    econs; eauto with paco. i. inv PR. eapply GF in SIM.
    guclo fuelC_spec. econs; [|eauto]. gstep.
    eapply _hsim_flag_mon; eauto.
    eapply _hsim_mon; eauto. i. gbase. eapply rclo9_base. auto.
  Qed.

  Variant hsimC
          (r g: forall R_src R_tgt
                       (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                       (ctx: Σ),
              option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hsimC_ret
      v_src v_tgt
      st_src st_tgt
      fuel f_src f_tgt
      (RET: current_iProp ctx (Q st_src st_tgt v_src v_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, (Ret v_src)) (st_tgt, (Ret v_tgt))
  | hsimC_call
      fsp (x: fsp.(meta)) w0 FR
      fn arg_src arg_tgt
      st_src0 st_tgt0 ktr_src ktr_tgt
      fuel f_src f_tgt
      (SPEC: stb fn = Some fsp)
      (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
      (MEASURE: o = ord_top)
      (NPURE: fsp.(measure) x = ord_top)
      (POST: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                    (LE: le w0 w1)
                    (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
          g _ _ Q ctx1 None true true (st_src1, ktr_src ret_src) (st_tgt1, ktr_tgt ret_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src0, trigger (Call fn arg_src) >>= ktr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt)
  | hsimC_apc_start
      fuel1
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx (fuel1) true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, trigger (hAPC) >>= ktr_src) (st_tgt, itr_tgt)
  | hsimC_apc_step
      fsp (x: fsp.(meta)) w0 FR arg_src
      fn arg_tgt
      st_src0 st_tgt0 itr_src ktr_tgt
      fuel0 f_src f_tgt
      (SPEC: stb fn = Some fsp)
      (PRE: current_iProp ctx (FR ** I w0 st_src0 st_tgt0 ** fsp.(precond) (Some mn) x arg_src arg_tgt))
      (MEASURE: ord_lt (fsp.(measure) x) o)
      (PURE: is_pure (fsp.(measure) x))
      (POST: exists fuel1,
          (<<FUEL: Ord.lt fuel1 fuel0>>) /\
          (<<SIM: forall ctx1 w1 st_src1 st_tgt1 ret_src ret_tgt
                         (LE: le w0 w1)
                         (ACC: current_iProp ctx1 (FR ** I w1 st_src1 st_tgt1 ** fsp.(postcond) (Some mn) x ret_src ret_tgt)),
              g _ _ Q ctx1 (Some fuel1) true true (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt)>>))
    :
      hsimC r g Q ctx (Some fuel0) f_src f_tgt (st_src0, itr_src) (st_tgt0, trigger (Call fn arg_tgt) >>= ktr_tgt)
  | hsimC_syscall
      fn arg rvs
      st_src st_tgt ktr_src ktr_tgt
      fuel f_src f_tgt
      (POST: forall ret,
          g _ _ Q ctx None true true (st_src, ktr_src ret) (st_tgt, ktr_tgt ret))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, trigger (Syscall fn arg rvs) >>= ktr_src) (st_tgt, trigger (Syscall fn arg rvs) >>= ktr_tgt)
  | hsimC_tau_src
      st_src st_tgt itr_src itr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, tau;; itr_src) (st_tgt, itr_tgt)
  | hsimC_tau_tgt
      st_src st_tgt itr_src itr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, tau;; itr_tgt)
  | hsimC_choose_src
      X
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: exists x, r _ _ Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, trigger (Choose X) >>= ktr_src) (st_tgt, itr_tgt)
  | hsimC_choose_tgt
      X
      st_src st_tgt itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: forall x, r _ _ Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Choose X) >>= ktr_tgt)
  | hsimC_take_src
      X
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: forall x, r _ _ Q ctx None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, trigger (Take X) >>= ktr_src) (st_tgt, itr_tgt)
  | hsimC_take_tgt
      X
      st_src st_tgt itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: exists x, r _ _ Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Take X) >>= ktr_tgt)
  | hsimC_pput_src
      st_src1
      st_src0 st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src0, trigger (PPut st_src1) >>= ktr_src) (st_tgt, itr_tgt)
  | hsimC_pput_tgt
      st_tgt1
      st_src st_tgt0 itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt0, trigger (PPut st_tgt1) >>= ktr_tgt)
  | hsimC_pget_src
      st_src st_tgt ktr_src itr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, trigger (PGet) >>= ktr_src) (st_tgt, itr_tgt)
  | hsimC_pget_tgt
      st_src st_tgt itr_src ktr_tgt
      fuel f_src f_tgt
      (SIM: r _ _ Q ctx fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt))
    :
      hsimC r g Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (PGet) >>= ktr_tgt)
  | hsimC_progress
      st_src st_tgt itr_src itr_tgt
      fuel
      (SIM: g _ _ Q ctx fuel false false (st_src, itr_src) (st_tgt, itr_tgt))
    :
      hsimC r g Q ctx fuel true true (st_src, itr_src) (st_tgt, itr_tgt)
  .

  Lemma hsim_indC_mon_gen r0 r1 g0 g1
        (LE0: r0 <9= r1)
        (LE1: g0 <9= g1)
    :
      @hsimC r0 g0 <9= @hsimC r1 g1.
  Proof.
    ii. inv PR.
    { econs 1; eauto. }
    { econs 2; eauto. }
    { econs 3; eauto. }
    { econs 4; eauto. des. esplits; eauto. }
    { econs 5; eauto. }
    { econs 6; eauto. }
    { econs 7; eauto. }
    { econs 8; eauto. des. esplits; eauto. }
    { econs 9; eauto. }
    { econs 10; eauto. }
    { econs 11; eauto. des. esplits; eauto. }
    { econs 12; eauto. }
    { econs 13; eauto. }
    { econs 14; eauto. }
    { econs 15; eauto. }
    { econs 16; eauto. }
  Qed.

  Lemma hsim_indC_mon: monotone9 (fun r => @hsimC r r).
  Proof.
    ii. eapply hsim_indC_mon_gen; eauto.
  Qed.

  Lemma hsim_indC_spec:
    (fun r => @hsimC r r) <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply wrespect9_uclo; eauto with paco. econs.
    { eapply hsim_indC_mon. }
    i. inv PR.
    { econs 1; eauto. }
    { econs 2; eauto. i. eapply rclo9_base. eauto. }
    { econs 3; eauto. eapply GF in SIM. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 4; eauto. des. esplits; eauto. i. eapply rclo9_base. eauto. }
    { econs 5; eauto. i. eapply rclo9_base. eauto. }
    { econs 6; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 7; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 8; eauto. des. esplits; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 9; eauto. i. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 10; eauto. i. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 11; eauto. des. esplits; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 12; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 13; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 14; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 15; eauto. eapply _hsim_mon; eauto. i. eapply rclo9_base. eauto. }
    { econs 16; eauto. eapply rclo9_base. eauto. }
  Qed.

  Lemma hsimC_spec:
    hsimC <11= gpaco9 (_hsim) (cpn9 _hsim).
  Proof.
    i. inv PR.
    { gstep. econs 1; eauto. }
    { gstep. econs 2; eauto. i. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 3; eauto. gbase. eauto. }
    { gstep. econs 4; eauto. des. esplits; eauto. i. gbase. eauto. }
    { gstep. econs 5; eauto. i. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 6; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 7; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 8; eauto. des. esplits; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 9; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 10; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 11; eauto. des. esplits; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 12; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 13; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 14; eauto. gbase. eauto. }
    { guclo hsim_indC_spec. ss. econs 15; eauto. gbase. eauto. }
    { gstep. econs 16; eauto. i. gbase. eauto. }
  Qed.

  Lemma hsimC_uclo r g:
    @hsimC (gpaco9 (_hsim) (cpn9 _hsim) r g) (gupaco9 (_hsim) (cpn9 _hsim) g) <9= gpaco9 (_hsim) (cpn9 _hsim) r g.
  Proof.
    i. eapply hsimC_spec in PR.  ss.
    eapply gpaco9_gpaco; [eauto with paco|].
    eapply gpaco9_mon; eauto. i. eapply gupaco9_mon; eauto.
  Qed.

  Variant hbindC (r: forall R_src R_tgt
                            (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                            (ctx: Σ),
                     option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hbindC_intro
      S_src S_tgt
      (P: Any.t -> Any.t -> S_src -> S_tgt -> iProp)
      fuel f_src f_tgt st_src0 st_tgt0 itr_src itr_tgt ktr_src ktr_tgt
      (SIM: @r S_src S_tgt P ctx fuel f_src f_tgt (st_src0, itr_src) (st_tgt0, itr_tgt))
      (SIMK: forall ctx1 st_src1 st_tgt1 ret_src ret_tgt
                    (POST: current_iProp ctx1 (P st_src1 st_tgt1 ret_src ret_tgt)),
          @r R_src R_tgt Q ctx1 None false false (st_src1, ktr_src ret_src) (st_tgt1, ktr_tgt ret_tgt))
    :
      hbindC r Q ctx fuel f_src f_tgt (st_src0, itr_src >>= ktr_src) (st_tgt0, itr_tgt >>= ktr_tgt)
  .

  Lemma hbindC_mon:
    monotone9 hbindC.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve hbindC_mon: paco.

  Lemma hbindC_spec: hbindC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply grespect_uclo.
    econs; eauto with paco. i. inv PR. eapply GF in SIM.
    remember (st_src0, itr_src). remember (st_tgt0, itr_tgt).
    revert st_src0 itr_src st_tgt0 itr_tgt Heqp Heqp0.
    induction SIM using _hsim_ind2; i; clarify; ired_both.
    { hexploit SIMK; eauto. i.
      eapply GF in H. guclo hflagC_spec. econs.
      2:{ instantiate (1:=false). ss. }
      2:{ instantiate (1:=false). ss. }
      2:{ instantiate (1:=None). destruct fuel; ss. }
      gstep. eapply _hsim_mon; eauto. i. gbase. eapply rclo9_base. auto.
    }
    { gstep. econs 2; eauto. i. hexploit POST; eauto. i.
      gbase. eapply rclo9_clo_base. left. econs; eauto.
    }
    { eapply hsimC_uclo. econs 3; eauto. }
    { des. gstep. econs 4; eauto. esplits; eauto. i.
      hexploit SIM; eauto. i. gbase. eapply rclo9_clo_base. left. econs; eauto.
    }
    { gstep. econs 5; eauto. i. gbase. eapply rclo9_clo_base. left. econs; eauto. }
    { eapply hsimC_uclo. econs 6; eauto. }
    { eapply hsimC_uclo. econs 7; eauto. }
    { des. eapply hsimC_uclo. econs 8; eauto. }
    { eapply hsimC_uclo. econs 9; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { eapply hsimC_uclo. econs 10; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { des. eapply hsimC_uclo. econs 11; eauto. }
    { eapply hsimC_uclo. econs 12; eauto. }
    { eapply hsimC_uclo. econs 13; eauto. }
    { eapply hsimC_uclo. econs 14; eauto. }
    { eapply hsimC_uclo. econs 15; eauto. }
    { gstep. econs 16; eauto. gbase. eapply rclo9_clo_base. left. econs; eauto. }
  Qed.

  Variant hbind_rightC (r: forall R_src R_tgt
                                  (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                                  (ctx: Σ),
                           option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hbind_rightC_intro
      S_tgt
      (P: Any.t -> Any.t -> S_tgt -> iProp)
      fuel f_src f_tgt st_src0 st_tgt0 itr_src itr_tgt ktr_tgt
      (SIM: @r unit S_tgt (fun st_src st_tgt _ ret_tgt => P st_src st_tgt ret_tgt) ctx None f_src f_tgt (st_src0, Ret tt) (st_tgt0, itr_tgt))
      (SIMK: forall ctx1 st_src1 st_tgt1 ret_tgt
                    (POST: current_iProp ctx1 (P st_src1 st_tgt1 ret_tgt)),
          @r R_src R_tgt Q ctx1 fuel false false (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt))
    :
      hbind_rightC r Q ctx fuel f_src f_tgt (st_src0, itr_src) (st_tgt0, itr_tgt >>= ktr_tgt)
  .

  Lemma hbind_rightC_mon:
    monotone9 hbind_rightC.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve hbind_rightC_mon: paco.

  Lemma hbind_rightC_spec: hbind_rightC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply grespect_uclo.
    econs; eauto with paco. i. inv PR. eapply GF in SIM. remember None in SIM.
    remember (st_src0, Ret tt). remember (st_tgt0, itr_tgt).
    revert st_src0 st_tgt0 itr_tgt Heqp Heqp0 Heqo0.
    induction SIM using _hsim_ind2; i; clarify; ired_both.
    { hexploit SIMK; eauto. i.
      eapply GF in H. guclo hflagC_spec. econs.
      2:{ instantiate (1:=false). ss. }
      2:{ instantiate (1:=false). ss. }
      2:{ refl. }
      gstep. eapply _hsim_mon; eauto. i. gbase. eapply rclo9_base. auto.
    }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 7; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 9; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { des. eapply hsimC_uclo. econs 11; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 13; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 15; eauto. }
    { gstep. econs 16; eauto. gbase. eapply rclo9_clo_base. left. econs; eauto. }
  Qed.

  Variant hsplitC (r: forall R_src R_tgt
                             (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                             (ctx: Σ),
                      option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hsplitC_intro
      S_tgt
      (P: Any.t -> Any.t -> S_tgt -> iProp)
      fuel0 fuel1 f_src f_tgt st_src0 st_tgt0 itr_src itr_tgt ktr_tgt
      (SIM: @r unit S_tgt (fun st_src st_tgt _ ret_tgt => P st_src st_tgt ret_tgt) ctx (Some fuel0) f_src f_tgt (st_src0, Ret tt) (st_tgt0, itr_tgt))
      (SIMK: forall ctx1 st_src1 st_tgt1 ret_tgt
                    (POST: current_iProp ctx1 (P st_src1 st_tgt1 ret_tgt)),
          @r R_src R_tgt Q ctx1 (Some fuel1) false false (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt))
    :
      hsplitC r Q ctx (Some (fuel1 + fuel0)%ord) f_src f_tgt (st_src0, itr_src) (st_tgt0, itr_tgt >>= ktr_tgt)
  .

  Lemma hsplitC_mon:
    monotone9 hsplitC.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve hsplitC_mon: paco.

  Lemma hsplitC_spec: hsplitC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply grespect_uclo.
    econs; eauto with paco. i. inv PR. eapply GF in SIM.
    remember (st_src0, Ret tt). remember (st_tgt0, itr_tgt). remember (Some fuel0).
    revert fuel0 st_src0 st_tgt0 itr_tgt Heqp Heqp0 Heqo0.
    induction SIM using _hsim_ind2; i; clarify; ired_both.
    { hexploit SIMK; eauto. i.
      eapply GF in H. guclo hflagC_spec. econs.
      2:{ instantiate (1:=false). ss. }
      2:{ instantiate (1:=false). ss. }
      2:{ instantiate (1:=(Some fuel1)). ss. apply OrdArith.add_base_l. }
      gstep. eapply _hsim_mon; eauto. i. gbase. eapply rclo9_base. auto.
    }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { des. gstep. econs 4; eauto. esplits; eauto.
      { eapply OrdArith.lt_add_r. eauto. }
      i. hexploit SIM; eauto. i. gbase. eapply rclo9_clo_base. left. econs; eauto.
    }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 7; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 9; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { des. eapply hsimC_uclo. econs 11; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 13; eauto. }
    { apply f_equal with (f:=_observe) in H0. ss. }
    { eapply hsimC_uclo. econs 15; eauto. }
    { gstep. econs 16; eauto. gbase. eapply rclo9_clo_base. left. econs; eauto. }
  Qed.

  Variant hmonoC (r: forall R_src R_tgt
                            (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                            (ctx: Σ),
                     option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hmonoC_intro
      f_src f_tgt fuel Q0
      st_src st_tgt
      (SIM: r _ _ Q0 ctx fuel f_src f_tgt st_src st_tgt)
      (MONO: forall st_src st_tgt ret_src ret_tgt,
          (bi_entails (Q0 st_src st_tgt ret_src ret_tgt) (#=> Q st_src st_tgt ret_src ret_tgt)))
    :
      hmonoC r Q ctx fuel f_src f_tgt st_src st_tgt
  .

  Lemma hmonoC_mon:
    monotone9 hmonoC.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve hmonoC_mon: paco.

  Lemma hmonoC_spec: hmonoC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply wrespect9_uclo; eauto with paco.
    econs; eauto with paco. i. inv PR. eapply GF in SIM.
    induction SIM using _hsim_ind2; i; clarify; ired_both.
    { econs 1; eauto. eapply current_iProp_upd.
      eapply current_iProp_entail; eauto.
    }
    { econs 2; eauto. i. eapply rclo9_clo_base. econs; eauto. }
    { econs 3; eauto. }
    { econs 4; eauto. des. esplits; eauto. i. hexploit SIM; eauto. i. eapply rclo9_clo_base. econs; eauto. }
    { econs 5; eauto. i. eapply rclo9_clo_base. econs; eauto. }
    { econs 6; eauto. }
    { econs 7; eauto. }
    { econs 8; eauto. des. esplits; eauto. }
    { econs 9; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { econs 10; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { econs 11; eauto. des. esplits; eauto. }
    { econs 12; eauto. }
    { econs 13; eauto. }
    { econs 14; eauto. }
    { econs 15; eauto. }
    { econs 16; eauto. eapply rclo9_clo_base. econs; eauto. }
  Qed.

  Variant hframeC_aux (r: forall R_src R_tgt
                             (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                             (ctx: Σ),
                      option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hframeC_aux_intro
      res
      f_src f_tgt fuel
      st_src st_tgt
      (PRE: URA.wf (ctx ⋅ res))
      (SIM: r _ _ (fun st_src st_tgt ret_src ret_tgt => Own res -* #=> Q st_src st_tgt ret_src ret_tgt) (ctx ⋅ res) fuel f_src f_tgt st_src st_tgt)
    :
      hframeC_aux r Q ctx fuel f_src f_tgt st_src st_tgt
  .

  Lemma hframeC_aux_mon:
    monotone9 hframeC_aux.
  Proof. ii. inv IN; econs; et. Qed.
  Hint Resolve hframeC_aux_mon: paco.

  Lemma current_iProp_frame_own ctx0 ctx1 P
        (CUR: current_iProp (ctx0 ⋅ ctx1) (Own ctx1 -* P))
    :
      current_iProp ctx0 P.
  Proof.
    inv CUR. uipropall. hexploit IPROP.
    2:{ exists URA.unit. eapply URA.unit_id. }
    { eapply URA.wf_mon. instantiate (1:=ctx0). r_wf GWF. }
    i. econs; [|eauto]. r_wf GWF.
  Qed.

  Lemma current_iProp_frame_own_rev ctx0 ctx1 P
        (CUR: current_iProp ctx0 (Own ctx1 ** P))
    :
      current_iProp (ctx0 ⋅ ctx1) P.
  Proof.
    inv CUR. uipropall.
    unfold URA.extends in *. des; clarify.
    econs; [|eauto]. eapply URA.wf_mon.
    instantiate (1:=ctx). r_wf GWF.
  Qed.

  Lemma current_iProp_own_wf ctx res
        (CUR: current_iProp ctx (Own res))
    :
      URA.wf (ctx ⋅ res).
  Proof.
    inv CUR. uipropall. unfold URA.extends in *. des. clarify.
    eapply URA.wf_mon.
    instantiate (1:=ctx0). r_wf GWF.
  Qed.

  Lemma hframeC_aux_spec: hframeC_aux <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    eapply wrespect9_uclo; eauto with paco.
    econs; eauto with paco. i. inv PR. eapply GF in SIM.
    induction SIM using _hsim_ind2; i; clarify; ired_both.
    { econs 1; eauto. eapply current_iProp_upd. eapply current_iProp_frame_own; eauto. }
    { econs 2; eauto.
      { eapply current_iProp_frame_own.
        eapply current_iProp_entail.
        { eapply PRE0. }
        iIntros "[[H0 H1] H2] H3".
        iSplitR "H2"; [|iExact "H2"].
        iSplitR "H1"; [|iExact "H1"].
        instantiate (1:= _ ** _).
        iSplitL "H0"; [iExact "H0"|].
        iExact "H3".
      }
      { i. eapply rclo9_clo_base. econs.
        { instantiate (1:=res). eapply current_iProp_own_wf.
          eapply current_iProp_entail.
          { eapply ACC. }
          iIntros "[[[H0 H1] H2] H3]". ss.
        }
        { eapply POST; eauto.
          eapply current_iProp_frame_own_rev.
          eapply current_iProp_entail.
          { eapply ACC. }
          iIntros "[[[H0 H1] H2] H3]".
          iSplitL "H1"; [iExact "H1"|].
          iSplitR "H3"; [|iExact "H3"].
          iSplitR "H2"; [|iExact "H2"].
          iExact "H0".
        }
      }
    }
    { econs 3; eauto. }
    { econs 4; eauto.
      { eapply current_iProp_frame_own.
        eapply current_iProp_entail.
        { eapply PRE0. }
        iIntros "[[H0 H1] H2] H3".
        iSplitR "H2"; [|iExact "H2"].
        iSplitR "H1"; [|iExact "H1"].
        instantiate (1:= _ ** _).
        iSplitL "H0"; [iExact "H0"|].
        iExact "H3".
      }
      { des. esplits; eauto.
        i. eapply rclo9_clo_base. econs.
        { instantiate (1:=res). eapply current_iProp_own_wf.
          eapply current_iProp_entail.
          { eapply ACC. }
          iIntros "[[[H0 H1] H2] H3]". ss.
        }
        { eapply SIM; eauto.
          eapply current_iProp_frame_own_rev.
          eapply current_iProp_entail.
          { eapply ACC. }
          iIntros "[[[H0 H1] H2] H3]".
          iSplitL "H1"; [iExact "H1"|].
          iSplitR "H3"; [|iExact "H3"].
          iSplitR "H2"; [|iExact "H2"].
          iExact "H0".
        }
      }
    }
    { econs 5; eauto. i. eapply rclo9_clo_base. econs; eauto. }
    { econs 6; eauto. }
    { econs 7; eauto. }
    { econs 8; eauto. des. esplits; eauto. }
    { econs 9; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { econs 10; eauto. i. hexploit SIM; eauto. i. des. esplits; eauto. }
    { econs 11; eauto. des. esplits; eauto. }
    { econs 12; eauto. }
    { econs 13; eauto. }
    { econs 14; eauto. }
    { econs 15; eauto. }
    { econs 16; eauto. eapply rclo9_clo_base. econs; eauto. }
  Qed.

  Variant hframeC (r: forall R_src R_tgt
                             (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                             (ctx: Σ),
                      option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
          {R_src R_tgt}
          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
          (ctx: Σ)
    : option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop :=
  | hframeC_intro
      P0 P1
      f_src f_tgt fuel
      st_src st_tgt
      (PRE: current_iProp ctx (P0 ** P1))
      (SIM: forall ctx (PRE: current_iProp ctx P1),
          r _ _ (fun st_src st_tgt ret_src ret_tgt => P0 -* #=> Q st_src st_tgt ret_src ret_tgt) ctx fuel f_src f_tgt st_src st_tgt)
    :
      hframeC r Q ctx fuel f_src f_tgt st_src st_tgt
  .

  Lemma hframeC_spec: hframeC <10= gupaco9 (_hsim) (cpn9 _hsim).
  Proof.
    ii. inv PR.
    inv PRE. red in IPROP.
    autounfold with iprop in IPROP.
    autorewrite with iprop in IPROP. des. clarify.
    guclo hframeC_aux_spec. econs.
    { instantiate (1:=a). eapply URA.wf_mon. instantiate (1:=b). r_wf GWF. }
    { guclo hmonoC_spec. econs.
      { gbase. eapply SIM. econs; [|eauto]. r_wf GWF.
      }
      { i. ss. iIntros "H0". iModIntro. iIntros "H1".
        iApply bupd_trans. iApply "H0".
        iStopProof. uipropall.
        i. red in H. des. clarify. esplits; [|eauto].
        eapply URA.wf_mon. instantiate (1:=ctx0). r_wf H0.
      }
    }
  Qed.

  Definition back
             (r g: forall R_src R_tgt
                          (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
                          (ctx: Σ),
                 option Ord.t -> bool -> bool -> Any.t * itree hEs R_src -> Any.t * itree Es R_tgt -> Prop)
             {R_src R_tgt}
             (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
             (fuel: option Ord.t)
             (f_src f_tgt: bool)
             (st_src: Any.t * itree hEs R_src)
             (st_tgt: Any.t * itree Es R_tgt): iProp :=
    fun res =>
      forall ctx (WF: URA.wf (res ⋅ ctx)),
        gpaco9 (_hsim) (cpn9 _hsim) r g _ _ Q ctx fuel f_src f_tgt st_src st_tgt.

  Lemma back_init
        R_src R_tgt (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        P r g ctx fuel f_src f_tgt st_src st_tgt itr_src itr_tgt
        (ENTAIL: bi_entails
                   P
                   (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)))
        (CUR: current_iProp ctx P)
    :
      gpaco9 _hsim (cpn9 _hsim) r g _ _ Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt).
  Proof.
    eapply current_iProp_entail in ENTAIL; eauto.
    inv ENTAIL. unfold back in IPROP. eapply IPROP; eauto.
  Qed.

  Lemma back_final
        R_src R_tgt (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        P r g fuel f_src f_tgt st_src st_tgt itr_src itr_tgt
        (SIM: forall ctx
                     (CUR: current_iProp ctx P),
            gpaco9 _hsim (cpn9 _hsim) r g _ _ Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
    :
      bi_entails
        P
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)).
  Proof.
    uipropall. ii. eapply SIM. econs; eauto.
  Qed.

  Lemma back_current
        R_src R_tgt (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel ctx f_src f_tgt st_src st_tgt itr_src itr_tgt
        (CUR: current_iProp ctx (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)))
    :
      gpaco9 _hsim (cpn9 _hsim) r g _ _ Q ctx fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt).
  Proof.
    inv CUR. eapply IPROP; eauto.
  Qed.

  Lemma back_mono R_src R_tgt
        (Q0 Q1: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src itr_src st_tgt itr_tgt
        (MONO: forall st_src st_tgt ret_src ret_tgt,
            (bi_entails (Q0 st_src st_tgt ret_src ret_tgt) (#=> Q1 st_src st_tgt ret_src ret_tgt)))
    :
      bi_entails
        (back r g Q0 fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
        (back r g Q1 fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back in *. i. hexploit H; eauto. i.
    guclo hmonoC_spec. econs; eauto.
  Qed.

  Lemma back_wand R_src R_tgt
        (Q0 Q1: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src itr_src st_tgt itr_tgt
    :
      bi_entails
        ((∀ st_src st_tgt ret_src ret_tgt,
             ((Q0 st_src st_tgt ret_src ret_tgt) -∗ (#=> Q1 st_src st_tgt ret_src ret_tgt))) ** (back r g Q0 fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)))
        (back r g Q1 fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back in *. i.
    red in H. unfold Sepconj in H. autorewrite with iprop in H.
    des. clarify. eapply from_semantic in H0. hexploit (H1 (ctx ⋅ a)).
    { r_wf WF0. }
    i. guclo hframeC_aux_spec. econs.
    { instantiate (1:=a). eapply URA.wf_mon. instantiate (1:=b). r_wf WF0. }
    guclo hmonoC_spec. econs.
    { eapply H. }
    i. iIntros "H0". iModIntro. iIntros "H1".
    iPoseProof (H0 with "H1") as "H1".
    iMod "H1". iApply "H1". iApply "H0".
  Qed.

  Lemma back_upd R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (#=> (back r g Q fuel f_src f_tgt st_src st_tgt))
        (back r g Q fuel f_src f_tgt st_src st_tgt).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back in *. i.
    red in H. unfold bi_bupd_bupd in H. ss. unfold Upd in H. autorewrite with iprop in H.
    hexploit H; eauto. i. des.
    hexploit H1; eauto.
  Qed.

  Lemma back_bind R_src R_tgt S_src S_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src (itr_src: itree hEs S_src)
        ktr_src st_tgt (itr_tgt: itree Es S_tgt) ktr_tgt
    :
      bi_entails
        (back r g (fun st_src st_tgt ret_src ret_tgt => back r g Q None false false (st_src, ktr_src ret_src) (st_tgt, ktr_tgt ret_tgt)) fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src >>= ktr_src) (st_tgt, itr_tgt >>= ktr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back in *. i.
    guclo hbindC_spec. econs.
    { eapply H; eauto. }
    i. inv POST. eapply IPROP. eauto.
  Qed.

  Lemma back_bind_left R_src R_tgt S_src
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src (itr_src: itree hEs S_src)
        ktr_src st_tgt itr_tgt
    :
      bi_entails
        (back r g (fun st_src st_tgt ret_src ret_tgt => back r g Q None false false (st_src, ktr_src ret_src) (st_tgt, itr_tgt)) fuel f_src f_tgt (st_src, itr_src) (st_tgt, Ret tt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src >>= ktr_src) (st_tgt, itr_tgt)).
  Proof.
    iIntros "H".
    assert (EQ: itr_tgt = Ret tt >>= fun _ => itr_tgt).
    { grind. }
    rewrite EQ. iApply back_bind. rewrite <- EQ. iApply "H".
  Qed.

  Lemma back_bind_right R_src R_tgt S_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src itr_src
        st_tgt (itr_tgt: itree Es S_tgt) ktr_tgt
    :
      bi_entails
        (back r g (fun st_src st_tgt ret_src ret_tgt => back r g Q None false false (st_src, itr_src) (st_tgt, ktr_tgt ret_tgt)) fuel f_src f_tgt (st_src, Ret tt) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt >>= ktr_tgt)).
  Proof.
    iIntros "H".
    assert (EQ: itr_src = Ret tt >>= fun _ => itr_src).
    { grind. }
    rewrite EQ. iApply back_bind. rewrite <- EQ. iApply "H".
  Qed.

  Lemma back_bind_right_pure R_src R_tgt S_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src itr_src
        st_tgt (itr_tgt: itree Es S_tgt) ktr_tgt
    :
      bi_entails
        (back r g (fun st_src st_tgt ret_src ret_tgt => back r g Q fuel false false (st_src, itr_src) (st_tgt, ktr_tgt ret_tgt)) None f_src f_tgt (st_src, Ret tt) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt >>= ktr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back in *. i.
    guclo hbind_rightC_spec. econs.
    { eapply H; eauto. }
    i. inv POST. eapply IPROP. eauto.
  Qed.

  Lemma back_progress R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel st_src itr_src st_tgt itr_tgt
    :
      bi_entails
        (back g g Q fuel false false (st_src, itr_src) (st_tgt, itr_tgt))
        (back r g Q fuel true true (st_src, itr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply back_current in CUR.
    eapply hsim_progress_flag. auto.
  Qed.

  Lemma back_flag_mon
        fuel0 f_src0 f_tgt0
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g st_src itr_src st_tgt itr_tgt
        fuel1 f_src1 f_tgt1
        (SRC: f_src0 = true -> f_src1 = true)
        (TGT: f_tgt0 = true -> f_tgt1 = true)
        (FUEL: option_Ord_le fuel0 fuel1)
    :
      bi_entails
        (back r g Q fuel0 f_src0 f_tgt0 (st_src, itr_src) (st_tgt, itr_tgt))
        (back r g Q fuel1 f_src1 f_tgt1 (st_src, itr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply back_current in CUR.
    guclo hflagC_spec. econs; eauto.
  Qed.

  Lemma back_split_aux R_src R_tgt S_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g st_src itr_src st_tgt (itr_tgt: itree Es S_tgt) ktr_tgt
        fuel0 fuel1 f_src f_tgt
    :
      bi_entails
        (back r g (fun st_src st_tgt _ ret_tgt => back r g Q (Some fuel1) false false (st_src, itr_src) (st_tgt, ktr_tgt ret_tgt)) (Some fuel0) f_src f_tgt (st_src, Ret tt) (st_tgt, itr_tgt))
        (back r g Q (Some (fuel1 + fuel0)%ord) f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt >>= ktr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back in *. i.
    guclo hsplitC_spec. econs.
    { eapply H; eauto. }
    i. inv POST. eapply IPROP. eauto.
  Qed.

  Lemma back_split
        fuel0 fuel1
        R_src R_tgt S_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g st_src itr_src st_tgt (itr_tgt: itree Es S_tgt) ktr_tgt
        fuel f_src f_tgt
        (FUEL: (fuel1 + fuel0 <= fuel)%ord)
    :
      bi_entails
        (back r g (fun st_src st_tgt _ ret_tgt => back r g Q (Some fuel1) false false (st_src, itr_src) (st_tgt, ktr_tgt ret_tgt)) (Some fuel0) f_src f_tgt (st_src, Ret tt) (st_tgt, itr_tgt))
        (back r g Q (Some fuel) f_src f_tgt (st_src, itr_src) (st_tgt, itr_tgt >>= ktr_tgt)).
  Proof.
    iIntros "H".
    iApply back_flag_mon.
    { eauto. }
    { eauto. }
    { instantiate (1:=Some (fuel1 + fuel0)%ord). ss. }
    iApply back_split_aux. auto.
  Qed.

  Lemma back_call_impure
        pre post w0
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt fn arg_src arg_tgt ktr_src ktr_tgt
        (SPEC: fn_has_spec fn pre post false)
    :
      bi_entails
        ((#=> ((pre arg_src arg_tgt: iProp) ** I w0 st_src st_tgt))
           **
           (∀ st_src st_tgt ret_src ret_tgt,
               ((∃ w1, I w1 st_src st_tgt ** ⌜le w0 w1⌝) ** (post ret_src ret_tgt: iProp)) -* #=> back g g Q None true true (st_src, ktr_src ret_src) (st_tgt, ktr_tgt ret_tgt)))
        (back r g Q fuel f_src f_tgt (st_src, trigger (Call fn arg_src) >>= ktr_src) (st_tgt, trigger (Call fn arg_tgt) >>= ktr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back at 2. i.
    match (type of H) with
    | ?P _ =>
      assert (CUR: current_iProp ctx P)
    end.
    { econs; eauto. }
    apply current_iPropL_convert in CUR.
    mDesAll. mUpd "H". mDesSep "H".
    ired_both. gstep. inv SPEC. econs; eauto.
    { mAssert _ with "H".
      { iApply (PRE with "H"). }
      mUpd "A2".
      eapply current_iProp_entail; [eapply CUR|]. start_ipm_proof.
      iSplitR "A2"; [|iExact "A2"].
      iSplitR "A1"; [|iExact "A1"].
      iExact "A".
    }
    { destruct (measure fsp x), o; ss. }
    { destruct (measure fsp x), o; ss. }
    i. apply current_iPropL_convert in ACC.
    mDesAll. mSpcUniv "H" with st_src1.
    mSpcUniv "H" with st_tgt1.
    mSpcUniv "H" with ret_src.
    mSpcUniv "H" with ret_tgt.
    mAssert _ with "A".
    { iApply (POST with "A"). }
    mUpd "A2".
    mAssert (#=> (back g g Q None true true (st_src1, ktr_src ret_src)
                       (st_tgt1, ktr_tgt ret_tgt))) with "*".
    { iApply "H". iSplitR "A2"; [|iExact "A2"].
      iExists w1. iSplit; ss.
    }
    mUpd "A".
    inv ACC. red in IPROP. uipropall. des. subst. eapply IPROP0.
    eapply URA.wf_mon. instantiate (1:=b). r_wf GWF.
  Qed.

  Lemma back_call_pure
        pre post w0 fuel1
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g f_src f_tgt st_src st_tgt fn arg_src arg_tgt itr_src ktr_tgt
        fuel0
        (SPEC: fn_has_spec fn pre post true)
        (FUEL: Ord.lt fuel1 fuel0)
    :
      bi_entails
        ((#=> ((pre arg_src arg_tgt: iProp) ** I w0 st_src st_tgt))
           **
           (∀ st_src st_tgt ret_src ret_tgt,
               ((∃ w1, I w1 st_src st_tgt ** ⌜le w0 w1⌝) ** (post ret_src ret_tgt: iProp)) -* #=> back g g Q (Some fuel1) true true (st_src, itr_src) (st_tgt, ktr_tgt ret_tgt)))
        (back r g Q (Some fuel0) f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Call fn arg_tgt) >>= ktr_tgt)).
  Proof.
    red. unfold Entails. autorewrite with iprop.
    unfold back at 2. i.
    match (type of H) with
    | ?P _ =>
      assert (CUR: current_iProp ctx P)
    end.
    { econs; eauto. }
    apply current_iPropL_convert in CUR.
    mDesAll. mUpd "H". mDesSep "H".
    ired_both. gstep. inv SPEC. econs; eauto.
    { mAssert _ with "H".
      { iApply (PRE with "H"). }
      mUpd "A2".
      eapply current_iProp_entail; [eapply CUR|]. start_ipm_proof.
      iSplitR "A2"; [|iExact "A2"].
      iSplitR "A1"; [|iExact "A1"].
      iExact "A".
    }
    { destruct (measure fsp x), o; ss. }
    esplits; eauto.
    i. apply current_iPropL_convert in ACC.
    mDesAll. mSpcUniv "H" with st_src1.
    mSpcUniv "H" with st_tgt1.
    mSpcUniv "H" with ret_src.
    mSpcUniv "H" with ret_tgt.
    mAssert _ with "A".
    { iApply (POST with "A"). }
    mUpd "A2".
    mAssert (#=> back g g Q (Some fuel1) true true (st_src1, itr_src) (st_tgt1, ktr_tgt ret_tgt)) with "*".
    { iApply "H". iSplitR "A2"; [|iExact "A2"].
      iExists w1. iSplit; ss.
    }
    mUpd "A".
    inv ACC. red in IPROP. uipropall. des. subst. eapply IPROP0.
    eapply URA.wf_mon. instantiate (1:=b). r_wf GWF.
  Qed.

  Lemma back_ret
        R_src R_tgt (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g
        v_src v_tgt
        st_src st_tgt
        fuel f_src f_tgt
    :
      bi_entails
        (#=> Q st_src st_tgt v_src v_tgt)
        (back r g Q fuel f_src f_tgt (st_src, Ret v_src) (st_tgt, (Ret v_tgt))).
  Proof.
    eapply back_final. i. apply current_iProp_upd in CUR.
    eapply hsimC_uclo. econs; eauto.
  Qed.

  Lemma back_apc
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g f_src f_tgt st_src st_tgt ktr_src itr_tgt
        fuel0
    :
      bi_entails
        (∃ fuel1, back r g Q fuel1 true f_tgt (st_src, ktr_src tt) (st_tgt, itr_tgt))
        (back r g Q fuel0 f_src f_tgt (st_src, trigger hAPC >>= ktr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i.
    inv CUR. red in IPROP. uipropall. des.
    eapply hsimC_uclo. econs; eauto.
  Qed.

  Lemma back_apc_trigger
        R_tgt
        (Q: Any.t -> Any.t -> unit -> R_tgt -> iProp)
        r g f_src f_tgt st_src st_tgt itr_tgt
        fuel0
    :
      bi_entails
        (∃ fuel1, back r g Q fuel1 true f_tgt (st_src, Ret tt) (st_tgt, itr_tgt))
        (back r g Q fuel0 f_src f_tgt (st_src, trigger hAPC) (st_tgt, itr_tgt)).
  Proof.
    erewrite (@idK_spec _ _ (trigger (hAPC))).
    iIntros "H". iApply back_apc. iExact "H".
  Qed.

  Lemma back_call_impure_trigger
        pre post w0
        (Q: Any.t -> Any.t -> Any.t -> Any.t -> iProp)
        r g fuel f_src f_tgt st_src st_tgt fn arg_src arg_tgt
        (SPEC: fn_has_spec fn pre post false)
    :
      bi_entails
        ((#=> ((pre arg_src arg_tgt: iProp) ** I w0 st_src st_tgt))
           **
           (∀ st_src st_tgt ret_src ret_tgt,
               ((∃ w1, I w1 st_src st_tgt ** ⌜le w0 w1⌝) ** (post ret_src ret_tgt: iProp)) -* #=> Q st_src st_tgt ret_src ret_tgt))
        (back r g Q fuel f_src f_tgt (st_src, trigger (Call fn arg_src)) (st_tgt, trigger (Call fn arg_tgt))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Call fn arg_src))).
    erewrite (@idK_spec _ _ (trigger (Call fn arg_tgt))).
    iIntros "H". iApply back_call_impure; eauto.
    iDestruct "H" as "[H0 H1]". iSplitL "H0"; auto.
    iIntros (st_src0 st_tgt0 ret_src ret_tgt) "H".
    iModIntro. iApply back_ret. iApply "H1". auto.
  Qed.

  Lemma back_call_pure_trigger
        pre post w0
        (Q: Any.t -> Any.t -> unit -> Any.t -> iProp)
        r g f_src f_tgt st_src st_tgt fn arg_src arg_tgt
        (SPEC: fn_has_spec fn pre post true)
    :
      bi_entails
        ((#=> ((pre arg_src arg_tgt: iProp) ** I w0 st_src st_tgt))
           **
           (∀ st_src st_tgt ret_src ret_tgt,
               ((∃ w1, I w1 st_src st_tgt ** ⌜le w0 w1⌝) ** (post ret_src ret_tgt: iProp)) -* #=> Q st_src st_tgt tt ret_tgt))
        (back r g Q (Some (1: Ord.t)) f_src f_tgt (st_src, Ret tt) (st_tgt, trigger (Call fn arg_tgt))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Call fn arg_tgt))).
    iIntros "H". iApply back_call_pure; eauto.
    { oauto. }
    iDestruct "H" as "[H0 H1]". iSplitL "H0"; auto.
    iIntros (st_src0 st_tgt0 ret_src ret_tgt) "H".
    iModIntro. iApply back_ret. iApply "H1". auto.
  Qed.

  Lemma back_syscall
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        fn arg rvs
        r g fuel f_src f_tgt st_src st_tgt ktr_src ktr_tgt
    :
      bi_entails
        (∀ ret, back g g Q None true true (st_src, ktr_src ret) (st_tgt, ktr_tgt ret))
        (back r g Q fuel f_src f_tgt (st_src, trigger (Syscall fn arg rvs) >>= ktr_src) (st_tgt, trigger (Syscall fn arg rvs) >>= ktr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    i. inv CUR. red in IPROP. uipropall. eapply IPROP; eauto.
  Qed.

  Global Instance iProp_back_absorbing
         R_src R_tgt r g (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
         fuel f_src f_tgt st_src st_tgt:
    Absorbing (back r g Q fuel f_src f_tgt st_src st_tgt).
  Proof.
    unfold Absorbing. unfold bi_absorbingly.
    iIntros "[H0 H1]". iApply back_upd.
    iDestruct "H0" as "%". iModIntro. iApply "H1".
  Qed.

  Global Instance iProp_back_elim_upd
         R_src R_tgt r g (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
         fuel f_src f_tgt st_src st_tgt
         P:
    ElimModal True false false (#=> P) P (back r g Q fuel f_src f_tgt st_src st_tgt) (back r g Q fuel f_src f_tgt st_src st_tgt).
  Proof.
    unfold ElimModal. i. iIntros "[H0 H1]".
    iApply back_upd. iMod "H0". iModIntro.
    iApply "H1". iApply "H0".
  Qed.

  Lemma back_syscall_trigger
        (Q: Any.t -> Any.t -> Any.t -> Any.t -> iProp)
        fn arg_src arg_tgt rvs
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (⌜arg_src = arg_tgt⌝ ** ∀ ret, Q st_src st_tgt ret ret)
        (back r g Q fuel f_src f_tgt (st_src, trigger (Syscall fn arg_src rvs)) (st_tgt, trigger (Syscall fn arg_tgt rvs))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Syscall fn arg_src rvs))).
    erewrite (@idK_spec _ _ (trigger (Syscall fn arg_tgt rvs))).
    iIntros "[% H1]". subst.
    iApply back_syscall. iIntros (ret).
    iApply back_ret. iModIntro. iApply "H1".
  Qed.

  Lemma back_tau_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_src itr_tgt
    :
      bi_entails
        (back r g Q None true f_tgt (st_src, itr_src) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, tau;; itr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    eapply back_current; eauto.
  Qed.

  Lemma back_tau_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_src itr_tgt
    :
      bi_entails
        (back r g Q fuel f_src true (st_src, itr_src) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, tau;; itr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    eapply back_current; eauto.
  Qed.

  Lemma back_choose_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt X ktr_src itr_tgt
    :
      bi_entails
        (∃ x, back r g Q None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, trigger (Choose X) >>= ktr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    inv CUR. red in IPROP. uipropall. des. esplits. eapply IPROP; eauto.
  Qed.

  Lemma back_choose_src_trigger
        X
        (Q: Any.t -> Any.t -> X -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (∃ x, Q st_src st_tgt x tt)
        (back r g Q fuel f_src f_tgt (st_src, trigger (Choose X)) (st_tgt, Ret tt)).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Choose X))).
    iIntros "H". iApply back_choose_src.
    iDestruct "H" as (x) "H". iExists x.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_choose_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt X itr_src ktr_tgt
    :
      bi_entails
        (∀ x, back r g Q fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Choose X) >>= ktr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    inv CUR. red in IPROP. uipropall. i. eapply IPROP; eauto.
  Qed.

  Lemma back_choose_tgt_trigger
        X
        (Q: Any.t -> Any.t -> unit -> X -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (∀ x, Q st_src st_tgt tt x)
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, trigger (Choose X))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Choose X))).
    iIntros "H". iApply back_choose_tgt.
    iIntros (x). iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_take_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt X ktr_src itr_tgt
    :
      bi_entails
        (∀ x, back r g Q None true f_tgt (st_src, ktr_src x) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, trigger (Take X) >>= ktr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    inv CUR. red in IPROP. uipropall. i. eapply IPROP; eauto.
  Qed.

  Lemma back_take_src_trigger
        X
        (Q: Any.t -> Any.t -> X -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (∀ x, Q st_src st_tgt x tt)
        (back r g Q fuel f_src f_tgt (st_src, trigger (Take X)) (st_tgt, Ret tt)).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Take X))).
    iIntros "H". iApply back_take_src.
    iIntros (x). iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_take_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt X itr_src ktr_tgt
    :
      bi_entails
        (∃ x, back r g Q fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt x))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (Take X) >>= ktr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    inv CUR. red in IPROP. uipropall. des. esplits. eapply IPROP; eauto.
  Qed.

  Lemma back_take_tgt_trigger
        X
        (Q: Any.t -> Any.t -> unit -> X -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (∃ x, Q st_src st_tgt tt x)
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, trigger (Take X))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (Take X))).
    iIntros "H". iApply back_take_tgt.
    iDestruct "H" as (x) "H". iExists x.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_pput_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src0 st_src1 st_tgt ktr_src itr_tgt
    :
      bi_entails
        (back r g Q None true f_tgt (st_src1, ktr_src tt) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src0, trigger (PPut st_src1) >>= ktr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    eapply back_current; eauto.
  Qed.

  Lemma back_pput_src_trigger
        (Q: Any.t -> Any.t -> unit -> unit -> iProp)
        r g fuel f_src f_tgt st_src0 st_src1 st_tgt
    :
      bi_entails
        (Q st_src1 st_tgt tt tt)
        (back r g Q fuel f_src f_tgt (st_src0, trigger (PPut st_src1)) (st_tgt, Ret tt)).
  Proof.
    erewrite (@idK_spec _ _ (trigger (PPut st_src1))).
    iIntros "H". iApply back_pput_src.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_pget_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt ktr_src itr_tgt
    :
      bi_entails
        (back r g Q None true f_tgt (st_src, ktr_src st_src) (st_tgt, itr_tgt))
        (back r g Q fuel f_src f_tgt (st_src, trigger (PGet) >>= ktr_src) (st_tgt, itr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    eapply back_current; eauto.
  Qed.

  Lemma back_get_src_trigger
        (Q: Any.t -> Any.t -> Any.t -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (Q st_src st_tgt st_src tt)
        (back r g Q fuel f_src f_tgt (st_src, trigger (PGet)) (st_tgt, Ret tt)).
  Proof.
    erewrite (@idK_spec _ _ (trigger (PGet))).
    iIntros "H". iApply back_pget_src.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_pput_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt0 st_tgt1 itr_src ktr_tgt
    :
      bi_entails
        (back r g Q fuel f_src true (st_src, itr_src) (st_tgt1, ktr_tgt tt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt0, trigger (PPut st_tgt1) >>= ktr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    eapply back_current; eauto.
  Qed.

  Lemma back_pput_tgt_trigger
        (Q: Any.t -> Any.t -> unit -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt0 st_tgt1
    :
      bi_entails
        (Q st_src st_tgt1 tt tt)
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt0, trigger (PPut st_tgt1))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (PPut st_tgt1))).
    iIntros "H". iApply back_pput_tgt.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_pget_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_src ktr_tgt
    :
      bi_entails
        (back r g Q fuel f_src true (st_src, itr_src) (st_tgt, ktr_tgt st_tgt))
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, trigger (PGet) >>= ktr_tgt)).
  Proof.
    eapply back_final. i. eapply hsimC_uclo. econs; eauto.
    eapply back_current; eauto.
  Qed.

  Lemma back_pget_tgt_trigger
        (Q: Any.t -> Any.t -> unit -> Any.t -> iProp)
        r g fuel f_src f_tgt st_src st_tgt
    :
      bi_entails
        (Q st_src st_tgt tt st_tgt)
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, trigger (PGet))).
  Proof.
    erewrite (@idK_spec _ _ (trigger (PGet))).
    iIntros "H". iApply back_pget_tgt.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_assume_src
        (Q: Any.t -> Any.t -> unit -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt P
    :
      bi_entails
        (⌜P⌝ -* Q st_src st_tgt tt tt)
        (back r g Q fuel f_src f_tgt (st_src, assume P) (st_tgt, Ret tt)).
  Proof.
    iIntros "H". unfold assume.
    iApply back_bind_left. iApply back_take_src_trigger.
    iIntros (H). iApply back_ret. iModIntro. iApply "H". iPureIntro. auto.
  Qed.

  Lemma back_assume_tgt
        (Q: Any.t -> Any.t -> unit -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt P
    :
      bi_entails
        (⌜P⌝ ∧ Q st_src st_tgt tt tt)
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, assume P)).
  Proof.
    iIntros "H". iDestruct "H" as "[% H]".
    unfold assume. iApply back_bind_right. iApply back_take_tgt_trigger.
    iExists H. iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_guarantee_src
        (Q: Any.t -> Any.t -> unit -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt P
    :
      bi_entails
        (⌜P⌝ ∧ Q st_src st_tgt tt tt)
        (back r g Q fuel f_src f_tgt (st_src, guarantee P) (st_tgt, Ret tt)).
  Proof.
    iIntros "H". iDestruct "H" as "[% H]".
    unfold guarantee. iApply back_bind_left. iApply back_choose_src_trigger.
    iExists H. iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_guarantee_tgt
        (Q: Any.t -> Any.t -> unit -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt P
    :
      bi_entails
        (⌜P⌝ -* Q st_src st_tgt tt tt)
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, guarantee P)).
  Proof.
    iIntros "H". unfold guarantee.
    iApply back_bind_right. iApply back_choose_tgt_trigger.
    iIntros (H). iApply back_ret. iModIntro. iApply "H". iPureIntro. auto.
  Qed.

  Lemma back_triggerUB_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_tgt
    :
      bi_entails
        (⌜True⌝)
        (back r g Q fuel f_src f_tgt (st_src, triggerUB) (st_tgt, itr_tgt)).
  Proof.
    iIntros "H". iApply back_take_src.
    iIntros (x). destruct x.
  Qed.

  Lemma back_triggerNB_src
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_tgt
    :
      bi_entails
        (⌜False⌝)
        (back r g Q fuel f_src f_tgt (st_src, triggerUB) (st_tgt, itr_tgt)).
  Proof.
    iIntros "%". inv H.
  Qed.

  Lemma back_triggerUB_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_src
    :
      bi_entails
        (⌜False⌝)
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, triggerUB)).
  Proof.
    iIntros "%". inv H.
  Qed.

  Lemma back_triggerNB_tgt
        R_src R_tgt
        (Q: Any.t -> Any.t -> R_src -> R_tgt -> iProp)
        r g fuel f_src f_tgt st_src st_tgt itr_src
    :
      bi_entails
        (⌜True⌝)
        (back r g Q fuel f_src f_tgt (st_src, itr_src) (st_tgt, triggerNB)).
  Proof.
    iIntros "H". iApply back_choose_tgt.
    iIntros (x). destruct x.
  Qed.

  Lemma back_unwrapU_src
        X
        (Q: Any.t -> Any.t -> X -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt x
    :
      bi_entails
        (∀ x', ⌜x = Some x'⌝ -* Q st_src st_tgt x' tt)
        (back r g Q fuel f_src f_tgt (st_src, unwrapU x) (st_tgt, Ret tt)).
  Proof.
    iIntros "H". unfold unwrapU. destruct x.
    { iApply back_ret. iModIntro. iApply "H". auto. }
    { iApply back_triggerUB_src. auto. }
  Qed.

  Lemma back_unwrapN_src
        X
        (Q: Any.t -> Any.t -> X -> unit -> iProp)
        r g fuel f_src f_tgt st_src st_tgt x
    :
      bi_entails
        (∃ x', ⌜x = Some x'⌝ ∧ Q st_src st_tgt x' tt)
        (back r g Q fuel f_src f_tgt (st_src, unwrapN x) (st_tgt, Ret tt)).
  Proof.
    iIntros "H". iDestruct "H" as (x') "[% H]". subst. ss.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_unwrapU_tgt
        X
        (Q: Any.t -> Any.t -> unit -> X -> iProp)
        r g fuel f_src f_tgt st_src st_tgt x
    :
      bi_entails
        (∃ x', ⌜x = Some x'⌝ ∧ Q st_src st_tgt tt x')
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, unwrapU x)).
  Proof.
    iIntros "H". iDestruct "H" as (x') "[% H]". subst. ss.
    iApply back_ret. iModIntro. iApply "H".
  Qed.

  Lemma back_unwrapN_tgt
        X
        (Q: Any.t -> Any.t -> unit -> X -> iProp)
        r g fuel f_src f_tgt st_src st_tgt x
    :
      bi_entails
        (∀ x', ⌜x = Some x'⌝ -* Q st_src st_tgt tt x')
        (back r g Q fuel f_src f_tgt (st_src, Ret tt) (st_tgt, unwrapN x)).
  Proof.
    iIntros "H". unfold unwrapN. destruct x.
    { iApply back_ret. iModIntro. iApply "H". auto. }
    { iApply back_triggerNB_tgt. auto. }
  Qed.
End SIM.
#[export] Hint Resolve _hsim_mon: paco.
#[export] Hint Resolve cpn9_wcompat: paco.
