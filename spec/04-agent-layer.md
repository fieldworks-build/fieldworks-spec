# Part III - The Agent Layer

## Overview

The agent layer is where reasoning happens. It sits above the plant layer, receives queries from operators, reads from the protocol surface through the aggregator, and returns findings or executes actions. It never touches the protocol layer directly. It never bypasses the aggregator. It never acts without leaving a record.

The agent layer has five fixed agents. Their names are drawn from industrial vocabulary. That is not an accident. The names carry meaning that people who work in plants will recognize immediately.

- **Cascade** — orchestrates. The entry point for every query. Loads plant context, routes to Specialists, synthesizes findings.

- **Specialist** — diagnoses. One per process area, defined by topology. Knows its area in depth.

- **Historian** — provides time dimension. Consulted when trend context adds value to a diagnosis.

- **Deadband** — validates. Noise or signal? The gate between the diagnostic path and the action path.

- **Millwright** — executes. Write access only. Called when things need to change.

The agent layer has two paths. The diagnostic path runs on every query. The action path runs only when a validated finding warrants intervention. The audit trail runs on both, always, without exception.

## The Two Paths

### The diagnostic path

The diagnostic path is the path of understanding. It begins when Cascade receives a query and ends when Cascade returns a synthesized finding to the operator. Every query travels the diagnostic path. Most queries go no further.

- Cascade receives the query and loads plant context from topology.yaml.

- Cascade determines which process areas are relevant and dispatches the corresponding Specialists.

- Each Specialist reads current tag values through the aggregator and evaluates them against the equipment type definitions and fault mode descriptions in its process area.

- When trend context adds diagnostic value, Cascade dispatches the Historian to read historical data for the relevant tags.

- Cascade synthesizes the Specialist and Historian findings into a coherent response and returns it to the operator.

The diagnostic path is read-only. No tags are written. No state changes. The operator receives a finding and decides what to do with it.

### The action path

The action path is the path of intervention. It begins when a diagnostic finding warrants a control action and ends when the outcome of that action is confirmed and logged. Not every finding leads to the action path. Many findings are advisory. The action path is taken only when something needs to change.

- A diagnostic finding identifies a condition that warrants intervention.

- Deadband validates the finding. Is this noise or signal? Does the condition meet the threshold for action given its duration, trend direction, and confidence?

- If Deadband validates the finding as signal, and the action is destructive, operator approval is requested. Destructive actions include setpoint writes, alarm acknowledgements, mode changes, and any operation that cannot be trivially undone.

- The operator approves or denies. In supervised trust mode this step is always present. In assisted mode it is present for destructive actions. In autonomous mode it is bypassed within topology-defined limits, but the operator is notified.

- Millwright receives the approved action, executes it through the aggregator, confirms the outcome, and logs every step.

The action path always produces an audit record regardless of trust mode. An autonomous action that bypassed operator approval is logged as clearly as one that required it. The log is the accountability mechanism. It cannot be disabled.

## The Agents

### Cascade

Orchestrator. The entry point for every query.

Cascade is always in control, never in a hurry. It does not diagnose. It does not execute. It orchestrates — loading context, dispatching the agents that have the knowledge for the task, and synthesizing what they return into something an operator can use.

Cascade is the only agent the operator interacts with directly. Everything else happens behind it. When an operator asks a question, they are talking to Cascade. When they receive a finding, it came from Cascade. What Cascade synthesized to produce that finding is the agent layer at work.

What Cascade knows

- The full topology — every process area, every equipment type, every instance, every fault mode.

- Which Specialists exist and which process areas they are responsible for.

- The current trust mode and what it permits.

- The audit trail contract and its logging obligations.

Cascade does not know raw tag values. It does not read from the protocol surface directly. It knows the plant as a model and dispatches agents that know the plant as data.

What Cascade does

- Receives operator queries and determines scope — which process areas are relevant, which agents to dispatch.

- Loads plant context from topology.yaml and injects it into Specialist system prompts.

- Dispatches Specialists in parallel when a query spans multiple process areas.

- Dispatches the Historian when trend context would improve diagnostic quality.

- Synthesizes findings from multiple Specialists into a coherent, operator-facing response.

- Routes validated findings to the action path when Deadband determines intervention is warranted.

- Logs query receipt, dispatch decisions, and response synthesis to the audit trail.

What Cascade does not do

- Read tag values directly from the protocol surface.

- Execute write operations.

- Bypass Deadband on the action path.

- Make diagnostic judgments that belong to a Specialist.

- Return findings without logging them.

### Specialist

Diagnostician. One per process area, defined by topology.

Specialists are the diagnostic intelligence of the framework. Each one is responsible for a single process area. Each one is instantiated from the topology at startup, not hardcoded. Change the topology, change the Specialists. Add a process area, get a new Specialist.

A Specialist knows its process area the way a good field engineer knows their section of the plant. It knows the equipment, the normal operating ranges, the fault mode patterns, the tag bindings, and the confidence level of each binding. It reads current values and evaluates them against that knowledge.

What a Specialist knows

- The equipment instances in its process area — types, attributes, tag bindings, confidence, notes.

- The normal operating ranges for every instrumented attribute on every instance.

- The fault mode descriptions for every equipment type in its area.

- Which tag bindings are verified, inferred, or suspect.

- Which attributes are missing from which instances, and why.

This knowledge is injected into the Specialist system prompt at instantiation time by Cascade, built from topology.yaml. The Specialist does not query the topology at runtime. It receives its context fully formed.

What a Specialist does

- Reads current tag values through the aggregator for all bound tags in its process area.

- Evaluates current values against normal operating ranges.

- Reasons against fault mode descriptions to identify conditions that match known failure patterns.

- Qualifies findings based on binding confidence — verified findings are stated clearly, inferred findings are flagged, suspect bindings are noted.

- Notes missing attributes explicitly rather than silently excluding them from the diagnosis.

- Returns a structured finding to Cascade with condition assessment, supporting evidence, confidence level, and recommended action if warranted.

What a Specialist does not do

- Read tags outside its assigned process area.

- Call write operations.

- Access historical data directly. It requests historical context through Cascade, which dispatches the Historian.

- Make action decisions. It returns findings. Deadband and the action path handle what happens next.

Specialists are dynamic. The topology defines how many exist and what they know. The framework instantiates them at startup by calling `build_specialist_prompt()` for each process area defined in topology.yaml.

```python
def build_specialist_prompt(process_area, equipment_instances, equipment_types):
    # Load all instances belonging to this process area
    # For each instance, load type definition, attribute schema,
    # fault modes, tag bindings with confidence and notes
    # Build a system prompt that gives the Specialist complete
    # knowledge of its area without requiring runtime topology queries
    ...
```

The output is a system prompt that is the Specialist's complete operating context. A water treatment plant with three process areas produces three Specialists. A refinery with twelve process areas produces twelve. The framework code does not change.

### Historian

Time dimension specialist. Consulted on demand.

Most diagnostic questions are answered by current values. A pump running outside its normal pressure range is a finding right now. The Historian is not needed for that.

Some diagnostic questions require time. Is the vibration increasing or has it been elevated for weeks? Did the pressure drop suddenly or has it been drifting? Is this the first time this fault has appeared or a recurring pattern? The Historian answers those questions.

Cascade decides when to dispatch the Historian. Not every query warrants historical context. Dispatching it unnecessarily adds latency and cost. Cascade makes the call based on whether the query or the Specialist findings suggest that trend data would change the diagnosis.

```jsonc
// Session opens — Cascade receives the query
{"ts":"2026-06-02T16:03:49.728265+00:00","event":"session_start",
 "session_id":"fd01fb5e...","model":"multi/claude-sonnet-4-6",
 "user_message":"give me a health overview of the plant"}

// Three specialists fan out simultaneously — note near-identical timestamps
{"ts":"2026-06-02T16:03:51.678591+00:00","event":"tool_call",
 "tool":"mqtt__get_full_topic_tree","args":{},"specialist":"treatment"}
{"ts":"2026-06-02T16:03:51.708151+00:00","event":"tool_call",
 "tool":"mqtt__get_full_topic_tree","args":{},"specialist":"distribution"}
{"ts":"2026-06-02T16:03:51.727619+00:00","event":"tool_call",
 "tool":"mqtt__get_full_topic_tree","args":{},"specialist":"intake"}

// Results return as each specialist completes
{"ts":"2026-06-02T16:03:51.805003+00:00","event":"tool_result",
 "tool":"mqtt__get_full_topic_tree","result":"Plant\n  WTP...",
 "specialist":"distribution"}

// Historian dispatched for time dimension
{"ts":"2026-06-02T16:03:52.140873+00:00","event":"tool_call",
 "tool":"influxdb__query",
 "args":{"flux_query":"from(bucket: \"waterworks\")..."},
 "specialist":"historian"}

// Cascade synthesizes and returns — session closes
{"ts":"2026-06-02T16:04:30.735441+00:00","event":"response",
 "text":"# Plant Health Overview — Synthesized Diagnostic Report..."}
```

What the Historian knows

- The historian configuration from topology.yaml — default lookback window, maximum lookback, resolution, data source.

- Which tags are bound to which equipment instances and attributes.

- Normal operating ranges for the attributes it is asked to analyze.

What the Historian does

- Reads historical tag data through the aggregator using read_tag_history.

- Analyzes trend direction, rate of change, and duration of exceedance.

- Identifies recurring patterns — has this fault mode appeared before, how often, under what conditions.

- Provides time-stamped context that sharpens or qualifies Specialist findings.

- Returns a structured time dimension finding to Cascade for synthesis.

What the Historian does not do

- Diagnose independently. It provides time context to findings that originate from Specialists.

- Read current values. That is the Specialist's job.

- Initiate action path requests. It returns findings to Cascade.

> The Historian is a peer to the Specialists, not a subordinate. Cascade dispatches it with the same authority as a Specialist. The distinction is scope. Specialists own a process area in the present, the Historian owns the time dimension across all areas.

### Deadband

Validator. The gate between diagnosis and action.

Deadband is named for one of the most fundamental concepts in process control. A deadband is a range around a setpoint within which no corrective action is taken. Small deviations are ignored. Only deviations that exceed the band trigger a response. This prevents the control system from chasing noise.

The Deadband agent does exactly this for the action path. It receives a diagnostic finding and asks, is this noise or signal? A single reading outside normal range is not necessarily a problem. A sustained exceedance with a deteriorating trend and high-confidence instrumentation is. Deadband knows the difference.

What Deadband evaluates

- **Duration** — how long has the condition been present? A transient spike is different from a sustained deviation.

- **Trend direction** — is the condition stable, improving, or deteriorating? A deteriorating trend with sustained exceedance is more urgent than a stable one at the same level.

- **Confidence** — how reliable is the instrumentation supporting the finding? A finding based on verified bindings and good quality signals carries more weight than one built on inferred bindings or uncertain quality.

- **Fault mode match** — does the pattern match a known fault mode description, or is it anomalous without a recognized pattern? Known fault modes with established diagnostic heuristics are more actionable.

- **Severity** — what severity did the equipment type assign to this fault mode? Advisory, warning, and critical have different thresholds.

Deadband outcomes

- **Noise** — condition does not meet the threshold for action. Finding is returned to Cascade as advisory. Logged. No action path.

- **Signal** — condition meets the threshold. If the proposed action is non-destructive, it may proceed to Millwright per trust mode rules. If destructive, operator approval is requested first.

> Deadband does not decide what action to take. It decides whether the finding warrants action at all. The action itself is proposed by the Specialist finding and executed by Millwright. Deadband is the gate, not the planner.
Deadband has a destructive action threshold. Any operation that changes control system state in a way that cannot be trivially undone is destructive. The threshold is intentionally broad. When in doubt, require approval.

- Setpoint writes — any write to a control setpoint.

- Mode changes — automatic to manual, run to standby, and similar state transitions.

- Alarm acknowledgements — clearing an active alarm from the system.

- Permissive overrides — any action that bypasses an interlock or safety permissive.

- Inhibits — suppressing an alarm or protection function.

Non-destructive operations such as reading values, generating reports or sending notifications, do not require approval regardless of trust mode.

### Millwright

Executor. Write access only. Called when things need to change.

A millwright is the tradesperson who installs, maintains, and repairs industrial machinery. They are the person who actually turns the wrench. In the agent layer, Millwright is the only agent that touches the control system. Everything else observes and reasons. Millwright acts.

Millwright is not called often. Most queries are diagnostic. Millwright is called when a validated finding has been approved for action and something in the plant needs to change. When it is called, it acts deliberately, confirms the outcome, and documents everything.

What Millwright knows

- The approved action — what tag, what value, what units, which operator approved it, what reason was given.

- The topology write permissions for the target tag — what the hard limits are, what ramping is configured.

- The current value of the target tag before the write.

- The audit trail contract — what it must log and when.

What Millwright does

- Reads the current value of the target tag before acting.

- Validates the proposed write value against topology hard limits. If the value exceeds the limit, the action is rejected regardless of who approved it.

- Executes the write through the aggregator using write_tag with operator_id and reason.

- Ramps to the target value when a ramping profile is configured, rather than stepping directly.

- Reads the tag value after the write to confirm the change took effect.

- Logs pre-write value, write action, post-write value, operator_id, reason, and outcome to the audit trail.

- Returns a structured execution report to Cascade.

What Millwright does not do

- Initiate actions. It receives approved actions from the action path. It does not decide on its own that something should change.

- Override topology hard limits. Not for any reason. Not at any trust mode. The limits are absolute.

- Execute without logging. Every Millwright action produces an audit record.

- Assume success. It always confirms the outcome by reading back the written value.

> Millwright's constraint is not a limitation of the framework. It is a design principle. The agent that executes is the most constrained agent in the system. Cascade has broad context. Specialists have deep knowledge. Deadband has judgment. Millwright has one job. Execute what it has been given, within the limits it has been set, and document what happened.

## Trust Mode

Trust mode governs how much autonomy the agent layer operates with. It is a deployment configuration, not a runtime toggle. Changing trust mode is a deliberate decision made by the facility, not something that happens automatically or in response to a query.

There are three trust modes. They form a ladder. Each level extends the autonomy of the previous one in a specific, bounded way. What never changes at any level: topology hard limits, the audit trail, and the requirement that Deadband validates before any action path proceeds.

### Supervised

Every action path step requires operator approval. Deadband validates the finding and presents it to the operator with a proposed action. Nothing executes until a human says yes.

- Diagnostic path runs without approval.

- Every action path action requires explicit operator approval before execution.

- Millwright executes only on approved actions.

- Topology hard limits enforced.

- Full audit trail.

Supervised is the appropriate mode for initial deployment, unfamiliar facilities, and any situation where the cost of an incorrect autonomous action is high. It is also the right mode when operator trust in the system is still being established.

### Assisted

The system recommends. The operator decides. Advisory findings are surfaced automatically. Actions that Deadband validates as warranted are presented to the operator as recommendations with proposed actions and supporting evidence. The operator approves or denies.

- Diagnostic path runs without approval.

- Advisory findings are surfaced automatically without operator prompt.

- Destructive actions require operator approval.

- Non-destructive actions may execute automatically.

- Topology hard limits enforced.

- Full audit trail.

Assisted is the mode most facilities will operate in for most of their deployment lifetime. The system adds intelligence without removing the operator from control decisions. It surfaces things the operator might have missed and makes it easy to act on them.

### Autonomous

Within topology-defined limits, Millwright executes without per-action approval. The operator is notified after execution. The system acts; the operator reviews.

- Diagnostic path runs without approval.

- Advisory findings are surfaced automatically.

- Actions within topology write permissions and hard limits execute without per-action approval.

- Operator is notified of autonomous actions in real time.

- Topology hard limits enforced. Always. Without exception.

- Full audit trail. Autonomous actions are logged as clearly as supervised ones.

Autonomous mode is appropriate for well-characterized facilities with high-confidence topology models and a track record of reliable system behavior. It is not the default. It is earned through demonstrated performance in supervised and assisted modes.

> The trust mode ladder is explicitly modeled on the way experienced operators extend trust to new equipment or new personnel. You supervise first. You assist as confidence grows. You step back when the track record warrants it. The system earns autonomy. It is not granted by default.

### Trust mode configuration

Trust mode is set in the aggregator configuration at the deployment level.

```json
{
  "trust_mode": "assisted",
  "trust_mode_notes": "Elevated from supervised 2026-04-01 after 90-day
    supervised evaluation. Reviewed and approved by plant manager.",
  "servers": [ ... ]
}
```

| Field | Type | Required | Description |
|:---|:---|:---|:---|
| `trust_mode` | string | yes | One of: supervised, assisted, autonomous. |
| `trust_mode_notes` | string | no | Human-readable record of why this mode was set and when. Logged to audit trail on startup. |
| `autonomous_notify_channel` | string | no | Notification endpoint for autonomous action alerts. Required if trust_mode is autonomous. |

## The Audit Trail

The audit trail is not a feature. It is infrastructure. It is as foundational to FieldWorks as the protocol layer. A deployment without a functioning audit trail is not a FieldWorks deployment.

Every session is logged from first query to final response. Every tool call and it result is logged. Every agent dispatch is attributed. Every operator approval or denial is logged. Every Millwright execution is logged. Every trust mode configuration is logged on startup. The log is append-only. It cannot be edited. It cannot be cleared by any agent.

### The audit-mcp server

The audit trail is implemented by the audit-mcp server, a required component of every FieldWorks deployment. It exposes a write-only logging interface to the agent layer and a read interface for compliance review and operator inspection.

The audit-mcp server is not optional. The agent layer will not operate without it. Cascade verifies audit-mcp availability at startup and refuses to proceed if it is unreachable.

- Append-only. No agent can modify or delete existing log entries.

- Structured JSONL. One record per line, one file per deployment. Human-readable and machine-parseable.

- Timestamped. Every entry carries a UTC timestamp with millisecond precision.

- Attributed. Every entry carries the agent that produced it and, where applicable, the operator identity.

- Durable. The audit-mcp server persists logs to disk. In-memory-only deployments are not conformant.

### Audit record schema

Every record in the audit log is a JSON object on a single line. The schema has two tiers. Fields that every conformant FieldWorks deployment produces today and fields that are planned additions as the framework matures. As the action path is implemented and the agent layer formalizes, the planned fields become standard fields and the distinction disappears.

Current fields produced by every conformant deployment.

| Field | Type | Required | Description |
|:---|:---|:---|:---|
| `ts` | string | yes | ISO 8601 UTC timestamp with microsecond precision. e.g. 2026-06-02T16:03:49.728265+00:00 |
| `event` | string | yes | Event type. One of session_start, tool_call, tool_result, response, incident. See event types below |
| `session_id` | string | yes | UUID. Groups all records from a single query session. Set at session_start and propagated to all records in the session. |
| `specialist` | string | no | The specialist agent that produced this record. One of historian, cascade, deadband, millwright or any process area id defined in topology.yaml. Present on tool_call and tool_result records in multi-agent deployments |
| `model` | string | no | Model identifier. Present on session_start. Format: mode/model-name, e.g. multi/claude-sonnet-4-6 |

Planned fields added as the framework matures.

| Field | Type | Required | Description |
|:---|:---|:---|:---|
| `event_id` | string | yes | UUID. Unique identifier for this audit record. |
| `process_area_id` | string | no | Relevant process area, if applicable. |
| `equipment_instance_id` | string | no | Relevant equipment instance, if applicable. |
| `operator_id` | string | no | Operator identity, present for approval events and write executions. |
| `trust_mode` | string | yes | Trust mode active at the time of this event. |

> The two tiers will merge as the framework develops. A deployment running only the diagnostic path today produces the current fields. When the action path is built, trust_mode and operator_id become standard fields on the relevant records. Existing log consumers will not break. The schema is additive.

### Event types

**session_start**

Logged once per session when Cascade receives an operator query. Contains the full user message and model identifier.

```json
{
  "ts": "2026-06-02T16:03:49.728265+00:00",
  "event": "session_start",
  "session_id": "fd01fb5e-67b1-4528-83bc-ceea3857ac4f",
  "model": "multi/claude-sonnet-4-6",
  "user_message": "give me a health overview of the plant"
}
```

**tool_call**

Logged each time a specialist calls a tool through the aggregator. In multi-agent mode, multiple tool_call records with different specialist value may share the same timestamp. This indicates parallel fan-out across specialists.

```json
{
  "ts": "2026-06-02T16:03:51.678591+00:00",
  "event": "tool_call",
  "session_id": "fd01fb5e-67b1-4528-83bc-ceea3857ac4f",
  "tool": "mqtt__get_full_topic_tree",
  "args": {},
  "specialist": "treatment"
}
```

> Parallel tool_call records with nearly identical timestamps and different specialist values are the audit trail signature of multi-agent fan-out. Three specialists dispatched simultaneously produce three tool_call records within milliseconds of each other.
**tool_result**

Logged when a tool call returns. Paired with the preceding tool_call by session_id and tool name. Contains the full result payload returned by the protocol adapter or historian.

```json
{
  "ts": "2026-06-02T16:03:51.805003+00:00",
  "event": "tool_result",
  "session_id": "fd01fb5e-67b1-4528-83bc-ceea3857ac4f",
  "tool": "mqtt__get_full_topic_tree",
  "result": "Plant\n  WTP\n    Pump\n      ...",
  "specialist": "distribution"
}
```

**response**

Logged once per session when Cascade returns the synthesized response to the operator. Contains the full response text. This is the closing record of a session’s diagnostic path.

```json
{
  "ts": "2026-06-02T16:04:30.735441+00:00",
  "event": "response",
  "session_id": "fd01fb5e-67b1-4528-83bc-ceea3857ac4f",
  "text": "# Plant Health Overview..."
}
```

### The incident record

In addition to the session log, FieldWorks maintains a separate incident index. Each session that produces a finding of diagnostic significance generates an incident record. The incident record is a summary artifact. It provides a high-level index of what was found, on which equipment, at what confidence, without requiring a reader to pars the full session log.

| Field | Type | Required | Description |
|:---|:---|:---|:---|
| `session_id` | string | yes | References the full session log for this incident. |
| `ts` | string | yes | Timestamp of the session that produced this incident. |
| `user_question` | string | yes | The operator query that initiated the session. |
| `equipment` | string | no | Comma-separated list of equipment instance IDs implicated in the finding. Empty if no specific equipment was identified |
| `status` | string | yes | Diagnostic outcome. One of normal, anomaly detected, fault detected. |
| `confidence` | number | yes | Confidence score from 0.0 to 1.0. Relects the certainty of the finding given instrumentation quality and pattern match strength. |
| `mode` | string | yes | Agent mode that produced the finding. One of single, multi. |

```json
{
  "incidents": [
    {
      "session_id": "fd01fb5e-67b1-4528-83bc-ceea3857ac4f",
      "ts": "2026-06-02T16:03:49.728265+00:00",
      "user_question": "give me a health overview of the plant",
      "equipment": "Chlorine_01,UV_01,RawWater_02,HighService_02",
      "status": "Anomaly Detected",
      "confidence": 0.78,
      "mode": "multi"
    }
  ]
}
```

### Reading a multi-agent session

The following is an abbreviated audit log from a real multi-agent session against the waterworks-ai reference deployment. It illustrates how the parallel fan-out pattern appears in the log and how a session flows from query receipt through specialist dispatch to synthesized response.

The full session spans from 16:03:49 to 16:04:30. 41 seconds from query to synthesized response covering four specialists, multiple InfluxDB queries and cross-system correlation across 33 process data points.

### Relationship to the waterworks-ai reference implementation

The waterworks-ai reference implementation uses the audit format defined in this section. It is a single-file JSONL log appended to on every session event, with a companion incidents index updated on every session that produces a diagnostic finding.

The field names and structure defined here are the authoritative contract. The waterworks-ai implementation is conformant. Deployments building on FieldWorks should use the same format.

> A note on evolution: the current audit format captures the diagnostic path fully. The action path fields — operator_id, approval events, Millwright write confirmations — will be added as the action path is implemented in the framework. The schema is additive; existing log consumers will not break when new event types are added.

### Compliance and retention

The audit trail is the primary compliance artifact for FieldWorks deployments. It provides a complete record of what the AI observed, what it concluded, what it recommended, what the operator decided, and what was executed. This record satisfies audit requirements for process safety management, environmental compliance, and operational excellence programs.

Log files are append-only and must not be modified after writing.

Retention period is deployment-specific and should be defined in the facility's data governance policy. Minimum recommended retention is 90 days.

Log files should be backed up to a separate storage location on a schedule consistent with the facility's data protection requirements.

The incidents index provides a human-readable summary for compliance review without requiring access to the full session logs.

Session logs contain full tool results including raw process data. Access to session logs should be restricted to authorized personnel consistent with the facility's data access policy.

## The Propose/Approve/Execute Primitive

The Trust Mode section above defines what SUPERVISED mode requires. Every action path step requires operator approval and nothing executes until a human says yes. This section defines the framework-level primitive that makes that requirement enforceable rather than aspirational.

Prior to this primitive, the propose/approve/execute pattern existed only as an application-specific implementation inside the waterworks-ai reference application. A real, working pattern, but not a reusable contract any other deployment could build against. This section extracts that pattern into fieldworks-core.

> This is the same category of work as extracting SpecialistMemory and the other memory-layer types into the framework. The example and the primitive are being defined together, for the first time, in this release. Treat this section as a new contract, not a description of long-standing behavior.

### How it works

An agent that wants to change something in the physical process does not call a write tool directly. Instead, it proposes the type of action, the target, the proposed value and its rationale. The host application intercepts that proposal before it reaches the underlying MCP server, holds it in a pending state and presents it to the operator.

Nothing executes until the operator responds. An approval releases the proposal for execution. A denial closes it. Either way, the decision is recorded with the same fidelity. A denial is not a lesser event than an approval. It is the operator's judgment being exercised exactly as the architecture intends and the audit trail treats it accordingly.

The agent proposes. It never writes directly to the protocol layer.

The host application owns how the proposal reaches the operator either with a UI dialog, a notification or a polling endpoint. The framework does not prescribe transport.

An approval and a denial are recorded as equally complete, equally detailed events.

Every proposal, and every decision made on it, is logged to the audit trail with the same rigor described above.

### What the framework provides, what the host provides

The framework owns the shape of a proposal, the mechanism for holding it pending and the audit record it produces. The host application owns transport, how the proposal tool is named alongside its other tools and how the agent loop calls into the mechanism.

**Framework provides**: the proposal data shape, the pending-decision registry, the hash-chained audit log and the canonical tool definition a host can use rather than hand-rolling its own.

**Host provides**: the transport that carries a decision from operator to system, the namespacing of the proposal tool alongside the host's other tools and the wiring into its own agent loop.

This division mirrors the one in Part I between the protocol layer and the agent layer. The framework defines the contract. The deployment defines the plumbing around it.

### The audit record

Two records are kept, for two different purposes.

The compliance record is a hash-chained, append-only log, optionally encrypted, that can be verified for tampering by replaying the chain. This is the record that would be produced in response to a 21 CFR Part 11, FSMA or process safety management audit request. It is not a dashboard or a reporting tool. Its only job is to be a trustworthy, tamper-evident account of what was proposed and what was decided.

The operational record is a queryable log, kept separately, meant for day-to-day reporting and review. What got proposed this week, how often the operator approved versus denied, which equipment generates the most proposals. It is not the compliance record of truth. Conflating the two undersells the rigor the first one is built for and overstates the rigor the second one needs.

### Scope boundary

This mechanism covers SUPERVISED mode only. Every write is confirmed by an operator before execution. It does not yet implement dispatch logic for the other rungs of the trust mode ladder:

**ADVISORY** — the system recommends. It never proposes a write for approval at all.

**COLLABORATIVE** — writes within a pre-approved normal range execute without confirmation. Writes outside that range still require it.

**AUTONOMOUS** — the proposal step is skipped entirely and the write is logged with the same fidelity as a supervised one.

> **IMPLEMENTATION STATUS**
>
> *SUPERVISED mode is implemented in fieldworks-core as of this release. ADVISORY, COLLABORATIVE, and AUTONOMOUS mode-dispatch logic is not yet implemented anywhere in the framework or in the waterworks-ai reference application. This is a documented gap in the current release, not a claim that the full trust mode ladder is realized end to end.*
