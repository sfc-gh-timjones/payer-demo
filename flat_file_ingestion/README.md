# flat_file_ingestion

Synthetic flat file demo data for the CalOptima RFP 26-038 demo.

## Files

| File | Records | Description |
|---|---|---|
| `data/pharmacy_claims.csv` | 5,000 rows | PBM pharmacy dispensing extract (OptumRx/CVS style) |
| `data/medical_claims.xml` | 6,000 claims | Clearinghouse professional claims adjudication file (837P style) |

## Regenerating

```bash
python3 generate_data.py
```

Requires Python 3.6+ (stdlib only — no pip installs needed). Seed is fixed (`random.seed(42)`) so output is reproducible.

## Data Model

### pharmacy_claims.csv (20 columns)
- Member IDs in `MBR-XXXXXXX` format (standalone — not Facets IDs)
- ~400 distinct members each with multiple fills
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
