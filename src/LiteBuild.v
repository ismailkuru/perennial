(** LiteBuild depends on a subset of Perennial that is relatively fast to check,
    for use in Coq's CI. *)

(* a couple program proofs that are pretty interesting on their own and include
the wpc infrastructure *)
From Perennial.program_proof Require
     append_log_proof
     examples.dir_proof.

(* Goose tests: goose_unittest has the syntactic tests while generated_test
includes running all the semantics tests *)
From Perennial.goose_lang.examples Require
     goose_unittest.
From Perennial.goose_lang.interpreter Require
     generated_test.
