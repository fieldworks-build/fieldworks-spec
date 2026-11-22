# Part IV - The Memory Layer

## Overview

Parts I through III describe a FieldWorks deployment that is capable and correct within a session. The protocol layer gives agents access to plant data. The plant layer gives that data meaning. The agent layer reasons, validates and acts. The audit trail records everything.

What Parts I through III do not provide is memory. Every session starts cold. A Specialist dispatched to diagnose a fault on RawWater_01 knows the topology, knows the current values and knows the fault mode descriptions. It does not know that RawWater_01 threw the same fault three times in the past six weeks, that the operator dismissed the first two events as transient or that the vibration binding on that equipment was flagged as suspect after a transmitter replacement. That knowledge exists in several places, in the audit trail, in the historian, in the operator's head but, nothing carries it forward into the next session.

The memory layer closes that gap. It is a five-store architecture that gives agents persistent, structured access to plant knowledge that accumulates across sessions. The agents get smarter over deployments without anyone having to manually update anything.

The context management work addressed efficiency within a session. The memory layer addresses intelligence across sessions. They are related but distinct problems.

## The Five Stores

Each store in the memory architecture serves a specific purpose. They are not interchangeable. The right store for a given query depends on the nature of the question being asked.

> **LadybugDB** - knowledge graph
>
> Structured plant knowledge. Equipment topology, fault causality chains, past incident fingerprints, operator decision patterns. Queryable in Cypher. The static layer describes what the plant is. The dynamic layer accumulates what has happened to it.

> **DuckDB** - analytical layer
>
> Long-horizon cross-equipment analytics. Materializes from InfluxDB on a configurable schedule. The Historian reaches for DuckDB when a query spans weeks or requires cross-equipment joins. InfluxDB when it needs recent trends.

> **InfluxDB** - time-series source
>
> The plant's process history at full resolution. Every tag value the streaming layer ingests lands here first. The Historian queries it directly for recent trends, and DuckDB materializes from it for long-horizon work.

> **Specialist memory files** - per-specialist persistent notes
>
> Unstructured cross-session knowledge. Per-specialist markdown files that accumulate equipment deviation observations, confidence updates, and recurring pattern flags. Injected into the system prompt at session start.

> **Knowledge store** - facility documentation
>
> Equipment manuals, maintenance procedures, operating limits and text-layer P&IDs, chunked and embedded for semantic search. Specialists retrieve the passages relevant to the equipment they are diagnosing. Runs in DuckDB with the VSS extension, so it needs no separate vector database.

## LadybugDB - The Knowledge Graph

LadybugDB is an embedded, serverless graph database. A property graph model with a Cypher query interface. It runs in-process alongside the FieldWorks application, requires no separate server and is appropriate for air-gapped on-premises deployments. It is MIT licensed and is the active community continuation of the Kuzu project.

The knowledge graph has two layers. The static layer describes the plant as it is configured. The dynamic layer accumulates what has happened to it during operation. Together they make the plant model queryable as a living knowledge base rather than a static configuration file.

### The static layer

The static layer mirrors the topology model from Part II. Every node type and relationship in topology.yaml has a corresponding representation in the graph. On first startup, the framework seeds the graph from the topology configuration. From that point forward, the graph is the primary topology store.

> TagBinding is a node, not an edge. This is a deliberate design decision. A binding carries properties — confidence, notes, known issues — that would be awkward to express on a relationship. As a node, a binding is a first-class queryable object. The BINDS_ATTRIBUTE and BINDING_OF relationships connect it to equipment and attribute respectively.

### The dynamic layer

The dynamic layer accumulates operational history. The host writes it on defined triggers: an Incident for each finding that is not Normal, and an Observation when an operator confirms an insight (see The Memory Lifecycle). It makes the plant model temporal. Not just what the plant is, but what has happened to it and what decisions have been made about it.

```cypher
// Node tables — static layer
CREATE NODE TABLE Facility (id STRING PRIMARY KEY, name STRING, ...)
CREATE NODE TABLE ProcessArea (id STRING PRIMARY KEY, name STRING, ...)
CREATE NODE TABLE EquipmentType (id STRING PRIMARY KEY, name STRING, ...)
CREATE NODE TABLE Equipment (id STRING PRIMARY KEY, name STRING, notes STRING, ...)
CREATE NODE TABLE Attribute (id STRING PRIMARY KEY, units STRING,
    normal_range_min DOUBLE, normal_range_max DOUBLE,
    writable BOOLEAN, requires_confirmation BOOLEAN,
    write_limit_min DOUBLE, write_limit_max DOUBLE)
CREATE NODE TABLE TagBinding (id STRING PRIMARY KEY, tag_id STRING,
    confidence STRING, notes STRING)
CREATE NODE TABLE FaultMode (id STRING PRIMARY KEY, name STRING,
    severity STRING, description STRING)

// Relationship tables — static layer
CREATE REL TABLE CONTAINS_AREA (FROM Facility TO ProcessArea)
CREATE REL TABLE CONTAINS_EQUIPMENT (FROM ProcessArea TO Equipment)
CREATE REL TABLE IS_TYPE (FROM Equipment TO EquipmentType)
CREATE REL TABLE DEFINES_ATTRIBUTE (FROM EquipmentType TO Attribute)
CREATE REL TABLE HAS_FAULT_MODE (FROM EquipmentType TO FaultMode)
CREATE REL TABLE AFFECTS (FROM FaultMode TO Attribute)
CREATE REL TABLE BINDS_ATTRIBUTE (FROM Equipment TO TagBinding,
    attribute_id STRING)
CREATE REL TABLE BINDING_OF (FROM TagBinding TO Attribute)
CREATE REL TABLE FEEDS_INTO (FROM ProcessArea TO ProcessArea,
    description STRING)
```

```cypher
// Node tables — dynamic layer
CREATE NODE TABLE Incident (id STRING PRIMARY KEY, ts TIMESTAMP,
    session_id STRING, status STRING, confidence DOUBLE,
    user_question STRING, mode STRING)
CREATE NODE TABLE Observation (id STRING PRIMARY KEY, ts TIMESTAMP,
    tag_id STRING, value DOUBLE, quality STRING, note STRING)
CREATE NODE TABLE OperatorDecision (id STRING PRIMARY KEY, ts TIMESTAMP,
    operator_id STRING, action STRING, reason STRING, outcome STRING)

// Relationship tables — dynamic layer
CREATE REL TABLE INCIDENT_ON (FROM Incident TO Equipment)
CREATE REL TABLE CONSISTENT_WITH (FROM Incident TO FaultMode)
CREATE REL TABLE OBSERVATION_ON (FROM Observation TO Equipment)
CREATE REL TABLE DECISION_ON (FROM OperatorDecision TO Incident)
CREATE REL TABLE PRECEDES (FROM Incident TO Incident,
    days_between DOUBLE)
```

The PRECEDES relationship connects incidents on the same equipment in chronological order. This is what makes recurrence patterns queryable. A Specialist can ask, how many times has this fault appeared on this equipment, how far apart were the events and what did the operator do each time. Without PRECEDES, answering that question requires parsing the audit log. With it, it is a single Cypher traversal.

CONSISTENT_WITH connects an incident to the fault mode it matched. This is the link between the dynamic layer and the static layer. When the Specialist diagnoses a bearing wear fault on RawWater_01, the incident node is connected to the bearing_wear fault mode node. Future sessions can query: which fault modes have appeared on this equipment, and how recently.

### Write permission metadata

The Attribute node carries write permission metadata in the static layer. This is the graph representation of the write constraints defined in Part II. Millwright queries the graph before executing a write to confirm the tag is writable, whether operator confirmation is required, and what the hard limits are.

| Field | Type | Required | Description |
|:---|:---|:---|:---|
| `writable` | boolean | yes | Whether this attribute accepts writes via write_tag. Default false. |
| `requires_confirmation` | boolean | yes | Whether operator approval is required before a write is executed. Applies only when writable is true. |
| `write_limit_min` | double | no | Hard lower bound on any write value. Millwright rejects writes below this value regardless of what any agent or operator requests. |
| `write_limit_max` | double | no | Hard upper bound on any write value. Millwright rejects writes above this value regardless of what any agent or operator requests. |

> The hard limits in the graph are the same limits defined in topology.yaml. They are not advisory. Millwright does not override them for any reason at any trust level. The graph is the enforcement layer for write constraints.

### Example queries

The following Cypher queries illustrate the kinds of questions the graph makes answerable.

**Build a specialist prompt for a process area**

Everything a Specialist needs to know about its process area in a single traversal.

```cypher
MATCH (area:ProcessArea {id: 'intake'})-[:CONTAINS_EQUIPMENT]->(e:Equipment)
      -[:IS_TYPE]->(t:EquipmentType)
OPTIONAL MATCH (t)-[:DEFINES_ATTRIBUTE]->(attr:Attribute)
OPTIONAL MATCH (t)-[:HAS_FAULT_MODE]->(fm:FaultMode)
OPTIONAL MATCH (e)-[:BINDS_ATTRIBUTE {attribute_id: attr.id}]->(b:TagBinding)
RETURN area.name, area.specialist_prompt, e.name, e.notes,
       t.name, attr.name, attr.units,
       attr.normal_range_min, attr.normal_range_max,
       b.tag_id, b.confidence, b.notes,
       fm.name, fm.severity, fm.description
ORDER BY e.name, attr.name
```

**Fault recurrence on a specific equipment instance**

```cypher
MATCH (e:Equipment {id: 'RawWater_01'})<-[:INCIDENT_ON]-(i:Incident)
      -[:CONSISTENT_WITH]->(fm:FaultMode)
OPTIONAL MATCH (i)-[:PRECEDES]->(next:Incident)
RETURN i.ts, fm.name, fm.severity, i.confidence,
       i.status, next.ts AS next_occurrence
ORDER BY i.ts
```

**Operator decisions following a fault mode**

```cypher
MATCH (fm:FaultMode {id: 'pump_cavitation'})<-[:CONSISTENT_WITH]-(i:Incident)
      <-[:DECISION_ON]-(d:OperatorDecision)
RETURN d.action, d.outcome, count(*) AS frequency
ORDER BY frequency DESC
```

**All writable attributes with hard limits**

```cypher
MATCH (e:Equipment)-[:BINDS_ATTRIBUTE]->(b:TagBinding)
      -[:BINDING_OF]->(a:Attribute {writable: true})
RETURN e.name, a.name, b.tag_id,
       a.requires_confirmation,
       a.write_limit_min, a.write_limit_max
ORDER BY e.name
```

## DuckDB - The Analytical Layer

DuckDB is an embedded analytical database. It runs in-process, requires no server and is optimized for columnar analytical queries over large datasets. It complements InfluxDB rather than replacing it.

InfluxDB is the right tool for ingesting continuous process data and querying recent time series. It is not designed for complex cross-equipment analytical queries spanning weeks or months. DuckDB fills that gap.

### Data pipeline

A configurable pipeline materializes process data from InfluxDB into DuckDB on a schedule. The pipeline runs in the background and does not interrupt real-time operations. The materialization interval is set in the aggregator configuration.

```json

# aggregator.json — DuckDB pipeline configuration

{
  "duckdb": {
    "path": "./data/fieldworks.duckdb",
    "sync_interval_minutes": 15,
    "lookback_days": 90
  }
}
```

The DuckDB database holds the materialized process data in a structure optimized for analytical queries. The Historian queries it directly using SQL rather than Flux, which is more expressive for multi-equipment correlation queries.

### The Historian’s data source hierarchy

The Historian agent selects its data source based on the nature of the query. This distinction is explicit in the Historian's system prompt and is enforced by the available tools rather than left to the model's judgment.

**InfluxDB** — recent trends, current session context, queries spanning hours to a few days. The Historian defaults here for most queries.

**DuckDB** — long-horizon analytics, cross-equipment correlations, queries spanning weeks to months. The Historian reaches for run_correlation when the query requires it.

> The data source distinction is not exposed to the operator. From the operator's perspective, the Historian answers time-dimension questions. Which store it queries to answer them is an implementation detail the Historian manages based on the query scope.

## Specialist Memory Files

Specialist memory files are per-specialist markdown files that persist unstructured knowledge across sessions. Each specialist has its own file, keyed by the specialist's name. fieldworks-core provides them as `fieldworks.memory.SpecialistMemory`, which reads a file and appends timestamped entries to it.

They are not a log. They are a distillation: only what is worth carrying forward. Observations that change how future sessions should interpret this equipment, confidence updates on tag bindings, recurring patterns that have not been formally captured in the graph.

### Who writes them

An entry reaches a memory file through an operator. When an operator saves an insight from a session and routes it to specialist memory, the host appends it to that specialist's file. Agents read their memory files but do not write them. A note an agent wrote about itself, unreviewed, would carry into every later session with no one having checked it.

### Memory scope

**Specialist memory** — process area specific. RawWater_01's binding confidence notes live in the intake specialist's memory. Each specialist's file holds knowledge about its own process area.

**Historian memory** — pattern knowledge that spans process areas: recurring fault signatures, seasonal baselines, correlations seen across sessions. The Historian is a specialist like any other here and keeps its own file.

### Bootstrap

At session start, the host reads each specialist's memory file and places it at the top of that specialist's system prompt, ahead of the topology context and before the specialist reads any sensor data. The specialist reasons from it from its first step. If the memory server is unreachable, the specialist starts without it (see Graceful degradation).

### What goes in a memory file

Memory files are structured but not rigidly schema-bound. Entries are natural language, filed under consistent section headings. The following sections appear in every well-maintained memory file.

```markdown

# Intake Specialist Memory

Last updated: 2026-06-03T18:45:00Z

## Equipment notes

- RawWater_01: Vibration binding suspect since 2023-08 transmitter replacement.
  Reads consistently 0.8 mm/s high. Weight accordingly.
- RawWater_02: Run status anomaly pattern. Shows non-zero flow when stopped.
  Sensor zeroing deferred — flag for instrumentation team on next inspection.

## Recurring patterns

- Suction starvation on RawWater_01 correlates with high turbidity events.
  Three occurrences in past 90 days, each resolved within 4 hours.
  Check upstream clarifier level when this fault appears.

## Confidence updates

- pump_pressure binding on RawWater_02: downgraded to inferred.
  Transmitter appears to read 0.3 bar low based on cross-check with flow.

## Operator patterns

- Night shift typically reduces pump speeds proactively during high turbidity.
  Context for interpreting low-flow readings between 22:00 and 06:00.
```

> Memory files are not the audit trail. They are not a log of what happened. They are a specialist's working notes — the knowledge worth carrying forward, distilled from sessions. Redundancy with the audit trail is intentional: the audit trail is complete and uneditable, the memory file is curated and current.

## The Knowledge Store

Facility documentation — equipment manuals, maintenance procedures, operating limits, P&IDs — holds domain knowledge that no sensor data can provide. A Specialist that can reason against a pump's engineering manual knows things the topology alone cannot tell it.

fieldworks-core provides the knowledge store as `fieldworks.memory.KnowledgeClient`.

- **Storage.** DuckDB with the VSS extension, in the same embedded engine as the analytical layer. No separate vector database service.

- **Embeddings.** Local by default, through `fastembed`. Documents and queries never leave the deployment. The embedding provider is pluggable.

- **Ingestion.** `.md`, `.txt` and text-layer `.pdf` files are chunked and embedded. Scanned PDFs without a text layer and CAD or image P&IDs are out of scope. Ingestion skips a file it cannot read rather than failing the whole batch.

- **Change detection.** Each file's content hash is stored. Re-ingesting a directory skips unchanged files and re-embeds only new or edited ones.

- **Retrieval.** Semantic search returns the top matching passages with their source file. A query can be scoped to one equipment instance.

Air-gapped deployments install the VSS extension and download the embedding model once while online, then ship both inside the deployment image. `KnowledgeConfig.extension_directory` points DuckDB at the vendored extension, so nothing is fetched at runtime.

> The knowledge store is reference material, not plant history. It answers "what does the manual say about this pump" and never "what happened to this pump". That question belongs to the graph and the historian.

## The Memory Server

The memory layer reaches the agent layer through an MCP server registered in aggregator.json, alongside the protocol adapters and the audit server.

The framework and the deployment split the work the same way they do for the trust layer. fieldworks-core provides the clients that do the work: `GraphClient`, `AnalyticalClient`, `SpecialistMemory` and `KnowledgeClient`. This section defines the tool contract a memory server exposes over them. The server process itself (its MCP wiring, port, environment and startup) is deployment code. The waterworks-ai reference application's `memory-mcp/` is the reference server.

```json
{
  "name": "memory",
  "url": "http://localhost:8006/sse"
}
```

### Tool surface

The aggregator prefixes each tool with the server name, so agents see `memory__query_graph`, `memory__run_correlation` and so on. Every tool declares MCP annotations under the same rules as Part I.

| Tool | Access | Description |
|:---|:---|:---|
| `get_topology` | read | Full process area → equipment → type tree. Used for Cascade routing decisions. |
| `get_specialist_context` | read | Equipment, attributes, fault modes, tag bindings and area notes for one process area. |
| `get_equipment_history` | read | Past incidents, observations and operator decision patterns for one equipment instance. |
| `get_writable_attributes` | read | Every writable attribute with its tag, confirmation requirement and write limits. |
| `get_severity_for_attribute` | read | Severity for an equipment type and attribute, from the graph's FaultMode nodes. Used by the reactive monitor. |
| `query_graph` | read | Read-only Cypher against the knowledge graph. Write clauses are rejected. |
| `run_correlation` | read | SELECT query against the DuckDB analytical layer. Used by the Historian for long-horizon and cross-equipment analysis. |
| `query_knowledge` | read | Semantic search over the knowledge store, optionally scoped to one equipment instance. |
| `get_specialist_memory` | read | One specialist's memory file. |
| `record_incident` | write | Write an Incident node and link it to its Equipment and, if known, its FaultMode. |
| `record_observation` | write | Write an Observation node for an equipment instance. |
| `link_incident_precedes` | write | Link two incidents with a PRECEDES relationship for causality-chain queries. |
| `append_specialist_memory` | write | Append a timestamped entry to one specialist's memory file. |
| `ingest_knowledge_docs` | write | Re-scan the knowledge document directory. Unchanged files are skipped. |
| `seed_discovered_topology` | destructive | Bulk-write a confirmed topology-builder result into the graph (Part II). |

Agents receive only the read tools. The write tools are called by the host on defined triggers, described in The Memory Lifecycle below, so nothing an agent concludes enters permanent memory without the host deciding it should.

### Graceful degradation

Memory access degrades gracefully. If the memory server is unavailable, sessions still operate. The protocol adapters, aggregator and agent layer continue to function without the memory layer. The only loss is accumulation. Sessions run without knowledge of previous sessions.

This is a deliberate design decision. In industrial settings, uptime is not optional. A memory layer failure must not take the diagnostic capability offline. The memory layer enhances the system. It is not a dependency of the system.

> Graceful degradation applies to the memory layer as a whole. Individual tool failures within a session are handled by the agents. A failed query_graph call is logged and the specialist continues without that context, noting the gap in its findings.

## The Memory Lifecycle

A complete session with memory follows a defined sequence.

The host reads each dispatched specialist's memory file via `get_specialist_memory` and places it at the top of that specialist's system prompt.

Cascade routes the query using the topology. Each specialist pulls the graph context it needs through `get_specialist_context`, `get_equipment_history` and `query_graph`, and the relevant documentation through `query_knowledge`.

Specialists read live and historical data from the protocol adapters and InfluxDB. The Historian queries DuckDB via `run_correlation` when long-horizon context is needed.

Specialists return findings to Cascade. Cascade synthesizes and returns the response to the operator.

For each specialist whose finding is not Normal, the host writes an Incident node via `record_incident` for the equipment that specialist covers, carrying the session, the diagnosis, the status and the confidence.

When the operator saves an insight from the session, the host routes it to its target: an Observation node via `record_observation`, or a specialist's memory file via `append_specialist_memory`.

This lifecycle runs on every session. The accumulation is gradual and continuous. Incidents build the graph's operational history on their own. Observations and memory notes accumulate as operators confirm what is worth keeping. After a year, the system holds institutional knowledge that no individual session could have provided.

## Planned Memory Layer Extensions

The following extensions are planned as the framework matures.

### Vector store for fault mode retrieval

The current implementation injects all fault mode descriptions for a process area into the specialist system prompt. This works for facilities with a small number of equipment types. At enterprise scale, with hundreds of equipment types and thousands of fault mode descriptions, the context window becomes a constraint.

A vector store over fault mode embeddings allows the framework to retrieve only the fault modes that are semantically similar to what the current sensor data suggests. The specialist receives a focused, relevant set of fault modes rather than the full library. The knowledge store's embedding and search machinery is the likely foundation.

### Operator decisions in the graph

The graph schema defines OperatorDecision nodes, and `get_equipment_history` already reads them as decision patterns. Nothing writes them yet. The action path will write one for every approval and denial, linked to the equipment it targeted, so specialists can see how operators have responded to similar proposals before.

### Cascade shared memory

A memory file shared across all specialists: plant-wide known issues, recent session summaries, operator communication preferences, trust mode history. Every specialist would read it at bootstrap, before its own file.
