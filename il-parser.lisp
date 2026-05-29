(defpackage :iec-il-parser
  (:use :cl :alexandria)
  (:export :il-statement
           :il-statement-label
           :il-statement-opcode
           :il-statement-operands
           :il-operand
           :il-address
           :il-literal
           :operand-raw
           :operand-area
           :operand-size
           :operand-byte-index
           :operand-bit-index
           :operand-value
           :il-parse-error
           :parse-error-token
           :parse-error-message
           :parse-il
           :dump-il
           :validate-iec-syntax
           :demo))

(in-package :iec-il-parser)

;; ========================
;; 1. Conditions
;; ========================
(define-condition il-parse-error (error)
  ((token   :initarg :token   :reader parse-error-token)
   (message :initarg :message :reader parse-error-message))
  (:report (lambda (c s)
             (format s "IEC 61131-3 IL Parse Error: ~A (at ~A)"
                     (parse-error-message c)
                     (parse-error-token c)))))

;; ========================
;; 2. AST Nodes (CLOS)
;; ========================
(defclass il-statement ()
  ((label    :initarg :label    :accessor il-statement-label    :initform nil)
   (opcode   :initarg :opcode   :accessor il-statement-opcode   :initform nil)
   (operands :initarg :operands :accessor il-statement-operands :initform '())))

(defclass il-operand ()
  ((raw :initarg :raw :accessor operand-raw)))

(defclass il-address (il-operand)
  ((area       :initarg :area       :accessor operand-area)
   (size       :initarg :size       :accessor operand-size       :initform :bit)
   (byte-index :initarg :byte-index :accessor operand-byte-index)
   (bit-index  :initarg :bit-index  :accessor operand-bit-index  :initform nil)))

(defclass il-literal (il-operand)
  ((value :initarg :value :accessor operand-value)))

;; ========================
;; 3. Comment Stripper
;; ========================
(defun strip-comments (source)
  "Remove ;, //, and (* *) comments, preserving newlines for line structure."
  (with-output-to-string (out)
    (let ((i 0)
          (len (length source)))
      (loop while (< i len) do
        (cond
          ;; (* ... *) block comment (may span lines)
          ((and (< (1+ i) len)
                (char= (char source i) #\()
                (char= (char source (1+ i)) #\*))
           (incf i 2)
           (loop
             (when (>= (1+ i) len)
               (setf i len)
               (return))
             (cond ((and (char= (char source i) #\*)
                         (char= (char source (1+ i)) #\)))
                    (incf i 2)
                    (return))
                   ((char= (char source i) #\Newline)
                    (write-char #\Newline out)
                    (incf i))
                   (t (incf i)))))
          ;; // line comment
          ((and (< (1+ i) len)
                (char= (char source i) #\/)
                (char= (char source (1+ i)) #\/))
           (loop while (and (< i len) (char/= (char source i) #\Newline))
                 do (incf i)))
          ;; ; line comment
          ((char= (char source i) #\;)
           (loop while (and (< i len) (char/= (char source i) #\Newline))
                 do (incf i)))
          ;; Regular character
          (t (write-char (char source i) out)
             (incf i)))))))

;; ========================
;; 4. Opcode Set (keyword-based, EQ lookup)
;; ========================
(defparameter *il-opcodes*
  (let ((ht (make-hash-table :test #'eq)))
    (dolist (op '(:LD :LDN :ST :STN
                  :AND :ANDN :OR :ORN :XOR :XORN :NOT :NOTN
                  :ADD :SUB :MUL :DIV
                  :EQ :GT :GE :LT :LE :NE
                  :CALL :RET :NOP
                  :SET :RESET :JMP :JMPN :CAL :CALN :JCN
                  :TON :TOF :TP :CTU :CTD
                  :MOVD :MOVB :MOVE :SWAP
                  :SEL :MAX :MIN
                  :MUL_REAL :DIV_REAL :ADD_REAL :SUB_REAL
                  :ABS :SQRT :LN :EXP
                  :SIN :COS :TAN :TRUNC :FRAC :FLOOR :CEIL
                  :MOD :BIT_AND :BIT_OR :BIT_XOR :BIT_NOT
                  :SHL :SHR :ROL :ROR))
      (setf (gethash op ht) t))
    ht))

;; ========================
;; 5. Operand Parser
;; ========================
(defun parse-operand (raw)
  "Parse a raw operand string into a structured il-operand."
  (let ((up (string-upcase raw)))
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings
         "^([IQM])([XBWDL])?([0-9]+)(?:\\.([0-9]+))?$" up)
      (cond
        ;; IEC address (I0.0, Q1.3, MW10, etc.)
        (match
         (make-instance 'il-address
           :raw raw
           :area (ecase (char (aref groups 0) 0)
                   (#\I :input) (#\Q :output) (#\M :memory))
           :size (if (aref groups 1)
                     (ecase (char (aref groups 1) 0)
                       (#\X :bit) (#\B :byte) (#\W :word)
                       (#\D :dword) (#\L :lword))
                     :bit)
           :byte-index (parse-integer (aref groups 2))
           :bit-index (when (aref groups 3)
                        (parse-integer (aref groups 3)))))
        ;; Numeric literal
        ((cl-ppcre:scan "^-?[0-9]" up)
         (make-instance 'il-literal :raw raw
           :value (multiple-value-bind (int end)
                       (parse-integer raw :junk-allowed t)
                     (if (and int (= end (length raw)))
                         int
                         (let ((*read-eval* nil))
                           (read-from-string raw))))))
        ;; Boolean literal
        ((member up '("TRUE" "FALSE") :test #'string=)
         (make-instance 'il-literal :raw raw
           :value (string= up "TRUE")))
        ;; Everything else (variable names, function block names, etc.)
        (t
         (make-instance 'il-operand :raw raw))))))

;; ========================
;; 6. Lexer
;; ========================
(defun lex (source)
  "Tokenize IL source into a list of (type . value) cons cells."
  (let ((cleaned (strip-comments source))
        (tokens '()))
    (with-input-from-string (in cleaned)
      (loop for line = (read-line in nil nil)
            while line
            do (loop for tok in (cl-ppcre:split "[ \\t,]+" line)
                     do (when (and tok (string/= tok ""))
                          (let* ((tok-up (string-upcase tok))
                                 (kw (find-symbol tok-up :keyword)))
                            (cond
                              ;; Label: trailing colon
                              ((and (> (length tok) 1)
                                    (char= (char tok (1- (length tok))) #\:))
                               (push (cons :label (subseq tok 0 (1- (length tok))))
                                     tokens))
                              ;; Known opcode
                              ((and kw (gethash kw *il-opcodes*))
                               (push (cons :opcode kw) tokens))
                              ;; Operand
                              (t
                               (push (cons :operand tok) tokens))))))))
    (nreverse (push (cons :eof nil) tokens))))

;; ========================
;; 7. Parser
;; ========================
(defun parse-il (source)
  "Parse IL source string into a list of il-statement objects."
  (let ((tokens (lex source)))
    (flet ((peek () (first tokens))
           (advance () (pop tokens)))
      (labels ((parse-statement ()
                 (let ((label nil)
                       (opcode nil)
                       (operands '()))
                   (when (and (peek) (eq (car (peek)) :label))
                     (setf label (cdr (advance))))
                   (unless (and (peek) (eq (car (peek)) :opcode))
                     (restart-case
                         (error 'il-parse-error
                                :token (peek)
                                :message "expected opcode")
                       (skip-statement ()
                         :report "Skip this statement and continue parsing"
                         (loop while (and (peek)
                                         (not (member (car (peek))
                                                      '(:label :opcode :eof))))
                               do (advance))
                         (return-from parse-statement nil))
                       (use-nop ()
                         :report "Insert a NOP instruction"
                         (setf opcode :NOP))))
                   (unless opcode
                     (setf opcode (cdr (advance))))
                   (loop while (and (peek) (eq (car (peek)) :operand))
                         do (push (parse-operand (cdr (advance))) operands))
                   (make-instance 'il-statement
                                  :label label
                                  :opcode opcode
                                  :operands (nreverse operands)))))
        (let ((statements '()))
          (loop until (eq (car (peek)) :eof)
                do (let ((stmt (parse-statement)))
                     (when stmt (push stmt statements))))
          (nreverse statements))))))

;; ========================
;; 8. Utilities
;; ========================
(defun dump-il (statements)
  "Pretty-print IL statements to stdout."
  (format t ";; IEC 61131-3 IL AST (~A statements)~%" (length statements))
  (dolist (stmt statements)
    (when (il-statement-label stmt)
      (format t ";; ~A:~%" (il-statement-label stmt)))
    (format t "   ~A ~A~%"
            (symbol-name (il-statement-opcode stmt))
            (if (il-statement-operands stmt)
                (format nil "~{~A ~}"
                        (mapcar #'operand-raw (il-statement-operands stmt)))
                ""))))

(defun validate-iec-syntax (statements)
  "Return a list of semantic error strings, or NIL if valid."
  (let ((errors '()))
    (dolist (stmt statements)
      (when (eq (il-statement-opcode stmt) :CALL)
        (unless (il-statement-operands stmt)
          (push "CALL requires at least a procedure name" errors)))
      (when (member (il-statement-opcode stmt) '(:ADD :SUB :MUL :DIV))
        (unless (>= (length (il-statement-operands stmt)) 2)
          (push "Arithmetic ops require ≥2 operands" errors))))
    errors))

;; ========================
;; 9. Sample & Demo
;; ========================
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

(defun demo ()
  "Parse and display the sample motor latch program."
  (let ((parsed (parse-il *sample-iec-il*)))
    (dump-il parsed)
    (format t "Validation errors: ~A~%" (validate-iec-syntax parsed))
    parsed))
