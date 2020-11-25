From Coq.Structures Require Import OrdersTac.
From stdpp Require Import gmap.
From iris.algebra Require Import numbers.
From iris.program_logic Require Export weakestpre.
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.
From Perennial.goose_lang Require Import notation.
From Perennial.program_proof Require Import proof_prelude.
From RecordUpdate Require Import RecordUpdate.
From Perennial.algebra Require Import auth_map.
From Perennial.goose_lang.lib Require Import lock.
From Perennial.goose_lang.lib Require Import crash_lock.
From Perennial.Helpers Require Import NamedProps.
From Perennial.Helpers Require Import ModArith.
From Perennial.program_proof.lockservice Require Import lockservice_crash rpc_proof rpc_durable nondet kv_proof fmcounter_map.

Section kv_durable_proof.
Context `{!heapG Σ, !kvserviceG Σ, stagedG Σ}.

Implicit Types (γ : kvservice_names).

Local Notation "k [[ γ ]]↦ '_'" := (∃ v, k [[γ]]↦ v)%I
(at level 20, format "k  [[ γ ]]↦ '_'") : bi_scope.

Record RPCServerC :=
  {
  lastSeqM : gmap u64 u64;
  lastReplyM  : gmap u64 u64;
  }.

Record KVServerC :=
  {
  sv : RPCServerC ;
  kvsM : gmap u64 u64;
  }.

(**
  Old crash-safety plan:

  KVServer_core_own_vol kvserver: ownership of volatile (in-memory) state, that can be directly modified by the core function

  KVServer_core_own_ghost kvserver: ownership of state that isn't supposed to be modified until the durable write (i.e. this is ghost state associated with the core function's spec)

  RPCServer_core_own_vol rpcserver: same as above, but for RPCServer
  RPCServer_core_own_ghost rpcserver: same as above, but for RPCServer

  KVServer_durable_own : ownership of durable state for the KVServer, including the contained RPCServer object

  This is what must be proved about a core function.
  ∀ R,
  { _core_own_vol old_state ∗ R ∗ cinv_sem R (PreCond args) }
    coreFunction args
  { _core_own_vol new_state ∗ R ∗ (PreCond args -∗ _core_own_ghost old_state ={⊤}=∗ _core_own_ghost new_state ∗ PostCond args ret) }
  The point of the cinv_sem is that the coreFunction and R is that the core function can access the PreCond as often as it likes, so long as it maintains it. It wouldn't make sense to put it in an inv, because the PreCond won't always hold.

  This might look a bit logically like having a quadruple that looks something like { ... ∗ PreCond } coreFunction args { ... ∗ PreCond } { PreCond }.
  But, that would make sense if the PreCond was used somewhere in some recovery function. But, the requests don't disappear after a crash, and there's no such thing as "recovery for a sent request". Instead, the RPCRequest invariant governs what the req looks like for all-time, so the core function spec is also in terms of a (weaker) invariant (the cinv_sem).

  From the core function spec, we get a fupd that allows us to simultaneously get the PostCond from the PreCond, and to update the ghost state.
  For the kvserver put, this fupd would use the map_ctx for γkv and the ptsto from PreCond, and give back a new ptsto and new map_ctx (necessarily the map_ctx for the new_state).

  { _core_own_vol new_state ∗ _durable_own old_state }
    makeDurable
  { _core_own_vol new_state ∗ _durable_own new_state }
  { _durable_own new_state ∨ _durable_own old_state } (* atomicity of makeDurable *)


  The crash obligation while holding the server mutex is (|={⊤}=> ∃ some_state, _core_own_ghost some_state ∗ _durable_own some_state).
  When we call makeDurable, we need to make sure that the crash obligation of makeDurable together with the resources left over (the ones we didn't pass as PreCond of makeDurable) imply the crash obligation (this is the <blah> -∗ Φc part of the makeDurable quadruple spec). In other words, we'll have an obligation to prove

  _durable_own_new_state ∨ _durable_own old_state ={⊤}=∗ ∃ some_state, _core_own_ghost some_state ∗ _durable_own some_state

  We simply split into the two cases, and fire the fupd in the second case to update ghost state to match the new durable state.

  Additionally, we also will be forced to apply the fupd to update the state of _own_ghost to match the durable state; this will also give us the reply receipt, which is the postcondition for the HandleRequest function. The client can, as before, take the PostCond out of RPCRequest_inv.

*)

(**

New crash-safety plan:

The old plan suffers from the same problem as original perennial. You have to
keep opening and closing the invariant, so you might lose some information,
unless you use something like recovery leases.

Here's a better approach:
To get out the PreCond, the server must put a token in the invariant. We keep
ownership of this token in the server's mutex invariant (the ghost part).
This means that if we have an obligation to prove that we never lose these
tokens as we execute code while holding the lock. When we take PreCond out of
the invariant, we'll actually get PreCond \ast \gamma P. Finally, we can show
that the crash condition for owning the token is implied by
PreCond \ast \gamma P. Namely, with \gamma P and PreCond in hand, on a crash,
we can open up the invariant, show that we are in the unprocesssed case of the
invariant (by using the RPCServer_own that we have not changed yet), then use
the \gamma P and PreCond to get back the token that we need for our crash
obligation.

By doing this, we can pass in P to a function that has P in its crash
condition, and show that it implies our crash condition! So the core function
proof no longer needs to repeatedly open and close an invariant.

For token, we can get away with using the fmcounter_map lseq ptsto for that
client. For now, this'll allow us to avoid needing to add more ghost state to
coordinate this stuff.
*)

Axiom KVServer_durable_own : KVServerC -> iProp Σ.

Definition KVServer_core_own_vol (srv:loc) kv_server : iProp Σ :=
  ∃ (kvs_ptr:loc),
  "HkvsOwn" ∷ srv ↦[KVServer.S :: "kvs"] #kvs_ptr ∗
  "HkvsMap" ∷ is_map (kvs_ptr) kv_server.(kvsM)
.

Definition KVServer_core_own_ghost γ kv_server : iProp Σ :=
  "Hkvctx" ∷ map_ctx γ.(ks_kvMapGN) 1 kv_server.(kvsM)
.

Definition KVServer_core_own γ (srv:loc) kv_server : iProp Σ :=
  "Hkvvol" ∷ KVServer_core_own_vol srv kv_server ∗
  "Hkvghost" ∷ KVServer_core_own_ghost γ kv_server
.

Definition KVServer_mutex_cinv γ : iProp Σ :=
  ∃ kv_server,
  "Hkvdurable" ∷ KVServer_durable_own kv_server
∗ "Hsrpc" ∷ RPCServer_own γ.(ks_rpcGN) kv_server.(sv).(lastSeqM) kv_server.(sv).(lastReplyM)
∗ "Hkvctx" ∷ map_ctx γ.(ks_kvMapGN) 1 kv_server.(kvsM)
.

Definition RPCServer_own_vol (sv:loc) rpc_server : iProp Σ :=
  ∃ (lastSeq_ptr lastReply_ptr:loc),
    "HlastSeqOwn" ∷ sv ↦[RPCServer.S :: "lastSeq"] #lastSeq_ptr
∗ "HlastReplyOwn" ∷ sv ↦[RPCServer.S :: "lastReply"] #lastReply_ptr
∗ "HlastSeqMap" ∷ is_map (lastSeq_ptr) rpc_server.(lastSeqM)
∗ "HlastReplyMap" ∷ is_map (lastReply_ptr) rpc_server.(lastReplyM)
.

Definition RPCServer_own_ghost (sv:loc) γrpc rpc_server : iProp Σ :=
  "Hsrpc" ∷ RPCServer_own γrpc rpc_server.(lastSeqM) rpc_server.(lastReplyM) (* TODO: Probably should get better naming for this *)
.

Definition RPCServer_phys_own γrpc (sv:loc) rpc_server : iProp Σ :=
  "Hrpcvol" ∷ RPCServer_own_vol sv rpc_server ∗
  "Hrpcghost" ∷ RPCServer_own_ghost sv γrpc rpc_server
.

Instance durable_timeless kv_server : Timeless (KVServer_durable_own kv_server).
Admitted.

Instance durable_disc kv_server : Discretizable (KVServer_durable_own kv_server).
Admitted.

Definition KVServer_mutex_inv srv_ptr sv_ptr γ : iProp Σ :=
  ∃ kv_server,
    "Hkv" ∷ KVServer_core_own γ srv_ptr kv_server ∗
    "Hrpc" ∷ RPCServer_phys_own γ.(ks_rpcGN) sv_ptr kv_server.(sv) ∗
    "Hkvdurable" ∷ KVServer_durable_own kv_server
.

Definition mutexN : namespace := nroot .@ "kvmutexN".

Definition is_kvserver (srv_ptr sv_ptr:loc) γ : iProp Σ :=
  ∃ (mu_ptr:loc),
  "#Hsv" ∷ readonly (srv_ptr ↦[KVServer.S :: "sv"] #sv_ptr) ∗
  "#Hlinv" ∷ is_RPCServer γ.(ks_rpcGN) ∗
  "#Hmu_ptr" ∷ readonly(sv_ptr ↦[RPCServer.S :: "mu"] #mu_ptr) ∗
  "#Hmu" ∷ is_crash_lock mutexN 37 #mu_ptr (KVServer_mutex_inv srv_ptr sv_ptr γ)
    (|={⊤}=> KVServer_mutex_cinv γ)
.

Definition own_kvclerk γ ck_ptr srv : iProp Σ :=
  ∃ (cl_ptr:loc),
   "Hcl_ptr" ∷ ck_ptr ↦[KVClerk.S :: "client"] #cl_ptr ∗
   "Hprimary" ∷ ck_ptr ↦[KVClerk.S :: "primary"] #srv ∗
   "Hcl" ∷ own_rpcclient cl_ptr γ.(ks_rpcGN).

Lemma CheckReplyTable_spec (reply_ptr:loc) (req:Request64) (reply:Reply64) γ (lastSeq_ptr lastReply_ptr:loc) lastSeqM lastReplyM :
{{{
     "%" ∷ ⌜int.nat req.(Req_Seq) > 0⌝
    ∗ "#Hrinv" ∷ is_RPCServer γ.(ks_rpcGN)
    ∗ "HlastSeqMap" ∷ is_map (lastSeq_ptr) lastSeqM
    ∗ "HlastReplyMap" ∷ is_map (lastReply_ptr) lastReplyM
    ∗ ("Hsrpc" ∷ RPCServer_own γ.(ks_rpcGN) lastSeqM lastReplyM)
    ∗ ("Hreply" ∷ own_reply reply_ptr reply)
}}}
CheckReplyTable #lastSeq_ptr #lastReply_ptr #req.(Req_CID) #req.(Req_Seq) #reply_ptr @ 36; ⊤
{{{
     (b:bool) reply', RET #b;
      "Hreply" ∷ own_reply reply_ptr reply'
    ∗ "Hcases" ∷ ("%" ∷ ⌜b = false⌝
         ∗ "%" ∷ ⌜(int.Z req.(Req_Seq) > int.Z (map_get lastSeqM req.(Req_CID)).1)%Z⌝
         ∗ "%" ∷ ⌜reply'.(Rep_Stale) = false⌝
         ∗ "HlastSeqMap" ∷ is_map (lastSeq_ptr) (<[req.(Req_CID):=req.(Req_Seq)]>lastSeqM)
         ∨ 
         "%" ∷ ⌜b = true⌝
         ∗ "HlastSeqMap" ∷ is_map (lastSeq_ptr) lastSeqM
         ∗ ((⌜reply'.(Rep_Stale) = true⌝ ∗ RPCRequestStale γ.(ks_rpcGN) req)
          ∨ RPCReplyReceipt γ.(ks_rpcGN) req reply'.(Rep_Ret)))

    ∗ "HlastReplyMap" ∷ is_map (lastReply_ptr) lastReplyM
    ∗ ("Hsrpc" ∷ RPCServer_own γ.(ks_rpcGN) lastSeqM lastReplyM)
}}}
{{{
    RPCServer_own γ.(ks_rpcGN) lastSeqM lastReplyM
}}}
.
Proof.
  iIntros (Φ Φc) "Hpre Hpost".
  iNamed "Hpre".
  wpc_call.
  { iNext. iFrame. }
  { iNext. iFrame. }
  iCache with "Hsrpc Hpost".
  { iDestruct "Hpost" as "[Hpost _]". iModIntro. iNext. by iApply "Hpost". }
  wpc_pures.
  iApply wpc_fupd.
  wpc_frame.
  wp_apply (wp_MapGet with "HlastSeqMap").
  iIntros (v ok) "(HSeqMapGet&HlastSeqMap)"; iDestruct "HSeqMapGet" as %HSeqMapGet.
  wp_pures.
  iNamed "Hreply".
  wp_storeField.
  wp_apply (wp_and ok (int.Z req.(Req_Seq) ≤ int.Z v)%Z).
  { wp_pures. by destruct ok. }
  { iIntros "_". wp_pures. done. }
  rewrite bool_decide_decide.
  destruct (decide (ok ∧ int.Z req.(Req_Seq) ≤ int.Z v)%Z) as [ [Hok Hineq]|Hmiss].
  { (* Cache hit *)
    destruct ok; last done. clear Hok. (* ok = false *)
    wp_pures.
    apply map_get_true in HSeqMapGet.
    destruct bool_decide eqn:Hineqstrict.
    - wp_pures.
      apply bool_decide_eq_true in Hineqstrict.
      wp_storeField.
      iNamed 1.
      iMod (smaller_seqno_stale_fact with "[] Hsrpc") as "[Hsrpc #Hstale]"; eauto.
      iDestruct "Hpost" as "[_ Hpost]".
      iApply "Hpost".
      iModIntro.
      iSplitL "HReplyOwnStale HReplyOwnRet".
      { eauto with iFrame. instantiate (1:={| Rep_Ret:=_; Rep_Stale:=_ |}).
        iFrame. }
      iFrame; iFrame "#".
      iRight.
      eauto with iFrame.
    - wp_pures.
      assert (v = req.(Req_Seq)) as ->. {
        (* not strict + non-strict ineq ==> eq *)
        apply bool_decide_eq_false in Hineqstrict.
        assert (int.Z req.(Req_Seq) = int.Z v) by lia; word.
      }
      wp_apply (wp_MapGet with "HlastReplyMap").
      iIntros (reply_v reply_get_ok) "(HlastReplyMapGet & HlastReplyMap)"; iDestruct "HlastReplyMapGet" as %HlastReplyMapGet.
      wp_storeField.
      iNamed 1.
      iMod (server_replies_to_request with "[Hrinv] [Hsrpc]") as "[#Hreceipt Hsrpc]"; eauto.
      iApply "Hpost".
      iModIntro.
      iSplitL "HReplyOwnStale HReplyOwnRet".
      { eauto with iFrame. instantiate (1:={| Rep_Ret:=_; Rep_Stale:=_ |}).
        iFrame. }
      iFrame.
      iRight.
      by iFrame; iFrame "#".
  }
  { (* Cache miss *)
    wp_pures.
    apply not_and_r in Hmiss.
    wp_apply (wp_MapInsert _ _ lastSeqM _ req.(Req_Seq) (#req.(Req_Seq)) with "HlastSeqMap"); eauto.
    iIntros "HlastSeqMap".
    wp_seq.
    iNamed 1.
    iDestruct "Hpost" as "[_ Hpost]".
    iApply ("Hpost" $! _ ({| Rep_Stale:=false; Rep_Ret:=reply.(Rep_Ret) |}) ).
    iModIntro.
    iFrame; iFrame "#".
    iLeft. iFrame. iPureIntro.
    split; eauto. split; eauto. injection HSeqMapGet as <- Hv. simpl.
    destruct Hmiss as [Hnok|Hineq].
    - destruct ok; first done.
      destruct (lastSeqM !! req.(Req_CID)); first done.
      simpl. word.
    - word.
  }
Qed.

Variable coreFunction:goose_lang.val.
Variable makeDurable:goose_lang.val.
Variable PreCond:RPCValC -> iProp Σ.
Variable PostCond:RPCValC -> u64 -> iProp Σ.
Variable srv_ptr:loc.
Variable sv_ptr:loc.

Lemma wp_coreFunction γ (args:RPCValC) kvserver :
  {{{
       "Hvol" ∷ KVServer_core_own_vol srv_ptr kvserver ∗
       "Hpre" ∷ (PreCond args)
 }}}
    coreFunction (into_val.to_val args) @ 36; ⊤
 {{{
      (* TODO: need the disc to proof work out *)
      kvserver' (r:u64) P', RET #r; 
            ⌜Discretizable P'⌝ ∗
             (P') ∗
            KVServer_core_own_vol srv_ptr kvserver' ∗
            □ (P' -∗ PreCond args) ∗
            (* TODO: putting this here because need to be discretizable *)
            □ (▷ P' -∗ KVServer_core_own_ghost γ kvserver ==∗ PostCond args r ∗ KVServer_core_own_ghost γ kvserver')
 }}}
 {{{
      (PreCond args)
 }}}
.
Admitted.

(**
 Precondition owns all of the physical state of the server.
 Postcondition gives it back *unchanged*, but updates the durable state.

(P -∗ core_own)
P

(P -∗ Q)
P

Q is something such that (Q -∗ )

use to get core_own. destruct ∃'s. take a bunch of steps using mem ptsto's from core_own.
Then, want to give back P.

This is a probably unsound hack just to get back the same existentially quantified ptrs that make up KVServer_core_own_vol. Otherwise, would need to iDestruct again. In this particular code, it isn't an issue to iDestruct it again, but it would be a problem if we wrote code that saved, e.g. lastSeq_ptr in a local var, and then did something with that local var after wpc_makeDurable, since we won't be able to show that the new lastSeq_ptr is the same as before.

Doing this hack because there I feel like to be a better way than explicitly writing out the existentially quantified vars as arguments to wpc_makeDurable.

  □(P -∗
     KVServer_core_own_vol γ srv kv_server
  ) -∗
  {{{
      "HP" ∷ P ∗
      "Holdkv" ∷ KVServer_durable_own old_kv_server
  }}}

*)
Lemma wpc_makeDurable old_kv_server kv_server :
  {{{
     KVServer_core_own_vol srv_ptr kv_server ∗
     RPCServer_own_vol sv_ptr kv_server.(sv) ∗
     KVServer_durable_own old_kv_server
  }}}
    makeDurable #() @ 36 ; ⊤
  {{{
       RET #(); KVServer_durable_own kv_server ∗
     KVServer_core_own_vol srv_ptr kv_server ∗
     RPCServer_own_vol sv_ptr kv_server.(sv)
  }}}
  {{{
 KVServer_durable_own old_kv_server ∨ KVServer_durable_own kv_server
}}}.
Admitted.

Lemma wp_RPCServer__HandleRequest' (req_ptr reply_ptr:loc) (req:Request64) (reply:Reply64) γ γPost γPre:
{{{
  "#Hls" ∷ is_kvserver srv_ptr sv_ptr γ
  ∗ "#HreqInv" ∷ is_durable_RPCRequest γ.(ks_rpcGN) γPost γPre PreCond PostCond req
  ∗ "#Hreq" ∷ read_request req_ptr req
  ∗ "Hreply" ∷ own_reply reply_ptr reply
}}}
  RPCServer__HandleRequest #sv_ptr coreFunction makeDurable #req_ptr #reply_ptr
{{{ RET #false; ∃ reply':Reply64, own_reply reply_ptr reply'
    ∗ ((⌜reply'.(Rep_Stale) = true⌝ ∗ RPCRequestStale γ.(ks_rpcGN) req)
  ∨ RPCReplyReceipt γ.(ks_rpcGN) req reply'.(Rep_Ret))
}}}.
Proof.
  iIntros (Φ) "Hpre Hpost".
  iNamed "Hpre".
  wp_lam.
  wp_pures.
  iNamed "Hls".
  wp_loadField.
  wp_apply (crash_lock.acquire_spec with "Hmu"); first done.
  iIntros "Hlocked".
  wp_pures.
  iApply (wpc_wp _ _ _ _ _ True).

  (*
  iDestruct "Hlocked" as "(Hinv & #Hmu_nc & Hlocked)".
  iApply (wpc_na_crash_inv_open with "Hinv"); eauto.
  iSplit; first by iModIntro.
   *)
  wpc_bind_seq.
  crash_lock_open "Hlocked".
  { eauto. }
  { by iModIntro. }
  iIntros ">Hlsown".
  iNamed "Hlsown".
  iNamed "Hkv". iNamed "Hrpc".
  iNamed "Hreq".
  (* this iNamed stuff is a bit silly *)

  unfold RPCServer_own_ghost. iNamed "Hrpcghost".
  iCache with "Hkvdurable Hkvghost Hsrpc".
  { iModIntro; iNext. iSplit; first done.
    iExists _; iFrame. by iModIntro.
  }
  wpc_loadField.
  wpc_loadField.

  iNamed "Hrpcvol".
  (* Do loadField on non-readonly ptsto *)
  wpc_bind (struct.loadF _ _ _).
  wpc_frame.
  wp_loadField.
  iNamed 1.

  (* This is the style of the wpc_loadField tactic *)
  wpc_bind (struct.loadF _ _ _).
  wpc_frame_go "HlastSeqOwn" base.Right [INamed "HlastSeqOwn"].
  wp_loadField.
  iNamed 1.

  wpc_apply (CheckReplyTable_spec with "[$Hsrpc $HlastSeqMap $HlastReplyMap $Hreply]"); first eauto.
  iSplit.
  { iModIntro. iNext. iIntros. iSplit; first done.
    iExists _; iFrame. by iModIntro. }
  iNext.
  iIntros (b reply').
  iNamed 1.

  destruct b.
  - (* Seen request in reply table; easy because we don't touch durable state *)
    wpc_pures.
    iDestruct "Hcases" as "[Hcases|Hcases]".
    { (* Wrong case of postcondition of CheckReplyTable *) 
      iNamed "Hcases"; discriminate. }
    iNamed "Hcases".
    (* Do loadField on non-readonly ptsto *)
    iSplitR "Hkvvol Hkvdurable Hsrpc HlastSeqOwn HlastReplyOwn Hkvghost HlastSeqMap HlastReplyMap"; last first.
    {
      iNext. iExists _; iFrame.
      iExists _, _; iFrame.
    }
    iIntros "Hlocked".
    iSplit.
    { by iModIntro. }
    wpc_pures; first by iModIntro.
    iApply (wp_wpc).
    wp_loadField.
    wp_apply (crash_lock.release_spec with "[$Hlocked]"); first done.
    wp_pures.
    iApply "Hpost".
    iExists _; iFrame.
  - (* Case of actually running core function and updating durable state *)
    wpc_pures.

    iDestruct "Hcases" as "[Hcases | [% _]]"; last discriminate.
    iNamed "Hcases".

    repeat (wpc_bind (struct.loadF _ _ _);
    wpc_frame;
    wp_loadField;
    iNamed 1).
    iMod (server_takes_request with "[] Hsrpc") as "(HγPre & Hpre & Hsrpc_proc)"; eauto.
    (* FIXME: Hpre starts with a ▷ but we need it without. *)
    wpc_apply (wp_coreFunction with "[Hpre $Hkvvol]").
    iSplit.
    {
      iModIntro. iNext. iIntros "Hpre".
      iSplit; first done.
      iMod (server_returns_request with "[HreqInv] HγPre Hpre Hsrpc_proc") as "Hsrpc"; eauto.
      iModIntro.
      iExists _; iFrame.
    }
    iNext.
    iIntros (kvserver' retval P').
    iIntros "(% & HP' & Hkvvol & #HPimpliesPre & #Hfupd)".
    iCache with "Hkvdurable HγPre HP' Hsrpc_proc Hkvghost".
    {
      iModIntro. iNext.
      iSplit; first done.
      iDestruct ("HPimpliesPre" with "HP'") as "Hpre".
      iMod (server_returns_request with "[HreqInv] HγPre Hpre Hsrpc_proc") as "Hsrpc"; eauto.
      iModIntro.
      iExists _; iFrame.
    }

    iNamed "Hreply".

    (* wpc_storeField *)
    wpc_bind (struct.storeF _ _ _ _).
    wpc_frame.
    wp_storeField.
    iNamed 1.

    wpc_pures.
    repeat (wpc_bind (struct.loadF _ _ _);
    wpc_frame;
    wp_loadField;
    iNamed 1).

    wpc_bind_seq.
    wpc_frame.
    wp_apply (wp_MapInsert with "HlastReplyMap"); first eauto; iIntros "HlastReplyMap".
    iNamed 1.
    wpc_pures.
    iApply wpc_fupd.
    wpc_apply (wpc_makeDurable _ {| kvsM := _; sv :=
                                                 {| lastSeqM := (<[req.(Req_CID):=req.(Req_Seq)]> kv_server.(sv).(lastSeqM)) ;
                                                    lastReplyM := (<[req.(Req_CID):=retval]> kv_server.(sv).(lastReplyM))
                                                 |}
                                 |} with "[-Hpost Hkvghost Hsrpc_proc HP' HγPre HReplyOwnRet HReplyOwnStale]").
    { iFrame. simpl. iExists _, _. iFrame. }
    iSplit.
    { (* show that crash condition of makeDurable maintains our crash condition *)
      iModIntro. iNext.
      iIntros "Hkvdurable".
      iSplit; first done.

      iDestruct "Hkvdurable" as "[Hkvdurable|Hkvdurable]".
      + iDestruct ("HPimpliesPre" with "HP'") as "Hpre".
        iMod (server_returns_request with "[HreqInv] HγPre Hpre Hsrpc_proc") as "Hsrpc"; eauto.
        iModIntro. iExists _; iFrame.
      + iDestruct (server_executes_durable_request' with "HreqInv Hlinv [Hsrpc_proc] HγPre [HP' Hfupd] Hkvghost") as "HH"; eauto.
        {
          iExists P'. iFrame "HP'".
          iFrame "Hfupd".
        }
        iMod "HH" as "(Hreceipt & Hsrpc & Hkvghost)"; eauto.
        unfold KVServer_core_own_ghost.
        iExists _; iFrame "Hkvdurable".
        simpl. by iFrame.
    }
    iNext. iIntros "[Hkvdurable Hsrvown]".
    simpl.
    iMod (server_executes_durable_request' with "HreqInv Hlinv [Hsrpc_proc] HγPre [HP' Hfupd] Hkvghost") as "HH"; eauto.
    { iExists P'. iFrame "HP'".
      iFrame "Hfupd". }
    iDestruct "HH" as "(Hreceipt & Hsrpc & Hkvghost)".
    iModIntro.
    iSplitR "Hsrvown Hkvdurable Hkvghost Hsrpc"; last first.
    {
      iNamed "Hsrvown".
      iNext. iExists _. iFrame "Hkvdurable".
      iFrame.
    }

    iIntros "Hlocked".
    iSplit; first by iModIntro.
    iApply (wp_wpc).

    wp_pures.
    wp_loadField.
    iApply wp_fupd.
    wp_apply (crash_lock.release_spec with "Hlocked"); first eauto.
    wp_pures.
    iApply "Hpost".
    iModIntro.
    iExists {| Rep_Stale:=_ ; Rep_Ret:=retval |}; iFrame.
Qed.

End kv_proof.
