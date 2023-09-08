;;; rdef-ts-mode.el --- tree-sitter support for RDef  -*- lexical-binding: t; -*-

;;; SPDX-License-Identifier: MIT
;;; SPDX-FileCopyrightText: 2023 Chris Roberts

;;; Commentary:

;;; Code:

(require 'treesit)
(eval-when-compile (require 'rx))

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-induce-sparse-tree "treesit.c")
(declare-function treesit-node-child "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")
(declare-function treesit-node-start "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-search-subtree "treesit.c")

(defcustom rdef-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `rdef-ts-mode'."
  :version "29.1"
  :type 'integer
  :safe 'integerp
  :group 'rdef)

;; (defvar rdef-ts-mode--syntax-table
;;   (let ((table (make-syntax-table)))
;;     (modify-syntax-entry ?+   "."      table)
;;     (modify-syntax-entry ?-   "."      table)
;;     (modify-syntax-entry ?=   "."      table)
;;     (modify-syntax-entry ?%   "."      table)
;;     (modify-syntax-entry ?&   "."      table)
;;     (modify-syntax-entry ?|   "."      table)
;;     (modify-syntax-entry ?^   "."      table)
;;     (modify-syntax-entry ?!   "."      table)
;;     (modify-syntax-entry ?<   "."      table)
;;     (modify-syntax-entry ?>   "."      table)
;;     (modify-syntax-entry ?\\  "\\"     table)
;;     (modify-syntax-entry ?\'  "\""     table)
;;     (modify-syntax-entry ?/   ". 124b" table)
;;     (modify-syntax-entry ?*   ". 23"   table)
;;     (modify-syntax-entry ?\n  "> b"    table)
;;     table)
;;   "Syntax table for `rdef-ts-mode'.")

;; (defvar rdef-ts-mode--indent-rules
;;   `((rdef
;;      ((parent-is "source_file") column-0 0)
;;      ((node-is ")") parent-bol 0)
;;      ((node-is "]") parent-bol 0)
;;      ((node-is "}") parent-bol 0)
;;      ((node-is "labeled_statement") no-indent 0)
;;      ((parent-is "raw_string_literal") no-indent 0)
;;      ((parent-is "argument_list") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "block") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "communication_case") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "const_declaration") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "default_case") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "expression_case") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "selector_expression") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "expression_switch_statement") parent-bol 0)
;;      ((parent-is "field_declaration_list") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "import_spec_list") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "interface_type") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "labeled_statement") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "literal_value") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "parameter_list") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "select_statement") parent-bol 0)
;;      ((parent-is "type_case") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "type_spec") parent-bol rdef-ts-mode-indent-offset)
;;      ((parent-is "type_switch_statement") parent-bol 0)
;;      ((parent-is "var_declaration") parent-bol rdef-ts-mode-indent-offset)
;;      (no-node parent-bol 0)))
;;   "Tree-sitter indent rules for `rdef-ts-mode'.")

(defvar rdef-ts-mode--keywords
  '("archive" "array" "enum" "import" "message" "resource" "type")
  "RDef keywords for tree-sitter font-locking.")

(defvar rdef-ts-mode--operators
  ;; '("+" "-" "|" "*" "/" "=")
  '("|" "=")
  "RDef operators for tree-sitter font-locking.")

(defvar rdef-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'rdef
   :feature 'bracket
   '((["(" ")" "[" "]" "{" "}"]) @font-lock-bracket-face)

   :language 'rdef
   :feature 'builtin
   '((builtin (identifier) @font-lock-builtin-face)
     (heavy_builtin) @font-lock-builtin-face)

   :language 'rdef
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'rdef
   :feature 'constant
   `((constant) @font-lock-constant-face)

   :language 'rdef
   :feature 'delimiter
   '((["," ";"]) @font-lock-delimiter-face)

   :language 'rdef
   :feature 'keyword
   `([,@rdef-ts-mode--keywords] @font-lock-keyword-face)

   :language 'rdef
   :feature 'number
   '((number) @font-lock-number-face)

   :language 'rdef
   :feature 'preprocessor
   '("#include" @font-lock-preprocessor-face)

   :language 'rdef
   :feature 'string
   '([(string) (hex_string)] @font-lock-string-face)

   :language 'rdef
   :feature 'type
   '([(typecode) (typecast) (what)] @font-lock-type-face)

   :language 'rdef
   :feature 'variable
   '((identifier) @font-lock-variable-use-face)

   :language 'rdef
   :feature 'error
   :override t
   '((ERROR) @font-lock-warning-face))
  "Tree-sitter font-lock settings for `rdef-ts-mode'.")

;;;###autoload
(define-derived-mode rdef-ts-mode prog-mode "RDef"
  "Major mode for editing RDef, powered by tree-sitter."
  :group 'rdef
  ;; :syntax-table rdef-ts-mode--syntax-table

  (when (treesit-ready-p 'rdef)
    (treesit-parser-create 'rdef)

    ;; Comments.
    (setq-local comment-start "// ")
    (setq-local comment-end "")
    ;; (setq-local comment-start-skip (rx "//" (* (syntax whitespace))))

    ;; Navigation.
    ;; (setq-local treesit-defun-type-regexp
    ;;             (regexp-opt '("method_declaration"
    ;;                           "function_declaration"
    ;;                           "type_declaration")))
    ;; (setq-local treesit-defun-name-function #'rdef-ts-mode--defun-name)

    ;; Imenu.
    ;; (setq-local treesit-simple-imenu-settings
    ;;             `(("Function" "\\`function_declaration\\'" nil nil)
    ;;               ("Method" "\\`method_declaration\\'" nil nil)
    ;;               ("Struct" "\\`type_declaration\\'" rdef-ts-mode--struct-node-p nil)
    ;;               ("Interface" "\\`type_declaration\\'" rdef-ts-mode--interface-node-p nil)
    ;;               ("Type" "\\`type_declaration\\'" rdef-ts-mode--other-type-node-p nil)
    ;;               ("Alias" "\\`type_declaration\\'" rdef-ts-mode--alias-node-p nil)))

    ;; Indent.
    (setq-local indent-tabs-mode t)
    ;; (setq-local indent-tabs-mode t
    ;;             treesit-simple-indent-rules rdef-ts-mode--indent-rules)

    ;; Electric
    (setq-local electric-indent-chars
                (append "{}()" electric-indent-chars))

    ;; Font-lock.
    (setq-local treesit-font-lock-settings rdef-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '(( comment )
                  ( keyword preprocessor string)
                  ( builtin constant number type)
                  ( bracket delimiter error operator variable)))

    (treesit-major-mode-setup)))

(if (treesit-ready-p 'rdef)
    (add-to-list 'auto-mode-alist '("\\.rdef\\'" . rdef-ts-mode)))

;; (defun rdef-ts-mode--defun-name (node)
;;   "Return the defun name of NODE.
;; Return nil if there is no name or if NODE is not a defun node."
;;   (pcase (treesit-node-type node)
;;     ("function_declaration"
;;      (treesit-node-text
;;       (treesit-node-child-by-field-name
;;        node "name")
;;       t))
;;     ("method_declaration"
;;      (let* ((receiver-node (treesit-node-child-by-field-name node "receiver"))
;;             (type-node (treesit-search-subtree receiver-node "type_identifier"))
;;             (name-node (treesit-node-child-by-field-name node "name")))
;;        (concat
;;         "(" (treesit-node-text type-node) ")."
;;         (treesit-node-text name-node))))
;;     ("type_declaration"
;;      (treesit-node-text
;;       (treesit-node-child-by-field-name
;;        (treesit-node-child node 0 t) "name")
;;       t))))

;; (defun rdef-ts-mode--interface-node-p (node)
;;   "Return t if NODE is an interface."
;;   (and
;;    (string-equal "type_declaration" (treesit-node-type node))
;;    (treesit-search-subtree node "interface_type" nil nil 2)))

;; (defun rdef-ts-mode--struct-node-p (node)
;;   "Return t if NODE is a struct."
;;   (and
;;    (string-equal "type_declaration" (treesit-node-type node))
;;    (treesit-search-subtree node "struct_type" nil nil 2)))

;; (defun rdef-ts-mode--alias-node-p (node)
;;   "Return t if NODE is a type alias."
;;   (and
;;    (string-equal "type_declaration" (treesit-node-type node))
;;    (treesit-search-subtree node "type_alias" nil nil 1)))

;; (defun rdef-ts-mode--other-type-node-p (node)
;;   "Return t if NODE is a type other than interface, struct, or alias."
;;   (and
;;    (string-equal "type_declaration" (treesit-node-type node))
;;    (not (rdef-ts-mode--interface-node-p node))
;;    (not (rdef-ts-mode--struct-node-p node))
;;    (not (rdef-ts-mode--alias-node-p node))))

(provide 'rdef-ts-mode)

;;; rdef-ts-mode.el ends here
