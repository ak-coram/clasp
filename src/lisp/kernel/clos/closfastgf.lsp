;;; ------------------------------------------------------------
;;;
;;; Generic function dispatch compiler
;;;   This implements the algorithm described by Robert Strandh for fast generic function dispatch
;;;
;;;   clos:generic-function-call-history is an alist of (past-call-signature . effective-method-closure)
;;;      The effective-method-closure is generated by combin.lsp:combine-method-functions3 and
;;;        the fptr always points to combin.lsp:combine-method-functions3.lambda
;;;        and is closed over the method and the rest-methods.
;;;      The past-call-signature is a simple-vector of classes for class-specializers
;;;        or (list eql-spec) for eql specializers.  The CAR of eql-spec is the EQL value and the
;;;        argument passed to the generic function.
;;;        eql-spec is the result of calling spec_type.unsafe_cons()->memberEql(spec_position_arg)
;;;          in the function fill_spec_vector.
;;;          https://github.com/drmeister/clasp/blob/dev/src/core/genericFunction.cc#L194
;;;
;;; clos:*enable-fastgf* and :fast-dispatch feature.
;;;    When the :fast-dispatch feature exists and clos:*enable-fastgf* == t
;;;    then fast dispatch will be used for new generic functions.

(in-package :cmp)

;;; ------------------------------------------------------------
;;;
;;; Debugging code
;;;
;;; Add :DEBUG-CMPGF to *features* and recompile for lots of debugging info
;;;   during fastgf compilation and execution.
;;;
;;; Add :LOG-CMPGF to log fastgf messages during the slow path.
;;;    
#+(or)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (pushnew :debug-cmpgf *features*))
;#+(or)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (pushnew :log-cmpgf *features*))


#+log-cmpgf
(progn
  (ensure-directories-exist "/tmp/dispatch-history/")
  (defvar *dml* (open "/tmp/dispatch-history/dispatch-miss.log" :direction :output))
  (defvar *didx* 0)
  (defvar *dmtrack* (make-hash-table))
  (defun history-entry (entry)
    (mapcar (lambda (e)
              (if (consp e)
                  (list 'eql (car e))
                  e))
            (coerce entry 'list)))
  (defun graph-call-history (generic-function output)
    (cmp:generate-dot-file generic-function output))
  (defun log-cmpgf-filename (suffix extension)
    (pathname (core:bformat nil "/tmp/dispatch-history/dispatch-%s%d.%s" suffix *didx* extension)))
  (defmacro gf-log-dispatch-graph (gf)
    `(graph-call-history ,gf (log-cmpgf-filename "graph" "dot")))
  (defmacro gf-log-dispatch-miss-followup (msg &rest args)
    `(progn
       (core:bformat *dml* "------- ")
       (core:bformat *dml* ,msg ,@args)))
  (defmacro gf-log-dispatch-miss-message (msg &rest args)
    `(core:bformat *dml* ,msg ,@args))
  (defmacro gf-log-sorted-roots (roots)
    `(progn
       (core:bformat *dml* ">>> sorted roots\n")
       (let ((x 0))
         (mapc (lambda (root)
                 (core:bformat *dml* "  root[%d]: %s\n" (prog1 x (incf x)) root))))))
  (defmacro gf-log-dispatch-miss (msg gf va-args)
    `(progn
       (incf *didx*)
       (incf (gethash ,gf *dmtrack* 0))
       (core:bformat *dml* "------- DIDX:%d %s\n" *didx* ,msg)
       (core:bformat *dml* "Dispatch miss #%d for %s\n" (gethash ,gf *dmtrack*) (core:instance-ref ,gf 0))
       (let* ((args-as-list (core:list-from-va-list ,va-args))
              (call-history (clos::instance-ref ,gf 4))
              (specializer-profile (clos::instance-ref ,gf 6)))
         (core:bformat *dml* "      args (num args -> %d):  " (length args-as-list))
         (dolist (arg args-as-list)
           (core:bformat *dml* "%s[%d] " arg (core:instance-stamp arg)))
         (core:bformat *dml* "\n")
         (let ((index 0))
           (core:bformat *dml* "    raw call-history (length -> %d):\n" (length call-history))
           (dolist (entry call-history)
             (core:bformat *dml* "    entry #%3d: %s\n" (prog1 index (incf index)) entry))
           #+(or)(dolist (entry call-history)
                   (core:bformat *dml* "        entry#%3d: (" (prog1 index (incf index)))
                   (dolist (c (history-entry (car entry)))
                     (if (consp c)
                         (core:bformat *dml* "%s " c)
                         (core:bformat *dml* "%s[%d] " (class-name c) (core:class-stamp-for-instances c))))
                   (core:bformat *dml* ")\n")))
         #+(or)(let ((optimized-call-history (cmp::optimized-call-history call-history specializer-profile)))
                 (core:bformat *dml* "    optimized call-history (length -> %d):\n" (length optimized-call-history))
                 (dolist (entry optimized-call-history)
                   (core:bformat *dml* "        entry: (")
                   (let ((history-entry (history-entry (car entry))))
                     ;;(core:bformat *dml* "          ----> %s\n" history-entry)
                     (dolist (c history-entry)
                       ;;(core:bformat *dml* "    c -> %s   (type-of c) -> %s (consp c) -> %s\n" c (type-of c) (consp c))
                       (cond
                         ((consp c) (core:bformat *dml* "%s " c))
                         ((null c) (core:bformat *dml* "NIL "))
                         (t (core:bformat *dml* "%s[%d] " (class-name c) (core:class-stamp-for-instances c))))))
                   (core:bformat *dml* ")\n")))
         (finish-output *dml*)
         #++(when (string= (subseq args 0 2) "''")
           (break "Check backtrace"))))))

#-log-cmpgf
(progn
  (defmacro gf-log-sorted-roots (roots) nil)
  (defmacro gf-log-dispatch-graph (gf) nil)
  (defmacro gf-log-dispatch-miss (msg gf va-args) nil)
  (defmacro gf-log-dispatch-miss-followup (msg &rest args) nil)
  (defmacro gf-log-dispatch-miss-message (msg &rest args) nil))


#+debug-cmpgf
(progn
  (defmacro gf-log (fmt &rest fmt-args) `(core::bformat t ,fmt ,@fmt-args))
  (defmacro gf-do (&body code) `(progn ,@code)))

#-debug-cmpgf
(progn
  (defmacro gf-log (fmt &rest fmt-args) nil)
  (defmacro gf-do (&body code) nil))


;;; --------------------------------------------------
;;;
;;; Switch to CLOS package here
;;;
;;; This section contains code that is called by CLOS to
;;;   update generic-function-call-history and to call
;;;   codegen-dispatcher to generate a new dispatch function when needed
;;;

(in-package :clos)

(defun specializers-as-list (arguments)
  (loop for arg in arguments
     for specializer = (if (consp arg) (car arg) 'T)
     collect specializer))

(defparameter *trap* nil)
(defparameter *dispatch-log* nil)

(defun maybe-update-instances (arguments)
  (let ((invalid-instance nil))
    (dolist (x arguments)
      (when (core:cxx-instance-p x)
        (let* ((i x)
               (s (si::instance-sig i)))
          (declare (:read-only i s))
          (clos::with-early-accessors (clos::+standard-class-slots+)
            (when (si::sl-boundp s)
              (unless (and (eq s (clos::class-slots (core:instance-class i)))
                           (= (core:instance-stamp i) (core:class-stamp-for-instances (core:instance-class i))))
                (setf invalid-instance t)
                (clos::update-instance i)
                (core:instance-stamp-set i (core:class-stamp-for-instances (si:instance-class i)))))))))
    invalid-instance))

;; A call history selector a list of classes and eql-specializers
;; So to compute the applicable methods we need to consider the following cases for each
;; possible entry selector ...
;; 1) The selector is a list of just classes
;;      In that case behavior like that of compute-applicable-methods-using-classes can be used
;; 2) The selector is a mix of classes and eql-specializers
;;      In this case something like compute-applicable-methods needs to be used - but
;;         compute-applicable-methods takes a list of ARGUMENTS
;;        So I think we 
(defun applicable-method-p (method specializers)
  (loop for spec in (method-specializers method)
     for argspec in specializers
     always (if (eql-specializer-flag spec)
                (and (consp argspec) (eql (car argspec) (eql-specializer-object spec)))
                (and (not (consp argspec)) (subclassp argspec spec)))))

(defun applicable-method-list-using-specializers (gf specializers)
  (declare (optimize (speed 3))
	   (si::c-local))
  (with-early-accessors (+standard-method-slots+
			 +standard-generic-function-slots+
			 +eql-specializer-slots+
			 +standard-class-slots+)
    (loop for method in (generic-function-methods gf)
       when (applicable-method-p method specializers)
       collect method)))

(defun compute-applicable-methods-using-specializers (generic-function specializers)
  (check-type specializers list)
  (sort-applicable-methods generic-function
                           (applicable-method-list-using-specializers generic-function specializers)
                           (mapcar (lambda (s) (if (consp s)
                                                   (class-of (car s))
                                                   s))
                                   specializers)))

(defmacro with-generic-function-write-lock ((generic-function) &body body)
  `(unwind-protect
       (progn
         (mp:write-lock (generic-function-lock ,generic-function))
         ,@body)
    (mp:write-unlock (generic-function-lock ,generic-function))))

(defmacro with-generic-function-shared-lock ((generic-function) &body body)
  `(unwind-protect
        (progn
          (mp:shared-lock (generic-function-lock ,generic-function))
          ,@body)
     (mp:shared-unlock (generic-function-lock ,generic-function))))

(defun update-call-history-for-add-method (generic-function method)
  "When a method is added then we update the effective-method-functions for
   those call-history entries with specializers that the method would apply to."
  (with-generic-function-write-lock (generic-function)
    (loop for entry in (generic-function-call-history generic-function)
       for specializers = (coerce (car entry) 'list)
       when (applicable-method-p method specializers)
       do (let* ((methods (compute-applicable-methods-using-specializers
                           generic-function
                           specializers))
                 (effective-method-function (compute-effective-method-function
                                             generic-function
                                             (generic-function-method-combination generic-function)
                                             methods)))
            (rplacd entry effective-method-function)))))

(defun update-call-history-for-remove-method (generic-function method)
  "When a method is removed then we update the effective-method-functions for
   those call-history entries with specializers that the method would apply to
    AND if that means there are no methods left that apply to the specializers
     then remove the entry from the list."
  (with-generic-function-write-lock (generic-function)
    (let (keep-entries)
      (loop for entry in (generic-function-call-history generic-function)
         for specializers = (coerce (car entry) 'list)
         if (applicable-method-p method specializers)
         do (let* ((methods (compute-applicable-methods-using-specializers
                             generic-function
                             specializers))
                   (effective-method-function (if methods
                                                  (compute-effective-method-function
                                                   generic-function
                                                   (generic-function-method-combination generic-function)
                                                   methods)
                                                  nil)))
              (when effective-method-function
                (rplacd entry effective-method-function)
                (push entry keep-entries)))
         else
         do (push entry keep-entries))
      (setf (generic-function-call-history generic-function) keep-entries))))



(defun calculate-discriminator-function (generic-function)
  "This is called from set-generic-function-dispatch - which is called whenever a method is added or removed "
  (calculate-fastgf-dispatch-function generic-function
                                      #+log-cmpgf :output-path
                                      #+log-cmpgf (cmp::log-cmpgf-filename "func" "ll")))

(defun memoize-call (generic-function vaslist-arguments effective-method-function)
  (cmp::gf-log "about to call clos:memoization-key vaslist-arguments-> ~a" vaslist-arguments)
  (let ((pushed (let ((memoize-key (clos:memoization-key generic-function vaslist-arguments)))
                  (cmp::gf-log "Memoizing key -> ~a ~%" memoize-key)
                  (cmp::gf-log-dispatch-miss "Adding to history" generic-function vaslist-arguments)
                  (generic-function-call-history-push-new generic-function memoize-key effective-method-function))))
    (unless pushed
      (warn "The generic-function ~a experienced a dispatch-miss but the call did not result in a new call-history entry - this suggests the fastgf is failing somehow - turn on log-cmpgf in cmpgf.lsp and recompile everything" (core:bformat nil "%s" (core:instance-ref generic-function 0)))
      (cmp::gf-log-dispatch-miss-followup "!!!!!!  DID NOT MODIFY CALL-HISTORY\n"))
    (cmp::gf-log "Installing new discriminator function~%")
    #+log-cmpgf(cmp::graph-call-history generic-function (cmp::log-cmpgf-filename "graph" "dot"))
    (set-funcallable-instance-function generic-function
                                       (calculate-fastgf-dispatch-function
                                        generic-function
                                        #+log-cmpgf :output-path
                                        #+log-cmpgf (cmp::log-cmpgf-filename "func" "ll")))))

(defun do-dispatch-miss (generic-function vaslist-arguments arguments)
  "This effectively does what compute-discriminator-function does and maybe memoizes the result 
and calls the effective-method-function that is calculated.
It takes the arguments in two forms, as a vaslist and as a list of arguments."
  (let ((can-memoize t))
    (multiple-value-bind (method-list ok)
        (clos::compute-applicable-methods-using-classes
         generic-function
         (mapcar #'class-of arguments))
      ;; If ok is NIL then what do we use as the key
      (cmp::gf-log "Called compute-applicable-methods-using-classes - returned method-list: ~a  ok: ~a~%" method-list ok)
      (unless ok
        (setf method-list (clos::compute-applicable-methods generic-function arguments))
        (cmp::gf-log "compute-applicable-methods-using-classes returned NIL for second argument~%")
        ;; MOP says we can only memoize results if c-a-m-u-c returns T as its second return value
        ;;     But for standard-generic-functions we can memoize the effective-method-function
        ;;        even if c-a-m-u-c returns NIL as its second return value
        ;;        because it is illegal to implement new methods on c-a-m specialized
        ;;        on standard-generic-function.
        (setf can-memoize (eq (class-of generic-function) (find-class 'standard-generic-function))))
      ;; If the method list contains a single entry and it is an accessor - then we can
      ;; create an optimized reader/writer and put that in the call history
      ;; FIXME:  To achieve optimized slot access - I need here to determine if I can use an optimized slot accessor.
      ;;         Can I use the method-list?
      (cmp::gf-log "        check if method list (1) has one entry (2) is a reader or writer - if so - optimize it%&        method-list -> ~a" method-list)
      (if method-list
          (let ((effective-method-function (clos::compute-effective-method-function
                                            generic-function
                                            (clos::generic-function-method-combination generic-function)
                                            method-list)))
            (when can-memoize (memoize-call generic-function vaslist-arguments effective-method-function))
            (cmp::gf-log "Calling effective-method-function ~a~%" effective-method-function)
            (apply effective-method-function arguments nil arguments))
          (progn
            (cmp::gf-log-dispatch-miss "no-applicable-method" generic-function vaslist-arguments)
            (apply #'no-applicable-method generic-function arguments))))))

(defun clos::dispatch-miss (generic-function valist-args)
  (cmp::gf-log "A dispatch-miss occurred~%")
  (core:stack-monitor (lambda () (format t "In clos::dispatch-miss with generic function ~a~%" (clos::generic-function-name generic-function))))
  ;; update instances
  (cmp::gf-log "In clos::dispatch-miss~%")
  ;; Update any invalid instances
  (let* ((arguments (core:list-from-va-list valist-args))
         (invalid-instance (maybe-update-instances arguments)))
    (if invalid-instance
        (apply generic-function valist-args)
        (prog1
            (do-dispatch-miss generic-function valist-args arguments)
          (cmp::gf-log "Returned from do-dispatch-miss~%")))))

;;; change-class requires removing call-history entries involving the class
;;; and invalidating the generic functions

(defun update-specializer-profile (generic-function specializers)
  (if (and (generic-function-specializer-profile generic-function)
           (vectorp (generic-function-specializer-profile generic-function)))
      (let ((vec (generic-function-specializer-profile generic-function)))
        (loop for i from 0
           for spec in specializers
           for specialized = (not (eq spec clos:+the-t-class+))
           when specialized
           do (setf (elt vec i) t)))
      (warn "update-specializer-profile - Generic function ~a does not have a specializer-profile defined at this point" generic-function)))


(defun compute-and-set-specializer-profile (generic-function)
  ;; The generic-function MUST have a specializer-profile defined already
  ;;   - it must be a simple-vector with size number-of-requred-arguments
  ;;     Each element is T if the corresponding argument is specialized on
  ;;        and NIL if it is not (all specializers are T).
  (if (and (generic-function-specializer-profile generic-function)
           (vectorp (generic-function-specializer-profile generic-function)))
      (let ((vec (make-array (length (generic-function-specializer-profile generic-function))
                             :initial-element nil))
            (methods (clos:generic-function-methods generic-function)))
        (setf (generic-function-specializer-profile generic-function) vec)
        (when methods
          (loop for method in methods
             for specializers = (method-specializers method)
             do (update-specializer-profile generic-function specializers))))
      (warn "compute-and-set-specializer-profile - Generic function ~a does not have a specializer-profile at this point" generic-function)))

(defun calculate-fastgf-dispatch-function (generic-function &key output-path)
  (with-generic-function-shared-lock (generic-function)
    (if (generic-function-call-history generic-function)
        (cmp:codegen-dispatcher generic-function
                                :generic-function-name (core:function-name generic-function)
                                :output-path output-path)
        'invalidated-dispatch-function)))

(defun maybe-invalidate-generic-function (gf)
  (when (typep (clos:get-funcallable-instance-function gf) 'core:compiled-dispatch-function)
    (set-funcallable-instance-function gf
                                       'invalidated-dispatch-function
                                       #+(or)(clos::calculate-fastgf-dispatch-function gf))))


(defun invalidated-dispatch-function (generic-function valist-args)
  ;;; If there is a call history then compile a dispatch function
  ;;;   being extremely careful NOT to use any generic-function calls.
  ;;;   Then redo the call.
  ;;; If there is no call history then treat this like a dispatch-miss.
  (if (generic-function-call-history generic-function)
      (progn
        (set-funcallable-instance-function generic-function
                                            (calculate-fastgf-dispatch-function generic-function))
        (apply generic-function valist-args))
      (dispatch-miss generic-function valist-args)))

(defun method-spec-matches-entry-spec (method-spec entry-spec)
  (or
   (and (consp method-spec)
        (consp entry-spec)
        (eq (car method-spec) 'eql)
        (eql (second method-spec) (car entry-spec)))
   (and (classp method-spec) (classp entry-spec)
        (member method-spec (clos:class-precedence-list entry-spec)))))

(defun call-history-entry-involves-method-with-specializers (entry method-specializers)
  (let ((key (car entry)))
    (loop for method-spec in method-specializers
       for entry-spec across key
       always (method-spec-matches-entry-spec method-spec entry-spec))))

(defun call-history-after-method-with-specializers-change (gf method-specializers)
  (loop for entry in (generic-function-call-history gf)
     unless (call-history-entry-involves-method-with-specializers entry method-specializers)
     collect entry))

#+(or)
(defun call-history-after-class-change (gf class)
;;;  (format t "call-history-after-class-change  start: gf->~a  call-history ->~a~%" gf (clos::generic-function-call-history gf))
  (loop for entry in (generic-function-call-history gf)
     unless (loop for subclass in (clos::subclasses* class)
               thereis (clos:call-history-entry-key-contains-specializer (car entry) subclass))
     collect entry))

(defun invalidate-generic-functions-with-class-selector (top-class)
;;;  (format t "!!!!Looking to invalidate-generic-functions-with-class-selector: ~a~%" top-class)
  ;; Loop over all of the subclasses of class (including class) and append together
  ;;    the lists of generic-functions for the specializer-direct-methods of each subclass
  (let* ((all-subclasses (clos:subclasses* top-class))
         (generic-functions (loop for subclass in all-subclasses
                               nconc (loop for method in (clos:specializer-direct-methods subclass)
                                        collect (clos:method-generic-function method))))
	 (unique-generic-functions (remove-duplicates generic-functions)))
    ;;(when core:*debug-dispatch* (format t "    generic-functions: ~a~%" generic-functions))
    (loop for gf in unique-generic-functions
       do (generic-function-call-history-remove-entries-with-specializers gf all-subclasses)
       do (maybe-invalidate-generic-function gf))))

(defun switch-to-fastgf (gf)
  (let ((dispatcher (calculate-fastgf-dispatch-function gf)))
    (set-funcallable-instance-function gf dispatcher)))

(export '(invalidate-generic-functions-with-class-selector
          switch-to-fastgf))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Satiation of generic functions to start fastgf
;;;
;;; Ideas copied from Sicl/Code/CLOS/satiation.lisp
;;;

(defun cartesian-product (sets)
  (if (null (cdr sets))
      (mapcar #'list (car sets))
      (loop for element in (car sets)
	    append (mapcar (lambda (set)
			     (cons element set))
			   (cartesian-product (cdr sets))))))

(defun calculate-all-argument-subclasses-of-method (specializers profile)
  (let ((sets (loop for class in specializers
                  for flag in profile
                  collect (if (null flag)
                              (list class)
                              (subclasses* class)))))
    (cartesian-product sets)))

(defun add-to-call-history (generic-function specializers profile verbose)
  (let* ((all-arguments-subclassed-for-method (calculate-all-argument-subclasses-of-method specializers profile)))
    (loop for combination in all-arguments-subclassed-for-method
       for methods = (std-compute-applicable-methods-using-classes generic-function combination)
       for effective-method-function = (compute-effective-method-function
                                        generic-function
                                        (generic-function-method-combination generic-function)
                                        methods)
       do (generic-function-call-history-push-new generic-function
                                                       (coerce combination 'vector)
                                                       effective-method-function)
       when verbose
         do (core:bformat t "%s\n" combination))))

(defun load-generic-function (generic-function list-of-specializers-names verbose)
  "If a list of lists of specializer names (like specializers of a method but the names and not classes)
   is given then load the generic-function-call-history with subclasses of the named classes
   when the generic-function-specializer-profile says to specialize on that argument.
   If list-of-specializers-names is NIL then use the specializers of the generic-function-methods."
  (compute-and-set-specializer-profile generic-function)
  (if list-of-specializers-names
      (loop with profile = (coerce (generic-function-specializer-profile generic-function) 'list)
         for specializer-names in list-of-specializers-names
         with specializers = (mapcar #'find-class specializer-names)
         do (add-to-call-history generic-function specializers profile verbose))
      (loop with profile = (coerce (generic-function-specializer-profile generic-function) 'list)
         for method in (generic-function-methods generic-function)
         for specializers = (method-specializers method)
         do (add-to-call-history generic-function specializers profile verbose)))
  (length (generic-function-call-history generic-function)))
  
(defun satiate-generic-function (gf-name list-of-specializers-names test verbose)
  ;; Many generic functions at startup will be missing specializer-profile at startup
  ;;    so we compute one here using the number of required arguments in the lambda-list.
  ;; The call-history may be incorrect because of improper initialization as
  ;;    clos starts up - so lets wipe it out and then satiate it.
  (let* ((generic-function (fdefinition gf-name))
         (lambda-list (generic-function-lambda-list generic-function))
         (num-req-args (length (lambda-list-required-arguments lambda-list)))
         (specializer-profile (make-array num-req-args :initial-element nil)))
    ;; Set the specializer-profile to a correctly sized vector of nils
    (setf (generic-function-specializer-profile generic-function) specializer-profile)
    ;; Compute the specializer-profile using the generic-function-method's
    (compute-and-set-specializer-profile generic-function)
    ;; Wipe out the call-history and satiate it using methods
    (setf (generic-function-call-history generic-function) nil)
    (let ((loaded (load-generic-function generic-function list-of-specializers-names (eq :verbose verbose))))
      (when verbose (format t "~a ~a~%" loaded gf-name))
      (unless test (switch-to-fastgf generic-function)))))

(defun satiate-standard-generic-functions (&key test verbose)
  (flet ((satiate-one (gf-name &optional list-of-specializers-names)
           (satiate-generic-function gf-name list-of-specializers-names test verbose)))
    ;; I may want to special case some generic functions
    ;;   and specify which methods they should use for satiation
    ;;   - so I'm defining satiate-one so that I can
    ;;     write a more sophisticated one in the future if needed.
    (satiate-one 'MAKE-INSTANCE)
    ;;  (satiate-one 'CLOS:ENSURE-CLASS-USING-CLASS)
    (satiate-one 'INITIALIZE-INSTANCE '((standard-object)))
    (satiate-one 'SHARED-INITIALIZE '((standard-object t)))
    (satiate-one 'REINITIALIZE-INSTANCE '((standard-object)))
    (satiate-one 'ALLOCATE-INSTANCE)
    (satiate-one 'CLOS:REMOVE-DIRECT-SUBCLASS)
    (satiate-one 'CLOS:COMPUTE-CLASS-PRECEDENCE-LIST)
    (satiate-one 'CLOS:METHOD-FUNCTION)
    (satiate-one 'CLOS:METHOD-LAMBDA-LIST)
    (satiate-one 'CLOS:COMPUTE-DISCRIMINATING-FUNCTION)
    (satiate-one 'CLOS:CLASS-SLOTS)
    (satiate-one 'ADD-METHOD)
    (satiate-one 'CLOS:CLASS-DEFAULT-INITARGS)
    (satiate-one 'CLOS:GENERIC-FUNCTION-METHODS)
    (satiate-one 'CLOS:COMPUTE-APPLICABLE-METHODS-USING-CLASSES)
    (satiate-one 'COMPUTE-APPLICABLE-METHODS)
    (satiate-one 'CLOS:METHOD-SPECIALIZERS)
    (satiate-one 'CLOS:SLOT-DEFINITION-INITFUNCTION)
    (satiate-one 'CLOS:METHOD-GENERIC-FUNCTION)
    (satiate-one 'CLOS:ADD-DEPENDENT)
    (satiate-one 'CLOS:SLOT-DEFINITION-WRITERS)
    ;;  (satiate-one 'CLOS:CLASS-DIRECT-SUBCLASSES)
    (satiate-one 'CLOS:GENERIC-FUNCTION-METHOD-CLASS)
    (satiate-one 'CLOS:GENERIC-FUNCTION-ARGUMENT-PRECEDENCE-ORDER)
    (satiate-one 'CLOS:SLOT-DEFINITION-ALLOCATION)
    (satiate-one 'CLOS:SLOT-DEFINITION-LOCATION)
    (satiate-one 'CLOS:EFFECTIVE-SLOT-DEFINITION-CLASS)
    (satiate-one 'CLOS:COMPUTE-DEFAULT-INITARGS)
    (satiate-one 'CLOS:WRITER-METHOD-CLASS)
    (satiate-one 'CLOS:REMOVE-DEPENDENT)
    (satiate-one 'CLOS:REMOVE-DIRECT-METHOD)
    (satiate-one 'CLOS:MAP-DEPENDENTS)
    (satiate-one 'CLOS:SLOT-MAKUNBOUND-USING-CLASS)
    (satiate-one 'CLOS:ADD-DIRECT-METHOD)
    (satiate-one 'CLOS:CLASS-FINALIZED-P)
    (satiate-one 'CLOS:SLOT-DEFINITION-NAME)
    (satiate-one 'CLOS:READER-METHOD-CLASS)
    (satiate-one 'CLOS:VALIDATE-SUPERCLASS)
    (satiate-one 'CLOS:COMPUTE-SLOTS)
    (satiate-one 'METHOD-QUALIFIERS)
    (satiate-one 'CLOS:SLOT-BOUNDP-USING-CLASS)
    (satiate-one 'CLOS:GENERIC-FUNCTION-METHOD-COMBINATION)
    (satiate-one 'CLOS:ADD-DIRECT-SUBCLASS)
    (satiate-one 'CLOS:SPECIALIZER-DIRECT-METHODS)
    (satiate-one 'CLOS:COMPUTE-EFFECTIVE-SLOT-DEFINITION)
    (satiate-one 'REMOVE-METHOD)
    (satiate-one 'CLOS:CLASS-DIRECT-SLOTS)
    (satiate-one 'CLOS:GENERIC-FUNCTION-LAMBDA-LIST)
    (satiate-one 'CLOS:SLOT-DEFINITION-INITARGS)
    (satiate-one 'CLOS:MAKE-METHOD-LAMBDA)
    (satiate-one 'CLOS:SLOT-DEFINITION-READERS)
    (satiate-one 'CLOS:ACCESSOR-METHOD-SLOT-DEFINITION)
    (satiate-one 'CLOS:GENERIC-FUNCTION-NAME)
    (satiate-one 'CLOS:CLASS-PROTOTYPE)
    (satiate-one 'CLOS:SLOT-VALUE-USING-CLASS)
    (satiate-one 'CLOS:FINALIZE-INHERITANCE)
    (satiate-one 'CLOS:DIRECT-SLOT-DEFINITION-CLASS)
    (satiate-one 'CLOS:SLOT-DEFINITION-TYPE)
    (satiate-one 'CLOS:GENERIC-FUNCTION-DECLARATIONS)
    (satiate-one 'CLOS:SPECIALIZER-DIRECT-GENERIC-FUNCTIONS)
    (satiate-one 'CLOS:COMPUTE-EFFECTIVE-METHOD)
    (satiate-one 'CLOS:ENSURE-GENERIC-FUNCTION-USING-CLASS)
    (satiate-one 'CLOS:FIND-METHOD-COMBINATION)
    (satiate-one 'CLOS:CLASS-PRECEDENCE-LIST)
    (satiate-one 'CLOS:CLASS-DIRECT-DEFAULT-INITARGS)
    (satiate-one 'PRINT-OBJECT)
    (satiate-one 'NO-APPLICABLE-METHOD) 
    ;;  (satiate-one 'SLOT-UNBOUND)
    (satiate-one 'MAKE-INSTANCES-OBSOLETE)
    (satiate-one 'UPDATE-INSTANCE-FOR-REDEFINED-CLASS)
    (satiate-one 'SLOT-MISSING)
    (satiate-one 'NO-NEXT-METHOD)
    (satiate-one 'FIND-METHOD)
    (satiate-one 'CLASS-NAME)
    #||
;;  (satiate-one 'CHANGE-CLASS))        ;
    (satiate-one 'CLOSE)
    )
  (satiate-one 'DESCRIBE-OBJECT)
  'CLOS:EQL-SPECIALIZER-OBJECT
  'CLOS:SLOT-DEFINITION-INITFORM 
  'CLOS:UPDATE-DEPENDENT 
  'FUNCTION-KEYWORDS 
  (satiate-one 'DOCUMENTATION)
  (satiate-one 'INTERACTIVE-STREAM-P)
  (satiate-one 'STREAM-ELEMENT-TYPE)
  (satiate-one 'INPUT-STREAM-P)
  (satiate-one 'OPEN-STREAM-P)
  (satiate-one 'UPDATE-INSTANCE-FOR-DIFFERENT-CLASS)
  ||#
  ))

  (defun cache-status ()
    (format t "                method-cache: ~a~%" (multiple-value-list (core:method-cache-status)))
    (format t "single-dispatch-method-cache: ~a~%" (multiple-value-list (core:single-dispatch-method-cache-status)))
    (format t "                  slot-cache: ~a~%" (multiple-value-list (core:slot-cache-status))))

  (export '(cache-status satiate-standard-generic-functions))
  
