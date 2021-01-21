;;; org-fc-macros.el --- description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Trey Peacock
;;
;; Author: Trey Peacock <http://github/tpeacock19>
;; Maintainer: Trey Peacock <git@treypeacock.com>
;; Created: January 10, 2021
;; Modified: January 10, 2021
;; Version: 0.0.1
;; Keywords:
;; Homepage: https://github.com/tpeacock19/org-fc-macros
;; Package-Requires: ((emacs 28.0.50) (cl-lib "0.5"))
;;
;; This file is not part of GNU Emacs.
;;
;; This file is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation; either version 3, or (at your option) any
;; later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;;  description
;;
;;; Code:

(declare-function org-fc-goto-entry-heading "org-fc")

(defmacro org-fc-with-point-at-entry (&rest body)
  "Execute BODY with point at the card heading.
If point is not inside a flashcard entry, an error is raised."
  `(save-excursion
     (org-fc-goto-entry-heading)
     ,@body))

(declare-function org-fc-back-heading-position "org-fc")

(defmacro org-fc-with-point-at-back-heading (&rest body)
  "Execute BODY with point at the card's back heading.
If point is not inside a flashcard entry, an error is raised."
  `(if-let ((pos (org-fc-back-heading-position)))
       (save-excursion
         (goto-char pos)
         ,@body)))

(defmacro org-fc-review-with-current-item (var &rest body)
  "Evaluate BODY with the current card bound to VAR.
Before evaluating BODY, check if the heading at point has the
same ID as the current card in the session."
  (declare (indent defun))
  `(if org-fc--session
       (if-let ((,var (oref org-fc--session current-item)))
           (if (string= (plist-get ,var :id) (org-id-get))
               (progn ,@body)
             (message "Flashcard ID mismatch"))
         (message "No flashcard review is in progress"))))

(provide 'org-fc-macros)
;;; org-fc-macros.el ends here
