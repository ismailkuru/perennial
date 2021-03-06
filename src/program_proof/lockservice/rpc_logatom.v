From Perennial.algebra Require Import auth_map.
From Perennial.program_proof Require Import proof_prelude marshal_proof.
From Perennial.goose_lang.lib Require Import slice.typed_slice.
From Goose.github_com.mit_pdos.lockservice Require Import lockservice.
From Perennial.program_proof.lockservice Require Import rpc_proof rpc nondet kv_proof fmcounter_map wpc_proofmode common_proof rpc_durable_proof.
Require Import Decimal Ascii String DecimalString.
From Perennial.goose_lang Require Import ffi.grove_ffi.

Section rpc_namespace.

Definition rpcReqInvUpToN_list (seqno:u64) : list coPset :=
 ((λ (n:nat), ↑rpcRequestInvN {| Req_CID:= 0; Req_Seq:=(U64 n) |} ) <$> (seq 0 (int.nat seqno))).
Definition rpcReqInvUpToN (seqno:u64) : coPset :=
 ⋃ rpcReqInvUpToN_list seqno.

(*
Definition rpcReqInvUpToN (seqno:u64) : coPset :=
  [^union list] x ∈ (seq 0 (int.nat seqno)), ↑rpcRequestInvN {| Req_CID:= 0; Req_Seq:=(U64 (Z.of_nat x)) |}. *)

Lemma rpcReqInvUpToN_prop cid seq :
  ∀ seq', int.nat seq' < int.nat seq → (↑rpcRequestInvN {|Req_CID:=cid; Req_Seq:=seq' |}) ⊆ rpcReqInvUpToN seq.
Proof.
  intros seq' Hineq.
  enough (↑rpcRequestInvN {| Req_CID := cid; Req_Seq := seq' |} ∈ rpcReqInvUpToN_list seq).
  {
    intros x Hxin.
    rewrite elem_of_union_list.
    eauto.
  }
  unfold rpcReqInvUpToN_list.
  eapply (elem_of_fmap_2_alt _ _ (int.nat seq')).
  2:{
    unfold rpcRequestInvN.
    simpl.
    replace (U64 (Z.of_nat (int.nat seq'))) with (seq'); first done.
    admit.
  }
  admit.
Admitted.

Lemma rpcReqInvUpToN_prop_2 cid seq :
 ∀ seq', int.nat seq' ≥ int.nat seq → ↑rpcRequestInvN {|Req_CID:=cid; Req_Seq:=seq' |} ## rpcReqInvUpToN seq.
Admitted.

End rpc_namespace.

Section rpc_atomic_pre.
Context `{!heapG Σ}.
Context `{!rpcG Σ u64}.

(* Need this fupd to be OK to fire with any sequence number larger than the *)
Definition rpc_atomic_pre_fupd_def γrpc (cid seq:u64) R : iProp Σ :=
  (own γrpc.(proc) (Excl ()) -∗ cid fm[[γrpc.(lseq)]]≥ int.nat seq ={rpcReqInvUpToN seq}=∗ own γrpc.(proc) (Excl ()) ∗ R)%I.

Definition rpc_atomic_pre_fupd_aux : seal (@rpc_atomic_pre_fupd_def). Proof. by eexists. Qed.
Definition rpc_atomic_pre_fupd := rpc_atomic_pre_fupd_aux.(unseal).
Local Definition rpc_atomic_pre_fupd_eq : @rpc_atomic_pre_fupd = @rpc_atomic_pre_fupd_def := rpc_atomic_pre_fupd_aux.(seal_eq).

Notation "|RN={ γrpc , cid , seq }=> R" :=
 (rpc_atomic_pre_fupd γrpc cid seq R)
 (at level 20, right associativity)
  : bi_scope.


(* This gives the rpc_atomic_pre_fupd for any sequence number that the client can take on
   This is the precondition for ck.MakeRequest(args), where ck has the given cid *)
Definition rpc_atomic_pre_def γrpc cid R : iProp Σ :=
   (∀ seq, cid fm[[γrpc.(cseq)]]↦ int.nat seq -∗
    cid fm[[γrpc.(cseq)]]↦ int.nat seq ∗
    (laterable.make_laterable (|RN={γrpc , cid , seq}=> R))).

Definition rpc_atomic_pre_aux : seal (@rpc_atomic_pre_def). Proof. by eexists. Qed.
Definition rpc_atomic_pre := rpc_atomic_pre_aux.(unseal).
Local Definition rpc_atomic_pre_eq : @rpc_atomic_pre = @rpc_atomic_pre_def := rpc_atomic_pre_aux.(seal_eq).

Notation "|PN={ γrpc , cid }=> R" :=
 (rpc_atomic_pre γrpc cid R)
 (at level 20, right associativity)
  : bi_scope.

Lemma rpc_atomic_pre_fupd_mono_strong γrpc cid seq P Q:
  (P -∗ cid fm[[γrpc.(lseq)]]≥ int.nat seq -∗
     own γrpc.(proc) (Excl ())={rpcReqInvUpToN seq}=∗ own γrpc.(proc) (Excl ()) ∗ Q) -∗
  |RN={γrpc,cid,seq}=> P -∗
  |RN={γrpc,cid,seq}=> Q.
Proof.
  rewrite rpc_atomic_pre_fupd_eq.
  iIntros "HPQ HfupdP Hγproc #Hlb".
  iMod ("HfupdP" with "Hγproc Hlb") as "[Hγproc HP]".
  iSpecialize ("HPQ" with "HP Hlb Hγproc").
  iMod "HPQ".
  iFrame.
  by iModIntro.
Qed.

Lemma modality_rpc_atomic_mixin γrpc cid seq :
  modality_mixin (rpc_atomic_pre_fupd γrpc cid seq ) MIEnvId MIEnvId.
Proof.
  split; simpl; eauto.
  { iIntros (P) "#HP".
    rewrite rpc_atomic_pre_fupd_eq.
    iIntros "$ _ !#". done. }
  { iIntros (P) "HP".
    rewrite rpc_atomic_pre_fupd_eq.
      by iIntros "$ _ !>". }
  { iIntros.
    rewrite rpc_atomic_pre_fupd_eq.
    iIntros "$ _". by iModIntro. }
  {
    iIntros (P Q).
    intros HPQ.
    iApply rpc_atomic_pre_fupd_mono_strong.
    iIntros "HP _ $".
    iModIntro.
    by iApply HPQ.
  }
  {
    iIntros (P Q) "[HP HQ]".
    rewrite rpc_atomic_pre_fupd_eq.
    iIntros "Hγproc #Hlb".
    iDestruct ("HP" with "Hγproc Hlb") as ">[Hγproc $]".
    iDestruct ("HQ" with "Hγproc Hlb") as ">[$ $]".
    by iModIntro.
  }
Qed.

Definition modality_rpc_atomic γrpc cid seq :=
  Modality _ (modality_rpc_atomic_mixin γrpc cid seq).

(* IPM typeclasses for rnfupd *)
Global Instance from_modal_rpc_atomic γrpc cid seq P :
  FromModal (modality_rpc_atomic γrpc cid seq) (|RN={γrpc,cid,seq}=> P) (|RN={γrpc,cid,seq}=> P) P | 2.
Proof. by rewrite /FromModal. Qed.

Global Instance elim_modal_rpc_atomic γrpc p cid seq' seq P Q :
  ElimModal (int.nat seq' ≤ int.nat seq) p false (|RN={γrpc,cid,seq'}=> P) P (|RN={γrpc,cid,seq}=> Q) (|RN={γrpc,cid,seq}=> Q).
Proof.
  rewrite /ElimModal.
  simpl.
  rewrite rpc_atomic_pre_fupd_eq.
  iIntros (Hineq) "[HmodP HwandQ] Hγproc #Hlb".
  iDestruct (intuitionistically_if_elim with "HmodP") as "HmodP".
  iDestruct ("HmodP" with "Hγproc [Hlb]") as "HmodP".
  {
    iApply (fmcounter_map_mono_lb); last done.
    word.
  }

  iMod (fupd_intro_mask' _ _) as "Hclose"; last iMod "HmodP" as "[Hγproc HP]".
  {
    admit. (* property of masks *)
  }
  iDestruct ("HwandQ" with "HP") as "HmodQ".
  iMod "Hclose" as "_".
  iDestruct ("HmodQ" with "Hγproc Hlb") as ">HmodQ".
  iFrame.
  by iModIntro.
Admitted.

Global Instance into_wand_rpc_atomic γrpc cid seq p q R P Q :
  IntoWand p false R P Q → IntoWand' p q R (|RN={γrpc,cid,seq}=> P) (|RN={γrpc,cid,seq}=> Q).
Proof.
  rewrite /IntoWand' /IntoWand /=.
  intros.
  iIntros "HR HmodP".
  iDestruct (H with "HR") as "HwandQ".
  iDestruct (intuitionistically_if_elim with "HmodP") as "HmodP".
  iMod "HmodP".
  iModIntro.
  by iApply "HwandQ".
Qed.

Global Instance from_sep_rpc_atomic γrpc cid seq P Q1 Q2 :
  FromSep P Q1 Q2 → FromSep (|RN={γrpc,cid,seq}=> P) (|RN={γrpc,cid,seq}=> Q1) (|RN={γrpc,cid,seq}=> Q2).
Proof.
  rewrite /FromSep.
  intros Hsep.
  iIntros "[H1 H2]".
  iApply Hsep.
  (* Make a lemma for this. *)

  rewrite rpc_atomic_pre_fupd_eq.
  iIntros "Hγproc #Hlb".
  iDestruct ("H1" with "Hγproc Hlb") as ">[Hγproc $]".
  iDestruct ("H2" with "Hγproc Hlb") as ">[$ $]".
    by iModIntro.
Qed.

(* IPM typeclasses for pnfupd *)

Global Instance elim_modal_rpc_atomic γrpc p cid P Q :
  ElimModal True p false (|PN={γrpc,cid}=> P) (P) (|PN={γrpc,cid}=> Q) (|PN={γrpc,cid}=> Q).
Proof.
  rewrite /ElimModal.
  simpl.
  intros _.
  iIntros "[HmodP HPmodQ]".
  iDestruct (intuitionistically_if_elim with "HmodP") as "HmodP".
  rewrite rpc_atomic_pre_eq.
  iIntros (seq) "Hcown".
  iDestruct ("HmodP" with "Hcown") as "[Hcown HmodP]".
  unfold laterable.make_laterable.
  iDestruct "HmodP" as (R) "[HR HRwandModP]".
  iApply sep_exist_l.
  iExists R. iFrame.
  iModIntro.

  iDestruct "HmodP".
  iFrame.

  iDestruct ("HmodP" with "Hγproc [Hlb]") as "HmodP".
  {
    iApply (fmcounter_map_mono_lb); last done.
    word.
  }

  iMod (fupd_intro_mask' _ _) as "Hclose"; last iMod "HmodP" as "[Hγproc HP]".
  {
    admit. (* property of masks *)
  }
  iDestruct ("HwandQ" with "HP") as "HmodQ".
  iMod "Hclose" as "_".
  iDestruct ("HmodQ" with "Hγproc Hlb") as ">HmodQ".
  iFrame.
  by iModIntro.
Admitted.


Lemma rpc_atomic_pre_mono_strong cid γrpc P Q :
  (∀ seq, RPCClient_own γrpc cid seq -∗ RPCClient_own γrpc cid seq ∗ □(P -∗ |RN={γrpc,cid,seq}=> Q )) -∗
  |PN={γrpc,cid}=> P -∗
  |PN={γrpc,cid}=> Q.
Proof.
  iIntros "HPQ HatomicP".
  rewrite rpc_atomic_pre_eq.
  iIntros (seq) "Hcown".
  iDestruct ("HatomicP" $! seq with "Hcown") as "[Hcown HatomicP]".
  iDestruct ("HPQ" with "Hcown") as "[$ #HPmodQ]".
  unfold laterable.make_laterable.
  iDestruct "HatomicP" as (R) "[HR #HatomicP]".
  iExists (R). iFrame.
  iModIntro.
  iIntros "HR".
  iMod ("HatomicP" with "HR") as "HP".
  iDestruct ("HPmodQ" with "HP") as "$".
Qed.

End rpc_atomic_pre.

Notation "|RN={ γrpc , cid , seq }=> R" :=
 (rpc_atomic_pre_fupd γrpc cid seq R)
 (at level 20, right associativity)
  : bi_scope.

Notation "|PN={ γrpc , cid }=> R" :=
 (rpc_atomic_pre γrpc cid R)
 (at level 20, right associativity)
  : bi_scope.

Section rpc_neutralization.

Context `{!heapG Σ}.
Context `{!rpcG Σ u64}.
Definition neutralized_pre γrpc cid PreCond PostCond : iProp Σ :=
  |PN={γrpc,cid}=> (▷ PreCond ∨ ▷ ∃ ret:u64, PostCond ret)%I.

Lemma neutralize_request (req:RPCRequestID) γrpc γreq (PreCond:iProp Σ) PostCond  :
  is_RPCServer γrpc -∗
  is_RPCRequest γrpc γreq PreCond PostCond req -∗
  (RPCRequest_token γreq) ={⊤}=∗
  <disc> neutralized_pre γrpc req.(Req_CID) PreCond PostCond.
Proof.
    iIntros "#Hsrpc #His_req Hγpost".
    iFrame "#∗".


    iInv "His_req" as "[>#Hcseq_lb_strict HN]" "HNClose".
    iMod ("HNClose" with "[$Hcseq_lb_strict $HN]") as "_".

    iModIntro.
    iModIntro.
    rewrite /neutralized_pre rpc_atomic_pre_eq.
    iIntros (new_seq) "Hcown".
    unfold is_RPCRequest.

    iDestruct (fmcounter_map_agree_lb with "Hcown Hcseq_lb_strict") as %Hnew_seq.
    iFrame.

    iExists (RPCRequest_token γreq).
    iFrame.
    iModIntro.
    rewrite rpc_atomic_pre_fupd_eq.
    iIntros ">Hγpost".

    iIntros "Hγproc #Hlseq_lb".
    iInv "His_req" as "HN" "HNClose".
    { apply (rpcReqInvUpToN_prop req.(Req_CID)). destruct req. simpl in *. word. }
    iDestruct "HN" as "[#>_ [HN|HN]]"; simpl. (* Is cseq_lb_strict relevant for this? *)
    {
      iDestruct "HN" as "[_ [>Hbad|HN]]".
      { iDestruct (own_valid_2 with "Hbad Hγproc") as %?; contradiction. }

      iMod ("HNClose" with "[Hγpost]") as "_".
      { iNext. iFrame "Hcseq_lb_strict". iRight. iFrame.
        iDestruct (fmcounter_map_mono_lb (int.nat req.(Req_Seq)) with "Hlseq_lb") as "$".
        lia.
      }
      iFrame.
      iModIntro.
      iLeft.
      iNext.
      iDestruct "HN" as "[_ $]".
    }
    {
      iDestruct "HN" as "[#Hlseq_lb_req HN]".
      iDestruct "HN" as "[>Hbad|Hreply_post]".
      { by iDestruct (own_valid_2 with "Hγpost Hbad") as %Hbad. }
      iMod ("HNClose" with "[Hγpost]") as "_".
      {
        iNext.
        iFrame "Hcseq_lb_strict".
        iRight.
        iFrame "# ∗".
      }
      iDestruct "Hreply_post" as (last_reply) "[#Hreply Hpost]".
      iModIntro.
      iFrame.
      iRight.
      iExists _; iFrame.
    }
Qed.

Lemma neutralize_idemp γrpc cid seqno Q PreCond PostCond :
  cid fm[[γrpc.(cseq)]]≥ int.nat seqno -∗
  □(▷Q -∗ (rpc_atomic_pre_fupd γrpc cid seqno (▷ PreCond ∨ ▷ ∃ ret:u64, PostCond ret))) -∗
  neutralized_pre γrpc cid Q (PostCond) -∗
  neutralized_pre γrpc cid PreCond PostCond.
Proof.
  iIntros "#Hseqno_lb #Hwand Hatomic_pre".
  iApply rpc_atomic_pre_mono_strong; last done.
  iIntros (seq).
  iIntros "Hcown".
  iDestruct (fmcounter_map_agree_lb with "Hcown Hseqno_lb") as %Hseqno_ineq.
  iFrame.
  iModIntro.
  iIntros "[HQ|Hpost]".
  { iMod ("Hwand" with "HQ") as "HQ". by iModIntro. }
  { iModIntro. by iRight. }
Qed.

Definition neutralized_fupd γrpc cid seqno PreCond PostCond : iProp Σ :=
  |RN={γrpc,cid,seqno}=> (▷ PreCond ∨ ▷ ∃ ret:u64, PostCond ret)%I.

Lemma post_neutralize_instantiate γrpc cid seqno P :
  RPCClient_own γrpc cid seqno -∗
  |PN={γrpc,cid}=> P ={⊤}=∗
  RPCClient_own γrpc cid seqno ∗
  |RN={γrpc,cid,seqno}=> P.
Proof.
  iIntros "Hcrpc Hqpre".
  rewrite rpc_atomic_pre_eq.
  iDestruct ("Hqpre" $! seqno with "Hcrpc") as "[$ Hp]".
  iModIntro.
  iApply (laterable.make_laterable_elim with "Hp").
Qed.

End rpc_neutralization.
