; VL Verilog Toolkit
; Copyright (C) 2008-2012 Centaur Technology
;
; Contact:
;   Centaur Technology Formal Verification Group
;   7600-C N. Capital of Texas Highway, Suite 300, Austin, TX 78731, USA.
;   http://www.centtech.com/
;
; This program is free software; you can redistribute it and/or modify it under
; the terms of the GNU General Public License as published by the Free Software
; Foundation; either version 2 of the License, or (at your option) any later
; version.  This program is distributed in the hope that it will be useful but
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
; more details.  You should have received a copy of the GNU General Public
; License along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA 02110-1335, USA.
;
; Original author: Jared Davis <jared@centtech.com>

(in-package "VL")
(include-book "conditions")
(include-book "../../mlib/stmt-tools")
(local (include-book "../../util/arithmetic"))

(defxdoc unelse
  :parents (always-top)
  :short "Convert @('if/else') statements into blocks of independent
@('if')-statements."

  :long "<p>This is a preprocessing step in synthesizing always blocks.</p>

<p>The idea is to eliminate any else statements by turning an @('if/else')
statement into a pair of @('if') statements with inverted conditions.  That
is:</p>

@({
    if (cond)   -->   begin
       body1            if (cond) body1
    else                if (!cond) body2
       body2          end
})

<p>This gets us a little closer to @(see flopcode) programs.</p>

<p>We expect it to be run only after expressions are sized.</p>")

(define vl-ifstmt-unelse
  ((x "any statement, but we only rewrite it when it's an if statement;
       this makes writing @(see vl-stmt-unelse) very simple."
      (and (vl-stmt-p x)
           (vl-compoundstmt-p x))))
  :returns (new-x vl-stmt-p :hyp :fguard)
  :parents (unelse)
  :short "Just handles a single if statement (not recursive)."
  (b* (((unless (vl-ifstmt-p x))
        x)
       ((vl-ifstmt x) x)
       ((when (vl-fast-nullstmt-p x.falsebranch))
        ;; The else branch is already NULL, so this is fine, don't do any
        ;; rewriting.
        x)

       ((unless (and (vl-expr->finaltype x.condition)
                     (posp (vl-expr->finalwidth x.condition))
                     (vl-expr-welltyped-p x.condition)))
        ;; Doesn't seem good, let's leave it alone.  BOZO it'd be nice to issue
        ;; a warning instead of just silently not rewriting it.
        x)

       (!condition (vl-condition-neg x.condition))
       (nullstmt   (make-vl-nullstmt))
       (stmt1
        ;; if (condition) truebranch else ;
        (make-vl-ifstmt :condition   x.condition
                        :truebranch  x.truebranch
                        :falsebranch nullstmt))
       (stmt2
        ;; if (!condition) falsebranch else ;
        (make-vl-ifstmt :condition   !condition
                        :truebranch  x.falsebranch
                        :falsebranch nullstmt))
       (new-x
        ;; begin stmt1 stmt2 end
        (make-vl-blockstmt :sequentialp t
                           :stmts       (list stmt1 stmt2))))
    new-x))


(defsection vl-stmt-unelse
  :parents (unelse)
  :short "Recursively processes all the if statements."

  (mutual-recursion

   (defund vl-stmt-unelse (x)
     "Returns X-PRIME"
     (declare (xargs :guard (vl-stmt-p x)
                     :verify-guards nil
                     :measure (two-nats-measure (acl2-count x) 1)))
     (b* (((when (vl-fast-atomicstmt-p x))
           x)
          ;; Remove elses from any sub-statements
          (substmts (vl-compoundstmt->stmts x))
          (substmts (vl-stmtlist-unelse substmts))
          (x        (change-vl-compoundstmt x :stmts substmts)))
       ;; Possibly simplify the resulting statement
       (vl-ifstmt-unelse x)))

   (defund vl-stmtlist-unelse (x)
     "Returns X-PRIME"
     (declare (xargs :guard (vl-stmtlist-p x)
                     :verify-guards nil
                     :measure (two-nats-measure (acl2-count x) 0)))
     (if (atom x)
         nil
       (cons (vl-stmt-unelse (car x))
             (vl-stmtlist-unelse (cdr x))))))

  (flag::make-flag vl-flag-stmt-unelse
                   vl-stmt-unelse
                   :flag-mapping ((vl-stmt-unelse . stmt)
                                  (vl-stmtlist-unelse . list)))

  (defthm len-of-vl-stmtlist-unelse
    (equal (len (vl-stmtlist-unelse x))
           (len x))
    :hints(("Goal"
            :induct (len x)
            :expand (vl-stmtlist-unelse x))))

  (defthm-vl-flag-stmt-unelse
    (defthm return-type-of-vl-stmt-unelse
      (implies (force (vl-stmt-p x))
               (vl-stmt-p (vl-stmt-unelse x)))
      :flag stmt)
    (defthm return-type-of-vl-stmtlist-unelse
      (implies (force (vl-stmtlist-p x))
               (vl-stmtlist-p (vl-stmtlist-unelse x)))
      :flag list)
    :hints(("Goal"
            :expand ((vl-stmt-unelse x)
                     (vl-stmtlist-unelse x)))))

  (verify-guards vl-stmt-unelse))


(define vl-always-unelse ((x vl-always-p))
  :returns (new-x vl-always-p :hyp :fguard)
  :parents (unelse)
  (b* (((vl-always x) x)
       (stmt (vl-stmt-unelse x.stmt)))
    (change-vl-always x :stmt stmt)))

(defprojection vl-alwayslist-unelse (x)
  (vl-always-unelse x)
  :guard (vl-alwayslist-p x)
  :result-type vl-alwayslist-p
  :parents (unelse))

(define vl-module-unelse ((x vl-module-p))
  :returns (new-x vl-module-p :hyp :fguard)
  :parents (unelse)
  (b* (((vl-module x) x)
       ((when (vl-module->hands-offp x))
        x)
       ((unless x.alwayses)
        ;; Optimization: not going to do anything, don't bother re-consing the
        ;; module.
        x)
       (alwayses (vl-alwayslist-unelse x.alwayses)))
    (change-vl-module x :alwayses alwayses))
  ///
  (defthm vl-module->name-of-vl-module-unelse
    (equal (vl-module->name (vl-module-unelse x))
           (vl-module->name x))))

(defprojection vl-modulelist-unelse (x)
  (vl-module-unelse x)
  :guard (vl-modulelist-p x)
  :result-type vl-modulelist-p
  :rest
  ((defthm vl-modulelist->names-of-vl-modulelist-unelse
    (equal (vl-modulelist->names (vl-modulelist-unelse x))
           (vl-modulelist->names x)))))
