# Versioning

```text
Current version: 0.4
November 2026  ·  Sean Slavin  ·  fieldworks.build
```

## Version Numbering

FieldWorks uses semantic versioning. Version numbers follow the pattern MAJOR.MINOR.PATCH.

**Major version** — breaking changes to the conformant tool surface, schema changes that require adapter updates, or agent behavior changes that break existing deployments. A deployment built against v1.x must be reviewed before upgrading to v2.0.

**Minor version** — additive changes. New optional fields, new sections, new tools that do not break existing conformant adapters. A deployment built against v0.1 will continue to work on v0.2 without modification.

**Patch version** — corrections and clarifications. No behavioral changes. Patch releases do not require any deployment review.

> v0.x versions are pre-release. The framework architecture is established but the conformant tool surface and schema details are subject to change between minor versions. Implementations should expect the surface to stabilize at v1.0. When the spec reaches v1.0, the major/minor/patch stability guarantees apply in full.

## Version History

| Version | Date | Summary |
|:---|:---|:---|
| `0.1` | `2026-06` | Initial release. Introduction, Parts I–IV, Topology Builder, Audit Trail, Versioning sections. |
| `0.2` | `2026-07` | Added the Propose/Approve/Execute mechanism to Part III (SUPERVISED mode only). Documented as a new framework contract, not a description of existing behavior. |
| `0.3` | `2026-11` | Brought the spec up to date with what shipped since v0.2: tool annotations and result shapes in Part I, the four-mode trust ladder and reactive mode in Part III, the knowledge store and memory tool contract in Part IV, operator identity, and a new Part V for multi-plant deployments. |
| `0.4` | `2026-11` | Defined the FINDINGS and SUMMARY verdict blocks in Part III as the agent layer's output contract. |

New versions will be listed here as the spec evolves. Each entry links to the changelog below for detail on what changed.

## Changelog

**v0.4 — November 2026**

Part III — new section: Verdict Blocks. Every Specialist and the Historian end with a FINDINGS block, and Cascade opens an overview with a SUMMARY block. The section defines the three statuses and their severity order, both templates and their required fields, the parsing rules a conformant parser applies, and the missing-verdict rule: a Specialist without a verdict is unknown, never Normal. The incident record's `status` and `confidence` now come from the verdict.

Part III and Part V — implementation status notes updated: fieldworks-core 1.4.0 provides the enterprise layer's plant-agnostic logic, and 1.5.0 provides the verdict templates and parser.

This is an additive, non-breaking change. The blocks were already in use; this release writes them down.

**v0.3 — November 2026**

The first release built from the Markdown source. Since v0.2, fieldworks-core went from 1.0.x to 1.3.0 and the spec fell behind it. This release brings the text up to date and specifies the contracts the next round of framework work will implement.

Source — the spec moved from a Pages document to Markdown in the fieldworks-spec repository, and CI builds the PDF. No content change.

Part I — new: Tool annotations. Read tools declare `readOnlyHint: true`, `connect` and `disconnect` declare `destructiveHint: false`, and `write_tag` claims neither.

Part I — new: Result Shapes. `discover_tags`, `browse`/`scan` and `read_tag_history` wrap their lists in an object under `tags`, `entries` and `values`, as MCP requires.

Part I — Error Handling. `TIMEOUT` is conformant for an unknown tag when the protocol cannot determine non-existence, as with MQTT. `TAG_NOT_FOUND` remains required whenever it can.

Part I — new: Operator identity. `operator_id` stays required and must name what the deployment actually authenticated: a user, a documented shared-credential value, or `trust-mode:<mode>`. Never a placeholder person.

Part II — the conformance suite list and `fieldworks test-adapter` invocation match the current CLI. `facility.site_id` is tied to Part V.

Part III — Trust Mode rewritten to the four modes fieldworks-core implements: advisory, supervised, collaborative and autonomous, with the dispatch table, what the host supplies and the `trust_mode_changed` record. The three-rung ladder and its "assisted" mode are removed. The Propose/Approve/Execute scope boundary no longer calls dispatch unimplemented.

Part III — audit record schema gains `auth_method` next to `operator_id`.

Part III — new: Reactive Mode. Detect, Deadband filter, route by severity, with the framework/host split.

Part IV — the knowledge store (`KnowledgeClient`) joins as a fifth store. The memory server is specified as framework clients plus a tool contract, using the tool names the reference server exposes. The lifecycle describes what runs: agents read memory, the host writes it. Cascade shared memory and OperatorDecision writes move to planned.

Part V — new: The Enterprise Layer. Plant boundaries, the `enterprise.yaml` schema and validation, `site_id` end to end, federated read and the cross-plant orchestrator. The orchestrator cannot propose writes at any plant.

> Several v0.3 changes tighten what counts as conformant: required annotations, wrapped list results, the removal of "assisted", and the renamed memory tools. Under the v0.x policy above, these ship in a minor release. Every published adapter already meets the Part I changes.

**v0.2 — July 2026**

Added the Propose/Approve/Execute mechanism to Part III, extracted from the waterworks-ai reference application into a shared, framework-level contract.

Part III — new section: The Propose/Approve/Execute Primitive. Defines the propose/hold/approve-or-deny flow, the division of responsibility between framework and host, the two-tier audit record (compliance vs. operational) and the current scope boundary (SUPERVISED mode only; ADVISORY, COLLABORATIVE, and AUTONOMOUS mode-dispatch logic remain unimplemented).

This is an additive, non-breaking change per the versioning policy defined below.

**v0.1 — June 2026**

Initial publication of the FieldWorks Framework Specification.

Introduction — framework overview, three-layer architecture, design philosophy, audience guide.

Part I — Protocol layer specification. Nine required tools, VQT response envelope, error handling, naming conventions, conformance requirements, reference implementations.

Part II — Plant layer specification. topology.yaml schema, aggregator.json schema, equipment type and instance modeling, fault modes, topology builder, legacy mode, validation, modeling imperfect plants.

Part III — Agent layer specification. Five fixed agents (Cascade, Specialist, Historian, Deadband, Millwright), diagnostic and action paths, trust mode ladder, audit trail contract.

Part IV — Memory layer specification. Four-store architecture (LadybugDB, DuckDB, InfluxDB, specialist memory files), memory-mcp server, memory lifecycle, Phase 2 planned extensions.

Versioning — this section.

## Compatibility

### Spec version to implementation

The waterworks-ai reference implementation tracks the current spec version. The README documents which spec version it implements.

| Version | Date | Summary |
|:---|:---|:---|
| `0.1` | `2026-06` | waterworks-ai v0.1 — Phases 8–10 implemented. Protocol layer, plant layer, four-store memory, topology builder. |
| `0.2` | 2026-07 | fieldworks-core adds the Propose/Approve/Execute mechanism (SUPERVISED mode only). waterworks-ai has not yet migrated its existing action-path code onto it. |
| `0.3` | 2026-11 | fieldworks-adapters 1.0.5 and later conform to Part I. fieldworks-core 1.3.0 implements the conformance suite, trust dispatch and the memory clients. It does not yet record `auth_method` or the dispatch disposition, or provide Part V. waterworks-ai 3.3.0 implements reactive mode, the memory server and the enterprise layer. Its action path does not yet use fieldworks-core's trust layer or record `operator_id`. |
| `0.4` | 2026-11 | fieldworks-adapters 1.0.5 and later conform to Part I. fieldworks-core 1.5.0 adds the Part V enterprise layer (1.4.0) and the Verdict Blocks templates and parser. It does not yet record `auth_method` or the dispatch disposition, or load `facility.trust_mode`. waterworks-ai 3.4.0 runs its enterprise layer and verdict parsing on fieldworks-core, meeting Part V's validation, federated-read and audit rules. Its action path does not yet use fieldworks-core's trust layer or record `operator_id`. |

### Breaking change policy

Breaking changes increment the major version. The following are considered breaking:

Removing or renaming a required tool from the conformant tool surface.

Changing the VQT response envelope schema in a way that breaks existing consumers.

Changing required fields in topology.yaml or aggregator.json.

Changing the LadybugDB schema in a way that requires migration of existing graphs.

Changing agent behavior in a way that breaks existing operator workflows.

The following are not breaking and increment the minor version:

Adding new optional fields to any schema.

Adding new tools to the conformant surface that do not replace existing ones.

Adding new sections or parts to the specification.

Adding new event types to the audit trail.

Adding new trust mode configurations.

### Deprecation policy

Features deprecated in a minor version are supported for at least one full major version before removal. Deprecated features are marked in the specification with a deprecation notice and the target removal version.

No features are deprecated as of v0.3.

## Contributing to the spec

The FieldWorks Framework Specification is maintained in the FieldWorks GitHub organization. Its source is Markdown, in the `spec/` directory of the fieldworks-spec repository. The PDF for each release is built from that source. Proposed changes go through a review process before being incorporated.

**Bug reports and clarifications** — open an issue in the fieldworks-spec repository. Patch releases are cut regularly to incorporate clarifications.

**Additive proposals** — open a pull request with the proposed text. Additive changes that do not break existing implementations are incorporated into the next minor release.

**Breaking change proposals** — open an issue for discussion before writing spec text. Breaking changes require a clear migration path and are batched into major releases.

**Changes that come with code** — when a change to fieldworks-core or fieldworks-adapters alters a contract this specification defines, open the spec pull request first or alongside the code, and link the two. The code then implements written text rather than the text catching up with the code.

> The reference implementations are authoritative when the spec is ambiguous. If a reference implementation and the spec disagree, the spec takes precedence and the implementation is a bug — unless the spec is genuinely unclear, in which case a clarification patch is issued first.
