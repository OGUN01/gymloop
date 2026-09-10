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

The main-branch database workflow `34450245473` applied the migration, passed
schema drift, and completed its 49 files / 4385 assertions database suite with
the seed successful. The main CI workflow `34450245469`, test-immutability
workflow `34450245595`, and holdout-placeholder workflow `34450245693` also
succeeded. No migration was applied manually.

## Browser verification

The signed-in owner opened Sneha Joshi's annual membership after CI applied the
migration. The screen showed INR 10800.00 per period, payment default 10800.00,
and the same 10800.00 in the full-year explanation. The annual plan option
correctly retained its INR 12000.00 catalogue price. The historical dates still
read 2025-09-12 through 2026-09-12. This was a read-only check; no payment or
other demo mutation was made.

A read-only CLI query confirmed price 1200000, discount 120000, eligible total
1080000 paise, periods_granted 1, active status and the unchanged historical
dates after the CI apply.
