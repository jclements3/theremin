;;; Project-local Emacs settings — VHDL house style + compile wiring.
;;; First visit prompts about applying these; answer `!' to trust permanently.

((vhdl-mode
  . ((vhdl-basic-offset . 2)                ; match existing RTL indentation
     (vhdl-upper-case-keywords . nil)       ; house style is lowercase
     (vhdl-upper-case-types . nil)
     (vhdl-upper-case-enum-values . nil)
     (vhdl-upper-case-constants . nil)      ; ALL_CAPS names typed by hand
     (vhdl-standard . (8 nil))              ; VHDL-2008
     ;; M-x compile runs the current exercise's testbench from anywhere in
     ;; the repo; GHDL's file:line:col errors work with next-error (M-g n).
     (eval . (setq-local compile-command
                         (concat "source ~/tools/oss-cad-suite/environment && "
                                 "make -C \"$(git rev-parse --show-toplevel)\"/fpga/phase1 "
                                 "sim TB=scale_seq_tb"))))))
