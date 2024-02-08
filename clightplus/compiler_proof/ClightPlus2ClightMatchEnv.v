Require Import CoqlibCCR.
Require Import Skeleton.
Require Import ModSem.
Require Import ClightPlusSkel ClightPlusExprgen.

Set Implicit Arguments.

From compcert Require Import Globalenvs Smallstep AST Integers Events Behaviors Errors Memory Values Maps.
From compcert Require Import Ctypes Clight Clightdefs Globalenvs.

Section MATCH.

  Import List.

  Local Open Scope Z.

  (* global env is fixed when src program is fixed *)
  Variable sk : Sk.t.
  Variable tge : Genv.t Clight.fundef type.

  (* should dummy value in map_blk*)
  Definition dummy_blk : positive := 1%positive.

  Opaque dummy_blk.

  Definition le_dec (p1 p2 : positive) : { Pos.le p1 p2 } + { not (Pos.le p1 p2) }.
  Proof.
    destruct (p1 <=? p2)%positive eqn: E.
    - left. eapply Pos.leb_le; et.
    - right. eapply Pos.leb_gt in E; nia.
  Qed.

  Definition map_blk : positive -> block :=
    fun blk =>
      if (le_dec (Pos.of_succ_nat (length sk)) blk)%positive
      then 
        match Zpos blk + (Z.pos tge.(Genv.genv_next) - Z.pos (Pos.of_succ_nat (length sk))) with
        | Zpos tblk => tblk
        | _ => dummy_blk (* unreachable *)
        end
      else
        let sg := load_skenv sk in
        match sg.(SkEnv.blk2id) (pred (Pos.to_nat blk)) with
        | Some name =>
          match Genv.find_symbol tge (ident_of_string name) with
          | Some tblk => tblk
          | None => dummy_blk
          end
        | None => dummy_blk
        end
  .

  Definition map_val (v : val) : val :=
    match v with
    | Vptr blk ofs => Vptr (map_blk blk) ofs
    | _ => v
    end.

  Definition map_memval (mv : memval) : memval :=
    match mv with
    | Fragment v q n => Fragment (map_val v) q n
    | _ => mv
    end.

  Variant match_ge : Prop :=
  | match_ge_intro
      (WFSK: Sk.wf sk)
      (MGE: forall id idx, SkEnv.id2blk (load_skenv sk) (string_of_ident id) = Some idx -> Genv.find_symbol tge id = Some (map_blk (Pos.of_succ_nat idx)))
      (ELEM: forall s n gd, nth_error sk n = Some (s, gd) -> Genv.find_def tge (map_blk (Pos.of_succ_nat n)) = Some gd)
    :
      match_ge.


  (* alist <-> ptree conversion needs well-formedness of ptree *)
  (* TODO: when we construct initial envs, we should check disjointness of source ids *)
  (* this is justified with pre-existing triggerUB ofs id-repet *)

  Variant match_le : ClightPlusExprgen.temp_env -> temp_env -> Prop :=
  | match_le_intro
      sle tle 
      (ML: forall id sv, alist_find (string_of_ident id) sle = Some sv -> Maps.PTree.get id tle = Some (map_val sv))
    :
      match_le sle tle.

  Definition map_env_entry (entry: ident * Values.block * type) :=
    let '(id, b, ty) := entry in
    (string_of_ident id, map_blk b, ty).

  Variant match_e : ClightPlusExprgen.env -> env -> Prop :=
  | match_e_intro
      se te 
      (MCE: forall i a, Permutation (PTree.elements te) (map se))
    :
      match_e se te.

  Lemma env_match_some e te b ty i
      (MCE: match_e e te)
    :
      alist_find (string_of_ident i) e = Some (b, ty) -> te ! i = Some (map_blk b, ty).
  Proof.
    i. apply PTree.elements_complete. inv MCE. rewrite MCE0.
    rewrite alist_find_map_snd. uo. des_ifs.
  Qed.

  Lemma env_match_none e te i
      (MCE: match_e e te)
    :
      alist_find (string_of_ident i) e = None -> te ! i = None.
  Proof.
    i. destruct (te ! i) eqn:?; et. apply PTree.elements_correct in Heqo. 
    inv MCE. rewrite MCE0 in Heqo. rewrite alist_find_map_snd in Heqo. uo.
    des_ifs.
  Qed.

  Variant match_ce : comp_env -> composite_env -> Prop :=
  | match_ce_intro
      sce tce
      (* (CEWF: NoDup (map fst sce)) *)
      (MCE: forall i co, In (i, co) (PTree.elements tce) <-> alist_find (string_of_ident i) sce = Some co)
    :
      match_ce sce tce.

  Lemma cenv_match_some ce tce co i
      (MCE: match_ce ce tce)
    :
      alist_find (string_of_ident i) ce = Some co -> tce ! i = Some co.
  Proof.
    i. apply PTree.elements_complete. inv MCE. rewrite MCE0. et.
  Qed.

  Lemma cenv_match_none ce tce i
      (MCE: match_ce ce tce)
    :
      alist_find (string_of_ident i) ce = None -> tce ! i = None.
  Proof.
    i. destruct (tce ! i) eqn:?; et. apply PTree.elements_correct in Heqo. 
    inv MCE. rewrite MCE0 in Heqo. clarify.
  Qed.

  Variant match_mem : Memory.Mem.mem -> Memory.Mem.mem -> Prop :=
  | match_mem_intro
      m tm
      (INITIALIZED: (Pos.of_succ_nat (length sk) <= m.(Mem.nextblock))%positive)
      (NBLK: tm.(Mem.nextblock) = map_blk (m.(Mem.nextblock)))
      (MEM_CNT: forall b ofs mv, PMap.get ofs (PMap.get b m.(Mem.mem_contents)) = mv -> PMap.get ofs (PMap.get (map_blk b) tm.(Mem.mem_contents)) = map_memval mv)
      (MEM_PERM: forall b, PMap.get b m.(Mem.mem_access) = Maps.PMap.get (map_blk b) tm.(Mem.mem_access) )
      (MEM_CONC: forall b, PTree.get b m.(Mem.mem_concrete) = Maps.PTree.get (map_blk b) tm.(Mem.mem_concrete) )
    :
      match_mem m tm.

End MATCH.