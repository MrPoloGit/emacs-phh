# emacs-phh

Emacs support for PHH (`.phh` / `.phhs`), for editor parity. Built
after VS Code, Neovim, Vim and Zed already existed for this language, Emacs gets the same two artifacts every other editor uses, not a bespoke
reimplementation: `tree-sitter-phh`'s (and `tree-sitter-phh-actions`'s)
compiled grammar, and `phh-ls` itself over `eglot`.

## Install

```elisp
(add-to-list 'load-path "/path/to/emacs-phh")
(require 'phh-ts-mode)
(setq phh-ts-mode-registry-path "/path/to/phh/registry") ; required, no default
```

Needs Emacs 29.1+ (built-in `treesit` and `eglot`, no third-party
packages).

**Not published to MELPA (or any other package archive).** This repo
is pushed to `github.com/MrPoloGit/emacs-phh`, usable today via
`straight.el`/`use-package :vc`/`package-vc-install` pointing at that
URL, or the manual `load-path` above, but it hasn't been submitted to
MELPA, nothing has an MELPA recipe yet.

## What's implemented (L0, highlighting)

- **Filetype detection**: `.phh`/`.phhs` → `phh-ts-mode`, via `auto-mode-alist`.
- **Highlighting**: `treesit-font-lock-rules`, ported from
  `tree-sitter-phh/queries/highlights.scm`'s patterns (same node types,
  same field names) with capture names rewritten to Emacs's own
  `font-lock-*-face` names, Emacs's font-lock captures must themselves
  be face symbols, unlike the generic `@keyword`/`@string` captures
  Neovim/Zed/Helix queries share, so this is a by-hand port, checked
  against the real grammar (`test/phh-ts-mode-tests.el`), not a
  mechanical sync the way `zed-phh/scripts/sync-queries.sh` is for Zed.
- **The `actions` array's action-notation micro-grammar is injected**,
  via `treesit-range-rules` + a second `treesit-font-lock-rules` set
  targeting `phh_actions`, e.g. `"d dh p1 Ac2d"` highlights `dh` as a
  builtin action, `p1` as a parameter, `Ac`/`2d` as cards, distinct from
  the host grammar's blanket string-face for the array element as a
  whole. Confirmed by a real test (`test/phh-ts-mode-tests.el`), not
  assumed from the API docs, getting this working took two real,
  non-obvious fixes, both left as comments in `phh-ts-mode.el` at the
  exact lines they matter so they don't get "cleaned up" back into the
  bug later:
  1. `treesit-range-rules` without `:local t` creates a **global**
     embedded-language parser, it only *assigns ranges* to an existing
     parser for that language, it does not create one. `phh_actions`
     must be pre-created with `(treesit-parser-create 'phh_actions)`
     before the range rules do anything, or every range update finds
     nothing to attach to and silently no-ops.
  2. The injected rules need `:override t`. Without it,
     `treesit-font-lock-rules`'s default (`nil` = "don't replace a face
     the region already has") means the host grammar's string-face,
     applied first, permanently wins, every injected capture matches
     correctly but visibly does nothing until `:override t` is added.
- **Imenu**: one "Hand" entry per `[key]` table header, for multi-hand
  `.phhs` files, labeled by the table's own key text (`"1"`, `"2"`,
  `"first"`, ...), not Emacs's default `defun`-name extraction, which
  was tried first and extracted the wrong text entirely (confirmed by
  testing, fixed by passing an explicit `NAME-FN`). A single-hand `.phh`
  file correctly produces an empty Imenu index, tree-sitter-phh's
  grammar has no synthetic table header for that case at all.

**Grammar binaries are bundled**, but only for **macOS arm64**, `parser/libtree-sitter-phh.dylib` and `parser/libtree-sitter-phh_actions.dylib`
are the exact same compiled Mach-O dylibs `nvim-phh/parser/*.so` already
ships, confirmed byte-identical in provenance (same build, just renamed
to Emacs's own `libtree-sitter-LANG.<ext>` convention, and re-confirmed
to load and parse correctly under Emacs's `treesit`, not just assumed
from the rename). On another platform, rebuild both yourself with the
`tree-sitter` CLI (`npm install -g tree-sitter-cli`) and a C compiler,
naming the output extension for whichever platform you're on (Emacs's
`treesit` picks the extension to look for from its own
`dynamic-library-suffixes`, `.so` on Linux, `.dylib` on macOS, `.dll` on
Windows):

```sh
# Linux
tree-sitter build ../tree-sitter-phh -o parser/libtree-sitter-phh.so
tree-sitter build ../tree-sitter-phh-actions -o parser/libtree-sitter-phh_actions.so

# Windows
tree-sitter build ../tree-sitter-phh -o parser/libtree-sitter-phh.dll
tree-sitter build ../tree-sitter-phh-actions -o parser/libtree-sitter-phh_actions.dll
```

`treesit-extra-load-path` already points `phh-ts-mode-register-grammars`
at this directory, so no further configuration is needed once the files
are there.

## What's implemented (L1, diagnostics, hover, completion)

`eglot-server-programs` gets a `phh-ts-mode` entry that starts
`phh-ls <registry-path>` over stdio, through a **function** contact
(not a static list) so a `setq` of `phh-ts-mode-registry-path` after
this file loads still takes effect, and so an unset registry path fails
loudly (`user-error`) instead of silently passing a bogus argument to
`phh-ls`, the same "never approximate silently" rule
 states and every other editor
integration in this project repeats.

**Not independently confirmed**: a live, interactive `M-x eglot`
handshake in a real Emacs session (everything above was tested via
`emacs -Q --batch`, which never starts a subprocess LSP server). This
is the same category of gap `vim-phh`'s README already names for
vim-lsp, `phh-ls`'s own hover/diagnostics behavior is independently
proven correct over real JSON-RPC (`phh-ls/tests/lsp_smoke_test.py`)
and through Neovim's real LSP client (`nvim-phh/test/headless_test.lua`);
what's specifically unconfirmed here is only `eglot`'s handshake
completing live.

## How this was verified

`test/phh-ts-mode-tests.el` (ERT, run via
`emacs -Q --batch -L .. -l test/phh-ts-mode-tests.el -f ert-run-tests-batch-and-exit`)
checks the real resolved face at specific real-corpus positions, including both injection fixes above and the Imenu labeling fix, via
`get-text-property`, the same discipline `vim-phh/test/synid_test.vim`
uses with `synID()`. **All 8 checks pass.** All three `.el` files in
this package also byte-compile with zero warnings.

Positions were found via `search-forward` + `(match-beginning 0)`, not
hand-counted `backward-char` offsets, an earlier draft of this test
file used hand-counted offsets, miscounted one, and got a false "WHEN
isn't highlighted" failure that had nothing to do with the mode. Worth
naming so the mistake isn't repeated: trust the search, not arithmetic.
