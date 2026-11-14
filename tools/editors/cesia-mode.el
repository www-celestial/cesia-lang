;;; cesia-mode.el --- Major mode for Cesia  -*- lexical-binding: t; -*-

(defvar cesia-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?\( "()1nb" table)
    (modify-syntax-entry ?* ". 23nb" table)
    (modify-syntax-entry ?\) ")(4nb" table)
    (modify-syntax-entry ?_ "w" table)
    table))

(defun cesia-syntactic-face (state)
  "The face of a text, of a (** ... *) and of another comment."
  (cond ((nth 3 state) font-lock-string-face)
        ((and (eq (char-after (+ 1 (nth 8 state))) ?*) (eq (char-after (+ 2 (nth 8 state))) ?*)
              (not (memq (char-after (+ 3 (nth 8 state))) '(?* ?\))))) font-lock-doc-face)
        (t font-lock-comment-face)))

(defvar cesia-font-lock
  `((,(regexp-opt '("if" "else" "end" "for" "in" "while" "break" "return" "defn" "match" "struct" "interface"
                    "then" "use" "and" "or" "not")
                  'words)
     . font-lock-keyword-face)
    (")[ \t]*\\(\\<do\\>\\)" 1 font-lock-keyword-face)
    (,(regexp-opt '("true" "false" "missing") 'words) . font-lock-constant-face)
    ("\\<\\([a-zA-Z_][a-zA-Z0-9_]*\\)(" 1 font-lock-function-name-face)))

;;;###autoload
(define-derived-mode cesia-mode prog-mode "Cesia"
  "Major mode for Cesia files."
  (setq-local comment-start "(* ")
  (setq-local comment-end " *)")
  (setq-local font-lock-defaults '(cesia-font-lock nil nil nil nil (font-lock-syntactic-face-function . cesia-syntactic-face))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.ce\\'" . cesia-mode))

;; M-x eglot starts cesia lsp, the language server, in the folder of the project.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(cesia-mode "cesia" "lsp")))

(provide 'cesia-mode)
;;; cesia-mode.el ends here
