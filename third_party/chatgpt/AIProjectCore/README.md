# CHATGPT / AI Project Core snapshot

Origin: `pacote/AI Project Core` of https://github.com/marcelomaurin/CHATGPT,
commit `ec5cccf907c37577ef51a5965423f6ffe60576ea` (2026-10-20).

Units: `aiprojectduration`, `aiundohistory`, `aijsonutils`, `aitaskgraph`
(FCL only, no LCL),
used by the MultiProject. They are identical to the upstream files and use the
CHATGPT repository license (`../LICENSE`).

Build tooling (`tools/verify_suite.py`) uses the external CHATGPT directory when
it contains these units, with this snapshot as a fallback for older pinned
library revisions (including CI). Change the component upstream first, then
synchronize this copy.
