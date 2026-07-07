# CalOptima Member Enrollment Agent — Query Reference

## Objects Built

| Object | Location | Description |
|---|---|---|
| `MEMBER_ENROLLMENT` | `FACETS_PROD.AGENTS` | Flat view: 1 row per member (MEMBER + ELIGIBILITY deduped + PROVIDER) |
| `CALOPTIMA_MEMBER_SV` | `FACETS_PROD.AGENTS` | Semantic view over MEMBER_ENROLLMENT |
| `CALOPTIMA_AGENT` | `FACETS_PROD.AGENTS` | Cortex Agent with Cortex Analyst tool |

---

## Verified Queries (VQRs)

These are embedded in the semantic view and drive Cortex Analyst's highest-confidence answers.

### VQR 1 — Active Enrollment by Plan Type
> **"How many active members are enrolled in each plan type?"**

```sql
SELECT PLAN_TYPE_DESC, MEPE_PLAN_TYPE, COUNT(*) AS member_count
FROM FACETS_PROD.AGENTS.MEMBER_ENROLLMENT
WHERE MEMBER_STATUS = 'Active'
  AND MEPE_PLAN_TYPE IS NOT NULL
GROUP BY 1, 2
ORDER BY 3 DESC;
```
Expected: 5 rows — HMO, DSNP, MEDICAID, PPO, EPO (~23,600 members each)

---

### VQR 2 — PCP Assignment Rate
> **"What percentage of active members have a PCP assigned?"**

```sql
SELECT
  COUNT(*) AS total_active_members,
  COUNT(ACTIVE_PCP_PRPR_ID) AS members_with_pcp,
  ROUND(COUNT(ACTIVE_PCP_PRPR_ID) / COUNT(*) * 100, 2) AS pcp_assignment_pct
FROM FACETS_PROD.AGENTS.MEMBER_ENROLLMENT
WHERE MEMBER_STATUS = 'Active';
```
Expected: ~101,415 active members, ~69,038 with PCP (68.07%)

---

### VQR 3 — Active Members by Medicaid Aid Category
> **"How many active members are in each Medicaid aid category?"**

```sql
SELECT MECD_AID_CD, COUNT(*) AS member_count
FROM FACETS_PROD.AGENTS.MEMBER_ENROLLMENT
WHERE MEMBER_STATUS = 'Active'
  AND MECD_AID_CD IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC;
```
Expected: 8 aid categories (30, 58, 14E, 40, 44, 6N, 2G, 01A — ~9,000 each)

---

### VQR 4 — Active Members by PCP City
> **"Which cities have the most active members assigned to PCPs?"**

```sql
SELECT PCP_CITY, PCP_STATE, COUNT(*) AS member_count
FROM FACETS_PROD.AGENTS.MEMBER_ENROLLMENT
WHERE MEMBER_STATUS = 'Active'
  AND PCP_CITY IS NOT NULL
GROUP BY 1, 2
ORDER BY 3 DESC;
```
Expected: Orange County cities (Laguna Niguel, Costa Mesa, Orange, Huntington Beach, Anaheim...)

---

### VQR 5 — Enrollment by Relationship Type
> **"What is the breakdown of active members by relationship type?"**

```sql
SELECT RELATIONSHIP_DESC, COUNT(*) AS member_count
FROM FACETS_PROD.AGENTS.MEMBER_ENROLLMENT
WHERE MEMBER_STATUS = 'Active'
GROUP BY 1
ORDER BY 2 DESC;
```
Expected: Subscriber (~52,768), Spouse (~17,918), Child (~17,894), Other Dependent (~12,835)

---

## Additional Questions (Not VQRs — Answerable by the Agent)

These questions can be answered by the agent through Cortex Analyst text-to-SQL without a pre-built VQR.

### Q6 — Top PCPs by Member Count
> **"Which PCPs have the most active members assigned to them?"**

Hint for the agent: group by `ACTIVE_PCP_NAME` + `ACTIVE_PCP_NPI` where `MEMBER_STATUS = 'Active'`, order by COUNT DESC.

---

### Q7 — DSNP Enrollment Count
> **"How many active members are enrolled in the Dual Special Needs Plan (DSNP)?"**

Hint for the agent: filter `MEPE_PLAN_TYPE = 'DSNP'` and `MEMBER_STATUS = 'Active'`.

---

### Q8 — Gender Breakdown
> **"What is the breakdown of active members by gender?"**

Hint for the agent: group by `SEX_DESC` where `MEMBER_STATUS = 'Active'`.

---

### Q9 — Capitation Contract PCP Coverage
> **"How many active members have a capitation contract PCP?"**

Hint for the agent: filter `PCP_CONTRACT_TYPE = 'Capitation'` and `MEMBER_STATUS = 'Active'`.

---

### Q10 — Active Medicaid Benefit
> **"How many active members currently have an active Medicaid benefit?"**

Hint for the agent: filter `MEMBER_STATUS = 'Active'` and `MEDICAID_TERM_DT IS NULL OR MEDICAID_TERM_DT >= CURRENT_DATE()` and `MEDICAID_EFF_DT IS NOT NULL`.

---

## Data Model Notes

- **MEMBER_ENROLLMENT** is a flat view joining three Silver tables:
  - `FACETS_DEV.SILVER.MEMBER` — base (1 row per member)
  - `FACETS_DEV.SILVER.ELIGIBILITY` — deduped to latest active span per member via `ROW_NUMBER()`
  - `FACETS_DEV.SILVER.PROVIDER` — PCP details via `ACTIVE_PCP_PRPR_ID = PRPR_ID AND IS_CURRENT = TRUE`
- Row count: **105,843** (1 per member, no fanout)
- Members without eligibility spans have `MEPE_PLAN_TYPE = NULL`
- Members without a PCP have `ACTIVE_PCP_PRPR_ID = NULL` and all `PCP_*` columns = NULL
