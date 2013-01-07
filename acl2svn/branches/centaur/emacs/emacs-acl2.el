; ACL2 Version 6.0 -- A Computational Logic for Applicative Common Lisp
; Copyright (C) 2012, Regents of the University of Texas

; This version of ACL2 is a descendent of ACL2 Version 1.9, Copyright
; (C) 1997 Computational Logic, Inc.  See the documentation topic NOTES-2-0.

; This program is free software; you can redistribute it and/or modify
; it under the terms of Version 2 of the GNU General Public License as
; published by the Free Software Foundation.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

; Written by:  Matt Kaufmann               and J Strother Moore
; email:       Kaufmann@cs.utexas.edu      and Moore@cs.utexas.edu
; Department of Computer Sciences
; University of Texas at Austin
; Austin, TX 78712-1188 U.S.A.

; This file contains some emacs stuff for ACL2 users.  It is intended
; to work both with GNU Emacs and XEmacs.

; Suggestion: look at the final section, "Some other features you may want."

;;; CONTENTS OF THIS FILE

;;; Here we summarize the functionality offered by this file.  In many cases,
;;; lower-level details may be found later in the file where the functionality
;;; is actually provided.

; General shell stuff
  ; Starts up a shell buffer, *shell*.
  ; "meta-x new-shell" starts new shell buffers *shell-1*, *shell-2*, ....
  ; "control-x k" redefined to avoid accidentally killing shell buffer.
  ; "control-t e" sends the current form to the shell buffer.
  ; "control-t b" switches to the shell buffer.
  ; "control-t c" sets the shell buffer (initially, *shell*) to the current
  ;      buffer
  ; "control-t control-e" sends the current form to the shell buffer, but
  ;      in the other window.
  ; "control-d" is redefined in shell/telnet buffers to avoid ending process.
  ; "meta-p" and "meta-n" cycle backward/forward doing command completion in
  ;      shell/telnet buffers.
  ; "control-<RETURN>" sets shell/telnet directory buffer to current directory.
; From current buffer to shell buffer
  ; "control-t l" prints appropiate ACL2 LD form to the end of the shell
  ;      buffer, to cause evaluation of the active region in the current
  ;      buffer.
  ; "control-t control-l" prints just as above, but inhibits output and proofs;
  ;      can easily be edited to inhibit only one or the other
  ; "control-t u" puts an appropriate :ubt at the end of the shell buffer, based
  ;      on the event in which you are currently standing.
; Some editing commands
  ; "meta-x find-unbalanced-parentheses" locates unbalanced parentheses.
  ; "control-t a" puts line with cursor at bottom of window.
  ; "control-t <TAB>" completes filename in any buffer.
  ; "control-t control-v" scrolls half as far as "control-v".
  ; "control-t v" scrolls half as far as "meta-v".
  ; "control-t s" searches forward non-interactively, with string supplied in
  ;      minibuffer, case-sensitive
  ; "control-t control-s":  like "control-t s" above, but case-insensitive (at
  ;      least by default).
  ; "control-meta-q" indents s-expression even when not in lisp-mode.
  ; "control-t control-p" executes "meta-x up-list", moving to end of enclosing
  ;      s-expression.
  ; "control-t w" does "meta-x compare-windows" (see emacs documentation,
  ;      "control-h f compare-windows", for more info).
  ; "control-t q" is like "control-t w" above, but ignores whitespace (and case
  ;      too, with a positive prefix argument).
  ; Lisp mode comes up with auto-fill mode on, right margin set at column 79,
  ;      and causes latin-1 (i.e., iso-8859-1) encoding (see :doc
  ;      character-encoding) to be used when saving a buffer to a file.
  ;      If X Windows is being run, then font-lock-mode is also turned on,
  ;      which causes Emacs to color text in .lisp files.  If you don't want
  ;      colors in .lisp files, put this in your .emacs file after the load of
  ;      "emacs-acl2.el":
  ;      (if (equal window-system 'x)
  ;          (remove-hook 'lisp-mode-hook '(lambda () (font-lock-mode 1))))
  ; "meta-x visit-acl2-tags-table" sets the current tag table to the one in the
  ;      ACL2 source directory.
  ; "control-t f" fills format strings; see documentation for more info
  ;      ("control-h f fill-format-string").
  ; "control-t control-f" buries the current buffer (puts it on the bottom of
  ;      the buffer stack, out of the way, without killing the buffer)
; ACL2 proof-tree support
  ; NOTE: This works by default if you install the ACL2 community books, as
  ;       most ACL2 users do, in the books/ directory of your ACL2
  ;       distribution.  Otherwise, you will need to set the variable
  ;       *acl2-interface-dir* to a directory string containing a file
  ;       top-start-shell-acl2.el that defines the functions start-proof-tree
  ;       and start-proof-tree-noninteractive in emacs.  For user-level
  ;       documentation provided in the ACL2 community books implementation,
  ;       see the following file included there:
  ;       books/interface/emacs/PROOF-TREE-EMACS.txt
  ; "meta-x start-proof-tree" starts proof-tree tracking in the current buffer
  ;      (where ACL2 is running).  See ACL2 documentation for PROOF-TREE for
  ;      more information.
  ; Function start-proof-tree-noninteractive (see below) can be used to start
  ;      proof-trees when emacs starts up; see below.
; Run ACL2 as inferior process
  ; NOTE: This works by default if you install the ACL2 community books.
  ;       Otherwise, see the NOTE above on "ACL2 proof-tree support".
  ; "meta-x run-acl2" starts up acl2 as an inferior process in emacs.  You may
  ;      have better luck simply issuing your ACL2 command in an ordinary
  ;      (emacs) shell.
; ACL2 proof-checker support
  ; "control-t d" prints an appropriate DV command at the end of the current
  ;      buffer, suitable for diving to subexpression after printing with
  ;      proof-checker "th" or "p" command and then positioning cursor on that
  ;      subexpression.  See ACL2 documentation for PROOF-CHECKER.
  ; "control-t control-d" is like "control-t d" above, but for DIVE instead
  ;      (used with "pp" instead of "p")
; Support for Dynamic Monitoring of Rewrites (dmr)
; Miscellaneous
  ; "meta-x acl2-info" brings up ACL2 documentation in pleasant emacs-info
  ;      format.
  ; "meta-x date" prints the current date and time (commented out).
  ; "control-meta-l" swaps top buffer with next-to-top buffer (same as
  ;      "control-x b <RETURN>").
  ; "control-t" is a prefix for other commands
  ; "control-t control-t" transposes characters (formerly "control-t")
  ; Other features:
  ;   Turn on time/mail display on mode line.
  ;   Disable a few commands.
  ;   Calls of case, case!, case-match, and dolist will indent like
  ;      calls of defun.
; Some other features you may want (these are commented out by default):
  ; Turn off menu bar.
  ; Turn off emacs auto-save feature.
  ; Start an abbrev table.
  ; Avoid getting two windows, for example with control-x control-b.
  ; Modify whitespace to ignore with "control-t q" (see above).
  ; Turn on version control.
  ; Arrange for "control-meta-l" to work as above even in rmail mode.
  ; If time and "mail" displays icons, this may turn them into ascii.
  ; Get TeX-style quotes with meta-".
  ; Debug emacs errors with backtrace and recursive edit.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; EDIT THIS SECTION!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Edit the following to point to your ACL2 source directory.  This is not
; necessary, however, if this file is located in the emacs/ subdirectory of the
; ACL2 source directory (as is the case when it is distributed).
; Example:
; (defvar *acl2-sources-dir* "/u/acl2/v2-9/acl2-sources/")

; It is tempting to add the following code.  But we want the user to
; manage re-binding *acl2-sources-dir*, say by putting the following
; form in the .emacs file in front of the load of the present file.
; (if (boundp '*acl2-sources-dir*)
;     (makunbound '*acl2-sources-dir*))
(defvar *acl2-sources-dir*)

; Attempt to set *acl2-sources-dir*.
(if (and (not (boundp '*acl2-sources-dir*))
	 (file-name-absolute-p load-file-name))
    (let ((pattern (if (string-match "[\\]" load-file-name)
		       "\[^\\]+\\*$"
		     "/[^/]+/*$"))
	  (dir (file-name-directory load-file-name)))
      (let ((posn (string-match pattern dir)))
	(if posn
	    (setq *acl2-sources-dir*
		  (substring dir 0 (1+ posn)))))))

; The following causes, for every event, the event name to be given
; the same color (in font-lock mode) as when defun is called.  If you
; don't like it, first copy this form into your .emacs file after the
; form that loads this emacs-acl2.el, and then change
; font-lock-add-keywords to font-lock-remove-keywords.

(font-lock-add-keywords
 'lisp-mode
 '(("\\((def[^ \t]*\\|(encapsulate\\|(in-theory\\|(include-book\\|(local\\)\\>"
    . font-lock-keyword-face)
   ("\\((make-event\\|(mutual-recursion\\|(prog[^ \t]*\\)\\>"
    . font-lock-keyword-face)
   ("\\((table\\|(theory-invariant\\)\\>"
    . font-lock-keyword-face)
   ("\\((value-triple\\|(verify-guards\\|(verify-termination\\)\\>"
    . font-lock-keyword-face)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Control-t keymap
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when (not (boundp 'ctl-t-keymap))

; This trick probably came from Bob Boyer, to define a new keymap; so now
; control-t is the first character of a complex command.
  (defvar ctl-t-keymap)
  (setq ctl-t-keymap (make-sparse-keymap))
  (define-key (current-global-map) "\C-T" ctl-t-keymap)

; Control-t t now transposes characters, instead of the former control-t.
  (define-key ctl-t-keymap "\C-T" 'transpose-chars)
  (define-key ctl-t-keymap "\C-t" 'transpose-chars)
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; General shell stuff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; If you don't want to start up a shell when emacs starts but you load
; the present file emacs-acl2.el in your .emacs file, then put the
; following in your ~/.emacs file above the form that loads the
; present file:
;
; (defvar acl2-skip-shell nil)
; (setq acl2-skip-shell t)
;

(defvar acl2-skip-shell nil)

; Start up a shell.  This also loads in comint-mode, used below.
(if (not acl2-skip-shell)
    (shell)
; Otherwise load the shell package in case it's used somewhere.
  (load "shell"))

; Do meta-x new-shell to start a new shell.
(defvar number-of-other-shells 0)
(defun new-shell ()
  "Start up another shell."
  (interactive)
  (switch-to-buffer
   (make-comint (concat "shell-" 
			(number-to-string
			 (setq number-of-other-shells
			       (+ 1 number-of-other-shells))))
		(or (getenv "SHELL")
		    "csh")))
  (shell-mode))

; Avoid killing shell buffers by accident:
(defun kill-buffer-without-process (name)
  "Kill a buffer unless there's a process associated with it."
  (interactive
   (let (val
         (default-name (buffer-name (current-buffer)))
         (table
          (mapcar (function (lambda (x) (cons (buffer-name x) x))) (buffer-list))))
     (setq val (completing-read (format "Kill buffer: (default: %s) "
                                        default-name)
                                table
                                nil
                                t))
     (list (if (equal val "")
               default-name val))))
  (if (get-buffer-process name)
      (error "Process is active in the indicated buffer.  Use meta-x kill-buffer instead.")
    (kill-buffer name)))

(define-key (current-global-map) "\C-Xk" 'kill-buffer-without-process)

; Variable *acl2-shell* is the name of the "ACL2 shell", the buffer to which
; forms are written by various commands defined in this file.  Control-t c
; (defined below) changes the ACL2 buffer.
(defvar *acl2-shell* "*shell*")

; Set the ACL2 shell to the current buffer.
(define-key ctl-t-keymap "c" 'set-shell-buffer)
(defun set-shell-buffer ()
  (interactive)
  (setq *acl2-shell* (buffer-name (current-buffer)))
  (message "Setting the ACL2 shell to buffer %s" *acl2-shell*)
  *acl2-shell*)

; Change to the ACL2 shell.
(define-key ctl-t-keymap "b" 'switch-to-shell)
(defun switch-to-shell ()
  (interactive)
  (switch-to-buffer *acl2-shell*))

; Send the current form to the ACL2 shell.  Here, the "current form" is the one
; starting with the immediately preceding left parenthesis in column 0.  (It is
; OK to stand on that parenthesis as well.)
(define-key ctl-t-keymap "e" 'enter-theorem)
(define-key ctl-t-keymap "\C-e" 'enter-theorem-other-window)

; Old version (before v2-8) hardwires in the use of *shell*.
;(defalias 'enter-theorem
;  (read-kbd-macro
;   "C-e C-M-a NUL C-M-f ESC w C-x b *shell* RET M-> C-y"))

; Versions after v3-4 allow us to open up ACL2 scopes.
; See the documentation for enter-theorem.
; This code is relatively less tested; please send bug reports
; to the ACL2 implementors or contribute fixes.

(defun acl2-scope-start-p ()
  (looking-at
   "(encapsulate[ \t]*\\(;;.*\\)?\n[ \t\n]*()[ \t]*;; start lemmas for"))

(defun acl2-beginning-of-def ()
; See the documentation for enter-theorem.  We return nil unless we go
; to a preceding package marker, #!pkg, in which case we return t.
  (let ((saved-point (point))
	(ans nil))
    (end-of-line)
    (beginning-of-defun)
    (let ((temp-point (point)))
      (cond ((not (equal temp-point (point-min)))
	     (forward-line -1)
	     (cond ((looking-at "#!")
		    (setq ans t))
		   (t (goto-char temp-point))))))
    (cond ((acl2-scope-start-p)
	   (goto-char saved-point)
	   (if (not (looking-at "("))
	       (backward-up-list))
	   (let ((scope-p (acl2-scope-start-p)))
	     (or scope-p
		 (progn (while (not scope-p)
			  (setq saved-point (point))
			  (backward-up-list)
			  (setq scope-p (acl2-scope-start-p)))
			(goto-char saved-point))))))
    ans))

(defun acl2-current-form-string (&optional ignore-pkg-marker)
  (save-excursion
    (end-of-line)
    (let ((temp (acl2-beginning-of-def)))
      (let ((beg (point)))
	(if (and temp (not ignore-pkg-marker))
	    (forward-line 1))
	(forward-sexp)
	(buffer-substring beg (point))))))

(defun enter-theorem ()

  "Normally just insert the last top-level form starting at or before
the cursor, where a \"top-level\" form is one starting with a left
parenthesis on the left margin.  If that form is preceded by a line
starting with #!pkg-name, then that line is included in the inserted
string.

However, if that form is an ACL2 scope -- an encapsulate with empty
signature followed by \";; start lemmas for \" -- then first move up
if necessary to a left parenthesis, and then keep moving up until
hitting a \"top-level form\", i.e., either an ACL2 scope (in the above
sense) or else a form immediately under an ACL2 scope.  You can open a
scope with control-t o."

  (interactive)
  (push-mark) ; I think I sometimes like to go back to the form.
  (let ((str (acl2-current-form-string)))
    (switch-to-buffer *acl2-shell*)
    (end-of-buffer)
    (insert str))
  (end-of-buffer) ; harmless; seemed necessary at one point
  )

(defun enter-theorem-other-window ()
  (interactive)
  (push-mark) ; I think I sometimes like to go back to the form.
  (let ((str (acl2-current-form-string)))
    (other-window 1)
    (switch-to-buffer *acl2-shell*)
    (end-of-buffer)
    (insert str)))

(defun event-name ()
  (save-excursion
    (let ((beg (point)))
      (forward-sexp)
      (let ((pair (read-from-string (buffer-substring beg (point)))))
	(let ((expr (car pair)))
	  (if (and (consp expr)
		   (consp (cdr expr)))
	      (cadr expr)
	    (error "Not in an event!")))))))

(defun acl2-open-scope ()

  "Open a superior encapsulate that defines an ACL2 scope for the
current top-level form.  See the documentation for enter-theorem."

  (interactive)
  (save-excursion
    (acl2-beginning-of-def)
    (let ((name (event-name)))
      (beginning-of-line)
      (open-line 2)
      (lisp-indent-line)
      (insert "(encapsulate\n")
      (lisp-indent-line)
      (insert (format
	       "() ;; start lemmas for %s"
	       (or name "anonymous event")))
      (forward-sexp)
      (let ((end (point)))
	(backward-sexp)
	(insert " ")
	(indent-rigidly (point) end 1))
      (forward-sexp)
      (end-of-line)
      (open-line 1)
      (next-line 1)
      (insert ")")
      (lisp-indent-line))))

(define-key ctl-t-keymap "o" 'acl2-open-scope)

; Avoid killing process with control-d in shell buffer:
(define-key comint-mode-map "\C-d" 'delete-char)

; The following only seems necessary in gnu.
(define-key comint-mode-map "�" 'c-m-l)

; Allow use of meta-p and meta-n for command completion.  Multiple
; meta-p/meta-n commands cycle backward/forward through previous matching
; commands.
; See also emacs lisp source file lisp/comint.el.
(define-key comint-mode-map "\ep" 'comint-previous-matching-input-from-input)
(define-key comint-mode-map "\en" 'comint-next-matching-input-from-input)

; Bind control-<RETURN> to the command that brings the current buffer's
; directory back to what it is supposed to be.
(define-key global-map "\C-\M-M" 'shell-resync-dirs)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Write region to shell
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The next forms support control-t l (ell), which writes the current region to
; file "./temp-emacs-file.lsp" and puts an appropriate LD command in the shell
; buffer.

(defvar *shell-temp-file-name* "temp-emacs-file.lsp")

(if (boundp '*shell-temp-file-directory*)
    (makunbound '*shell-temp-file-directory*))
(defvar *shell-temp-file-directory*)

(defun set-shell-temp-file-directory ()
  (setq *shell-temp-file-directory*
	"./"))

(defun shell-temp-file-name ()
  (expand-file-name *shell-temp-file-name* (set-shell-temp-file-directory)))

(defun write-region-for-shell (beg end)
  "Writes the current region to the shell temp file, with the header
   string at the top and the footer string at the bottom and <return> separating each.
   Assumes beg < end."
  (let ((flg (buffer-modified-p)))
    (save-excursion
      (goto-char beg)
      (write-region beg end (shell-temp-file-name)))
    (set-buffer-modified-p flg)))

(defun send-region-to-shell (message)
  "Writes the current region to the shell temp file and then puts one at the
   end of the ACL2 shell buffer, ready to submit that file."
  (let ((beg (min (point) (mark)))
	(end (max (point) (mark))))
    (write-region-for-shell beg end)
    (switch-to-buffer *acl2-shell*)
    (end-of-buffer)
    (insert message)))

(defun acl2-load ()
  "Writes the current region to the shell temp file and then puts the cursor
   at the end of the ACL2 shell buffer, ready to execute an ld."
  (interactive)
  (send-region-to-shell
   (concat (format
	    ";; Ready to execute ACL2-LOAD -- hit <RETURN> when ready\n")
	   (format "(acl2::ld \"%s\" :LD-PRE-EVAL-PRINT acl2::t :ld-error-action :return)"
		   (shell-temp-file-name)))))

(defun acl2-load-inhibited ()
  "Writes the current region to the shell temp file and then puts the cursor
   at the end of the ACL2 shell buffer, ready to execute an ld with output
   inhibited and proofs skipped."
  (interactive)
  (send-region-to-shell
   (concat (format
	    ";; Ready to execute ACL2-LOAD -- hit <RETURN> when ready\n")
	   (format "(acl2::with-output :off :all (acl2::ld \"%s\" :ld-error-action :return :ld-skip-proofsp t))"
		   (shell-temp-file-name)))))

(define-key ctl-t-keymap "l" 'acl2-load)
(define-key ctl-t-keymap "\C-l" 'acl2-load-inhibited)

(defun acl2-event-name (form allow-local)
  (and (consp form)
       (let ((hd (car form))
	     name)
	 (cond ((eq hd 'encapsulate)
		(let ((form-list (cdr (cdr form))))
		  (while form-list
		    (setq name (acl2-event-name (car form-list) nil))
		    (if name
			(setq form-list nil) ; exit loop
		      (setq form-list (cdr form-list))))))
	       ((eq hd 'progn)
		(let ((form-list (cdr form)))
		  (while form-list
		    (setq name (acl2-event-name (car form-list) allow-local))
		    (if name
			(setq form-list nil) ; exit loop
		      (setq form-list (cdr form-list))))))
	       ((eq hd 'local)
		(and allow-local
		     (setq name (acl2-event-name (car (cdr form)) t))))
	       (t (setq name (and (consp (cdr form))
				  (car (cdr form))))))
	 (and (symbolp name)
	      name))))

(defun acl2-undo ()
  "Undoes back through the current event.  Current weaknesses: Doesn't
work for encapsulate or progn, and is ignorant of packages."
  (interactive)
  (let ((name (acl2-event-name
	       (car (read-from-string (acl2-current-form-string t)))
	       t)))
    (cond (name (switch-to-buffer *acl2-shell*)
		(end-of-buffer)
		(insert (format ":ubt! %s" name)))
	  (t (error "ERROR: Unable to find event name for undoing.")))))

(define-key ctl-t-keymap "u" 'acl2-undo)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Some editing commands
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Contributed by Bill Bevier:
(defun find-unbalanced-parentheses ()
  "Finds parenthesis mismatch error in buffer. Reads through all of the
current buffer and tries to find places in which the parentheses do not
balance. Positions point to possible trouble-spots, printing out a message
that says what the trouble appears to be.  This command only finds
one such error; if you suspect more errors, run it again."
  (interactive)
  (let ((saved-point (point)))
    (goto-char (point-min));; Go to start of buffer.
    (let (old-point)
      (setq old-point (point))
      (forward-sexp)
      (while (not (equal (point) old-point))
	(setq old-point (point))
	(forward-sexp)))
    (goto-char saved-point)
    (message "All parentheses appear balanced.")))

(defun cursor-at-end-and-bottom ()
  "Put cursor at the end of the buffer on the bottom line"
  (interactive)
  (recenter -1))

; Control-t Control-a puts current line (line with cursor) at bottom of window:
(define-key ctl-t-keymap "\C-a" 'cursor-at-end-and-bottom)

; Control-t <TAB> completes filename in any buffer:
(define-key ctl-t-keymap "\t" 'comint-dynamic-complete-filename)

(defun scroll-up-half ()
  (interactive)
  (scroll-up (/ (window-height) 2)))

(defun scroll-down-half ()
  (interactive)
  (scroll-down (/ (window-height) 2)))

; Like control-v, but only half a screen:
(define-key ctl-t-keymap "\C-V" 'scroll-up-half)

; Like meta-v, but only half a screen:
(define-key ctl-t-keymap "v" 'scroll-down-half)

(defun search-forward-with-case (string)
  (interactive "sSearch: ")
  (let ((case-fold-search nil))
    (search-forward string)))

; Case-sensitive forward search (i.e., searches forward non-interactively, with
; string supplied in minibuffer).
(define-key ctl-t-keymap "s" 'search-forward-with-case)

; Forward search (case-insensitive by default):
(define-key ctl-t-keymap "\C-s" 'search-forward)

(define-key (current-global-map) "\C-\M-q" 'indent-sexp)

(define-key ctl-t-keymap "" 'up-list)

; For the following, set compare-windows-whitespace to something other than "[
; \t\n]+"
; if desired.
(defun approx-compare-windows (&optional ignore-case)
  "Compare windows, ignoring whitespace.  If optional argument is supplied,
then also ignore case if that argument is positive, else do not ignore case."
  (interactive "P")
  (if ignore-case
      (let ((compare-ignore-case (> ignore-case 0)))
	(compare-windows "0"))
    (compare-windows "0")))

; Set compare-windows-whitespace to something other than "[ \t\n]+"
; if desired.  Also consider compare-ignore-case.
(define-key ctl-t-keymap "w" 'compare-windows)
(define-key ctl-t-keymap "q" 'approx-compare-windows)

(defun my-lisp-mode-hook ()
  (setq indent-tabs-mode nil)   
  (setq comment-column 0)
  (turn-on-auto-fill)
  (setq save-buffer-coding-system 'iso-8859-1)
  )

(if (not (boundp 'lisp-mode-hook)) (setq lisp-mode-hook nil))
(add-hook 'lisp-mode-hook 'my-lisp-mode-hook)

; Other modes can be put below as well (asm, c++, c, perl, emacs-lisp).
(if (equal window-system 'x)
    (add-hook 'lisp-mode-hook '(lambda () (font-lock-mode 1))))

(defun acl2-sources-dir ()
  (let ((dir
	 (if (boundp '*acl2-sources-dir*)
	     *acl2-sources-dir*
	   (setq *acl2-sources-dir*
		 (expand-file-name
		  (read-file-name
		  "*acl2-sources-dir* (e.g. /u/acl2/v2-9/acl2-sources/): "
		  nil nil t))))))
    (if (or (equal dir "")
	    (let ((lastch (aref "abc/" (1- (length "abc/")))))
	      (and (not (equal lastch ?/))
		   (not (equal lastch ?\\)))))
	(concat dir
		(if (and (string-match "[\\]" dir)
			 (not (string-match "/" dir)))
		    "\\"
		  "/"))
      dir)))

(defun visit-acl2-tags-table ()
  "Visit the tags table for ACL2."
  (interactive)
  (visit-tags-table (concat (acl2-sources-dir) "TAGS")))

; Set the right margin (used when auto-fill-mode is on).
(add-hook 'lisp-mode-hook
	  '(lambda ()
	     (setq fill-column 79)))
; Formerly: (set-default 'fill-column 79)

; The function fill-format-string below probably originated from Bob
; Boyer in the early 1990s.  See documentation for fill-format-string.
; This is useful both for format and for ACL2's printing functions fmt
; and fms.  Enhanced Nov. 2010 by incorporating a version of code from
; Jared Davis, so that this works even when the cursor is within the
; string rather at the start of it.
(define-key ctl-t-keymap "f" 'fill-format-string)

(defun fill-format-string ()

  "Remove the ~<newline>'s from a Lisp format string, and put in new
ones, after any space, in such a way that the next space does not pass
fill-column.  The point (i.e., the cursor) should initially be at the
start of the string or anywhere within the string (but not on the
closing double-quote).  The final position of the cursor is the
beginning of the string that was processed."

  (interactive "")

; First move the point to the beginning of the string, if possible.

  (or (and (equal (char-after (point)) ?\")
	   (not (equal (char-before (point)) ?\\)))
      (let ((pos (point))
	    (not-done t))
	(while not-done
	  (if (> pos 0)
	      (if (equal (char-after pos) ?\")
		  (if (equal (char-before pos) ?\\)
		      (setq pos (1- pos))
		    (goto-char pos)
		    (setq not-done nil))
		(setq pos (1- pos)))
	    (error "Cannot find beginning of a format string to fill.")))))
  (save-excursion
    (let ((start-point (point))
	  (fill (make-string (+ 1 (current-column)) ? )))
      (forward-sexp 1)
      (let ((end-point (point))
	    (new-end nil))
	(save-restriction
	  (narrow-to-region (+ 1 start-point)
			    (- end-point 1))
	  (goto-char (point-min))
	  (while (re-search-forward "~\n" nil t)
	    (delete-char -2)
	    (while (or (looking-at " ")
		       (looking-at "\t")
		       (looking-at "\n"))
	      (delete-char 1)))
	  (goto-char (point-max))
	  (setq new-end (point)))
	(save-restriction
	  (beginning-of-line)
	  (narrow-to-region (point)
			    new-end)
	  (goto-char (+ 1 start-point))
	  (while (re-search-forward "[ \t]" nil t)
	    (cond ((next-break-too-far)
		   (insert "~\n")
		   (insert fill)))))))))

(defun next-break-too-far ()
  (let ((p (point)))
    (cond ((equal (point) (point-max))
	   nil)
	  (t (cond ((re-search-forward "[ \t\n]" nil t)
		    (prog1
			(>= (current-column) fill-column)
		      (goto-char p)))
		   (t (goto-char (point-max))
		      (prog1
			  (>= (current-column) fill-column)
			(goto-char p))))))))

; Bury the current buffer, putting it on the bottom of the buffer stack, out of
; the way, without killing the buffer).
(define-key ctl-t-keymap "\C-F" 'bury-buffer)

;; Make some functions' indentation behave as for defun.
(put 'case         'lisp-indent-function 'defun)
(put 'case!        'lisp-indent-function 'defun)
(put 'case-match   'lisp-indent-function 'defun)
(put 'dolist       'lisp-indent-function 'defun)
(put 'er@par       'lisp-indent-function 'defun)
(put 'warning$@par 'lisp-indent-function 'defun)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ACL2 proof-tree support
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(if (boundp '*acl2-interface-dir*)
    (makunbound '*acl2-interface-dir*))
(defvar *acl2-interface-dir*)

(defun acl2-interface-dir ()
  (if (boundp '*acl2-interface-dir*)
      *acl2-interface-dir*
    (setq *acl2-interface-dir*
; common location (i.e., for those who install ACL2 community books in books/):
	  (concat (acl2-sources-dir) "books/interface/emacs/"))))

(autoload 'start-proof-tree
  (concat (acl2-interface-dir) "top-start-shell-acl2")
  "Enable proof tree logging in a prooftree buffer."
  t)

(autoload 'start-proof-tree-noninteractive
  (concat (acl2-interface-dir) "top-start-shell-acl2")
  "Enable proof tree logging in a prooftree buffer."
  t)

; You may find it useful to put some version of the following two forms in your
; .emacs file.  It should start a new frame (perhaps after you click in the
; initial emacs window) to the side of the first frame, with the "prooftree"
; buffer displayed in the new frame.
; (start-proof-tree-noninteractive "*shell*")
; (cond ((and (eq window-system 'x)
;             (fboundp 'x-display-pixel-width)
;             (= (x-display-pixel-width) 2048) ; for a wide monitor
;             )
;        (delete-other-windows)
;        (if (boundp 'emacs-startup-hook) ; false in xemacs
;            (push 'new-prooftree-frame emacs-startup-hook))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Run ACL2 as inferior process in emacs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; You may have better luck simply issuing your ACL2 command in an ordinary
; (emacs) shell.  But in case anyone wants to try this:

(autoload 'run-acl2
  (concat *acl2-interface-dir* "top-start-inferior-acl2")
  "Open communication between acl2 running in shell and prooftree."
  t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ACL2 proof-checker support
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Insert  DV  command that gets to subexpression at the cursor.
; This is for use with the P and TH commands.
(define-key ctl-t-keymap "d" 'dv-manual)

; Insert DIVE command that gets to subexpression at the cursor.
; This is for use with the PP command.
(define-key ctl-t-keymap "\C-d" 'dive-manual)

; The rest of the functions in this section support \C-t d and \C-t \C-d. 

(defvar *acl2-pc-dive-syntax-table* nil)

(defun maybe-set-acl2-pc-dive-syntax-table ()
  (cond ((null *acl2-pc-dive-syntax-table*)
	 (setq *acl2-pc-dive-syntax-table*
	       (copy-syntax-table (syntax-table)))
	 (modify-syntax-entry ?- "w" *acl2-pc-dive-syntax-table*)
	 (modify-syntax-entry ?: "w" *acl2-pc-dive-syntax-table*)
	 (modify-syntax-entry ?_ "w" *acl2-pc-dive-syntax-table*)
	 (modify-syntax-entry ?+ "w" *acl2-pc-dive-syntax-table*)
	 (modify-syntax-entry ?* "w" *acl2-pc-dive-syntax-table*)
	 (modify-syntax-entry ?. "w" *acl2-pc-dive-syntax-table*)
	 *acl2-pc-dive-syntax-table*)))

(defun dive-manual ()
  "Returns the 0-based address of the current s-expression inside
the expression beginning at the margin, assuming that the point
is properly inside the margin (otherwise causes an error), then
moves to the end of the buffer and plops down the appropriate DIVE
command for the proof-checker.  Causes an error if one is already
at the top."
  (interactive)
  (let ((addr (find-address)))
    (end-of-buffer)
    (if (null addr)
	(error "Null address.")
      (insert (prin1-to-string (cons 'dive addr))))))

(defun dv-manual ()
  "Returns the 0-based address of the current s-expression inside
the expression beginning at the margin, assuming that the point
is properly inside the margin (otherwise causes an error), then
moves to the end of the buffer and plops down the appropriate DV
command for the proof-checker. Causes an error if one is already at the top."
  (interactive)
  (let ((addr (find-address)))
    (end-of-buffer)
    (if (null addr)
	(error "Null address.")
      (insert (prin1-to-string (cons 'dv addr))))))

(defun beginning-of-current-defun ()
  "Causes an error if one is already at the beginning of defun, in
the sense of c-m-a"
;  (interactive)
  (let ((old-point (point)))
    (end-of-defun)
    (beginning-of-defun)
    (or (not (equal (point) old-point))
	(error "Already at the beginning of the expression."))))

(defun find-address ()
  "Returns the 0-based address of the current s-expression inside
the expression beginning at the margin.  Leaves one at the original point."
  (maybe-set-acl2-pc-dive-syntax-table)
  (with-syntax-table
      *acl2-pc-dive-syntax-table*
    (let (quit-point old-point result)
      (setq old-point (point))
      (beginning-of-current-defun)
      (setq quit-point (point))
      (goto-char old-point)
      (while (not (equal (point) quit-point))
	(setq result (cons (move-up-one-level) result)))
      (goto-char old-point)
      result)))

(defun move-up-one-level ()
  "Like backward-up-list, except that it returns the position
of the current s-expression in the enclosing list"
;  (interactive)
  (let (saved-point final-point n)
    (forward-sexp) ; puts us just past the end of current sexp
    (setq saved-point (point))
    (backward-up-list 1)
    (setq final-point (point))
    (forward-char 1)
    (forward-sexp)
    (setq n 0)
    (while (not (equal (point) saved-point))
      (setq n (1+ n))
      (forward-sexp))
    (goto-char final-point)
    n))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Support for Dynamic Monitoring of Rewrites (dmr)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(load (concat (acl2-sources-dir) "emacs/monitor.el"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Miscellaneous
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun acl2-info ()
  "Starts up info pointing at top of acl2 documentation"
  (interactive)
  (info (concat (acl2-sources-dir) "doc/EMACS/acl2-doc-emacs.info"))
  )

; From Bishop Brock:
;(defun date ()
;  "Inserts the date and time at point."
;  (interactive)
;  (insert (current-time-string)))

; Get control-meta-l to change buffers in rmail mode and perhaps some other
; modes where it otherwise doesn't work.
(fset 'c-m-l "\C-Xb\C-M")
(global-set-key "\214" 'c-m-l)
; (load "rmail")
; (define-key rmail-mode-map "\214" 'c-m-l)

; Turn on time/mail display on mode line.
(setq display-time-interval 10)
(display-time) ; turn off as described just below:
; Turn off display-time with:
;   (display-time-mode) in emacs
;   (display-time-stop) in xemacs
; Needed for displaying day and date in addition to time:
; (setq display-time-day-and-date t)

; Disable commands that we do not want to execute by mistake:
(put 'shell-resync-dirs 'disabled t)
(put 'suspend-or-iconify-emacs 'disabled t)
(put 'suspend-emacs 'disabled t)
(put 'iconify-or-deiconify-frame 'disabled t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Some other features you may want
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Turn off menu bar:
; (menu-bar-mode 0)

;; Turn off auto-save (not actually a good idea unless you save your files
;; often).
; (setq auto-save-interval 0)
; (setq auto-save-timeout 0)

; Abbrevs are great!  For example, if you type
; ac
; followed by
; control-x '
; then (assuming the following form has been evaluated), the "ac" will be
; replaced by the value of *acl2-sources-dir*.
; (define-abbrev-table 'global-abbrev-table
;   (list
;    (list "ac" *acl2-sources-dir* nil 1)
;    ))

;; Avoid getting two windows, for example with control-x control-b.
; (setq pop-up-windows nil)

;; For compare-windows ignoring whitespace (control-t q):
; Set compare-windows-whitespace to something other than "[ \t\n]+"
; if desired.  Also consider compare-ignore-case.

;; Turn on version control (backup files *.~1~, *.~2~, ...):
; (setq version-control t)

;; If c-m-l does not work in rmail mode, you can do this:
; (load "rmail")
; (define-key rmail-mode-map "\214" 'c-m-l)

;; If time and "mail" displays icons, this may turn them into ordinary ascii.
; (setq display-time-show-icons-maybe nil)

;; To get ``real'' quotes with Escape-" (even without TeX mode):
; (autoload 'tex-insert-quote "tex-mode" nil t)
; (define-key global-map "\C-[\"" 'tex-insert-quote)

;; To debug emacs errors with backtrace and recursive edit:
; (setq debug-on-error t)
