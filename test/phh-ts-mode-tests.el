;;; phh-ts-mode-tests.el --- ERT tests for phh-ts-mode -*- lexical-binding: t; -*-

;; Run with:
;;   emacs -Q --batch -L .. -l phh-ts-mode-tests.el -f ert-run-tests-batch-and-exit
;; from this directory, or via the repo-root smoke-test convention used by
;; every other editor package in this project.

;;; Code:

(require 'ert)
(require 'phh-ts-mode)

;; Captured once at top level, not recomputed inside a test body, see
;; phh-ts-mode.el's own `phh-ts-mode--source-directory' comment for why
;; `load-file-name'/`buffer-file-name' are unreliable once read lazily
;; from inside a function instead of at a file's own top level.
(defconst phh-ts-mode-tests--dir
  (file-name-directory (or load-file-name buffer-file-name)))
(defconst phh-ts-mode-tests--corpus-file
  (expand-file-name "../../phh/corpus/valid/antonius-dwan-ivey-2009.phh"
                     phh-ts-mode-tests--dir))
(defconst phh-ts-mode-tests--phhs-corpus-file
  (expand-file-name "../../phh/corpus/valid/sample.phhs" phh-ts-mode-tests--dir))

(defmacro phh-ts-mode-tests--with-corpus-buffer (var &rest body)
  "Visit the real corpus fixture, enable `phh-ts-mode', fontify, run BODY."
  (declare (indent 1))
  `(let ((,var (find-file-noselect phh-ts-mode-tests--corpus-file)))
     (with-current-buffer ,var
       (phh-ts-mode)
       (treesit-parser-create 'phh_actions)
       (font-lock-ensure)
       ,@body)))

(ert-deftest phh-ts-mode-tests-mode-active ()
  (phh-ts-mode-tests--with-corpus-buffer buf
    (should (eq major-mode 'phh-ts-mode))
    (should (treesit-parser-list))))

(ert-deftest phh-ts-mode-tests-variant-value-gets-type-face ()
  "The `variant' field's string value is highlighted distinctly."
  (phh-ts-mode-tests--with-corpus-buffer buf
    (goto-char (point-min))
    (search-forward "\"NT\"")
    (backward-char 2)
    (should (eq (get-text-property (point) 'face) 'font-lock-type-face))))

(ert-deftest phh-ts-mode-tests-bare-key-gets-property-face ()
  (phh-ts-mode-tests--with-corpus-buffer buf
    (goto-char (point-min))
    (search-forward "antes")
    (backward-char 3)
    (should (eq (get-text-property (point) 'face) 'font-lock-property-name-face))))

(ert-deftest phh-ts-mode-tests-comment-gets-comment-face ()
  (phh-ts-mode-tests--with-corpus-buffer buf
    (goto-char (point-min))
    (search-forward "# Pre-flop")
    (backward-char 3)
    (should (eq (get-text-property (point) 'face) 'font-lock-comment-face))))

(ert-deftest phh-ts-mode-tests-injected-action-verb-wins-over-host-string-face ()
  "The injected phh_actions grammar's `dh' action code is highlighted as a
builtin, not left as the host grammar's blanket string face, this is
the actual thing this test suite exists to pin down: the injection
needs an explicit :override t AND a pre-created, non-local parser for
`phh_actions', neither of which is obvious from the API docs alone
(see phh-ts-mode.el's comments at the two spots this was discovered)."
  (phh-ts-mode-tests--with-corpus-buffer buf
    (goto-char (point-min))
    (search-forward "d dh p1")
    (backward-char 5)
    (should (eq (get-text-property (point) 'face) 'font-lock-builtin-face))))

(ert-deftest phh-ts-mode-tests-injected-card-gets-constant-face ()
  (phh-ts-mode-tests--with-corpus-buffer buf
    (goto-char (point-min))
    (search-forward "Ac2d")
    (backward-char 2)
    (should (eq (get-text-property (point) 'face) 'font-lock-constant-face))))

(ert-deftest phh-ts-mode-tests-imenu-finds-no-table-in-single-hand-file ()
  "A bare .phh file (no [N] table header) has nothing for this Imenu rule
to find, confirmed this doesn't error, not that it finds something."
  (phh-ts-mode-tests--with-corpus-buffer buf
    (should (functionp imenu-create-index-function))
    (should (equal (funcall imenu-create-index-function) nil))))

(ert-deftest phh-ts-mode-tests-imenu-labels-multi-hand-phhs-by-table-key ()
  "A multi-hand .phhs file's Imenu entries are labeled by each hand's own
`[key]' text (\"1\", \"2\", \"3\", ...), not by `treesit-defun-name''s
default extraction, confirmed necessary by testing: the default
extracted the wrong text entirely (\"Anonymous\", a `players' array
value from deep inside the hand) until an explicit NAME-FN was added."
  (let ((buf (find-file-noselect phh-ts-mode-tests--phhs-corpus-file)))
    (with-current-buffer buf
      (phh-ts-mode)
      (font-lock-ensure)
      (should (equal (mapcar #'car (cdr (assoc "Hand" (funcall imenu-create-index-function))))
                      '("1" "2" "3"))))))

(provide 'phh-ts-mode-tests)
;;; phh-ts-mode-tests.el ends here
