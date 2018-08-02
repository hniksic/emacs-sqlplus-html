;; sqlplus-html.el -- Render SQL*Plus HTML output on-the-fly.

;; Copyright (C) 2001 Hrvoje Niksic

;; Author: Hrvoje Niksic <hniksic@xemacs.org>
;; Keywords: database, hypermedia, commwww
;; Version: 0.97

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; This package might be useful to people who use Oracle's SQL*Plus in
;; a shell buffer.  It massages the output of SQL*Plus to format it
;; into nice-looking tables a la mysql's command line client.  This is
;; feasible thanks to the fact that SQL*Plus has an option to produce
;; HTML output, and that links and w3 handle HTML tables nicely.

;; For the mode to work, you will need a working `w3' package or the
;; `links' external browser (`lynx' won't do because it doesn't handle
;; tables.)  Start the `sqlplus' client in a comint (i.e. shell)
;; buffer.  Then execute `M-x sqlplus-html-init-all', and you should
;; be set.

;; To test whether this works as intended, issue a simple query such
;; as "select 2+2 from dual".  The result should look like this:

;; SQL>select 2+2 from dual;
;;
;; +---+
;; |2+2|
;; |---|
;; | 4 |
;; +---+

;; sqlplus-html-init-all does two things: sends "set markup html on"
;; to SQL*Plus to make it write all output in HTML; and and puts the
;; buffer in sqlplus-html minor mode so that the HTML output is
;; rendered on the fly.

;; You can disable the mode at any time with `M-x sqlplus-html-mode',
;; which works as a toggle.

;; The latest version should be available at:
;;
;;        <URL:http://fly.srk.fer.hr/~hniksic/emacs/sqlplus-html.el>
;;

;; Thanks go to:
;;   * Drazen Kacar <dave@arsdigita.com>, for introducing me to "set
;;   markup html on".


;;; Code:

(require 'cl)
(require 'comint)

(defvar sqlplus-html-mode nil
  "A mode for rendering SQL*Plus HTML output.")
(make-variable-buffer-local 'sqlplus-html-mode)

;; This belongs to "cross-Emacs compatibility" section below, but we
;; need it to define sqlplus-html-process-method.

(defun sqlplus-html-find-executable (name)
  ;; First try the easy and fast way, using locate-file.  We cannot
  ;; check for (fboubdp 'locate-file) because we can't check if it
  ;; supports the new interface.
  (block out
    (condition-case nil
	(return-from out
	  (locate-file name (split-path (getenv "PATH")) nil 'executable))
      (error nil))

    ;; The hard way.
    (dolist (directory (split-string (getenv "PATH") ":"))
      (if (file-executable-p (expand-file-name name directory))
	  (return-from out t)))

    nil))

(defvar sqlplus-html-process-method
  (cond ((sqlplus-html-find-executable "links")
	 ;; Links is preferred due to extremely fast startup and
	 ;; operation.
	 'links)
	((sqlplus-html-find-executable "w3m")
	 ;; w3m is also OK.
	 'w3m)
	((locate-library "w3")
	 ;; w3 is unacceptably slow when rendering tables, but it's
	 ;; still better than nothing.
	 (require 'w3)
	 'w3)
	(t
	 (error
	  "Please install `links' or `w3m' browsers, or the `w3' elisp library")))
  "*Method for processing HTML.
Currently valid methods are symbols `links', `w3m', and `w3'.")

(defvar sqlplus-html-prompt-regexp "\n\r?SQL&gt; \\'"
  "Regexp that matches the HTML version of the SQL*Plus prompt.")

;; Receive progress params.
(defvar sqlplus-html-receive-progress-threshold 0
  "Don't print progress messages before this many bytes are received.")
(defvar sqlplus-html-receive-progress-step 1024
  "Print progress messages in these intervals.")

(defvar sqlplus-html-work-buffer)

(if (fboundp 'add-minor-mode)
    (add-minor-mode 'sqlplus-html-mode " HTML")
  (pushnew '(sqlplus-html-mode (" HTML")) minor-mode-alist
	   :test 'equal))

;;;#autoload
(defun sqlplus-html-init-all ()
  "Put SQL*Plus in HTML mode and turn on sqlplus-html-mode.
This assumes you are in a shell buffer, running a SQL*Plus session."
  (interactive)
  (comint-send-string (current-buffer) "set linesize 10000\n")
  (comint-send-string (current-buffer) "set pagesize 10000\n")
  (comint-send-string (current-buffer) "set markup html on\n")
  (sqlplus-html-mode 1))

;;;###autoload
(defun sqlplus-html-mode (&optional arg)
  "Toggle sqlplus-html-mode.
When active, handle intercept SQL*Plus HTML output, render it using
`w3', and replace the original output with the rendered version.

This works by hijacking the process filter so that it calls our
`sqlplus-html-output-filter' instead of `comint-output-filter'.  It also
sets `truncate-lines' to t and makes sure that the HTML accumulation
buffer is killed when the SQL*Plus buffer is killed or when the mode
is turned off."
  (interactive)
  ;; XXX Should at least assert that the buffer is in a comint-derived
  ;; mode!
  (setq sqlplus-html-mode
	(cond ((eq arg t) t)
	      ((null arg) (not sqlplus-html-mode))
	      ((> (prefix-numeric-value arg) 0))))
  (cond (sqlplus-html-mode
	 (make-local-hook 'kill-buffer-hook)
	 (add-hook 'kill-buffer-hook 'sqlplus-html-kill-work-buffer nil t)
	 (set-process-filter (get-buffer-process (current-buffer))
			     'sqlplus-html-output-filter)
	 (setq truncate-lines t))
	(t
	 ;; Clean up after a run of the mode.

	 (let ((process (get-buffer-process (current-buffer)))
	       (workbuf (and (boundp 'sqlplus-html-work-buffer)
			     (buffer-live-p sqlplus-html-work-buffer)
			     sqlplus-html-work-buffer)))

	   ;; If there's any pending output, process it.
	   (when (and workbuf
		      (not (zerop (buffer-size workbuf))))
	     (comint-output-filter process (with-current-buffer workbuf
					     (buffer-string))))
	   (sqlplus-html-kill-work-buffer)
	   (remove-hook 'kill-buffer-hook 'sqlplus-html-kill-work-buffer t)
	   (set-process-filter process 'comint-output-filter))
	 (setq truncate-lines (default-value 'truncate-lines))))
  (sqlplus-html-redraw-modeline))

;; This used to be a lambda, but I changed it to defun to make its
;; removal easier.
(defun sqlplus-html-kill-work-buffer ()
  ;; Use `ignore-errors' to avoid problems if somebody else killed the
  ;; working buffer, if sqlplus-html-work-buffer is still unbound, etc.
  (ignore-errors
    (kill-buffer sqlplus-html-work-buffer)))

(defun sqlplus-html-ensure-work-buffer ()
  "Ensure that the HTML work buffer exists, and return it."
  (let ((buf (and (boundp 'sqlplus-html-work-buffer)
		  (buffer-live-p sqlplus-html-work-buffer)
		  sqlplus-html-work-buffer)))
    (if buf
	buf
      (set (make-local-variable 'sqlplus-html-work-buffer)
	   (generate-new-buffer " *sqlplus-html*"))
      sqlplus-html-work-buffer)))

;; The workhorse of the module: accumulate subprocess output in a work
;; buffer until the prompt is encountered.  Then feed the collected
;; HTML to a renderer and call `comint-output-filter' with the result.
;; That way comint "sees" the rendered HTML as originating from the
;; subprocess, which is what we want.

(defun sqlplus-html-output-filter (process output-string)
  (let ((work-buffer (sqlplus-html-ensure-work-buffer))
	(result nil))
    (with-current-buffer work-buffer
      ;; Report the progress.
      (sqlplus-html-receive-progress (buffer-size) (length output-string))

      ;; Append the output to the work buffer.
      (goto-char (point-max))
      (insert output-string)

      ;; Try to find the sqlplus prompt.  We're now at point-max.
      ;; Back out 20 characters and then search for
      ;; sqlplus-html-prompt-regexp.
      (ignore-errors
	(backward-char 20))

      (when (re-search-forward sqlplus-html-prompt-regexp nil t)
	;; We found the prompt regexp.  This means that the output
	;; from the last command is finished and that we can process
	;; it.
	(sqlplus-html-process-region (point-min) (point-max))
	(setq result (buffer-string))

	;; Note: we're erasing the whole buffer here, not only the
	;; part until the prompt we've matched.  But that's ok because
	;; sqlplus-html-prompt-regexp includes an end-of-buffer anchor
	;; which ensures that if we're here, the whole buffer contents
	;; should be displayed (and hence erased from the tmp buffer).
	(erase-buffer)))

    (when result
      ;; Clear the echo area.
      (message "")

      ;; Pass the result string to comint so that it thinks the input
      ;; comes from the subprocess.
      (comint-output-filter process result))))

(defun sqlplus-html-process-region (b e)
  (save-restriction
    (narrow-to-region b e)
    (let ((fn (intern (format "sqlplus-html-process-impl-%s"
			      sqlplus-html-process-method))))
      (funcall fn))))

(defun sqlplus-html-process-impl-w3 ()
  (flet ((message (&rest ignored)
	   ;; Disable `message' to avoid ugly "drawing..." 
	   ;; messages printed by w3.
	   t))
    (w3-region (point-min) (point-max)))

  ;; Post-process w3 output.
  (goto-char (point-min))

  ;; Delete leading newlines, except for the very first one.
  (if (looking-at "\n\\(\n+\\)")
      (delete-region (match-beginning 1) (match-end 1)))

  ;; Delete trailing newlines.
  (goto-char (point-max))
  (while (memq (char-before) '(?\n ?\r))
    (delete-char -1)))

(defun sqlplus-html-process-impl-links ()
  (let ((tmp (make-temp-name (expand-file-name
			      "sqlplus-html"
			      (sqlplus-html-temp-directory)))))
    (write-region (point-min) (point-max) tmp nil 'silent)
    (delete-region (point-min) (point-max))
    (unwind-protect
	;; It would be nice if we could use `call-process-region' to
	;; feed the HTML to links's stdin thus avoiding the tmpfile.
	;; But `links -dump /dev/stdin' doesn't work when stdin is a
	;; pipe.
	(call-process "links" nil t nil "-dump" tmp)
      (delete-file tmp)))

  ;; Post-process links output.
  (goto-char (point-min))

  ;; Delete the annoying three spaces preceding each line of links
  ;; output.
  (while (re-search-forward "^   " nil t)
    (delete-region (match-beginning 0) (match-end 0)))

  ;; Delete trailing newlines.
  (goto-char (point-max))
  (while (memq (char-before) '(?\n ?\r))
    (delete-char -1)))

(defun sqlplus-html-process-impl-w3m ()
  ;; w3m can read from stdin, hence we don't need temporary files.
  (call-process-region (point-min) (point-max) "w3m" t t nil
		       "-dump" "-T" "text/html")

  ;; Delete trailing newlines.
  (goto-char (point-max))
  (while (memq (char-before) '(?\n ?\r))
    (delete-char -1)))

(defun sqlplus-html-receive-progress (oldtotal new)
  (let ((newtotal (+ oldtotal new)))
    (when (> newtotal sqlplus-html-receive-progress-threshold)
      (let ((old-count (/ oldtotal 1024))
	    (new-count (/ newtotal 1024)))
	(when (> new-count old-count)
	  (message "sqlplus read: %dk" (/ newtotal 1024)))))))

;;; Cross-Emacs compatibility.

(defun sqlplus-html-temp-directory ()
  (or (and (fboundp 'temp-directory)
	   (temp-directory))
      (getenv "TMPDIR")
      "/tmp"))

(defun sqlplus-html-redraw-modeline ()
  (cond ((fboundp 'redraw-modeline)
	 (redraw-modeline))
	((fboundp 'force-mode-line-update)
	 (force-mode-line-update))
	(t
	 ;; Oldie-goldie.
	 (set-buffer-modified-p (buffer-modified-p)))))

(provide 'sqlplus-html)

;;; sqlplus-html.el ends here
