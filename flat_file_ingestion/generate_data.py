"""
generate_data.py
Generates two synthetic flat files for the CalOptima demo:
  data/pharmacy_claims.csv  — 5,000 rows, 20 columns
  data/medical_claims.xml   — 6,000 claims, 20 fields each

Uses only Python stdlib. Run: python3 generate_data.py
"""

import csv
import random
import xml.etree.ElementTree as ET
from datetime import date, timedelta
from pathlib import Path

random.seed(42)

# ── Shared reference data ─────────────────────────────────────────────────────
GENDERS        = ["M", "F"]
CLAIM_STATUS   = (["PAID"] * 85) + (["DENIED"] * 10) + (["PENDING"] * 5)
PLAN_TYPES     = (["MEDICAID"] * 65) + (["DSNP"] * 25) + (["HMO"] * 10)

# ~400 distinct standalone member IDs shared across both files
MEMBER_IDS = [f"MBR-{i:07d}" for i in random.sample(range(1000000), 400)]

def rand_date(start_days_ago=365, end_days_ago=0):
    """Return a random date between start_days_ago and end_days_ago before today."""
    base = date(2026, 6, 30)
    delta = random.randint(end_days_ago, start_days_ago)
    return base - timedelta(days=delta)

def rand_dob(min_age=5, max_age=80):
    base = date(2026, 6, 30)
    age_days = random.randint(min_age * 365, max_age * 365)
    return base - timedelta(days=age_days)

def rand_npi():
    return str(random.randint(1000000000, 1999999999))

def rand_money(lo, hi):
    return round(random.uniform(lo, hi), 2)

# ── Pharmacy reference data ───────────────────────────────────────────────────
DRUGS = [
    # (NDC, name, category, tier)
    ("00093-7236-56", "Metformin HCl 500mg",            "Diabetes",      1),
    ("00093-0832-01", "Glipizide 5mg",                   "Diabetes",      1),
    ("68645-0458-54", "Insulin Glargine 100u/mL",        "Diabetes",      3),
    ("00781-1620-13", "Lisinopril 10mg",                 "Hypertension",  1),
    ("00228-2895-11", "Amlodipine 5mg",                  "Hypertension",  1),
    ("00093-1083-01", "Losartan 50mg",                   "Hypertension",  1),
    ("00378-0221-01", "Metoprolol Succinate 25mg",       "Hypertension",  1),
    ("00228-2061-11", "Hydrochlorothiazide 25mg",        "Hypertension",  1),
    ("00093-0172-01", "Sertraline 50mg",                 "Mental Health", 1),
    ("00781-5077-31", "Fluoxetine 20mg",                 "Mental Health", 1),
    ("59762-0502-01", "Quetiapine 25mg",                 "Mental Health", 3),
    ("59762-0174-01", "Albuterol HFA Inhaler",           "Asthma",        1),
    ("00378-2010-01", "Atorvastatin 20mg",               "Cholesterol",   1),
    ("00093-7044-01", "Levothyroxine 50mcg",             "Thyroid",       1),
    ("00093-5162-56", "Gabapentin 300mg",                "Pain",          2),
    ("00378-4320-01", "Omeprazole 20mg",                 "GI",            2),
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
    "OB/GYN", "Psychiatry", "Endocrinology",
    "Cardiology", "Pulmonology",
]

# ── Generate pharmacy_claims.csv ──────────────────────────────────────────────
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
    member_id  = random.choice(MEMBER_IDS)
    dob        = rand_dob()
    gender     = random.choice(GENDERS)
    fill_date  = rand_date()
    drug       = random.choice(DRUGS)
    days       = random.choices([30, 90], weights=[70, 30])[0]
    qty        = days * 2 if "mg" in drug[1] else days
    pharm      = random.choice(PHARMACIES)
    prescriber = rand_npi()
    specialty  = random.choice(SPECIALTIES)
    billed     = rand_money(8, 450)
    copay      = random.choices([0.0, 1.0, 3.0, 10.0], weights=[40, 35, 15, 10])[0]
    plan_paid  = max(0, round(billed * random.uniform(0.7, 0.95) - copay, 2))
    status     = random.choice(CLAIM_STATUS)
    if status != "PAID":
        plan_paid = 0.0
        copay     = 0.0

    return {
        "CLAIM_ID":            f"PH-2026-{seq:08d}",
        "MEMBER_ID":           member_id,
        "DATE_OF_BIRTH":       dob.isoformat(),
        "GENDER":              gender,
        "FILL_DATE":           fill_date.isoformat(),
        "DRUG_NDC":            drug[0],
        "DRUG_NAME":           drug[1],
        "DRUG_CATEGORY":       drug[2],
        "DAYS_SUPPLY":         days,
        "QUANTITY_DISPENSED":  qty,
        "GENERIC_IND":         "N" if drug[3] >= 3 else "Y",
        "PHARMACY_NPI":        pharm[1],
        "PHARMACY_NAME":       pharm[0],
        "PRESCRIBER_NPI":      prescriber,
        "PRESCRIBER_SPECIALTY": specialty,
        "BILLED_AMOUNT":       f"{billed:.2f}",
        "PLAN_PAID_AMOUNT":    f"{plan_paid:.2f}",
        "MEMBER_COPAY":        f"{copay:.2f}",
        "FORMULARY_TIER":      drug[3],
        "CLAIM_STATUS":        status,
    }

out_csv = Path(__file__).parent / "data" / "pharmacy_claims.csv"
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=PHARMACY_FIELDS)
    w.writeheader()
    for i in range(1, 5001):
        w.writerow(make_pharmacy_row(i))
print(f"Wrote {out_csv}  (5,000 rows)")

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
    "Z79.4",   # Long-term use of insulin
    "Z87.39",  # Personal history of other endocrine, nutritional and metabolic diseases
    "Z82.49",  # Family history of ischemic heart disease
    "Z96.641", # Presence of right artificial hip joint
    "Z79.01",  # Long-term (current) use of anticoagulants
    None, None, None,  # ~37% have no secondary dx
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
    ("99213", "Office Visit Established Patient Low-Moderate Complexity"),  # weighted double
    ("99213", "Office Visit Established Patient Low-Moderate Complexity"),
    ("99214", "Office Visit Established Patient Moderate-High Complexity"),
]

PLACE_OF_SERVICE = random.choices(
    ["11", "22", "23"],
    weights=[70, 20, 10],
    k=6000,
)

PROVIDERS = [
    ("Garcia, Maria MD",        rand_npi(), "Internal Medicine"),
    ("Nguyen, Thomas DO",       rand_npi(), "Family Medicine"),
    ("Patel, Priya MD",         rand_npi(), "Pediatrics"),
    ("Williams, Sandra MD",     rand_npi(), "OB/GYN"),
    ("Kim, David MD",           rand_npi(), "Cardiology"),
    ("Johnson, Robert MD",      rand_npi(), "Psychiatry"),
    ("Martinez, Elena MD",      rand_npi(), "Endocrinology"),
    ("Chen, Lisa MD",           rand_npi(), "Internal Medicine"),
    ("Thompson, James DO",      rand_npi(), "Family Medicine"),
    ("Robinson, Patricia NP",   rand_npi(), "Family Medicine"),
]

# ── Generate medical_claims.xml ───────────────────────────────────────────────
root = ET.Element("MedicalClaims")

batch = ET.SubElement(root, "BatchInfo")
ET.SubElement(batch, "BatchID").text          = "BATCH-20260630"
ET.SubElement(batch, "SubmitterID").text      = "CALOPTIMA-CLMS"
ET.SubElement(batch, "SubmissionDate").text   = "2026-06-30"
ET.SubElement(batch, "TotalClaims").text      = "6000"

for i in range(1, 6001):
    member_id = random.choice(MEMBER_IDS)
    dob       = rand_dob()
    gender    = random.choice(GENDERS)
    plan_type = random.choice(PLAN_TYPES)
    svc_date  = rand_date()
    provider  = random.choice(PROVIDERS)
    pos       = PLACE_OF_SERVICE[i - 1]
    dx1       = random.choice(DIAGNOSES)
    dx2_code  = random.choice(SECONDARY_DX)
    proc      = random.choice(PROCEDURES)
    billed    = rand_money(90, 850)
    allowed   = round(billed * random.uniform(0.55, 0.85), 2)
    copay     = random.choices([0.0, 5.0, 10.0, 20.0], weights=[50, 25, 15, 10])[0]
    plan_paid = max(0, round(allowed - copay, 2))
    status    = random.choice(CLAIM_STATUS)
    if status != "PAID":
        plan_paid = 0.0
        copay     = 0.0
        allowed   = 0.0

    c = ET.SubElement(root, "Claim")
    ET.SubElement(c, "ClaimID").text               = f"CLM-2026-{i:08d}"
    ET.SubElement(c, "MemberID").text              = member_id
    ET.SubElement(c, "DateOfBirth").text           = dob.isoformat()
    ET.SubElement(c, "Gender").text                = gender
    ET.SubElement(c, "PlanType").text              = plan_type
    ET.SubElement(c, "ServiceDate").text           = svc_date.isoformat()
    ET.SubElement(c, "ProviderNPI").text           = provider[1]
    ET.SubElement(c, "ProviderName").text          = provider[0]
    ET.SubElement(c, "ProviderSpecialty").text     = provider[2]
    ET.SubElement(c, "PlaceOfService").text        = pos
    ET.SubElement(c, "DiagnosisCode1").text        = dx1[0]
    ET.SubElement(c, "DiagnosisCode2").text        = dx2_code if dx2_code else ""
    ET.SubElement(c, "ProcedureCode").text         = proc[0]
    ET.SubElement(c, "ProcedureDescription").text  = proc[1]
    ET.SubElement(c, "Units").text                 = "1"
    ET.SubElement(c, "BilledAmount").text          = f"{billed:.2f}"
    ET.SubElement(c, "AllowedAmount").text         = f"{allowed:.2f}"
    ET.SubElement(c, "PlanPaidAmount").text        = f"{plan_paid:.2f}"
    ET.SubElement(c, "MemberResponsibility").text  = f"{copay:.2f}"
    ET.SubElement(c, "ClaimStatus").text           = status

def indent_xml(elem, level=0):
    """Add pretty-print indentation to the XML tree."""
    pad = "\n" + "  " * level
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = pad + "  "
        if not elem.tail or not elem.tail.strip():
            elem.tail = pad
        for child in elem:
            indent_xml(child, level + 1)
        if not child.tail or not child.tail.strip():
            child.tail = pad
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = pad

indent_xml(root)
tree = ET.ElementTree(root)

out_xml = Path(__file__).parent / "data" / "medical_claims.xml"
with open(out_xml, "wb") as f:
    tree.write(f, encoding="utf-8", xml_declaration=True)
print(f"Wrote {out_xml}  (6,000 claims)")
