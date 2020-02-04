(* autogenerated from github.com/mit-pdos/goose-nfsd/util *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

Definition Debug : expr := #0.

Definition DPrintf: val :=
  λ: "level" "format" "a",
    (if: "level" ≤ Debug
    then
      (* log.Printf(format, a...) *)
      #()
    else #()).

Definition RoundUp: val :=
  λ: "n" "sz",
    "n" + "sz" - #1 `quot` "sz".

Definition Min: val :=
  λ: "n" "m",
    (if: "n" < "m"
    then "n"
    else "m").