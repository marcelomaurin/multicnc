# CHATGPT / AI Project Core snapshot

Origin: `pacote/AI Project Core` of https://github.com/marcelomaurin/CHATGPT,
commit `35203a3783436d85e0805fa11e72eedeb1d13fd4` (2026-10-20).

Units: `aiprojectduration`, `aiundohistory`, `aijsonutils` (FCL only, no LCL),
used by the MultiProject. They are identical to the upstream files and use the
CHATGPT repository license (`../LICENSE`).

Build tooling (`tools/verify_suite.py`) uses the external CHATGPT directory when
it contains these units, with this snapshot as a fallback for older pinned
library revisions (including CI). Change the component upstream first, then
synchronize this copy.
