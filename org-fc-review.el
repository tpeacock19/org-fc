;;; org-fc-review.el --- Review of due headlines / positions -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Leon Rische

;; Author: Leon Rische <emacs@leonrische.me>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Cards are reviewed by
;; 1. opening the file they are in
;; 2. calling the setup function for the card type
;; 3. opening a hydra for flipping the card
;; 4. calling the flip function for the card type
;; 5. opening a hydra for rating the card
;; 6. updating the review data based on the rating
;;
;;; Code:

(require 'org-fc-sm2)

;;;; Customization

(defcustom org-fc-review-data-drawer "REVIEW_DATA"
  "Name of the drawer used to store review data."
  :type 'string
  :group 'org-fc)

;;;; Session Management

(defclass org-fc-review-session ()
  ((current-item :initform nil)
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

(defun org-fc-session-cards-pending-p (session)
  "Check if there are any cards in SESSION."
  (not (null (oref session cards))))

(defun org-fc-session-pop-next-card (session)
  "Remove and return one card from SESSION."
  (let ((card (pop (oref session cards))))
    (setf (oref session current-item) card)
    card))

(defun org-fc-session-add-rating (session rating)
  "Store RATING in the review history of SESSION."
  (with-slots (ratings) session
    (case rating
      ('again (incf (getf ratings :again) 1))
      ('hard (incf (getf ratings :hard) 1))
      ('good (incf (getf ratings :good) 1))
      ('easy (incf (getf ratings :easy) 1)))
    (incf (getf ratings :total 1))))

(defun org-fc-session-stats-string (session)
  "Generate a string with review stats for SESSION."
  (with-slots (ratings) session
    (let ((total (plist-get ratings :total)))
      (if (plusp total)
          (format "%.2f again, %.2f hard, %.2f good, %.2f easy"
                  (/ (* 100.0 (plist-get ratings :again)) total)
                  (/ (* 100.0 (plist-get ratings :hard)) total)
                  (/ (* 100.0 (plist-get ratings :good)) total)
                  (/ (* 100.0 (plist-get ratings :easy)) total))
        "No ratings yet"))))

(defvar org-fc-review--current-session nil
  "Current review session.")

;;;; Helper Functions

(defun org-fc-review-next-time (next-interval)
  "Generate an `org-mode' timestamp NEXT-INTERVAL days from now."
  (let ((seconds (* next-interval 60 60 24))
        (now (time-to-seconds)))
    (format-time-string
     org-fc-timestamp-format
     (seconds-to-time (+ now seconds))
     "UTC0")))

;; File-scoped variant of `org-id-goto'
(defun org-fc-id-goto (id file)
  "Go to the heading with ID in FILE."
  (let ((position (org-id-find-id-in-file id file)))
    (if position
        (goto-char (cdr position))
      (error "ID %s not found in %s" id file))))

;;;; Reviewing Cards

(defun org-fc-review--context (context)
  "Start a review session for all cards in CONTEXT."
  (if org-fc-review--current-session
      (message "Flashcards are already being reviewed")
    (let ((cards (org-fc-due-positions context)))
      (if (null cards)
          (message "No cards due right now")
        (progn
          (setq org-fc-review--current-session
                (org-fc-make-review-session cards))
          (org-fc-review-next-card))))))

;;;###autoload
(defun org-fc-review-buffer ()
  "Review due cards in the current buffer."
  (interactive)
  (org-fc-review--context 'buffer))

;;;###autoload
(defun org-fc-review-all ()
  "Review all due cards."
  (interactive)
  (org-fc-review--context 'all))

(defun org-fc-review-next-card ()
  "Review the next card of the current session."
  (if (org-fc-session-cards-pending-p org-fc-review--current-session)
      (condition-case err
          (let* ((card (org-fc-session-pop-next-card org-fc-review--current-session))
                 (path (plist-get card :path))
                 (id (plist-get card :id))
                 (type (plist-get card :type))
                 (position (plist-get card :position))
                 ;; Prevent messages from hiding the multiple-choice card dialog
                 (inhibit-message t))
            (let ((buffer (find-buffer-visiting path)))
              (with-current-buffer (find-file path)
                ;; If buffer was already open, don't kill it after rating the card
                (if buffer
                    (setq-local org-fc-reviewing-existing-buffer t)
                  (setq-local org-fc-reviewing-existing-buffer nil))
                (goto-char (point-min))
                (org-fc-show-all)
                (org-fc-id-goto id path)
                ;; Make sure the headline the card is in is expanded
                (org-reveal)
                (org-fc-narrow-tree)
                (org-fc-hide-drawers)
                (org-fc-show-latex)
                (setq org-fc-timestamp (time-to-seconds (current-time)))
                (funcall (org-fc-type-setup-fn type) position))))
        (error
         (message "Error during review: %s" (error-message-string err))
         (org-fc-review-quit)))
    (message "Review Done")
    (org-fc-review-quit)))

(defhydra org-fc-review-rate-hydra (:foreign-keys warn)
  "
%(length (oref org-fc-review--current-session cards)) cards remaining
%s(org-fc-session-stats-string org-fc-review--current-session)

"
  ("a" (org-fc-review-rate-card 'again) "Rate as again" :exit t)
  ("h" (org-fc-review-rate-card 'hard) "Rate as hard" :exit t)
  ("g" (org-fc-review-rate-card 'good) "Rate as good" :exit t)
  ("e" (org-fc-review-rate-card 'easy) "Rate as easy" :exit t)
  ("q" org-fc-review-quit "Quit" :exit t))

(defhydra org-fc-review-flip-hydra (:foreign-keys warn)
  "
%(length (oref org-fc-review--current-session cards)) cards remaining
%s(org-fc-session-stats-string org-fc-review--current-session)

"
  ("RET" org-fc-review-flip "Flip" :exit t)
  ("t" org-fc-tag-card "Add Tag")
  ;; Neo-Layout ergonomics
  ("n" org-fc-review-flip "Flip" :exit t)
  ("q" org-fc-review-quit "Quit" :exit t))

(defmacro org-fc-review-with-current-item (var &rest body)
  "Evaluate BODY with the current card bound to VAR.
Before evaluating BODY, check if the heading at point has the
same ID as the current card in the session."
  (declare (indent defun))
  `(if org-fc-review--current-session
       (if-let ((,var (oref org-fc-review--current-session current-item)))
           (if (string= (plist-get ,var :id) (org-id-get))
               (progn ,@body)
             (message "Flashcard ID mismatch"))
         (message "No flashcard review is in progress"))))

(defun org-fc-review-flip ()
  "Flip the current flashcard."
  (interactive)
  (condition-case err
      (org-fc-review-with-current-item card
        (let ((type (plist-get card :type)))
          (funcall (org-fc-type-flip-fn type))))
    (error
     (message "Error flipping card: %s" (error-message-string err))
     (org-fc-review-quit))))

;; TODO: Remove -card suffix
(defun org-fc-review-rate-card (rating)
  "Rate the card at point with RATING."
  (interactive)
  (condition-case err
      (org-fc-review-with-current-item card
        (let* ((path (plist-get card :path))
               (id (plist-get card :id))
               (position (plist-get card :position))
               (now (time-to-seconds (current-time)))
               (delta (- now org-fc-timestamp)))
          (org-fc-session-add-rating org-fc-review--current-session rating)
          (org-fc-review-update-data path id position rating delta)
          (org-fc-show-all)
          (save-buffer)
          (unless org-fc-reviewing-existing-buffer
            (kill-buffer))
          (org-fc-review-next-card)))
    (error
     (message "Error rating card: %s" (error-message-string err))
     (org-fc-review-quit))))

(defun org-fc-review-update-data (path id position rating delta)
  "Update the review data of the card.
Also add a new entry in the review history file.  PATH, ID,
POSITION identify the position that was reviewed, RATING is a
review rating and DELTA the time in seconds between showing and
rating the card."
  (save-excursion
    (org-fc-goto-entry-heading)
    (let* ((data (org-fc-get-review-data))
           (current (assoc position data #'string=)))
      (unless current
        (error "No review data found for this position"))
      (unless (and (boundp 'org-fc-demo-mode) org-fc-demo-mode)
        (let ((ease (string-to-number (second current)))
              (box (string-to-number (third current)))
              (interval (string-to-number (fourth current))))
          (org-fc-review-history-add
           (list
            (org-fc-timestamp-now)
            path
            id
            position
            (format "%.2f" ease)
            (format "%d" box)
            (format "%.2f" interval)
            (symbol-name rating)
            (format "%.2f" delta)))
          (destructuring-bind (next-ease next-box next-interval)
              (org-fc-sm2-next-parameters ease box interval rating)
            (setcdr
             current
             (list (format "%.2f" next-ease)
                   (number-to-string next-box)
                   (format "%.2f" next-interval)
                   (org-fc-review-next-time next-interval)))
            (org-fc-set-review-data data)))))))

;;;###autoload
(defun org-fc-review-quit ()
  "Quit the review, remove all overlays from the buffer."
  (interactive)
  (setq org-fc-review--current-session nil)
  (org-fc-show-all))

;;;; Writing Review History

(defun org-fc-review-history-add (elements)
  "Add ELEMENTS to the history csv file."
  (append-to-file
   (concat
    (mapconcat #'identity elements "\t")
    "\n")
   nil
   org-fc-review-history-file))

;;;; Reading / Writing Review Data

;; Based on `org-log-beginning'
(defun org-fc-review-data-position (&optional create)
  "Return (BEGINNING . END) points of the review data drawer.
When optional argument CREATE is non-nil, the function creates a
drawer, if necessary.  Returned position ignores narrowing.

BEGINNING is the start of the first line inside the drawer,
END is the start of the line with :END: on it."
  (org-with-wide-buffer
   (org-end-of-meta-data)
   (let ((regexp (concat "^[ \t]*:" (regexp-quote org-fc-review-data-drawer) ":[ \t]*$"))
         (end (if (org-at-heading-p) (point)
                (save-excursion (outline-next-heading) (point))))
         (case-fold-search t))
     (catch 'exit
       ;; Try to find existing drawer.
       (while (re-search-forward regexp end t)
         (let ((element (org-element-at-point)))
           (when (eq (org-element-type element) 'drawer)
             (throw 'exit
                    (cons (org-element-property :contents-begin element)
                          (org-element-property :contents-end element))))))
       ;; No drawer found.  Create one, if permitted.
       (when create
         (unless (bolp) (insert "\n"))
         (let ((beg (point)))
           (insert ":" org-fc-review-data-drawer ":\n:END:\n")
           (org-indent-region beg (point)))
         (cons
          (line-beginning-position 0)
          (line-beginning-position 0)))))))

(defun org-fc-get-review-data ()
  "Get a cards review data as a Lisp object."
  (let ((position (org-fc-review-data-position nil)))
    (if position
        (save-excursion
          (goto-char (car position))
          (cddr (org-table-to-lisp))))))

(defun org-fc-set-review-data (data)
  "Set the cards review data to DATA."
  (save-excursion
    (let ((position (org-fc-review-data-position t)))
      (kill-region (car position) (cdr position))
      (goto-char (car position))
      (insert "| position | ease | box | interval | due |\n")
      (insert "|-|-|-|-|-|\n")
      (loop for datum in data do
            (insert
             "| "
             (mapconcat (lambda (x) (format "%s" x)) datum " | ")
             " |\n"))
      (org-table-align))))

(defun org-fc-review-data-default (position)
  "Default review data for position POSITION."
  (list position org-fc-sm2-ease-initial 0 0
        (org-fc-timestamp-now)))

(defun org-fc-review-data-update (positions)
  "Update review data to POSITIONS.
If a doesn't exist already, it is initialized with default
values.  Entries in the table not contained in POSITIONS are
removed."
  (let ((old-data (org-fc-get-review-data)))
    (org-fc-set-review-data
     (mapcar
      (lambda (pos)
        (or
         (assoc pos old-data #'string=)
         (org-fc-review-data-default pos)))
      positions))))

;;;; Footer

(provide 'org-fc-review)

;;; org-fc-review.el ends here
