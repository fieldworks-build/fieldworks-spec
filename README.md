# FieldWorks Framework Specification

**Version 0.4 — November 2026**

The normative reference for FieldWorks-conformant protocol adapters, plant topology definitions, agent behavior, and memory architecture.

**Read it:** [Introduction](spec/00-introduction.md) · [Versioning](spec/01-versioning.md) · [Part I — Protocol](spec/02-protocol-layer.md) · [Part II — Plant](spec/03-plant-layer.md) · [Part III — Agent](spec/04-agent-layer.md) · [Part IV — Memory](spec/05-memory-layer.md) · [Part V — Enterprise](spec/06-enterprise-layer.md)

**PDF:** each release is attached to [Releases](https://github.com/fieldworks-build/fieldworks-spec/releases). The v0.1 and v0.2 PDFs, which predate the Markdown source, are in [archive/](archive/).

---

## What's in the spec

**Part I — Protocol Layer**
The conformant tool surface. Every FieldWorks adapter implements these nine tools with identical signatures and the VQT response envelope.

**Part II — Plant Layer**
The `topology.yaml` schema. Equipment types, instances, attributes, fault modes, process areas, and write permissions. The `aggregator.json` schema. The topology builder.

**Part III — Agent Layer**
Five fixed agents — Cascade, Specialist, Historian, Deadband, Millwright. Diagnostic and action paths. The four-mode trust ladder (advisory, supervised, collaborative, autonomous) and its dispatch rules. The Propose/Approve/Execute mechanism. Audit trail contract.

**Part IV — Memory Layer**
Five-store architecture — LadybugDB, DuckDB, InfluxDB, specialist memory files, and the knowledge store for facility documentation. The memory server's tool contract. Memory lifecycle.

**Part V — Enterprise Layer**
Multi-plant deployments. Plant boundaries, the `enterprise.yaml` schema, `site_id`, federated read, and the cross-plant orchestrator.

---

## Quick reference

### The nine required tools

| Tool | Description |
|---|---|
| `connect` | Establish connection to the protocol surface |
| `disconnect` | Close the connection |
| `discover_tags` | Return available tags with metadata |
| `read_tag` | Read current value — returns VQT envelope |
| `read_tag_history` | Read time series for a tag |
| `write_tag` | Write a value to a writable tag |
| `get_server_info` | Return adapter metadata and connection state |
| `scan` / `browse` | Incremental address space exploration (protocol-specific name) |
| `get_topic_tree` / `get_node_tree` | Full address space retrieval (protocol-specific name) |

Seven tools use identical names across all adapters. `scan`/`browse` and `get_topic_tree`/`get_node_tree` occupy single conformant slots with protocol-appropriate names.

### The VQT envelope

Every tool that returns tag data returns this shape:

```json
{
  "tag_id": "string",
  "value": "number | boolean | string",
  "quality": "good | uncertain | bad",
  "timestamp": "ISO 8601 UTC",
  "units": "string"
}
```

Quality is never absent. If the protocol does not provide quality natively, the adapter must infer it.

### Conformance

An adapter is conformant if it implements all nine tools, returns the VQT envelope for all data operations, returns structured errors, declares the required MCP tool annotations, enforces topology write permissions, and logs all write operations.

Partial conformance is not conformance.

---

## Validation

```bash
# Validate topology.yaml
fieldworks validate topology.yaml

# Validate with aggregator — checks tag bindings against live adapters
fieldworks validate topology.yaml --aggregator aggregator.json

# Run the adapter conformance suite against an adapter binary
fieldworks test-adapter --command "mqtt-mcp" --host localhost --port 1883
fieldworks test-adapter --command "opcua-mcp" --host 127.0.0.1 --port 4840
```

---

## Reference implementation

[waterworks-ai](https://github.com/smslavin/waterworks-ai) is the reference application. The Compatibility table in [spec/01-versioning.md](spec/01-versioning.md) lists which parts of each spec version it and the framework implement.

---

## Implementations

| Repo | Language | Status |
|---|---|---|
| [fieldworks-core](https://github.com/fieldworks-build/fieldworks-core) | Python | 1.5.0, v0.4 except as noted in Compatibility |
| [fieldworks-adapters](https://github.com/fieldworks-build/fieldworks-adapters) | Rust | 1.0.5+ conforms to v0.3 Part I: mqtt-mcp, opcua-mcp, modbus-mcp |

---

## Version history

| Version | Date | Summary |
|---|---|---|
| 0.4 | 2026-11 | Defined the FINDINGS and SUMMARY verdict blocks in Part III. |
| 0.3 | 2026-11 | Caught up with shipped code: annotations, trust dispatch, reactive mode, knowledge store, operator identity. Added Part V (enterprise). |
| 0.2 | 2026-07 | Added the Propose/Approve/Execute mechanism to Part III (SUPERVISED mode only). |
| 0.1 | 2026-06 | Initial release. Parts I–IV, topology builder, audit trail, versioning. |

Full changelog in [spec/01-versioning.md](spec/01-versioning.md).

---

## Source and build

The Markdown in [`spec/`](spec/) is the source of truth, one file per part. The PDF is generated from it, so never edit a PDF by hand.

```bash
scripts/build-pdf.sh 0.3    # -> build/FieldWorks_Framework_Specification_v0.3.pdf
```

The script needs only [uv](https://docs.astral.sh/uv/). It runs pandoc and the Typst compiler from pinned Python packages, so a local build matches CI. `scripts/table-widths.lua` and the Typst rules in `spec/metadata.yaml` handle PDF layout only and don't affect the Markdown.

CI (`.github/workflows/pdf.yml`) builds the PDF for every pull request that touches the spec and attaches it as a workflow artifact. Pushing a `v*` tag publishes a GitHub Release with the PDF.

---

## Contributing

- **Bug reports and clarifications:** open an issue.
- **Proposed changes:** open a pull request that edits the Markdown. Review the PDF artifact CI attaches.
- **Breaking change proposals:** open an issue for discussion before writing spec text.
- **Changes that come with code:** when a fieldworks-core or fieldworks-adapters change alters a contract the spec defines, open the spec PR first or alongside the code, and link the two.

---

## License

Apache 2.0
