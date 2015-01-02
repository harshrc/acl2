; Reverse lemmas
; Copyright (C) 2005-2013 Kookamara LLC
;
; Contact:
;
;   Kookamara LLC
;   11410 Windermere Meadows
;   Austin, TX 78759, USA
;   http://www.kookamara.com/
;
; License: (An MIT/X11-style license)
;
;   Permission is hereby granted, free of charge, to any person obtaining a
;   copy of this software and associated documentation files (the "Software"),
;   to deal in the Software without restriction, including without limitation
;   the rights to use, copy, modify, merge, publish, distribute, sublicense,
;   and/or sell copies of the Software, and to permit persons to whom the
;   Software is furnished to do so, subject to the following conditions:
;
;   The above copyright notice and this permission notice shall be included in
;   all copies or substantial portions of the Software.
;
;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;   DEALINGS IN THE SOFTWARE.
;
; Original author: Jared Davis <jared@kookamara.com>
;
; reverse.lisp
; This file was originally part of the Unicode library.

(in-package "ACL2")
(include-book "list-fix")
(local (include-book "revappend"))
(local (include-book "std/strings/coerce" :dir :system))

(defsection std/lists/reverse
  :parents (std/lists reverse)
  :short "Lemmas about @(see reverse) available in the @(see std/lists)
library."

  :long "<p>The built-in @(see reverse) function is overly complex because it
can operate on either lists or strings.  To reverse a list, it is generally
preferable to use @(see rev), which has a very simple definition.</p>

<p>We ordinarily expect @('reverse') to be enabled, in which case it
expands (in the list case) to @('(revappend x nil)'), which we generally expect
to be rewritten to @('(rev x)') due to the @('revappend-removal') theorem.</p>

<p>Because of this, we do not expect these lemmas to be very useful unless, for
some reason, you have disabled @('reverse') itself.</p>"

  (defthm stringp-of-reverse
    (equal (stringp (reverse x))
           (stringp x)))

  (defthm true-listp-of-reverse
    (equal (true-listp (reverse x))
           (not (stringp x))))

  (local (defthm len-zero
           (equal (equal 0 (len x))
                  (atom x))))

  (local
   (defsection revappend-lemma

     (local (defun ind (a b x y)
              (if (or (atom a)
                      (atom b))
                  (list a b x y)
                (ind (cdr a) (cdr b)
                     (cons (car a) x)
                     (cons (car b) y)))))

     (local (defthm l0
              (implies (and (equal (len a) (len b))
                            (equal (len x) (len y)))
                       (equal (equal (revappend a x)
                                     (revappend b y))
                              (and (equal (list-fix a) (list-fix b))
                                   (equal x y))))
              :hints(("Goal" :induct (ind a b x y)))))

     (local (defthm l1
              (implies (and (not (equal (len a) (len b)))
                            (equal (len x) (len y)))
                       (equal (equal (revappend a x)
                                     (revappend b y))
                              nil))
              :hints(("Goal"
                      :in-theory (disable len-of-revappend)
                      :use ((:instance len-of-revappend (x a) (y x))
                            (:instance len-of-revappend (x b) (y y)))))))

     (local (defthm l2
              (implies (not (equal (len a) (len b)))
                       (not (equal (list-fix a) (list-fix b))))
              :hints(("Goal"
                      :in-theory (disable len-of-list-fix)
                      :use ((:instance len-of-list-fix (x a))
                            (:instance len-of-list-fix (x b)))))))

     (defthm revappend-lemma
       (implies (equal (len x) (len y))
                (equal (equal (revappend a x)
                              (revappend b y))
                       (and (equal (list-fix a) (list-fix b))
                            (equal x y))))
       :hints(("Goal"
               :in-theory (disable l0 l1)
               :use ((:instance l0)
                     (:instance l1)))))))

  (defthm equal-of-reverses
    ;; And this is why we should never use "reverse."
    (equal (equal (reverse x) (reverse y))
           (if (or (stringp x) (stringp y))
               (and (stringp x)
                    (stringp y)
                    (equal x y))
             (equal (list-fix x) (list-fix y))))
    :hints(("Goal" :cases ((stringp x)
                           (stringp y))))))

