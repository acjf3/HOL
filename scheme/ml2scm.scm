(require (lib "plt-match.ss")
         (lib "pretty.ss"))

(define output-directory "/root/temp/")

(define name 'Randomset)

(define name-string (symbol->string name))

(define requires null)

;read in the ML program, as a parsed S-exp (by haMLet)
(define sigProgram
  (with-input-from-file
      (string-append output-directory
                     name-string
                     "-sig.s")
    (lambda ()
      (read)
      (read)
      (read))))


(define Program
  (with-input-from-file
      (string-append output-directory
                     name-string
                     ".s")
    (lambda ()
      (read)
      (read)
      (read))))

(define (symbol-append sym str)
  (string->symbol
   (string-append
    (symbol->string sym)
    str)))
(define (make-str-name id)
  (symbol-append id "@"))
(define (make-sig-name id)
  (symbol-append id "^"))


;function name mapping from ML to Scheme (need to extend)
(define function-table
  (make-immutable-hash-table
   '((~ . -)
     (+ . +)
     (* . *)
     (- . -)
     (div . /)
     (:: . cons)
     (@ . append)
     (ref . box)
     (:= . set-box!)
     (! . unbox)
     (abs . abs)
     (app . apply)
     (ceil . ceiling)
     (chr . integer->char)
     (concat . string-concatenate);need to be exported
     (explode . string->list)
     (floor . floor)
     (foldl . foldl);need to be exported
     (foldr . foldr);need to be exported
     (hd . car)
     (help . void)
     (ignore . void)
     (implode . list->string)
     (length . length)
     (map . map)
     (not . not)
     (null . null?)
     (ord . char->integer)
     (print . print)
     ;(read_integer . read)
     (real . exact->inexact)
     (rev . reverse)
     (round . round)
     (size . string-length)
     (str . char->string);need to be exported
     (substring . substring)
     (tl . cdr)
     (trunc . inexact->exact);
     (vector . vector)
     ;(toString . number->string)
     (^ . string-append)
     (mod . modulo);or quotient?
     (@ . append)
     (= . eqv?)
     (<> . !=);need to be exported
     (< . <)
     (<= . <=)
     (> . >)
     (>= . >=)
     (o . compose);need to be exported
     (before . begin0)     
     )))

;ML's build-in function takes a record as argument
;tranform to Scheme function: can take arbitrary number of arguments
(define (function-map f arg)
  (cond ((symbol? f)
         (let ((scheme-f
                (hash-table-get function-table f (lambda () #f))))
           (match (list arg scheme-f)
             ((list (list (or 'list 'list-no-order) (list 'cons (list 'quote (? number? _)) act-arg) ...)
                    (not #f))
              (cons scheme-f act-arg))
             (else
              (list f arg)))))
        ((and (pair? f)
              (eq? (car f) 'struct))
         `(struct ,(cadr f) (,arg)))
        (else
         (list f arg))))

;ML pattern to Scheme
(define (pattern-map f arg)
  (let ((scheme-f
         (hash-table-get function-table f (lambda () #f))))
    (if scheme-f
        (cons scheme-f (map caddr (cdr arg)))
        `(struct ,(cadr f) (,arg)))))

;translate : ML-program list-of-defined -> list-of-Scheme-program list-of-defined
(define (translate ml-program defined)
  (match ml-program
    ((list (or 'Program 'STRDECTopDec 'DECStrDec 'RECValBind 'ATPat 'IDAtPat 'SIGDECTopDec 'STRUCTUREStrDec 'SigDec 'SIGSigExp 'VALSpec 'IDSigExp 'STRUCTStrExp 'EXCEPTIONDec 'EXCEPTIONSpec 'DATATYPESpec) _ p)
     (translate p defined))
    ((list (or 'Program 'STRDECTopDec 'SEQStrDec 'SEQDec 'SIGDECTopDec 'SEQSpec) _ p1 p2)
     (let*-values (((translated-p1 middle-defined)
                    (translate p1 defined))
                   ((translated-p2 new-defined)
                    (translate p2 middle-defined)))
       (values (append! translated-p1 translated-p2)
               new-defined)))
    ((list 'VALDec _ _ p)
     (translate p defined))
    ((list 'PLAINValBind _ var val)
     ;var and val should be translated to be one expression
     (let*-values (((translated-var middle-defined)
                    (translate var defined))
                   ((translated-val new-defined)
                    (translate val middle-defined)))
       (values `((match-define ,(car translated-var)
                               ,@translated-val))
               new-defined)))
    ((list 'PLAINValBind _ var val another)
     (let*-values (((translated-var middle-defined)
                    (translate var defined))
                   ((translated-val new-defined)
                    (translate val middle-defined))
                   ((translated-another final-defined)
                    (translate another new-defined)))
       (values (cons `(match-define ,(car translated-var)
                                    ,@translated-val)
                     translated-another)
               final-defined)))
    ;build in ML types
    ((list 'LongVId 'true)
     (values '(#t)
             defined))
    ((list 'LongVId 'false)
     (values '(#f)
             defined))
    ((list 'LongVId 'nil)
     (values '(())
             defined))
    ((list (or 'VId 'StrId 'LongVId 'SigId 'LongStrId) a)
     (cond ((regexp-match "([^\\.]*)\\.(.*)" (symbol->string a))
            => (match-lambda
                 ((list _ module-string var-string)
                  (let ((module-name (string->symbol module-string))
                        (var-name (string->symbol var-string)))
                    (values `((ml-dot ,module-name ,var-name))
                            ;maybe need to open .data file for that module?
                            defined)))))
           (else
            (values (list (if (memq a defined)
                              `(struct ,a ())
                              a))
                    defined))))
    ((list (or 'ATExp 'PARAtExp 'PARAtPat 'SCONAtExp 'IDAtExp) _ p)
     (translate p defined))
    ((list 'APPExp _ f arg)
     ;both f and arg should be translated to be one expression
     (let*-values (((f-translated middle-defined)
                    (translate f defined))
                   ((arg-translated new-defined)
                    (translate arg middle-defined)))
       (values (list (function-map (car f-translated)
                                   (car arg-translated)))
               new-defined)))
    ((list 'CONPat _ id pat)
     ;both id and pat should be translated to be one expression
     (let*-values (((id-translated middle-defined)
                    (translate id defined))
                   ((pat-translated new-defined)
                    (translate pat middle-defined)))
       (values (list (pattern-map (car id-translated)
                                  (car pat-translated)))
               new-defined)))
    ((list 'RECORDAtPat _)
     (values '((list-no-order))
             defined))
    ((list 'RECORDAtPat _ p)
     ;p should be a FIELDPatRow
     (let-values (((p-translated new-defined)
                   (translate p defined)))
       (values `((list-no-order ,@(cdar p-translated)))
               new-defined)))
    ((list (or 'ExpRow 'FIELDPatRow) _ (list 'Lab n) p)
     ;p should be translated to be one expression
     (let-values (((p-translated new-defined)
                   (translate p defined)))
       (values `((list (cons (quote ,n) ,@p-translated)))
               new-defined)))
    ((list (or 'ExpRow 'FIELDPatRow) _ (list 'Lab n) p1 p2)
     ;p1 should be translated to be one expression
     (let*-values (((translated-p1 middle-defined)
                    (translate p1 defined))
                   ((translated-p2 new-defined)
                    (translate p2 middle-defined)))
       (values `((list (cons (quote ,n) ,@translated-p1)
                       ,@(cdar translated-p2)))
               new-defined)))
    ((list 'SCONAtPat _ p)
     (translate p defined))
    ((list (or 'INTSCon 'REALSCon 'STRINGSCon) n)
     (values (list n)
             defined))
    ((list 'EMPTYStrDec _)
     (values ()
             defined))
    ((list 'FNExp _ p)
     (let-values (((p-translated new-defined)
                   (translate p defined)))
       (values `((match-lambda ,@p-translated))
               new-defined)))
    ((list 'Match _ p)
     (let-values (((p-translated new-defined)
                   (translate p defined)))
       (values (list p-translated)
               new-defined)))
    ((list 'Match _ p1 p2)
     (let*-values (((translated-p1 middle-defined)
                    (translate p1 defined))
                   ((translated-p2 new-defined)
                    (translate p2 middle-defined)))
       (values (cons translated-p1
                     translated-p2)
               new-defined)))
    ;Mrule/Match/FNExp rules work together
    ((list 'Mrule _ pat exp)
     ;both pat and exp should be translated to be one expression
     (let*-values (((translated-pat middle-defined)
                    (translate pat defined))
                   ((translated-exp new-defined)
                    (translate exp middle-defined)))
       (values (list (car translated-pat)
                     (car translated-exp))
               new-defined)))
    ((list 'LETAtExp _ def body)
     (let*-values (((translated-def middle-defined)
                    (translate def defined))
                   ((translated-body new-defined)
                    (translate body middle-defined)))
       (values `((let ()
                   ,@translated-def
                   ,@translated-body))
               defined)))
    ((list (or 'COLONPat 'COLONExp) _ v _)
     (translate v defined))
    ((list 'RECORDAtExp _)
     (values '(())
             defined))
    ((list 'RECORDAtExp _ p)
     (translate p defined))
    ((list 'TYPEDec _ _)
     (values ()
             defined))
    ((list 'WILDCARDAtPat _)
     (values '(_)
             defined))
    ((list 'DOTSPatRow _)
     (values `((list ,(gensym) ...))
             defined))
    ((list 'LOCALStrDec _ locdef boddef)
     ;boddef should be translated to be one expression
     (let*-values (((translated-locdef middle-defined)
                    (translate locdef defined))
                   ((translated-boddef new-defined)
                    (translate boddef middle-defined)))
       (let ((body (car translated-boddef)))
         (match body
           ((list 'match-define expr cause)
            (values `((match-define ,expr
                                    (let ()
                                      ,@translated-boddef
                                      ,cause)))
                    defined))
           ;open
           (else
            (values
             `((let ()
                 ,translated-locdef
                 ,body))
             defined))))))
    ((list 'DATATYPEDec _ p)
     (translate p defined))
    ((list 'DatBind _ _ _ p)
     (translate p defined))
    ((list 'ConBind _ p)
     (let*-values (((translated-p new-defined)
                    (translate p defined))
                   ((id) (car translated-p)))
       (if (memq id defined)
           (values '()
                   new-defined)
           (values `((define-struct ,@translated-p () #f))
                   (cons (car translated-p) defined)))))
    ((list 'ConBind _ p1 (and p2 (list-rest 'ConBind _)))
     (let-values (((translated-p1 middle-defined)
                   (translate p1 defined))
                  ((translated-p2 final-defined)
                   (translate p2 defined)))
       (values (cons `(define-struct ,@translated-p1 () #f)
                     translated-p2)
               (cons (car translated-p1) final-defined))))
    ((list 'ConBind _ p _)
     (let-values (((translated-p new-defined)
                   (translate p defined)))
       (values `((define-struct ,@translated-p (content) #f))
               (cons (car translated-p) new-defined))))
    ((list 'ConBind _ p1 _ p2)
     (let*-values (((translated-p1 mid-defined)
                    (translate p1 defined))
                   ((translated-p2 new-defined)
                    (translate p2 mid-defined)))
       (values (cons `(define-struct ,@translated-p1 (content) #f)
                     translated-p2)
               (cons (car translated-p1) new-defined))))
    ((list 'NEWExBind _ p)
     (let*-values (((translated-id _)
                    (translate p defined)))
       (values `((define-struct ,@translated-id () #f))
               (cons (car translated-id) defined))))
    ((list 'NEWExBind _ p _)
     (let*-values (((translated-id _)
                    (translate p defined)))
       (values `((define-struct ,@translated-id (content) #f))
               (cons (car translated-id) defined))))
    ((list 'RAISEExp _ p)
     (let-values (((p-translated new-defined)
                   (translate p defined)))
       (values  `((raise ,@p-translated))
                new-defined)))
    ((list 'HANDLEExp _ body matcher)
     (let*-values (((translated-body middle-defined)
                    (translate body defined))
                   ((translated-matcher new-defined)
                    (translate matcher middle-defined)))
       (values `((with-handlers ,(map match->handlers
                                      translated-matcher)
                   ,@translated-body))
               new-defined)))
    ((list 'StrBind _ name body)
     (let*-values (((translated-name middle-defined)
                    (translate name defined))
                   ((translated-body new-defined)
                    (translate body middle-defined)))
       (values `((define-structure ,(make-str-name (car translated-name)) ,@translated-body))
               new-defined)))
    ((list 'SEALStrExp _ structure signiture)
     (let*-values (((translated-structure middle-defined)
                    (translate structure defined))
                   ((translated-signiture new-defined)
                    (translate signiture middle-defined)))
       (values (cons (make-sig-name (car translated-signiture))
                     translated-structure)
               new-defined)))
    ;any difference between this two?
    ((list 'COLONStrExp _ structure signiture)
     (let*-values (((translated-structure middle-defined)
                    (translate structure defined))
                   ((translated-signiture new-defined)
                    (translate signiture middle-defined)))
       (values (cons (make-sig-name (car translated-signiture))
                     translated-structure)
               new-defined)))
    ((list 'SigBind _ id sig)
     (let*-values (((translated-id middle-defined)
                    (translate id defined))
                   ((translated-sig new-defined)
                    (translate sig middle-defined)))
       (values `((define-signature ,(make-sig-name (car translated-id))
                   ,translated-sig))
               new-defined)))
    ((list 'TYPESpec _ _)
     (values ()
             defined))
    ((list 'DatDesc _  _  _ p)
     (translate p defined))
    ((list 'ConDesc _ p _)
     (let-values (((translated-p new-defined)
                   (translate p defined)))
       (values `((struct ,(car translated-p) (content)))
               (cons (car translated-p) new-defined))))
    ((list 'ValDesc _ p _)
     (translate p defined))
    ((list 'OPENDec _ p)
     (let-values (((translated-p new-defined)
                   (translate p defined)))
       ;update requires
       (set! requires (cons (car translated-p) requires))
       (values `((ml-open ,(make-str-name (car translated-p))))
               (append! (with-input-from-file
                            (string-append output-directory (symbol->string (car translated-p)) ".data")
                          read)
                        new-defined))))
    ((list 'ExDesc _ p)
     (let-values (((translated-p new-defined)
                   (translate p defined)))
       (values `((struct ,(car translated-p) ()))
               (cons (car translated-p) new-defined))))
    ((list 'ExDesc _ p _)
     (let-values (((translated-p new-defined)
                   (translate p defined)))
       (values `((struct ,(car translated-p) (content)))
               (cons (car translated-p) new-defined))))
    ((list 'ASPat _ id pat)
     (let-values (((translated-id _)
                   (translate id defined))
                  ((translated-pat new-defined)
                   (translate pat defined)))
       (values `((and ,(car translated-id) ,@translated-pat))
               new-defined)))
    ((list 'EMPTYDec _)
     (values '()
             defined))
    (else
     (error (car else))
     )))

(define (beta-redex? literals body)
  (match body
    ((list 'match-lambda (list (? symbol? literal) body2))
     (beta-redex? (cons literal literals) body2))
    ((list f (list 'list (list 'cons (list 'quote (? number? _)) args) ...))
     (and (equal? args (reverse literals))
          (equal? (car f) 'match-lambda)
          (null? (cddr f))))
    (else
     #f)))

(define beta-reduct
  (match-lambda
    ((list 'match-lambda (list (? symbol? literal) body))
     (beta-reduct body))
    (else
     (curry (car else)))))

(define (curry e)
  (match e
    ((list 'match-lambda (list (list (or 'list 'list-no-order) (list 'cons _ arg)) body))
     `(match-lambda (,arg ,body)))
    ((list 'match-lambda (list (list-rest (or 'list 'list-no-order) (list 'cons _ arg) args) body))
     `(match-lambda (,arg
                     ,(curry `(match-lambda ((list-no-order ,@args) ,body))))))
    (else
     (error 'beta-reduction e))))

(define (if2and/or s)
  (cond ((eq? (caddr s) #t)
         `(or ,(cadr s) ,(cadddr s)))
        ((eq? (cadddr s) #f)
         `(and ,(cadr s) ,(caddr s)))
        (else
         s)))

(define improve
  (match-lambda
    ;lambda -> begin
    ((list (list 'match-lambda
                 (list '_ b)) a)
     (let ((improved_b (improve b)))
       (if (and (pair? improved_b)
                (eq? (car improved_b) 'begin))
           `(begin ,(improve a)
                   ,@(cdr improved_b))
           `(begin ,(improve a)
                   ,improved_b))))
    ;beta reduction (without curry)
    ((list 'match-lambda (list (? symbol? literal) (list lamb literal)))
     (improve lamb))
    ;match-lambda -> if
    ((list (list 'match-lambda
                 (list #t then)
                 (list #f else))
           cond)
     (if2and/or
      (list 'if
            (improve cond)
            (improve then)
            (improve else))))
    ;match-lambda -> lambda
    ((list 'match-lambda (list (? symbol? literal) body))
     (if (beta-redex? (list literal) body)
         ;beta reduction (with curry)
         (improve (beta-reduct `(match-lambda (,literal ,body))))
         `(lambda (,literal) ,(improve body))))
    ;match-lambda -> lambda, for Records
    ;match-lambda -> match-lambda*
    #;((list 'match-lambda
           (list (list 'list-no-order (list 'cons (list 'quote (? number? _)) arg) ...) body) ...)
     (if (and (= (length body) 1)
              (andmap symbol? (car arg)))
         (list* 'lambda (car arg) (improve body))
         (cons 'match-lambda*
               (map (lambda (arg body)
                      (list (cons 'list arg) (improve body)))
                    arg body))))
    ;match-define -> define
    ((list 'match-define (? symbol? var) val)
     `(define ,var ,(improve val)))
    ;Records
    ((list 'list (list 'cons lab val) ... (? symbol? sym) '...)
     `(list-no-order ,@(map (lambda (l v) `(cons ,l ,v))
                            lab val)
                     ,sym ...))
    ;recursion
    ((cons p1 p2)
     (cons (improve p1)
           (improve p2)))
    (else
     else)))

(define (match->handlers clause)
  (let ((pattern (car clause)))
    `((match-lambda (,pattern #t))
      (match-lambda ,clause))))

(define (my-write file-name sexp)
  (with-output-to-file file-name
    (lambda ()
      (pretty-print sexp))))

;for signature
(let-values (((code defined)
                (translate sigProgram
                           ;this is ML pre-defined (may need to extend)
                           '(SOME NONE LESS EQUAL GREATER
                                  QUOTE ANTIQUOTE
                                  ;exceptions
                                  Out_of_memory Invalid_argument Graphic
                                  Interrupt Overflow Fail Ord Match Bind
                                  Size Div SysErr Subscript Chr Io Domain))))
    (my-write (string-append output-directory name-string "-sig.ss")
              `(module ,(symbol-append name "-sig") (lib "mlsig.scm" "lang")
                 (provide ,(make-sig-name name))
                 (require ,@(map (lambda (id)
                                   (string-append (symbol->string id) ".ss"))
                                 requires))
                 ,@(improve code)))
    (my-write (string-append output-directory name-string ".data")
              defined))

;for structure
(let-values (((code defined)
              (translate Program
                         (with-input-from-file
                             (string-append output-directory name-string ".data")
                           read))))
  (my-write (string-append output-directory name-string ".ss")
            `(module ,name (lib "ml.scm" "lang")
               (provide ,(make-str-name name))
               (require ,(string-append name-string "-sig.ss")
                        ,@(map (lambda (id)
                                 (string-append (symbol->string id) ".ss"))
                               requires))
               ,@(improve code))))
