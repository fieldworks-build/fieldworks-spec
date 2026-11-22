# Versioning

```text
Current version: 0.2
July 2026  ·  Sean Slavin  ·  fieldworks.build
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

New versions will be listed here as the spec evolves. Each entry links to the changelog below for detail on what changed.

## Changelog

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

No features are deprecated in v0.1.

## Contributing to the spec

The FieldWorks Framework Specification is maintained in the FieldWorks GitHub organization. Its source is Markdown, in the `spec/` directory of the fieldworks-spec repository. The PDF for each release is built from that source. Proposed changes go through a review process before being incorporated.

**Bug reports and clarifications** — open an issue in the fieldworks-spec repository. Patch releases are cut regularly to incorporate clarifications.

**Additive proposals** — open a pull request with the proposed text. Additive changes that do not break existing implementations are incorporated into the next minor release.

**Breaking change proposals** — open an issue for discussion before writing spec text. Breaking changes require a clear migration path and are batched into major releases.

**Changes that come with code** — when a change to fieldworks-core or fieldworks-adapters alters a contract this specification defines, open the spec pull request first or alongside the code, and link the two. The code then implements written text rather than the text catching up with the code.

> The reference implementations are authoritative when the spec is ambiguous. If a reference implementation and the spec disagree, the spec takes precedence and the implementation is a bug — unless the spec is genuinely unclear, in which case a clarification patch is issued first.
