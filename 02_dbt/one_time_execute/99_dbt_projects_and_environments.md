# dbt Projects and Environments — How They Fit Together

## The Mental Model

There is **one codebase** (the `payer_dw/` folder in this git repo) and **two deployed Snowflake project objects**. The project objects are just file stores — frozen snapshots of whatever was last uploaded via `snow dbt deploy`. They have no knowledge of git branches.

The **CI workflow** is what enforces which branch's code lands in which object:

| Git Event | Deploys To | Runs Against |
|---|---|---|
| `push → dev` | `PAYER_DW_DEV` | `FACETS_DEV` (`--target dev`) |
| `merge → main` (PR) | `PAYER_DW` | `FACETS_QA` + `FACETS_PROD` |

So saying "PAYER_DW_DEV contains dev branch code" really means: the last time someone pushed to dev, CI deployed that code into it. There is no live link to git.

---

## The Full Picture

```
payer_dw/  (one codebase, one git repo)
       │
       ├─ push → dev ──────────► snow dbt deploy PAYER_DW_DEV
       │                               │
       │                               └─► DBT_REFRESH_TASK_DEV
       │                                       EXECUTE DBT PROJECT PAYER_DW_DEV
       │                                       --target dev → FACETS_DEV
       │
       └─ merge → main ────────► snow dbt deploy PAYER_DW
                                       │
                                       ├─► DBT_REFRESH_TASK_QA
                                       │       EXECUTE DBT PROJECT PAYER_DW
                                       │       --target qa → FACETS_QA
                                       │
                                       └─► DBT_REFRESH_TASK_PROD
                                               EXECUTE DBT PROJECT PAYER_DW
                                               --target prod → FACETS_PROD
```

---

## The Three Environments

The `--target` flag controls which **database** dbt writes to. The code is the same; only the destination changes.

| Target | Database | Purpose |
|---|---|---|
| `dev` | `FACETS_DEV` | Active development, runs dev branch code |
| `qa` | `FACETS_QA` | Pre-merge validation gate |
| `prod` | `FACETS_PROD` | Stable, main branch code only |

These are defined in `payer_dw/profiles.yml`.

---

## The Scheduled Task Chain

Every time Openflow loads new CDC data, the following chain fires automatically:

```
FACETS_INCREMENTAL_TASK          ← Openflow CDC loads Bronze
    → DBT_REFRESH_TASK_DEV       ← PAYER_DW_DEV → FACETS_DEV
    → DBT_REFRESH_TASK_QA        ← PAYER_DW     → FACETS_QA
    → DBT_REFRESH_TASK_PROD      ← PAYER_DW     → FACETS_PROD
    → PROVIDER_SCD2_STREAM_TASK  ← Stream/Task SCD2 for providers (when stream has data)
```

All tasks live in `FACETS_BRONZE.UTILS`. See `silver_refresh_task.sql` for the DDL to recreate them.

---

## Why Two Objects Instead of One

With a single project object, a `push → dev` would immediately update the code that QA and PROD tasks run — a broken dev commit would contaminate all three environments. With two objects:

- A broken dev push only affects `FACETS_DEV`
- QA and PROD keep running the last merged-to-main stable code until you explicitly open a PR and merge

---

## Redeploying

Both project objects are managed automatically by CI. Manual redeploy (e.g., after a config change):

```bash
# Redeploy dev object (from dev branch)
cd payer_dw && snow dbt deploy payer_dw_dev \
  --database ANALYTICS_ADMIN --schema PROJECTS

# Redeploy stable object (from main branch)
cd payer_dw && snow dbt deploy payer_dw \
  --database ANALYTICS_ADMIN --schema PROJECTS
```

Or use the **workflow_dispatch** button in GitHub Actions (deploys `PAYER_DW_DEV` + runs dev build).
