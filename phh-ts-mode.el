;;; phh-ts-mode.el --- Tree-sitter major mode for PHH poker hand histories -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Emacs support for PHH (.phh / .phhs), for editor parity: Emacs gets
;; the same two artifacts every other editor in this project uses rather
;; than a bespoke reimplementation, ;;
;;   - tree-sitter-phh's compiled grammar (copied verbatim from
;;     nvim-phh/parser/phh.so, just renamed to Emacs's own
;;     "libtree-sitter-LANG.<ext>" convention, confirmed to be the exact
;;     same Mach-O arm64 dylib, loaded and parsed successfully under
;;     Emacs's built-in `treesit' with no rebuild needed) for highlighting,
;;     plus tree-sitter-phh-actions (same provenance) for the injected
;;     action-notation micro-grammar inside each `actions` array string;
;;   - phh-ls itself, over `eglot' (built into Emacs 29+, no third-party
;;     LSP client needed), for diagnostics/hover/completion.
;;
;; What's different from tree-sitter-phh/queries/highlights.scm: this file
;; does NOT reuse that query text verbatim. Emacs's `treesit-font-lock-rules'
;; wants capture names that are themselves face symbols (or functions), not
;; the generic `@keyword'/`@string' names Neovim, Zed and Helix queries
;; share, so the node patterns below are ported from highlights.scm's
;; patterns (same node types, same field names), but the capture names are
;; rewritten to Emacs's own `font-lock-*-face' names. This is a different
;; kind of sync discipline than zed-phh/scripts/sync-queries.sh's mechanical
;; copy, not a weaker one: every pattern here was checked against
;; highlights.scm by hand and both were tested against the same corpus
;; (see test/phh-ts-mode-tests.el).

;;; Code:

(require 'treesit)
(require 'eglot)

(defgroup phh nil
  "Major mode for PHH poker hand histories."
  :group 'languages)

(defcustom phh-ts-mode-server-program "phh-ls"
  "Path to the phh-ls executable."
  :type 'string
  :group 'phh)

(defcustom phh-ts-mode-registry-path nil
  "Path to the phh/registry directory.

phh-ls has no built-in default for this, same reasoning as
 (\"never approximate silently\"),
carried over from every other editor integration in this project. You
must set this (e.g. in a directory-local variable, or with `setq' in
your init file) before `phh-ts-mode' will start the language server."
  :type '(choice (const nil) string)
  :group 'phh)

;; Captured once, at top level, while this file is actually being loaded, ;; `load-file-name' is a dynamically-scoped variable bound for the whole
;; extent of a `load' call, so reading it lazily from inside a function
;; (e.g. when `phh-ts-mode' is first activated) can pick up some *other*
;; file's `load-file-name' if that activation happens to occur while a
;; caller's own file is still being loaded (confirmed by hitting exactly
;; this bug while testing: a smoke-test script that both loaded this file
;; and then immediately called `phh-ts-mode' saw `load-file-name' resolve
;; to the *script's* path, not this file's, and silently looked for the
;; grammar in the wrong directory). Capturing it in a `defconst' at top
;; level avoids the whole class of bug.
(defconst phh-ts-mode--source-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory this file was loaded from.")

;;;###autoload
(defun phh-ts-mode-register-grammars ()
  "Add this package's bundled grammars to `treesit-extra-load-path'.

Only macOS arm64 binaries are bundled (same single-platform caveat as
nvim-phh/README.md's parser/*.so, these are in fact the identical
compiled artifacts, just renamed to Emacs's `libtree-sitter-LANG.ext'
convention). On another platform, rebuild tree-sitter-phh and
tree-sitter-phh-actions yourself and point `treesit-extra-load-path'
at the result instead of calling this function."
  (add-to-list 'treesit-extra-load-path
               (expand-file-name "parser" phh-ts-mode--source-directory)))

(defvar phh-ts-mode--host-font-lock-rules
  (treesit-font-lock-rules
   :language 'phh
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'phh
   :feature 'key
   '((table name: (bare_key) @font-lock-constant-face)
     (table name: (quoted_key) @font-lock-constant-face)
     (pair key: (bare_key) @font-lock-property-name-face)
     (pair key: (quoted_key) @font-lock-property-name-face))

   :language 'phh
   :feature 'string
   '((basic_string) @font-lock-string-face
     (literal_string) @font-lock-string-face
     (escape_sequence) @font-lock-escape-face)

   :language 'phh
   :feature 'constant
   '((integer) @font-lock-number-face
     (float) @font-lock-number-face
     (local_time) @font-lock-number-face
     (boolean) @font-lock-constant-face)

   ;; PHH-specific: the `variant' field's value gets its own face, same
   ;; special-casing highlights.scm does .
   :language 'phh
   :feature 'phh-specific
   :override t
   '(((pair key: (bare_key) @_key
        value: (string (basic_string) @font-lock-type-face))
      (:equal @_key "variant"))
     ((pair key: (bare_key) @_key
        value: (string (literal_string) @font-lock-type-face))
      (:equal @_key "variant")))

   :language 'phh
   :feature 'punctuation
   '("[" @font-lock-bracket-face
     "]" @font-lock-bracket-face
     "=" @font-lock-operator-face
     "," @font-lock-delimiter-face))
  "Host-grammar (TOML-level) font-lock rules for `phh-ts-mode'.")

(defvar phh-ts-mode--actions-font-lock-rules
  (treesit-font-lock-rules
   :language 'phh_actions
   :feature 'actions
   ;; :override t: the host grammar's `string' feature already colors the
   ;; whole `actions' array element one solid `font-lock-string-face' (it
   ;; has no idea there's an injected language inside); without :override,
   ;; `treesit-font-lock-rules''s default (nil = "don't replace an
   ;; existing face") means every one of these rules would be silently
   ;; discarded wherever the host's string face already won, confirmed
   ;; by hitting exactly that while testing: every capture here matched
   ;; correctly, but the host's face never budged until :override t was
   ;; added.
   :override t
   '((dealer) @font-lock-keyword-face
     (player_ref) @font-lock-variable-name-face
     (bring_in) @font-lock-builtin-face
     (bet) @font-lock-builtin-face
     (check_or_call) @font-lock-builtin-face
     (fold) @font-lock-builtin-face
     (stand_pat_or_discard) @font-lock-builtin-face
     (show_or_muck) @font-lock-builtin-face
     "db" @font-lock-builtin-face
     "dh" @font-lock-builtin-face
     (card) @font-lock-constant-face
     (repeat_marker) @font-lock-constant-face
     (amount) @font-lock-number-face
     (commentary) @font-lock-comment-face))
  "Font-lock rules for the injected phh_actions micro-grammar.")

(defvar phh-ts-mode--range-rules
  (treesit-range-rules
   :embed 'phh_actions
   :host 'phh
   :offset '(1 . -1)
   '(((pair key: (bare_key) @_key
        value: (array (string (basic_string) @cap)))
      (:equal @_key "actions"))
     ((pair key: (bare_key) @_key
        value: (array (string (literal_string) @cap)))
      (:equal @_key "actions"))))
  "Injects phh_actions into each string of the `actions' array.

Mirrors tree-sitter-phh/queries/injections.scm's two patterns (basic
and literal TOML strings) and its `#offset!' quote-trimming exactly,
translated to `treesit-range-rules' s-expression form.")

(defun phh-ts-mode--imenu-table-name (node)
  "Return a `table' NODE's own `[key]' text, for Imenu's label."
  (treesit-node-text (treesit-node-child-by-field-name node "name") t))

(defvar phh-ts-mode--imenu-settings
  `(("Hand" ,(rx bos "table" eos) nil phh-ts-mode--imenu-table-name))
  "Imenu entries: one per `[key]' table header in a multi-hand .phhs file.

A single-hand .phh file has no `table' node at all (tree-sitter-phh
has no synthetic header for it), so this correctly produces an empty
Imenu index there rather than one fake entry, confirmed via
test/phh-ts-mode-tests.el's single-hand test, not assumed.")

;;;###autoload
(define-derived-mode phh-ts-mode prog-mode "PHH"
  "Major mode for PHH (.phh / .phhs) poker hand histories."
  :group 'phh
  (phh-ts-mode-register-grammars)
  (when (treesit-ready-p 'phh)
    (setq-local treesit-primary-parser (treesit-parser-create 'phh))
    (when (treesit-ready-p 'phh_actions t)
      ;; `treesit-range-rules' here has no `:local t', so this is the
      ;; "global embedded parser" shape, not the "fresh parser per
      ;; occurrence" shape: one `phh_actions' parser covers every
      ;; `actions' array in the buffer, and `treesit-update-ranges' only
      ;; ASSIGNS ranges to an existing parser for that language, it does
      ;; not create one. It has to be created here, up front, or every
      ;; range update silently finds nothing to attach to (confirmed by
      ;; hitting exactly that while testing).
      (treesit-parser-create 'phh_actions)
      (setq-local treesit-range-settings phh-ts-mode--range-rules))
    (setq-local treesit-font-lock-settings
                (append phh-ts-mode--host-font-lock-rules
                        (if (treesit-ready-p 'phh_actions t)
                            phh-ts-mode--actions-font-lock-rules
                          nil)))
    (setq-local treesit-font-lock-feature-list
                '((comment key string)
                  (constant phh-specific)
                  (punctuation actions)
                  ()))
    (setq-local treesit-simple-imenu-settings phh-ts-mode--imenu-settings)
    (setq-local comment-start "# ")
    (setq-local comment-end "")
    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.phhs?\\'" . phh-ts-mode))

(defun phh-ts-mode--eglot-contact (_interactive _project)
  "Build phh-ls's eglot CONTACT, reading `phh-ts-mode-registry-path' fresh.

A function CONTACT (rather than a static list) so a `setq' of
`phh-ts-mode-registry-path' after this file loads still takes effect,
and so an unset registry path fails loudly instead of silently passing
a bogus argument to phh-ls, the same discipline every other editor
integration in this project follows."
  (unless phh-ts-mode-registry-path
    (user-error "phh-ts-mode: set `phh-ts-mode-registry-path' before starting eglot"))
  (list phh-ts-mode-server-program phh-ts-mode-registry-path))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(phh-ts-mode . phh-ts-mode--eglot-contact)))

(provide 'phh-ts-mode)
;;; phh-ts-mode.el ends here
