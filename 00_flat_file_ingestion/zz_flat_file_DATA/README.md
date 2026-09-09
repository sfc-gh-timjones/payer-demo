# flat_file_ingestion

Synthetic flat file demo data for the Payer RFP 26-038 demo.

## Files

| File | Records | Description |
|---|---|---|
| `data/pharmacy_claims.csv` | 25,000 rows | PBM pharmacy dispensing extract (OptumRx/CVS style) — clean |
| `data/medical_claims.xml` | 20,000 claims | Clearinghouse professional claims adjudication file (837P style) — clean |
| `data/pharmacy_claims_bad_records.csv` | 5,000 rows | Pharmacy extract with 5 load-breaking records for COPY INTO validation demo |
| `data/pharmacy_claims_add_refillnum.csv` | 1,000 rows | 21-column file adding REFILL_NUMBER (INTEGER) — for schema evolution demo |
| `data/pharmacy_claims_inc1.csv` | 1,000 rows | Incremental batch 1 — clean, for Snowpipe file-arrival demo |
| `data/pharmacy_claims_inc2.csv` | 1,000 rows | Incremental batch 2 — clean, for Snowpipe file-arrival demo |

## Bad Records (pharmacy_claims_bad_records.csv)

Five records that cause COPY INTO to reject the row when the target table has typed columns:

| Row | Error Type | Field | Bad Value |
|---|---|---|---|
| 312 | Numeric cast failure | `DAYS_SUPPLY` | `THIRTY-DAYS` |
| 891 | Numeric cast failure | `BILLED_AMOUNT` | `N/A` |
| 1,547 | Numeric cast failure | `QUANTITY_DISPENSED` | `MANY` |
| 2,983 | Numeric cast failure | `FORMULARY_TIER` | `GOLD` |
| 4,201 | Column count mismatch | *(row has 21 fields instead of 20)* | extra trailing field |

Demo with `VALIDATION_MODE = RETURN_ERRORS` to surface all 5 without loading, then reload with `ON_ERROR = CONTINUE` to show 4,995 good rows land and 5 are skipped.

## Regenerating

```bash
python3 generate_data.py
```

Requires Python 3.6+ (stdlib only — no pip installs needed). Seed is fixed (`random.seed(42)`) so output is reproducible.

## Data Model

### pharmacy_claims.csv (20 columns)
- Member IDs in `MBR-XXXXXXX` format (standalone — not Facets IDs)
- ~400 distinct members each with multiple fills across 25,000 rows
- 15 common Medi-Cal generics across 6 therapeutic categories
- Dates: Jul 2025 – Jun 2026
- Status mix: 85% PAID / 10% DENIED / 5% PENDING

### medical_claims.xml (20 fields per claim)
- Same `MBR-XXXXXXX` member ID pool as pharmacy — enables cross-file joins
- Flat structure: one service line per claim
- ICD-10 chronic condition codes + CPT office visit/procedure codes
- Plan types: 65% MEDICAID / 25% DSNP / 10% HMO
- Place of service: 70% office (11) / 20% outpatient (22) / 10% ER (23)
- Status mix: 82% PAID / 12% DENIED / 6% PENDING
