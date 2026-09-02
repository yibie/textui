;; Tests and benchmarks are loaded by the test runner, never compiled.
;; package-vc-install byte-compiles the whole checkout, so mark this
;; directory to keep it out of the compile log.
((nil . ((no-byte-compile . t))))
