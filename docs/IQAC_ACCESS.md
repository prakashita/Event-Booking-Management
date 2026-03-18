# IQAC Data Collection – Access and Roles

This document describes how the **IQAC Data Collection** feature works and which roles have access.

## Purpose

The feature is used to store and manage NAAC accreditation evidence by the seven criteria (and sub-criteria like 1.1, 1.1.1, etc.). Only designated roles can see the section and use upload/list/download/delete.

## Role–Access Matrix

| Role            | See IQAC menu | View criteria tree | List files | Upload | Download | Delete |
|-----------------|---------------|--------------------|------------|--------|----------|--------|
| **IQAC**        | Yes           | Yes                | Yes        | Yes    | Yes      | Yes    |
| **Admin**       | Yes           | Yes                | Yes        | Yes    | Yes      | Yes    |
| **Registrar**   | Yes           | Yes                | Yes        | Yes    | Yes      | Yes    |
| Faculty         | No            | No                 | No         | No     | No       | No     |
| Facility Manager| No            | No                 | No         | No     | No       | No     |
| Marketing       | No            | No                 | No         | No     | No       | No     |
| IT              | No            | No                 | No         | No     | No       | No     |

- **IQAC**: Primary users; they collect and manage evidence for NAAC.
- **Admin / Registrar**: Same full access for oversight and support; they are not restricted to “view only”.

All other roles cannot open the IQAC page or call IQAC APIs (they get 403 if they try).

## Where It’s Enforced

- **Backend**: `Server/routers/deps.py` – `IQAC_ALLOWED_ROLES` and `require_iqac`. All IQAC routes use `Depends(require_iqac)`.
- **Frontend**: `Client/src/constants/index.js` – `ROLES_WITH_IQAC_ACCESS`. Used to show/hide the “IQAC Data Collection” menu item and to redirect away from `/iqac-data` when the user’s role is not in this list.

When changing allowed roles, update both:

1. `Server/routers/deps.py` → `IQAC_ALLOWED_ROLES`
2. `Client/src/constants/index.js` → `ROLES_WITH_IQAC_ACCESS`
