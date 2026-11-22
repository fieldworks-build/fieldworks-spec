# Part V - The Enterprise Layer

## Overview

Parts I through IV describe one plant. A utility, a manufacturer or a pipeline operator runs many. Their questions cross plant boundaries: is everything normal across the region, has this pump fault appeared at any other site, which plants saw a turbidity event last week.

The enterprise layer answers those questions without merging the plants. Every plant stays a complete, independent FieldWorks deployment, with its own adapters, aggregator, agents, memory, audit trail, trust mode and credentials. The enterprise layer sits above them. It knows which plants exist and how to ask each one a question. It never reaches past a plant's own agents to its data or its controls.

> A plant's operators answer for that plant. An enterprise layer that could read another plant's sensors or write to its setpoints would put decisions about a plant outside the people accountable for it. The boundaries in this part exist to keep that from happening.

## Boundaries

These rules hold for every enterprise deployment. Every other section in this part follows from them.

- **Each plant is self-contained.** A plant runs its own stack, on its own ports, with its own API token. Losing the enterprise layer costs nothing at any plant. Each plant keeps operating exactly as it did.

- **No central store.** Each plant's stores stay authoritative for that plant's data. The enterprise layer reads across plants by asking each one (see Federated Read). It never replicates plant data into a store of its own.

- **No cross-plant data access.** The enterprise layer never calls a plant's protocol adapters, reads its time-series store or queries its knowledge graph. It learns about a plant's process only by asking that plant's agents.

- **No cross-plant actuation.** Nothing at the enterprise layer proposes, approves or executes a write at any plant. Every action at a plant goes through that plant's own action path, trust mode and operators.

- **Moving between plants is navigation.** A user interface that lets a user move from one plant to another sends them to that plant's own interface, at that plant's own origin. It never calls one plant's API from another plant's page. Each plant's interface can reach an actuation path, and each plant's credentials stay with that plant.

## enterprise.yaml

`enterprise.yaml` registers the plants in an enterprise. It is a configuration schema in the same family as topology.yaml and aggregator.json: one file per enterprise, the single source of truth for which plants exist and where to reach them.

```yaml
enterprise:
  name: Metro Water Authority

regions:
  - id: metro
    name: Metro Region
    sites:
      - site_id: wtp-riverside-01
        name: Riverside
        topology_file: plants/riverside/topology.yaml
        chat_ui_url: https://riverside.example.internal
        aggregator_url: https://riverside.example.internal:8100/sse
      - site_id: wtp-eastside-01
        name: Eastside
        topology_file: plants/eastside/topology.yaml
        chat_ui_url: https://eastside.example.internal
        aggregator_url: https://eastside.example.internal:8100/sse
  - id: valley
    name: Valley Region
    sites: []
```

#### `enterprise`

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `name` | string | yes | Human-readable enterprise name. Appears in enterprise-level responses. |

#### `regions`

Regions group sites for people. They carry no behavior: a query is never scoped by region unless a user asks for one by name.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `id` | string | yes | Unique region identifier. |
| `name` | string | yes | Human-readable region name. |
| `sites` | list | yes | The sites in this region. May be empty, so a region can be declared before its first plant comes online. |

#### `sites`

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `site_id` | string | yes | The plant's identifier. Must equal `facility.site_id` in the plant's topology.yaml. |
| `name` | string | yes | Human-readable plant name. |
| `topology_file` | string | yes | Path to the plant's topology.yaml, relative to enterprise.yaml. |
| `chat_ui_url` | string | yes | Base URL of the plant's own agent interface. The only address the cross-plant orchestrator uses for the plant. |
| `aggregator_url` | string | no | The plant's aggregator endpoint. Used only by federated read, to reach the plant's audit history. Without it, the plant is left out of federated reads and reported as such. |

### Validation

A conformant loader rejects an enterprise.yaml that breaks any of these rules:

- Every `site_id` is unique across the whole file, not just within its region.

- Every `region.id` is unique.

- Every site has `site_id`, `name`, `topology_file` and `chat_ui_url`.

- Every `topology_file` exists, loads as a valid topology.yaml (Part II, Validation), and declares a `facility.site_id` equal to the site's `site_id`.

A site missing a required field is an error, not a site to skip. Silently dropping a plant from the registry would leave every cross-plant answer quietly incomplete.

## Site Identity

`site_id` is the one identifier that names a plant everywhere. It is declared once, in `facility.site_id` in the plant's topology.yaml (Part II), and carried end to end:

- **Registry.** enterprise.yaml repeats it, and validation checks that the two agree.

- **Audit records.** Each plant stamps its own records with its own `site_id`: session summaries, incident records and action events. A record's `site_id` names the plant that produced it, never the plant that asked about it.

- **Federated results.** Every record a federated read returns keeps the `site_id` its plant stamped on it.

- **Enterprise answers.** The cross-plant orchestrator attributes every finding to the `site_id` it came from.

A `site_id` never changes once a plant has records. Renaming a plant changes its `name`. Changing its `site_id` would orphan its history.

## Federated Read

A federated read answers a question about plant history across many plants, such as diagnostic sessions in a time range or incidents on one equipment type, by asking every plant and merging the answers.

1. **Select.** The request names one `site_id`, or none for every registered site. An unknown `site_id` is an error that lists the known sites.

2. **Fan out.** The request goes to every selected plant in parallel. Each plant answers from its own audit history, through the read-only history tool its audit server exposes on its aggregator.

3. **Merge.** The per-plant results are combined into one list sorted by timestamp, ascending. Each record keeps its `site_id`.

4. **Isolate failures.** A plant that fails, times out or has no `aggregator_url` does not fail the request. The others still answer. The result names every plant that did not answer, so a missing plant reads as *unknown*, never as *no history*.

Federated read reaches only a plant's audit history. Audit history describes what the plant's agents and operators did. It is not raw process data or a control path, and the read never touches a plant's protocol adapters, write tools or memory stores.

## The Cross-Plant Orchestrator

The cross-plant orchestrator answers enterprise questions in natural language. It is shaped like Cascade (Part III), with plants in place of specialists. It decides which plants a question concerns, asks each one, and synthesizes a single answer.

### What it can do

The orchestrator has exactly two tools, each scoped to one plant by `site_id`:

| Tool | Description |
|:---|:---|
| `get_plant_status` | The plant's last periodic status check: a status level, a short narrative and the time it was produced. Fast, because the plant computes it in the background. Can be stale. |
| `diagnose_plant` | Asks the plant's own agent stack a question through its `chat_ui_url` and returns that plant's synthesized summary verdict. Always current, but runs a live multi-agent diagnosis at the plant. |

The orchestrator uses `get_plant_status` for overview questions and `diagnose_plant` for drill-down. When it answers from `get_plant_status`, it says each status is the plant's last periodic check, with its time.

### What it must not do

- **Reach past a plant's agents.** The orchestrator holds no aggregator URL and no adapter or store credentials. This is structural, not a prompt instruction: its tools can do nothing but ask a plant a question.

- **Propose writes.** It cannot propose, approve or execute an action at any plant. If a plant's own Cascade proposes an action while answering a `diagnose_plant` request, the proposal is held at that plant, under that plant's trust mode, for that plant's operators. The orchestrator cannot answer it.

- **Guess.** It never states a plant's status without calling a tool for that plant. A plant that errors or times out is reported as *unknown*, never as normal.

### Synthesis

An answer that covers several plants leads with a summary verdict in the same form Cascade uses. Its status is the most severe status among the plants checked. Every finding in the answer names its `site_id`.

### Audit

The orchestrator's sessions are logged under the audit trail contract in Part III, like any Cascade session. Each `diagnose_plant` and `get_plant_status` call is a tool call record carrying the `site_id` it asked. The plant logs its own side of every `diagnose_plant` request in its own audit trail, as it would any other query.

## Implementation Status

> **IMPLEMENTATION STATUS**
>
> *fieldworks-core provides the plant-agnostic logic as of 1.4.0: `fieldworks.enterprise` loads and validates enterprise.yaml (`fieldworks validate-enterprise` runs every rule above) and runs federated reads, and `fieldworks.agents` holds the cross-plant orchestrator's contract (prompt, tool schemas, answer formatting). The orchestrator's agentic loop, its model client, the transport to each plant and the MCP servers are deployment code: fieldworks-core takes no model-provider dependency. The waterworks-ai reference application runs its enterprise layer on fieldworks-core across two concurrently running plants.*
