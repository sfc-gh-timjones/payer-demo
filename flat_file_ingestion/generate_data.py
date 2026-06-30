"""
generate_data.py
Generates synthetic flat files for the CalOptima demo:
  data/pharmacy_claims.csv           — 25,000 rows, 20 columns
  data/medical_claims.xml            — 20,000 claims, 20 fields each
  data/pharmacy_claims_bad_records.csv — 5,000 rows, 5 intentionally bad records

Uses only Python stdlib. Run: python3 generate_data.py
XML is written as a stream (not built in-memory) so it stays fast at large counts.
"""

import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(42)

BASE_DATE = date(2026, 6, 30)

# ── Shared reference data ─────────────────────────────────────────────────────
GENDERS      = ["M", "F"]
CLAIM_STATUS = (["PAID"] * 85) + (["DENIED"] * 10) + (["PENDING"] * 5)
PLAN_TYPES   = (["MEDICAID"] * 65) + (["DSNP"] * 25) + (["HMO"] * 10)

# ~400 distinct standalone member IDs shared across all three files
MEMBER_IDS = [f"MBR-{i:07d}" for i in random.sample(range(1000000), 400)]

def rand_date():
    return (BASE_DATE - timedelta(days=random.randint(0, 365))).isoformat()

def rand_dob():
    return (BASE_DATE - timedelta(days=random.randint(5 * 365, 80 * 365))).isoformat()

def rand_npi():
    return str(random.randint(1000000000, 1999999999))

def rand_money(lo, hi):
    return round(random.uniform(lo, hi), 2)

# ── Pharmacy reference data ───────────────────────────────────────────────────
DRUGS = [
    ("00093-7236-56", "Metformin HCl 500mg",         "Diabetes",     1),
    ("00093-0832-01", "Glipizide 5mg",                "Diabetes",     1),
    ("68645-0458-54", "Insulin Glargine 100u/mL",     "Diabetes",     3),
    ("00781-1620-13", "Lisinopril 10mg",              "Hypertension", 1),
    ("00228-2895-11", "Amlodipine 5mg",               "Hypertension", 1),
    ("00093-1083-01", "Losartan 50mg",                "Hypertension", 1),
    ("00378-0221-01", "Metoprolol Succinate 25mg",    "Hypertension", 1),
    ("00228-2061-11", "Hydrochlorothiazide 25mg",     "Hypertension", 1),
    ("00093-0172-01", "Sertraline 50mg",              "Mental Health",1),
    ("00781-5077-31", "Fluoxetine 20mg",              "Mental Health",1),
    ("59762-0502-01", "Quetiapine 25mg",              "Mental Health",3),
    ("59762-0174-01", "Albuterol HFA Inhaler",        "Asthma",       1),
    ("00378-2010-01", "Atorvastatin 20mg",            "Cholesterol",  1),
    ("00093-7044-01", "Levothyroxine 50mcg",          "Thyroid",      1),
    ("00093-5162-56", "Gabapentin 300mg",             "Pain",         2),
    ("00378-4320-01", "Omeprazole 20mg",              "GI",           2),
]

PHARMACIES = [
    ("CVS Pharmacy #2841",      rand_npi()),
    ("Walgreens #4512",         rand_npi()),
    ("Rite Aid #0831",          rand_npi()),
    ("Walmart Pharmacy #3027",  rand_npi()),
    ("Kaiser Permanente Pharm", rand_npi()),
    ("Costco Pharmacy #0441",   rand_npi()),
    ("Target Pharmacy #1290",   rand_npi()),
    ("CalOptima Mail Order",    rand_npi()),
]

SPECIALTIES = [
    "Internal Medicine", "Family Medicine", "Pediatrics",
    "OB/GYN", "Psychiatry", "Endocrinology", "Cardiology", "Pulmonology",
]

PHARMACY_FIELDS = [
    "CLAIM_ID", "MEMBER_ID", "DATE_OF_BIRTH", "GENDER",
    "FILL_DATE", "DRUG_NDC", "DRUG_NAME", "DRUG_CATEGORY",
    "DAYS_SUPPLY", "QUANTITY_DISPENSED", "GENERIC_IND",
    "PHARMACY_NPI", "PHARMACY_NAME",
    "PRESCRIBER_NPI", "PRESCRIBER_SPECIALTY",
    "BILLED_AMOUNT", "PLAN_PAID_AMOUNT", "MEMBER_COPAY",
    "FORMULARY_TIER", "CLAIM_STATUS",
]

def make_pharmacy_row(seq):
    drug     = random.choice(DRUGS)
    pharm    = random.choice(PHARMACIES)
    days     = random.choices([30, 90], weights=[70, 30])[0]
    billed   = rand_money(8, 450)
    copay    = random.choices([0.0, 1.0, 3.0, 10.0], weights=[40, 35, 15, 10])[0]
    plan_pd  = max(0, round(billed * random.uniform(0.7, 0.95) - copay, 2))
    status   = random.choice(CLAIM_STATUS)
    if status != "PAID":
        plan_pd = copay = 0.0
    return {
        "CLAIM_ID":             f"PH-2026-{seq:08d}",
        "MEMBER_ID":            random.choice(MEMBER_IDS),
        "DATE_OF_BIRTH":        rand_dob(),
        "GENDER":               random.choice(GENDERS),
        "FILL_DATE":            rand_date(),
        "DRUG_NDC":             drug[0],
        "DRUG_NAME":            drug[1],
        "DRUG_CATEGORY":        drug[2],
        "DAYS_SUPPLY":          days,
        "QUANTITY_DISPENSED":   days * 2 if "mg" in drug[1] else days,
        "GENERIC_IND":          "N" if drug[3] >= 3 else "Y",
        "PHARMACY_NPI":         pharm[1],
        "PHARMACY_NAME":        pharm[0],
        "PRESCRIBER_NPI":       rand_npi(),
        "PRESCRIBER_SPECIALTY": random.choice(SPECIALTIES),
        "BILLED_AMOUNT":        f"{billed:.2f}",
        "PLAN_PAID_AMOUNT":     f"{plan_pd:.2f}",
        "MEMBER_COPAY":         f"{copay:.2f}",
        "FORMULARY_TIER":       drug[3],
        "CLAIM_STATUS":         status,
    }

# ── Generate pharmacy_claims.csv (25,000 rows) ────────────────────────────────
DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

out_csv = DATA_DIR / "pharmacy_claims.csv"
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=PHARMACY_FIELDS)
    w.writeheader()
    for i in range(1, 25001):
        w.writerow(make_pharmacy_row(i))
print(f"Wrote {out_csv}  (25,000 rows)")

# ── Medical claims reference data ─────────────────────────────────────────────
DIAGNOSES = [
    ("E11.9",   "Type 2 diabetes mellitus without complications"),
    ("I10",     "Essential (primary) hypertension"),
    ("F32.9",   "Major depressive disorder, single episode, unspecified"),
    ("J45.909", "Unspecified asthma, uncomplicated"),
    ("F41.9",   "Anxiety disorder, unspecified"),
    ("M54.5",   "Low back pain"),
    ("Z00.00",  "Encounter for general adult medical examination"),
    ("E78.5",   "Hyperlipidemia, unspecified"),
    ("J06.9",   "Acute upper respiratory infection, unspecified"),
    ("K21.0",   "Gastro-esophageal reflux disease with esophagitis"),
    ("F32.1",   "Major depressive disorder, single episode, moderate"),
    ("E11.65",  "Type 2 diabetes mellitus with hyperglycemia"),
]

SECONDARY_DX = [
    "Z79.4", "Z87.39", "Z82.49", "Z96.641", "Z79.01",
    None, None, None,   # ~37% no secondary dx
]

PROCEDURES = [
    ("99213", "Office Visit Established Patient Low-Moderate Complexity"),
    ("99214", "Office Visit Established Patient Moderate-High Complexity"),
    ("99203", "Office Visit New Patient Low Complexity"),
    ("99204", "Office Visit New Patient Moderate Complexity"),
    ("99232", "Subsequent Hospital Care"),
    ("93000", "Electrocardiogram with Interpretation"),
    ("36415", "Venipuncture for Blood Collection"),
    ("99381", "Preventive Medicine New Patient Infant"),
    ("99386", "Preventive Medicine New Patient 40-64 Years"),
    ("99213", "Office Visit Established Patient Low-Moderate Complexity"),
    ("99213", "Office Visit Established Patient Low-Moderate Complexity"),
    ("99214", "Office Visit Established Patient Moderate-High Complexity"),
]

POS_CHOICES = random.choices(["11", "22", "23"], weights=[70, 20, 10], k=20000)

PROVIDERS = [
    ("Garcia, Maria MD",      rand_npi(), "Internal Medicine"),
    ("Nguyen, Thomas DO",     rand_npi(), "Family Medicine"),
    ("Patel, Priya MD",       rand_npi(), "Pediatrics"),
    ("Williams, Sandra MD",   rand_npi(), "OB/GYN"),
    ("Kim, David MD",         rand_npi(), "Cardiology"),
    ("Johnson, Robert MD",    rand_npi(), "Psychiatry"),
    ("Martinez, Elena MD",    rand_npi(), "Endocrinology"),
    ("Chen, Lisa MD",         rand_npi(), "Internal Medicine"),
    ("Thompson, James DO",    rand_npi(), "Family Medicine"),
    ("Robinson, Patricia NP", rand_npi(), "Family Medicine"),
]

# ── Generate medical_claims.xml (20,000 claims) — streaming write ─────────────
out_xml = DATA_DIR / "medical_claims.xml"
with open(out_xml, "w", encoding="utf-8") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
    f.write('<MedicalClaims>\n')
    f.write('  <BatchInfo>\n')
    f.write('    <BatchID>BATCH-20260630</BatchID>\n')
    f.write('    <SubmitterID>CALOPTIMA-CLMS</SubmitterID>\n')
    f.write('    <SubmissionDate>2026-06-30</SubmissionDate>\n')
    f.write('    <TotalClaims>20000</TotalClaims>\n')
    f.write('  </BatchInfo>\n')

    for i in range(1, 20001):
        prov     = random.choice(PROVIDERS)
        dx1      = random.choice(DIAGNOSES)
        dx2      = random.choice(SECONDARY_DX)
        proc     = random.choice(PROCEDURES)
        billed   = rand_money(90, 850)
        allowed  = round(billed * random.uniform(0.55, 0.85), 2)
        copay    = random.choices([0.0, 5.0, 10.0, 20.0], weights=[50, 25, 15, 10])[0]
        plan_pd  = max(0, round(allowed - copay, 2))
        status   = random.choice(CLAIM_STATUS)
        if status != "PAID":
            plan_pd = copay = allowed = 0.0

        f.write('  <Claim>\n')
        f.write(f'    <ClaimID>CLM-2026-{i:08d}</ClaimID>\n')
        f.write(f'    <MemberID>{random.choice(MEMBER_IDS)}</MemberID>\n')
        f.write(f'    <DateOfBirth>{rand_dob()}</DateOfBirth>\n')
        f.write(f'    <Gender>{random.choice(GENDERS)}</Gender>\n')
        f.write(f'    <PlanType>{random.choice(PLAN_TYPES)}</PlanType>\n')
        f.write(f'    <ServiceDate>{rand_date()}</ServiceDate>\n')
        f.write(f'    <ProviderNPI>{prov[1]}</ProviderNPI>\n')
        f.write(f'    <ProviderName>{prov[0]}</ProviderName>\n')
        f.write(f'    <ProviderSpecialty>{prov[2]}</ProviderSpecialty>\n')
        f.write(f'    <PlaceOfService>{POS_CHOICES[i - 1]}</PlaceOfService>\n')
        f.write(f'    <DiagnosisCode1>{dx1[0]}</DiagnosisCode1>\n')
        f.write(f'    <DiagnosisCode2>{dx2 or ""}</DiagnosisCode2>\n')
        f.write(f'    <ProcedureCode>{proc[0]}</ProcedureCode>\n')
        f.write(f'    <ProcedureDescription>{proc[1]}</ProcedureDescription>\n')
        f.write(f'    <Units>1</Units>\n')
        f.write(f'    <BilledAmount>{billed:.2f}</BilledAmount>\n')
        f.write(f'    <AllowedAmount>{allowed:.2f}</AllowedAmount>\n')
        f.write(f'    <PlanPaidAmount>{plan_pd:.2f}</PlanPaidAmount>\n')
        f.write(f'    <MemberResponsibility>{copay:.2f}</MemberResponsibility>\n')
        f.write(f'    <ClaimStatus>{status}</ClaimStatus>\n')
        f.write('  </Claim>\n')

    f.write('</MedicalClaims>\n')
print(f"Wrote {out_xml}  (20,000 claims)")

# ── Generate pharmacy_claims_bad_records.csv (5,000 rows, 5 bad) ─────────────
# These records cause COPY INTO to fail — type cast errors Snowflake cannot
# coerce when loading into a typed table:
#   312  — DAYS_SUPPLY='THIRTY-DAYS'  → cannot cast VARCHAR to NUMBER
#   891  — BILLED_AMOUNT='N/A'        → cannot cast VARCHAR to FLOAT/NUMBER
#   1547 — QUANTITY_DISPENSED='MANY'  → cannot cast VARCHAR to NUMBER
#   2983 — FORMULARY_TIER='GOLD'      → cannot cast VARCHAR to NUMBER
#   4201 — extra field (21 columns)   → column count mismatch, row rejected
BAD_OVERRIDES = {
    312:  {"DAYS_SUPPLY":         "THIRTY-DAYS"},
    891:  {"BILLED_AMOUNT":       "N/A"},
    1547: {"QUANTITY_DISPENSED":  "MANY"},
    2983: {"FORMULARY_TIER":      "GOLD"},
    # row 4201 gets an extra field injected via raw write below
}
EXTRA_FIELD_ROW = 4201

out_bad = DATA_DIR / "pharmacy_claims_bad_records.csv"
with open(out_bad, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=PHARMACY_FIELDS)
    w.writeheader()
    for i in range(1, 5001):
        row = make_pharmacy_row(i + 25000)   # offset so IDs don't collide
        if i in BAD_OVERRIDES:
            row.update(BAD_OVERRIDES[i])
        if i == EXTRA_FIELD_ROW:
            # Write raw line with an extra trailing field — column count mismatch
            values = [str(row[col]) for col in PHARMACY_FIELDS]
            values.append("EXTRA_FIELD")   # 21st column
            f.write(",".join(values) + "\n")
        else:
            w.writerow(row)

print(f"Wrote {out_bad}  (5,000 rows, 5 load-breaking records)")
print()
print("Bad record summary (each causes COPY INTO to reject the row):")
labels = {
    312:  "NUMERIC_CAST_FAIL  — DAYS_SUPPLY='THIRTY-DAYS' (VARCHAR in NUMBER column)",
    891:  "NUMERIC_CAST_FAIL  — BILLED_AMOUNT='N/A' (VARCHAR in FLOAT column)",
    1547: "NUMERIC_CAST_FAIL  — QUANTITY_DISPENSED='MANY' (VARCHAR in NUMBER column)",
    2983: "NUMERIC_CAST_FAIL  — FORMULARY_TIER='GOLD' (VARCHAR in NUMBER column)",
    4201: "COLUMN_COUNT_MISMATCH — 21 fields instead of 20 (extra trailing field)",
}
for row_num, desc in labels.items():
    print(f"  Row {row_num:5d}: {desc}")
