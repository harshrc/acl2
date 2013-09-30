(IN-PACKAGE "ACL2")

(INCLUDE-BOOK "gauss-fns")

(LOCAL (INCLUDE-BOOK "gauss-work"))

(SET-ENFORCE-REDUNDANCY T)

(DEFTHM ACL2-TOP-INV$INV
        (IMPLIES (GAUSS$INPUT-HYPS IN)
                 (G :ASN (ACL2-TOP-INV IN))))

