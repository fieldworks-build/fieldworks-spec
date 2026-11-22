# Part I - Protocol Layer

## Overview

The protocol layer is the foundation of FieldWorks. It is a collection of conformant MCP servers, one per industrial protocol, that give the agent layer a standardized, consistent tool surface regardless of what protocol is running underneath.

Every conformant FieldWorks MCP server exposes the same nine tools. Seven tool names are identical across all adapters. Two tools, incremental address space exploration and full tree retrieval, use protocol-appropriate names that reflect the fundamentally different discovery models of each protocol. The input signatures and response envelope are identical for the seven universal tools.

For the two protocol-specific slots, the response shape is identical but the names and parameters differ per protocol. The AI never knows whether it is reading from an MQTT broker, an OPC-UA server or a PI historian. It calls the same tools with the same parameters and receives the same shape of response.

| Conceptual Slot | MQTT | OPCUA |
|:------------------------|:-------------------|:------------------|
| Incremental exploration | scan               | browse            |
| Full tree retrieval     | `get_topic_tree` | `get_node_tree` |

Swap the adapter. Nothing else changes.

This part of the specification is written for protocol adapter builders. System integrators, equipment vendors and OT engineers who want to build a conformant MCP server for a protocol not yet covered by the framework. It is self-contained. You do not need to read Parts II or III to implement a conformant adapter.

The reference implementations are mqtt-mcp and opcua-mcp, both available in the FieldWorks GitHub organization. When this specification is ambiguous, those implementations are authoritative.

## Naming Conventions

### Server naming

MCP servers are named using the pattern:

```json
{protocol}-mcp
```

Examples: mqtt-mcp, opcua-mcp, modbus-mcp, dnp3-mcp, ethernetip-mcp, aveva-mcp.

The server name is the protocol namespace. It provides context for every tool call. A tool called read_tag on mqtt-mcp is unambiguously mqtt-mcp::read_tag. Tool names carry no protocol prefix. The server name provides it.

### Tool naming

Tools use snake_case verb_noun format. No protocol prefix. No server prefix. The verb describes the action. The noun describes the target.

```json
{verb}_{noun}
```

The nine required tools follow this convention without exception. Protocol-specific extensions, if any, must also follow it.

### Parameter naming

Parameters use snake_case throughout. Tag identifiers are passed as tag_id. Time boundaries use start_time and end_time. Filter parameters use process_area and equipment_id consistently across all tools that accept them.

### Implementation note - Rust trait

The Rust adapter trait in fieldworks-adapters uses the MQTT tool names as canonical for the two protocol-specific slots: scan and get_topic_tree. OPC-UA adapters rename these to browse and get_node_tree in their implementations. Adapters targeting other protocols follow the same pattern. Choose the protocol-appropriate name and document the mapping in the adapter README.

## The VQT Response Envelope

VQT — Value, Quality, Timestamp — is the gold standard of industrial data. Every historian, every SCADA platform, every process data infrastructure speaks it. FieldWorks codifies it as the required response envelope for all data operations.

Every tool that returns tag data — read_tag, read_tag_history, write_tag confirmation — returns the same envelope:

```json
{
  "tag_id": "string",
  "value": "number | string | boolean",
  "quality": "good | uncertain | bad",
  "timestamp": "ISO 8601 string",
  "units": "string"
}
```

Field definitions

- **tag_id** — The tag identifier as passed in the request. Echoed back for correlation.

- **value** — The tag value. Type varies by tag data type. Numeric process values are float. Boolean states are boolean. String descriptors are string.

- **quality** — One of three states: good (value is reliable and current), uncertain (value may be stale, interpolated or from a degraded source), bad (value is not reliable; do not use for decisions)

- **timestamp** — ISO 8601 UTC. Always UTC. Never local time. Millisecond precision preferred.

- **units** — Engineering units string. Examples: degC, bar, m3/h, %, NTU, mg/L. Empty string if unitless or not applicable.

Quality is not optional. If the underlying protocol does not provide quality information natively, the adapter must infer it. A value received from a disconnected or timed-out source is bad. A value that exceeds the configured engineering range is uncertain. A value received normally from a healthy source is good.

## Error Handling

All tools return structured errors. Adapters must never throw unhandled exceptions that surface raw protocol errors to the agent layer. All protocol-specific errors are caught, translated, and returned in the standard error envelope.

```json
{
  "error": {
    "code": "string",
    "message": "string",
    "tag_id": "string | null"
  }
}
```

Required error codes

- `TAG_NOT_FOUND` — The requested tag_id does not exist on this server. Returned whenever the protocol can determine that a tag does not exist.

- `TAG_NOT_WRITABLE` — A write was attempted on a tag not configured for write access.

- `CONNECTION_ERROR` — The adapter cannot reach the protocol endpoint.

- `TIMEOUT` — The protocol endpoint did not respond within the configured timeout window.

- `INVALID_VALUE` — The value provided to write_tag is outside the configured engineering range or wrong type.

- `PERMISSION_DENIED` — The write was blocked by topology configuration write permissions.

- `HISTORY_UNAVAILABLE` — read_tag_history was called but the protocol or endpoint does not support historical data.

### Unknown tags on protocols without a tag registry

Some protocols cannot prove that a tag does not exist. MQTT has no server-side registry of topics. An MQTT adapter can only report that no message arrived on a topic within the timeout window. It cannot tell a topic that does not exist from one that has not published recently.

An adapter for such a protocol returns `TIMEOUT` for an unknown tag. That is conformant only when the protocol gives the adapter no way to check. An adapter whose protocol has an address space it can query, such as OPC-UA, must return `TAG_NOT_FOUND`. Returning `TIMEOUT` instead is non-conformant.

Clients treat both codes the same way for an unknown tag: there is no value for this tag.

Error messages must be human-readable. They will surface to operators. Protocol-specific codes and addresses should not appear in the message field.

## Result Shapes

MCP requires a tool's structured result to be a JSON object. A tool that returns a list wraps it in an object under a fixed key, so every client finds it in the same place:

| Tool | List key |
|:---|:---|
| `discover_tags` | `tags` |
| `browse` / `scan` | `entries` |
| `read_tag_history` | `values` |

Every other tool returns a single object, as defined in its table below. Errors use the error envelope above in place of the result.

## The Nine Required Tools

Every conformant FieldWorks MCP server implements exactly these nine tools. No more are required. Additional protocol-specific tools may be added but do not replace these. The agent layer depends on this surface being consistent and complete.

### Lifecycle Tools

#### `connect`

Establish a connection to the protocol endpoint. Called once on startup and on reconnect after a connection failure. Returns connection status and server metadata.

| Tool | connect |
|:---|:---|
| **Description** | Establish connection to the protocol endpoint. |
| **Parameters** | `host` (string, required) — Hostname or IP address of the protocol endpoint.<br>`port` (integer, required) — Port number.<br>`timeout_ms` (integer, optional) — Connection timeout in milliseconds. Default 5000.<br>`options` (object, optional) — Protocol-specific connection options (credentials, TLS config, client ID, etc.). |
| **Returns** | Connection status object: { connected: boolean, server_name: string, protocol_version: string, timestamp: ISO 8601 } |

#### `disconnect`

Cleanly terminate the connection to the protocol endpoint. Adapters must flush any pending operations before disconnecting. Called on graceful shutdown.

| Tool | disconnect |
|:---|:---|
| **Description** | Cleanly terminate the connection to the protocol endpoint. |
| **Parameters** | `reason` (string, optional) — Human-readable reason for disconnection. Logged to audit trail. |
| **Returns** | { disconnected: boolean, timestamp: ISO 8601 } |

### Discovery Tools

#### `discover_tags`

Enumerate available tags with full metadata. The primary mechanism for the plant layer to understand what data is available on a given adapter. Supports optional filtering by process area or equipment instance.

| Tool | discover_tags |
|:---|:---|
| **Description** | Enumerate available tags with metadata. Returns the full tag inventory or a filtered subset. |
| **Parameters** | `process_area` (string, optional) — Filter results to tags belonging to this process area. Must match a process_area defined in topology.yaml.<br>`equipment_id` (string, optional) — Filter results to tags belonging to this equipment instance.<br>`include_metadata` (boolean, optional) — Include extended metadata (description, normal range, fault modes). Default true. |
| **Returns** | Object wrapping an array of tag descriptors: { tags: [{ tag_id, name, description, units, data_type, writable, process_area, equipment_id, normal_range: { min, max } }] } |

#### `browse` (OPC-UA) / `scan` (MQTT)

browse and scan occupy a single conformant slot. Incremental address space exploration. A conformant adapter implements one, not both, based on its protocol. These tools share a conceptual purpose but reflect the fundamentally different discovery models of their respective protocols.

browse (OPC-UA) traverses the OPC-UA address space hierarchically from a given node. The address space is a tree; browse navigates it. Returns child nodes with their NodeId, BrowseName, NodeClass and display name. Recurse by calling browse on returned node IDs.

scan (MQTT) discovers active topics by subscribing to a wildcard pattern and collecting published topics over a defined observation window. Returns the set of topics seen during the window with their last known value and quality.

| Tool | browse / scan |
|:---|:---|
| **Description** | Protocol-native address space exploration. |
| **Parameters** | `node_id` (string, optional) — (OPC-UA) Starting node for traversal. Defaults to root Objects node.<br>`topic_pattern` (string, optional) — (MQTT) Wildcard subscription pattern. Default #.<br>`scan_duration_ms` (integer, optional) — (MQTT) Observation window duration. Default 5000.<br>`depth` (integer, optional) — (OPC-UA) Maximum traversal depth. Default 3. Use -1 for unlimited. |
| **Returns** | Object wrapping an array of discovered nodes or topics with available metadata: { entries: [ ... ] } |

#### `get_topic_tree` / `get_node_tree`

get_topic_tree and get_node_tree occupy a single conformant slot. Full tree retrieval. A conformant adapter implements one, not both, based on its protocol.Where browse/scan is an exploratory tool for navigating incrementally, get_topic_tree and get_node_tree return the full picture at once.

This tool is intentionally expensive. It is designed for two use cases: initial topology.yaml construction when onboarding a new plant, and periodic refresh to detect newly added equipment or sensors. It should not be called at query runtime.

| Tool | get_topic_tree / get_node_tree |
|:---|:---|
| **Description** | Return the complete address space as a structured hierarchical object. |
| **Parameters** | `root_node` (string, optional) — (OPC-UA) Root node for tree traversal. Default: Objects root.<br>`topic_prefix` (string, optional) — (MQTT) Prefix to scope the tree. Default: empty (full tree).<br>`include_values` (boolean, optional) — Include current values for leaf nodes. Increases response size significantly. Default false. |
| **Returns** | Nested object representing the full address space hierarchy. Leaf nodes include tag_id, name, data_type, units, and optionally current VQT. |

### Data Tools

#### `read_tag`

Read the current value of a single tag. The most frequently called tool in the framework. Returns the VQT envelope. Quality must always be present.

| Tool | read_tag |
|:---|:---|
| **Description** | Read the current value of a single tag by identifier. |
| **Parameters** | `tag_id` (string, required) — Tag identifier as returned by discover_tags or browse/scan. |
| **Returns** | VQT envelope: { tag_id, value, quality, timestamp, units } |

#### `read_tag_history`

Read a time series for a tag over a defined window. Used by the Historian agent to provide time dimension to diagnostic queries. Returns VQT envelopes ordered by timestamp ascending, wrapped in an object under `values`.

Not all protocols support historical data natively. Adapters for protocols without native historian capability must return a HISTORY_UNAVAILABLE error rather than attempting to simulate history.

| Tool | read_tag_history |
|:---|:---|
| **Description** | Read a time series for a tag over a defined time window. |
| **Parameters** | `tag_id` (string, required) — Tag identifier.<br>`start_time` (string, required) — Window start. ISO 8601 UTC.<br>`end_time` (string, required) — Window end. ISO 8601 UTC.<br>`max_points` (integer, optional) — Maximum number of data points to return. Adapter may interpolate or downsample to fit. Default 1000.<br>`quality_filter` (string, optional) — Return only values meeting this quality threshold. One of: good, good_or_uncertain. Default: no filter. |
| **Returns** | Object wrapping VQT envelopes ordered by timestamp ascending: { values: [{ tag_id, value, quality, timestamp, units }] } |

#### `write_tag`

Write a value to a tag. The only tool in the protocol layer with side effects on the physical process. Write access is gated by the topology configuration. An adapter must refuse writes to any tag not explicitly configured as writable in topology.yaml.

Millwright is the only agent that calls write_tag. The topology configuration defines which tags are writable and the hard limits that bound any write value. These limits cannot be overridden by any agent, including Millwright, regardless of what the diagnostic path has determined.

| Tool | write_tag |
|:---|:---|
| **Description** | Write a value to a tag. Gated by topology write permissions. |
| **Parameters** | `tag_id` (string, required) — Tag identifier. Must appear in topology write_permissions to succeed.<br>`value` (number \| boolean, required) — Value to write. Must be within the configured engineering range.<br>`units` (string, required) — Engineering units of the provided value. Adapter validates against configured units.<br>`operator_id` (string, required) — Identifier of the operator who approved this write. Logged to audit trail.<br>`reason` (string, required) — Human-readable reason for the write. Logged to audit trail. |
| **Returns** | Write confirmation VQT: { tag_id, value_written, quality, timestamp, units, operator_id } |

> operator_id and reason are required even when the write originates from an automated action path. The topology configuration determines what operator approval means in each deployment context — it may be a named individual, a role, or a session token. The adapter logs it; the topology defines it.

### Server Tool

#### `get_server_info`

Returns metadata about the adapter and its connection state. Called by Cascade on initialization to understand what protocol surfaces are available and their current health. Also useful for monitoring and diagnostics.

| Tool | get_server_info |
|:---|:---|
| **Description** | Return metadata about this adapter and its current connection state. |
| **Parameters** | None |
| **Returns** | { server_name: string, protocol: string, protocol_version: string, connected: boolean, connection_state: string, capabilities: \[string\], uptime_seconds: integer, last_error: string \| null } |

> capabilities is an array of tool names the server supports. All nine required tools are always listed. Protocol-specific extensions appear here as well. Cascade uses this to understand what it can rely on from each adapter.

## Conformance Requirements

A FieldWorks-conformant MCP server meets all of the following requirements:

- Implements all nine required tools with the exact signatures defined in this specification.

- Returns the VQT envelope for all data operations. Quality is never absent.

- Returns structured errors in the standard error envelope. Raw protocol errors never surface to the agent layer.

- Enforces topology write permissions on write_tag. Writes to tags not in topology write_permissions return TAG_NOT_WRITABLE.

- Logs all write operations with operator_id and reason. The log is append-only.

- Reports accurate capabilities in get_server_info.

- Uses UTC timestamps in ISO 8601 format throughout.

- Follows the naming conventions defined in this specification.

Adapters that meet these requirements are conformant. Adapters that do not are not FieldWorks adapters, regardless of whether they implement some subset of the tools.

Partial conformance is not conformance. The agent layer assumes the full surface is present. An adapter missing read_tag_history will cause Historian to fail silently. An adapter that surfaces raw protocol errors will confuse operators. The requirements exist because the framework depends on them.

## Reference Implementations

`mqtt-mcp` and `opcua-mcp` are the reference implementations of this specification. Both are open source and available in the FieldWorks GitHub organization.

When this specification is ambiguous, the reference implementations are authoritative. When the reference implementations diverge from this specification, this specification takes precedence and the implementation is a bug.

mqtt-mcp is the simpler of the two. It is the recommended starting point for understanding the conformant surface. The demo mode, deterministic synthetic data without a live broker, is particularly useful for understanding how the tool surface behaves under normal and fault conditions without requiring protocol infrastructure.

opcua-mcp demonstrates the browse/get_node_tree pattern and the OPC-UA address space model. The node hierarchy traversal and NodeId handling in opcua-mcp are the reference for any adapter targeting a protocol with a structured address space.

## What Comes Next

Part I is complete when you have a conformant MCP server that passes the conformance requirements. At that point you have a protocol adapter that can plug into any FieldWorks deployment.

Part II covers the plant layer. How to describe a real facility in topology.yaml so the agent layer understands the equipment, process areas, normal operating ranges, fault modes and write permissions. Part II assumes you have conformant adapters underneath.

Part III covers the agent layer. Cascade, the Specialists, Deadband, Millwright, the Historian, the action path and the audit trail contract. Part III assumes Parts I and II.
