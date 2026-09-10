# Membership net price — verification

The agreed membership fee is the listed price minus its discount. INR 10800
fully buys the INR 12000 annual membership sold with INR 1200 off. Paid
discounts are immutable, and a discount cannot exceed its price.

## Independent verification

The contract and delegated owner authority were committed first (`5b041e9`).
Separate implementation-blind authors committed visible tests (`3fad26a`),
holdout tests (`ff77e37`) and post-seed holdout assertions (`dfa8566`) red.
The visible author also corrected two old trusted-writer control inputs to
remain inside the newly approved discount bounds (`9485d42`). The implementer
did not edit test files or read holdout source.

The candidate passed all 49 database files / 4385 assertions, with every plan
complete: the first full sweep passed 48 files, and the independently corrected
809-assertion payment file then passed separately. New coverage comprises 42
visible database assertions, 100 holdout assertions and 25 shared arithmetic
tests. Existing and isolated fresh seed runs each passed the independent three
assertions after both one and two runs. All database checks rolled back.

The isolated fresh seed harness remapped fixture UUIDs, gym code and the global
QR-token hash. It supplied the owner staff row required by seed-scenarios.sql,
which is normally provisioned separately; it created no Auth identity. Initial
harness attempts exposed those two missing prerequisites and rolled back.
Neither prerequisite was a net-price implementation defect.

A fresh Astra critic returned GO. The grant function changes only its price
input; the terms function adds discount to the existing paid-terms freeze.
The guarded historical correction counts the demo's already-paid annual span
once without moving its dates. The seed now restores both historical dates
after constructing its payment history.

## Gates and delivery

Local lint, typecheck, duplication, registry, dependency boundaries, dead-code,
escape-hatch, rollback, web/shared tests, 47 script tests and production build
passed. Registry initially rejected a helper row with a signature instead of
the exact exported name; the row was corrected and the gate passed.

CI application and browser verification are pending. No migration was applied
manually; the migration will be applied by the main-branch database workflow.
