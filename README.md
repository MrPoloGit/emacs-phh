# emacs-phh

Emacs support for PHH (`.phh` / `.phhs`).

## Install

```elisp
(add-to-list 'load-path "/path/to/emacs-phh")
(require 'phh-ts-mode)
(setq phh-ts-mode-registry-path "/path/to/phh-data/registry") ; required, no default
```

Needs Emacs 29.1+ (built-in `treesit` and `eglot`, no third-party
packages).

**Not published to MELPA (or any other package archive).** This repo
is pushed to `github.com/MrPoloGit/emacs-phh`, usable today via
`straight.el`/`use-package :vc`/`package-vc-install` pointing at that
URL, or the manual `load-path` above, but it hasn't been submitted to
MELPA, nothing has an MELPA recipe yet.
