; -*- mode: lisp -*-

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; A Hunchentoot taskmaster that limits the number of worker threads
;;;

(in-package :limited-thread-taskmaster)

(defparameter *hunchentoot-worker-thread-limit* 10)

(defvar *eager-future-pool* nil)

(defun eager-future-pool ()
  (or *eager-future-pool*
      (let ((pool (make-instance 'eager-future:fixed-fifo-thread-pool)))
        (setf (eager-future:thread-limit pool) *hunchentoot-worker-thread-limit*
              *eager-future-pool* pool))))

(defun limited-thread-limit ()
  "Return the maximum number of hunchentoot worker threads that will be created."
  *hunchentoot-worker-thread-limit*)

(defun (setf limited-thread-limit) (limit)
  "Set the maxmimum number of worker threads that will be created.
LIMIT must be an integer >= 2."
  (check-type limit integer)
  (assert (>= limit 2))
  (setf *hunchentoot-worker-thread-limit* limit)
  (let ((pool *eager-future-pool*))
    (when pool
      (setf (eager-future:thread-limit pool) limit)))
  limit)

(defclass limited-thread-taskmaster (hunchentoot:one-thread-per-connection-taskmaster)
  ((thread-pool :initform (eager-future-pool)
                :accessor thread-pool-of))
  (:documentation "A Hunchentoot taskmaster that limits the number of worker threads."))

(defparameter *log-message-fn*
  (cond ((fboundp 'hunchentoot::log-message)
         'hunchentoot::log-message)
        ((fboundp 'hunchentoot::log-message*)
         'hunchentoot::log-message*)
        (t (lambda (&rest rest) (declare (ignore rest))))))

(defmethod hunchentoot:handle-incoming-connection
    ((taskmaster limited-thread-taskmaster) socket)
  (let ((eager-future:*thread-pool* (thread-pool-of taskmaster)))
    (hunchentoot::handler-case*
     (eager-future:pexec
       (let ((thread (bt:current-thread)))
         (declare (ignorable thread))
         #+ccl
         (setf (ccl:process-name thread)
               (format nil "Hunchentoot worker \(client: ~A)"
                       (hunchentoot::client-as-string socket)))
         (unwind-protect
              (hunchentoot:process-connection
               (hunchentoot:taskmaster-acceptor taskmaster)
               socket)
           #+ccl
           (setf (ccl:process-name thread) "Hunchentoot worker (idle)"))))
     (error (cond)
       ;; need to bind *ACCEPTOR* so that LOG-MESSAGE can do its work.
       (let ((hunchentoot:*acceptor* (hunchentoot:taskmaster-acceptor taskmaster)))
         (funcall *log-message-fn*
          hunchentoot:*lisp-errors-log-level*
          "Error while scheduling new incoming connection: ~A"
          cond))))))

(eval-when (:compile-toplevel :load-toplevel :execute)

(when (find-class 'hunchentoot::easy-acceptor nil)
  (pushnew :hunchentoot-easy-acceptor *features*))
(when (fboundp 'hunchentoot::acceptor-access-log-destination)
  (pushnew :hunchentoot-access-log-destination *features*))
)

(defclass limited-thread-acceptor (#+hunchentoot-easy-acceptor
                                   hunchentoot:easy-acceptor
                                   #-hunchentoot-easy-acceptor
                                   hunchentoot:acceptor)
  ()
  (:default-initargs
   :taskmaster (make-instance 'limited-thread-taskmaster)
    #+hunchentoot-access-log-destination :access-log-destination
    #+hunchentoot-access-log-destination nil)
  (:documentation "A Hunchentoot acceptor that uses a limited-thread-taskmaster to imit the number of worker threads."))

(defclass limited-thread-ssl-acceptor (hunchentoot:ssl-acceptor)
  ()
  (:default-initargs
   :taskmaster (make-instance 'limited-thread-taskmaster))
  (:documentation "A Hunchentoot SSL acceptor that uses a limited-thread-taskmaster to imit the number of worker threads."))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Copyright 2011 Bill St. Clair
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions
;;; and limitations under the License.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
