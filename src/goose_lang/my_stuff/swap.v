(* autogenerated from swap *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

Module SwapVar.
  Definition S := struct.decl [
    "val" :: uint64T
  ].
End SwapVar.

Definition swap: val :=
  rec: "swap" "x" "y" :=
    let: "tmp" := struct.loadF SwapVar.S "val" "x" in
    struct.storeF SwapVar.S "val" "x" (struct.loadF SwapVar.S "val" "y");;
    struct.storeF SwapVar.S "val" "y" "tmp".

Definition rotate_r: val :=
  rec: "rotate_r" "x" "y" "z" :=
    swap "y" "z";;
    swap "x" "y".

Definition rotate_l: val :=
  rec: "rotate_l" "x" "y" "z" :=
    swap "x" "y";;
    swap "y" "z".

(* should really put this in a second file and import, but i'm struggling w that rn *)
(* also, having to put this down here is ***sus as hell*** *)
From Perennial.goose_lang.lib Require Import encoding.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.program_proof Require Import disk_lib.
From Perennial.program_proof Require Import marshal_proof.

Section proof.
Context `{!heapG Σ}.

(* why in the world does the ↦ need to be tight on the right side *)
Definition swap_var_fields (l:loc) (x: u64): iProp Σ :=
  l ↦[SwapVar.S :: "val"] #x.

Definition is_swap_var (l:loc) (x:u64) : iProp Σ :=
  swap_var_fields l x.

Lemma swap_spec x y a b :
  {{{ (is_swap_var x a) ∗ (is_swap_var y b)}}}
    swap #x #y
  {{{ RET #(); (is_swap_var x b) ∗ (is_swap_var y a) }}}.
Proof.
  iIntros (Φ) "(Hx & Hy) Post".
  wp_lam. wp_let.

  wp_loadField. wp_let.
  wp_loadField. wp_storeField.
  wp_storeField.

  iApply "Post".
  iFrame.
Qed.

(* careful not to use the wrong star lmao *)
Lemma rotate_r_spec (x y z:loc) (a b c:u64) :
  {{{ (is_swap_var x a) ∗ (is_swap_var y b) ∗ (is_swap_var z c) }}}
    rotate_r #x #y #z
  {{{ RET #(); (is_swap_var x c) ∗ (is_swap_var y a) ∗ (is_swap_var z b) }}}.
Proof.
  iIntros (Φ) "(Hx & Hy & Hz) Post". wp_lam.
  (* wp_apply is magic *)
  wp_apply (swap_spec with "[$Hy $Hz]"). iIntros "[Hy Hz]". wp_seq.
  wp_apply (swap_spec with "[$Hx $Hy]"). iIntros "[Hx Hy]".
  iApply "Post". iFrame.
Qed.

Lemma rotate_l_spec (x y z:loc) (a b c:u64) :
  {{{ (is_swap_var x a) ∗ (is_swap_var y b) ∗ (is_swap_var z c) }}}
    rotate_l #x #y #z
  {{{ RET #(); (is_swap_var x b) ∗ (is_swap_var y c) ∗ (is_swap_var z a) }}}.
Proof.
  iIntros (Φ) "(Hx & Hy & Hz) Post". wp_lam.
  wp_apply (swap_spec with "[$Hx $Hy]"). iIntros "[Hx Hy]". wp_seq.
  wp_apply (swap_spec with "[$Hy $Hz]"). iIntros "[Hy Hz]".
  iApply "Post". iFrame.
Qed.
End proof.