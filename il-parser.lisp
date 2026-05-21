(defpackage :iec-il-parser
  (:use :cl :alexandria)
  (:export :parse-il
           :dump-il
           :il-statement
           :il-label
           :il-opcode
           :il-operands
           :validate-iec-syntax))

(in-package :iec-il-parser)

;; ========================
;; 1. AST Node
;; ========================
(defstruct (il-statement (:constructor %make-il-statement))
  (label nil :type (or null string))
  (opcode nil :type string)
  (operands '() :type list))

(defun make-il-statement (&key (label nil) (opcode nil) (operands '()))
  (%make-il-statement :label label :opcode opcode :operands (coerce operands 'list)))

;; ========================
;; 2. Lexer (Tokenizer)
;; ========================
;; Fix 1: proper alist with dotted pairs + :test #'equal for string keys
(defparameter *il-keywords*
  (alexandria:alist-hash-table
   '(("LD" . :opcode) ("LDN" . :opcode) ("ST" . :opcode) ("STN" . :opcode)
     ("AND" . :opcode) ("ANDN" . :opcode) ("OR" . :opcode) ("ORN" . :opcode)
     ("XOR" . :opcode) ("XORN" . :opcode) ("NOT" . :opcode) ("NOTN" . :opcode)
     ("ADD" . :opcode) ("SUB" . :opcode) ("MUL" . :opcode) ("DIV" . :opcode)
     ("EQ" . :opcode) ("GT" . :opcode) ("GE" . :opcode) ("LT" . :opcode) ("LE" . :opcode)
     ("NE" . :opcode) ("CALL" . :opcode) ("RET" . :opcode) ("NOP" . :opcode)
     ("SET" . :opcode) ("RESET" . :opcode) ("JMP" . :opcode) ("JMPN" . :opcode)
     ("CAL" . :opcode) ("CALN" . :opcode) ("JCN" . :opcode)
     ("TON" . :opcode) ("TOF" . :opcode) ("TP" . :opcode) ("CTU" . :opcode) ("CTD" . :opcode)
     ("MOVD" . :opcode) ("MOVB" . :opcode) ("MOVE" . :opcode) ("SWAP" . :opcode)
     ("SEL" . :opcode) ("MAX" . :opcode) ("MIN" . :opcode) ("MUL_REAL" . :opcode)
     ("DIV_REAL" . :opcode) ("ADD_REAL" . :opcode) ("SUB_REAL" . :opcode)
     ("ABS" . :opcode) ("SQRT" . :opcode) ("LN" . :opcode) ("EXP" . :opcode)
     ("SIN" . :opcode) ("COS" . :opcode) ("TAN" . :opcode) ("TRUNC" . :opcode)
     ("FRAC" . :opcode) ("FLOOR" . :opcode) ("CEIL" . :opcode)
     ("MOD" . :opcode) ("BIT_AND" . :opcode) ("BIT_OR" . :opcode) ("BIT_XOR" . :opcode)
     ("BIT_NOT" . :opcode) ("SHL" . :opcode) ("SHR" . :opcode) ("ROL" . :opcode) ("ROR" . :opcode))
   :test #'equal))

(defun lex (source)
  (with-input-from-string (in source)
    (let ((tokens '()))
      (loop for line = (read-line in nil nil)
            while line
            ;; Fix 2: removed invalid :over-write keyword; added ; comment style
            do (let ((cleaned (cl-ppcre:regex-replace "(?:;.*|//.*|\\(\\*.*?\\*\\))" line "")))
                 (when (string/= cleaned "")
                   (loop for token in (cl-ppcre:split "[ \t,;]+" cleaned)
                         do (when (string/= token "")
                              (let* ((tok (string-trim " " token))
                                     (tok-up (string-upcase tok))
                                     ;; Fix 3: correct arg order — target then replacement
                                     (base (cl-ppcre:regex-replace "[NP]$" tok-up "")))
                                ;; Fix 4: label detection — trailing colon only (standard IL)
                                (cond ((and (> (length tok) 1)
                                            (char= (aref tok (1- (length tok))) #\:))
                                       (push (cons :label (subseq tok 0 (1- (length tok)))) tokens))
                                      ((gethash base *il-keywords*)
                                       (push (cons :opcode tok-up) tokens))
                                      (t
                                       (push (cons :operand tok) tokens)))))))))
      (nreverse (push (cons :eof nil) tokens)))))

;; ========================
;; 3. Parser (Recursive Descent)
;; ========================
(defparameter *tok-stream* nil)

(defun next-token () (pop *tok-stream*))
(defun peek-token () (first *tok-stream*))

(defun parse-statement ()
  (let ((label nil)
        (opcode nil)
        (operands '()))
    (when (and (peek-token) (eq (car (peek-token)) :label))
      (setf label (cdr (pop *tok-stream*))))
    (unless (and (peek-token) (eq (car (peek-token)) :opcode))
      (error "IEC 61131-3 IL Syntax Error: expected opcode at ~A" (peek-token)))
    (setf opcode (cdr (pop *tok-stream*)))
    (loop while (and (peek-token) (eq (car (peek-token)) :operand))
          do (push (cdr (pop *tok-stream*)) operands))
    (make-il-statement :label label :opcode opcode :operands (nreverse operands))))

(defun parse-il (source)
  (setf *tok-stream* (lex source))
  (let ((statements '()))
    (loop until (eq (car (peek-token)) :eof)
          do (push (parse-statement) statements))
    (nreverse statements)))

;; ========================
;; 4. Utilities & Demo
;; ========================
(defun dump-il (statements)
  (format t ";; IEC 61131-3 IL AST (~A statements)~%" (length statements))
  (dolist (stmt statements)
    (when (il-statement-label stmt)
      (format t ";; ~A:~%" (il-statement-label stmt)))
    (format t "   ~A ~A~%" (il-statement-opcode stmt)
            (if (il-statement-operands stmt)
                (format nil "~{~A ~}" (il-statement-operands stmt))
                ""))))

(defun validate-iec-syntax (statements)
  (let ((errors '()))
    (dolist (stmt statements)
      (when (string= (il-statement-opcode stmt) "CALL")
        (unless (il-statement-operands stmt)
          (push "CALL requires at least a procedure name" errors)))
      (when (member (il-statement-opcode stmt) '("ADD" "SUB" "MUL" "DIV") :test #'string=)
        (unless (>= (length (il-statement-operands stmt)) 2)
          (push "Arithmetic ops require ≥2 operands" errors))))
    errors))

;; ▶ Example IEC IL Program (labels use standard trailing-colon format)
(defparameter *sample-iec-il*
  "
  ; Motor Latch Control
  START_LATCH:
  LD     I0.0          ; Start PB (NO)
  ANDN   I0.1          ; Stop PB (NC)
  OR     Q0.0          ; Latch with motor feedback
  ST     Q0.0          ; Set contactor coil
  RET
  ")

;; Fix 9: declare *parsed* before setf
(defparameter *parsed* nil)
(setf *parsed* (parse-il *sample-iec-il*))
(dump-il *parsed*)
(format t "Validation errors: ~A~%" (validate-iec-syntax *parsed*))
