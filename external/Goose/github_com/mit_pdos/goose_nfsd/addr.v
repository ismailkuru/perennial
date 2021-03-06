(* autogenerated from github.com/mit-pdos/goose-nfsd/addr *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

From Goose Require github_com.mit_pdos.goose_nfsd.common.

(* Addr identifies the start of a disk object.

   Blkno is the block number containing the object, and Off is the location of
   the object within the block (expressed as a bit offset). The size of the
   object is determined by the context in which Addr is used. *)
Module Addr.
  Definition S := struct.decl [
    "Blkno" :: uint64T;
    "Off" :: uint64T
  ].
End Addr.

Definition Addr__Flatid: val :=
  rec: "Addr__Flatid" "a" :=
    struct.get Addr.S "Blkno" "a" * disk.BlockSize * #8 + struct.get Addr.S "Off" "a".

Definition MkAddr: val :=
  rec: "MkAddr" "blkno" "off" :=
    struct.mk Addr.S [
      "Blkno" ::= "blkno";
      "Off" ::= "off"
    ].

Definition MkBitAddr: val :=
  rec: "MkBitAddr" "start" "n" :=
    let: "bit" := "n" `rem` common.NBITBLOCK in
    let: "i" := "n" `quot` common.NBITBLOCK in
    let: "addr" := MkAddr ("start" + "i") "bit" in
    "addr".
