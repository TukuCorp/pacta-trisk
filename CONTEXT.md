# PACTA + TRISK Vietnam

A demo platform on which a fictional Vietnamese bank measures its loanbook's
climate alignment (PACTA) and transition-risk stress (TRISK), and turns the
results into client engagement deliverables. All data is synthetic.

## Language

### The run

**Engagement**:
One bank's configured end-to-end run of the platform, identified by a slug and
described entirely by its engagement config. The public demo (`mcb-demo`) is an
Engagement like any other.
_Avoid_: client, bank run, project

**Step**:
One named unit of the Engagement's ordered pipeline, executed as its own R
script and recorded in the Manifest.
_Avoid_: stage, phase (phases are plan-document sections, not pipeline units), task

**Manifest**:
The provenance record one Engagement run writes: which Steps ran, in what
order, with what status and inputs, and whether the run was partial.
_Avoid_: log, run record

**Loanbook**:
The bank's portfolio of loans, in whole VND, as submitted (raw) or after
intake normalization (normalized).
_Avoid_: portfolio (used only for PACTA's portfolio-level aggregates), book

### What the run produces

**Artifact**:
Any file or directory a Step writes that another part of the platform reads by
name: a CSV, a parquet, a JSON sidecar, a figure group, a report.
_Avoid_: output (too broad: every file is an output), result

**Artifact catalog**:
The single owner of every Artifact's identity, producing Step, location, and
Snapshot location. Nothing else may spell an Artifact's path.
_Avoid_: file list, path registry, manifest (that word is taken)

**Snapshot**:
The frozen copy of an Engagement's published Artifacts that the dashboard
reads. The public Snapshot is the one under version control.
_Avoid_: dashboard data, export, cache

**Deliverable**:
A client-facing rendered document (HTML, PDF) produced from Artifacts: the
bank report, engagement letters, the disclosure pack, the coverage report.
_Avoid_: report (too broad: internal build reports are not Deliverables), output

**Published report**:
A Deliverable an Engagement chooses to place in its Snapshot, and which the
report catalog classifies as client-facing.
_Avoid_: public report, exported report

**Facts sidecar**:
The machine-readable set of headline figures a Deliverable claims, written
beside it so the Gate can recompute and assert them.
_Avoid_: metadata, summary JSON

### Proof

**Gate**:
The acceptance check that a change left every committed Artifact and
Deliverable observably unchanged, and that committed Artifacts agree with each
other.
_Avoid_: CI check, regression test, verification script

**Golden numbers**:
The exact pinned values in the test suite that a refactor must reproduce.
_Avoid_: expected values, fixtures, baselines

**Invariant**:
One numbered cross-Artifact consistency rule the Gate enforces (INV-001 …).
_Avoid_: check, assertion, rule
