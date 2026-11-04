;;; kepler-mode.el --- Major mode for Kepler  -*- lexical-binding: t; -*-

(defvar kepler-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?- ". 12" table)
    (modify-syntax-entry ?\( "()1nb" table)
    (modify-syntax-entry ?* ". 23nb" table)
    (modify-syntax-entry ?\) ")(4nb" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?_ "w" table)
    table))

(defvar kepler-font-lock
  `((,(regexp-opt '("if" "else" "end" "for" "in" "while" "break" "return" "defn" "match" "struct" "interface"
                    "then" "use" "and" "or" "not")
                  'words)
     . font-lock-keyword-face)
    (,(regexp-opt '("true" "false" "missing") 'words) . font-lock-constant-face)
    ("\\<\\([a-zA-Z_][a-zA-Z0-9_]*\\)(" 1 font-lock-function-name-face)))

;;;###autoload
(define-derived-mode kepler-mode prog-mode "Kepler"
  "Major mode for Kepler files."
  (setq-local comment-start "-- ")
  (setq-local comment-end "")
  (setq-local font-lock-defaults '(kepler-font-lock)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.k\\'" . kepler-mode))

(provide 'kepler-mode)
;;; kepler-mode.el ends here
