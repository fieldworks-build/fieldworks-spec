# Part IV - The Memory Layer

## Overview

Parts I through III describe a FieldWorks deployment that is capable and correct within a session. The protocol layer gives agents access to plant data. The plant layer gives that data meaning. The agent layer reasons, validates and acts. The audit trail records everything.

What Parts I through III do not provide is memory. Every session starts cold. A Specialist dispatched to diagnose a fault on RawWater_01 knows the topology, knows the current values and knows the fault mode descriptions. It does not know that RawWater_01 threw the same fault three times in the past six weeks, that the operator dismissed the first two events as transient or that the vibration binding on that equipment was flagged as suspect after a transmitter replacement. That knowledge exists in several places, in the audit trail, in the historian, in the operator's head but, nothing carries it forward into the next session.

The memory layer closes that gap. It is a four-store architecture that gives agents persistent, structured access to plant knowledge that accumulates across sessions. The agents get smarter over deployments without anyone having to manually update anything.

The context management work addressed efficiency within a session. The memory layer addresses intelligence across sessions. They are related but distinct problems.

## The Four Stores

Each store in the memory architecture serves a specific purpose. They are not interchangeable. The right store for a given query depends on the nature of the question being asked.

> **LadybugDB** - knowledge graph
>
> Structured plant knowledge. Equipment topology, fault causality chains, past incident fingerprints, operator decision patterns. Queryable in Cypher. The static layer describes what the plant is. The dynamic layer accumulates what has happened to it.

> **DuckDB** - analytical layer
>
> Long-horizon cross-equipment analytics. Materializes from InfluxDB on a configurable schedule. The Historian reaches for DuckDB when a query spans weeks or requires cross-equipment joins. InfluxDB when it needs recent trends.

> **InfluxDB** - time-series source
>
> Long-horizon cross-equipment analytics. Materializes from InfluxDB on a configurable schedule. The Historian reaches for DuckDB when a query spans weeks or requires cross-equipment joins. InfluxDB when it needs recent trends.

> **Specialist memory files** - per-specialist persistent notes
>
> Unstructured cross-session knowledge. Per-specialist markdown files that accumulate equipment deviation observations, confidence updates, and recurring pattern flags. Injected into the system prompt at session start.

## LadybugDB - The Knowledge Graph

LadybugDB is an embedded, serverless graph database. A property graph model with a Cypher query interface. It runs in-process alongside the FieldWorks application, requires no separate server and is appropriate for air-gapped on-premises deployments. It is MIT licensed and is the active community continuation of the Kuzu project.

The knowledge graph has two layers. The static layer describes the plant as it is configured. The dynamic layer accumulates what has happened to it during operation. Together they make the plant model queryable as a living knowledge base rather than a static configuration file.

### The static layer

The static layer mirrors the topology model from Part II. Every node type and relationship in topology.yaml has a corresponding representation in the graph. On first startup, the framework seeds the graph from the topology configuration. From that point forward, the graph is the primary topology store.

> TagBinding is a node, not an edge. This is a deliberate design decision. A binding carries properties — confidence, notes, known issues — that would be awkward to express on a relationship. As a node, a binding is a first-class queryable object. The BINDS_ATTRIBUTE and BINDING_OF relationships connect it to equipment and attribute respectively.

### The dynamic layer

The dynamic layer accumulates operational history. It is written to by the audit trail pipeline and by specialist agents as they complete sessions. It makes the plant model temporal. Not just what the plant is, but what has happened to it and what decisions have been made about it.

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

Specialist memory files are per-specialist markdown files that persist unstructured knowledge across sessions. Each specialist maintains its own memory file. Cascade maintains a shared memory file visible to all agents.

Memory files are written by specialists at the end of a session and read at the start of the next. They are not a log. They are a distillation. A specialist writes only what is worth carrying forward. Observations that change how future sessions should interpret this equipment, confidence updates on tag bindings, recurring patterns that have not been formally captured in the graph.

### Memory hierarchy

**Cascade shared memory** — plant-wide known issues, recent session summaries, operator communication preferences, trust mode history. All specialists read this before starting work.

**Specialist memory** — process area specific. RawWater_01's binding confidence notes live in the intake specialist's memory, not in Cascade's. Each specialist maintains its own knowledge base about its process area.

**Historian memory** — pattern knowledge that spans process areas. Recurring fault signatures, seasonal baselines, correlation patterns that the Historian has identified across multiple sessions.

### Bootstrap protocol

At session start, each specialist reads its memory file before doing anything else. This is not optional. It is the first step in the specialist's system prompt instruction. The memory file is injected into the system prompt along with the topology context from the graph.

```markdown

# Specialist system prompt — memory bootstrap

BEFORE READING ANY SENSOR DATA, read your memory file at:
  /memories/{process_area_id}/specialist_memory.md

This file contains accumulated knowledge from previous sessions.
Apply it to your diagnostic reasoning before querying current values.
Update it at the end of this session with anything worth carrying forward.
```

### What goes in a memory file

Memory files are structured but not rigidly schema-bound. The specialist writes in natural language with consistent section headings. The following sections appear in every well-maintained memory file.

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

```markdown

## Operator patterns

- Night shift typically reduces pump speeds proactively during high turbidity.
  Context for interpreting low-flow readings between 22:00 and 06:00.
```

> Memory files are not the audit trail. They are not a log of what happened. They are a specialist's working notes — the knowledge worth carrying forward, distilled from sessions. Redundancy with the audit trail is intentional: the audit trail is complete and uneditable, the memory file is curated and current.

## The memory-mcp server

The memory layer is exposed to the agent layer through a dedicated MCP server, memory-mcp. It runs alongside the protocol adapters and the audit-mcp server, and is wired into the aggregator configuration.

```json

# aggregator.json — memory-mcp server entry

{
  "name": "memory",
  "url": "http://localhost:8006/sse",
  "include_tools": [
    "graph__query",
    "graph__write_incident",
    "graph__write_observation",
    "graph__write_decision",
    "memory__read_specialist",
    "memory__write_specialist",
    "memory__read_cascade",
    "memory__write_cascade",
    "run_correlation"
  ],
  "description": "Knowledge graph, analytical queries, and specialist memory files"
}
```

### Tool surface

| Field | Type | Required | Description |
|:---|:---|:---|:---|
| `graph__query` | Cypher | yes | Execute a read-only Cypher query against the LadybugDB knowledge graph. Used by specialists to retrieve topology context, fault history, and operator decision patterns. |
| `graph__write_incident` | write | yes | Write a new Incident node and connect it to the relevant Equipment and FaultMode nodes. Called by Cascade at the end of sessions that produced a diagnostic finding. |
| `graph__write_observation` | write | yes | Write a new Observation node. Called by specialists when they note a tag value or condition worth recording outside the normal audit trail. |
| `graph__write_decision` | write | yes | Write a new OperatorDecision node and connect it to the relevant Incident. Called by the action path when an operator approves or denies an action. |
| `memory__read_specialist` | read | yes | Read the memory file for a specific specialist. Called at session start as part of the bootstrap protocol. |
| `memory__write_specialist` | write | yes | Write or update the memory file for a specific specialist. Called at session end. |
| `memory__read_cascade` | read | yes | Read the shared Cascade memory file. Called at the start of every session. |
| `memory__write_cascade` | write | yes | Write or update the shared Cascade memory file. Called by Cascade at session end when plant-wide knowledge warrants updating. |
| `run_correlation` | DuckDB | yes | Execute a cross-equipment analytical query against the DuckDB materialized dataset. Used by the Historian for long-horizon trend analysis and multi-equipment correlation queries. |

### Graceful degradation

Memory access degrades gracefully. If memory-mcp is unavailable, sessions still operate. The protocol adapters, aggregator and agent layer continue to function without the memory layer. The only loss is accumulation. Sessions run without knowledge of previous sessions.

This is a deliberate design decision. In industrial settings, uptime is not optional. A memory layer failure must not take the diagnostic capability offline. The memory layer enhances the system. It is not a dependency of the system.

> Graceful degradation applies to the memory layer as a whole. Individual tool failures within a session are handled by the agents. A failed graph\_\_query is logged and the specialist continues without that context, noting the gap in its findings.

## The Memory Lifecycle

A complete session with memory follows a defined sequence.

Cascade reads the shared memory file via `memory__read_cascade`.

Cascade dispatches specialists. Each specialist reads its own memory file via `memory__read_specialist` as the first action in its bootstrap.

Each specialist queries the knowledge graph for topology context, fault history and relevant operator decisions via `graph__query`.

Specialists read live and historical data from the protocol adapters and InfluxDB. The Historian queries DuckDB via `run_correlation` when long-horizon context is needed.

Specialists return findings to Cascade. Cascade synthesizes and returns the response to the operator.

At session end, Cascade writes updated knowledge to the shared memory file via `memory__write_cascade` if anything at the plant level warrants updating.

Each specialist writes its updated memory file via `memory__write_specialist`, recording any new observations, confidence updates, or patterns identified in this session.

If the session produced a diagnostic finding, Cascade writes an Incident node to the knowledge graph via `graph__write_incident` and connects it to the relevant Equipment and FaultMode nodes.

If an operator decision was made on the action path, it is written to the graph via `graph__write_decision` and connected to the Incident.

This lifecycle runs on every session. The accumulation is gradual and continuous. After ten sessions, the specialists know more than they did after one. After a hundred sessions, the knowledge graph holds a meaningful operational history. After a year, the system has institutional knowledge that no individual operator session could have provided.

## Phase 2 - Planned Memory Layer Extensions

The four-store architecture described in this part is the current implementation. The following extensions are planned as the framework matures.

### Vector store for fault mode retrieval

The current implementation injects all fault mode descriptions for a process area into the specialist system prompt. This works for facilities with a small number of equipment types. At enterprise scale, with hundreds of equipment types and thousands of fault mode descriptions, the context window becomes a constraint.

A vector store over fault mode embeddings allows the framework to retrieve only the fault modes that are semantically similar to what the current sensor data suggests. The specialist receives a focused, relevant set of fault modes rather than the full library. This is a planned addition for enterprise deployments.

### Knowledge memory via RAG

Facility documentation — P&IDs, equipment manuals, maintenance procedures, regulatory requirements — contains domain knowledge that no sensor data can provide. A Specialist that can reason against a pump's engineering manual knows things the topology alone cannot tell it.

RAG over facility documentation is planned as a knowledge memory layer. Documents are indexed at deployment time. Specialists query relevant sections when diagnosis requires deeper equipment or process knowledge than the topology provides.

### Reactive architecture

The current architecture is query-response. An operator asks a question; the agents answer it. The streaming layer ingests data continuously but agents do not act on it proactively.

The reactive architecture extends this. A streaming processor watches the incoming process data for patterns that match fault mode descriptions in the knowledge graph. When a pattern is detected, it wakes the relevant specialist proactively. The operator is notified before they need to ask.

The reactive architecture requires the memory layer to be in place before it makes sense. An agent waking up proactively without persistent memory just creates noise. With memory, it can filter against known patterns and known history before alerting. That is a planned Phase 2 capability.
