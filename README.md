# FieldWorks Framework Specification

**Version 0.1 — June 2026**

The normative reference for FieldWorks-conformant protocol adapters, plant topology definitions, agent behavior, and memory architecture.

[Download PDF — v0.1](spec/FieldWorks_Framework_Specification_v0.1.pdf)

---

## What's in the spec

**Part I — Protocol Layer**
The conformant tool surface. Every FieldWorks adapter implements these nine tools with identical signatures and the VQT response envelope.

**Part II — Plant Layer**
The `topology.yaml` schema. Equipment types, instances, attributes, fault modes, process areas, and write permissions. The `aggregator.json` schema. The topology builder.

**Part III — Agent Layer**
Five fixed agents — Cascade, Specialist, Historian, Deadband, Millwright. Diagnostic and action paths. Trust mode ladder. Audit trail contract.

**Part IV — Memory Layer**
Four-store architecture — LadybugDB, DuckDB, InfluxDB, specialist memory files. The memory-mcp server. Memory lifecycle.

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

An adapter is conformant if it implements all nine tools, returns the VQT envelope for all data operations, returns structured errors, enforces topology write permissions, and logs all write operations.

Partial conformance is not conformance.

---

## Validation

```bash
# Validate topology.yaml
fieldworks validate topology.yaml

# Validate with aggregator — checks tag bindings against live adapters
fieldworks validate topology.yaml --aggregator aggregator.json

# Run the adapter conformance suite
fieldworks test-adapter --url http://localhost:8001/sse --protocol mqtt
fieldworks test-adapter --url http://localhost:8002/sse --protocol opcua
```

---

## Reference implementation

[waterworks-ai](https://github.com/smslavin/waterworks-ai) implements FieldWorks Framework Specification v0.1.

---

## Implementations

| Repo | Language | Status |
|---|---|---|
| [fieldworks-core](https://github.com/fieldworks-build/fieldworks-core) | Python | v0.1 |
| [fieldworks-adapters](https://github.com/fieldworks-build/fieldworks-adapters) | Rust | v0.1 — mqtt-mcp, opcua-mcp |

---

## Version history

| Version | Date | Summary |
|---|---|---|
| 0.1 | 2026-06 | Initial release. Parts I–IV, topology builder, audit trail, versioning. |

Full changelog in the PDF.

---

## Contributing

Bug reports and clarifications — open an issue. 
Proposed changes — open a pull request. 
Breaking change proposals — open an issue for discussion before writing spec text.

---

## License

Apache 2.0
