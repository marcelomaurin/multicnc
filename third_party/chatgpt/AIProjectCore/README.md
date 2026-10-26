# CHATGPT / AI Project Core snapshot

Origin: `pacote/AI Project Core` of https://github.com/marcelomaurin/CHATGPT,
commit `78f3f2b1cb0bb7201d2b73ce3bcafca70f632166` (2026-10-21).

Units: `aiprojectduration`, `aiundohistory`, `aijsonutils`, `aitaskgraph`,
`aiworkcalendar`, `aicpmscheduler`, `airesourceload` (FCL only, no LCL),
used by the MultiProject. They are identical to the upstream files and use the
CHATGPT repository license (`../LICENSE`).

New local components added on 2026-10-26 (MultiProject phase 7.5/7.7), not yet
published upstream: `aitasktype` (task type and effort-driven scheduling,
Work = Duration x Units) and `aicostmodel` (rates, per-use, material, fixed
cost accrual, money text). Copy both to `pacote/AI Project Core` of the CHATGPT
repository; until then `tools/verify_suite.py` uses this snapshot, because the
external directory does not contain every unit listed here.

Build tooling (`tools/verify_suite.py`) uses the external CHATGPT directory when
it contains these units, with this snapshot as a fallback for older pinned
library revisions (including CI). Change the component upstream first, then
synchronize this copy.
