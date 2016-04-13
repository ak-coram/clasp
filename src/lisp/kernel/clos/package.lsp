;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: CLOS -*-
;;;;
;;;;  Copyright (c) 1992, Giuseppe Attardi.
;;;;  Copyright (c) 2001, Juan Jose Garcia Ripoll.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

;;;; clasp - changes approved May1 2013

;;#-clasp
(defpackage "CLOS"
  (:use "CL" "EXT")
  (:import-from "SI" "UNBOUND" "GET-SYSPROP" "PUT-SYSPROP" "REM-SYSPROP"
		"SIMPLE-PROGRAM-ERROR"))


#+clasp (in-package "CLOS")
#+clasp (use-package '(:CORE :ext) :clos)
#+clasp (import '(unbound get-sysprop put-sysprop rem-sysprop simple-program-error
		 slot-descriptions
		 SLOT-NAMES SLOT-NAME CLASS-PRECEDENCE-LIST PRINT-FUNCTION
		 CONSTRUCTORS COUNT-FUNCTION-CONTAINER-ENVIRONMENTS
		 SETF-FIND-CLASS ALLOCATE-RAW-CLASS SPECIALIZER
		 FORWARD-REFERENCED-CLASS METAOBJECT STD-CLASS ) :si)




#+compare (print "MLOG ********* Starting package.lsp **********")
#+clasp
(defmacro clos-log (fmt &rest args)
  `(bformat t ,fmt ,@args))

#+clasp
(export '(WITH-SLOTS WITH-ACCESSORS UPDATE-INSTANCE-FOR-REDEFINED-CLASS
	  UPDATE-INSTANCE-FOR-DIFFERENT-CLASS STANDARD-METHOD
	  STANDARD SLOT-UNBOUND SLOT-MISSING SLOT-MAKUNBOUND
	  SLOT-EXISTS-P SLOT-BOUNDP SHARED-INITIALIZE REMOVE-METHOD
	  REINITIALIZE-INSTANCE NO-NEXT-METHOD METHOD-QUALIFIERS
	  METHOD-COMBINATION-ERROR METHOD-COMBINATION MAKE-METHOD
	  MAKE-LOAD-FORM-SAVING-SLOTS MAKE-LOAD-FORM MAKE-INSTANCES-OBSOLETE
	  INVALID-METHOD-ERROR INITIALIZE-INSTANCE FUNCTION-KEYWORDS
	  FIND-METHOD ENSURE-GENERIC-FUNCTION DESCRIBE-OBJECT
	  CHANGE-CLASS CALL-METHOD ALLOCATE-INSTANCE
	  ADD-METHOD ))

(export '(UPDATE-DEPENDENT 
          LOAD-DEFCLASS 
          SLOT-DEFINITION-LOCATION 
          CLASS-PRECEDENCE-LIST 
          +THE-FUNCALLABLE-STANDARD-CLASS+ 
          CLASS-SLOTS 
          SPECIALIZER 
          MAKE-METHOD-LAMBDA 
          SLOT-DEFINITION-ALLOCATION 
          STANDARD-DIRECT-SLOT-DEFINITION 
          STANDARD-WRITER-METHOD 
          EFFECTIVE-SLOT-DEFINITION-CLASS 
          MAP-DEPENDENTS 
          STANDARD-READER-METHOD 
          SLOT-DEFINITION-TYPE 
          STD-COMPUTE-EFFECTIVE-METHOD 
          GENERIC-FUNCTION-ARGUMENT-PRECEDENCE-ORDER 
          EQL-SPECIALIZER 
          COMPUTE-EFFECTIVE-SLOT-DEFINITION 
          WRITER-METHOD-CLASS 
          SLOT-TABLE 
          CLASS-DEFAULT-INITARGS 
          METHOD-SPECIALIZERS 
          ENSURE-GENERIC-FUNCTION-USING-CLASS 
          SLOT-DEFINITION-INITARGS 
          METAOBJECT 
          NEED-TO-MAKE-LOAD-FORM-P 
          COMPUTE-SLOTS 
          STD-COMPUTE-APPLICABLE-METHODS-USING-CLASSES 
          GENERIC-FUNCTION-METHOD-COMBINATION 
          CLASS-PROTOTYPE 
          FUNCALLABLE-STANDARD-CLASS 
          STD-COMPUTE-APPLICABLE-METHODS 
          SLOT-DEFINITION 
          SET-FUNCALLABLE-INSTANCE-FUNCTION 
          ACCESSOR-METHOD-SLOT-DEFINITION 
          CLASS-DIRECT-SLOTS 
          FIND-METHOD-COMBINATION 
          GENERIC-FUNCTION-NAME 
          CLASS-DIRECT-SUPERCLASSES 
          EQL-SPECIALIZER-OBJECT 
          ENSURE-CLASS-USING-CLASS 
          EXTRACT-SPECIALIZER-NAMES 
          SPECIALIZER-DIRECT-GENERIC-FUNCTIONS 
          ADD-DIRECT-SUBCLASS 
          SAFE-INSTANCE-REF 
          METHOD-FUNCTION 
          COMPUTE-DEFAULT-INITARGS 
          FUNCALLABLE-STANDARD-INSTANCE-ACCESS 
          READER-METHOD-CLASS 
          +THE-STD-CLASS+ 
          SPECIALIZER-DIRECT-METHODS 
          REMOVE-DEPENDENT 
          DIRECT-SLOT-DEFINITION 
          GENERIC-FUNCTION-METHODS 
          *OPTIMIZE-SLOT-ACCESS* 
          SLOT-MAKUNBOUND-USING-CLASS 
          *NEXT-METHODS* 
          STANDARD-ACCESSOR-METHOD 
          SLOT-DEFINITION-WRITERS 
          METHOD-LAMBDA-LIST 
          SLOT-VALUE-USING-CLASS 
          GENERIC-FUNCTION-LAMBDA-LIST 
          FUNCALLABLE-STANDARD-OBJECT 
          COMPUTE-EFFECTIVE-METHOD-FUNCTION 
          VALIDATE-SUPERCLASS 
          ADD-DIRECT-METHOD 
          ENSURE-CLASS 
          SLOT-DEFINITION-NAME 
          FINALIZE-INHERITANCE 
          UPDATE-INSTANCE 
          CLASS-FINALIZED-P 
          .COMBINED-METHOD-ARGS. 
          COMPUTE-DISCRIMINATING-FUNCTION 
          SLOT-DEFINITION-READERS 
          ADD-DEPENDENT 
          +BUILTIN-CLASSES+ 
          EXTRACT-LAMBDA-LIST 
          +THE-CLASS+ 
          COMPUTE-CLASS-PRECEDENCE-LIST 
          DIRECT-SLOT-DEFINITION-CLASS 
          EFFECTIVE-SLOT-DEFINITION 
          REMOVE-DIRECT-SUBCLASS 
          STANDARD-EFFECTIVE-SLOT-DEFINITION 
          STANDARD-OPTIMIZED-WRITER-METHOD 
          CLASS-DIRECT-SUBCLASSES 
          GENERIC-FUNCTION-DECLARATIONS 
          STANDARD-INSTANCE-ACCESS 
          COMPUTE-APPLICABLE-METHODS-USING-CLASSES 
          GENERIC-FUNCTION-METHOD-CLASS 
          +THE-STANDARD-CLASS+ 
          FORWARD-REFERENCED-CLASS 
          SLOT-BOUNDP-USING-CLASS 
          STANDARD-OPTIMIZED-READER-METHOD 
          STANDARD-INSTANCE-SET 
          INTERN-EQL-SPECIALIZER 
          METHOD-GENERIC-FUNCTION 
          COMPUTE-EFFECTIVE-METHOD 
          DOCSTRING 
          STANDARD-SLOT-DEFINITION 
          REMOVE-DIRECT-METHOD 
          SLOT-VALUE-SET 
          +THE-T-CLASS+ 
          CLASS-DIRECT-DEFAULT-INITARGS 
          SLOT-DEFINITION-INITFUNCTION 
          SLOT-DEFINITION-INITFORM )
        )

(export '*environment-contains-closure-hook*)

#+(or)(defmacro gf-log (fmt &rest fmt-args)
        `(progn
           (format t "GF-LOG:  ")
           (format t ,fmt ,@fmt-args)
           (format t "~%")))

(defmacro gf-log (fmt &rest fmt-args) nil)
