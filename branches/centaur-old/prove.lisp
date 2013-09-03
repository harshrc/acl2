; ACL2 Version 4.2 -- A Computational Logic for Applicative Common Lisp
; Copyright (C) 2011  University of Texas at Austin

; This version of ACL2 is a descendent of ACL2 Version 1.9, Copyright
; (C) 1997 Computational Logic, Inc.  See the documentation topic NOTE-2-0.

; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

; Written by:  Matt Kaufmann               and J Strother Moore
; email:       Kaufmann@cs.utexas.edu      and Moore@cs.utexas.edu
; Department of Computer Science
; University of Texas at Austin
; Austin, TX 78701 U.S.A.

(in-package "ACL2")

; Section:  PREPROCESS-CLAUSE

; The preprocessor is the first clause processor in the waterfall when
; we enter from prove.  It contains a simple term rewriter that expands
; certain "abbreviations" and a gentle clausifier.

; We first develop the simple rewriter, called expand-abbreviations.

; Rockwell Addition: We are now concerned with lambdas, where we
; didn't used to treat them differently.  This extra argument will
; show up in several places during a compare-windows.

(mutual-recursion

(defun abbreviationp1 (lambda-flg vars term2)

; This function returns t if term2 is not an abbreviation of term1
; (where vars is the bag of vars in term1).  Otherwise, it returns the
; excess vars of vars.  If lambda-flg is t we look out for lambdas and
; do not consider something an abbreviation if we see a lambda in it.
; If lambda-flg is nil, we treat lambdas as though they were function
; symbols.

  (cond ((variablep term2)
         (cond ((null vars) t) (t (cdr vars))))
        ((fquotep term2) vars)
        ((and lambda-flg
              (flambda-applicationp term2))
         t)
        ((member-eq (ffn-symb term2) '(if not implies)) t)
        (t (abbreviationp1-lst lambda-flg vars (fargs term2)))))

(defun abbreviationp1-lst (lambda-flg vars lst)
  (cond ((null lst) vars)
        (t (let ((vars1 (abbreviationp1 lambda-flg vars (car lst))))
             (cond ((eq vars1 t) t)
                   (t (abbreviationp1-lst lambda-flg vars1 (cdr lst))))))))

)

(defun abbreviationp (lambda-flg vars term2)

; Consider the :REWRITE rule generated from (equal term1 term2).  We
; say such a rule is an "abbreviation" if term2 contains no more
; variable occurrences than term1 and term2 does not call the
; functions IF, NOT or IMPLIES or (if lambda-flg is t) any LAMBDA.
; Vars, above, is the bag of vars from term1.  We return non-nil iff
; (equal term1 term2) is an abbreviation.

  (not (eq (abbreviationp1 lambda-flg vars term2) t)))

(mutual-recursion

(defun all-vars-bag (term ans)
  (cond ((variablep term) (cons term ans))
        ((fquotep term) ans)
        (t (all-vars-bag-lst (fargs term) ans))))

(defun all-vars-bag-lst (lst ans)
  (cond ((null lst) ans)
        (t (all-vars-bag-lst (cdr lst)
                             (all-vars-bag (car lst) ans)))))
)

(defun find-abbreviation-lemma (term geneqv lemmas ens wrld)

; Term is a function application, geneqv is a generated equivalence
; relation and lemmas is the 'lemmas property of the function symbol
; of term.  We find the first (enabled) abbreviation lemma that
; rewrites term maintaining geneqv.  A lemma is an abbreviation if it
; is not a meta-lemma, has no hypotheses, has no loop-stopper, and has
; an abbreviationp for the conclusion.

; If we win we return t, the rune of the :CONGRUENCE rule used, the
; lemma, and the unify-subst.  Otherwise we return four nils.

  (cond ((null lemmas) (mv nil nil nil nil))
        ((and (enabled-numep (access rewrite-rule (car lemmas) :nume) ens)
              (eq (access rewrite-rule (car lemmas) :subclass) 'abbreviation)
              (geneqv-refinementp (access rewrite-rule (car lemmas) :equiv)
                                 geneqv
                                 wrld))
         (mv-let
             (wonp unify-subst)
           (one-way-unify (access rewrite-rule (car lemmas) :lhs) term)
           (cond (wonp (mv t
                           (geneqv-refinementp
                            (access rewrite-rule (car lemmas) :equiv)
                            geneqv
                            wrld)
                           (car lemmas)
                           unify-subst))
                 (t (find-abbreviation-lemma term geneqv (cdr lemmas)
                                             ens wrld)))))
        (t (find-abbreviation-lemma term geneqv (cdr lemmas)
                                    ens wrld))))

(mutual-recursion

(defun expand-abbreviations-with-lemma (term geneqv
                                             fns-to-be-ignored-by-rewrite
                                             rdepth step-limit ens wrld state
                                             ttree)
  (mv-let
    (wonp cr-rune lemma unify-subst)
    (find-abbreviation-lemma term geneqv
                             (getprop (ffn-symb term) 'lemmas nil
                                      'current-acl2-world wrld)
                             ens
                             wrld)
    (cond
     (wonp
      (with-accumulated-persistence
       (access rewrite-rule lemma :rune)
       ((the (signed-byte 30) step-limit) term ttree)
       t
       (expand-abbreviations
        (access rewrite-rule lemma :rhs)
        unify-subst
        geneqv
        fns-to-be-ignored-by-rewrite
        (adjust-rdepth rdepth) step-limit ens wrld state
        (push-lemma cr-rune
                    (push-lemma (access rewrite-rule lemma :rune)
                                ttree)))))
     (t (mv step-limit term ttree)))))

(defun expand-abbreviations (term alist geneqv fns-to-be-ignored-by-rewrite
                                  rdepth step-limit ens wrld state ttree)

; This function is essentially like rewrite but is more restrictive in
; its use of rules.  We rewrite term/alist maintaining geneqv and
; avoiding the expansion or application of lemmas to terms whose fns
; are in fns-to-be-ignored-by-rewrite.  We return a new term and a
; ttree (accumulated onto our argument) describing the rewrite.  We
; only apply "abbreviations" which means we expand lambda applications
; and non-rec fns provided they do not duplicate arguments or
; introduce IFs, etc. (see abbreviationp), and we apply those
; unconditional :REWRITE rules with the same property.

; It used to be written:

;  Note: In a break with Nqthm and the first four versions of ACL2, in
;  Version 1.5 we also expand IMPLIES terms here.  In fact, we expand
;  several members of *expandable-boot-strap-non-rec-fns* here, and
;  IFF.  The impetus for this decision was the forcing of impossible
;  goals by simplify-clause.  As of this writing, we have just added
;  the idea of forcing rounds and the concommitant notion that forced
;  hypotheses are proved under the type-alist extant at the time of the
;  force.  But if the simplifer sees IMPLIES terms and rewrites their
;  arguments, it does not augment the context, e.g., in (IMPLIES hyps
;  concl) concl is rewritten without assuming hyps and thus assumptions
;  forced in concl are context free and often impossible to prove.  Now
;  while the user might hide propositional structure in other functions
;  and thus still suffer this failure mode, IMPLIES is the most common
;  one and by opening it now we make our context clearer.  See the note
;  below for the reason we expand other
;  *expandable-boot-strap-non-rec-fns*.
  
; This is no longer true.  We now expand the IMPLIES from the original
; theorem in preprocess-clause before expand-abbreviations is called,
; and do not expand any others here.  These changes in the handling of
; IMPLIES (as well as several others) are caused by the introduction
; of assume-true-false-if.  See the mini-essay at
; assume-true-false-if.

  (cond
   ((zero-depthp rdepth)
    (rdepth-error
     (mv step-limit term ttree)
     t))
   ((time-limit5-reached-p ; nil, or throws
     "Out of time in preprocess (expand-abbreviations).")
    (mv step-limit nil nil))
   (t
    (let ((step-limit (decrement-step-limit step-limit wrld)))
      (cond
       ((variablep term)
        (let ((temp (assoc-eq term alist)))
          (cond (temp (mv step-limit (cdr temp) ttree))
                (t (mv step-limit term ttree)))))
       ((fquotep term) (mv step-limit term ttree))
       ((and (eq (ffn-symb term) 'return-last)

; We avoid special treatment for return-last when the first argument is progn,
; since the user may have intended the first argument to be rewritten in that
; case; consider for example (prog2$ (cw ...) ...).  But it is useful in the
; other cases, in particular for calls of return-last generated by calls of
; mbe, to avoid spending time simplifying the next-to-last argument.

             (not (equal (fargn term 1) ''progn)))
        (expand-abbreviations (fargn term 3)
                              alist geneqv fns-to-be-ignored-by-rewrite rdepth
                              step-limit ens wrld state
                              (push-lemma
                               (fn-rune-nume 'return-last nil nil wrld)
                               ttree)))
       ((eq (ffn-symb term) 'hide)
        (mv step-limit
            (sublis-var alist term)
            ttree))
       (t 
        (sl-let
         (expanded-args ttree)
         (expand-abbreviations-lst (fargs term)
                                   alist
                                   (geneqv-lst (ffn-symb term) geneqv ens wrld)
                                   fns-to-be-ignored-by-rewrite
                                   (adjust-rdepth rdepth) step-limit
                                   ens wrld state ttree)
         (let* ((fn (ffn-symb term))
                (term (cons-term fn expanded-args)))

; If term does not collapse to a constant, fn is still its ffn-symb.

           (cond
            ((fquotep term)

; Term collapsed to a constant.  But it wasn't a constant before, and so
; it collapsed because cons-term executed fn on constants.  So we record
; a use of the executable counterpart.

             (mv step-limit
                 term
                 (push-lemma (fn-rune-nume fn nil t wrld) ttree)))
            ((member-equal fn fns-to-be-ignored-by-rewrite)
             (mv step-limit (cons-term fn expanded-args) ttree))
            ((and (all-quoteps expanded-args)
                  (enabled-xfnp fn ens wrld)
                  (or (flambda-applicationp term)
                      (not (getprop fn 'constrainedp nil
                                    'current-acl2-world wrld))))
             (cond ((flambda-applicationp term)
                    (expand-abbreviations
                     (lambda-body fn)
                     (pairlis$ (lambda-formals fn) expanded-args)
                     geneqv
                     fns-to-be-ignored-by-rewrite
                     (adjust-rdepth rdepth) step-limit ens wrld state ttree))
                   ((programp fn wrld)

; Why is the above test here?  We do not allow :program mode fns in theorems.
; However, the prover can be called during definitions, and in particular we
; wind up with the call (SYMBOL-BTREEP NIL) when trying to admit the following
; definition.

;  (defun symbol-btreep (x)
;    (if x
;        (and (true-listp x)
;             (symbolp (car x))
;             (symbol-btreep (caddr x))
;             (symbol-btreep (cdddr x)))
;      t))

                    (mv step-limit (cons-term fn expanded-args) ttree))
                   (t
                    (mv-let
                     (erp val latches)
                     (pstk
                      (ev-fncall fn (strip-cadrs expanded-args) state nil t
                                 nil))
                     (declare (ignore latches))
                     (cond
                      (erp

; We following a suggestion from Matt Wilding and attempt to simplify the term
; before applying HIDE.

                       (let ((new-term1 (cons-term fn expanded-args)))
                         (sl-let (new-term2 ttree)
                                 (expand-abbreviations-with-lemma
                                  new-term1 geneqv fns-to-be-ignored-by-rewrite
                                  rdepth step-limit ens wrld state ttree)
                                 (cond
                                  ((equal new-term2 new-term1)
                                   (mv step-limit
                                       (mcons-term* 'hide new-term1)
                                       (push-lemma (fn-rune-nume 'hide nil nil wrld)
                                                   ttree)))
                                  (t (mv step-limit new-term2 ttree))))))
                      (t (mv step-limit
                             (kwote val)
                             (push-lemma (fn-rune-nume fn nil t wrld)
                                         ttree))))))))
            ((flambdap fn)
             (cond ((abbreviationp nil
                                   (lambda-formals fn)
                                   (lambda-body fn))
                    (expand-abbreviations
                     (lambda-body fn)
                     (pairlis$ (lambda-formals fn) expanded-args)
                     geneqv
                     fns-to-be-ignored-by-rewrite
                     (adjust-rdepth rdepth) step-limit ens wrld state ttree))
                   (t

; Once upon a time (well into v1-9) we just returned (mv term ttree)
; here.  But then Jun Sawada pointed out some problems with his proofs
; of some theorems of the form (let (...) (implies (and ...)  ...)).
; The problem was that the implies was not getting expanded (because
; the let turns into a lambda and the implication in the body is not
; an abbreviationp, as checked above).  So we decided that, in such
; cases, we would actually expand the abbreviations in the body
; without expanding the lambda itself, as we do below.  This in turn
; often allows the lambda to expand via the following mechanism.
; Preprocess-clause calls expand-abbreviations and it expands the
; implies into IFs in the body without opening the lambda.  But then
; preprocess-clause calls clausify-input which does another
; expand-abbreviations and this time the expansion is allowed.  We do
; not imagine that this change will adversely affect proofs, but if
; so, well, the old code is shown on the first line of this comment.
                 
                    (sl-let (body ttree)
                            (expand-abbreviations
                             (lambda-body fn)
                             nil
                             geneqv
                             fns-to-be-ignored-by-rewrite
                             (adjust-rdepth rdepth) step-limit ens wrld state
                             ttree)

; Rockwell Addition: 

; Once upon another time (through v2-5) we returned the fcons-term
; shown in the t clause below.  But Rockwell proofs indicate that it
; is better to eagerly expand this lambda if the new body would make
; it an abbreviation.

                            (cond
                             ((abbreviationp nil
                                             (lambda-formals fn)
                                             body)
                              (expand-abbreviations
                               body
                               (pairlis$ (lambda-formals fn) expanded-args)
                               geneqv
                               fns-to-be-ignored-by-rewrite
                               (adjust-rdepth rdepth) step-limit ens wrld state
                               ttree))
                             (t
                              (mv step-limit
                                  (mcons-term (list 'lambda (lambda-formals fn)
                                                    body)
                                              expanded-args)
                                  ttree)))))))
            ((member-eq fn '(iff synp mv-list return-last wormhole-eval force
                                 case-split double-rewrite))

; The list above is an arbitrary subset of *expandable-boot-strap-non-rec-fns*.
; Once upon a time we used the entire list here, but Bishop Brock complained
; that he did not want EQL opened.  So we have limited the list to just the
; propositional function IFF and the no-ops.

; Note: Once upon a time we did not expand any propositional functions
; here.  Indeed, one might wonder why we do now?  The only place
; expand-abbreviations was called was from within preprocess-clause.
; And there, its output was run through clausify-input and then
; remove-trivial-clauses.  The latter called tautologyp on each clause
; and that, in turn, expanded all the functions above (but discarded
; the expansion except for purposes of determining tautologyhood).
; Thus, there is no real case to make against expanding these guys.
; For sanity, one might wish to keep the list above in sync with
; that in tautologyp, where we say about it: "The list is in fact
; *expandable-boot-strap-non-rec-fns* with NOT deleted and IFF added.
; The main idea here is to include non-rec functions that users
; typically put into the elegant statements of theorems."  But now we
; have deleted IMPLIES from this list, to support the assume-true-false-if
; idea, but we still keep IMPLIES in the list for tautologyp because
; if we can decide it's a tautology by expanding, all the better.

             (with-accumulated-persistence
              (fn-rune-nume fn nil nil wrld)
              ((the (signed-byte 30) step-limit) term ttree)
              t
              (expand-abbreviations (body fn t wrld)
                                    (pairlis$ (formals fn wrld) expanded-args)
                                    geneqv
                                    fns-to-be-ignored-by-rewrite
                                    (adjust-rdepth rdepth)
                                    step-limit ens wrld state
                                    (push-lemma (fn-rune-nume fn nil nil wrld)
                                                ttree))))

; Rockwell Addition:  We are expanding abbreviations.  This is new treatment
; of IF, which didn't used to receive any special notice.

            ((eq fn 'if)
         
; There are no abbreviation (or rewrite) rules hung on IF, so coming out
; here is ok.
         
             (let ((a (car expanded-args))
                   (b (cadr expanded-args))
                   (c (caddr expanded-args)))
               (cond
                ((equal b c) (mv step-limit b ttree))
                ((quotep a)
                 (mv step-limit
                     (if (eq (cadr a) nil) c b)
                     ttree))
                ((and (equal geneqv *geneqv-iff*)
                      (equal b *t*)
                      (or (equal c *nil*)
                          (and (nvariablep c)
                               (not (fquotep c))
                               (eq (ffn-symb c) 'HARD-ERROR))))

; Some users keep HARD-ERROR disabled so that they can figure out
; which guard proof case they are in.  HARD-ERROR is identically nil
; and we would really like to eliminate the IF here.  So we use our
; knowledge that HARD-ERROR is nil even if it is disabled.  We don't
; even put it in the ttree, because for all the user knows this is
; primitive type inference.

                 (mv step-limit a ttree))
                (t (mv step-limit
                       (mcons-term 'if expanded-args)
                       ttree)))))

; Rockwell Addition: New treatment of equal.

            ((and (eq fn 'equal)
                  (equal (car expanded-args) (cadr expanded-args)))
             (mv step-limit *t* ttree))
            (t
             (expand-abbreviations-with-lemma
              term geneqv fns-to-be-ignored-by-rewrite rdepth step-limit ens
              wrld state ttree)))))))))))

(defun expand-abbreviations-lst (lst alist geneqv-lst
                                     fns-to-be-ignored-by-rewrite rdepth
                                     step-limit ens wrld state ttree)
  (cond
   ((null lst) (mv step-limit nil ttree))
   (t (sl-let (term1 new-ttree)
              (expand-abbreviations (car lst) alist
                                    (car geneqv-lst)
                                    fns-to-be-ignored-by-rewrite
                                    rdepth step-limit ens wrld state ttree)
              (sl-let (terms1 new-ttree)
                      (expand-abbreviations-lst (cdr lst) alist
                                                (cdr geneqv-lst)
                                                fns-to-be-ignored-by-rewrite
                                                rdepth step-limit ens wrld
                                                state new-ttree)
                      (mv step-limit (cons term1 terms1) new-ttree))))))

)

(defun and-orp (term bool)

; We return t or nil according to whether term is a disjunction
; (if bool is t) or conjunction (if bool is nil).

  (case-match term
              (('if & c2 c3)
               (if bool
                   (or (equal c2 *t*) (equal c3 *t*))
                 (or (equal c2 *nil*) (equal c3 *nil*))))))

(defun find-and-or-lemma (term bool lemmas ens wrld)

; Term is a function application and lemmas is the 'lemmas property of
; the function symbol of term.  We find the first enabled and-or
; (wrt bool) lemma that rewrites term maintaining iff.

; If we win we return t, the :CONGRUENCE rule name, the lemma, and the
; unify-subst.  Otherwise we return four nils.

  (cond ((null lemmas) (mv nil nil nil nil))
        ((and (enabled-numep (access rewrite-rule (car lemmas) :nume) ens)
              (or (eq (access rewrite-rule (car lemmas) :subclass) 'backchain)
                  (eq (access rewrite-rule (car lemmas) :subclass) 'abbreviation))
              (null (access rewrite-rule (car lemmas) :hyps))
              (null (access rewrite-rule (car lemmas) :heuristic-info))
              (geneqv-refinementp (access rewrite-rule (car lemmas) :equiv)
                                 *geneqv-iff*
                                 wrld)
              (and-orp (access rewrite-rule (car lemmas) :rhs) bool))
         (mv-let
             (wonp unify-subst)
           (one-way-unify (access rewrite-rule (car lemmas) :lhs) term)
           (cond (wonp (mv t
                           (geneqv-refinementp
                            (access rewrite-rule (car lemmas) :equiv)
                            *geneqv-iff*
                            wrld)
                           (car lemmas)
                           unify-subst))
                 (t (find-and-or-lemma term bool (cdr lemmas) ens wrld)))))
        (t (find-and-or-lemma term bool (cdr lemmas) ens wrld))))

(defun expand-and-or (term bool fns-to-be-ignored-by-rewrite ens wrld state
                           ttree step-limit)

; We expand the top-level fn symbol of term provided the expansion
; produces a conjunction -- when bool is nil -- or a disjunction -- when
; bool is t.  We return three values:  wonp, the new term, and a new ttree.
; This fn is a No-Change Loser.

  (cond ((variablep term) (mv step-limit nil term ttree))
        ((fquotep term) (mv step-limit nil term ttree))
        ((member-equal (ffn-symb term) fns-to-be-ignored-by-rewrite)
         (mv step-limit nil term ttree))
        ((flambda-applicationp term)
         (cond ((and-orp (lambda-body (ffn-symb term)) bool)
                (sl-let
                 (term ttree)
                 (expand-abbreviations
                  (subcor-var (lambda-formals (ffn-symb term))
                              (fargs term)
                              (lambda-body (ffn-symb term)))
                  nil
                  *geneqv-iff*
                  fns-to-be-ignored-by-rewrite
                  (rewrite-stack-limit wrld) step-limit ens wrld state ttree)
                 (mv step-limit t term ttree)))
               (t (mv step-limit nil term ttree))))
        (t
         (let ((def-body (def-body (ffn-symb term) wrld)))
           (cond
            ((and def-body
                  (null (access def-body def-body :recursivep))
                  (null (access def-body def-body :hyp))
                  (enabled-numep (access def-body def-body :nume)
                                 ens)
                  (and-orp (access def-body def-body :concl)
                           bool))
             (sl-let
              (term ttree)
              (with-accumulated-persistence
               (access def-body def-body :rune)
               ((the (signed-byte 30) step-limit) term ttree)
               t
               (expand-abbreviations
                (subcor-var (access def-body def-body
                                    :formals)
                            (fargs term)
                            (access def-body def-body :concl))
                nil
                *geneqv-iff*
                fns-to-be-ignored-by-rewrite
                (rewrite-stack-limit wrld)
                step-limit ens wrld state
                (push-lemma? (access def-body def-body :rune)
                             ttree)))
              (mv step-limit t term ttree)))
            (t (mv-let
                (wonp cr-rune lemma unify-subst)
                (find-and-or-lemma
                 term bool
                 (getprop (ffn-symb term) 'lemmas nil
                          'current-acl2-world wrld)
                 ens wrld)
                (cond
                 (wonp
                  (sl-let
                   (term ttree)
                   (with-accumulated-persistence
                    (access rewrite-rule lemma :rune)
                    ((the (signed-byte 30) step-limit) term ttree)
                    t
                    (expand-abbreviations
                     (sublis-var unify-subst
                                 (access rewrite-rule lemma :rhs))
                     nil
                     *geneqv-iff*
                     fns-to-be-ignored-by-rewrite
                     (rewrite-stack-limit wrld)
                     step-limit ens wrld state
                     (push-lemma cr-rune
                                 (push-lemma (access rewrite-rule lemma
                                                     :rune)
                                             ttree))))
                   (mv step-limit t term ttree)))
                 (t (mv step-limit nil term ttree))))))))))

(defun clausify-input1 (term bool fns-to-be-ignored-by-rewrite ens wrld state
                             ttree step-limit)

; We return two things, a clause and a ttree.  If bool is t, the
; (disjunction of the literals in the) clause is equivalent to term.
; If bool is nil, the clause is equivalent to the negation of term.
; This function opens up some nonrec fns and applies some rewrite
; rules.  The final ttree contains the symbols and rules used.

  (cond
   ((equal term (if bool *nil* *t*)) (mv step-limit nil ttree))
   ((and (nvariablep term)
         (not (fquotep term))
         (eq (ffn-symb term) 'if))
    (let ((t1 (fargn term 1))
          (t2 (fargn term 2))
          (t3 (fargn term 3)))
      (cond
       (bool
        (cond
         ((equal t3 *t*)
          (sl-let (cl1 ttree)
                  (clausify-input1 t1 nil
                                   fns-to-be-ignored-by-rewrite
                                   ens wrld state ttree step-limit)
                  (sl-let (cl2 ttree)
                          (clausify-input1 t2 t
                                           fns-to-be-ignored-by-rewrite
                                           ens wrld state ttree step-limit)
                          (mv step-limit (disjoin-clauses cl1 cl2) ttree))))
         ((equal t2 *t*)
          (sl-let (cl1 ttree)
                  (clausify-input1 t1 t
                                   fns-to-be-ignored-by-rewrite
                                   ens wrld state ttree step-limit)
                  (sl-let (cl2 ttree)
                          (clausify-input1 t3 t
                                           fns-to-be-ignored-by-rewrite
                                           ens wrld state ttree step-limit)
                          (mv step-limit (disjoin-clauses cl1 cl2) ttree))))
         (t (mv step-limit (list term) ttree))))
       ((equal t3 *nil*)
        (sl-let (cl1 ttree)
                (clausify-input1 t1 nil
                                 fns-to-be-ignored-by-rewrite
                                 ens wrld state ttree step-limit)
                (sl-let (cl2 ttree)
                        (clausify-input1 t2 nil
                                         fns-to-be-ignored-by-rewrite
                                         ens wrld state ttree step-limit)
                        (mv step-limit (disjoin-clauses cl1 cl2) ttree))))
       ((equal t2 *nil*)
        (sl-let (cl1 ttree)
                (clausify-input1 t1 t
                                 fns-to-be-ignored-by-rewrite
                                 ens wrld state ttree step-limit)
                (sl-let (cl2 ttree)
                        (clausify-input1 t3 nil
                                         fns-to-be-ignored-by-rewrite
                                         ens wrld state ttree step-limit)
                        (mv step-limit (disjoin-clauses cl1 cl2) ttree))))
       (t (mv step-limit (list (dumb-negate-lit term)) ttree)))))
   (t (sl-let (wonp term ttree)
              (expand-and-or term bool fns-to-be-ignored-by-rewrite
                             ens wrld state ttree step-limit)
              (cond (wonp
                     (clausify-input1 term bool fns-to-be-ignored-by-rewrite
                                      ens wrld state ttree step-limit))
                    (bool (mv step-limit (list term) ttree))
                    (t (mv step-limit
                           (list (dumb-negate-lit term))
                           ttree)))))))

(defun clausify-input1-lst (lst fns-to-be-ignored-by-rewrite ens wrld state
                                ttree step-limit)

; This function is really a subroutine of clausify-input.  It just
; applies clausify-input1 to every element of lst, accumulating the ttrees.
; It uses bool=t.

  (cond ((null lst) (mv step-limit nil ttree))
        (t (sl-let (clause ttree)
                   (clausify-input1 (car lst) t fns-to-be-ignored-by-rewrite
                                    ens wrld state ttree step-limit)
                   (sl-let (clauses ttree)
                           (clausify-input1-lst (cdr lst)
                                                fns-to-be-ignored-by-rewrite
                                                ens wrld state ttree
                                                step-limit)
                           (mv step-limit
                               (conjoin-clause-to-clause-set clause clauses)
                               ttree))))))

(defun clausify-input (term fns-to-be-ignored-by-rewrite ens wrld state ttree
                            step-limit)

; This function converts term to a set of clauses, expanding some
; non-rec functions when they produce results of the desired parity
; (i.e., we expand AND-like functions in the hypotheses and OR-like
; functions in the conclusion.)  AND and OR themselves are, of course,
; already expanded into IFs, but we will expand other functions when
; they generate the desired IF structure.  We also apply :REWRITE rules
; deemed appropriate.  We return two results, the set of clauses and a
; ttree documenting the expansions.

  (sl-let (neg-clause ttree)
          (clausify-input1 term nil fns-to-be-ignored-by-rewrite ens
                           wrld state ttree step-limit)

; neg-clause is a clause that is equivalent to the negation of term.
; That is, if the literals of neg-clause are lit1, ..., litn, then
; (or lit1 ... litn) <-> (not term).  Therefore, term is the negation
; of the clause, i.e., (and (not lit1) ... (not litn)).  We will
; form a clause from each (not lit1) and return the set of clauses,
; implicitly conjoined.

          (clausify-input1-lst (dumb-negate-lit-lst neg-clause)
                               fns-to-be-ignored-by-rewrite
                               ens wrld state ttree step-limit)))

(defun expand-some-non-rec-fns-in-clauses (fns clauses wrld)

; Warning: fns should be a subset of functions that

; This function expands the non-rec fns listed in fns in each of the clauses
; in clauses.  It then throws out of the set any trivial clause, i.e.,
; tautologies.  It does not normalize the expanded terms but just leaves
; the expanded bodies in situ.  See the comment in preprocess-clause.

  (cond
   ((null clauses) nil)
   (t (let ((cl (expand-some-non-rec-fns-lst fns (car clauses) wrld)))
        (cond
         ((trivial-clause-p cl wrld)
          (expand-some-non-rec-fns-in-clauses fns (cdr clauses) wrld))
         (t (cons cl
                  (expand-some-non-rec-fns-in-clauses fns (cdr clauses)
                                                      wrld))))))))

(defun no-op-histp (hist)

; We say a history, hist, is a "no-op history" if it is empty or its most
; recent entry is a to-be-hidden preprocess-clause or apply-top-hints-clause
; (possibly followed by a settled-down-clause).

  (or (null hist)
      (and hist
           (member-eq (access history-entry (car hist) :processor)
                      '(apply-top-hints-clause preprocess-clause))
           (tag-tree-occur 'hidden-clause
                           t
                           (access history-entry (car hist) :ttree)))
      (and hist
           (eq (access history-entry (car hist) :processor)
               'settled-down-clause)
           (cdr hist)
           (member-eq (access history-entry (cadr hist) :processor)
                      '(apply-top-hints-clause preprocess-clause))
           (tag-tree-occur 'hidden-clause
                           t
                           (access history-entry (cadr hist) :ttree)))))

(mutual-recursion

; This pair of functions is copied from expand-abbreviations and
; heavily modified.  The idea implemented by the caller of this
; function is to expand all the IMPLIES terms in the final literal of
; the goal clause.  This pair of functions actually implements that
; expansion.  One might think to use expand-some-non-rec-fns with
; first argument '(IMPLIES).  But this function is different in two
; respects.  First, it respects HIDE.  Second, it expands the IMPLIES
; inside of lambda bodies.  The basic idea is to mimic what
; expand-abbreviations used to do, before we added the
; assume-true-false-if idea.

(defun expand-any-final-implies1 (term wrld)
  (cond
   ((variablep term)
    term)
   ((fquotep term)
    term)
   ((eq (ffn-symb term) 'hide)
    term)
   (t
    (let ((expanded-args (expand-any-final-implies1-lst (fargs term)
                                                        wrld)))
      (let* ((fn (ffn-symb term))
             (term (cons-term fn expanded-args)))
        (cond ((flambdap fn)
               (let ((body (expand-any-final-implies1 (lambda-body fn)
                                                      wrld)))

; Note: We could use a make-lambda-application here, but if the
; original lambda used all of its variables then so does the new one,
; because IMPLIES uses all of its variables and we're not doing any
; simplification.  This remark is not soundness related; there is no
; danger of introducing new variables, only the inefficiency of
; keeping a big actual which is actually not used.

                 (fcons-term (make-lambda (lambda-formals fn) body)
                             expanded-args)))
              ((eq fn 'IMPLIES)
               (subcor-var (formals 'implies wrld)
                           expanded-args
                           (body 'implies t wrld)))
              (t term)))))))

(defun expand-any-final-implies1-lst (term-lst wrld)
  (cond ((null term-lst)
         nil)
        (t
         (cons (expand-any-final-implies1 (car term-lst) wrld)
               (expand-any-final-implies1-lst (cdr term-lst) wrld)))))

 )

(defun expand-any-final-implies (cl wrld)

; Cl is a clause (a list of ACL2 terms representing a goal) about to
; enter preprocessing.  If the final term contains an 'IMPLIES, we
; expand those IMPLIES here.  This change in the handling of IMPLIES
; (as well as several others) is caused by the introduction of
; assume-true-false-if.  See the mini-essay at assume-true-false-if.

; Note that we fail to report the fact that we used the definition
; of IMPLIES.

; Note also that we do not use expand-some-non-rec-fns here.  We want
; to preserve the meaning of 'HIDE and expand an 'IMPLIES inside of
; a lambda.
  
  (cond ((null cl)  ; This should not happen.
         nil)
        ((null (cdr cl))
         (list (expand-any-final-implies1 (car cl) wrld)))
        (t
         (cons (car cl)
               (expand-any-final-implies (cdr cl) wrld)))))


(defun preprocess-clause (cl hist pspv wrld state step-limit)

; This is the first "real" clause processor (after a little remembered
; apply-top-hints-clause) in the waterfall.  Its arguments and
; values are the standard ones.  We expand abbreviations and clausify
; the clause cl.  For mainly historic reasons, expand-abbreviations
; and clausify-input operate on terms.  Thus, our first move is to
; convert cl into a term.

  (let ((rcnst (access prove-spec-var pspv :rewrite-constant)))
    (mv-let
     (built-in-clausep ttree)
     (cond
      ((or (eq (car (car hist)) 'simplify-clause)
           (eq (car (car hist)) 'settled-down-clause))

; If the hist shows that cl has just come from simplification, there is no
; need to check that it is built in, because the simplifier does that.

       (mv nil nil))
      (t
       (built-in-clausep 'preprocess-clause
                         cl
                         (access rewrite-constant
                                 rcnst
                                 :current-enabled-structure)
                         (access rewrite-constant
                                 rcnst
                                 :oncep-override)
                         wrld
                         state)))

; Ttree is known to be 'assumption free.

     (cond
      (built-in-clausep
       (mv step-limit 'hit nil ttree pspv))
      (t

; Here is where we expand the "original" IMPLIES in the conclusion but
; leave any IMPLIES in the hypotheses.  These IMPLIES are thought to
; have been introduced by :USE hints.

       (let ((term (disjoin (expand-any-final-implies cl wrld))))
         (sl-let (term ttree)
                 (expand-abbreviations term nil
                                       *geneqv-iff*
                                       (access rewrite-constant
                                               rcnst
                                               :fns-to-be-ignored-by-rewrite)
                                       (rewrite-stack-limit wrld)
                                       step-limit
                                       (access rewrite-constant
                                               rcnst
                                               :current-enabled-structure)
                                       wrld state nil)
                 (sl-let (clauses ttree)
                         (clausify-input term
                                         (access rewrite-constant
                                                 (access prove-spec-var
                                                         pspv
                                                         :rewrite-constant)
                                                 :fns-to-be-ignored-by-rewrite)
                                         (access rewrite-constant
                                                 rcnst
                                                 :current-enabled-structure)
                                         wrld
                                         state
                                         ttree
                                         step-limit)
;;;                         (let ((clauses
;;;                                (expand-some-non-rec-fns-in-clauses
;;;                                 '(iff implies)
;;;                                 clauses
;;;                                 wrld)))
                         
; Previous to Version_2.6 we had written:

; ; Note: Once upon a time (in Version 1.5) we called "clausify-clause-set" here.
; ; That function called clausify on each element of clauses and unioned the
; ; results together, in the process naturally deleting tautologies as does
; ; expand-some-non-rec-fns-in-clauses above.  But Version 1.5 caused Bishop a
; ; lot of pain because many theorems would explode into case analyses, each of
; ; which was then dispatched by simplification.  The reason we used a full-blown
; ; clausify in Version 1.5 was that in was also into that version that we
; ; introduced forcing rounds and the liberal use of force-flg = t.  But if we
; ; are to force that way, we must really get all of our hypotheses out into the
; ; open so that they can contribute to the type-alist stored in each assumption.
; ; For example, in Version 1.4 the concl of (IMPLIES hyps concl) was rewritten
; ; first without the hyps being manifest in the type-alist since IMPLIES is a
; ; function.  Not until the IMPLIES was opened did the hyps become "governers"
; ; in this sense.  In Version 1.5 we decided to throw caution to the wind and
; ; just clausify the clausified input.  Well, it bit us as mentioned above and
; ; we are now backing off to simply expanding the non-rec fns that might
; ; contribute hyps.  But we leave the expansions in place rather than normalize
; ; them out so that simplification has one shot on a small set (usually
; ; singleton set) of clauses.

; But the comment above is now irrelevant to the current situation.
; Before commenting on the current situation, however, we point out that
; in (admittedly light) testing the original call to 
; expand-some-non-rec-fns-in-clauses in its original context acted as 
; the identity.  This seems reasonable because 'iff and 'implies were
; expanded in expand-abbreviations.

; We now expand the 'implies from the original theorem (but not the
; implies from a :use hint) in the call to expand-any-final-implies.
; This performs the expansion whose motivations are mentioned in the
; old comments above, but does not interfere with the conclusions
; of a :use hint.  See the mini-essay

; Mini-Essay on Assume-true-false-if and Implies
; or
; How Strengthening One Part of a Theorem Prover Can Weaken the Whole.

; in type-set-b for more details on this latter criterion.

                         (cond
                          ((equal clauses (list cl))

; In this case, preprocess-clause has made no changes to the clause.

                           (mv step-limit 'miss nil nil nil))
                          ((and (consp clauses)
                                (null (cdr clauses))
                                (no-op-histp hist)
                                (equal (prettyify-clause
                                        (car clauses)
                                        (let*-abstractionp state)
                                        wrld)
                                       (access prove-spec-var pspv
                                               :displayed-goal)))

; In this case preprocess-clause has produced a singleton set of
; clauses whose only element will be displayed exactly like what the
; user thinks is the input to prove.  For example, the user might have
; invoked defthm on (implies p q) and preprocess has managed to to
; produce the singleton set of clauses containing {(not p) q}.  This
; is a valuable step in the proof of course.  However, users complain
; when we report that (IMPLIES P Q) -- the displayed goal -- is
; reduced to (IMPLIES P Q) -- the prettyification of the output.

; We therefore take special steps to hide this transformation from the
; user without changing the flow of control through the waterfall.  In
; particular, we will insert into the ttree the tag
; 'hidden-clause with (irrelevant) value t.  In subsequent places
; where we print explanations and clauses to the user we will look for
; this tag.

                           (mv step-limit
                               'hit
                               clauses
                               (add-to-tag-tree
                                'hidden-clause t ttree)
                               pspv))
                          (t (mv step-limit
                                 'hit
                                 clauses
                                 ttree
                                 pspv)))))))))))

; And here is the function that reports on a successful preprocessing.

(defun tilde-*-preprocess-phrase (ttree)

; This function is like tilde-*-simp-phrase but knows that ttree was
; constructed by preprocess-clause and hence is based on abbreviation
; expansion rather than full-fledged rewriting.

; Warning:  The function apply-top-hints-clause-msg1 knows
; that if the (car (cddddr &)) of the result is nil then nothing but
; case analysis was done!

  (mv-let (message-lst char-alist)
          (tilde-*-simp-phrase1
           (extract-and-classify-lemmas ttree '(implies not iff) nil nil)

; Note: The third argument to extract-and-classify-lemmas is the list
; of forced runes, which we assume to be nil in preprocessing.  If
; this changes, see the comment in fertilize-clause-msg1.

           t)
          (list* "case analysis"
                 "~@*"
                 "~@* and "
                 "~@*, "
                 message-lst
                 char-alist)))

(defun tilde-*-raw-preprocess-phrase (ttree punct)

; See tilde-*-preprocess-phrase.  Here we print for a non-nil value of state
; global 'raw-proof-format.

  (let ((runes (all-runes-in-ttree ttree nil)))
    (mv-let (message-lst char-alist)
            (tilde-*-raw-simp-phrase1
             runes
             nil ; forced-runes
             punct
             '(implies not iff) ; ignore-lst
             "" ; phrase
             nil)
            (list* (concatenate 'string "case analysis"
                                (case punct
                                  (#\, ",")
                                  (#\. ".")
                                  (otherwise "")))
                   "~@*"
                   "~@* and "
                   "~@*, "
                   message-lst
                   char-alist))))

(defun preprocess-clause-msg1 (signal clauses ttree pspv state)

; This function is one of the waterfall-msg subroutines.  It has the
; standard arguments of all such functions: the signal, clauses, ttree
; and pspv produced by the given processor, in this case
; preprocess-clause.  It produces the report for this step.

  (declare (ignore signal pspv))
  (let ((raw-proof-format (f-get-global 'raw-proof-format state)))
    (cond ((tag-tree-occur 'hidden-clause t ttree)

; If this preprocess clause is to be hidden, e.g., because it transforms
; (IMPLIES P Q) to {(NOT P) Q}, we print no message.  Note that this is
; just part of the hiding.  Later in the waterfall, when some other processor
; has successfully hit our output, that output will be printed and we
; need to stop that printing too.

           state)
          ((and raw-proof-format
                (null clauses))
           (fms "But preprocess reduces the conjecture to T, by ~*0~|"
                (list (cons #\0 (tilde-*-raw-preprocess-phrase ttree #\.)))
                (proofs-co state)
                state
                (term-evisc-tuple nil state)))
          ((null clauses)
           (fms "But we reduce the conjecture to T, by ~*0.~|"
                (list (cons #\0 (tilde-*-preprocess-phrase ttree)))
                (proofs-co state)
                state
                (term-evisc-tuple nil state)))
          (raw-proof-format
           (fms "Preprocess reduces the conjecture to ~#1~[~x2~/the ~
                 following~/the following ~n3 conjectures~], by ~*0~|"
                (list (cons #\0 (tilde-*-raw-preprocess-phrase ttree #\.))
                      (cons #\1 (zero-one-or-more clauses))
                      (cons #\2 t)
                      (cons #\3 (length clauses)))
                (proofs-co state)
                state
                (term-evisc-tuple nil state)))
          (t
           (fms "By ~*0 we reduce the conjecture to~#1~[~x2.~/~/ the ~
                 following ~n3 conjectures.~]~|"
                (list (cons #\0 (tilde-*-preprocess-phrase ttree))
                      (cons #\1 (zero-one-or-more clauses))
                      (cons #\2 t)
                      (cons #\3 (length clauses)))
                (proofs-co state)
                state
                (term-evisc-tuple nil state))))))


; Section:  PUSH-CLAUSE and The Pool

; At the opposite end of the waterfall from the preprocessor is push-clause,
; where we actually put a clause into the pool.  We develop it now.

(defun more-than-simplifiedp (hist)

; Return t if hist contains a process besides simplify-clause (and its
; mates settled-down-clause and preprocess-clause), where we don't count 
; certain top-level hints: :OR, or top-level hints that create hidden clauses.

  (cond ((null hist) nil)
        ((member-eq (caar hist) '(settled-down-clause
                                  simplify-clause
                                  preprocess-clause))
         (more-than-simplifiedp (cdr hist)))
        ((eq (caar hist) 'apply-top-hints-clause)
         (if (or (tagged-object 'hidden-clause
                                (access history-entry (car hist) :ttree))
                 (tagged-object ':or
                                (access history-entry (car hist) :ttree)))
             (more-than-simplifiedp (cdr hist))
           t))
        (t t)))

(defun delete-assoc-eq-lst (lst alist)
  (declare (xargs :guard (or (symbol-listp lst)
                             (symbol-alistp alist))))
  (if (consp lst)
      (delete-assoc-eq-lst (cdr lst)
                           (delete-assoc-eq (car lst) alist))
    alist))

(defun delete-assumptions-1 (ttree only-immediatep)

; See comment for delete-assumptions.  This function returns (mv changedp
; new-ttree), where if changedp is nil then new-ttree equals ttree.  The only
; reason for the change from Version_2.6 is efficiency.

  (cond ((null ttree) (mv nil nil))
        ((symbolp (caar ttree))
         (mv-let (changedp new-cdr-ttree)
                 (delete-assumptions-1 (cdr ttree) only-immediatep)
                 (cond ((and (eq (caar ttree) 'assumption)
                             (cond
                              ((eq only-immediatep 'non-nil)
                               (access assumption (cdar ttree) :immediatep))
                              ((eq only-immediatep 'case-split)
                               (eq (access assumption (cdar ttree) :immediatep)
                                   'case-split))
                              ((eq only-immediatep t)
                               (eq (access assumption (cdar ttree) :immediatep)
                                   t))
                              (t t)))
                        (mv t new-cdr-ttree))
                       (changedp
                        (mv t
                            (cons (car ttree) new-cdr-ttree)))
                       (t (mv nil ttree)))))
        (t (mv-let (changedp1 ttree1)
                   (delete-assumptions-1 (car ttree) only-immediatep)
                   (mv-let (changedp2 ttree2)
                           (delete-assumptions-1 (cdr ttree) only-immediatep)
                           (if (or changedp1 changedp2)
                               (mv t (cons-tag-trees ttree1 ttree2))
                             (mv nil ttree)))))))

(defun delete-assumptions (ttree only-immediatep)
  
; We delete the assumptions in ttree.  We give the same interpretation to
; only-immediatep as in collect-assumptions.

  (mv-let (changedp new-ttree)
          (delete-assumptions-1 ttree only-immediatep)
          (declare (ignore changedp))
          new-ttree))

(defun push-clause (cl hist pspv wrld state)

; Roughly speaking, we drop cl into the pool of pspv and return.
; However, we sometimes cause the waterfall to abort further
; processing (either to go straight to induction or to fail) and we
; also sometimes choose to push a different clause into the pool.  We
; even sometimes miss and let the waterfall fall off the end of the
; ledge!  We make this precise in the code below.

; The pool is actually a list of pool-elements and is treated as a
; stack.  The clause-set is a set of clauses and is almost always a
; singleton set.  The exception is when it contains the clausification
; of the user's initial conjecture.

; The expected tags are:

; 'TO-BE-PROVED-BY-INDUCTION - the clause set is to be given to INDUCT
; 'BEING-PROVED-BY-INDUCTION - the clause set has been given to INDUCT and
;                              we are working on its subgoals now.

; Like all clause processors, we return four values: the signal,
; which is either 'hit, 'miss or 'abort, the new set of clauses, in this
; case nil, the ttree for whatever action we take, and the new
; value of pspv (containing the new pool).

; Warning: Generally speaking, this function either 'HITs or 'ABORTs.
; But it is here that we look out for :DO-NOT-INDUCT name hints.  For
; such hints we want to act like a :BY name-clause-id was present for
; the clause.  But we don't know the clause-id and the :BY handling is
; so complicated we don't want to reproduce it.  So what we do instead
; is 'MISS and let the waterfall fall off the ledge to the nil ledge.
; See waterfall0.  This function should NEVER return a 'MISS unless
; there is a :DO-NOT-INDUCT name hint present in the hint-settings,
; since waterfall0 assumes that it falls off the ledge only in that
; case.

  (declare (ignore state wrld))
  (let ((pool (access prove-spec-var pspv :pool))
        (do-not-induct-hint-val
         (cdr (assoc-eq :do-not-induct
                        (access prove-spec-var pspv :hint-settings)))))
    (cond
     ((null cl)

; The empty clause was produced.  Stop the waterfall by aborting.  Produce the
; ttree that expains the abort.  Drop the clause set containing the empty
; clause into the pool so that when we look for the next goal we see it and
; quit.

      (mv 'abort
          nil
          (add-to-tag-tree 'abort-cause 'empty-clause nil)
          (change prove-spec-var pspv
                  :pool (cons (make pool-element
                                    :tag 'TO-BE-PROVED-BY-INDUCTION
                                    :clause-set '(nil)
                                    :hint-settings nil)
                              pool))))
     ((and (or (and (not (access prove-spec-var pspv :otf-flg))
                    (eq do-not-induct-hint-val t))
               (eq do-not-induct-hint-val :otf-flg-override))
           (not (assoc-eq :induct (access prove-spec-var pspv
                                          :hint-settings))))

; We need induction but can't use it.  Stop the waterfall by aborting.  Produce
; the ttree that expains the abort.  Drop the clause set containing the empty
; clause into the pool so that when we look for the next goal we see it and
; quit.  Note that if :otf-flg is specified, then we skip this case because we
; do not want to quit just yet.  We will see the :do-not-induct value again in
; prove-loop1 when we return to the goal we are pushing.

      (mv 'abort
          nil
          (add-to-tag-tree 'abort-cause
                           (if (eq do-not-induct-hint-val :otf-flg-override)
                               'do-not-induct-otf-flg-override
                             'do-not-induct)
                           nil)
          (change prove-spec-var pspv
                  :pool (cons (make pool-element
                                    :tag 'TO-BE-PROVED-BY-INDUCTION
                                    :clause-set '(nil)
                                    :hint-settings nil)
                              pool))))
     ((and (not (access prove-spec-var pspv :otf-flg))
           (not (eq do-not-induct-hint-val :otf))
           (or
            (and (null pool) ;(a)
                 (more-than-simplifiedp hist)
                 (not (assoc-eq :induct (access prove-spec-var pspv
                                                :hint-settings))))
            (and pool ;(b)
                 (not (assoc-eq 'being-proved-by-induction pool))
                 (not (assoc-eq :induct  (access prove-spec-var pspv
                                                 :hint-settings))))))

; We have not been told to press Onward Thru the Fog and

; either (a) this is the first time we've ever pushed anything and we have
; applied processes other than simplification to it and we have not been
; explicitly instructed to induct for this formula, or (b) we have already put
; at least one goal into the pool but we have not yet done our first induction
; and we are not being explicitly instructed to induct for this formula.

; Stop the waterfall by aborting.  Produce the ttree explaining the abort.
; Drop the clausification of the user's input into the pool in place of
; everything else in the pool.

; Note: We once reverted to the output of preprocess-clause in prove.  However,
; preprocess (and clausify-input) applies unconditional :REWRITE rules and we
; want users to be able to type exactly what the system should go into
; induction on.  The theorem that preprocess-clause screwed us on was HACK1.
; It screwed us by distributing * and GCD.

      (mv 'abort
          nil
          (add-to-tag-tree 'abort-cause 'revert nil)
          (change prove-spec-var pspv

; Before Version_2.6 we did not modify the tag-tree here.  The result was that
; assumptions created by forcing before reverting to the original goal still
; generated forcing rounds after the subsequent proof by induction.  When this
; bug was discovered we added code below to use delete-assumptions to remove
; assumptions from the the tag-tree.  Note that we are not modifying the
; 'accumulated-ttree in state, so these assumptions still reside there; but
; since that ttree is only used for reporting rules used and is intended to
; reflect the entire proof attempt, this decision seems reasonable.

; Version_2.6 was released on November 29, 2001.  On January 18, 2002, we
; received email from Francisco J. Martin-Mateos reporting a soundness bug,
; with an example that is included after the definition of push-clause.  The
; problem turned out to be that we did not remove :use and :by tagged values
; from the tag-tree here.  The result was that if the early part of a
; successful proof attempt had involved a :use or :by hint but then the early
; part was thrown away and we reverted to the original goal, the :use or :by
; tagged value remained in the tag-tree.  When the proof ultimately succeeded,
; this tagged value was used to update (global-val
; 'proved-functional-instances-alist (w state)), which records proved
; constraints so that subsequent proofs can avoid proving them again.  But
; because the prover reverted to the original goal rather than taking advantage
; of the :use hint, those constraints were not actually proved in this case and
; might not be valid!

; So, we have decided that rather than remove assumptions and :by/:use tags
; from the :tag-tree of pspv, we would just replace that tag-tree by the empty
; tag tree.  We do not want to get burned by a third such problem!

                  :tag-tree nil
                  :pool (list (make pool-element
                                    :tag 'TO-BE-PROVED-BY-INDUCTION
                                    :clause-set

; At one time we clausified here.  But some experiments suggested that the
; prover can perhaps do better by simply doing its thing on each induction
; goal, starting at the top of the waterfall.  So, now we pass the same clause
; to induction as it would get if there were a hint of the form ("Goal" :induct
; term), where term is the user-supplied-term.

                                    (list (list
                                           (access prove-spec-var pspv
                                                   :user-supplied-term)))

; Below we set the :hint-settings for the input clause, doing exactly what
; find-applicable-hint-settings does.  Unfortunately, we haven't defined that
; function yet.  Fortunately, it's just a simple assoc-equal.  In addition,
; that function goes on to compute a second value we don't need here.  So
; rather than go to the bother of moving its definition up to here we just open
; code the part we need.  We also remove top-level hints that were supposed to
; apply before we got to push-clause.

                                    :hint-settings
                                    (delete-assoc-eq-lst
                                     (cons ':reorder *top-hint-keywords*)

; We could also delete :induct, but we know it's not here!

                                     (cdr
                                      (assoc-equal
                                       *initial-clause-id*
                                       (access prove-spec-var pspv
                                               :orig-hints)))))))))
     ((and do-not-induct-hint-val
           (not (member-eq do-not-induct-hint-val '(t :otf :otf-flg-override)))
           (not (assoc-eq :induct
                          (access prove-spec-var pspv :hint-settings))))

; In this case, we have seen a :DO-NOT-INDUCT name hint (where name isn't t)
; that is not overridden by an :INDUCT hint.  We would like to give this clause
; a :BY.  We can't do it here, as explained above.  So we will 'MISS instead.

      (mv 'miss nil nil nil))
     (t (mv 'hit
            nil
            nil
            (change prove-spec-var pspv
                    :pool
                    (cons
                     (make pool-element
                           :tag 'TO-BE-PROVED-BY-INDUCTION
                           :clause-set (list cl)
                           :hint-settings (access prove-spec-var pspv
                                                  :hint-settings))
                     pool)))))))

; Below is the soundness bug example reported by Francisco J. Martin-Mateos.

; ;;;============================================================================
; 
; ;;;
; ;;; A bug in ACL2 (2.5 and 2.6). Proving "0=1".
; ;;; Francisco J. Martin-Mateos
; ;;; email: Francisco-Jesus.Martin@cs.us.es
; ;;; Dpt. of Computer Science and Artificial Intelligence
; ;;; University of SEVILLE
; ;;;
; ;;;============================================================================
; 
; ;;;   I've found a bug in ACL2 (2.5 and 2.6). The following events prove that
; ;;; "0=1".
; 
; (in-package "ACL2")
; 
; (encapsulate
;  (((g1) => *))
; 
;  (local
;   (defun g1 ()
;     0))
; 
;  (defthm 0=g1
;    (equal 0 (g1))
;    :rule-classes nil))
; 
; (defun g1-lst (lst)
;   (cond ((endp lst) (g1))
;  (t (g1-lst (cdr lst)))))
; 
; (defthm g1-lst=g1
;   (equal (g1-lst lst) (g1)))
; 
; (encapsulate
;  (((f1) => *))
; 
;  (local
;   (defun f1 ()
;     1)))
; 
; (defun f1-lst (lst)
;   (cond ((endp lst) (f1))
;  (t (f1-lst (cdr lst)))))
; 
; (defthm f1-lst=f1
;   (equal (f1-lst lst) (f1))
;   :hints (("Goal"
;     :use (:functional-instance g1-lst=g1
;           (g1 f1)
;           (g1-lst f1-lst)))))
; 
; (defthm 0=f1
;   (equal 0 (f1))
;   :rule-classes nil
;   :hints (("Goal"
;     :use (:functional-instance 0=g1
;           (g1 f1)))))
; 
; (defthm 0=1
;   (equal 0 1)
;   :rule-classes nil
;   :hints (("Goal"
;     :use (:functional-instance 0=f1
;           (f1 (lambda () 1))))))
; 
; ;;;   The theorem F1-LST=F1 is not proved via functional instantiation but it
; ;;; can be proved via induction. So, the constraints generated by the
; ;;; functional instantiation hint has not been proved. But when the theorem
; ;;; 0=F1 is considered, the constraints generated in the functional
; ;;; instantiation hint are bypassed because they ".. have been proved when
; ;;; processing the event F1-LST=F1", and the theorem is proved !!!. Finally,
; ;;; an instance of 0=F1 can be used to prove 0=1.
; 
; ;;;============================================================================

; We now develop the functions for reporting what push-clause did.  Except,
; pool-lst has already been defined, in support of proof-trees.

(defun push-clause-msg1-abort (cl-id ttree pspv state)
  (let ((temp (cdr (tagged-object 'abort-cause ttree)))
        (cl-id-phrase (tilde-@-clause-id-phrase cl-id))
        (gag-mode (gag-mode)))
    (case temp
      (empty-clause
       (if gag-mode
           (msg "A goal of NIL, ~@0, has been generated!  Obviously, the ~
                 proof attempt has failed.~|"
                cl-id-phrase)
         ""))
      ((do-not-induct do-not-induct-otf-flg-override)
       (msg "Normally we would attempt to prove ~@0 by induction.  However, a ~
             :DO-NOT-INDUCT hint was supplied to abort the proof attempt.~|"
            cl-id-phrase
            (if (eq temp 'do-not-induct)
                t
              :otf-flg-override)))
      (otherwise
       (msg "Normally we would attempt to prove ~@0 by induction.  However, ~
             we prefer in this instance to focus on the original input ~
             conjecture rather than this simplified special case.  We ~
             therefore abandon our previous work on this conjecture and ~
             reassign the name ~@1 to the original conjecture.  (See :DOC ~
             otf-flg.)~#2~[~/  [Note:  Thanks again for the hint.]~]~|"
            cl-id-phrase
            (tilde-@-pool-name-phrase
             (access clause-id cl-id :forcing-round)
             (pool-lst
              (cdr (access prove-spec-var pspv
                           :pool))))
            (if (and (not gag-mode)
                     (access prove-spec-var pspv
                             :hint-settings))
                1
              0))))))

(defun push-clause-msg1 (cl-id signal clauses ttree pspv state)

; Push-clause was given a clause and produced a signal and ttree.  We
; are responsible for printing out an explanation of what happened.
; We look at the ttree to determine what happened.  We return state.

  (declare (ignore clauses))
  (cond ((eq signal 'abort)
         (fms "~@0"
              (list (cons #\0 (push-clause-msg1-abort cl-id ttree pspv state)))
              (proofs-co state)
              state
              nil))
        (t
         (fms "Name the formula above ~@0.~|"
              (list (cons #\0 (tilde-@-pool-name-phrase
                               (access clause-id cl-id :forcing-round)
                               (pool-lst
                                (cdr (access prove-spec-var pspv
                                             :pool))))))
              (proofs-co state)
              state
              nil))))

(deflabel otf-flg
  :doc
  ":Doc-Section Miscellaneous

  pushing all the initial subgoals~/

  The value of this flag is normally ~c[nil].  If you want to prevent the
  theorem prover from abandoning its initial work upon pushing the
  second subgoal, set ~c[:otf-flg] to ~c[t].~/

  Suppose you submit a conjecture to the theorem prover and the system
  splits it up into many subgoals.  Any subgoal not proved by other
  methods is eventually set aside for an attempted induction proof.
  But upon setting aside the second such subgoal, the system chickens
  out and decides that rather than prove n>1 subgoals inductively, it
  will abandon its initial work and attempt induction on the
  originally submitted conjecture.  The ~c[:otf-flg] (Onward Thru the Fog)
  allows you to override this chickening out. When ~c[:otf-flg] is ~c[t], the
  system will push all the initial subgoals and proceed to try to
  prove each, independently, by induction.

  Even when you don't expect induction to be used or to succeed,
  setting the ~c[:otf-flg] is a good way to force the system to generate
  and display all the initial subgoals.

  For ~ilc[defthm] and ~ilc[thm], ~c[:otf-flg] is a keyword argument that is a peer to
  ~c[:]~ilc[rule-classes] and ~c[:]~ilc[hints].  It may be supplied as in the following
  examples; also ~pl[defthm].
  ~bv[]
  (thm (my-predicate x y) :rule-classes nil :otf-flg t)

  (defthm append-assoc
    (equal (append (append x y) z)
           (append x (append y z)))
    :hints ((\"Goal\" :induct t))
    :otf-flg t)
  ~ev[]
  The ~c[:otf-flg] may be supplied to ~ilc[defun] via the ~ilc[xargs]
  declare option.  When you supply an ~c[:otf-flg] hint to ~c[defun], the
  flag is effective for the termination proofs and the guard proofs, if
  any.~/")

; Section:  Use and By hints

(defun clause-set-subsumes-1 (init-subsumes-count cl-set1 cl-set2 acc)

; We return t if the first set of clauses subsumes the second in the sense that
; for every member of cl-set2 there exists a member of cl-set1 that subsumes
; it.  We return '? if we don't know (but this can only happen if
; init-subsumes-count is non-nil); see the comment in subsumes.

  (cond ((null cl-set2) acc)
        (t (let ((temp (some-member-subsumes init-subsumes-count
                                             cl-set1 (car cl-set2) nil)))
             (and temp ; thus t or maybe, if init-subsumes-count is non-nil, ?
                  (clause-set-subsumes-1 init-subsumes-count
                                         cl-set1 (cdr cl-set2) temp))))))

(defun clause-set-subsumes (init-subsumes-count cl-set1 cl-set2)

; This function is intended to be identical, as a function, to
; clause-set-subsumes-1 (with acc set to t).  The first two disjuncts are
; optimizations that may often apply.

  (or (equal cl-set1 cl-set2)
      (and cl-set1
           cl-set2
           (null (cdr cl-set2))
           (subsetp-equal (car cl-set1) (car cl-set2)))
      (clause-set-subsumes-1 init-subsumes-count cl-set1 cl-set2 t)))

(defun apply-use-hint-clauses (temp clauses pspv wrld state step-limit)

; Note: There is no apply-use-hint-clause.  We just call this function
; on a singleton list of clauses.

; Temp is the result of assoc-eq :use in a pspv :hint-settings and is
; non-nil.  We discuss its shape below.  But this function applies the
; given :use hint to each clause in clauses and returns (mv 'hit
; new-clauses ttree new-pspv).

; Temp is of the form (:USE lmi-lst (hyp1 ... hypn) constraint-cl k
; event-names new-entries) where each hypi is a theorem and
; constraint-cl is a clause that expresses the conjunction of all k
; constraints.  Lmi-lst is the list of lmis that generated these hyps.
; Constraint-cl is (probably) of the form {(if constr1 (if constr2 ...
; (if constrk t nil)... nil) nil)}.  We add each hypi as a hypothesis
; to each goal clause, cl, and in addition, create one new goal for
; each constraint.  Note that we discard the extended goal clause if
; it is a tautology.  Note too that the constraints generated by the
; production of the hyps are conjoined into a single clause in temp.
; But we hit that constraint-cl with preprocess-clause to pick out its
; (non-tautologial) cases and that code will readily unpack the if
; structure of a typical conjunct.  We remove the :use hint from the
; hint-settings so we don't fire the same :use again on the subgoals.

; We return (mv 'hit new-clauses ttree new-pspv).

; The ttree returned has at most two tags.  The first is :use and has
; ((lmi-lst hyps constraint-cl k event-names new-entries)
; . non-tautp-applications) as its value, where non-tautp-applications
; is the number of non-tautologous clauses we got by adding the hypi
; to each clause.  However, it is possible the :use tag is not
; present: if clauses is nil, we don't report a :use.  The optional
; second tag is the ttree produced by preprocess-clause on the
; constraint-cl.  If the preprocess-clause is to be hidden anyway, we
; ignore its tree (but use its clauses).

  (let* ((hyps (caddr temp))
         (constraint-cl (cadddr temp))
         (new-pspv (change prove-spec-var pspv
                           :hint-settings
                           (remove1-equal temp
                                          (access prove-spec-var
                                                  pspv
                                                  :hint-settings))))
         (A (disjoin-clause-segment-to-clause-set (dumb-negate-lit-lst hyps)
                                                  clauses))
         (non-tautp-applications (length A)))

; In this treatment, the final set of goal clauses will the union of
; sets A and C.  A stands for the "application clauses" (obtained by
; adding the use hyps to each clause) and C stands for the "constraint
; clauses."  Non-tautp-applications is |A|.

    (cond
     ((null clauses)
      
; In this case, there is no point in generating the constraints!  We
; anticipate this happening if the user provides both a :use and a
; :cases hint and the :cases hint (which is applied first) proves the
; goal completely.  If that were to happen, clauses would be output of
; the :cases hint and pspv would be its output pspv, from which the
; :cases had been deleted.  So we just delete the :use hint from that
; pspv and call it quits, without reporting a :use hint at all.

      (mv step-limit 'hit nil nil new-pspv))
     (t
      (sl-let
       (signal C ttree irrel-pspv)
       (preprocess-clause constraint-cl nil pspv wrld state step-limit)
       (declare (ignore irrel-pspv))
       (cond
        ((eq signal 'miss)
         (mv step-limit
             'hit
             (conjoin-clause-sets
              A
              (conjoin-clause-to-clause-set constraint-cl
                                            nil))
             (add-to-tag-tree :use
                              (cons (cdr temp)
                                    non-tautp-applications)
                              nil)
             new-pspv))
        ((or (tag-tree-occur 'hidden-clause
                             t
                             ttree)
             (and C
                  (null (cdr C))
                  (equal (list (prettyify-clause
                                (car C)
                                (let*-abstractionp state)
                                wrld))
                         constraint-cl)))
         (mv step-limit
             'hit
             (conjoin-clause-sets A C)
             (add-to-tag-tree :use
                              (cons (cdr temp)
                                    non-tautp-applications)
                              nil)
             new-pspv))
        (t (mv step-limit
               'hit
               (conjoin-clause-sets A C)
               (add-to-tag-tree :use
                                (cons (cdr temp)
                                      non-tautp-applications)
                                (add-to-tag-tree 'preprocess-ttree
                                                 ttree
                                                 nil))
               new-pspv))))))))

(defun apply-cases-hint-clause (temp cl pspv wrld)

; Temp is the value associated with :cases in a pspv :hint-settings
; and is non-nil.  It is thus of the form (:cases term1 ... termn).
; For each termi we create a new clause by adding its negation to the
; goal clause, cl, and in addition, we create a final goal by adding
; all termi.  As with a :use hint, we remove the :cases hint from the
; hint-settings so that the waterfall doesn't loop!

; We return (mv 'hit new-clauses ttree new-pspv).

  (let ((new-clauses 
         (remove-trivial-clauses
          (conjoin-clause-to-clause-set
           (disjoin-clauses
            (cdr temp)
            cl)
           (split-on-assumptions

; We reverse the term-list so the user can see goals corresponding to the
; order of the terms supplied.

            (dumb-negate-lit-lst (reverse (cdr temp)))
            cl
            nil))
          wrld)))
    (mv 'hit
        new-clauses
        (add-to-tag-tree :cases (cons (cdr temp) new-clauses) nil)
        (change prove-spec-var pspv
                :hint-settings
                (remove1-equal temp
                               (access prove-spec-var
                                       pspv
                                       :hint-settings))))))

(defun term-list-listp (l w)
  (declare (xargs :guard t))
  (if (atom l)
      (equal l nil)
    (and (term-listp (car l) w)
         (term-list-listp (cdr l) w))))

(defun non-term-listp-msg (x w)

; Perhaps ~Y01 should be ~y below.  If someone complains about a large term
; being printed, consider making that change.

  (declare (xargs :guard t))
  (cond
   ((atom x)
    (assert$
     x
     "that fails to satisfy true-listp."))
   ((not (termp (car x) w))
    (msg "that contains the following non-termp (see :DOC term):~|~%  ~Y01"
         (car x)
         nil))
   (t (non-term-listp-msg (cdr x) w))))

(defun non-term-list-listp-msg (l w)

; Perhaps ~Y01 should be ~y below.  If someone complains about a large term
; being printed, consider making that change.

  (declare (xargs :guard t))
  (cond
   ((atom l)
    (assert$
     l
     "which fails to satisfy true-listp."))
   ((not (term-listp (car l) w))
    (msg "which has a member~|~%  ~Y01~|~%~@2"
         (car l)
         nil
         (non-term-listp-msg (car l) w)))
   (t (non-term-list-listp-msg (cdr l) w))))

(defun eval-clause-processor (clause term stobjs-out ctx state)

; Should we do our evaluation in safe-mode?  For a relevant discussion, see the
; comment in protected-eval about safe-mode.

  (revert-world-on-error
   (let ((original-wrld (w state))
         (cl-term (subst-var (kwote clause) 'clause term)))
     (protect-system-state-globals
      (pprogn
       (mv-let
        (erp trans-result state)
        (ev-for-trans-eval cl-term (all-vars cl-term) stobjs-out ctx state

; See chk-evaluator-use-in-rule for a discussion of how we restrict the use of
; evaluators in rules of class :meta or :clause-processor, so that we can use
; aok = t here.

                           t)
        (cond
         (erp (mv (msg "Evaluation failed for the :clause-processor hint.")
                  nil
                  state))
         (t
          (assert$
           (equal (car trans-result) stobjs-out)
           (let* ((result (cdr trans-result))
                  (eval-erp (and (cdr stobjs-out) (car result)))
                  (val (if (cdr stobjs-out) (cadr result) result)))
             (cond ((stringp eval-erp)
                    (mv (msg "~s0" eval-erp) nil state))
                   ((tilde-@p eval-erp) ; a message
                    (mv (msg
                         "Error in clause-processor hint:~|~%  ~@0"
                         eval-erp)
                        nil state))
                   (eval-erp
                    (mv (msg
                         "Error in clause-processor hint:~|~%  ~Y01"
                         term
                         nil)
                        nil state))
                   (t (pprogn (set-w! original-wrld state)
                              (cond ((not (term-list-listp val
                                                           original-wrld))
                                     (mv (msg
                                          "The :CLAUSE-PROCESSOR hint~|~%  ~
                                           ~Y01~%did not evaluate to a list ~
                                           of clauses, but instead to~|~%  ~
                                           ~Y23~%~@4"
                                          term nil
                                          val nil
                                          (non-term-list-listp-msg
                                           val original-wrld))
                                         nil
                                         state))
                                    (t (value val))))))))))))))))

(defun apply-top-hints-clause1 (temp cl-id cl pspv wrld state step-limit)

; See apply-top-hints-clause.  This handles the case that we found a
; hint-setting, temp, for a top hint other than :clause-processor or :or.

  (case (car temp)
    (:use ; temp is a non-nil :use hint.
     (let ((cases-temp
            (assoc-eq :cases
                      (access prove-spec-var pspv :hint-settings))))
       (cond
        ((null cases-temp)
         (apply-use-hint-clauses temp (list cl) pspv wrld state step-limit))
        (t

; In this case, we have both :use and :cases hints.  Our
; interpretation of this is that we split clause cl according to the
; :cases and then apply the :use hint to each case.  By the way, we
; don't have to consider the possibility of our having a :use and :by
; or :bdd.  That is ruled out by translate-hints.

         (mv-let
          (signal cases-clauses cases-ttree cases-pspv)
          (apply-cases-hint-clause cases-temp cl pspv wrld)
          (declare (ignore signal))

; We know the signal is 'HIT.

          (sl-let
           (signal use-clauses use-ttree use-pspv)
           (apply-use-hint-clauses temp
                                   cases-clauses
                                   cases-pspv
                                   wrld state step-limit)
           (declare (ignore signal))

; Despite the names, use-clauses and use-pspv both reflect the work we
; did for cases.  However, use-ttree was built from scratch as was
; cases-ttree and we must combine them.

           (mv step-limit
               'HIT
               use-clauses
               (cons-tag-trees use-ttree cases-ttree)
               use-pspv)))))))
    (:by
      

; If there is a :by hint then it is of one of the two forms (:by .  name) or
; (:by lmi-lst thm constraint-cl k event-names new-entries).  The first form
; indicates that we are to give this clause a bye and let the proof fail late.
; The second form indicates that the clause is supposed to be subsumed by thm,
; viewed as a set of clauses, but that we have to prove constraint-cl to obtain
; thm and that constraint-cl is really a conjunction of k constraints.  Lmi-lst
; is a singleton list containing the lmi that generated this thm-cl.

     (cond
      ((symbolp (cdr temp))

; So this is of the first form, (:by . name).  We want the proof to fail, but
; not now.  So we act as though we proved cl (we hit, produce no new clauses
; and don't change the pspv) but we return a tag-tree containing the tag
; :bye with the value (name . cl).  At the end of the proof we must search
; the tag-tree and see if there are any :byes in it.  If so, the proof failed
; and we should display the named clauses.

       (mv step-limit
           'hit
           nil
           (add-to-tag-tree :bye (cons (cdr temp) cl) nil)
           pspv))
      (t
       (let ((lmi-lst (cadr temp)) ; a singleton list
             (thm (remove-guard-holders

; We often remove guard-holders without tracking their use in the tag-tree.
; Other times we record their use (but not here).  This is analogous to our
; reporting of the use of (:DEFINITION NOT) in some cases but not in others
; (e.g., when we use strip-not).

                   (caddr temp)))
             (constraint-cl (cadddr temp))
             (sr-limit (car (access rewrite-constant
                                    (access prove-spec-var pspv
                                            :rewrite-constant)
                                    :case-split-limitations)))
             (new-pspv
              (change prove-spec-var pspv
                      :hint-settings
                      (remove1-equal temp
                                     (access prove-spec-var
                                             pspv
                                             :hint-settings)))))

; We remove the :by from the hint-settings.  Why do we remove the :by?
; If we don't the subgoals we create from constraint-cl will also see
; the :by!

; We insist that thm-cl-set subsume cl -- more precisely, that cl be
; subsumed by some member of thm-cl-set.

; WARNING: See the warning about the processing in translate-by-hint.

         (let* ((cl (remove-guard-holders-lst cl))
                (easy-winp
                 (if (and cl (null (cdr cl)))
                     (equal (car cl) thm)
                   (equal thm
                          (implicate
                           (conjoin (dumb-negate-lit-lst (butlast cl 1)))
                           (car (last cl))))))
                (cl1 (if (and (not easy-winp)
                              (ffnnamep-lst 'implies cl))
                         (expand-some-non-rec-fns-lst '(implies) cl wrld)
                       cl))
                (cl-set (if (not easy-winp)

; Before Version_2.7 we only called clausify here when (and (null hist) cl1
; (null (cdr cl1))).  But Robert Krug sent an example in which a :by hint was
; given on a subgoal that had been produced from "Goal" by destructor
; elimination.  That subgoal was identical to the theorem given in the :by
; hint, and hence easy-winp is true; but before Version_2.7 we did not look for
; the easy win.  So, what happened was that thm-cl-set was the result of
; clausifying the theorem given in the :by hint, but cl-set was a singleton
; containing cl1, which still has IF terms.

                            (clausify (disjoin cl1) nil t sr-limit)
                          (list cl1)))
                (thm-cl-set (if easy-winp
                                (list (list thm))


; WARNING: Below we process the thm obtained from the lmi.  In particular, we
; expand certain non-rec fns and we clausify it.  For heuristic sanity, the
; processing done here should exactly duplicate that done above for cl-set.
; The reason is that we want it to be the case that if the user gives a :by
; hint that is identical to the goal theorem, the subsumption is guaranteed to
; succeed.  If the processing of the goal theorem is slightly different than
; the processing of the hint, that guarantee is invalid.

                              (clausify (expand-some-non-rec-fns
                                         '(implies) thm wrld)
                                        nil
                                        t
                                        sr-limit)))
                (val (list* (cadr temp) thm-cl-set (cdddr temp)))
                (subsumes (and (not easy-winp) ; otherwise we don't care
                               (clause-set-subsumes nil

; We supply nil just above, rather than (say) *init-subsumes-count*, because
; the user will be able to see that if the subsumption check goes out to lunch
; then it must be because of the :by hint.  For example, it takes 167,997,825
; calls of one-way-unify1 (more than 2^27, not far from the fixnum limit in
; many Lisps) to do the subsumption check for the following, yet in a feasible
; time (26 seconds on Allegro CL 7.0, on a 2.6GH Pentium 4).  So we prefer not
; to set a limit.

;  (defstub p (x) t)
;  (defstub s (x1 x2 x3 x4 x5 x6 x7 x8) t)
;  (defaxiom ax
;    (implies (and (p x1) (p x2) (p x3) (p x4)
;                  (p x5) (p x6) (p x7) (p x8))
;             (s x1 x2 x3 x4 x5 x6 x7 x8))
;    :rule-classes nil)
;  (defthm prop
;    (implies (and (p x1) (p x2) (p x3) (p x4)
;                  (p x5) (p x6) (p x7) (p x8))
;             (s x8 x7 x3 x4 x5 x6 x1 x2))
;    :hints (("Goal" :by ax)))

                                                    thm-cl-set cl-set)))
                (success (or easy-winp subsumes)))

; Before the full-blown subsumption check we ask if the two sets are identical
; and also if they are each singleton sets and the thm-cl-set's clause is a
; subset of the other clause.  These are fast and commonly successful checks.

           (cond
            (success

; Ok!  We won!  To produce constraint-cl as our goal we first
; preprocess it as though it had come down from the top.  See the
; handling of :use hints below for some comments on this.  This code
; was copied from that historically older code.

             (sl-let (signal clauses ttree irrel-pspv)
                     (preprocess-clause constraint-cl nil pspv wrld
                                        state step-limit)
                     (declare (ignore irrel-pspv))
                     (cond ((eq signal 'miss)
                            (mv step-limit
                                'hit
                                (conjoin-clause-to-clause-set
                                 constraint-cl nil)
                                (add-to-tag-tree :by val nil)
                                new-pspv))
                           ((or (tag-tree-occur 'hidden-clause
                                                t
                                                ttree)
                                (and clauses
                                     (null (cdr clauses))
                                     (equal (list
                                             (prettyify-clause
                                              (car clauses)
                                              (let*-abstractionp state)
                                              wrld))
                                            constraint-cl)))

; If preprocessing produced a single clause that prettyifies to the
; clause we had, then act as though it didn't do anything (but use its
; output clause set).  This is akin to the 'hidden-clause
; hack of preprocess-clause, which, however, is intimately tied to the
; displayed-goal input to prove and not to the input to prettyify-
; clause.  We look for the 'hidden-clause tag just in case.

                            (mv step-limit
                                'hit
                                clauses
                                (add-to-tag-tree :by val nil)
                                new-pspv))
                           (t
                            (mv step-limit
                                'hit
                                clauses
                                (add-to-tag-tree
                                 :by val
                                 (add-to-tag-tree 'preprocess-ttree
                                                  ttree
                                                  nil))
                                new-pspv)))))
            (t (mv step-limit
                   'error
                   (msg "When a :by hint is used to supply a lemma-instance ~
                         for a given goal-spec, the formula denoted by the ~
                         lemma-instance must subsume the goal.  This did not ~
                         happen~@1!  The lemma-instance provided was ~x0, ~
                         which denotes the formula ~p2 (when converted to a ~
                         set of clauses and then printed as a formula).  This ~
                         formula was not found to subsume the goal clause, ~
                         ~p3.~|~%Consider a :use hint instead ; see :DOC ~
                         hints." 
                        (car lmi-lst)

; The following is not possible, because we are not putting a limit on the
; number of one-way-unify1 calls in our subsumption check (see above).  But we
; leave this code here in case we change our minds on that.

                        (if (eq subsumes '?)
                            " because our subsumption heuristics were ~
                                   unable to decide the question"
                          "")
                        (untranslate thm t wrld)
                        (prettyify-clause-set cl-set
                                              (let*-abstractionp state)
                                              wrld))
                   nil
                   nil))))))))
    (:cases

; Then there is no :use hint present.  See the comment in *top-hint-keywords*.

     (prepend-step-limit
      4
      (apply-cases-hint-clause temp cl pspv wrld)))
    (:bdd
     (prepend-step-limit
      4
      (bdd-clause (cdr temp) cl-id cl
                  (change prove-spec-var pspv
                          :hint-settings
                          (remove1-equal temp
                                         (access prove-spec-var
                                                 pspv
                                                 :hint-settings)))
                  wrld state)))
    (t (mv step-limit
           (er hard 'apply-top-hints-clause
               "Implementation error: Missing case in apply-top-hints-clause.")
           nil nil nil))))

(defun apply-top-hints-clause (cl-id cl hist pspv wrld ctx state step-limit)

; This is a standard clause processor of the waterfall.  It is odd in that it
; is a no-op unless there is a :use, :by, :cases, :bdd, :clause-processor, or
; :or hint in the :hint-settings of pspv.  If there is, we remove it and apply
; it.  By implementing these hints via this special-purpose processor we can
; take advantage of the waterfall's already-provided mechanisms for handling
; multiple clauses and output.

; We return 5 values.  The fifth is state.  The first is a signal that is
; either 'hit, 'miss, or 'error.  When the signal is 'miss, the next 3 values
; are irrelevant.  When the signal is 'error, the second result is a pair of
; the form (str . alist) which allows us to give our caller an error message to
; print.  In this case, the next two values are irrelevant.  When the signal is
; 'hit, the second result is the list of new clauses, the third is a ttree that
; will become that component of the history-entry for this process, and the
; fourth is the modified pspv.

; We need cl-id passed in so that we can store it in the bddnote, in the case
; of a :bdd hint.

  (declare (ignore hist))
  (let ((temp (first-assoc-eq *top-hint-keywords*
                              (access prove-spec-var pspv
                                      :hint-settings))))
    (cond
     ((null temp) (mv step-limit 'miss nil nil nil state))
     ((eq (car temp) :or)

; If there is an :or hint then it is the only hint present and (in the
; translated form found here) it is of the form (:or . ((user-hint1
; . hint-settings1) ...(user-hintk . hint-settingsk))).  We simply signal an
; or-hit and let the waterfall process the hints.  We remove the :or hint from
; the :hint-settings of the pspv.  (It may be tempting simply to set the
; :hint-settings to nil.  But there may be other :hint-settings, say from a
; :do-not hint on a superior clause id.)

; The value, val, tagged with :or in the ttree is of the form (parent-cl-id NIL
; uhs-lst), where the parent-cl-id is the cl-id of the clause to which this :OR
; hint applies, the uhs-lst is the list of dotted pairs (... (user-hinti
; . hint-settingsi)...) and the NIL signifies that no branches have been
; created.  Eventually we will replace the NIL in the ttree of each branch by
; an integer i indicating which branch.  If that slot is occupied by an integer
; then user-hinti was applied to the corresponding clause.  See
; change-or-hit-history-entry.

      (mv step-limit
          'or-hit
          (list cl)
          (add-to-tag-tree :or
                           (list cl-id nil (cdr temp))
                           nil)
          (change prove-spec-var pspv
                  :hint-settings
                  (delete-assoc-eq :or
                                   (access prove-spec-var pspv
                                           :hint-settings)))
          state))
     ((eq (car temp) :clause-processor) ; special case since state is returned

; Temp is of the form (clause-processor-hint . stobjs-out), as returned by
; translate-clause-processor-hint.

      (mv-let
       (erp new-clauses state)
       (eval-clause-processor cl
                              (access clause-processor-hint (cdr temp) :term)
                              (access clause-processor-hint (cdr temp) :stobjs-out)
                              ctx state)
       (cond (erp (mv step-limit 'error erp nil nil state))
             (t (mv step-limit
                    'hit
                    new-clauses
                    (cond ((and new-clauses
                                (null (cdr new-clauses))
                                (equal (car new-clauses) cl))
                           (add-to-tag-tree 'hidden-clause t nil))
                          (t (add-to-tag-tree
                              :clause-processor
                              (cons (cdr temp) new-clauses)
                              nil)))
                    (change prove-spec-var pspv
                            :hint-settings
                            (remove1-equal temp
                                           (access prove-spec-var
                                                   pspv
                                                   :hint-settings)))
                    state)))))
     (t (sl-let
         (signal clauses ttree new-pspv)
         (apply-top-hints-clause1 temp cl-id cl pspv wrld state step-limit)
         (mv step-limit signal clauses ttree new-pspv state))))))

; We now develop the code for explaining the action taken above.  First we
; arrange to print a phrase describing a list of lmis.

(defun lmi-seed (lmi)

; The "seed" of an lmi is either a symbolic name or else a term.  In
; particular, the seed of a symbolp lmi is the lmi itself, the seed of
; a rune is its base symbol, the seed of a :theorem is the term
; indicated, and the seed of an :instance or :functional-instance is
; obtained recursively from the inner lmi.

; Warning: If this is changed so that runes are returned as seeds, it
; will be necessary to change the use of filter-atoms below.

  (cond ((atom lmi) lmi)
        ((eq (car lmi) :theorem) (cadr lmi))
        ((or (eq (car lmi) :instance)
             (eq (car lmi) :functional-instance))
         (lmi-seed (cadr lmi)))
        (t (base-symbol lmi))))

(defun lmi-techs (lmi)
  (cond
   ((atom lmi) nil)
   ((eq (car lmi) :theorem) nil)
   ((eq (car lmi) :instance)
    (add-to-set-equal "instantiation" (lmi-techs (cadr lmi))))
   ((eq (car lmi) :functional-instance)
    (add-to-set-equal "functional instantiation" (lmi-techs (cadr lmi))))
   (t nil)))

(defun lmi-seed-lst (lmi-lst)
  (cond ((null lmi-lst) nil)
        (t (add-to-set-eq (lmi-seed (car lmi-lst))
                          (lmi-seed-lst (cdr lmi-lst))))))

(defun lmi-techs-lst (lmi-lst)
  (cond ((null lmi-lst) nil)
        (t (union-equal (lmi-techs (car lmi-lst))
                        (lmi-techs-lst (cdr lmi-lst))))))

(defun filter-atoms (flg lst)

; If flg=t we return all the atoms in lst.  If flg=nil we return all
; the non-atoms in lst.

  (cond ((null lst) nil)
        ((eq (atom (car lst)) flg)
         (cons (car lst) (filter-atoms flg (cdr lst))))
        (t (filter-atoms flg (cdr lst)))))

(defun tilde-@-lmi-phrase (lmi-lst k event-names)

; Lmi-lst is a list of lmis.  K is the number of constraints we have to
; establish.  Event-names is a list of names of events that justify the
; omission of certain proof obligations, because they have already been proved
; on behalf of those events.  We return an object suitable for printing via ~@
; that will print the phrase

; can be derived from ~&0 via instantiation and functional
; instantiation, provided we can establish the ~n1 constraints

; when event-names is nil, or else

; can be derived from ~&0 via instantiation and functional instantiation,
; bypassing constraints that have been proved when processing the events ...,
;    [or:  instead of ``the events,'' use ``events including'' when there
;          is at least one unnamed event involved, such as a verify-guards
;          event]
; provided we can establish the remaining ~n1 constraints

; Of course, the phrase is altered appropriately depending on the lmis
; involved.  There are two uses of this phrase.  When :by reports it
; says "As indicated by the hint, this goal is subsumed by ~x0, which
; CAN BE ...".  When :use reports it says "We now add the hypotheses
; indicated by the hint, which CAN BE ...".

  (let* ((seeds (lmi-seed-lst lmi-lst))
         (lemma-names (filter-atoms t seeds))
         (thms (filter-atoms nil seeds))
         (techs (lmi-techs-lst lmi-lst)))
    (cond ((null techs)
           (cond ((null thms)
                  (msg "can be obtained from ~&0"
                       lemma-names))
                 ((null lemma-names)
                  (msg "can be obtained from the ~
                        ~#0~[~/constraint~/~n1 constraints~] generated"
                       (zero-one-or-more k)
                       k))
                 (t (msg "can be obtained from ~&0 and the ~
                          ~#1~[~/constraint~/~n2 constraints~] ~
                          generated"
                         lemma-names
                         (zero-one-or-more k)
                         k))))
          ((null event-names)
           (msg "can be derived from ~&0 via ~*1~#2~[~/, provided we can ~
                 establish the constraint generated~/, provided we can ~
                 establish the ~n3 constraints generated~]"
                seeds
                (list "" "~s*" "~s* and " "~s*, " techs)
                (zero-one-or-more k)
                k))
          (t
           (msg "can be derived from ~&0 via ~*1, bypassing constraints that ~
                 have been proved when processing ~#2~[events ~
                 including ~/previous events~/the event~#3~[~/s~]~ ~
                 ~]~&3~#4~[~/, provided we can establish the constraint ~
                 generated~/, provided we can establish the ~n5 constraints ~
                 generated~]"
                seeds
                (list "" "~s*" "~s* and " "~s*, " techs)

; Recall that an event-name of 0 is really an indication that the event in
; question didn't actually have a name.  See install-event.

                (if (member 0 event-names)
                    (if (cdr event-names)
                        0
                      1)
                  2)
                (if (member 0 event-names)
                    (remove 0 event-names)
                  event-names)
                (zero-one-or-more k)
                k)))))

(defun or-hit-msg (gag-mode-only-p cl-id ttree)

; We print the opening part of the :OR disjunction message, in which we alert
; the reader to the coming disjunctive branches.  If the signal is 'OR-HIT,
; then clauses just the singleton list contain the same clause the :OR was
; attached to.  But ttree contains an :or tag with value (parent-cl-id nil
; ((user-hint1 . hint-settings1)...))  indicating what is to be done to the
; clause.  Eventually the nil we be replaced, on each branch, by the number of
; that branch.  See change-or-hit-history-entry.  The number of branches is the
; length of the third element.  The parent-cl-id in the value is the same as
; the cl-id passed in.

  (let* ((val (cdr (tagged-object :or ttree)))
         (branch-cnt (length (nth 2 val))))
    (msg "The :OR hint for ~@0 gives rise to ~n1 disjunctive ~
          ~#2~[~/branch~/branches~].  Proving any one of these branches would ~
          suffice to prove ~@0.  We explore them in turn~#3~[~@4~/~].~%"
         (tilde-@-clause-id-phrase cl-id)
         branch-cnt
         (zero-one-or-more branch-cnt)
         (if gag-mode-only-p 1 0)
         ", describing their derivations as we go")))

(defun apply-top-hints-clause-msg1
  (signal cl-id clauses speciousp ttree pspv state)

; This function is one of the waterfall-msg subroutines.  It has the standard
; arguments of all such functions: the signal, clauses, ttree and pspv produced
; by the given processor, in this case preprocess-clause (except that for bdd
; processing, the ttree comes from bdd-clause, which is similar to
; simplify-clause, which explains why we also pass in the argument speciousp).
; It produces the report for this step.

; Note:  signal and pspv are really ignored, but they don't appear to be when
; they are passed to simplify-clause-msg1 below, so we cannot declare them
; ignored here.

  (cond ((tagged-object :bye ttree)

; The object associated with the :bye tag is (name . cl).  We are interested
; only in name here.

         (fms "But we have been asked to pretend that this goal is ~
               subsumed by the yet-to-be-proved ~x0.~|"
              (list (cons #\0 (car (cdr (tagged-object :bye ttree)))))
              (proofs-co state)
              state
              nil))
        ((tagged-object :by ttree)
         (let* ((obj (cdr (tagged-object :by ttree)))

; Obj is of the form (lmi-lst thm-cl-set constraint-cl k event-names
; new-entries).

                (lmi-lst (car obj))
                (thm-cl-set (cadr obj))
                (k (car (cdddr obj)))
                (event-names (cadr (cdddr obj)))
                (ttree (cdr (tagged-object 'preprocess-ttree ttree))))
           (fms "~#0~[But, as~/As~/As~] indicated by the hint, this goal is ~
                 subsumed by ~x1, which ~@2.~#3~[~/  By ~*4 we reduce the ~
                 ~#5~[constraint~/~n6 constraints~] to ~#0~[T~/the following ~
                 conjecture~/the following ~n7 conjectures~].~]~|"
                (list (cons #\0 (zero-one-or-more clauses))
                      (cons #\1 (prettyify-clause-set
                                 thm-cl-set
                                 (let*-abstractionp state)
                                 (w state)))
                      (cons #\2 (tilde-@-lmi-phrase lmi-lst k event-names))
                      (cons #\3 (if (int= k 0) 0 1))
                      (cons #\4 (tilde-*-preprocess-phrase ttree))
                      (cons #\5 (if (int= k 1) 0 1))
                      (cons #\6 k)
                      (cons #\7 (length clauses)))
                (proofs-co state)
                state
                (term-evisc-tuple nil state))))
        ((tagged-object :use ttree)
         (let* ((use-obj (cdr (tagged-object :use ttree)))

; The presence of :use indicates that a :use hint was applied to one
; or more clauses to give the output clauses.  If there is also a
; :cases tag in the ttree, then the input clause was split into to 2
; or more cases first and then the :use hint was applied to each.  If
; there is no :cases tag, the :use hint was applied to the input
; clause alone.  Each application of the :use hint adds literals to
; the target clause(s).  This generates a set, A, of ``applications''
; but A need not be the same length as the set of clauses to which we
; applied the :use hint since some of those applications might be
; tautologies.  In addition, the :use hint generated some constraints,
; C.  The set of output clauses, say G, is (C U A).  But C and A are
; not necessarily disjoint, e.g., some constraints might happen to be
; in A.  Once upon a time, we reported on the number of non-A
; constraints, i.e., |C'|, where C' = C\A.  Because of the complexity
; of the grammar, we do not reveal to the user all the numbers: how
; many non-tautological cases, how many hypotheses, how many
; non-tautological applications, how many constraints generated, how
; many after preprocessing the constraints, how many overlaps between
; C and A, etc.  Instead, we give a fairly generic message.  But we
; have left (as comments) the calculation of the key numbers in case
; someday we revisit this.

; The shape of the use-obj, which is the value of the :use tag, is
; ((lmi-lst (hyp1 ...) cl k event-names new-entries)
; . non-tautp-applications) where non-tautp-applications is the number
; of non-tautologies created by the one or more applications of the
; :use hint, i.e., |A|.  (But we do not report this.)

                (lmi-lst (car (car use-obj)))
                (hyps (cadr (car use-obj)))
                (k (car (cdddr (car use-obj))))             ;;; |C|
                (event-names (cadr (cdddr (car use-obj))))
;               (non-tautp-applications (cdr use-obj))      ;;; |A|
                (preprocess-ttree
                 (cdr (tagged-object 'preprocess-ttree ttree)))
;               (len-A non-tautp-applications)              ;;; |A|
                (len-G (len clauses))                       ;;; |G|
                (len-C k)                                   ;;; |C|
;               (len-C-prime (- len-G len-A))               ;;; |C'|

                (cases-obj (cdr (tagged-object :cases ttree)))

; If there is a cases-obj it means we had a :cases and a :use; the
; form of cases-obj is (splitting-terms . case-clauses), where
; case-clauses is the result of splitting on the literals in
; splitting-terms.  We know that case-clauses is non-nil.  (Had it
; been nil, no :use would have been reported.)  Note that if cases-obj
; is nil, i.e., there was no :cases hint applied, then these next two
; are just nil.  But we'll want to ignore them if cases-obj is nil.

;               (splitting-terms (car cases-obj))
;               (case-clauses (cdr cases-obj))
                )
           
           (fms
            "~#0~[But we~/We~] ~#x~[split the goal into the cases specified ~
             by the :CASES hint and augment each case~/augment the goal~] ~
             with the ~#1~[hypothesis~/hypotheses~] provided by the :USE ~
             hint. ~#1~[The hypothesis~/These hypotheses~] ~@2~#3~[~/; the ~
             constraint~#4~[~/s~] can be simplified using ~*5~].  ~#6~[This ~
             reduces the goal to T.~/We are left with the following ~
             subgoal.~/We are left with the following ~n7 subgoals.~]~%"
            (list
             (cons #\x (if cases-obj 0 1))
             (cons #\0 (if (> len-G 0) 1 0))               ;;; |G|>0
             (cons #\1 hyps)
             (cons #\2 (tilde-@-lmi-phrase lmi-lst k event-names))           
             (cons #\3 (if (> len-C 0) 1 0))               ;;; |C|>0
             (cons #\4 (if (> len-C 1) 1 0))               ;;; |C|>1
             (cons #\5 (tilde-*-preprocess-phrase preprocess-ttree))
             (cons #\6 (if (equal len-G 0) 0 (if (equal len-G 1) 1 2)))
             (cons #\7 len-G))
            (proofs-co state)
            state
            (term-evisc-tuple nil state))))
        ((tagged-object :cases ttree)
         (let* ((cases-obj (cdr (tagged-object :cases ttree)))

; The cases-obj here is of the form (term-list . new-clauses), where
; new-clauses is the result of splitting on the literals in term-list.

;               (splitting-terms (car cases-obj))
                (new-clauses (cdr cases-obj)))
           (cond
            (new-clauses
             (fms "We now split the goal into the cases specified by ~
                   the :CASES hint to produce ~n0 new non-trivial ~
                   subgoal~#1~[~/s~].~|"
                  (list (cons #\0 (length new-clauses))
                        (cons #\1 (if (cdr new-clauses) 1 0)))
                  (proofs-co state)
                  state
                  (term-evisc-tuple nil state)))
            (t
             (fms "But the resulting goals are all true by case reasoning."
                  nil
                  (proofs-co state)
                  state
                  nil)))))
        ((eq signal 'OR-HIT)
         (fms "~@0"
              (list (cons #\0 (or-hit-msg nil cl-id ttree)))
              (proofs-co state) state nil))
        ((tagged-object 'hidden-clause ttree)
         state)
        ((tagged-object :clause-processor ttree)
         (let* ((clause-processor-obj (cdr (tagged-object :clause-processor ttree)))

; The clause-processor-obj here is produced by apply-top-hints-clause, and is
; of the form (clause-processor-hint . new-clauses), where new-clauses is the
; result of splitting on the literals in term-list and hint is the translated
; form of a :clause-processor hint.

                (verified-p-msg (cond ((access clause-processor-hint
                                               (car clause-processor-obj)
                                               :verified-p)
                                       "verified")
                                      (t "trusted")))
                (new-clauses (cdr clause-processor-obj))
                (cl-proc-fn (ffn-symb (access clause-processor-hint
                                              (car clause-processor-obj)
                                              :term))))
           (cond
            (new-clauses
             (fms "We now apply the ~@0 :CLAUSE-PROCESSOR function ~x1 to ~
                   produce ~n2 new subgoal~#3~[~/s~].~|"
                  (list (cons #\0 verified-p-msg)
                        (cons #\1 cl-proc-fn)
                        (cons #\2 (length new-clauses))
                        (cons #\3 (if (cdr new-clauses) 1 0)))
                  (proofs-co state)
                  state
                  (term-evisc-tuple nil state)))
            (t
             (fms "But the ~@0 :CLAUSE-PROCESSOR function ~x1 replaces this goal ~
                   by T.~|"
                  (list (cons #\0 verified-p-msg)
                        (cons #\1 cl-proc-fn))
                  (proofs-co state)
                  state
                  nil)))))
        (t

; Normally we expect (tagged-object 'bddnote ttree) in this case, but it is
; possible that forward-chaining after trivial equivalence removal proved
; the clause, without actually resorting to bdd processing.

         (simplify-clause-msg1 signal cl-id clauses speciousp ttree pspv
                               state))))

(defun previous-process-was-speciousp (hist)

; NOTE: This function has not been called since Version_2.5.  However,
; we reference the comment below in a comment in settled-down-clause,
; so for now we keep this comment, if for no other other reason than
; historical.

; Context: We are about to print cl-id and clause in waterfall-msg.
; Then we will print the message associated with the first entry in
; hist, which is the entry for the processor which just hit clause and
; for whom we are reporting.  However, if the previous entry in the
; history was specious, then the cl-id and clause were printed when
; the specious hit occurred and we should not reprint them.  Thus, our
; job here is to decide whether the previous process in the history
; was specious.

; There are complications though, introduced by the existence of
; settled-down-clause.  In the first place, settled-down-clause ALWAYS
; produces a set of clauses containing the input clause and so ought
; to be considered specious every time it hits!  We avoid that in
; waterfall-step and never mark a settled-down-clause as specious, so
; we can assoc for them.  More problematically, consider the
; possibility that the first simplification -- the one before the
; clause settled down -- was specious.  Recall that the
; pre-settled-down-clause simplifications are weak.  Thus, it is
; imaginable that after settling down, other simplifications may
; happen and allow a non-specious simplification.  Thus,
; settled-down-clause actually does report its "hit" (and thus add its
; mark to the history so as to enable the subsequent simplify-clause
; to pull out the stops) following even specious simplifications.
; Thus, we must be prepared here to see a non-specious
; settled-down-clause which followed a specious simplification.

; Note: It is possible that the first entry on hist is specious.  That
; is, if the process on behalf of which we are about to print is in
; fact specious, it is so marked right now in the history.  But that
; is irrelevant to our question.  We don't care if the current guy
; specious, we want to know if his "predecessor" was.  For what it is
; worth, as of this writing, it is thought to be impossible for two
; adjacent history entries to be marked 'SPECIOUS.  Only
; simplify-clause, we think, can produce specious hits.  Whenever a
; specious simplify-clause occurs, it is treated as a 'miss and we go
; on to the next process, which is not simplify-clause.  Note that if
; elim could produce specious 'hits, then we might get two in a row.
; Observe also that it is possible for two successive simplifies to be
; specious, but that they are separated by a non-specious
; settled-down-clause.  (Our code doesn't rely on any of this, but it
; is sometimes helpful to be able to read such thoughts later as a
; hint of what we were thinking when we made some terrible coding
; mistake and so this might illuminate some error we're making today.)

  (cond ((null hist) nil)
        ((null (cdr hist)) nil)
        ((consp (access history-entry (cadr hist) :processor)) t)
        ((and (eq (access history-entry (cadr hist) :processor)
                  'settled-down-clause)
              (consp (cddr hist))
              (consp (access history-entry (caddr hist) :processor)))
         t)
        (t nil)))

; Section:  WATERFALL

; The waterfall is a simple finite state machine (whose individual
; state transitions are very complicated).  Abstractly, each state
; contains a "processor" and two neighbor states, the "hit" state and
; the "miss" state.  Roughly speaking, when we are in a state we apply
; its processor to the input clause and obtain either a "hit" signal
; (and some new clauses) or "miss" signal.  We then transit to the
; appropriate state and continue.

; However, the "hit" state for every state is that point in the falls,
; where 'apply-top-hints-clause is the processor.

; apply-top-hints-clause <------------------+
;  |                                        |
; preprocess-clause ----------------------->|
;  |                                        |
; simplify-clause ------------------------->|
;  |                                        |
; settled-down-clause---------------------->|
;  |                                        |
; ...                                       |
;  |                                        |
; push-clause ----------------------------->+

; WARNING: Waterfall1-lst knows that 'preprocess-clause follows
; 'apply-top-hints-clause!

; We therefore represent a state s of the waterfall as a pair whose car
; is the processor for s and whose cdr is the miss state for s.  The hit
; state for every state is the constant state below, which includes, by
; successive cdrs, every state below it in the falls.

; Because the word "STATE" has a very different meaning in ACL2 than we have
; been using thus far in this discussion, we refer to the "states" of the
; waterfall as "ledges" and basically name them by the processors on each.

(defconst *preprocess-clause-ledge*
  '(apply-top-hints-clause
    preprocess-clause
    simplify-clause
    settled-down-clause
    eliminate-destructors-clause
    fertilize-clause
    generalize-clause
    eliminate-irrelevance-clause
    push-clause))

; Observe that the cdr of the 'simplify-clause ledge, for example, is the
; 'settled-down-clause ledge, etc.  That is, each ledge contains the
; ones below it.

; Note: To add a new processor to the waterfall you must add the
; appropriate entry to the *preprocess-clause-ledge* and redefine
; waterfall-step and waterfall-msg, below.

; If we are on ledge p with input cl and pspv, we apply processor p to
; our input and obtain signal, some cli, and pspv'.  If signal is
; 'abort, we stop and return pspv'.  If signal indicates a hit, we
; successively process each cli, starting each at the top ledge, and
; accumulating the successive pspvs starting from pspv'.  If any cli
; aborts, we abort; otherwise, we return the final pspv.  If signal is
; 'miss, we fall to the next lower ledge with cl and pspv.  If signal
; is 'error, we return abort and propagate the error message upwards.

; Before we resume development of the waterfall, we introduce functions in
; support of gag-mode.

(defmacro initialize-pspv-for-gag-mode (pspv)
  `(if (gag-mode)
       (change prove-spec-var ,pspv
               :gag-state
               *initial-gag-state*)
     ,pspv))

; For debug only:
; (progn
; 
; (defun show-gag-info-pushed (pushed state)
;   (if (endp pushed)
;       state
;     (pprogn (let ((cl-id (caar pushed)))
;               (fms "~@0 (~@1) pushed for induction.~|"
;                    (list (cons #\0 (tilde-@-pool-name-phrase
;                                     (access clause-id cl-id :forcing-round)
;                                     (cdar pushed)))
;                          (cons #\1 (tilde-@-clause-id-phrase cl-id)))
;                    *standard-co* state nil))
;             (show-gag-info-pushed (cdr pushed) state))))
; 
; (defun show-gag-info (info state)
;   (pprogn (fms "~@0:~%~Q12~|~%"
;                (list (cons #\0 (tilde-@-clause-id-phrase
;                                 (access gag-info info :clause-id)))
;                      (cons #\1 (access gag-info info :clause))
;                      (cons #\2 nil))
;                *standard-co* state nil)
;           (show-gag-info-pushed (access gag-info info :pushed)
;                                 state)))
; 
; (defun show-gag-stack (stack state)
;   (if (endp stack)
;       state
;     (pprogn (show-gag-info (car stack) state)
;             (show-gag-stack (cdr stack) state))))
; 
; (defun show-gag-state (cl-id gag-state state)
;   (let* ((top-stack (access gag-state gag-state :top-stack))
;          (sub-stack (access gag-state gag-state :sub-stack))
;          (clause-id (access gag-state gag-state :active-cl-id))
;          (printed-p (access gag-state gag-state
;                             :active-printed-p)))
;     (pprogn (fms "********** Gag state from handling ~@0 (active ~
;                   clause id: ~#1~[<none>~/~@2~])~%"
;                  (list (cons #\0 (tilde-@-clause-id-phrase cl-id))
;                        (cons #\1 (if clause-id 1 0))
;                        (cons #\2 (and clause-id (tilde-@-clause-id-phrase
;                                                  clause-id))))
;                  *standard-co* state nil)
;             (fms "****** Top-stack:~%" nil *standard-co* state nil)
;             (show-gag-stack top-stack state)
;             (fms "****** Sub-stack:~%" nil *standard-co* state nil)
;             (show-gag-stack sub-stack state)
;             (fms "****** Active-printed-p: ~x0"
;                  (list (cons #\0 (access gag-state gag-state
;                                          :active-printed-p)))
;                  *standard-co* state nil)
;             (fms "****** Forcep: ~x0"
;                  (list (cons #\0 (access gag-state gag-state
;                                          :forcep)))
;                  *standard-co* state nil)
;             (fms "******************************~|" nil *standard-co* state
;                  nil))))
; 
; (defun maybe-show-gag-state (cl-id pspv state)
;   (if (and (f-boundp-global 'gag-debug state)
;            (f-get-global 'gag-debug state))
;       (show-gag-state cl-id
;                       (access prove-spec-var pspv :gag-state)
;                       state)
;     state))
; )

(defun waterfall-update-gag-state (cl-id clause proc signal ttree pspv
                                                state)

; We are given a clause-id, cl-id, and a corresponding clause.  Processor proc
; has operated on this clause and returned the given signal (either 'abort or a
; hit indicator), ttree, and pspv.  We suitably extend the gag-state of
; the pspv and produce a message to print before any normal prover output that
; is allowed under gag-mode.

; Thus, we return (mv gagst msg), where gagst is either nil or a new gag-state
; obtained by updating the :gag-state field of pspv, and msg is a message to be
; printed or else nil.  If msg is not nil, then its printer is expected to
; insert a newline before printing msg.

  (let* ((msg-p (not (output-ignored-p 'prove state)))
         (gagst0 (access prove-spec-var pspv :gag-state))
         (pool-lst (access clause-id cl-id :pool-lst))
         (forcing-round (access clause-id cl-id :forcing-round))
         (stack (cond (pool-lst (access gag-state gagst0 :sub-stack))
                      (t        (access gag-state gagst0 :top-stack))))
         (active-cl-id (access gag-state gagst0 :active-cl-id))
         (abort-p (eq signal 'abort))
         (push-or-bye-p (or (eq proc 'push-clause)
                            (and (eq proc 'apply-top-hints-clause)
                                 (eq signal 'hit)
                                 (tagged-object :bye ttree))))
         (new-active-p ; true if we are to push a new gag-info frame
          (and (null active-cl-id)
               (null (cdr pool-lst)) ; not in a sub-induction
               (or push-or-bye-p ; even if the next test fails
                   (member-eq proc (f-get-global 'checkpoint-processors
                                                 state)))))
         (new-frame (and new-active-p
                         (make gag-info
                               :clause-id cl-id
                               :clause clause
                               :pushed nil)))
         (new-stack (cond (new-active-p (cons new-frame stack))
                          (t stack)))
         (gagst (cond (new-active-p (cond (pool-lst
                                           (change gag-state gagst0
                                                   :sub-stack new-stack
                                                   :active-cl-id cl-id))
                                          (t
                                           (change gag-state gagst0
                                                   :top-stack new-stack
                                                   :active-cl-id cl-id))))
                      (t gagst0)))
         (new-forcep (and (not abort-p)
                          (not (access gag-state gagst :forcep))
                          (tagged-object 'assumption ttree)))
         (gagst (cond (new-forcep (change gag-state gagst :forcep t))
                      (t gagst)))
         (forcep-msg (and new-forcep
                          msg-p
                          (msg "Forcing Round ~x0 is pending (caused first by ~
                                ~@1)."
                               (1+ (access clause-id cl-id :forcing-round))
                               (tilde-@-clause-id-phrase cl-id)))))
    (cond
     (push-or-bye-p
      (let* ((top-ci (assert$ (consp new-stack)
                              (car new-stack)))
             (old-pushed (access gag-info top-ci :pushed))
             (top-goal-p (equal cl-id *initial-clause-id*))
             (print-p

; We avoid gag's key checkpoint message if we are in a sub-induction or if we
; are pushing the initial goal for proof by induction.  The latter case is
; handled similarly in the call of waterfall1-lst under waterfall.

              (not (or (access gag-state gagst :active-printed-p)
                       (cdr pool-lst)
                       top-goal-p)))
             (gagst (cond (print-p (change gag-state gagst
                                           :active-printed-p t))
                          (t gagst)))
             (top-stack (access gag-state gagst0 :top-stack))
             (msg0 (cond
                    ((and print-p msg-p)
                     (assert$
                      (null old-pushed)
                      (msg "~@0~|~%~@1~|~Q23~|~%"
                           (gag-start-msg
                            (and pool-lst
                                 (assert$
                                  (consp top-stack)
                                  (access gag-info (car top-stack)
                                          :clause-id)))
                            (and pool-lst
                                 (tilde-@-pool-name-phrase
                                  forcing-round
                                  pool-lst)))
                           (tilde-@-clause-id-phrase
                            (access gag-info top-ci :clause-id))
                           (prettyify-clause
                            (access gag-info top-ci :clause)
                            (let*-abstractionp state)
                            (w state))
                           (term-evisc-tuple nil state))))
                    (t nil))))
        (cond
         (abort-p
          (mv (cond ((eq (cdr (tagged-object 'abort-cause ttree))
                         'revert)
                     (change gag-state gagst :abort-stack new-stack))
                    (t gagst))
              (and msg-p
                   (msg "~@0~@1"
                        (or msg0 "")
                        (push-clause-msg1-abort cl-id ttree pspv state)))))
         (t (let* ((old-pspv-pool-lst
                    (pool-lst (cdr (access prove-spec-var pspv :pool))))
                   (newer-stack
                    (and (assert$
                          (or (cdr pool-lst) ;sub-induction; no active chkpt
                              (equal (access gag-state gagst
                                             :active-cl-id)
                                     (access gag-info top-ci
                                             :clause-id)))
                          (if (eq proc 'push-clause)
                              (cons (change gag-info top-ci
                                            :pushed
                                            (cons (cons cl-id old-pspv-pool-lst)
                                                  old-pushed))
                                    (cdr new-stack))
                            new-stack)))))
              (mv (cond (pool-lst
                         (change gag-state gagst :sub-stack
                                 newer-stack))
                        (t
                         (change gag-state gagst :top-stack
                                 newer-stack)))
                  (and
                   msg-p
                   (or msg0 forcep-msg (gag-mode))
                   (msg "~@0~#1~[~@2~|~%~/~]~@3"
                        (or msg0 "")
                        (if forcep-msg 0 1)
                        forcep-msg
                        (cond
                         ((null (gag-mode))
                          "")
                         (t
                          (let ((msg-finish
                                 (cond ((or pool-lst ; pushed for sub-induction
                                            (null active-cl-id))
                                        ".")
                                       (t (msg ":~|~Q01."
                                               (prettyify-clause
                                                clause
                                                (let*-abstractionp state)
                                                (w state))
                                               (term-evisc-tuple nil state))))))
                            (cond
                             ((eq proc 'push-clause)
                              (msg "~@0 (~@1) is pushed for proof by ~
                                    induction~@2"
                                   (tilde-@-pool-name-phrase
                                    forcing-round
                                    old-pspv-pool-lst)
                                   (if top-goal-p
                                       "the initial Goal, a key checkpoint"
                                     (tilde-@-clause-id-phrase cl-id))
                                   msg-finish))
                             (t
                              (msg "~@0 is subsumed by a goal yet to be ~
                                    proved~@1"
                                   (tilde-@-clause-id-phrase cl-id)
                                   msg-finish))))))))))))))
     (t (assert$ (not abort-p) ; we assume 'abort is handled above
                 (mv (cond ((or new-active-p new-forcep)
                            gagst)
                           (t nil))
                     forcep-msg))))))

(defun record-gag-state (gag-state state)
  (f-put-global 'gag-state gag-state state))

(defun gag-state-exiting-cl-id (signal cl-id pspv state)

; If cl-id is the active clause-id for the current gag-state, then we
; deactivate it.  We also eliminate the corresponding stack frame, if any,
; provided no goals were pushed for proof by induction.

  (let* ((gagst0 (access prove-spec-var pspv :gag-state))
         (active-cl-id (access gag-state gagst0 :active-cl-id)))
    (cond ((equal cl-id active-cl-id)
           (let* ((pool-lst (access clause-id cl-id :pool-lst))
                  (stack (cond (pool-lst
                                (access gag-state gagst0 :sub-stack))
                               (t
                                (access gag-state gagst0 :top-stack))))
                  (ci (assert$ (consp stack)
                               (car stack)))
                  (current-cl-id (access gag-info ci :clause-id))
                  (printed-p (access gag-state gagst0 :active-printed-p))
                  (gagst1 (cond (printed-p (change gag-state gagst0
                                                   :active-cl-id nil
                                                   :active-printed-p nil))
                                (t         (change gag-state gagst0
                                                   :active-cl-id nil))))
                  (gagst2 (cond
                           ((eq signal 'abort)
                            (cond
                             ((eq (cdr (tagged-object
                                        'abort-cause
                                        (access prove-spec-var pspv
                                                :tag-tree)))
                                  'revert)
                              (change gag-state gagst1 ; save abort info
                                      :active-cl-id nil
                                      :active-printed-p nil
                                      :forcep nil
                                      :sub-stack nil
                                      :top-stack
                                      (list
                                       (make gag-info
                                             :clause-id *initial-clause-id*
                                             :clause (list '<Goal>)
                                             :pushed
                                             (list (cons *initial-clause-id*
                                                         '(1)))))))
                             (t gagst1)))
                           ((and (equal cl-id current-cl-id)
                                 (null (access gag-info ci
                                               :pushed)))
                            (cond (pool-lst
                                   (change gag-state gagst1
                                           :sub-stack (cdr stack)))
                                  (t
                                   (change gag-state gagst1
                                           :top-stack (cdr stack)))))
                           (t gagst1))))
             (pprogn
              (record-gag-state gagst2 state)
              (cond (printed-p
                     (io? prove nil state nil
                          (pprogn
                           (increment-timer 'prove-time state)
                           (cond ((gag-mode)
                                  (fms "~@0"
                                       (list (cons #\0 *gag-suffix*))
                                       (proofs-co state) state nil))
                                 (t state))
                           (increment-timer 'print-time state))))
                    (t state))
              (mv (change prove-spec-var pspv
                          :gag-state gagst2)
                  state))))
          (t (mv pspv state)))))

(defun remove-pool-lst-from-gag-state (pool-lst gag-state)

; The proof attempt for the induction goal represented by pool-lst has been
; completed.  We return two values, (mv gagst cl-id), as follows.  Gagst is the
; result of removing pool-lst from the given gag-state.  Cl-id is nil unless
; pool-lst represents the final induction goal considered that was generated
; under a key checkpoint, in which case cl-id is the clause-id of that key
; checkpoint.

  (let* ((sub-stack (access gag-state gag-state :sub-stack))
         (stack (or sub-stack (access gag-state gag-state
                                      :top-stack))))
    (assert$ (consp stack)
             (let* ((ci (car stack))
                    (pushed (access gag-info ci :pushed))
                    (pop-car-p (null (cdr pushed))))
               (assert$
                (and (consp pushed)
                     (equal (cdar pushed) pool-lst)
                     (not (access gag-state gag-state
                                  :active-cl-id)))
                (let ((new-stack
                       (if pop-car-p
                           (cdr stack)
                         (cons (change gag-info ci
                                       :pushed
                                       (cdr pushed))
                               (cdr stack)))))
                  (mv (cond (sub-stack
                             (change gag-state gag-state
                                     :sub-stack new-stack))
                            (t
                             (change gag-state gag-state
                                     :top-stack new-stack)))
                      (and pop-car-p
                           (access gag-info ci :clause-id)))))))))

(defun pop-clause-update-gag-state-pop (pool-lsts gag-state msgs msg-p)

; Pool-lsts is in reverse chronological order.

  (cond
   ((endp pool-lsts)
    (mv gag-state msgs))
   (t
    (mv-let
     (gag-state msgs)
     (pop-clause-update-gag-state-pop (cdr pool-lsts) gag-state msgs msg-p)
     (mv-let (gagst cl-id)
             (remove-pool-lst-from-gag-state (car pool-lsts) gag-state)
             (mv gagst
                 (if (and msg-p cl-id)
                     (cons (msg "~@0"
                                (tilde-@-clause-id-phrase cl-id))
                           msgs)
                   msgs)))))))

(defun gag-mode-jppl-flg (gag-state)
  (let ((stack (or (access gag-state gag-state :sub-stack)
                   (access gag-state gag-state :top-stack))))
    (cond (stack
           (let* ((pushed (access gag-info (car stack) :pushed))
                  (pool-lst (and pushed (cdar pushed))))
  
; Notice that pool-lst is nil if pushed is nil, as can happen when we abort due
; to encountering an empty clause.

             (and (null (cdr pool-lst)) ; sub-induction goal was not printed
                  pool-lst)))
          (t nil))))

; That completes basic support for gag-mode.  We now resume mainline
; development of the waterfall.

; The waterfall also manages the output, by case switching on the
; processor.  The next function handles the printing of the formula
; and the output for those processes that hit.

(defun waterfall-msg1
  (processor cl-id signal clauses new-hist msg ttree pspv state)
  (pprogn

; (maybe-show-gag-state cl-id pspv state) ; debug

   (cond

; Suppress printing for :OR splits; see also other comments with this header.

;   ((and (eq signal 'OR-HIT)
;         (gag-mode))
;    (fms "~@0~|~%~@1~|"
;         (list (cons #\0 (or msg ""))
;               (cons #\1 (or-hit-msg t cl-id ttree)))
;         (proofs-co state) state nil))

    ((and msg (gag-mode))
     (fms "~@0~|" (list (cons #\0 msg)) (proofs-co state) state nil))
    (t state))
   (cond
    ((gag-mode) state)
    (t
     (case
       processor
       (apply-top-hints-clause

; Note that the args passed to apply-top-hints-clause, and to
; simplify-clause-msg1 below, are nonstandard.  This is what allows the
; simplify message to detect and report if the just performed simplification
; was specious.

        (apply-top-hints-clause-msg1
         signal cl-id clauses
         (consp (access history-entry (car new-hist)
                        :processor))
         ttree pspv state))
       (preprocess-clause
        (preprocess-clause-msg1 signal clauses ttree pspv state))
       (simplify-clause
        (simplify-clause-msg1 signal cl-id clauses
                              (consp (access history-entry (car new-hist)
                                             :processor))
                              ttree pspv state))
       (settled-down-clause
        (settled-down-clause-msg1 signal clauses ttree pspv state))
       (eliminate-destructors-clause
        (eliminate-destructors-clause-msg1 signal clauses ttree
                                           pspv state))
       (fertilize-clause
        (fertilize-clause-msg1 signal clauses ttree pspv state))
       (generalize-clause
        (generalize-clause-msg1 signal clauses ttree pspv state))
       (eliminate-irrelevance-clause
        (eliminate-irrelevance-clause-msg1 signal clauses ttree
                                           pspv state))
       (otherwise
        (push-clause-msg1 cl-id signal clauses ttree pspv state)))))))

(defun waterfall-msg
  (processor cl-id clause signal clauses new-hist ttree pspv state)

; This function prints the report associated with the given processor on some
; input clause, clause, with output signal, clauses, ttree, and pspv.  The code
; below consists of two distinct parts.  First we print the message associated
; with the particular processor.  Then we return three results: a "jppl-flg", a
; new pspv with the gag-state updated, and the state.

; The jppl-flg is either nil or a pool-lst.  When non-nil, the jppl-flg means
; we just pushed a clause into the pool and assigned it the name that is the
; value of the flag.  "Jppl" stands for "just pushed pool list".  This flag is
; passed through the waterfall and eventually finds its way to the pop-clause
; after the waterfall, where it is used to control the optional printing of the
; popped clause.  If the jppl-flg is non-nil when we pop, it means we need not
; re-display the clause because it was just pushed and we can refer to it by
; name.

; This function increments timers.  Upon entry, the accumulated time is charged
; to 'prove-time.  The time spent in this function is charged to 'print-time.

  (pprogn
   (increment-timer 'prove-time state)
   (io? proof-tree nil state
        (pspv signal new-hist clauses processor ttree cl-id)
        (pprogn
         (increment-proof-tree
          cl-id ttree processor (length clauses) new-hist signal pspv state)
         (increment-timer 'proof-tree-time state)))
   (mv-let
    (gagst msg)
    (waterfall-update-gag-state cl-id clause processor signal ttree pspv state)
    (mv-let
     (pspv state)
     (cond (gagst (pprogn (record-gag-state gagst state)
                          (mv (change prove-spec-var pspv :gag-state gagst)
                              state)))
           (t (mv pspv state)))
     (pprogn
      (io? prove nil state
           (pspv ttree new-hist clauses signal cl-id processor msg)
           (waterfall-msg1 processor cl-id signal clauses new-hist msg ttree
                           pspv state))
      (increment-timer 'print-time state)
      (mv (cond ((eq processor 'push-clause)

; Keep the following in sync with the corresponding call of pool-lst in
; waterfall0-or-hit.  See the comment there.

                 (pool-lst (cdr (access prove-spec-var pspv :pool))))
                (t nil))
          pspv
          state))))))

; The waterfall is responsible for storing the ttree produced by each
; processor in the pspv.  That is done with:

(defun put-ttree-into-pspv (ttree pspv)
  (change prove-spec-var pspv
          :tag-tree (cons-tag-trees ttree
                                   (access prove-spec-var pspv :tag-tree))))

(defun set-cl-ids-of-assumptions (ttree cl-id)

; We scan the tag-tree ttree, looking for 'assumptions.  Recall that each has a
; :assumnotes field containing exactly one assumnote record, which contains a
; :cl-id field.  We assume that :cl-id field is empty.  We put cl-id into it.
; We return a copy of ttree.

  (cond
   ((null ttree) nil)
   ((symbolp (caar ttree))
    (cond
     ((eq (caar ttree) 'assumption)

; Picky Note: The double-cons nest below is used as though it were equivalent
; to (add-to-tag-tree 'assumption & &) and is justified with the reasoning: if
; the original assumption was added to the cdr subtree with add-to-tag-tree
; (and thus, is known not to occur in that subtree), then the changed
; assumption does not occur in the changed cdr subtree.  That is true.  But we
; don't really know that the original assumption was ever checked by
; add-to-tag-tree.  It doesn't really matter, tag-trees being sets anyway.  But
; this optimization does mean that this function knows how to construct
; tag-trees without using the official constructors.  But of course it knows
; that: it destructures them to explore them.  This same picky note could be
; placed in front of the final cons below, as well as in
; strip-non-rewrittenp-assumptions.

      (cons (cons 'assumption
                  (change assumption (cdar ttree)
                          :assumnotes
                          (list (change assumnote
                                        (car (access assumption (cdar ttree)
                                                     :assumnotes))
                                        :cl-id cl-id))))
            (set-cl-ids-of-assumptions (cdr ttree) cl-id)))
     ((tagged-object 'assumption (cdr ttree))
      (cons (car ttree)
            (set-cl-ids-of-assumptions (cdr ttree) cl-id)))
     (t ttree )))
   ((tagged-object 'assumption ttree)
    (cons (set-cl-ids-of-assumptions (car ttree) cl-id)
          (set-cl-ids-of-assumptions (cdr ttree) cl-id)))
   (t ttree)))

; We now develop the code for proving the assumptions that are forced during
; the first part of the proof.  These assumptions are all carried in the ttree
; on 'assumption tags.  (Delete-assumptions was originally defined just below
; collect-assumptions, but has been moved up since it is used in push-clause.)

(defun collect-assumptions (ttree only-immediatep ans)

; We collect the assumptions in ttree and accumulate them onto ans.
; Only-immediatep determines exactly which assumptions we collect:
; * 'non-nil    -- only collect those with :immediatep /= nil
; * 'case-split -- only collect those with :immediatep = 'case-split
; * t           -- only collect those with :immediatep = t
; * nil         -- collect ALL assumptions

  (cond ((null ttree) ans)
        ((symbolp (caar ttree))
         (cond ((and (eq (caar ttree) 'assumption)
                     (cond
                      ((eq only-immediatep 'non-nil)
                       (access assumption (cdar ttree) :immediatep))
                      ((eq only-immediatep 'case-split)
                       (eq (access assumption (cdar ttree) :immediatep)
                           'case-split))
                      ((eq only-immediatep t)
                       (eq (access assumption (cdar ttree) :immediatep)
                           t))
                      (t t)))
                (collect-assumptions (cdr ttree)
                                     only-immediatep
                                     (add-to-set-equal (cdar ttree) ans)))
               (t (collect-assumptions (cdr ttree) only-immediatep ans))))
        (t (collect-assumptions
            (car ttree)
            only-immediatep
            (collect-assumptions (cdr ttree) only-immediatep ans)))))  

; We are now concerned with trying to shorten the type-alists used to
; govern assumptions.  We have two mechanisms.  One is
; ``disguarding,'' the throwing out of any binding whose term
; requires, among its guard clauses, the truth of the term we are
; trying to prove.  The second is ``disvaring,'' the throwing out of
; any binding that does not mention any variable linked to term.

; First, disguarding...  We must first define the fundamental process
; of generating the guard clauses for a term.  This "ought" to be in
; the vicinity of our definition of defun and verify-guards.  But we
; need it now.

(defun sublis-var-lst-lst (alist clauses)
  (cond ((null clauses) nil)
        (t (cons (sublis-var-lst alist (car clauses))
                 (sublis-var-lst-lst alist (cdr clauses))))))

(defun add-segments-to-clause (clause segments)
  (cond ((null segments) nil)
        (t (conjoin-clause-to-clause-set
            (disjoin-clauses clause (car segments))
            (add-segments-to-clause clause (cdr segments))))))

(defun split-initial-extra-info-lits (cl hyps-rev)
  (cond ((endp cl) (mv hyps-rev cl))
        ((extra-info-lit-p (car cl))
         (split-initial-extra-info-lits (cdr cl)
                                        (cons (car cl) hyps-rev)))
        (t (mv hyps-rev cl))))

(defun conjoin-clause-to-clause-set-extra-info1 (tags-rev cl0 cl cl-set
                                                          cl-set-all)

; Roughly speaking, we want to extend cl-set-all by adding cl = (revappend
; tags-rev cl0), where tags-rev is the reversed initial prefix of negated calls
; of *extra-info-fn*.  But the situation is a bit more complex:

; Cl is (revappend tags-rev cl0) and cl-set is a tail of cl-set-all.  Let cl1
; be the first member of cl-set, if any, such that removing its initial negated
; calls of *extra-info-fn* yields cl0.  We replace the corresponding occurrence
; of cl1 in cl-set-all by the result of adding tags-rev (reversed) in front of
; cl0, except that we drop each tag already in cl1; otherwise we return
; cl-set-all unchanged.  If there is no such cl1, then we return the result of
; consing cl on the front of cl-set-all.

  (cond
   ((endp cl-set)
    (cons cl cl-set-all))
   (t
    (mv-let
     (initial-extra-info-lits-rev cl1)
     (split-initial-extra-info-lits (car cl-set) nil)
     (cond
      ((equal cl0 cl1)
       (cond
        ((not tags-rev) ; seems unlikely
         cl-set-all)
        (t (cond
            ((subsetp-equal tags-rev initial-extra-info-lits-rev)
             cl-set-all)
            (t
             (append (take (- (length cl-set-all) (length cl-set))
                           cl-set-all)
                     (cons (revappend initial-extra-info-lits-rev
                                      (mv-let
                                       (changedp new-tags-rev)
                                       (set-difference-equal-changedp
                                        tags-rev
                                        initial-extra-info-lits-rev)
                                       (cond
                                        (changedp (revappend new-tags-rev cl0))
                                        (t cl))))
                           (cdr cl-set))))))))
      (t (conjoin-clause-to-clause-set-extra-info1 tags-rev cl0 cl (cdr cl-set)
                                                   cl-set-all)))))))

(defun conjoin-clause-to-clause-set-extra-info (cl cl-set)

; Cl, as well as each clause in cl-set, may start with zero or more negated
; calls of *extra-info-fn*.  Semantically (since *extra-info-fn* always returns
; T), we return the result of conjoining cl to cl-set, as with
; conjoin-clause-to-clause-set.  However, we view a prefix of negated
; *extra-info-fn* calls in a clause as a set of tags indicating a source of
; that clause, and we want to preserve that view when we conjoin cl to cl-set.
; In particular, if a member cl1 of cl-set agrees with cl except for the
; prefixes of negated calls of *extra-info-fn*, it is desirable for the merge
; to be achieved simply by adding the prefix of negated calls of
; *extra-info-fn* in cl to the prefix of such terms in cl1.  This function
; carries out that desire.

  (cond ((member-equal *t* cl) cl-set)
        (t (mv-let (tags-rev cl0)
                   (split-initial-extra-info-lits cl nil)
                   (conjoin-clause-to-clause-set-extra-info1
                    tags-rev cl0 cl cl-set cl-set)))))

(defun conjoin-clause-sets-extra-info (cl-set1 cl-set2)

; Keep in sync with conjoin-clause-sets.

; It is unfortunatel that each clause in cl-set2 is split into a prefix (of
; negated *extra-info-fn* calls) and the rest for EACH member of cl-set1.
; However, we expect the sizes of clause-sets to be relatively modest;
; otherwise presumably the simplifier would choke.  So even though we could
; preprocess by splitting cl-set2 into a list of pairs (prefix . rest), for now
; we'll avoid thus complicating the algorithm (which also could perhaps
; generate extra garbage as it reconstitutes cl-set2 from such pairs).

  (cond ((null cl-set1) cl-set2)
        (t (conjoin-clause-to-clause-set-extra-info
            (car cl-set1)
            (conjoin-clause-sets-extra-info (cdr cl-set1) cl-set2)))))

(defun maybe-add-extra-info-lit (debug-info term clause wrld)
  (cond (debug-info
         (cons (fcons-term* 'not
                            (fcons-term* *extra-info-fn*
                                         (kwote debug-info)
                                         (kwote (untranslate term nil wrld))))
               clause))
        (t clause)))

(defun conjoin-clause-sets+ (debug-info cl-set1 cl-set2)
  (cond (debug-info (conjoin-clause-sets-extra-info cl-set1 cl-set2))
        (t (conjoin-clause-sets cl-set1 cl-set2))))

(defconst *equality-aliases*

; This constant should be a subset of *definition-minimal-theory*, since we do
; not track the corresponding runes in simplify-tests and related code below.

  '(eq eql =))

(defun term-equated-to-constant (term)
  (case-match term
    ((rel x y)
     (cond ((or (eq rel 'equal)
                (member-eq rel *equality-aliases*))
            (cond ((quotep x) (mv y x))
                  ((quotep y) (mv x y))
                  (t (mv nil nil))))
           (t (mv nil nil))))
    (& (mv nil nil))))

(defun simplify-clause-for-term-equal-const-1 (var const cl)

; This is the same as simplify-tests, but where cl is a clause: here we are
; considering their disjunction, rather than the disjunction of their negations
; (i.e., an implication where all elements are considered true).

  (cond ((endp cl)
         (mv nil nil))
        (t (mv-let (changedp rest)
                   (simplify-clause-for-term-equal-const-1 var const (cdr cl))
                   (mv-let (var2 const2)
                           (term-equated-to-constant (car cl))
                           (cond ((and (equal var var2)
                                       (not (equal const const2)))
                                  (mv t rest))
                                 (changedp
                                  (mv t (cons (car cl) rest)))
                                 (t
                                  (mv nil cl))))))))

(defun simplify-clause-for-term-equal-const (var const cl)

; See simplify-clause-for-term-equal-const.

  (mv-let (changedp new-cl)
          (simplify-clause-for-term-equal-const-1 var const cl)
          (declare (ignore changedp))
          new-cl))

(defun add-literal-smart (lit cl at-end-flg)

; This version of add-literal can remove literals from cl that are known to be
; false, given that lit is false.

  (mv-let (term const)
          (cond ((and (nvariablep lit)
;                     (not (fquotep lit))
                      (eq (ffn-symb lit) 'not))
                 (term-equated-to-constant (fargn lit 1)))
                (t (mv nil nil)))
          (add-literal lit
                       (cond (term (simplify-clause-for-term-equal-const
                                    term const cl))
                             (t cl))
                       at-end-flg)))

(mutual-recursion

(defun guard-clauses (term debug-info stobj-optp clause wrld ttree)

; See also guard-clauses+, which is a wrapper for guard-clauses that eliminates
; ground subexpressions.

; We return two results.  The first is a set of clauses whose
; conjunction establishes that all of the guards in term are
; satisfied.  The second result is a ttree justifying the
; simplification we do and extending ttree.  Stobj-optp indicates
; whether we are to optimize away stobj recognizers.  Call this with
; stobj-optp = t only when it is known that the term in question has
; been translated with full enforcement of the stobj rules.  Clause is
; the list of accumulated, negated tests passed so far on this branch.
; It is maintained in reverse order, but reversed before we return it.

; We do not add the definition rune for *extra-info-fn* in ttree.  The caller
; should be content with failing to report that rune.  Prove-guard-clauses is
; ultimately the caller, and is happy not to burden the user with mention of
; that rune.

; Note: Once upon a time, this function took an additional argument,
; alist, and was understood to be generating the guards for term/alist.
; Alist was used to carry the guard generation process into lambdas.

  (cond ((variablep term) (mv nil ttree))
        ((fquotep term) (mv nil ttree))
        ((flambda-applicationp term)
         (mv-let
          (cl-set1 ttree)
          (guard-clauses-lst (fargs term) debug-info stobj-optp clause wrld
                             ttree)
          (mv-let
           (cl-set2 ttree)
           (guard-clauses (lambda-body (ffn-symb term))
                          debug-info
                          stobj-optp

; We pass in the empty clause here, because we do not want it involved
; in wrapping up the lambda term that we are about to create.

                          nil
                          wrld ttree)
           (let* ((term1 (make-lambda-application
                          (lambda-formals (ffn-symb term))
                          (termify-clause-set cl-set2)
                          (remove-guard-holders-lst (fargs term))))
                  (cl (reverse (add-literal-smart term1 clause nil)))
                  (cl-set3 (if (equal cl *true-clause*)
                               cl-set1
                             (conjoin-clause-sets+
                              debug-info
                              cl-set1

; Instead of cl below, we could use (maybe-add-extra-info-lit debug-info term
; cl wrld).  But that can cause a large number of lambda (let) terms in the
; output that are probabably more unhelpful (as noise) than helpful.

                              (list cl)))))
             (mv cl-set3 ttree)))))
        ((eq (ffn-symb term) 'if)
         (let ((test (remove-guard-holders (fargn term 1))))
           (mv-let
            (cl-set1 ttree)

; Note:  We generate guards from the original test, not the one with guard
; holders removed!

            (guard-clauses (fargn term 1) debug-info stobj-optp clause wrld
                           ttree)
            (mv-let
             (cl-set2 ttree)
             (guard-clauses (fargn term 2)
                            debug-info
                            stobj-optp

; But the additions we make to the two branches is based on the
; simplified test.

                            (add-literal-smart (dumb-negate-lit test)
                                               clause
                                               nil)
                            wrld ttree)
             (mv-let
              (cl-set3 ttree)
              (guard-clauses (fargn term 3)
                             debug-info
                             stobj-optp
                             (add-literal-smart test
                                                clause
                                                nil)
                             wrld ttree)
              (mv (conjoin-clause-sets+
                   debug-info
                   cl-set1
                   (conjoin-clause-sets+ debug-info cl-set2 cl-set3))
                  ttree))))))
        ((eq (ffn-symb term) 'wormhole-eval)

; Because of translate, term is necessarily of the form

; (wormhole-eval '<name> '(lambda (<whs>) <body>) <name-dropper-term>)
; or
; (wormhole-eval '<name> '(lambda (     ) <body>) <name-dropper-term>)

; the only difference being whether the lambda has one or no formals.  The
; <body> of the lambda has been translated despite its occurrence inside a
; quoted lambda.  The <name-dropper-term> is always of the form 'NIL or a
; variable symbol or a PROG2$ nest of variable symbols and thus has a guard of
; T.  Furthermore, translate insures that the free variables of the lambda
; are those of the <name-dropper-term>.  Thus, all the variables we encounter in
; <body> are variables known in the current context, except <whs>.  By the way,
; ``whs'' stands for ``wormhole status'' and if it is the lambda formal we know
; it occurs in <body>.

; The raw lisp macroexpansion of the first wormhole-eval form above is
; (modulo the name of var)

; (let* ((<whs> (cdr (assoc-equal '<name> *wormhole-status-alist*)))
;        (val <body>))
;   (or (equal <whs> val)
;       (put-assoc-equal '<name> val *wormhole-status-alist*))
;   nil)
;
; We wish to make sure this form is Common Lisp compliant.  We know that
; *wormhole-status-alist* is an alist satisfying the guard of assoc-equal and
; put-assoc-equal.  The raw lisp macroexpansion of the second form of
; wormhole-eval is also like that above.  Thus, the only problematic form in
; either expansion is <body>, which necessarily mentions the variable symbol
; <whs> if it's mentioned in the lambda.  Furthermore, at runtime we know
; absolutely nothing about the last wormhole status of <name>.  So we need to
; generate a fresh variable symbol to use in place of <whs> in our guard
; clauses.

         (let* ((whs (car (lambda-formals (cadr (fargn term 2)))))
                (body (lambda-body (cadr (fargn term 2))))
                (name-dropper-term (fargn term 3))
                (new-var (if whs
                             (genvar whs (symbol-name whs) nil
                                     (all-vars1-lst clause
                                                    (all-vars name-dropper-term)))
                           nil))
                (new-body (if (eq whs new-var)
                              body
                            (subst-var new-var whs body))))
           (guard-clauses new-body debug-info stobj-optp clause wrld ttree)))

; At one time we optimized away the guards on (nth 'n MV) if n is an
; integerp and MV is bound in (former parameter) alist to a call of a
; multi-valued function that returns more than n values.  Later we
; changed the way mv-let is handled so that we generated calls of
; mv-nth instead of nth, but we inadvertently left the code here
; unchanged.  Since we have not noticed resulting performance
; problems, and since this was the only remaining use of alist when we
; started generating lambda terms as guards, we choose for
; simplicity's sake to eliminate this special optimization for mv-nth.

        (t

; Here we generate the conclusion clauses we must prove.  These
; clauses establish that the guard of the function being called is
; satisfied.  We first convert the guard into a set of clause
; segments, called the guard-concl-segments.

; We optimize stobj recognizer calls to true here.  That is, if the
; function traffics in stobjs (and is not non-executablep!), then it
; was so translated and we know that all those stobj recognizer calls
; are true.

; Once upon a time, we normalized the 'guard first.  Is that important?

         (let ((guard-concl-segments (clausify
                                      (guard (ffn-symb term)
                                             stobj-optp
                                             wrld)

; Warning:  It might be tempting to pass in the assumptions of clause into
; the second argument of clausify.  That would be wrong!  The guard has not
; yet been instantiated and so the variables it mentions are not the same
; ones in clause!

                                      nil

; Should we expand lambdas here?  I say ``yes,'' but only to be
; conservative with old code.  Perhaps we should change the t to nil?

                                      t

; We use the sr-limit from the world, because we are above the level at which
; :hints or :guard-hints would apply.

                                      (sr-limit wrld))))
           (mv-let
            (cl-set1 ttree)
            (guard-clauses-lst
             (cond
              ((and (eq (ffn-symb term) 'return-last)
                    (quotep (fargn term 1)))
               (case (unquote (fargn term 1))
                 (mbe1-raw

; Since (return-last 'mbe1-raw exec logic) macroexpands to exec in raw Common
; Lisp, we need only verify guards for the :exec part of an mbe call.

                  (list (fargn term 2)))
                 (ec-call1-raw

; Since (return-last 'ec-call1-raw ign (fn arg1 ... argk)) macroexpands to
; (*1*fn arg1 ... argk) in raw Common Lisp, we need only verify guards for the
; argi.

                  (fargs (fargn term 3)))
                 (otherwise

; Consider the case that (fargn term 1) is not syntactically equal to 'mbe1-raw
; or 'ec-call1-raw but reduces to one of these.  Even then, return-last is a
; macro in Common Lisp, so we shouldn't produce the reduced obligations for
; either of the two cases above.  But this is a minor issue anyhow, because
; it's certainly safe to avoid those reductions, so in the worst case we would
; still be sound, even if producing excessively strong guard obligations.

                  (fargs term))))
              (t (fargs term)))
             debug-info stobj-optp clause wrld ttree)
            (mv (conjoin-clause-sets+
                 debug-info
                 cl-set1
                 (add-segments-to-clause
                  (maybe-add-extra-info-lit debug-info term (reverse clause)
                                            wrld)
                  (add-each-literal-lst
                   (and guard-concl-segments ; optimization (nil for ec-call)
                        (sublis-var-lst-lst
                         (pairlis$
                          (formals (ffn-symb term) wrld)
                          (remove-guard-holders-lst
                           (fargs term)))
                         guard-concl-segments)))))
                ttree))))))

(defun guard-clauses-lst (lst debug-info stobj-optp clause wrld ttree)
  (cond ((null lst) (mv nil ttree))
        (t (mv-let
            (cl-set1 ttree)
            (guard-clauses (car lst) debug-info stobj-optp clause wrld ttree)
            (mv-let
             (cl-set2 ttree)
             (guard-clauses-lst (cdr lst) debug-info stobj-optp clause wrld
                                ttree)
             (mv (conjoin-clause-sets+ debug-info cl-set1 cl-set2) ttree))))))

)

; And now disvaring...

(defun linked-variables1 (vars direct-links changedp direct-links0)

; We union into vars those elements of direct-links that overlap its
; current value.  When we have done them all we ask if anything
; changed and if so, start over at the beginning of direct-links.

  (cond
   ((null direct-links)
    (cond (changedp (linked-variables1 vars direct-links0 nil direct-links0))
          (t vars)))
   ((and (intersectp-eq (car direct-links) vars)
         (not (subsetp-eq (car direct-links) vars)))
    (linked-variables1 (union-eq (car direct-links) vars)
                       (cdr direct-links)
                       t direct-links0))
   (t (linked-variables1 vars (cdr direct-links) changedp direct-links0))))

(defun linked-variables (vars direct-links)

; Vars is a list of variables.  Direct-links is a list of lists of
; variables, e.g., '((X Y) (Y Z) (A B) (M)).  Let's say that one
; variable is "directly linked" to another if they both appear in one
; of the lists in direct-links.  Thus, above, X and Y are directly
; linked, as are Y and Z, and A and B.  This function returns the list
; of all variables that are linked (directly or transitively) to those
; in vars.  Thus, in our example, if vars is '(X) the answer is '(X Y
; Z), up to order of appearance.

; Note on Higher Order Definitions and the Inconvenience of ACL2:
; Later in these sources we will define the "mate and merge" function,
; m&m, which computes certain kinds of transitive closures.  We really
; wish we had that function now, because this function could use it
; for the bulk of this computation.  But we can't define it here
; without moving up some of the data structures associated with
; induction.  Rather than rip our code apart, we define a simple
; version of m&m that does the job.

; This suggests that we really ought to support the idea of defining a
; function before all of its subroutines are defined -- a feature that
; ultimately involves the possibility of implicit mutual recursion.

; It should also be noted that the problem with moving m&m is not so
; much with the code for the mate and merge process as it is with the
; pseudo functional argument it takes.  M&m naturally is a higher
; order function that compute the transitive closure of an operation
; supplied to it.  Because ACL2 is first order, our m&m doesn't really
; take a function but rather a symbol and has a finite table mapping
; symbols to functions (m&m-apply).  It is only that table that we
; can't move up to here!  So if ACL2 were higher order, we could
; define m&m now and everything would be neat.  Of course, if ACL2
; were higher order, we suspect some other aspects of our coding
; (perhaps efficiency and almost certainly theorem proving power)
; would be degraded.

  (linked-variables1 vars direct-links nil direct-links))

; Part of disvaring a type-alist to is keep type-alist entries about
; constrained constants.  This goes to a problem that Eric Smith noted.
; He had constrained (thebit) to be 0 or 1 and had a type-alist entry
; stating that (thebit) was not 0.  In a forcing round he needed that 
; (thebit) was 1.  But disvaring had thrown out of the type-alist the
; entry for (thebit) because it did not mention any of the relevant
; variables.  So, in a change for Version_2.7 we now keep entries that
; mention constrained constants.  We considered the idea of keeping
; entries that mention any constrained function, regardless of arity.
; But that seems like overkill.  Had Eric constrained (thebit x) to
; be 0 or 1 and then had a hypothesis that it was not 0, it seems
; unlikely that the forcing round would need to know (thebit x) is 1
; if x is not among the relevant vars.  That is, one assumes that if a
; constrained function has arguments then the function's behavior on
; those arguments does not determine the function's behavior on other
; arguments.  This need not be the case.  One can constrain (thebit x)
; so that if it is 0 on some x then it is 0 on all x.
; (implies (equal (thebit x) 0) (equal (thebit y) 0))
; But this seems unlikely.

(mutual-recursion

(defun contains-constrained-constantp (term wrld)
  (cond ((variablep term) nil)
        ((fquotep term) nil)
        ((flambda-applicationp term)
         (or (contains-constrained-constantp-lst (fargs term) wrld)
             (contains-constrained-constantp (lambda-body (ffn-symb term))
                                             wrld)))
        ((and (getprop (ffn-symb term) 'constrainedp nil
                       'current-acl2-world wrld)
              (null (getprop (ffn-symb term) 'formals t
                             'current-acl2-world wrld)))
         t)
        (t (contains-constrained-constantp-lst (fargs term) wrld))))

(defun contains-constrained-constantp-lst (lst wrld)
  (cond ((null lst) nil)
        (t (or (contains-constrained-constantp (car lst) wrld)
               (contains-constrained-constantp-lst (cdr lst) wrld))))))


; So now we can define the notion of ``disvaring'' a type-alist.

(defun disvar-type-alist1 (vars type-alist wrld)
  (cond ((null type-alist) nil)
        ((or (intersectp-eq vars (all-vars (caar type-alist)))
             (contains-constrained-constantp (caar type-alist) wrld))
         (cons (car type-alist)
               (disvar-type-alist1 vars (cdr type-alist) wrld)))
        (t (disvar-type-alist1 vars (cdr type-alist) wrld))))

(defun collect-all-vars (lst)
  (cond ((null lst) nil)
        (t (cons (all-vars (car lst)) (collect-all-vars (cdr lst))))))

(defun disvar-type-alist (type-alist term wrld)

; We throw out of type-alist any binding that does not involve a
; variable linked by type-alist to those in term.  Thus, if term
; involves only the variables X and Y and type-alist binds a term that
; links Y to Z (and nothing else is linked to X, Y, or Z), then the
; resulting type-alist only binds terms containing X, Y, and/or Z.
; We actually keep entries about constrained constants.

; As we did for ``disguard'' we apologize for (but stand by) the
; non-word ``disvar.''

  (let* ((vars (all-vars term))
         (direct-links (collect-all-vars (strip-cars type-alist)))
         (vars* (linked-variables vars direct-links)))
    (disvar-type-alist1 vars* type-alist wrld)))

; Finally we can define the notion of ``unencumbering'' a type-alist.
; But as pointed out below, we no longer use this notion.

(defun unencumber-type-alist (type-alist term rewrittenp wrld)

; We wish to prove term under type-alist.  If rewrittenp is non-nil,
; it is also a term, namely the unrewritten term from which we
; obtained term.  Generally, term (actually its unrewritten version)
; is some conjunct from a guard.  In many cases we expect term to be
; something very simple like (RATIONALP X).  But chances are high that
; type- alist talks about many other variables and many irrelevant
; terms.  We wish to throw out irrelevant bindings from type-alist and
; return a new type-alist that is weaker but, we believe, as
; sufficient as the original for proving term.  We call this
; ``unencumbering'' the type-alist.

; The following paragraph is inaccurate because we no longer use
; disguarding.

; Historical Comment:
; We apply two different techniques.  The first is ``disguarding.''
; Roughly, the idea is to throw out the binding of any term that
; requires the truth of term in its guard.  Since we are trying to
; prove term true we will assume it false.  If a hypothesis in the
; type-alist requires term to get past the guard, we'll never do it.
; This is not unlikely since term is (probably) a forced guard from
; the very clause from which type-alist was created.
; End of Historical Comment

; The second technique, applied after disguarding, is to throw out any
; binding of a term that is not linked to the variables used by term.
; For example, if term is (RATIONALP X) then we won't keep a
; hypothesis about (PRIMEP Y) unless some kept hypothesis links X and
; Y.  This is called ``disvaring'' and is applied after diguarding
; because the terms thrown out by disguarding are likely to link
; variables in a bogus way.  For example, (< X Y) would link X and Y,
; but is thrown out by disguarding since it requires (RATIONALP X).
; While disvaring, we actually keep type-alist entries about constrained
; constants.

  (declare (ignore rewrittenp))
  (disvar-type-alist
   type-alist
   term
   wrld))

(defun unencumber-assumption (assn wrld)

; We no longer unencumber assumptions.  An example from Jared Davis prompted
; this change, in which he had contradictory hypotheses for which the
; contradiction was not yet evident after a round of simplification, leading to
; premature forcing -- and the contradiction was in hypotheses about variables
; irrelevant to what was forced, and hence was lost in the forcing round!  Here
; is a much simpler example of that phenomenon.

;  (defstub p1 (x) t)
;  (defstub p2 (x) t)
;  (defstub p3 (x) t)
;  (defstub p4 (x) t)
; 
;  (defaxiom p1->p2
;    (implies (p1 x)
;             (p2 x)))
; 
;  (defun foo (x y)
;    (implies x y))
; 
;  (defaxiom p3->p4{forced}
;    (implies (force (p3 x))
;             (p4 x)))
; 
;  ; When we unencumber the type-alist upon forcing, the following THM fails with
;  ; the following forcing round.  The problem is that the hypothesis about x is
;  ; dropped because it is deemed (by unencumber-type-alist) to be irrelevant to
;  ; the sole variable y of the forced hypothesis.
; 
;  ; We now undertake Forcing Round 1.
;  ; 
;  ; [1]Goal
;  ; (P3 Y).
; 
;  (thm (if (not (foo (p1 x) (p2 x)))
;           (p4 y)
;         t)
;       :hints (("Goal" :do-not '(preprocess)
;                :in-theory (disable foo))))
; 
;  ; But with unencumber-assumption defined to return its first argument, the THM
;  ; produces a forced goal that includes the contradictory hypotheses:
; 
;  ; [1]Goal
;  ; (IMPLIES (NOT (FOO (P1 X) (P2 X)))
;  ;          (P3 Y)).
; 
;  (thm (if (not (foo (p1 x) (p2 x)))
;           (p4 y)
;         t)
;       :hints (("Goal" :do-not '(preprocess)
;                :in-theory (disable foo))))

; Old comment and code:

; Given an assumption we try to unencumber (i.e., shorten) its
; :type-alist.  We return an assumption that may be proved in place of
; assn and is supposedly simpler to prove.

;   (change assumption assn
;           :type-alist
;           (unencumber-type-alist (access assumption assn :type-alist)
;                                  (access assumption assn :term)
;                                  (access assumption assn :rewrittenp)
;                                  wrld))

  (declare (ignore wrld))
  assn)

(defun unencumber-assumptions (assumptions wrld ans)

; This is just a glorified list reverse function!  At one time we actually did
; unencumber assumptions, but now, unencumber-assumption is defined simply to
; return nil, as explained in a comment in its definition.  A more elegant fix
; is to redefine the present function to return assumptions unchanged, to avoid
; consing up a reversed list.  However, we continue to reverse the input
; assumptions, for backward compatibility (otherwise forcing round goal names
; will change).  Reversing a small list is cheap, so this is not a big deal.

; Old comments:

; We unencumber every assumption in assumptions and return the
; modified list, accumulated onto ans.

; Note: This process is mentioned in :DOC forcing-round.  So if we change it,
; update the documentation.

  (cond
   ((null assumptions) ans)
   (t (unencumber-assumptions
       (cdr assumptions) wrld
       (cons (unencumber-assumption (car assumptions) wrld)
             ans)))))

; We are now concerned, for a while, with the idea of deleting from a
; set of assumptions those implied by others.  We call this
; assumption-subsumption.  Each assumption can be thought of as a goal
; of the form type-alist -> term.  Observe that if you have two
; assumptions with the same term, then the first implies the second if
; the type-alist of the second implies the type-alist of the first.
; That is,
; (thm (implies (implies ta2 ta1)
;               (implies (implies ta1 term) (implies ta2 term))))

; First we develop the idea that one type-alist implies another.

(defun dumb-type-alist-implicationp1 (type-alist1 type-alist2 seen)  
  (cond ((null type-alist1) t)
        ((member-equal (caar type-alist1) seen)
         (dumb-type-alist-implicationp1 (cdr type-alist1) type-alist2 seen))
        (t (let ((ts1 (cadar type-alist1))
                 (ts2 (or (cadr (assoc-equal (caar type-alist1) type-alist2))
                          *ts-unknown*)))
             (and (ts-subsetp ts1 ts2)
                  (dumb-type-alist-implicationp1 (cdr type-alist1)
                                            type-alist2
                                            (cons (caar type-alist1) seen)))))))

(defun dumb-type-alist-implicationp2 (type-alist1 type-alist2)  
  (cond ((null type-alist2) t)
        (t (and (assoc-equal (caar type-alist2) type-alist1)
                (dumb-type-alist-implicationp2 type-alist1
                                          (cdr type-alist2))))))

(defun dumb-type-alist-implicationp (type-alist1 type-alist2)

; NOTE: This function is intended to be dumb but fast.  One can
; imagine that we should be concerned with the types deduced by
; type-set under these type-alists.  For example, instead of asking
; whether every term bound in type-alist1 is bound to a bigger type
; set in type-alist2, we should perhaps ask whether the term has a
; bigger type-set under type-alist2.  Similarly, if we find a term
; bound in type-alist2 we should make sure that its type-set under
; type-alist1 is smaller.  If we need the smarter function we'll write
; it.  That's why we call this one "dumb."

; We say type-alist1 implies type-alist2 if (1) for every
; "significant" entry in type-alist1, (term ts1 . ttree1) it is the
; case that either term is not bound in type-alist2 or term is bound
; to some ts2 in type-alist2 and (ts-subsetp ts1 ts2), and (2) every
; term bound in type-alist2 is bound in type-alist1.  The case where
; term is not bound in type-alist2 can be seen as the natural
; treatment of the equivalent situation in which term is bound to
; *ts-unknown* in type-set2.  An entry (term ts . ttree) is
; "significant" if it is the first binding of term in the alist.

; We can treat a type-alist as a conjunction of assumptions about the
; terms it binds.  Each relevant entry gives rise to an assumption
; about its term.  Call the conjunction the "assumptions" encoded in
; the type-alist.  If type-alist1 implies type-alist2 then the
; assumptions of the first imply those of the second.  Consider an
; assumption of the first.  It restricts its term to some type.  But
; the corresponding assumption about term in the second type-alist
; restricts term to a larger type.  Thus, each assumption of the first
; type-alist implies the corresponding assumption of the second.

; The end result of all of this is that if you need to prove some
; condition, say g, under type-alist1 and also under type-alist2, and
; you can determine that type-alist1 implies type-alist2, then it is
; sufficient to prove g under type-alist2.

; Here is an example.  Let type-alist1 be
;   ((x *ts-t*)      (y *ts-integer*) (z *ts-symbol*))
; and type-alist2 be
;   ((x *ts-boolean*)(y *ts-rational*)).

; Observe that type-alist1 implies type-alist2: *ts-t* is a subset of
; *ts- boolean*, *ts-integer* is a subset of *ts-rational*, and
; *ts-symbol* is a subset of *ts-unknown*, and there are no terms
; bound in type-alist2 that aren't bound in type-alist1.  If we needed
; to prove g under both of these type-alists, it would suffice to
; prove it under type-alist2 (the weaker) because we must ultimately
; prove g under type-alist2 and the proof of g under type-alist1
; follows from that for free.

; Observe also that if we added to type-alist2 the binding (u
; *ts-cons*) then condition (1) of our definition still holds but (2)
; does not.  Further, if we mistakenly regarded type-alist2 as the
; weaker then proving (consp u) under type-alist2 would not ensure a
; proof of (consp u) under type-alist1.

  (and (dumb-type-alist-implicationp1 type-alist1 type-alist2 nil)
       (dumb-type-alist-implicationp2 type-alist1 type-alist2)))

; Now we arrange to partition a bunch of assumptions into pots
; according to their :terms, so we can do the type-alist implication
; work just on those assumptions that share a :term.

(defun partition-according-to-assumption-term (assumptions alist)

; We partition assumptions into pots, where the assumptions in a
; single pot all share the same :term.  The result is an alist whose
; keys are the :terms and whose values are the assumptions which have
; those terms.

  (cond ((null assumptions) alist)
        (t (partition-according-to-assumption-term
            (cdr assumptions)
            (put-assoc-equal
             (access assumption (car assumptions) :term)
             (cons (car assumptions)
                   (cdr (assoc-equal
                         (access assumption (car assumptions) :term)
                         alist)))
             alist)))))

; So now imagine we have a bunch of assumptions that share a term.  We
; want to delete from the set any whose type-alist implies any one
; kept.  See dumb-keep-assumptions-with-weakest-type-alists.

(defun exists-assumption-with-weaker-type-alist (assumption assumptions i)

; If there is an assumption, assn, in assumptions whose type-alist is
; implied by that of the given assumption, we return (mv pos assn),
; where pos is the position in assumptions of the first such assn.  We
; assume i is the position of the first assumption in assumptions.
; Otherwise we return (mv nil nil).

  (cond
   ((null assumptions) (mv nil nil))
   ((dumb-type-alist-implicationp
     (access assumption assumption :type-alist)
     (access assumption (car assumptions) :type-alist))
    (mv i (car assumptions)))
   (t (exists-assumption-with-weaker-type-alist assumption
                                                (cdr assumptions)
                                                (1+ i)))))

(defun add-assumption-with-weak-type-alist (assumption assumptions ans)

; We add assumption to assumptions, deleting any member of assumptions
; whose type-alist implies that of the given assumption.  When we
; delete an assumption we union its :assumnotes field into that of the
; assumption we are adding.  We accumulate our answer onto ans to keep
; this tail recursive; we presume that there will be a bunch of
; assumptions when this stuff gets going.

  (cond
   ((null assumptions) (cons assumption ans))
   ((dumb-type-alist-implicationp
     (access assumption (car assumptions) :type-alist)
     (access assumption assumption :type-alist))
    (add-assumption-with-weak-type-alist
     (change assumption assumption
             :assumnotes
             (union-equal (access assumption assumption :assumnotes)
                          (access assumption (car assumptions) :assumnotes)))
     (cdr assumptions)
     ans))
   (t (add-assumption-with-weak-type-alist assumption
                                           (cdr assumptions)
                                           (cons (car assumptions) ans)))))

(defun dumb-keep-assumptions-with-weakest-type-alists (assumptions kept)

; We return that subset of assumptions with the property that for
; every member, a, of assumptions there is one, b, among those
; returned such that (dumb-type-alist-implicationp a b).  Thus, we keep
; all the ones with the weakest hypotheses.  If we can prove all the
; ones kept, then we can prove them all, because each one thrown away
; has even stronger hypotheses than one of the ones we'll prove.
; (These comments assume that kept is initially nil and that all of
; the assumptions have the same :term.)  Whenever we throw out a in
; favor of b, we union into b's :assumnotes those of a.

  (cond
   ((null assumptions) kept)
   (t (mv-let
       (i assn)
       (exists-assumption-with-weaker-type-alist (car assumptions) kept 0)
       (cond
        (i (dumb-keep-assumptions-with-weakest-type-alists
            (cdr assumptions)
            (update-nth
             i
             (change assumption assn
                     :assumnotes
                     (union-equal
                      (access assumption (car assumptions) :assumnotes)
                      (access assumption assn :assumnotes)))
             kept)))
        (t (dumb-keep-assumptions-with-weakest-type-alists
            (cdr assumptions)
            (add-assumption-with-weak-type-alist (car assumptions)
                                                 kept nil))))))))

; And now we can write the top-level function for dumb-assumption-subsumption.

(defun dumb-assumption-subsumption1 (partitions ans)

; Having partitioned the original assumptions into pots by :term, we
; now simply clean up the cdr of each pot -- which is the list of all
; assumptions with the given :term -- and append the results of all
; the pots together.

  (cond
   ((null partitions) ans)
   (t (dumb-assumption-subsumption1
       (cdr partitions)
       (append (dumb-keep-assumptions-with-weakest-type-alists
                (cdr (car partitions))
                nil)
               ans)))))

(defun dumb-assumption-subsumption (assumptions)

; We throw out of assumptions any assumption implied by any of the others.  Our
; notion of "implies" here is quite weak, being a simple comparison of
; type-alists.  Briefly, we partition the set of assumptions into pots by :term
; and then, within each pot throw out any assumption whose type-alist is
; stronger than some other in the pot.  When we throw some assumption out in
; favor of another we combine its :assumnotes into that of the one we keep, so
; we can report the cases for which each final assumption accounts.

  (dumb-assumption-subsumption1
   (partition-according-to-assumption-term assumptions nil)
   nil))

; Now we move on to the problem of converting an unemcumbered and subsumption
; cleansed assumption into a clause to prove.

(defun clausify-type-alist (type-alist cl ens w seen ttree)

; Consider a type-alist such as
; `((x ,*ts-cons*) (y ,*ts-integer*) (z ,(ts-union *ts-rational* *ts-symbol*)))

; and some term, such as (p x y z).  We wish to construct a clause
; that represents the goal of proving the term under the assumption of
; the type-alist.  A suitable clause in this instance is
; (implies (and (consp x)
;               (integerp y)
;               (or (rationalp z) (symbolp z)))
;          (p x y z))
; We return (mv clause ttree), where clause is the clause constructed.

  (cond ((null type-alist) (mv cl ttree))
        ((member-equal (caar type-alist) seen)
         (clausify-type-alist (cdr type-alist) cl ens w seen ttree))
        (t (mv-let (term ttree)
                   (convert-type-set-to-term (caar type-alist)
                                             (cadar type-alist)
                                             ens w ttree)
                   (clausify-type-alist (cdr type-alist)
                                        (cons (dumb-negate-lit term) cl)
                                        ens w
                                        (cons (caar type-alist) seen)
                                        ttree)))))

(defun clausify-assumption (assumption ens wrld)

; We convert the assumption assumption into a clause.

; Note: If you ever change this so that the assumption :term is not the last
; literal of the clause, change the printer process-assumptions-msg1.

  (clausify-type-alist
   (access assumption assumption :type-alist)
   (list (access assumption assumption :term))
   ens
   wrld
   nil
   nil))

(defun clausify-assumptions (assumptions ens wrld pairs ttree)

; We clausify every assumption in assumptions.  We return (mv pairs ttree),
; where pairs is a list of pairs, each of the form (assumnotes . clause) where
; the assumnotes are the corresponding field of the clausified assumption.

  (cond
   ((null assumptions) (mv pairs ttree))
   (t (mv-let (clause ttree1)
              (clausify-assumption (car assumptions) ens wrld)
              (clausify-assumptions
               (cdr assumptions)
               ens wrld
               (cons (cons (access assumption (car assumptions) :assumnotes)
                           clause)
                     pairs)
               (cons-tag-trees ttree1 ttree))))))

(defun strip-assumption-terms (lst)

; Given a list of assumptions, return the set of their terms.

  (cond ((endp lst) nil)
        (t (add-to-set-equal (access assumption (car lst) :term)
                             (strip-assumption-terms (cdr lst))))))

(defun extract-and-clausify-assumptions (cl ttree only-immediatep ens wrld)

; WARNING: This function is overloaded.  Only-immediatep can take only only two
; values in this function: 'non-nil or nil.  The interpretation is as in
; collect-assumptions.  Cl is irrelevant if only-immediatep is nil.  We always
; return four results.  But when only-immediatep = 'non-nil, the first and part
; of the third result are irrelevant.  We know that only-immediatep = 'non-nil
; is used only in waterfall-step to do CASE-SPLITs and immediate FORCEs.  We
; know that only-immediatep = nil is used for forcing-round applications and in
; the proof checker.  When CASE-SPLIT type assumptions are collected with
; only-immediatep = nil, then they are given the semantics of FORCE rather
; than CASE-SPLIT.  This could happen in the proof checker, but it is thought
; not to happen otherwise.

; In the case that only-immediatep is nil: we strip all assumptions out of
; ttree, obtaining an assumption-free ttree, ttree'.  We then cleanup the
; assumptions, by removing subsumed ones.  (Formerly we also unencumbered their
; type-alists of presumed irrelevant bindings first, but we no longer do so;
; see unencumber-assumption.)  We then convert each kept assumption into a
; clause encoding the implication from the cleaned up type-alist to the
; assumed term.  We pair each clause with the :assumnotes of the assumptions
; for which it accounts, to produce a list of pairs, which is among the things
; we return.  Each pair is of the form (assumnotes . clause).  We return four
; results, (mv n a pairs ttree'), where n is the number of assumptions in the
; tree, a is the cleaned up assumptions we have to prove, whose length is the
; same as the length of pairs.

; In the case that only-immediatep is 'non-nil: we strip out of ttree only
; those assumptions with non-nil :immediatep flags.  As before, we generate a
; clause for each, but those with :immediatep = 'case-split we handle
; differently now: the clause for such an assumption is the one that encodes
; the implication from the negation of cl to the assumed term, rather than the
; one involving the type-alist of the assumption.  The assumnotes paired with
; such a clause is nil.  We do not really care about the assumnotes in
; case-splits or immediatep = t cases (e.g., they are ignored by the
; waterfall-step processing).  The final ttree, ttree', may still contain
; non-immediatep assumptions.

; To keep the definition simpler, we split into just the two cases outlined
; above.

  (cond
   ((eq only-immediatep nil)
    (let* ((raw-assumptions (collect-assumptions ttree only-immediatep nil))
           (cleaned-assumptions (dumb-assumption-subsumption
                                 (unencumber-assumptions raw-assumptions
                                                         wrld nil))))
      (mv-let
       (pairs ttree1)
       (clausify-assumptions cleaned-assumptions ens wrld nil nil)

; We check below that ttree1 is 'assumption free, so that when we add it to the
; result of cleansing 'assumptions from ttree we get an assumption-free ttree.
; If ttree1 contains assumptions we believe it must be because the bottom-most
; generator of those ttrees, namely convert-type-set-to-term, was changed to
; force assumptions.  But if that happens, we will have to rethink a lot here.
; How can we ensure that we get rid of all assumptions if we make assumptions
; while trying to express our assumptions as clauses?

       (mv (length raw-assumptions)
           cleaned-assumptions
           pairs
           (cons-tag-trees
            (cond
             ((tagged-object 'assumption ttree1)
              (er hard 'extract-and-clausify-assumptions
                  "Convert-type-set-to-term apparently returned a ttree that ~
                   contained an 'assumption tag.  This violates the ~
                   assumption in this function."))
             (t ttree1))
            (delete-assumptions ttree only-immediatep))))))
   ((eq only-immediatep 'non-nil)
    (let* ((assumed-terms
            (strip-assumption-terms
             (collect-assumptions ttree 'case-split nil)))
           (case-split-clauses (split-on-assumptions assumed-terms cl nil))
           (case-split-pairs (pairlis2 nil case-split-clauses))
           (raw-assumptions (collect-assumptions ttree t nil))
           (cleaned-assumptions (dumb-assumption-subsumption
                                 (unencumber-assumptions raw-assumptions
                                                         wrld nil))))
      (mv-let
       (pairs ttree1)
       (clausify-assumptions cleaned-assumptions ens wrld nil nil)

; We check below that ttree1 is 'assumption free, so that when we add it to the
; result of cleansing 'assumptions from ttree we get an assumption-free ttree.
; If ttree1 contains assumptions we believe it must be because the bottom-most
; generator of those ttrees, namely convert-type-set-to-term, was changed to
; force assumptions.  But if that happens, we will have to rethink a lot here.
; How can we ensure that we get rid of all assumptions if we make assumptions
; while trying to express our assumptions as clauses?

       (mv 'ignored
           assumed-terms
           (append case-split-pairs pairs)
           (cons-tag-trees
            (cond
             ((tagged-object 'assumption ttree1)
              (er hard 'extract-and-clausify-assumptions
                  "Convert-type-set-to-term apparently returned a ttree that ~
                   contained an 'assumption tag.  This violates the assumption ~
                   in this function."))
             (t ttree1))
            (delete-assumptions ttree 'non-nil))))))
   (t (mv 0 nil
          (er hard 'extract-and-clausify-assumptions
              "We only implemented two cases for only-immediatep:  'non-nil ~
               and nil.  But you now call it on ~p0."
              only-immediatep)
          nil))))

; Finally, we put it all together in the primitive function that
; applies a processor to a clause.

(defun waterfall-step1 (processor cl-id clause hist pspv wrld state step-limit)

; Note that apply-top-hints-clause is handled in waterfall-step.

  (case processor
    (simplify-clause
     (pstk
      (simplify-clause clause hist pspv wrld state step-limit)))
    (preprocess-clause
     (pstk
      (preprocess-clause clause hist pspv wrld state step-limit)))
    (otherwise
     (prepend-step-limit
      4
      (case processor
        (settled-down-clause
         (pstk
          (settled-down-clause clause hist pspv wrld state)))
        (eliminate-destructors-clause
         (pstk
          (eliminate-destructors-clause clause hist pspv wrld state)))
        (fertilize-clause
         (pstk
          (fertilize-clause cl-id clause hist pspv wrld state)))
        (generalize-clause
         (pstk
          (generalize-clause clause hist pspv wrld state)))
        (eliminate-irrelevance-clause
         (pstk
          (eliminate-irrelevance-clause clause hist pspv wrld state)))
        (otherwise
         (pstk
          (push-clause clause hist pspv wrld state))))))))

(defun waterfall-step-cleanup (processor cl-id clause hist wrld state
                                         signal
                                         clauses
                                         ttree
                                         new-pspv
                                         step-limit)

; Signal here can be either some form of HIT (hit, hit-rewrite,
; hit-rewrite2, or-hit) or ABORT.

; Imagine that the indicated waterfall processor produced some form of
; hit and returned signal, clauses, ttree, and new-pspv.  We have to
; do certain cleanup on these things (e.g., add cl-id to all the
; assumnotes) and we do all that cleanup here.

; The actual cleanup is
; (1) add the cl-id to each assumnote in ttree
; (2) accumulate the modified ttree into state
; (3) extract the assumptions we are to handle immediately
; (4) compute the resulting case splits and modify clauses appropriately
; (5) make a new history entry 
; (6) adjust signal to account for a specious application

; The result is (mv signal' clauses' ttree' hist' pspv' state) where
; each of the primed things are (possibly) modifications of their
; input counterparts.

; Here is blow-by-blow description of the cleanup.

; We update the :cl-id field (in the :assumnote) of every 'assumption.
; We accumulate the modified ttree into state.

  (mv-let
   (erp ttree state)
   (accumulate-ttree-and-step-limit-into-state
    (set-cl-ids-of-assumptions ttree cl-id)
    step-limit
    state)
   (declare (ignore erp))

; We extract the assumptions we are to handle immediately.

   (mv-let
    (n assumed-terms pairs ttree)
    (extract-and-clausify-assumptions
     clause
     ttree
     'non-nil ; collect CASE-SPLIT and immediate FORCE assumptions
     (access rewrite-constant
             (access prove-spec-var new-pspv :rewrite-constant)
             :current-enabled-structure)
     wrld)
    (declare (ignore n))

; Note below that we throw away the cars of the pairs, which are
; typically assumnotes.  We keep only the clauses themselves.
; We perform the required splitting, augmenting the previously
; generated clauses with the assumed terms.

    (let* ((split-clauses (strip-cdrs pairs))
           (clauses
            (if (and (null split-clauses)
                     (null assumed-terms)
                     (member-eq processor
                                '(preprocess-clause
                                  apply-top-hints-clause)))
                clauses
              (remove-trivial-clauses
               (union-equal split-clauses
                            (disjoin-clause-segment-to-clause-set
                             (dumb-negate-lit-lst assumed-terms)
                             clauses))
               wrld)))

; We create the history entry for this step.  We have to be careful about
; specious hits to prevent a loop described below.

           (new-hist
            (cons (make history-entry
                        :signal signal ; indicating the type of "hit"
                        :processor
                        
; We here detect specious behavior.  The basic idea is that a hit
; is specious if the input clause is among the output clauses.  But
; there are two exceptions: when the process is settled-down-clause or
; apply-top-hints-clause, such apparently specious output is ok.
; We mark a specious hit by setting the :processor of the history-entry
; to the cons (SPECIOUS . processor).
                        
                        (if (and (not (member-eq
                                       processor
                                       '(settled-down-clause

; The obvious example of apparently specious behavior by
; apply-top-hints-clause that is not really specious is when it signals
; an OR-HIT and returns the input clause (to be processed by further hints).
; But the inclusion of apply-top-hints-clause in this list of exceptions
; was originally made in Version_2.7 because of :by hints.  Consider
; what happens when a :by hint produces a subgoal that is identical to the
; current goal.  If the subgoal is labeled as 'SPECIOUS, then we will 'MISS
; below.  This was causing the waterfall to apply the :by hint a second time,
; resulting in output such as the following:

;  As indicated by the hint, this goal is subsumed by (EQUAL (F1 X) (F0 X)),
;  which can be derived from LEMMA1 via functional instantiation, provided
;  we can establish the constraint generated.
; 
;  As indicated by the hint, this goal is subsumed by (EQUAL (F1 X) (F0 X)),
;  which can be derived from LEMMA1 via functional instantiation, provided
;  we can establish the constraint generated.

; The following example reproduces the above output.  The top-level hints
; (i.e., *top-hint-keywords*) should never be 'SPECIOUS anyhow, because the
; user will more than likely prefer to see the output before the proof
; (probably) fails.

; (defstub f0 (x) t)
; (defstub f1 (x) t)
; (defstub f2 (x) t)
;
; (defaxiom lemma1
;   (equal (f2 x) (f1 x)))
;
; (defthm main
;   (equal (f1 x) (f0 x))
;   :hints (("Goal" :by (:functional-instance lemma1 (f2 f1) (f1 f0)))))

                                         apply-top-hints-clause)))
                                 (member-equal clause clauses))
                            (cons 'SPECIOUS processor)
                          processor)
                        :clause clause
                        :ttree ttree)
                  hist)))
      (cond
       ((consp (access history-entry ; (SPECIOUS . processor)
                       (car new-hist) :processor))
        (mv 'MISS nil ttree new-hist nil state))
       (t (mv signal clauses ttree new-hist
              (put-ttree-into-pspv ttree new-pspv)
              state)))))))

(defun process-backtrack-hint (cl-id clause clauses processor new-hist new-pspv ctx
                                     wrld state)

; A step of the indicated clause with cl-id through the waterfall, via
; waterfall-step, has tentatively returned the indicated clauses, new-hist, and
; new-pspv.  If the original pspv contains a :backtrack hint-setting, we replace
; the hint-settings with the computed hint that it specifies.

  (let ((backtrack-hint (cdr (assoc-eq :backtrack
                                       (access prove-spec-var new-pspv
                                               :hint-settings)))))
    (cond
     (backtrack-hint
      (assert$
       (eq (car backtrack-hint) 'eval-and-translate-hint-expression)
       (mv-let
        (erp val state)
        (eval-and-translate-hint-expression
         (cdr backtrack-hint) ; tuple of the form (name-tree flg term)
         cl-id clause wrld
         :OMITTED ; stable-under-simplificationp, unused in :backtrack hints
         new-hist new-pspv clauses processor
         :OMITTED ; keyword-alist, unused in :backtrack hints
         'backtrack (override-hints wrld) ctx state)
        (cond (erp (mv t nil nil state))
              ((assert$ (listp val)
                        (eq (car val) :computed-hint-replacement))
               (mv nil
                   (cddr val)
                   (assert$ (consp (cdr val))
                            (case (cadr val)
                              ((t) (list backtrack-hint))
                              ((nil) nil)
                              (otherwise (cadr val))))
                   state))
              (t (mv nil val nil state))))))
     (t (mv nil nil nil state)))))

(defun waterfall-step (processor cl-id clause hist pspv wrld ctx state
                                 step-limit)

; Processor is one of the known waterfall processors.  This function applies
; processor and returns six results: signal, clauses, new-hist, new-pspv,
; jppl-flg, and state.

; All processor functions take as input a clause, its hist, a pspv, wrld, and
; state.  They all deliver four values: a signal, some clauses, a ttree, and a
; new pspv.  The signal delivered by such processors is one of 'error, 'miss,
; 'abort, or else indicates a "hit" via the signals 'hit, 'hit-rewrite,
; 'hit-rewrite2 and 'or-hit.  We identify the first three kinds of hits.
; 'Or-hits indicate that a set of disjunctive branches has been produced.

; If the returned signal is 'error or 'miss, we immediately return with that
; signal.  But if the signal is a "hit" or 'abort (which in this context means
; "the processor did something but it has demanded the cessation of the
; waterfall process"), we add a new history entry to hist, store the ttree into
; the new pspv, print the message associated with this processor, and then
; return.

; When a processor "hit"s, we check whether it is a specious hit, i.e., whether
; the input is a member of the output.  If so, the history entry for the hit is
; marked specious by having the :processor field '(SPECIOUS . processor).
; However, we report the step as a 'miss, passing back the extended history to
; be passed.  Specious processors have to be recorded in the history so that
; waterfall-msg can detect that they have occurred and not reprint the formula.
; Mild Retraction: Actually, settled-down-clause always produces
; specious-appearing output but we never mark it as 'SPECIOUS because we want
; to be able to assoc for settled-down-clause and we know it's specious anyway.

; We typically return (mv signal clauses new-hist new-pspv jppl-flg state).

; Signal             Meaning

; 'error         Halt the entire proof attempt with an error.  We
;                print out the error message to the returned state.
;                In this case, clauses, new-hist, new-pspv, and jppl-flg
;                are all irrelevant (and nil).

; 'miss          The processor did not apply or was specious.  Clauses,
;                new-pspv, and jppl-flg are irrelevant and nil.  But
;                new-hist has the specious processor recorded in it.
;                State is unchanged.

; 'abort         Like a "hit", except that we are not to continue with
;                the waterfall.  We are to use the new pspv as the
;                final pspv produced by the waterfall.

; 'hit           The processor applied and produced the new set of
; 'hit-rewrite   clauses returned.  The appropriate new history and
; 'hit-rewrite2  new pspv are returned.  Jppl-flg is either nil
;                (indicating that the processor was not push-clause)
;                or is a pool lst (indicating that a clause was pushed
;                and assigned that lst).  The jppl-flg of the last executed
;                processor should find its way out of the waterfall so
;                that when we get out and pop a clause we know if we
;                just pushed it.  Finally, the message describing the
;                transformation has been printed to state.

; 'or-hit        The processor applied and has requested a disjunctive
;                split determined by hints.  The results are actually
;                the same as for 'hit.  The processor did not actually
;                produce the case split because some of the hints
;                (e.g., :in-theory) are related to the environment
;                in which we are to process the clause rather than the
;                clause itself.

; 'top-of-waterfall-hint
;                A :backtrack hint was applicable, and suitable results are
;                returned for handling it.

  (sl-let
   (erp signal clauses ttree new-pspv state)
   (catch-time-limit5
    (cond ((eq processor 'apply-top-hints-clause) ; this case returns state
           (apply-top-hints-clause cl-id clause hist pspv wrld ctx state
                                   step-limit))
          (t
           (sl-let
            (signal clauses ttree new-pspv)
            (waterfall-step1 processor cl-id clause hist pspv wrld state
                             step-limit)
            (mv step-limit signal clauses ttree new-pspv state)))))
   (cond
    (erp ; from out-of-time or clause-processor failure; treat as 'error signal
     (mv-let (erp val state)
             (er soft ctx "~@0" erp)
             (declare (ignore erp val))
             (mv step-limit 'error nil nil nil nil state)))
    (t
     (pprogn ; account for bddnote in case we do not have a hit
      (cond ((and (eq processor 'apply-top-hints-clause)
                  (member-eq signal '(error miss))
                  ttree) ; a bddnote; see bdd-clause
             (f-put-global 'bddnotes
                           (cons ttree
                                 (f-get-global 'bddnotes state))
                           state))
            (t state))
      (prepend-step-limit
       (signal clauses new-hist new-pspv jppl-flg state)
       (cond ((eq signal 'error)

; As of this writing, the only processor which might cause an error is
; apply-top-hints-clause.  But processors can't actually cause errors in the
; error/value/state sense because they don't return state and so can't print
; their own error messages.  We therefore make the convention that if they
; signal error then the "clauses" value they return is in fact a pair
; (fmt-string . alist) suitable for giving error1.  Moreover, in this case
; ttree is an alist assigning state global variables to values.

              (mv-let (erp val state)
                      (error1 ctx (car clauses) (cdr clauses) state)
                      (declare (ignore erp val))
                      (mv 'error nil nil nil nil state)))
             ((eq signal 'miss)
              (mv 'miss nil hist nil nil state))
             (t
              (mv-let
               (signal clauses ttree new-hist new-pspv state)
               (waterfall-step-cleanup processor cl-id clause hist wrld state
                                       signal clauses ttree new-pspv
                                       step-limit)
               (mv-let
                (erp new-hint-settings new-hints state)
                (cond
                 ((or (eq signal 'miss)                   ; presumably specious
                      (eq processor 'settled-down-clause)) ; not user-visible
                  (mv nil nil nil state))
                 (t (process-backtrack-hint cl-id clause clauses processor
                                            new-hist new-pspv ctx wrld state)))
                (cond
                 (erp
                  (mv 'error nil nil nil nil state))
                 (new-hint-settings
                  (mv 'top-of-waterfall-hint
                      new-hint-settings
                      processor
                      :pspv-for-backtrack
                      new-hints
                      state))
                 (t
                  (mv-let
                   (jppl-flg new-pspv state)
                   (waterfall-msg processor
                                  cl-id clause signal clauses new-hist ttree
                                  new-pspv state)
                   (mv signal clauses new-hist new-pspv jppl-flg
                       state))))))))))))))

; Section:  FIND-APPLICABLE-HINT-SETTINGS

; Here we develop the code that recognizes that some user-supplied
; hint settings are applicable and we develop the routine to use
; hints.  It all comes together in waterfall1.

(defun find-applicable-hint-settings1
  (cl-id clause hist pspv ctx hints hints0 wrld stable-under-simplificationp
         override-hints state)

; See translate-hints1 for "A note on the taxonomy of hints", which explains
; hint settings.  Relevant background is also provided by :doc topic
; hints-and-the-waterfall, which links to :doc override-hints (also providing
; relevant background).

; We scan down hints looking for the first one that matches cl-id and clause.
; If we find none, we return nil.  Otherwise, we return a pair consisting of
; the corresponding hint-settings and hints0 modified as directed by the hint
; that was applied.  By "match" here, of course, we mean either

; (a) the hint is of the form (cl-id . hint-settings), or

; (b) the hint is of the form (eval-and-translate-hint-expression name-tree flg
; term) where term evaluates to a non-erroneous non-nil value when ID is bound
; to cl-id, CLAUSE to clause, WORLD to wrld, STABLE-UNDER-SIMPLIFICATIONP to
; stable-under-simplificationp, HIST to hist, PSPV to pspv, CTX to ctx, and
; STATE to state.  In this case the corresponding hint-settings is the
; translated version of what the term produced.  We know that term is
; single-threaded in state and returns an error triple.

; This function is responsible for interpreting computed hints, including the
; meaning of the :computed-hint-replacement keyword.  It also deals
; appropriately with override-hints.  Note that override-hints is
; (override-hints wrld).

; Stable-under-simplificationp is t when the clause has been found not to
; change when simplified.  In particular, it is t if we are about to transition
; to destructor elimination.

; Optimization: By convention, when this function is called with
; stable-under-simplificationp = t, we know that the function returned nil when
; called earlier with the change: stable-under-simplificationp = nil.  That is,
; if we know the clause is stable under simplification, then we have already
; tried and failed to find an applicable hint for it before we knew it was
; stable.  So when stable-under-simplificationp is t, we avoid some work and
; just eval those hints that might be sensitive to
; stable-under-simplificationp.  The flg component of (b)-style hints indicates
; whether the term contains the free variable stable-under-simplificationp.

  (cond ((null hints)
         (cond ((or (null override-hints) ; optimization for common case
                    stable-under-simplificationp) ; avoid loop
                (value nil))
               (t ; no applicable hint-settings, so apply override-hints to nil
                (er-let*
                 ((new-keyword-alist
                   (apply-override-hints
                    override-hints cl-id clause hist pspv ctx wrld
                    stable-under-simplificationp
                    :OMITTED ; clause-list
                    :OMITTED ; processor
                    nil ; keyword-alist
                    state))
                  (pair (cond (new-keyword-alist
                               (translate-hint
                                'override-hints ; name-tree
                                (cons (string-for-tilde-@-clause-id-phrase cl-id)
                                      new-keyword-alist)
                                nil ; hint-type
                                ctx wrld state))
                              (t (value nil)))))
                 (value (cond (pair (cons (cdr pair) hints0))
                              (t nil)))))))
        ((eq (car (car hints)) 'eval-and-translate-hint-expression)
         (cond
          ((and stable-under-simplificationp
                (not (caddr (car hints)))) ; flg
           (find-applicable-hint-settings1
            cl-id clause hist pspv ctx (cdr hints) hints0 wrld
            stable-under-simplificationp override-hints state))
          (t
           (er-let*
            ((hint-settings

; The following call applies the override-hints to the computed hint.

              (eval-and-translate-hint-expression
               (cdr (car hints))
               cl-id clause wrld
               stable-under-simplificationp hist pspv
               :OMITTED ; clause-list
               :OMITTED ; processor
               :OMITTED ; keyword-alist
               nil
               override-hints
               ctx state)))
            (cond
             ((null hint-settings)
              (find-applicable-hint-settings1
               cl-id clause hist pspv ctx (cdr hints) hints0 wrld
               stable-under-simplificationp override-hints state))
             ((eq (car hint-settings) :COMPUTED-HINT-REPLACEMENT)
              (value
               (cond
                ((eq (cadr hint-settings) nil)
                 (cons (cddr hint-settings)
                       (remove1-equal (car hints) hints0)))
                ((eq (cadr hint-settings) t)
                 (cons (cddr hint-settings)
                       hints0))
                (t (cons (cddr hint-settings)
                         (append (cadr hint-settings)
                                 (remove1-equal (car hints) hints0)))))))
             (t (value (cons hint-settings
                             (remove1-equal (car hints) hints0)))))))))
        ((and (not stable-under-simplificationp)
              (consp (car hints))
              (equal (caar hints) cl-id))
         (cond ((null override-hints)
                (value (cons (cdar hints)
                             (remove1-equal (car hints) hints0))))

; Override-hints is (override-hints wrld).  If override-hints is non-nil, then
; we originally translated the hint as (list* cl-id (:KEYWORD-ALIST
; . keyword-alist) (:NAME-TREE . name-tree) . hint-settings.  We apply the
; override-hints to get a new keyword-alist.  If the keyword-alist has not
; changed, then hint-settings is still the correct translation.  Otherwise, we
; need to translate the new keyword-alist.  The result could be a computed
; hint, in which case we simply replace the hint with that computed hint and
; call this function recursively.  But if the result is not a computed hint,
; then it is a fully-translated hint with the same clause-id, and we have our
; result.

               ((not (let ((hint-settings (cdar hints)))
                       (and (consp hint-settings)
                            (consp (car hint-settings))
                            (eq (car (car hint-settings))
                                :KEYWORD-ALIST)
                            (consp (cdr hint-settings))
                            (consp (cadr hint-settings))
                            (eq (car (cadr hint-settings))
                                :NAME-TREE))))
                (er soft ctx
                    "Implementation error: With override-hints present, we ~
                     expected an ordinary translated hint-settings to start ~
                     with ((:KEYWORD-ALIST . keyword-alist) (:NAME-TREE . ~
                     name-tree)) but instead the translated hint-settings ~
                     was ~x0.  Please contact the ACL2 implementors."
                    (cdar hints)))
               (t
                (let* ((full-hint-settings (cdar hints))
                       (keyword-alist (cdr (car full-hint-settings)))
                       (name-tree (cdr (cadr full-hint-settings)))
                       (hint-settings (cddr full-hint-settings)))
                  (er-let*
                   ((new-keyword-alist
                     (apply-override-hints
                      override-hints cl-id clause hist pspv ctx wrld
                      stable-under-simplificationp
                      :OMITTED ; clause-list
                      :OMITTED ; processor
                      keyword-alist
                      state))
                    (hint-settings
                     (cond
                      ((equal new-keyword-alist keyword-alist)
                       (value hint-settings))
                      ((null new-keyword-alist) ; optimization
                       (value nil))
                      (t (er-let*
                          ((pair (translate-hint
                                  name-tree
                                  (cons (string-for-tilde-@-clause-id-phrase
                                         cl-id)
                                        new-keyword-alist)
                                  nil ; hint-type
                                  ctx wrld state)))
                          (assert$ (equal (car pair) cl-id)
                                   (value (cdr pair))))))))
                   (value (cond ((null new-keyword-alist)
                                 nil)
                                (t (cons hint-settings
                                         (remove1-equal (car hints) hints0))))))))))
        (t (find-applicable-hint-settings1
            cl-id clause hist pspv ctx (cdr hints) hints0 wrld
            stable-under-simplificationp override-hints state))))

(defun find-applicable-hint-settings (cl-id clause hist pspv ctx hints wrld
                                            stable-under-simplificationp state)

; First, we find the applicable hint-settings (with
; find-applicable-hint-settings1) from the explicit and computed hints.  Then,
; we modify those hint-settings by using the override-hints; see :DOC
; override-hints.

  (find-applicable-hint-settings1 cl-id clause hist pspv ctx hints hints wrld
                                  stable-under-simplificationp
                                  (override-hints wrld)
                                  state))

(defun alist-keys-subsetp (x keys)
  (cond ((endp x) t)
        ((member-eq (caar x) keys)
         (alist-keys-subsetp (cdr x) keys))
        (t nil)))

(defun thanks-for-the-hint (goal-already-printed-p hint-settings state)

; This function prints the note that we have noticed the hint.  We have to
; decide whether the clause to which this hint was attached was printed out
; above or below us.  We return state.  Goal-already-printed-p is either t,
; nil, or a pair (cons :backtrack processor) where processor is a member of
; *preprocess-clause-ledge*.

  (cond ((cdr (assoc-eq :no-thanks hint-settings))
         (mv (delete-assoc-eq :no-thanks hint-settings) state))
        ((alist-keys-subsetp hint-settings '(:backtrack))
         (mv hint-settings state))
        (t
         (pprogn (io?-prove
                  (goal-already-printed-p)
                  (fms "[Note:  A hint was supplied for our processing of the ~
                        goal ~#0~[above~/below~/above, provided by a ~
                        :backtrack hint superseding ~@1~].  Thanks!]~%"
                       (list
                        (cons
                         #\0
                         (case goal-already-printed-p
                           ((t) 0)
                           ((nil) 1)
                           (otherwise 2)))
                        (cons
                         #\1
                         (and (consp goal-already-printed-p)
                              (case (cdr goal-already-printed-p)
                                (apply-top-hints-clause
                                 "the use of a :use, :by, :cases, :bdd, ~
                                  :clause-processor, or :or hint")
                                (preprocess-clause
                                 "preprocessing (the use of simple rules)")
                                (simplify-clause
                                 "simplification")
                                (eliminate-destructors-clause
                                 "destructor elimination")
                                (fertilize-clause
                                 "the heuristic use of equalities")
                                (generalize-clause
                                 "generalization")
                                (eliminate-irrelevance-clause
                                 "elimination of irrelevance")
                                (push-clause
                                 "the use of induction")
                                (otherwise
                                 (er hard 'thanks-for-the-hint
                                     "Implementation error: Unrecognized ~
                                      processor, ~x0."
                                     (cdr goal-already-printed-p)))))))
                       (proofs-co state)
                       state
                       nil))
                 (mv hint-settings state)))))

; We now develop the code for warning users about :USEing enabled
; :REWRITE and :DEFINITION rules.

(defun lmi-name-or-rune (lmi)

; See also lmi-seed, which is similar except that it returns a base
; symbol where we are happy to return a rune, and when it returns a
; term we return nil.

  (cond ((atom lmi) lmi)
        ((eq (car lmi) :theorem) nil)
        ((or (eq (car lmi) :instance)
             (eq (car lmi) :functional-instance))
         (lmi-name-or-rune (cadr lmi)))
        (t lmi)))

(defun enabled-lmi-names1 (ens pairs)

; Pairs is the runic-mapping-pairs for some symbol, and hence each of
; its elements looks like (nume . rune).  We collect the enabled
; :definition and :rewrite runes from pairs.

  (cond
   ((null pairs) nil)
   ((and (or (eq (cadr (car pairs)) :definition)
             (eq (cadr (car pairs)) :rewrite))
         (enabled-numep (car (car pairs)) ens))
    (add-to-set-equal (cdr (car pairs))
                      (enabled-lmi-names1 ens (cdr pairs))))
   (t (enabled-lmi-names1 ens (cdr pairs)))))

(defun enabled-lmi-names (ens lmi-lst wrld)

  (cond
   ((null lmi-lst) nil)
   (t (let ((x (lmi-name-or-rune (car lmi-lst))))

; x is either nil, a name, or a rune

        (cond
         ((null x)
          (enabled-lmi-names ens (cdr lmi-lst) wrld))
         ((symbolp x)
          (union-equal (enabled-lmi-names1
                        ens
                        (getprop x 'runic-mapping-pairs nil
                                 'current-acl2-world wrld))
                       (enabled-lmi-names ens (cdr lmi-lst) wrld)))
         ((enabled-runep x ens wrld)
          (add-to-set-equal x (enabled-lmi-names ens (cdr lmi-lst) wrld)))
         (t (enabled-lmi-names ens (cdr lmi-lst) wrld)))))))

(defun maybe-warn-for-use-hint (pspv ctx wrld state)
  (cond
   ((warning-disabled-p "Use")
    state)
   (t
    (let ((enabled-lmi-names
           (enabled-lmi-names
            (access rewrite-constant
                    (access prove-spec-var pspv :rewrite-constant)
                    :current-enabled-structure)
            (cadr (assoc-eq :use
                            (access prove-spec-var pspv :hint-settings)))
            wrld)))
      (cond
       (enabled-lmi-names
        (warning$ ctx ("Use")
                  "It is unusual to :USE an enabled :REWRITE or :DEFINITION ~
                   rule, so you may want to consider disabling ~&0."
                  enabled-lmi-names))
       (t state))))))

(defun maybe-warn-about-theory-simple (ens1 ens2 ctx wrld state)

; We may use this function instead of maybe-warn-about-theory when we know that
; ens1 contains a compressed theory array (and so does ens2, but that should
; always be the case).

  (let ((force-xnume-en1 (enabled-numep *force-xnume* ens1))
        (imm-xnume-en1 (enabled-numep *immediate-force-modep-xnume* ens1)))
    (maybe-warn-about-theory ens1 force-xnume-en1 imm-xnume-en1 ens2
                             ctx wrld state)))

(defun maybe-warn-about-theory-from-rcnsts (rcnst1 rcnst2 ctx ens wrld state)
  (declare (ignore ens))
  (let ((ens1 (access rewrite-constant rcnst1 :current-enabled-structure))
        (ens2 (access rewrite-constant rcnst2 :current-enabled-structure)))
    (cond
     ((equal (access enabled-structure ens1 :array-name)
             (access enabled-structure ens2 :array-name))

; We want to avoid printing a warning in those cases where we have not really
; created a new enabled structure.  In this case, the enabled structures could
; still in principle be different, in which case we are missing some possible
; warnings.  In practice, this function is only called when ens2 is either
; identical to ens1 or is created from ens1 by a call of
; load-theory-into-enabled-structure that creates a new array name, in which
; case the eql test above will fail.

; Warning: Through Version_4.1 we compared :array-name-suffix fields.  But now
; that the waterfall can be parallelized, the suffix might not change when we
; install a new theory array; consider load-theory-into-enabled-structure in
; the case that its incrmt-array-name-info argument is a clause-id.

      state)
     (t

; The new theory is being constructed from the user's hint and the ACL2 world.
; The most coherent thing to do is contruct the warning in an analogous manner,
; which is why we use ens below rather than ens1.

      (maybe-warn-about-theory-simple ens1 ens2 ctx wrld state)))))

(defun waterfall-print-clause-body (cl-id clause state)
  (pprogn
   (increment-timer 'prove-time state)
   (fms "~@0~|~q1.~|"
        (list (cons #\0 (tilde-@-clause-id-phrase cl-id))
              (cons #\1 (prettyify-clause
                         clause
                         (let*-abstractionp state)
                         (w state))))
        (proofs-co state)
        state
        (term-evisc-tuple nil state))
   (increment-timer 'print-time state)))

(defun waterfall-print-clause (suppress-print cl-id clause state)
  (cond ((or suppress-print (equal cl-id *initial-clause-id*))
         state)
        (t (pprogn
            (if (and (or (gag-mode)
                         (member-eq 'prove
                                    (f-get-global 'inhibit-output-lst state)))
                     (f-get-global 'print-clause-ids state))
                (pprogn
                 (increment-timer 'prove-time state)
                 (mv-let (col state)
                         (fmt1 "~@0~|"
                               (list (cons #\0
                                           (tilde-@-clause-id-phrase cl-id)))
                               0 (proofs-co state) state nil)
                         (declare (ignore col))
                         (increment-timer 'print-time state)))
              state)
            (io?-prove
             (cl-id clause)
             (waterfall-print-clause-body cl-id clause state))))))

; Essay on OR-HIT Messages

; When we generate an OR-HIT, we print a message saying it has
; happened and that we will sweep across the disjuncts and consider
; each in turn.  That message is printed in
; apply-top-hints-clause-msg1.

; As we sweep, we print three kinds of messages:
; a:  ``here is the next disjunct to consider''
; b:  ``this disjunct has succeeded and we won't consider the others''
; c:  ``we've finished the sweep and now we choose the best result''

; Each is printed by a waterfall-or-hit-msg- function, labeled a, b,
; or c.

(defun waterfall-or-hit-msg-a (cl-id user-hinti d-cl-id i branch-cnt state)

; We print out the message associated with one disjunctive branch.  The special
; case of when there is exactly one branch is handled by
; apply-top-hints-clause-msg1.

  (cond
   ((gag-mode)

; Suppress printing for :OR splits; see also other comments with this header.

; In the case where we are only printing for gag-mode, we want to keep the
; message short.  Our message relies on the disjunctive goal name starting with
; the word "Subgoal" so that the English is sensible.

;   (fms "---~|Considering disjunctive ~@0 of ~@1.~|"
;        (list (cons #\0 (tilde-@-clause-id-phrase d-cl-id))
;              (cons #\1 (tilde-@-clause-id-phrase cl-id)))
;        (proofs-co state)
;        state
;        nil)

    state)
   (t
    (fms "---~%~@0~%( same formula as ~@1 ).~%~%The ~n2 disjunctive branch ~
          (of ~x3) for ~@1 can be created by applying the hint:~%~y4.~%"
         (list (cons #\0 (tilde-@-clause-id-phrase d-cl-id))
               (cons #\1 (tilde-@-clause-id-phrase cl-id))
               (cons #\2 (list i))
               (cons #\3 branch-cnt)
               (cons #\4 (cons (string-for-tilde-@-clause-id-phrase d-cl-id)
                               user-hinti)))
         (proofs-co state)
         state
         nil))))

(defun waterfall-or-hit-msg-b (cl-id d-cl-id branch-cnt state)

; We print out the message that d-cl-id (and thus cl-id) has succeeded
; and that we will cut off the search through the remaining branches.

  (cond ((gag-mode)
; Suppress printing for :OR splits; see also other comments with this header.
         state)
        (t
         (fms "---~%~@0 has succeeded!  All of its subgoals have been proved ~
               (modulo any forced assumptions).  Recall that it was one of ~
               ~n1 disjunctive branches generated by the :OR hint to prove ~
               ~@2.   We therefore abandon work on the other branches.~%"
              (list (cons #\0 (tilde-@-clause-id-phrase d-cl-id))
                    (cons #\1 branch-cnt)
                    (cons #\2 (tilde-@-clause-id-phrase cl-id)))
              (proofs-co state)
              state
              nil))))

(defun tilde-*-or-hit-summary-phrase1 (summary)
  (cond
   ((endp summary) nil)
   (t (let ((cl-id (car (car summary)))
            (subgoals (cadr (car summary)))
            (difficulty (caddr (car summary))))
        (cons (msg "~@0~t1   ~c2   ~c3~%"
                   (tilde-@-clause-id-phrase cl-id)
                   20
                   (cons subgoals 5)
                   (cons difficulty 10))
              (tilde-*-or-hit-summary-phrase1 (cdr summary)))))))

(defun tilde-*-or-hit-summary-phrase (summary)

; Each element of summary is of the form (cl-id n d), where n is the
; number of subgoals pushed by the processing of cl-id and d is their
; combined difficulty.  We prepare a ~* message that will print as
; a series of lines:

; disjunct  subgoals  estimated difficulty
; cl-id1       n              d

  (list "" "~@*" "~@*" "~@*"
        (tilde-*-or-hit-summary-phrase1 summary)))

(defun waterfall-or-hit-msg-c (parent-cl-id results revert-d-cl-id cl-id summary
                                            state)

; This message is printed when we have swept all the disjunctive
; branches and have chosen cl-id as the one to pursue.  If results is
; empty, then cl-id and summary are all irrelevent (and probably nil).

  (cond
   ((null results)
    (cond
     (revert-d-cl-id
      (fms "---~%None of the branches we tried for ~@0 led to a plausible set ~
            of subgoals, and at least one, ~@1, led to the suggestion that we ~
            focus on the original conjecture.  We therefore abandon our ~
            previous work on this conjecture and reassign the name *1 to the ~
            original conjecture.  (See :DOC otf-flg.)~%"
           (list (cons #\0 (tilde-@-clause-id-phrase parent-cl-id))
                 (cons #\1 (tilde-@-clause-id-phrase revert-d-cl-id)))
           (proofs-co state)
           state
           nil))
     (t
      (fms "---~%None of the branches we tried for ~@0 led to a plausible set ~
            of subgoals.  The proof attempt has failed.~|"
           (list (cons #\0 (tilde-@-clause-id-phrase parent-cl-id)))
           (proofs-co state)
           state
           nil))))
   ((endp (cdr results))
    (fms "---~%Even though we saw a disjunctive split for ~@0, it ~
          turns out there is only one viable branch to pursue, the ~
          one named ~@1.~%"
         (list (cons #\0 (tilde-@-clause-id-phrase parent-cl-id))
               (cons #\1 (tilde-@-clause-id-phrase cl-id)))
         (proofs-co state)
         state
         nil))
   (t (let* ((temp (assoc-equal cl-id summary))
             (n (cadr temp))
             (d (caddr temp)))
      
        (fms "---~%After simplifying every branch of the disjunctive ~
              split for ~@0 we choose to pursue the branch named ~@1, ~
              which gave rise to ~x2 *-named formula~#3~[s~/~/s~] ~
              with total estimated difficulty of ~x4.  The complete ~
              list of branches considered is shown below.~%~%~
              clause id              subgoals    estimated~%~
              ~                        pushed     difficulty~%~*5"
             (list (cons #\0 (tilde-@-clause-id-phrase parent-cl-id))
                   (cons #\1 (tilde-@-clause-id-phrase cl-id))
                   (cons #\2 n)
                   (cons #\3 (zero-one-or-more n))
                   (cons #\4 d)
                   (cons #\5 (tilde-*-or-hit-summary-phrase summary)))
             (proofs-co state)
             state
             nil)))))

; Next we define a notion of the difficulty of a term and then grow it
; to define the difficulty of a clause and of a clause set.  The
; difficulty of a term is (almost) the sum of all the level numbers of
; the functions in the term, plus the number of function applications.
; That is, suppose f and g have level-nos of i and j.  Then the
; difficulty of (f (g x)) is i+j+2.  However, the difficulty of (NOT
; (g x)) is just i+1 because we pretend the NOT (and its function
; application) is invisible.

(mutual-recursion

(defun term-difficulty1 (term wrld n)
  (cond ((variablep term) n)
        ((fquotep term) n)
        ((flambda-applicationp term)
         (term-difficulty1-lst (fargs term) wrld
                               (term-difficulty1 (lambda-body term)
                                                 wrld (1+ n))))
        ((eq (ffn-symb term) 'not)
         (term-difficulty1 (fargn term 1) wrld n))
        (t (term-difficulty1-lst (fargs term) wrld
                                 (+ 1
                                    (get-level-no (ffn-symb term) wrld)
                                    n)))))

(defun term-difficulty1-lst (lst wrld n)
  (cond ((null lst) n)
        (t (term-difficulty1-lst (cdr lst) wrld
                                 (term-difficulty1 (car lst) wrld n)))))
)

(defun term-difficulty (term wrld)
  (term-difficulty1 term wrld 0))

; The difficulty of a clause is the sum of the complexities of the
; literals.  Note that we cannot have literals of difficulty 0 (except
; for something trivial like (NOT P)), so this measure will assign
; lower difficulty to shorter clauses, all other things being equal.

(defun clause-difficulty (cl wrld)
  (term-difficulty1-lst cl wrld 0))

; The difficulty of a clause set is similar.

(defun clause-set-difficulty (cl-set wrld)
  (cond ((null cl-set) 0)
        (t (+ (clause-difficulty (car cl-set) wrld)
              (clause-set-difficulty (cdr cl-set) wrld)))))

; The difficulty of a pspv is the sum of the difficulties of the
; TO-BE-PROVED-BY-INDUCTION clause-sets in the pool of the pspv down
; (and not counting) the element element0.

(defun pool-difficulty (element0 pool wrld)
  (cond ((endp pool) 0)
        ((equal (car pool) element0) 0)
        ((not (eq (access pool-element (car pool) :tag)
                  'TO-BE-PROVED-BY-INDUCTION))
         0)
        (t (+ (clause-set-difficulty
               (access pool-element (car pool) :clause-set)
               wrld)
              (pool-difficulty element0 (cdr pool) wrld)))))

(defun how-many-to-be-proved (element0 pool)

; We count the number of elements tagged TO-BE-PROVED-BY-INDUCTION in
; pool until we get to element0.

  (cond ((endp pool) 0)
        ((equal (car pool) element0) 0)
        ((not (eq (access pool-element (car pool) :tag)
                  'TO-BE-PROVED-BY-INDUCTION))
         0)
        (t (+ 1 (how-many-to-be-proved element0 (cdr pool))))))

(defun pick-best-pspv-for-waterfall0-or-hit1
  (results element0 wrld ans ans-difficulty summary)

; Results is a non-empty list of elements, each of which is of the
; form (cl-id . pspv) where pspv is a pspv corresponding to the
; complete waterfall processing of a single disjunct (of conjuncts).
; Inside the :pool of the pspv are a bunch of
; TO-BE-PROVED-BY-INDUCTION pool-elements.  We have to decide which of
; the pspv's is the "best" one, i.e., the one to which we will commit
; to puruse by inductions.  We choose the one that has the least
; difficulty.  We measure the difficulty of the pool-elements until we
; get to element0.

; Ans is the least difficult result so far, or nil if we have not seen
; any yet.  Ans-difficulty is the difficulty of ans (or nil).  Note
; that ans is of the form (cl-id . pspv).

; We accumulate into summary some information that is used to report
; what we find.  For each element of results we collect (cl-id n d),
; where n is the number of subgoals pushed by the cl-id processing and
; d is their combined difficulty.  We return (mv choice summary),
; where choice is the final ans (cl-id . pspv).

  (cond
   ((endp results)
    (mv ans summary))
   (t (let* ((cl-id (car (car results)))
             (pspv (cdr (car results)))
             (new-difficulty (pool-difficulty
                              element0
                              (access prove-spec-var pspv :pool)
                              wrld))
             (new-summary (cons (list cl-id
                                      (how-many-to-be-proved
                                       element0
                                       (access prove-spec-var pspv :pool))
                                      new-difficulty)
                                summary)))
        (if (or (null ans)
                (< new-difficulty ans-difficulty))
            (pick-best-pspv-for-waterfall0-or-hit1 (cdr results)
                                                   element0
                                                   wrld
                                                   (car results)
                                                   new-difficulty
                                                   new-summary)
          (pick-best-pspv-for-waterfall0-or-hit1 (cdr results)
                                                 element0
                                                 wrld
                                                 ans
                                                 ans-difficulty
                                                 new-summary))))))

(defun pick-best-pspv-for-waterfall0-or-hit (results pspv0 wrld)

; Results is a non-empty list of elements, each of which is of the
; form (cl-id . pspv) where pspv is a pspv corresponding to the
; complete waterfall processing of a single disjunct (of conjuncts).
; Inside the :pool of the pspv are a bunch of
; TO-BE-PROVED-BY-INDUCTION pool-elements.  We have to decide which of
; the pspv's is the "best" one, i.e., the one to which we will commit
; to puruse by inductions.  We choose the one that has the least
; difficulty.

; We return (mv (cl-id . pspv) summary) where cl-id and pspv are the
; clause id and pspv of the least difficult result in results and
; summary is a list that summarizes all the results, namely a list of
; the form (cl-id n difficulty), where cl-id is the clause id of a
; disjunct, n is the number of subgoals the processing of that
; disjunct pushed into the pool, and difficulty is the difficulty of
; those subgoals.

  (pick-best-pspv-for-waterfall0-or-hit1
   results

; We pass in the first element of the original pool as element0.  This
; may be a BEING-PROVED-BY-INDUCTION element but is typically a
; TO-BE-PROVED-BY-INDUCTION element.  In any case, we don't consider
; it or anything after it as we compute the difficulty.

   (car (access prove-spec-var pspv0 :pool))
   wrld
   nil   ; ans - none yet
   nil   ; ans-difficulty - none yet
   nil   ; summary
   ))

(defun change-or-hit-history-entry (i hist)
  
; The first entry in hist is a history-entry of the form

; (make history-entry 
;       :signal 'OR-HIT
;       :processor 'APPLY-TOP-HINTS-CLAUSE
;       :clause clause
;       :ttree ttree)

; where ttree contains an :OR tag with the value, val,

; (parent-cl-id NIL ((user-hint1 . hint-settings1) ...))

; We smash the NIL to i.  This indicates that along this branch of the
; history, we are dealing with user-hinti.  Note that numbering starts
; at 1.

; While apply-top-hints-clause generates a ttree with a :or tagged
; object containing a nil, this function is used to replace that nil
; in the history of every branch by the particular i generating the
; branch.

; In the histories maintained by uninterrupted runs, you should never
; see an :OR tag with a nil in that slot.  (Note carefully the use of
; the word "HISTORIES" above!  It is possible to see ttrees with :OR
; tagged objects containing nil instead of a branch number.  They get
; collected into the ttree inside the pspv that is following a clause
; around.  But it is silly to inspect that ttree to find out the
; history of the clause, since you need the history for that.)

; The basic rule is that in a history recovered from an uninterupted
; proof attempt the entries with :signal OR-HIT will have a ttree with
; a tag :OR on an object (parent-cl-id i uhs-lst).

  (let* ((val (cdr (tagged-object :or
                                  (access history-entry (car hist) :ttree))))
         (parent-cl-id (nth 0 val))
         (uhs-lst (nth 2 val)))
    (cons (make history-entry
                :signal 'OR-HIT
                :processor 'apply-top-hints-clause
                :clause (access history-entry (car hist) :clause)
                :ttree (add-to-tag-tree :or
                                        (list parent-cl-id
                                              i
                                              uhs-lst)
                                        nil))
          (cdr hist))))

(defun pair-cl-id-with-hint-setting (cl-id hint-settings)

; Background: An :OR hint takes a list of n translated hint settings,
; at a clause with a clause id.  It essentially copies the clause n
; times, gives it a new clause id (with a "Dk" suffix), and arranges
; for the waterfall to apply each hint settings to one such copy of
; the clause.  The way it arranges that is to change the hints in the
; pspv so that the newly generated "Dk" clause ids are paired with
; their respective hints.  But computed hints are different!  A
; computed hint isn't paired with a clause id.  It has it built into
; the form somewhere.  Now generally the user created the form and we
; assume the user saw the subgoal with the "Dk" id of interest and
; entered it into his form.  But we generate some computed hint forms
; -- namely custom keyword hints.  And we're responsible for tracking
; the new clause ids to which they apply.  

; Hint-settings is a translated hint-settings.  That is, it is either
; a dotted alist pairing common hint keywords to their translated
; values or it is a computed hint form starting with
; eval-and-translate-hint-expression.  In the former case, we produce
; (cl-id . hint-settings).  In the latter case, we look for the
; possibility that the term we are to eval is a call of the
; custom-keyword-hint-interpreter and if so smash its cl-id field.

  (cond
   ((eq (car hint-settings) 'eval-and-translate-hint-expression)
    (cond
     ((custom-keyword-hint-in-computed-hint-form hint-settings)
      (put-cl-id-of-custom-keyword-hint-in-computed-hint-form
       hint-settings cl-id))
     (t hint-settings)))
   (t (cons cl-id hint-settings))))

(defun apply-reorder-hint-front (indices len clauses acc)
  (cond ((endp indices) acc)
        (t (apply-reorder-hint-front
            (cdr indices) len clauses
            (cons (nth (- len (car indices)) clauses)
                  acc)))))

(defun apply-reorder-hint-back (indices current-index clauses acc)
  (cond ((endp clauses) acc)
        (t (apply-reorder-hint-back indices (1- current-index) (cdr clauses)
                                    (if (member current-index indices)
                                        acc
                                      (cons (car clauses) acc))))))

(defun filter-> (lst max)
  (cond ((endp lst) nil)
        ((> (car lst) max)
         (cons (car lst)
               (filter-> (cdr lst) max)))
        (t (filter-> (cdr lst) max))))

(defun apply-reorder-hint (pspv clauses ctx state)
  (let* ((hint-settings (access prove-spec-var pspv :hint-settings))
         (hint-setting (assoc-eq :reorder hint-settings))
         (indices (cdr hint-setting))
         (len (length clauses)))
    (cond (indices
           (cond
            ((filter-> indices len)
             (mv-let (erp val state)
                     (er soft ctx
                         "The following subgoal indices given by a :reorder ~
                          hint exceed the number of subgoals, which is ~
                          ~x0:  ~&1."
                         len (filter-> indices len))
                     (declare (ignore val))
                     (mv erp nil nil state)))
            (t
             (mv nil
                 hint-setting
                 (reverse (apply-reorder-hint-back
                           indices len clauses
                           (apply-reorder-hint-front indices len clauses
                                                     nil)))
                 state))))
          (t (mv nil nil clauses state)))))

; This completes the preliminaries for hints and we can get on with the
; waterfall itself.

(mutual-recursion

(defun waterfall1 (ledge cl-id clause hist pspv hints suppress-print ens wrld
                         ctx state step-limit)

; ledge     - In general in this mutually recursive definition, the
;             formal "ledge" is any one of the waterfall ledges.  But
;             by convention, in this function, waterfall1, it is
;             always either the 'apply-top-hints-clause ledge or
;             the next one, 'preprocess-clause.  Waterfall1 is the
;             place in the waterfall that hints are applied.
;             Waterfall0 is the straightforward encoding of the
;             waterfall, except that every time it sends clauses back
;             to the top, it send them to waterfall1 so that hints get
;             used again.

; cl-id     - the clause id for clause.
; clause    - the clause to process
; hist      - the history of clause
; pspv      - an assortment of special vars that any clause processor might
;             change
; hints     - an alist mapping clause-ids to hint-settings.
; wrld      - the current world
; state     - the usual state.

; We return 4 values: the first is a "signal" and is one of 'abort,
; 'error, or 'continue.  The last three returned values are the final
; values of pspv, the jppl-flg for this trip through the falls, and
; state.  The 'abort signal is used by our recursive processing to
; implement aborts from below.  When an abort occurs, the clause
; processor that caused the abort sets the pspv and state as it wishes
; the top to see them.  When the signal is 'error, the error message
; has been printed.  The returned pspv is irrelevant (and typically
; nil).

  (mv-let
   (erp pair state)
   (find-applicable-hint-settings cl-id clause hist pspv ctx hints wrld nil
                                  state)

; If no error occurs and pair is non-nil, then pair is of the form
; (hint-settings . hints') where hint-settings is the hint-settings
; corresponding to cl-id and clause and hints' is hints with the appropriate
; element removed.

   (cond
    (erp 

; This only happens if some hint function caused an error, e.g., by 
; generating a hint that would not translate.  The error message has been
; printed and pspv is irrelevant.  We pass the error up.

     (mv step-limit 'error nil nil state))
    (t (sl-let
        (signal pspv jppl-flg state)
        (cond
         ((null pair) ; There was no hint.
          (pprogn (waterfall-print-clause suppress-print cl-id clause state)
                  (waterfall0 ledge cl-id clause hist pspv hints ens wrld ctx
                              state step-limit)))
         (t (waterfall0-with-hint-settings
             (car pair)
             ledge cl-id clause hist pspv (cdr pair) suppress-print ens wrld
             ctx state step-limit)))
        (mv-let
         (pspv state)
         (cond ((or (eq signal 'miss)
                    (eq signal 'error))
                (mv pspv state))
               (t (gag-state-exiting-cl-id signal cl-id pspv state)))
         (mv step-limit signal pspv jppl-flg state)))))))

(defun waterfall0-with-hint-settings
  (hint-settings ledge cl-id clause hist pspv hints goal-already-printedp
                 ens wrld ctx state step-limit)

; We ``install'' the hint-settings given and call waterfall0 on the
; rest of the arguments.

  (mv-let
   (hint-settings state)
   (thanks-for-the-hint goal-already-printedp hint-settings state)
   (pprogn
    (waterfall-print-clause goal-already-printedp cl-id clause state)
    (mv-let
     (erp new-pspv-1 state)
     (load-hint-settings-into-pspv t hint-settings pspv cl-id wrld ctx state)
     (cond
      (erp (mv step-limit 'error pspv nil state))
      (t
       (pprogn
        (maybe-warn-for-use-hint new-pspv-1 ctx wrld state)
        (maybe-warn-about-theory-from-rcnsts
         (access prove-spec-var pspv :rewrite-constant)
         (access prove-spec-var new-pspv-1 :rewrite-constant)
         ctx ens wrld state)

; If there is no :INDUCT hint, then the hint-settings can be handled by
; modifying the clause and the pspv we use subsequently in the falls.

        (sl-let (signal new-pspv new-jppl-flg state)
                (waterfall0 (cond ((assoc-eq :induct hint-settings)
                                   '(push-clause))
                                  (t ledge))
                            cl-id
                            clause
                            hist
                            new-pspv-1
                            hints ens wrld ctx state step-limit)
                (mv step-limit
                    signal
                    (restore-hint-settings-in-pspv new-pspv pspv)
                    new-jppl-flg
                    state)))))))))

(defun waterfall0 (ledge cl-id clause hist pspv hints ens wrld ctx state
                         step-limit)
  (sl-let
   (signal clauses new-hist new-pspv new-jppl-flg state)
   (cond
    ((null ledge)

; The only way that the ledge can be nil is if the push-clause at the
; bottom of the waterfall signalled 'MISS.  This only happens if
; push-clause found a :DO-NOT-INDUCT name hint.  That being the case,
; we want to act like a :BY name' hint was attached to that clause,
; where name' is the result of extending the supplied name with the
; clause id.  This fancy call of waterfall-step is just a cheap way to
; get the standard :BY name' processing to happen.  All it will do is
; add a :BYE (name' . clause) to the tag-tree of the new-pspv.  We
; know that the signal returned will be a "hit".  Because we had to smash
; the hint-settings to get this to happen, we'll have to restore them
; in the new-pspv.

     (waterfall-step
      'apply-top-hints-clause
      cl-id clause hist
      (change prove-spec-var pspv
              :hint-settings
              (list
               (cons :by
                     (convert-name-tree-to-new-name
                      (cons (cdr (assoc-eq
                                  :do-not-induct
                                  (access prove-spec-var pspv :hint-settings)))
                            (string-for-tilde-@-clause-id-phrase cl-id))
                      wrld))))
      wrld ctx state step-limit))
    ((eq (car ledge) 'eliminate-destructors-clause)
     (mv-let (erp pair state)
             (find-applicable-hint-settings ; stable-under-simplificationp=t
              cl-id clause hist pspv ctx hints wrld t state)
             (cond
              (erp 

; A hint generated an error.  The error message has been printed and
; we pass the error up.  The other values are all irrelevant.

               (mv step-limit 'error nil nil nil nil state))
              ((null pair)

; No hint was applicable.  We do exactly the same thing we would have done
; had (car ledge) not been 'eliminate-destructors-clause.  Keep these two
; code segments in sync!
               
               (cond
                ((member-eq (car ledge)
                            (assoc-eq :do-not
                                      (access prove-spec-var pspv
                                              :hint-settings)))
                 (mv step-limit 'miss nil hist nil nil state))
                (t (waterfall-step (car ledge) cl-id clause hist pspv
                                   wrld ctx state step-limit))))
              (t

; A hint was found.  The car of pair is the new hint-settings and the
; cdr of pair is the new value of hints.  We need to arrange for
; waterfall0-with-hint-settings to be called.  But we are inside
; mv-let binding signal, etc., above.  We generate a fake ``signal''
; to get out of here and handle it below.

               (mv step-limit
                   'top-of-waterfall-hint
                   (car pair) hist (cdr pair) nil state)))))
    ((member-eq (car ledge)
                (assoc-eq :do-not (access prove-spec-var pspv :hint-settings)))
     (mv step-limit 'miss nil hist nil nil state))
    (t (waterfall-step (car ledge) cl-id clause hist pspv wrld ctx state
                       step-limit)))
   (cond
    ((eq signal 'OR-HIT)

; A disjunctive, hint-driven split has been requested by an :OR hint.
; Clauses is a singleton containing the clause to which we are to
; apply all of the hints.  The hints themselves are recorded in the
; first entry of the new-hist, which necessarily has the form

; (make history-entry 
;       :signal 'OR-HIT
;       :processor 'APPLY-TOP-HINTS-CLAUSE
;       :clause clause
;       :ttree ttree)

; where ttree contains an :OR tag with the value, val,

; (parent-cl-id NIL ((user-hint1 . hint-settings1) ...))

; Note that we are guaranteed here that (nth 1 val) is NIL.  That is
; because that's what apply-top-hints-clause puts into its ttree.
; It will be replaced along every history by the appropriate i.

; We recover this crucial data first.

     (let* ((val (cdr (tagged-object :or
                                     (access history-entry
                                             (car new-hist)
                                             :ttree))))
;           (parent-cl-id (nth 0 val))        ;;; same as our cl-id!
            (uhs-lst (nth 2 val))
            (branch-cnt (length uhs-lst)))

; Note that user-hinti is what the user wrote and hint-settingsi is
; the corresponding translation.  For each i we are going to act just
; like the user supplied the given hint for the parent.  Thus the
; waterfall will act like it saw parent n times, once for each
; user-hinti.

; For example, if the original :or hint was

; ("Subgoal 3" :OR ((:use lemma1 :in-theory (disable lemma1))
;                   (:use lemma2 :in-theory (disable lemma2))))
;
; then we will act just as though we saw "Subgoal 3" twice,
; once with the hint
; ("Subgoal 3" :use lemma1 :in-theory (disable lemma1))
; and then again with the hint
; ("Subgoal 3" :use lemma2 :in-theory (disable lemma2)).
; except that we give the two occurrences of "Subgoal 3" different
; names for sanity.

       (waterfall0-or-hit
        ledge cl-id
        (assert$ (and (consp clauses) (null (cdr clauses)))
                 (car clauses))
        new-hist new-pspv hints ens wrld ctx state
        uhs-lst 1 branch-cnt nil nil step-limit)))
    (t
     (let ((new-pspv
            (if (and (null ledge)
                     (not (eq signal 'error)))

; If signal is 'error, then new-pspv is nil (e.g., see the error
; behavior of waterfall step) and we wish to avoid manipulating a
; bogus pspv.

                (restore-hint-settings-in-pspv new-pspv pspv)
              new-pspv)))
       (cond
        ((eq signal 'top-of-waterfall-hint)

; This fake signal just means that either we have found an applicable hint for
; a clause that was stable under simplification (stable-under-simplificationp =
; t), or that we have found an applicable :backtrack hint.

         (mv-let
          (hint-settings hints pspv goal-already-printedp)
          (cond ((eq new-pspv :pspv-for-backtrack)

; The variable named clauses is holding the hint-settings.

                 (mv clauses
                     (append new-jppl-flg ; new-hints
                             hints)

; We will act as though we have just discovered the hint-settings and leave it
; up to waterfall0-with-hint-settings to restore the pspv if necessary after
; trying those hint-settings.

                     (change prove-spec-var pspv :hint-settings
                             (delete-assoc-eq :backtrack
                                              (access prove-spec-var pspv
                                                      :hint-settings)))
                     (cons :backtrack new-hist) ; see thanks-for-the-hint
                     ))
                (t

; The variables named clauses and new-pspv are holding the hint-settings and
; hints in this case.  We reenter the top of the falls with the new hint
; setting and hints.

                 (mv clauses
                     new-pspv
                     pspv
                     t)))
          (waterfall0-with-hint-settings
           hint-settings
           *preprocess-clause-ledge*
           cl-id clause

; Simplify-clause contains an optimization that lets us avoid resimplifying
; the clause if the most recent history entry is settled-down-clause and
; the induction hyp and concl terms don't occur in it.  We short-circuit that
; short-circuit by removing the settled-down-clause entry if it is the most
; recent.

           (cond ((and (consp hist)
                       (eq (access history-entry (car hist) :processor)
                           'settled-down-clause))
                  (cdr hist))
                 (t hist))
           pspv hints goal-already-printedp ens wrld ctx state step-limit)))
        ((eq signal 'error) (mv step-limit 'error nil nil state))
        ((eq signal 'abort) (mv step-limit 'abort new-pspv new-jppl-flg state))
        ((eq signal 'miss)
         (if ledge
             (waterfall0 (cdr ledge)
                         cl-id
                         clause
                         new-hist ; used because of specious entries
                         pspv
                         hints
                         ens
                         wrld
                         ctx
                         state
                         step-limit)
           (mv step-limit
               (er hard 'waterfall0
                   "The empty ledge signalled 'MISS!  This can only happen if ~
                    we changed APPLY-TOP-HINTS-CLAUSE so that when given a ~
                    single :BY name hint it fails to hit.")
               nil nil state)))
        (t 

; Signal is one of the flavors of 'hit, 'hit-rewrite, or 'hit-rewrite2.
           
         (mv-let
          (erp hint-setting clauses state)
          (apply-reorder-hint pspv clauses ctx state)
          (cond
           (erp ; error already printed; treat same as 'error signal
            (mv step-limit 'error nil nil state))
           (t
            (waterfall1-lst (cond ((eq (car ledge) 'settled-down-clause)
                                   'settled-down-clause)
                                  ((null clauses) 0)
                                  ((null (cdr clauses)) nil)
                                  (t (length clauses)))
                            cl-id
                            clauses
                            new-hist
                            (if hint-setting
                                (change
                                 prove-spec-var new-pspv
                                 :hint-settings
                                 (remove1-equal hint-setting
                                                (access prove-spec-var
                                                        new-pspv
                                                        :hint-settings)))
                              new-pspv)
                            new-jppl-flg
                            hints
                            (eq (car ledge) 'settled-down-clause)
                            ens
                            wrld
                            ctx
                            state
                            step-limit)))))))))))

(defun waterfall0-or-hit (ledge cl-id clause hist pspv hints ens wrld ctx state
                                uhs-lst i branch-cnt revert-info results
                                step-limit)

; Cl-id is the clause id of clause, of course, and we are to disjunctively
; apply each of the hints in ush-lst to it.  Uhs-lst is of the form
; (...(user-hinti . hint-settingsi)...) and branch-cnt is the length of that
; list initially, i.e., the maximum value of i.

; We map over uhs-lst and pursue each branch, giving each its own "D" clause id
; and changing the ttree in its history entry to indicate that it is branch i.
; We collect the results as we go into results.  The results are each of the
; form (d-cl-id . new-pspv), where new-pspv is the pspv that results from
; processing the branch.  If the :pool in any one of these new-pspv's is equal
; to that in pspv, then we have succeeded (nothing was pushed) and we stop.
; Otherwise, when we have considered all the hints in uhs-lst, we inspect
; results and choose the best (least difficult looking) one to pursue further.

; Revert-info is nil unless we have seen a disjunctive subgoal that generated a
; signal to abort and revert to the original goal.  In that case, revert-info
; is a pair (revert-d-cl-id . pspv) where revert-d-cl-id identifies that
; disjunctive subgoal (the first one, in fact) and pspv is the corresponding
; pspv returned for that subgoal.

  (cond
   ((endp uhs-lst)
    
; Results is the result of doing all the elements of uhs-lst.  If it is empty,
; all branches aborted.  Otherwise, we have to choose between the results.

    (cond
     ((endp results)

; In this case, every single disjunct aborted.  That means each failed in one
; of three ways: (a) it set the goal to nil, (b) it needed induction but found
; a hint prohibiting it, or (c) it chose to revert to the original input.  We
; will cause the whole proof to abort.  We choose to revert if revert-d-cl-id
; is non-nil, indicating that (c) occurred for at least one disjunctive branch,
; namely one with a clause-id of revert-d-cl-id.

      (pprogn
       (io? prove nil state
            (cl-id revert-info)
            (waterfall-or-hit-msg-c cl-id nil (car revert-info) nil nil state))
       (mv step-limit
           'abort
           (cond (revert-info (cdr revert-info))
                 (t
                  (change prove-spec-var pspv
                          :pool (cons (make pool-element
                                            :tag 'TO-BE-PROVED-BY-INDUCTION
                                            :clause-set '(nil)
                                            :hint-settings nil)
                                      (access prove-spec-var pspv :pool))
                          :tag-tree
                          (add-to-tag-tree 'abort-cause
                                           'empty-clause
                                           (access prove-spec-var pspv
                                                   :tag-tree)))))
           (and revert-info

; Keep the following in sync with the corresponding call of pool-lst in
; waterfall-msg.  That call assumes that the pspv was returned by push-clause,
; which is also the case here.

                (pool-lst (cdr (access prove-spec-var (cdr revert-info)
                                       :pool))))
           state)))
     (t (mv-let (choice summary)
                (pick-best-pspv-for-waterfall0-or-hit results pspv wrld)
                (pprogn
                 (io? proof-tree nil state
                      (choice cl-id)
                      (pprogn
                       (increment-timer 'prove-time state)
                       (install-disjunct-into-proof-tree cl-id (car choice) state)
                       (increment-timer 'proof-tree-time state)))
                 (io? prove nil state
                      (cl-id results choice summary)
                      (waterfall-or-hit-msg-c cl-id ; parent-cl-id
                                              results
                                              nil
                                              (car choice) ; new goal cl-id
                                              summary
                                              state))
                 (mv step-limit
                     'continue
                     (cdr choice) ; chosen pspv

; Through Version_3.3 we used a jppl-flg here instead of nil.  But to the
; extent that this value controls whether we print the goal before starting
; induction, we prefer to print it: for the corresponding goal pushed for
; induction under one of the disjunctive subgoals, the connection might not be
; obvious to the user.

                     nil
                     state))))))
   (t
    (let* ((user-hinti (car (car uhs-lst)))
           (hint-settingsi (cdr (car uhs-lst)))
           (d-cl-id (make-disjunctive-clause-id cl-id (length uhs-lst)
                                                (current-package state))))
      (pprogn
       (io? prove nil state
            (cl-id user-hinti d-cl-id i branch-cnt)
            (pprogn
             (increment-timer 'prove-time state)
             (waterfall-or-hit-msg-a cl-id user-hinti d-cl-id i branch-cnt
                                     state)
             (increment-timer 'print-time state)))
       (sl-let
        (d-signal d-new-pspv d-new-jppl-flg state)
        (waterfall1 ledge
                    d-cl-id
                    clause
                    (change-or-hit-history-entry i hist)
                    pspv
                    (cons (pair-cl-id-with-hint-setting d-cl-id
                                                        hint-settingsi)
                          hints)
                    t  ;;; suppress-print
                    ens
                    wrld ctx state step-limit)
        (declare (ignore d-new-jppl-flg))
                     
; Here, d-signal is one of 'error, 'abort or 'continue.  We pass 'error up
; immediately and we filter 'abort out.

        (cond
         ((eq d-signal 'error)

; Errors shouldn't happen and we stop with an error if one does.

          (mv step-limit 'error nil nil state))
         ((eq d-signal 'abort)

; Aborts are normal -- the proof failed somehow; we just skip it and continue
; with its peers.

          (waterfall0-or-hit
           ledge cl-id clause hist pspv hints ens wrld ctx state
           (cdr uhs-lst) (+ 1 i) branch-cnt
           (or revert-info
               (and (eq (cdr (tagged-object 'abort-cause
                                            (access prove-spec-var d-new-pspv
                                                    :tag-tree)))
                        'revert)
                    (cons d-cl-id d-new-pspv)))
           results step-limit))
         ((equal (access prove-spec-var pspv :pool)
                 (access prove-spec-var d-new-pspv :pool))

; We won!  The pool in the new pspv is the same as the pool in the old, which
; means all the subgoals generated in the branch were proved (modulo any forced
; assumptions, etc., in the :tag-tree).  In this case we terminate the sweep
; across the disjuncts.

          (pprogn
           (io? proof-tree nil state
                (d-cl-id cl-id)
                (pprogn
                 (increment-timer 'prove-time state)
                 (install-disjunct-into-proof-tree cl-id d-cl-id state)
                 (increment-timer 'proof-tree-time state)))
           (io? prove nil state
                (cl-id d-cl-id branch-cnt)
                (pprogn
                 (increment-timer 'prove-time state)
                 (waterfall-or-hit-msg-b cl-id d-cl-id branch-cnt state)
                 (increment-timer 'print-time state)))
           (mv step-limit
               'continue
               d-new-pspv
               nil ; could probably use jppl-flg, but nil is always OK
               state)))
         (t 

; Otherwise, we collect the result into results and continue with the others.

          (waterfall0-or-hit
           ledge cl-id clause hist pspv hints ens wrld ctx state
           (cdr uhs-lst) (+ 1 i) branch-cnt
           revert-info
           (cons (cons d-cl-id d-new-pspv) results)
           step-limit)))))))))

(defun waterfall1-lst (n parent-cl-id clauses hist pspv jppl-flg
                         hints suppress-print ens wrld ctx state step-limit)

; N is either 'settled-down-clause, nil, or an integer.  'Settled-
; down-clause means that we just executed settled-down-clause and so
; should pass the parent's clause id through as though nothing
; happened.  Nil means we produced one child and so its clause-id is
; that of the parent with the primes field incremented by 1.  An
; integer means we produced n children and they each get a clause-id
; derived by extending the parent's case-lst.

  (cond
   ((null clauses) (mv step-limit 'continue pspv jppl-flg state))
   (t (let ((cl-id (cond
                    ((and (equal parent-cl-id *initial-clause-id*)
                          (no-op-histp hist))
                     parent-cl-id)
                    ((eq n 'settled-down-clause) parent-cl-id)
                    ((null n)
                     (change clause-id parent-cl-id
                             :primes
                             (1+ (access clause-id
                                         parent-cl-id
                                         :primes))))
                    (t (change clause-id parent-cl-id
                               :case-lst
                               (append (access clause-id
                                               parent-cl-id
                                               :case-lst)
                                       (list n))
                               :primes 0)))))
        (sl-let
         (signal new-pspv new-jppl-flg state)
         (waterfall1 *preprocess-clause-ledge*
                     cl-id
                     (car clauses)
                     hist
                     pspv
                     hints
                     suppress-print
                     ens
                     wrld
                     ctx
                     state
                     step-limit)
         (cond
          ((eq signal 'error)
           (mv step-limit 'error nil nil state))
          ((eq signal 'abort)
           (mv step-limit 'abort new-pspv new-jppl-flg state))
          (t
           (waterfall1-lst (cond ((eq n 'settled-down-clause) n)
                                 ((null n) nil)
                                 (t (1- n)))
                           parent-cl-id
                           (cdr clauses)
                           hist
                           new-pspv
                           new-jppl-flg
                           hints
                           nil
                           ens
                           wrld
                           ctx
                           state
                           step-limit))))))))

)

; And here is the waterfall:

(defun waterfall (forcing-round pool-lst x pspv hints ens wrld ctx state
                                step-limit)

; Here x is a list of clauses, except that when we are beginning a forcing
; round other than the first, x is really a list of pairs (assumnotes .
; clause).

; Pool-lst is the pool-lst of the clauses and will be used as the
; first field in the clause-id's we generate for them.  We return the
; four values: an error flag, the final value of pspv, the jppl-flg,
; and the final state.

  (let ((parent-clause-id
         (cond ((and (= forcing-round 0)
                     (null pool-lst))

; Note:  This cond is not necessary.  We could just do the make clause-id
; below.  We recognize this case just to avoid the consing.

                *initial-clause-id*)
               (t (make clause-id
                        :forcing-round forcing-round
                        :pool-lst pool-lst
                        :case-lst nil
                        :primes 0))))
        (clauses
         (cond ((and (not (= forcing-round 0))
                     (null pool-lst))
                (strip-cdrs x))
               (t x))))
    (pprogn
     (cond ((output-ignored-p 'proof-tree state)
            state)
           (t (initialize-proof-tree parent-clause-id x ctx state)))
     (sl-let (signal new-pspv new-jppl-flg state)
             (waterfall1-lst (cond ((null clauses) 0)
                                   ((null (cdr clauses))
                                    'settled-down-clause)
                                   (t (length clauses)))
                             parent-clause-id
                             clauses nil
                             pspv nil hints
                             (and (eql forcing-round 0)
                                  (null pool-lst)) ; suppress-print
                             ens wrld ctx state step-limit)
             (cond ((eq signal 'error)

; If the waterfall signalled an error then it printed the message and we
; just pass the error up.

                    (mv step-limit t nil nil state))
                   (t

; Otherwise, the signal is either 'abort or 'continue.  But 'abort here
; was meant as an internal signal only, used to get out of the recursion
; in waterfall1.  We now simply fold those two signals together into the
; non-erroneous return of the new-pspv and final flg.

                    (mv step-limit nil new-pspv new-jppl-flg state)))))))

; After the waterfall has finished we have a pool of goals.  We
; now develop the functions to extract a goal from the pool for
; induction.  It is in this process that we check for subsumption
; among the goals in the pool.

(defun some-pool-member-subsumes (pool clause-set)

; We attempt to determine if there is a clause set in the pool that subsumes
; every member of the given clause-set.  If we make that determination, we
; return the tail of pool that begins with that member.  Otherwise, no such
; subsumption was found, perhaps because of the limitation in our subsumption
; check (see subsumes), and we return nil.

  (cond ((null pool) nil)
        ((eq (clause-set-subsumes *init-subsumes-count*
                                  (access pool-element (car pool) :clause-set)
                                  clause-set)
             t)
         pool)
        (t (some-pool-member-subsumes (cdr pool) clause-set))))

(defun add-to-pop-history
  (action cl-set pool-lst subsumer-pool-lst pop-history)

; Extracting a clause-set from the pool is called "popping".  It is
; complicated by the fact that we do subsumption checking and other
; things.  To report what happened when we popped, we maintain a "pop-history"
; which is used by the pop-clause-msg fn below.  This function maintains
; pop-histories.

; A pop-history is a list that records the sequence of events that
; occurred when we popped a clause set from the pool.  The pop-history
; is used only by the output routine pop-clause-msg.

; The pop-history is built from nil by repeated calls of this
; function.  Thus, this function completely specifies the format.  The
; elements in a pop-history are each of one of the following forms.
; All the "lst"s below are pool-lsts.

; (pop lst1 ... lstk)             finished the proofs of the lstd goals
; (consider cl-set lst)           induct on cl-set
; (subsumed-by-parent cl-set lst subsumer-lst)
;                                 cl-set is subsumed by lstd parent
; (subsumed-below cl-set lst subsumer-lst)
;                                 cl-set is subsumed by lstd peer
; (qed)                           pool is empty -- but there might be
;                                 assumptions or :byes yet to deal with.
; and has the property that no two pop entries are adjacent.  When
; this function is called with an action that does not require all of
; the arguments, nils may be provided.

; The entries are in reverse chronological order and the lsts in each
; pop entry are in reverse chronological order.

  (cond ((eq action 'pop)
         (cond ((and pop-history
                     (eq (caar pop-history) 'pop))
                (cons (cons 'pop (cons pool-lst (cdar pop-history)))
                      (cdr pop-history)))
               (t (cons (list 'pop pool-lst) pop-history))))
        ((eq action 'consider)
         (cons (list 'consider cl-set pool-lst) pop-history))
        ((eq action 'qed)
         (cons '(qed) pop-history))
        (t (cons (list action cl-set pool-lst subsumer-pool-lst)
                 pop-history))))

(defun pop-clause1 (pool pop-history)

; We scan down pool looking for the next 'to-be-proved-by-induction
; clause-set.  We mark it 'being-proved-by-induction and return six
; things: one of the signals 'continue, 'win, or 'lose, the pool-lst
; for the popped clause-set, the clause-set, its hint-settings, a
; pop-history explaining what we did, and a new pool.

  (cond ((null pool)

; It looks like we won this one!  But don't be fooled.  There may be
; 'assumptions or :byes in the ttree associated with this proof and
; that will cause the proof to fail.  But for now we continue to just
; act happy.  This is called denial.

         (mv 'win nil nil nil
             (add-to-pop-history 'qed nil nil nil pop-history)
             nil))
        ((eq (access pool-element (car pool) :tag) 'being-proved-by-induction)
         (pop-clause1 (cdr pool)
                      (add-to-pop-history 'pop
                                          nil
                                          (pool-lst (cdr pool))
                                          nil
                                          pop-history)))
        ((equal (access pool-element (car pool) :clause-set)
                '(nil))

; The empty set was put into the pool!  We lose.  We report the empty name
; and clause set, and an empty pop-history (so no output occurs).  We leave
; the pool as is.  So we'll go right out of pop-clause and up to the prover
; with the 'lose signal.

         (mv 'lose nil nil nil nil pool))
        (t
         (let ((pool-lst (pool-lst (cdr pool)))
               (sub-pool
                (some-pool-member-subsumes (cdr pool)
                                           (access pool-element (car pool)
                                                   :clause-set))))
           (cond
            ((null sub-pool)
             (mv 'continue
                 pool-lst
                 (access pool-element (car pool) :clause-set)
                 (access pool-element (car pool) :hint-settings)
                 (add-to-pop-history 'consider
                                     (access pool-element (car pool)
                                             :clause-set)
                                     pool-lst
                                     nil
                                     pop-history)
                 (cons (change pool-element (car pool)
                               :tag 'being-proved-by-induction)
                       (cdr pool))))
            ((eq (access pool-element (car sub-pool) :tag)
                 'being-proved-by-induction)
             (mv 'lose nil nil nil
                 (add-to-pop-history 'subsumed-by-parent
                                     (access pool-element (car pool)
                                             :clause-set)
                                     pool-lst
                                     (pool-lst (cdr sub-pool))
                                     pop-history)
                 pool))
            (t
             (pop-clause1 (cdr pool)
                          (add-to-pop-history 'subsumed-below
                                              (access pool-element (car pool)
                                                      :clause-set)
                                              pool-lst
                                              (pool-lst (cdr sub-pool))
                                              pop-history))))))))

; Here we develop the functions for reporting on a pop.

(defun make-defthm-forms-for-byes (byes wrld)

; Each element of byes is of the form (name . clause) and we create
; a list of the corresponding defthm events.

  (cond ((null byes) nil)
        (t (cons (list 'defthm (caar byes)
                       (prettyify-clause (cdar byes) nil wrld)
                       :rule-classes nil)
                 (make-defthm-forms-for-byes (cdr byes) wrld)))))

(defun pop-clause-msg1 (forcing-round lst jppl-flg prev-action gag-state msg-p
                                      state)

; Lst is a reversed pop-history.  Since pop-histories are in reverse
; chronological order, lst is in chronological order.  We scan down
; lst, printing out an explanation of each action.  Prev-action is the
; most recently explained action in this scan, or else nil if we are
; just beginning.  Jppl-flg, if non-nil, means that the last executed
; waterfall process was 'push-clause; the pool-lst of the clause pushed is
; in the value of jppl-flg.

  (cond
   ((null lst)
    (pprogn (increment-timer 'print-time state)
            (mv gag-state state)))
   (t
    (let ((entry (car lst)))
      (mv-let
       (gag-state state)
       (case-match
         entry
         (('pop . pool-lsts)
          (mv-let
           (gagst msgs)
           (pop-clause-update-gag-state-pop pool-lsts gag-state nil msg-p)
           (pprogn
            (io? prove nil state
                 (prev-action pool-lsts forcing-round msgs)
                 (pprogn
                  (fms
                   (cond ((gag-mode)
                          (assert$ pool-lsts
                                   "~*1 ~#0~[is~/are~] COMPLETED!~|"))
                         ((null prev-action)
                          "That completes the proof~#0~[~/s~] of ~*1.~|")
                         (t "That, in turn, completes the proof~#0~[~/s~] of ~
                             ~*1.~|"))
                   (list (cons #\0 pool-lsts)
                         (cons #\1
                               (list "" "~@*" "~@* and " "~@*, "
                                     (tilde-@-pool-name-phrase-lst
                                      forcing-round
                                      (reverse pool-lsts)))))
                   (proofs-co state) state nil)
                  (cond
                   ((and msgs (gag-mode))
                    (mv-let
                     (col state)
                     (fmt1 "Thus key checkpoint~#1~[~ ~*0 is~/s ~*0 are~] ~
                            COMPLETED!~|"
                           (list (cons #\0
                                       (list "" "~@*" "~@* and " "~@*, "
                                             (reverse msgs)))
                                 (cons #\1 msgs))
                           0 (proofs-co state) state nil)
                     (declare (ignore col))
                     state))
                   (t state))))
            (mv gagst state))))
         (('qed)

; We used to print Q.E.D. here, but that is premature now that we know
; there might be assumptions or :byes in the pspv.  We let
; process-assumptions announce the definitive completion of the proof.

          (mv gag-state state))
         (&

; Entry is either a 'consider or one of the two 'subsumed... actions.  For all
; three we print out the clause we are working on.  Then we print out the
; action specific stuff.

          (let ((pool-lst (caddr entry)))
            (mv-let
             (gagst cl-id)
             (cond ((eq (car entry) 'consider)
                    (mv gag-state nil))
                   (t (remove-pool-lst-from-gag-state pool-lst gag-state)))
             (pprogn
              (io? prove nil state
                   (prev-action forcing-round pool-lst entry cl-id jppl-flg
                                gag-state)
                   (let* ((cl-set (cadr entry))
                          (jppl-flg (if (gag-mode)
                                        (gag-mode-jppl-flg gag-state)
                                      jppl-flg))
                          (push-pop-flg
                           (and jppl-flg
                                (equal jppl-flg pool-lst))))

; The push-pop-flg is set if the clause just popped is the same as the one we
; just pushed.  It and its name have just been printed.  There's no need to
; identify it here unless we are in gag-mode and we are in a sub-induction,
; since in that case we never printed the formula.  (We could take the attitude
; that the user doesn't deserve to see any sub-induction formulas in gag-mode;
; but we expect there to be very few of these anyhow, since probably they'll
; generally fail.)

                     (pprogn
                      (cond
                       (push-pop-flg state)
                       (t (fms (cond
                                ((eq prev-action 'pop)
                                 "We therefore turn our attention to ~@1, ~
                                  which is~|~%~q0.~|")
                                ((null prev-action)
                                 "So we now return to ~@1, which is~|~%~q0.~|")
                                (t
                                 "We next consider ~@1, which is~|~%~q0.~|"))
                               (list (cons #\0 (prettyify-clause-set
                                                cl-set
                                                (let*-abstractionp state)
                                                (w state)))
                                     (cons #\1 (tilde-@-pool-name-phrase
                                                forcing-round pool-lst)))
                               (proofs-co state)
                               state
                               (term-evisc-tuple nil state))))
                      (case-match
                        entry
                        (('subsumed-below & & subsumer-pool-lst)
                         (pprogn
                          (fms "But the formula above is subsumed by ~@1, ~
                                which we'll try to prove later.  We therefore ~
                                regard ~@0 as proved (pending the proof of ~
                                the more general ~@1).~|"
                               (list
                                (cons #\0
                                      (tilde-@-pool-name-phrase
                                       forcing-round pool-lst))
                                (cons #\1
                                      (tilde-@-pool-name-phrase
                                       forcing-round subsumer-pool-lst)))
                               (proofs-co state)
                               state nil)
                          (cond
                           ((and cl-id (gag-mode))
                            (fms "~@0 COMPLETED!~|"
                                 (list (cons #\0 (tilde-@-clause-id-phrase
                                                  cl-id)))
                                 (proofs-co state) state nil))
                           (t state))))
                        (('subsumed-by-parent & & subsumer-pool-lst)
                         (fms "The formula above is subsumed by one of its ~
                               parents, ~@0, which we're in the process of ~
                               trying to prove by induction.  When an ~
                               inductive proof pushes a subgoal for induction ~
                               that is less general than the original goal, ~
                               it may be a sign that either an inappropriate ~
                               induction was chosen or that the original goal ~
                               is insufficiently general.  In any case, our ~
                               proof attempt has failed.~|"
                              (list
                               (cons #\0
                                     (tilde-@-pool-name-phrase
                                      forcing-round subsumer-pool-lst)))
                              (proofs-co state)
                              state nil))
                        (& ; (consider cl-set pool-lst)
                         state)))))
              (mv gagst state))))))
       (pop-clause-msg1 forcing-round (cdr lst) jppl-flg (caar lst) gag-state
                        msg-p state))))))

(defun pop-clause-msg (forcing-round pop-history jppl-flg pspv state)

; We print the messages explaining the pops we did.

; This function increments timers.  Upon entry, the accumulated time is
; charged to 'prove-time.  The time spent in this function is charged
; to 'print-time.

  (pprogn
   (increment-timer 'prove-time state)
   (mv-let
    (gag-state state)
    (let ((gag-state0 (access prove-spec-var pspv :gag-state)))
      (pop-clause-msg1 forcing-round
                       (reverse pop-history)
                       jppl-flg
                       nil
                       gag-state0
                       (not (output-ignored-p 'prove state))
                       state))
    (pprogn (record-gag-state gag-state state)
            (increment-timer 'print-time state)
            (mv (change prove-spec-var pspv :gag-state gag-state)
                state)))))

(defun subsumed-clause-ids-from-pop-history (forcing-round pop-history)
  (cond
   ((endp pop-history)
    nil)
   ((eq (car (car pop-history)) 'subsumed-below)
    (cons (make clause-id
                :forcing-round forcing-round
                :pool-lst (caddr (car pop-history)) ; see add-to-pop-history
                :case-lst nil
                :primes 0)
          (subsumed-clause-ids-from-pop-history forcing-round
                                                (cdr pop-history))))
   (t (subsumed-clause-ids-from-pop-history forcing-round (cdr pop-history)))))

(defun increment-proof-tree-pop-clause (forcing-round pop-history state)
  (let ((old-proof-tree (f-get-global 'proof-tree state))
        (dead-clause-ids
         (subsumed-clause-ids-from-pop-history forcing-round pop-history)))
    (if dead-clause-ids
        (pprogn (f-put-global 'proof-tree
                              (prune-proof-tree forcing-round
                                                dead-clause-ids
                                                old-proof-tree)
                              state)
                (print-proof-tree state))
      state)))

(defun pop-clause (forcing-round pspv jppl-flg state)

; We pop the first available clause from the pool in pspv.  We print
; out an explanation of what we do.  If jppl-flg is non-nil
; then it means the last executed waterfall processor was 'push-clause
; and the pool-lst of the clause pushed is the value of jppl-flg.

; We return 7 results.  The first is a signal: 'win, 'lose, or
; 'continue and indicates that we have finished successfully (modulo,
; perhaps, some assumptions and :byes in the tag-tree), arrived at a
; definite failure, or should continue.  If the first result is
; 'continue, the second, third and fourth are the pool name phrase,
; the set of clauses to induct upon, and the hint-settings, if any.
; The remaining results are the new values of pspv and state.

  (mv-let (signal pool-lst cl-set hint-settings pop-history new-pool)
          (pop-clause1 (access prove-spec-var pspv :pool)
                       nil)
          (mv-let
           (new-pspv state)
           (pop-clause-msg forcing-round pop-history jppl-flg pspv state)
           (pprogn
            (io? proof-tree nil state
                 (forcing-round pop-history)
                 (pprogn
                  (increment-timer 'prove-time state)
                  (increment-proof-tree-pop-clause forcing-round pop-history
                                                   state)
                  (increment-timer 'proof-tree-time state)))
            (mv signal
                pool-lst
                cl-set
                hint-settings
                (change prove-spec-var new-pspv :pool new-pool)
                state)))))

(defun tilde-@-assumnotes-phrase-lst (lst wrld)

; WARNING: Note that the phrase is encoded twelve times below, to put
; in the appropriate noise words and punctuation!

; Note: As of this writing it is believed that the only time the :rune of an
; assumnote is a fake rune, as in cases 1, 5, and 9 below, is when the
; assumnote is in the impossible assumption.  However, we haven't coded this
; specially because such an assumption will be brought immediately to our
; attention in the forcing round by its *nil* :term.

  (cond
   ((null lst) nil)
   (t (cons
       (cons
        (cond ((null (cdr lst))
               (cond ((and (consp (access assumnote (car lst) :rune))
                           (null (base-symbol (access assumnote (car lst) :rune))))
                      " ~@0~%  by primitive type reasoning about~%  ~q2,~| and~|")
                     ((eq (access assumnote (car lst) :rune) 'equal)
                      " ~@0~%  by the linearization of~%  ~q2.~|")
                     ((symbolp (access assumnote (car lst) :rune))
                      " ~@0~%  by assuming the guard for ~x1 in~%  ~q2.~|")
                     (t " ~@0~%  by applying ~x1 to~%  ~q2.~|")))
              ((null (cddr lst))
               (cond ((and (consp (access assumnote (car lst) :rune))
                           (null (base-symbol (access assumnote (car lst) :rune))))
                      " ~@0~%  by primitive type reasoning about~%  ~q2,~| and~|")
                     ((eq (access assumnote (car lst) :rune) 'equal)
                      " ~@0~%  by the linearization of~%  ~q2,~| and~|")
                     ((symbolp (access assumnote (car lst) :rune))
                      " ~@0~%  by assuming the guard for ~x1 in~%  ~q2,~| and~|")
                     (t " ~@0~%  by applying ~x1 to~%  ~q2,~| and~|")))
              (t
               (cond ((and (consp (access assumnote (car lst) :rune))
                           (null (base-symbol (access assumnote (car lst) :rune))))
                      " ~@0~%  by primitive type reasoning about~%  ~q2,~|")
                     ((eq (access assumnote (car lst) :rune) 'equal)
                      " ~@0~%  by the linearization of~%  ~q2,~|")
                     ((symbolp (access assumnote (car lst) :rune))
                      " ~@0~%  by assuming the guard for ~x1 in~%  ~q2,~|")
                     (t " ~@0~%  by applying ~x1 to~%  ~q2,~|"))))
        (list
         (cons #\0 (tilde-@-clause-id-phrase
                    (access assumnote (car lst) :cl-id)))
         (cons #\1 (access assumnote (car lst) :rune))
         (cons #\2 (untranslate (access assumnote (car lst) :target) nil wrld))))
       (tilde-@-assumnotes-phrase-lst (cdr lst) wrld)))))

(defun tilde-*-assumnotes-column-phrase (assumnotes wrld)

; We create a tilde-* phrase that will print a column of assumnotes.

  (list "" "~@*" "~@*" "~@*"
        (tilde-@-assumnotes-phrase-lst assumnotes wrld)))

(defun process-assumptions-msg1 (forcing-round n pairs state)

; N is either nil (meaning the length of pairs is 1) or n is the length of
; pairs.

  (cond
   ((null pairs) state)
   (t (pprogn
       (fms "~@0, below, will focus on~%~q1,~|which was forced in~%~*2"
            (list (cons #\0 (tilde-@-clause-id-phrase
                             (make clause-id
                                   :forcing-round (1+ forcing-round)
                                   :pool-lst nil
                                   :case-lst (if n
                                                 (list n)
                                                 nil)
                                   :primes 0)))
                  (cons #\1 (untranslate (car (last (cdr (car pairs))))
                                         t (w state)))
                  (cons #\2 (tilde-*-assumnotes-column-phrase
                             (car (car pairs))
                             (w state))))
            (proofs-co state) state
            (term-evisc-tuple nil state))
       (process-assumptions-msg1 forcing-round
                                 (if n (1- n) nil)
                                 (cdr pairs) state)))))

(defun process-assumptions-msg (forcing-round n0 n pairs state)

; This function is called when we have completed the given forcing-round and
; are about to begin the next one.  Forcing-round is an integer, r.  Pairs is a
; list of n pairs, each of the form (assumnotes . clause).  It was generated by
; cleaning up n0 assumptions.  We are about to pour all n clauses into the
; waterfall, where they will be given clause-ids of the form [r+1]Subgoal i,
; for i from 1 to n, or, if there is only one clause, [r+1]Goal.

; The list of assumnotes associated with each clause explain the need for the
; assumption.  Each assumnote is a record of that class, containing the cl-id
; of the clause we were working on when we generated the assumption, the rune
; (a symbol as per force-assumption) generating the assumption, and the target
; term to which the rule was being applied.  We print a table explaining the
; derivation of the new goals from the old ones and then announce the beginning
; of the next round.

  (io? prove nil state
       (n0 forcing-round n pairs)
       (pprogn
        (fms
         "Modulo the following~#0~[~/ ~n1~]~#2~[~/ newly~] forced ~
          goal~#0~[~/s~], that completes ~#2~[the proof of the input ~
          Goal~/Forcing Round ~x3~].~#4~[~/  For what it is worth, the~#0~[~/ ~
          ~n1~] new goal~#0~[ was~/s were~] generated by cleaning up ~n5 ~
          forced hypotheses.~]  See :DOC forcing-round.~%"
         (list (cons #\0 (if (cdr pairs) 1 0))
               (cons #\1 n)
               (cons #\2 (if (= forcing-round 0) 0 1))
               (cons #\3 forcing-round)
               (cons #\4 (if (= n0 n) 0 1))
               (cons #\5 n0)
               (cons #\6 (1+ forcing-round)))
         (proofs-co state)
         state
         nil)
        (process-assumptions-msg1 forcing-round
                                  (if (= n 1) nil n)
                                  pairs
                                  state)
        (fms "We now undertake Forcing Round ~x0.~%"
             (list (cons #\0 (1+ forcing-round)))
             (proofs-co state)
             state
             nil))))

(deflabel forcing-round

; Up through Version_3.3, unencumber-assumption removed hypotheses about
; irrelevant variables at the application of force.  Since that is no longer
; true, we have eliminated the following paragraph after the paragraph
; mentioning the ``clean them up'' process.

;   For example, suppose the main goal is about some term
;   ~c[(pred (xtrans i) i)] and that some rule rewriting ~c[pred] contains a
;   ~il[force]d hypothesis that the first argument is a ~c[good-inputp].
;   Suppose that during the proof of Subgoal 14 of the main goal,
;   ~c[(good-inputp (xtrans i))] is ~il[force]d in a context in which ~c[i] is
;   an ~ilc[integerp] and ~c[x] is a ~ilc[consp].  (Note that ~c[x] is
;   irrelevant.)  Suppose finally that during the proof of Subgoal 28,
;   ~c[(good-inputp (xtrans i))] is ~il[force]d ``again,'' but this time in a
;   context in which ~c[i] is a ~ilc[rationalp] and ~c[x] is a ~ilc[symbolp].
;   Since the ~il[force]d hypothesis does not mention ~c[x], we deem the
;   contextual information about ~c[x] to be irrelevant and discard it
;   from both contexts.  We are then left with two ~il[force]d assumptions:
;   ~c[(implies (integerp i) (good-inputp (xtrans i)))] from Subgoal 14,
;   and ~c[(implies (rationalp i) (good-inputp (xtrans i)))] from Subgoal
;   28.  Note that if we can prove the assumption required by Subgoal 28
;   we can easily get that for Subgoal 14, since the context of Subgoal
;   28 is the more general.  Thus, in the next forcing round we will
;   attempt to prove just
;   ~bv[]
;   (implies (rationalp i) (good-inputp (xtrans i)))
;   ~ev[]
;   and ``blame'' both Subgoal 14 and Subgoal 28 of the previous round
;   for causing us to prove this.

  :doc
  ":Doc-Section Miscellaneous

  a section of a proof dealing with ~il[force]d assumptions~/

  If ACL2 ``~il[force]s'' some hypothesis of some rule to be true, it is
  obliged later to prove the hypothesis.  ~l[force].  ACL2 delays
  the consideration of ~il[force]d hypotheses until the main goal has been
  proved.  It then undertakes a new round of proofs in which the main
  goal is essentially the conjunction of all hypotheses ~il[force]d in the
  preceding proof.  Call this round of proofs the ``Forcing Round.''
  Additional hypotheses may be ~il[force]d by the proofs in the Forcing
  Round.  The attempt to prove these hypotheses is delayed until the
  Forcing Round has been successfully completed.  Then a new Forcing
  Round is undertaken to prove the recently ~il[force]d hypotheses and this
  continues until no hypotheses are ~il[force]d.  Thus, there is a
  succession of Forcing Rounds.~/

  The Forcing Rounds are enumerated starting from 1.  The Goals and
  Subgoals of a Forcing Round are printed with the round's number
  displayed in square brackets.  Thus, ~c[\"[1~]Subgoal 1.3\"] means that
  the goal in question is Subgoal 1.3 of the 1st forcing round.  To
  supply a hint for use in the proof of that subgoal, you should use
  the goal specifier ~c[\"[1~]Subgoal 1.3\"].  ~l[goal-spec].

  When a round is successfully completed ~-[] and for these purposes you
  may think of the proof of the main goal as being the 0th forcing
  round ~-[] the system collects all of the assumptions ~il[force]d by the
  just-completed round.  Here, an assumption should be thought of as
  an implication, ~c[(implies context hyp)], where context describes the
  context in which hyp was assumed true.  Before undertaking the
  proofs of these assumptions, we try to ``clean them up'' in an
  effort to reduce the amount of work required.  This is often
  possible because the ~il[force]d assumptions are generated by the same
  rule being applied repeatedly in a given context.

  By delaying and collecting the ~c[forced] assumptions until the
  completion of the ``main goal'' we gain two advantages.  First, the
  user gets confirmation that the ``gist'' of the proof is complete
  and that all that remains are ``technical details.''  Second, by
  delaying the proofs of the ~il[force]d assumptions ACL2 can undertake the
  proof of each assumption only once, no matter how many times it was
  ~il[force]d in the main goal.

  In order to indicate which proof steps of the previous round were
  responsible for which ~il[force]d assumptions, we print a sentence
  explaining the origins of each newly ~il[force]d goal.  For example,
  ~bv[]
  [1]Subgoal 1, below, will focus on
  (GOOD-INPUTP (XTRANS I)),
  which was forced in
   Subgoal 14, above,
    by applying (:REWRITE PRED-CRUNCHER) to
    (PRED (XTRANS I) I),
   and
   Subgoal 28, above,
    by applying (:REWRITE PRED-CRUNCHER) to
    (PRED (XTRANS I) I).
  ~ev[]

  In this entry, ``[1]Subgoal 1'' is the name of a goal which will be
  proved in the next forcing round.  On the next line we display the
  ~il[force]d hypothesis, call it ~c[x], which is
  ~c[(good-inputp (xtrans i))] in this example.  This term will be the
  conclusion of the new subgoal.  Since the new subgoal will be
  printed in its entirety when its proof is undertaken, we do not here
  exhibit the context in which ~c[x] was ~il[force]d.  The sentence then
  lists (possibly a succession of) a goal name from the just-completed
  round and some step in the proof of that goal that ~il[force]d ~c[x].  In
  the example above we see that Subgoals 14 and 28 of the
  just-completed proof ~il[force]d ~c[(good-inputp (xtrans i))] by applying
  ~c[(:rewrite pred-cruncher)] to the term ~c[(pred (xtrans i) i)].

  If one were to inspect the theorem prover's description of the proof
  steps applied to Subgoals 14 and 28 one would find the word
  ``~il[force]d'' (or sometimes ``forcibly'') occurring in the commentary.
  Whenever you see that word in the output, you know you will get a
  subsequent forcing round to deal with the hypotheses ~il[force]d.
  Similarly, if at the beginning of a forcing round a ~il[rune] is blamed
  for causing a ~il[force] in some subgoal, inspection of the commentary
  for that subgoal will reveal the word ``~il[force]d'' after the rule name
  blamed.

  Most ~il[force]d hypotheses come from within the prover's simplifier.
  When the simplifier encounters a hypothesis of the form ~c[(force hyp)]
  it first attempts to establish it by rewriting ~c[hyp] to, say, ~c[hyp'].
  If the truth or falsity of ~c[hyp'] is known, forcing is not required.
  Otherwise, the simplifier actually ~il[force]s ~c[hyp'].  That is, the ~c[x]
  mentioned above is ~c[hyp'], not ~c[hyp], when the ~il[force]d subgoal was
  generated by the simplifier.

  Once the system has printed out the origins of the newly ~il[force]d
  goals, it proceeds to the next forcing round, where those goals are
  individually displayed and attacked.

  At the beginning of a forcing round, the ~il[enable]d structure defaults
  to the global ~il[enable]d structure.  For example, suppose some ~il[rune],
  ~c[rune], is globally ~il[enable]d.  Suppose in some event you ~il[disable] the
  ~il[rune] at ~c[\"Goal\"] and successfully prove the goal but ~il[force] ~c[\"[1~]Goal\"].
  Then during the proof of ~c[\"[1~]Goal\"], ~il[rune] is ~il[enable]d ``again.''  The
  right way to think about this is that the ~il[rune] is ``still'' ~il[enable]d.
  That is, it is ~il[enable]d globally and each forcing round resumes with
  the global ~il[enable]d structure.")

(deflabel failure
  :doc
  ":Doc-Section Miscellaneous

  how to deal with a proof failure~/

  When ACL2 gives up it does not mean that the submitted conjecture is invalid,
  even if the last formula ACL2 printed in its proof attempt is manifestly
  false.  Since ACL2 sometimes ~il[generalize]s the goal being proved, it is
  possible it adopted an invalid subgoal as a legitimate (but doomed) strategy
  for proving a valid goal.  Nevertheless, conjectures submitted to ACL2 are
  often invalid and the proof attempt often leads the careful reader to the
  realization that a hypothesis has been omitted or that some special case has
  been forgotten.  It is good practice to ask yourself, when you see a proof
  attempt fail, whether the conjecture submitted is actually a theorem.~/

  If you think the conjecture is a theorem, then you must figure out from
  ACL2's output what you know that ACL2 doesn't about the functions in the
  conjecture and how to impart that knowledge to ACL2 in the form of rules.
  The ``key checkpoint'' information printed at the end of the summary provides
  a fine place to start.  ~l[the-method] for a general discussion of how to
  prove theorems with ACL2.  Also ~pl[set-gag-mode] for discussion of key
  checkpoints and an abbreviated output mode that focuses attention on them.
  You may find it most useful to start by focusing on key checkpoints that are
  not under a proof by induction, if any, both because these are more likely to
  suggest useful lemmas and because they are more likely to be theorems; for
  example, generalization may have occurred before a proof by induction has
  begun.  If you need more information than is provided by the key checkpoints
  ~-[] although this should rarely be necessary ~-[] then you can look at the
  full proof, perhaps with the aid of certain utilities: ~pl[proof-tree],
  ~pl[set-gag-mode], and ~pl[set-saved-output].

  For information on a tool to help debug failures of ~ilc[encapsulate] and
  ~ilc[progn] events, as well as ~ilc[certify-book] failures, ~pl[redo-flat].

  See also the book ``Computer-Aided Reasoning: An Approach'' (Kaufmann,
  Manolios, Moore), as well as the discussion of how to read Nqthm proofs and how
  to use Nqthm rules in ``A Computational Logic Handbook'' by Boyer and Moore
  (Academic Press, 1988).

  If the failure occurred during a forcing round, ~pl[failed-forcing].")

(deflabel failed-forcing
  :doc
  ":Doc-Section Miscellaneous

  how to deal with a proof ~il[failure] in a forcing round~/

  ~l[forcing-round] for a background discussion of the notion of
  forcing rounds.  When a proof fails during a forcing round it means
  that the ``gist'' of the proof succeeded but some ``technical
  detail'' failed.  The first question you must ask yourself is
  whether the ~il[force]d goals are indeed theorems.  We discuss the
  possibilities below.~/

  If you believe the ~il[force]d goals are theorems, you should follow the
  usual methodology for ``fixing'' failed ACL2 proofs, e.g., the
  identification of key lemmas and their timely and proper use as
  rules.  ~l[failure] and ~pl[proof-tree].

  The rules designed for the goals of forcing rounds are often just
  what is needed to prove the ~il[force]d hypothesis at the time it is
  ~il[force]d.  Thus, you may find that when the system has been ``taught''
  how to prove the goals of the forcing round no forcing round is
  needed.  This is intended as a feature to help structure the
  discovery of the necessary rules.

  If a hint must be provided to prove a goal in a forcing round, the
  appropriate ``goal specifier'' (the string used to identify the goal
  to which the hint is to be applied) is just the text printed on the
  line above the formula, e.g., ~c[\"[1~]Subgoal *1/3''\"].
  ~l[goal-spec].

  If you solve a forcing problem by giving explicit ~il[hints] for the
  goals of forcing rounds, you might consider whether you could avoid
  forcing the assumption in the first place by giving those ~il[hints] in
  the appropriate places of the main proof.  This is one reason that
  we print out the origins of each ~il[force]d assumption.  An argument
  against this style, however, is that an assumption might be ~il[force]d
  in hundreds of places in the main goal and proved only once in the
  forcing round, so that by delaying the proof you actually save time.

  We now turn to the possibility that some goal in the forcing round
  is not a theorem.

  There are two possibilities to consider.  The first is that the
  original theorem has insufficient hypotheses to ensure that all the
  ~il[force]d hypotheses are in fact always true.  The ``fix'' in this case
  is to amend the original conjecture so that it has adequate
  hypotheses.

  A more difficult situation can arise and that is when the conjecture
  has sufficient hypotheses but they are not present in the forcing
  round goal.  This can be caused by what we call ``premature''
  forcing.

  Because ACL2 rewrites from the inside out, it is possible that it
  will ~il[force] hypotheses while the context is insufficient to establish
  them.  Consider trying to prove ~c[(p x (foo x))].  We first rewrite the
  formula in an empty context, i.e., assuming nothing.  Thus, we
  rewrite ~c[(foo x)] in an empty context.  If rewriting ~c[(foo x)] ~il[force]s
  anything, that ~il[force]d assumption will have to be proved in an empty
  context.  This will likely be impossible.

  On the other hand, suppose we did not attack ~c[(foo x)] until after we
  had expanded ~c[p].  We might find that the value of its second
  argument, ~c[(foo x)], is relevant only in some cases and in those cases
  we might be able to establish the hypotheses ~il[force]d by ~c[(foo x)].  Our
  premature forcing is thus seen to be a consequence of our ``over
  eager'' rewriting.

  Here, just for concreteness, is an example you can try.  In this
  example, ~c[(foo x)] rewrites to ~c[x] but has a ~il[force]d hypothesis of
  ~c[(rationalp x)].  ~c[P] does a case split on that very hypothesis
  and uses its second argument only when ~c[x] is known to be rational.
  Thus, the hypothesis for the ~c[(foo x)] rewrite is satisfied.  On
  the false branch of its case split, ~c[p] simplies to ~c[(p1 x)] which
  can be proved under the assumption that ~c[x] is not rational.

  ~bv[]
  (defun p1 (x) (not (rationalp x)))
  (defun p (x y)(if (rationalp x) (equal x y) (p1 x)))
  (defun foo (x) x)
  (defthm foo-rewrite (implies (force (rationalp x)) (equal (foo x) x)))
  (in-theory (disable foo))
  ~ev[]
  The attempt then to do ~c[(thm (p x (foo x)))] ~il[force]s the unprovable
  goal ~c[(rationalp x)].

  Since all ``formulas'' are presented to the theorem prover as single
  terms with no hypotheses (e.g., since ~ilc[implies] is a function), this
  problem would occur routinely were it not for the fact that the
  theorem prover expands certain ``simple'' definitions immediately
  without doing anything that can cause a hypothesis to be ~il[force]d.
  ~l[simple].  This does not solve the problem, since it is
  possible to hide the propositional structure arbitrarily deeply.
  For example, one could define ~c[p], above, recursively so that the test
  that ~c[x] is rational and the subsequent first ``real'' use of ~c[y]
  occurred arbitrarily deeply.

  Therefore, the problem remains: what do you do if an impossible goal
  is ~il[force]d and yet you know that the original conjecture was
  adequately protected by hypotheses?

  One alternative is to disable forcing entirely.
  ~l[disable-forcing].  Another is to ~il[disable] the rule that
  caused the ~il[force].

  A third alternative is to prove that the negation of the main goal
  implies the ~il[force]d hypothesis.  For example,
  ~bv[]
  (defthm not-p-implies-rationalp
    (implies (not (p x (foo x))) (rationalp x))
    :rule-classes nil)
  ~ev[]
  Observe that we make no rules from this formula.  Instead, we
  merely ~c[:use] it in the subgoal where we must establish ~c[(rationalp x)].
  ~bv[]
  (thm (p x (foo x))
       :hints ((\"Goal\" :use not-p-implies-rationalp)))
  ~ev[]
  When we said, above, that ~c[(p x (foo x))] is first rewritten in an
  empty context we were misrepresenting the situation slightly.  When
  we rewrite a literal we know what literal we are rewriting and we
  implicitly assume it false.  This assumption is ``dangerous'' in
  that it can lead us to simplify our goal to ~c[nil] and give up ~-[] we
  have even seen people make the mistake of assuming the negation of
  what they wished to prove and then via a very complicated series of
  transformations convince themselves that the formula is false.
  Because of this ``tail biting'' we make very weak use of the
  negation of our goal.  But the use we make of it is sufficient to
  establish the ~il[force]d hypothesis above.

  A fourth alternative is to weaken your desired theorem so as to make
  explicit the required hypotheses, e.g., to prove
  ~bv[]
  (defthm rationalp-implies-main
    (implies (rationalp x) (p x (foo x)))
    :rule-classes nil)
  ~ev[]
  This of course is unsatisfying because it is not what you
  originally intended.  But all is not lost.  You can now prove your
  main theorem from this one, letting the ~ilc[implies] here provide the
  necessary case split.
  ~bv[]
  (thm (p x (foo x))
       :hints ((\"Goal\" :use rationalp-implies-main)))
  ~ev[]")

(defun quickly-count-assumptions (ttree n mx)

; If there are no 'assumption tags in ttree, return 0.  If there are fewer than
; mx, return the number there are.  Else return mx.  Mx must be greater than 0.
; The soundness of the system depends on this function returning 0 only if
; there are no assumptions.

  (cond ((null ttree) n)
        ((symbolp (caar ttree))
         (cond ((eq (caar ttree) 'assumption)
                (let ((n+1 (1+ n)))
                  (cond ((= n+1 mx) mx)
                        (t (quickly-count-assumptions (cdr ttree) n+1 mx)))))
               (t (quickly-count-assumptions (cdr ttree) n mx))))
        (t (let ((n+car (quickly-count-assumptions (car ttree) n mx)))
             (cond ((= n+car mx) mx)
                   (t (quickly-count-assumptions (cdr ttree) n+car mx)))))))

(defun add-type-alist-runes-to-ttree (type-alist ttree)
  (cond ((endp type-alist)
         ttree)
        (t (add-type-alist-runes-to-ttree
            (cdr type-alist)
            (push-lemmas (all-runes-in-ttree (cddr (car type-alist))
                                             nil)
                         ttree)))))

(defun process-assumptions-ttree (assns ttree)

; Assns is a list of assumptions records.  We extend ttree with all runes in
; assns.

  (cond ((endp assns) ttree)
        (t (process-assumptions-ttree
            (cdr assns)
            (add-type-alist-runes-to-ttree (access assumption (car assns)
                                                   :type-alist)
                                           ttree)))))

(defun process-assumptions (forcing-round pspv wrld state)

; This function is called when prove-loop1 appears to have won the
; indicated forcing-round, producing pspv.  We inspect the :tag-tree
; in pspv and determines whether there are forced 'assumptions in it.
; If so, the "win" reported is actually conditional upon the
; successful relieving of those assumptions.  We create an appropriate
; set of clauses to prove, new-clauses, each paired with a list of
; assumnotes.  We also return a modified pspv, new-pspv,
; just like pspv except with the assumptions stripped out of its
; :tag-tree.  We do the output related to explaining all this to the
; user and return (mv new-clauses new-pspv state).  If new-clauses is
; nil, then the proof is really done.  Otherwise, we are obliged to
; prove new-clauses under new-pspv and should do so in another "round"
; of forcing.

  (let ((n (quickly-count-assumptions (access prove-spec-var pspv :tag-tree)
                                      0
                                      101)))
    (pprogn
     (cond
      ((= n 0)
       (pprogn

; We normally print "Q.E.D." for a successful proof done in gag-mode even if
; proof output is inhibited.  However, if summary output is also inhibited,
; then we guess that the user probably would prefer not to be bothered seeing
; the "Q.E.D.".

        (if (and (saved-output-token-p 'prove state)
                 (member-eq 'prove (f-get-global 'inhibit-output-lst state))
                 (not (member-eq 'summary (f-get-global 'inhibit-output-lst
                                                        state))))
            (fms "Q.E.D.~%" nil (proofs-co state) state nil)
          state)
        (io? prove nil state nil
             (fms "Q.E.D.~%" nil (proofs-co state) state nil))))
      ((< n 101)
       (io? prove nil state (n)
            (fms "q.e.d. (given ~n0 forced ~#1~[hypothesis~/hypotheses~])~%"
                 (list (cons #\0 n)
                       (cons #\1 (if (= n 1) 0 1)))
                 (proofs-co state) state nil)))
      (t
       (io? prove nil state nil
            (fms "q.e.d. (given over 100 forced hypotheses which we now ~
                 collect)~%"
                 nil
                 (proofs-co state) state nil))))
     (mv-let
      (n0 assns pairs ttree1)
      (extract-and-clausify-assumptions
       nil ;;; irrelevant with only-immediatep = nil
       (access prove-spec-var pspv :tag-tree)
       nil ;;; all assumptions, not only-immediatep

; Note: We here obtain the enabled structure.  Because the rewrite-constant of
; the pspv is restored after being smashed by hints, we know that this enabled
; structure is in fact the one in the pspv on which prove was called, which is
; the global enabled structure if prove was called by defthm.

       (access rewrite-constant
               (access prove-spec-var pspv
                       :rewrite-constant)
               :current-enabled-structure)
       wrld)
      (cond
       ((= n0 0)
        (mv nil pspv state))
       (t
        (pprogn
         (process-assumptions-msg
          forcing-round n0 (length assns) pairs state)
         (mv pairs
             (change prove-spec-var pspv
                     :tag-tree (process-assumptions-ttree assns ttree1)

; Note: In an earlier version of this code, we failed to set :otf-flg here and
; that caused us to backup and try to prove the original thm (i.e., "Goal") by
; induction.

                     :otf-flg t)
             state))))))))

(defun do-not-induct-msg (forcing-round pool-lst state)

; We print a message explaining that because of :do-not-induct, we quit.

; This function increments timers.  Upon entry, the accumulated time is
; charged to 'prove-time.  The time spent in this function is charged
; to 'print-time.

  (io? prove nil state
       (forcing-round pool-lst)
       (pprogn
        (increment-timer 'prove-time state)

; It is probably a good idea to keep the following wording in sync with
; push-clause-msg1.

        (fms "Normally we would attempt to prove ~@0 by induction.  However, a ~
             :DO-NOT-INDUCT hint was supplied to abort the proof attempt.~|"
             (list (cons #\0
                         (tilde-@-pool-name-phrase
                          forcing-round
                          pool-lst)))
             (proofs-co state)
             state
             nil)
        (increment-timer 'print-time state))))

(defun prove-loop2 (forcing-round pool-lst clauses pspv hints ens wrld ctx
                                  state step-limit)

; We are given some clauses to prove.  Forcing-round and pool-lst are the first
; two fields of the clause-ids for the clauses.  The pool of the prove spec
; var, pspv, in general contains some more clauses to work on, as well as some
; clauses tagged 'being-proved-by-induction.  In addition, the pspv contains
; the proper settings for the induction-hyp-terms and induction-concl-terms.

; Actually, when we are beginning a forcing round other than the first, clauses
; is really a list of pairs (assumnotes . clause).

; We pour all the clauses over the waterfall.  They tumble into the pool in
; pspv.  If the pool is then empty, we are done.  Otherwise, we pick one to
; induct on, do the induction and repeat.

; We either cause an error or return (as the "value" result in the usual
; error/value/state triple) the final tag-tree.  That tag-tree might contain
; some byes, indicating that the proof has failed.

; WARNING:  A non-erroneous return is not equivalent to success!

  (sl-let (erp pspv jppl-flg state)
          (pstk
           (waterfall forcing-round pool-lst clauses pspv hints ens wrld
                      ctx state step-limit))
          (cond
           (erp (mv step-limit t nil state))
           (t
            (mv-let
             (signal pool-lst clauses hint-settings pspv state)
             (pstk
              (pop-clause forcing-round pspv jppl-flg state))
             (cond
              ((eq signal 'win)
               (mv-let
                (pairs new-pspv state)
                (pstk
                 (process-assumptions forcing-round pspv wrld state))
                (mv-let
                 (erp ttree state)
                 (accumulate-ttree-and-step-limit-into-state
                  (access prove-spec-var new-pspv :tag-tree)
                  step-limit
                  state)
                 (assert$
                  (null erp)
                  (cond ((null pairs) 
                         (mv step-limit nil ttree state))
                        (t (prove-loop2 (1+ forcing-round)
                                        nil
                                        pairs
                                        (initialize-pspv-for-gag-mode new-pspv)
                                        hints ens wrld ctx state
                                        step-limit)))))))

; The following case can probably be removed.  It is probably left over from
; some earlier implementation of pop-clause.  The earlier code for the case
; below returned (value (access prove-spec-var pspv :tag-tree)), this case, and
; was replaced by the hard error on 5/5/00.

              ((eq signal 'bye)
               (mv
                step-limit
                t
                (er hard ctx
                    "Surprising case in prove-loop2; please contact the ACL2 ~
                     implementors!")
                state))
              ((eq signal 'lose)
               (mv step-limit t nil state))
              ((and (cdr (assoc-eq :do-not-induct hint-settings))
                    (not (assoc-eq :induct hint-settings)))

; There is at least one goal left to prove, yet :do-not-induct is currently in
; force.  How can that be?  The user may have supplied :do-not-induct t while
; also supplying :otf-flg t.  In that case, push-clause will return a "hit".  We
; believe that the hint-settings current at this time will reflect the
; appropriate action if :do-not-induct t is intended here, i.e., the test above
; will put us in this case and we will abort the proof.

               (pprogn (do-not-induct-msg forcing-round pool-lst state)
                       (mv step-limit t nil state)))
              (t
               (mv-let
                (signal clauses pspv state)
                (pstk
                 (induct forcing-round pool-lst clauses hint-settings pspv wrld
                         ctx state))

; We do not call maybe-warn-about-theory-from-rcnsts below, because we already
; made such a call before the goal was pushed for proof by induction.

                (cond ((eq signal 'lose)
                       (mv step-limit t nil state))
                      (t (prove-loop2 forcing-round
                                      pool-lst
                                      clauses
                                      pspv
                                      hints
                                      ens
                                      wrld
                                      ctx
                                      state
                                      step-limit)))))))))))

(defun prove-loop1 (forcing-round pool-lst clauses pspv hints ens wrld ctx
                                  state)
  (sl-let
   (erp val state)
   (catch-step-limit
    (prove-loop2 forcing-round pool-lst clauses pspv hints ens wrld ctx
                 state
                 (initial-step-limit wrld state)))
   (pprogn (f-put-global 'last-step-limit step-limit state)
           (mv erp val state))))

(defun print-pstack-and-gag-state (state)
  (prog2$
   (cw
    "Here is the current pstack [see :DOC pstack]:")
   (mv-let (erp val state)
           (pstack)
           (declare (ignore erp val))
           (print-gag-state state))))

(defun prove-loop0 (clauses pspv hints ens wrld ctx state)

; Warning: Because this function binds in-prove-flg to t, it should be called
; only when *acl2-time-limit* has been let-bound.

; The perhaps unusual structure below is intended to invoke
; print-pstack-and-gag-state only when there is a hard error such as an
; interrupt.  In the normal failure case, the pstack is not printed and the
; key checkpoint summary (from the gag-state) is printed after the summary.

  (state-global-let*
   ((guard-checking-on nil) ; see the Essay on Guard Checking
    (in-prove-flg t))
   (mv-let (interrupted-p erp-val state)
           (acl2-unwind-protect
            "prove-loop"
            (mv-let (erp val state)
                    (prove-loop1 0 nil clauses pspv hints ens wrld ctx
                                 state)
                    (mv nil (cons erp val) state))
            (print-pstack-and-gag-state state)
            state)
           (cond (interrupted-p (mv t nil state))
                 (t (mv (car erp-val) (cdr erp-val) state))))))

(defmacro bind-acl2-time-limit (form)

; The raw Lisp code for this macro arranges that *acl2-time-limit* is restored
; to its global value (presumably nil) after we exit its top-level call.
; Consider the following key example of how this can work.  Suppose
; *acl2-time-limit* is set to 0 by our-abort because of an interrupt.
; Inspection of the code for our-abort shows that *acl2-time-limit-boundp* must
; be true in that case; but then we must be in the dynamic scope of
; bind-acl2-time-limit, as that is the only legal way for
; *acl2-time-limit-boundp* to be bound or set.  But inside bind-acl2-time-limit
; we are only modifying a let-bound *acl2-time-limit*, not its global value.
; In summary, setting *acl2-time-limit* to 0 by our-abort will not change the
; global value of *acl2-time-limit*.

  #-acl2-loop-only
  `(if *acl2-time-limit-boundp*
       ,form
     (let ((*acl2-time-limit-boundp* t)
           (*acl2-time-limit* *acl2-time-limit*))
       ,form))
  #+acl2-loop-only
  form)

(defun prove-loop (clauses pspv hints ens wrld ctx state)

; We either cause an error or return a ttree.  If the ttree contains
; :byes, the proof attempt has technically failed, although it has
; succeeded modulo the :byes.

  #-acl2-loop-only
  (setq *deep-gstack* nil) ; in case we never call initial-gstack
  #+(and hons (not acl2-loop-only))
  (when (memoizedp-raw 'worse-than)
    (clear-memoize-table 'worse-than))
  (prog2$ (clear-pstk)
          (pprogn
           (increment-timer 'other-time state)
           (f-put-global 'bddnotes nil state)
           (if (gag-mode)
               (pprogn (f-put-global 'gag-state *initial-gag-state* state)
                       (f-put-global 'gag-state-saved nil state))
             state)
           (mv-let (erp ttree state)
                   (bind-acl2-time-limit ; make *acl2-time-limit* be let-bound
                    (prove-loop0 clauses pspv hints ens wrld ctx state))
                   (pprogn
                    (increment-timer 'prove-time state)
                    (cond
                     (erp (mv erp nil state))
                     (t (value ttree))))))))

(defmacro make-rcnst (ens wrld &rest args)

; (Make-rcnst w) will make a rewrite-constant that is the result of filling in
; *empty-rewrite-constant* with a few obviously necessary values, such as the
; global-enabled-structure as the :current-enabled-structure.  More generally,
; you may use args to supply a list of additional alternating keyword/value
; pairs to override what is otherwise created.  E.g.,

; (make-rcnst w :expand-lst lst)

; will make a rewrite-constant that is like the empty one except that it will
; have lst as the :expand-lst.

; Note: Wrld and ens are only used in the "default" setting of
; :current-enabled-structure -- a setting overridden by any explicit one in
; args.

  `(change rewrite-constant
           (change rewrite-constant
                   *empty-rewrite-constant*
                   :current-enabled-structure ,ens
                   :oncep-override (match-free-override ,wrld)
                   :case-split-limitations (case-split-limitations ,wrld)
                   :nonlinearp (non-linearp ,wrld)
                   :backchain-limit-rw (backchain-limit ,wrld :rewrite))
           ,@args))

(defmacro make-pspv (ens wrld &rest args)

; This macro is similar to make-rcnst, which is a little easier to understand.
; (make-pspv ens w) will make a pspv that is just *empty-prove-spec-var* except
; that the rewrite constant is (make-rcnst ens w).  More generally, you may use
; args to supply a list of alternating keyword/value pairs to override the
; default settings.  E.g.,

; (make-pspv w :rewrite-constant rcnst :displayed-goal dg)

; will make a pspv that is like the empty one except for the two fields
; listed above.

; Note: Ens and wrld are only used in the default setting of the
; :rewrite-constant.  If you supply a :rewrite-constant in args, then ens and
; wrld are actually irrelevant.

  `(change prove-spec-var
           (change prove-spec-var *empty-prove-spec-var*
                   :rewrite-constant (make-rcnst ,ens ,wrld))
           ,@args))

(defun chk-assumption-free-ttree (ttree ctx state)

; Let ttree be the ttree about to be returned by prove.  We do not
; want this tree to contain any 'assumption tags because that would be
; a sign that an assumption got ignored.  For similar reasons, we do
; not want it to contain any 'fc-derivation tags -- assumptions might
; be buried therein.  This function checks these claimed invariants of
; the final ttree and causes an error if they are violated.

; A predicate version of this function is assumption-free-ttreep and
; it should be kept in sync with this function.

; While this function causes a hard error, its functionality is that
; of a soft error because it is so like our normal checkers.

  (cond ((tagged-object 'assumption ttree)
         (mv t
             (er hard ctx
                 "The 'assumption ~x0 was found in the final ttree!"
                 (tagged-object 'assumption ttree))
             state))
        ((tagged-object 'fc-derivation ttree)
         (mv t
             (er hard ctx
                 "The 'fc-derivation ~x0 was found in the final ttree!"
                 (tagged-object 'fc-derivation ttree))
             state))
        (t (value nil))))

#+(and write-arithmetic-goals (not acl2-loop-only))
(when (not (boundp '*arithmetic-goals-fns*))
  (defconstant *arithmetic-goals-fns*
    '(< = abs acl2-numberp binary-* binary-+ case-split complex-rationalp
        denominator equal evenp expt fix floor force if iff ifix implies integerp
        mod natp nfix not numerator oddp posp rationalp synp unary-- unary-/
        zerop zip zp signum booleanp nonnegative-integer-quotient rem truncate
        ash lognot binary-logand binary-logior binary-logxor)))

#+(and write-arithmetic-goals (not acl2-loop-only))
(when (not (boundp '*arithmetic-goals-filename*))
  (defconstant *arithmetic-goals-filename*
; Be sure to delete ~/write-arithmetic-goals.lisp before starting a regression.
; (This is done by GNUmakefile.)
    (let ((home (our-user-homedir-pathname)))
      (cond (home
             (merge-pathnames home "write-arithmetic-goals.lisp"))
            (t (error "Unable to determine (user-homedir-pathname)."))))))

(defun prove (term pspv hints ens wrld ctx state)

; Term is a translated term.  Displayed-goal is any object and is
; irrelevant except for output purposes.  Hints is a list of pairs
; as returned by translate-hints.

; We try to prove term using the given hints and the rules in wrld.

; Note: Having prove use hints is a break from nqthm, where only
; prove-lemma used hints.

; This function returns the traditional three values of an error
; producing/output producing function.  The first value is a Boolean
; that indicates whether an error occurred.  We cause an error if we
; terminate without proving term.  Hence, if the first result is nil,
; term was proved.  The second is a ttree that describes the proof, if
; term is proved.  The third is the final value of state.

; Displayed-goal is relevant only for output purposes.  We assume that
; this object was prettyprinted to the user before prove was called
; and is, in the user's mind, what is being proved.  For example,
; displayed-goal might be the untranslated -- or pre-translated --
; form of term.  The only use made of displayed-goal is that if the
; very first transformation we make produces a clause that we would
; prettyprint as displayed-goal, we hide that transformation from the
; user.

; Commemorative Plaque:

; We began the creation of the ACL2 with an empty GNU Emacs buffer on
; August 14, 1989.  The first few days were spent writing down the
; axioms for the most primitive functions.  We then began writing
; experimental applicative code for macros such as cond and
; case-match.  The first weeks were dizzying because of the confusion
; in our minds over what was in the logic and what was in the
; implementation.  On November 3, 1989, prove was debugged and
; successfully did the associativity of append.  During that 82 days
; we worked our more or less normal 8 hours, plus an hour or two on
; weekday nights.  In general we did not work weekends, though there
; might have been two or three where an 8 hour day was put in.  We
; worked separately, "contracting" with one another to do the various
; parts and meeting to go over the code.  Bill Schelter was extremely
; helpful in tuning akcl for us.  Several times we did massive
; rewrites as we changed the subset or discovered new programming
; styles.  During that period Moore went to the beach at Rockport one
; weekend, to Carlsbad Caverns for Labor Day, to the University of
; Utah for a 4 day visit, and to MIT for a 4 day visit.  Boyer taught
; at UT from September onwards.  These details are given primarily to
; provide a measure of how much effort it was to produce this system.
; In all, perhaps we have spent 60 8 hour days each on ACL2, or about
; 1000 man hours.  That of course ignores totally the fact that we
; have thought about little else during the past three months, whether
; coding or not.

; The system as it stood November 3, 1989, contained the complete
; nqthm rewriter and simplifier (including metafunctions, compound
; recognizers, linear and a trivial cut at congruence relations that
; did not connect to the user-interface) and induction.  It did not
; include destructor elimination, cross-fertilization, generalization
; or the elimination of irrelevance.  It did not contain any notion of
; hints or disabledp.  The system contained full fledged
; implementations of the definitional principle (with guards and
; termination proofs) and defaxiom (which contains all of the code to
; generate and store rules).  The system did not contain the
; constraint or functional instantiation events or books.  We have not
; yet had a "code walk" in which we jointly look at every line.  There
; are known bugs in prove (e.g., induction causes a hard error when no
; candidates are found).

; Matt Kaufmann officially joined the project in August, 1993.  He had
; previously generated a large number of comments, engaged in a number of
; design discussions, and written some code.

; Bob Boyer requested that he be removed as a co-author of ACL2 in April, 1995,
; because, in his view, he has worked so much less on the project in the last
; few years than Kaufmann and Moore.

; End of Commemorative Plaque

; This function increments timers.  Upon entry, the accumulated time is
; charged to 'other-time.  The time spent in this function is divided
; between both 'prove-time and to 'print-time.

  (cond
   ((ld-skip-proofsp state) (value nil))
   (t
    #+(and write-arithmetic-goals (not acl2-loop-only))
    (when (ffnnames-subsetp term *arithmetic-goals-fns*)
      (with-open-file (str *arithmetic-goals-filename*
                           :direction :output
                           :if-exists :append
                           :if-does-not-exist :create)
                      (let ((*print-pretty* nil)
                            (*package* (find-package-fast "ACL2"))
                            (*readtable* *acl2-readtable*)
                            (*print-escape* t)
                            *print-level*
                            *print-length*)
                        (prin1 term str)
                        (terpri str)
                        (force-output str))))
    (prog2$
     (prog2$ (initialize-brr-stack state)
             (initialize-fc-wormhole-sites))
     (er-let* ((ttree1 (prove-loop (list (list term))
                                   (change prove-spec-var pspv
                                           :user-supplied-term term
                                           :orig-hints hints)
                                   hints ens wrld ctx state)))
              (er-progn
               (chk-assumption-free-ttree ttree1 ctx state)
               (cond
                ((tagged-object :bye ttree1)
                 (let ((byes (reverse (tagged-objects :bye ttree1 nil))))
                   (pprogn

; The use of ~*1 below instead of just ~&1 forces each of the defthm forms
; to come out on a new line indented 5 spaces.  As is already known with ~&1,
; it can tend to scatter the items randomly -- some on the left margin and others
; indented -- depending on where each item fits flat on the line first offered.

                    (io? prove nil state
                         (wrld byes)
                         (fms "To complete this proof you could try to admit the
                               following event~#0~[~/s~]:~|~%~*1~%See the ~
                               discussion of :by hints in :DOC hints ~
                               regarding the name~#0~[~/s~] displayed above."
                              (list (cons #\0 byes)
                                    (cons #\1
                                          (list ""
                                                "~|~     ~q*."
                                                "~|~     ~q*,~|and~|"
                                                "~|~     ~q*,~|~%" 
                                                (make-defthm-forms-for-byes
                                                 byes wrld))))
                              (proofs-co state)
                              state
                              (term-evisc-tuple nil state)))
                    (silent-error state))))
                (t (value ttree1)))))))))