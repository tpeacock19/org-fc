;;; org-fc-session.el --- description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Trey Peacock
;;
;; Author: Trey Peacock <http://github/tpeacock19>
;; Maintainer: Trey Peacock <git@treypeacock.com>
;; Created: January 10, 2021
;; Modified: January 10, 2021
;; Version: 0.0.1
;; Keywords:
;; Homepage: https://github.com/tpeacock19/org-fc-session
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


;;;; Session Management

(defclass org-fc-review-session ()
  ((current-item :initform nil)
   (paused :initform nil :initarg :paused)
   (history :initform nil)
   (ratings :initform nil :initarg :ratings)
   (cards :initform nil :initarg :cards)))

(defun org-fc-make-review-session (cards)
  "Create a new review session with CARDS."
  (make-instance
   'org-fc-review-session
   :ratings
   (if-let ((stats (org-fc-awk-stats-reviews)))
       (plist-get stats :day)
     '(:total 0 :again 0 :hard 0 :good 0 :easy 0))
   :cards cards))

(defun org-fc-review-history-add (elements)
  "Add ELEMENTS to review history."
  (push
   elements
   (slot-value org-fc--session 'history)))

(defun org-fc-review-history-save ()
  "Save all history entries in the current session."
  (when (and org-fc--session (oref org-fc--session history))
    (append-to-file
     (concat
      (mapconcat
       (lambda (elements) (mapconcat #'identity elements "\t"))
       (reverse (oref org-fc--session history))
       "\n")
      "\n")
     nil
     org-fc-review-history-file)
    (setf (oref org-fc--session history) nil)))

;; Make sure the history is saved even if Emacs is killed
(add-hook 'kill-emacs-hook #'org-fc-review-history-save)

(defun org-fc-session-cards-pending-p (session)
  "Check if there are any cards in SESSION."
  (not (null (oref session cards))))

(defun org-fc-session-pop-next-card (session)
  "Remove and return one card from SESSION."
  (let ((card (pop (oref session cards))))
    (setf (oref session current-item) card)
    card))

(defun org-fc-session-append-card (session card)
  "Append CARD to the cards of SESSION."
  (with-slots (cards) session
    (setf cards (append cards (list card)))))

(defun org-fc-session-prepend-card (session card)
  "Prepend CARD to the cards of SESSION."
  (with-slots (cards) session
    (setf cards (cons card cards))))

(defun org-fc-session-add-rating (session rating)
  "Store RATING in the review history of SESSION."
  (with-slots (ratings) session
    (cl-case rating
      ('again (cl-incf (cl-getf ratings :again) 1))
      ('hard (cl-incf (cl-getf ratings :hard) 1))
      ('good (cl-incf (cl-getf ratings :good) 1))
      ('easy (cl-incf (cl-getf ratings :easy) 1)))
    (cl-incf (cl-getf ratings :total 1))))

(defun org-fc-session-stats-string (session)
  "Generate a string with review stats for SESSION."
  (with-slots (ratings) session
    (let ((total (plist-get ratings :total)))
      (if (cl-plusp total)
          (format "%.2f again, %.2f hard, %.2f good, %.2f easy"
                  (/ (* 100.0 (plist-get ratings :again)) total)
                  (/ (* 100.0 (plist-get ratings :hard)) total)
                  (/ (* 100.0 (plist-get ratings :good)) total)
                  (/ (* 100.0 (plist-get ratings :easy)) total))
        "No ratings yet"))))

(defvar org-fc--session nil
  "Current review session.")


(provide 'org-fc-session)
;;; org-fc-session.el ends here
