# Part II - The Plant Layer

## Overview

The plant layer is where FieldWorks learns the facility. Protocol adapters give the framework access to data. The plant layer gives that data meaning.

Two configuration files define the plant layer. Together they tell the framework what the facility is, how it is structured, what normal looks like, what failure looks like and how the protocol surface maps onto the physical world.

- `topology.yaml` describes the facility. Its process areas, the types of equipment deployed, the specific instances of that equipment, the tag IDs that represent each attribute, normal operating ranges and fault mode descriptions. This is the plant model.

- `aggregator.json` describes the deployment. Which protocol servers are available, which tools each server exposes and how each server is scoped to a section of the protocol surface. This is the connection model.

Part II is written for plant deployers. OT engineering teams configuring FieldWorks against a real facility. It assumes you have conformant protocol adapters in place. If you are building an adapter, read Part I first.

The reference scenario throughout this part is waterworks-ai, a water treatment plant deployment available as the FieldWorks reference implementation.

## Two Files, One Deployment

The separation between topology.yaml and aggregator.json is deliberate. They answer different questions.

**topology.yaml** answers, what is this plant? It describes physical reality. A centrifugal pump is a centrifugal pump regardless of whether it reports via MQTT or OPC-UA. The equipment type, its attributes, its normal operating ranges and its failure modes are properties of the physical equipment, not the protocol it happens to speak. topology.yaml captures that physical knowledge.

**aggregator.json** answers, how do we connect to it? It describes the protocol surface and how that surface is presented to the agent layer. The same MQTT broker might be split into multiple logical server instances, each scoped to a different section of the topic tree. The aggregator config is where those deployment decisions live.

Keeping them separate means you can change the connection topology without touching the plant model and vice versa. You can also reuse equipment type definitions across facilities with different protocol configurations.

### topology.yaml

topology.yaml is a single YAML file that fully describes the facility being monitored. It has five top-level sections.

```yaml
facility:
  # Facility metadata

process_areas:
  # Named zones mapping to Specialist agents

equipment_types:
  # Class definitions for equipment categories

equipment_instances:
  # Deployed equipment with tag ID bindings

historian:
  # Time dimension configuration
```

#### `facility`

Top-level metadata about the facility. Used by Cascade to provide context in responses and by the audit trail for log attribution.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `name` | string | yes | Human-readable facility name. Appears in agent responses and audit log headers. |
| `site_id` | string | yes | Unique identifier for this site. Stamped on the plant's audit records, and the key that names the plant in multi-plant deployments (Part V). Never changes once the plant has records. |
| `description` | string | no | Brief description of the facility type and function. Provides Cascade with context for response framing. |
| `timezone` | string | yes | IANA timezone string. e.g. America/New_York. Used for local time display in operator-facing responses. |
| units_system | string | no | Preferred units system: metric or imperial. Default: metric. Individual attributes override this. |

```yaml
facility:
  name: Riverside Water Treatment Plant
  site_id: wtp-riverside-01
  description: Municipal water treatment facility, 45 MGD capacity
  timezone: America/Chicago
  units_system: metric
```

#### `process_areas`

Process areas divide the facility into named zones. Each process area maps directly to a Specialist agent. When Cascade receives a query, it determines which process areas are relevant and dispatches the corresponding Specialists.

Process area names should reflect how operators naturally refer to sections of the plant. They appear in agent responses and in the audit trail.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `id` | string | yes | Unique identifier for this process area. Referenced by equipment instances. |
| `name` | string | yes | Human-readable name. Used in operator-facing responses. |
| `description` | string | yes | What this area does. Provides the Specialist with context for its diagnostic role. |
| `specialist_prompt` | string | no | Additional context injected into the Specialist system prompt for this area. Use for facility-specific knowledge the Specialist should always have. |

```yaml
process_areas:
  - id: intake
    name: Raw Water Intake
    description: Screens and pumps raw water from the source into the
      treatment process. Primary equipment is raw water pumps and intake screens.
    specialist_prompt: This plant draws from a river source with seasonal
      turbidity variation. High turbidity events are common in spring.

  - id: treatment
    name: Treatment
    description: Coagulation, flocculation, sedimentation, and filtration.
      Includes chemical dosing systems for coagulant and pH adjustment.

  - id: distribution
    name: Treated Water Distribution
    description: Pumping of treated water to the distribution network.
      Includes high-service pumps and clear well level management.
```

#### `equipment_types`

Equipment types are class definitions. They define the attribute schema, normal operating ranges and fault mode descriptions that apply to every instance of that equipment category. This is the object-oriented foundation of the topology model.

A real plant may have dozens of centrifugal pumps, each with identical attribute schemas and similar fault modes. Define the type once. Instances reference it and bind their specific tag IDs to the attribute names.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `id` | string | yes | Unique identifier for this equipment type. Referenced by instances. |
| `name` | string | yes | Human-readable type name. e.g. Centrifugal Pump, UV Disinfection Bank. |
| `description` | string | yes | What this type of equipment does in the process. Provides Specialists with equipment context. |
| `attributes` | list | yes | List of attribute definitions. See Attributes below. |
| `fault_modes` | list | yes | List of fault mode descriptions. See Fault Modes below. |

```yaml
equipment_types:
  - id: centrifugal_pump
    name: Centrifugal Pump
    description: Moves water through the process via impeller rotation.
      Primary equipment in intake and distribution areas.
    attributes:
      - id: discharge_pressure
        name: Discharge Pressure
        units: bar
        normal_range:
          min: 2.8
          max: 4.2
          description: Varies with system demand. Lower end during low-demand periods.
      - id: motor_current
        name: Motor Current
        units: A
        normal_range:
          min: 18.0
          max: 32.0
      - id: vibration
        name: Vibration
        units: mm/s
        normal_range:
          min: 0.0
          max: 4.5
      - id: bearing_temp
        name: Bearing Temperature
        units: degC
        normal_range:
          min: 20.0
          max: 75.0
      - id: run_status
        name: Run Status
        units: ""
        normal_range:
          min: 0
          max: 1
      - id: speed_setpoint
        name: Speed Setpoint
        description: VFD speed setpoint as percentage of rated speed.
        units: "%"
        normal_range:
          min: 40.0
          max: 100.0
        writable: true
```

```yaml
   fault_modes:
      - id: bearing_wear
        name: Bearing Wear
        severity: warning
        affected_attributes: [vibration, bearing_temp, motor_current]
        description: Bearing wear presents as a gradual increase in vibration
          over hours to days, typically starting on one axis before spreading.
          Bearing temperature rises as friction increases. Motor current may
          increase slightly as mechanical resistance grows. Early stage is
          often detectable only in trend data. Advanced bearing wear can
          progress to failure rapidly. Common causes are inadequate lubrication,
          contamination, or end-of-service-life.
      - id: cavitation
        name: Cavitation
        severity: warning
        affected_attributes: [discharge_pressure, vibration, motor_current]
        description: Cavitation presents as erratic discharge pressure with
          high-frequency vibration. Characteristically noisy in the field.
          Motor current becomes unstable. Sustained cavitation causes rapid
          impeller damage. Common causes are insufficient suction head, high
          flow demand exceeding pump curve, or air entrainment in suction.
      - id: seal_failure
        name: Seal Failure
        severity: critical
        affected_attributes: [discharge_pressure, motor_current]
        description: Seal failure presents as a sudden drop in discharge
          pressure accompanied by a drop in motor current as the pump loses
          prime. In wet well installations this is accompanied by visible
          leakage. Requires immediate shutdown. Do not restart without
          seal inspection and replacement.
```

#### `Attributes`

Attributes are the measurable properties of an equipment type. Each attribute defines what is being measured, its engineering units, and its normal operating range. Instances bind tag IDs to these attribute names.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `id` | string | yes | Attribute identifier. Referenced in equipment instances to bind tag IDs. |
| `name` | string | yes | Human-readable attribute name. e.g. Discharge Pressure, Motor Current. |
| `description` | string | no | What this attribute measures and why it matters diagnostically. |
| `units` | string | yes | Engineering units. e.g. bar, degC, A, m3/h, NTU, mg/L. |
| `normal_range.min` | number | yes | Lower bound of normal operating range. |
| `normal_range.max` | number | yes | Upper bound of normal operating range. |
| `normal_range.description` | string | no | Narrative context for the normal range. Useful for ranges that vary by operating mode. |
| `writable` | boolean | no | Whether this attribute accepts writes via write_tag. Default false. Write permissions are enforced at the aggregator layer. |

#### `Fault Modes`

Fault modes describe failure patterns the Specialist should recognize. They are natural language descriptions, not structured rules. The Specialist reasons against them using its understanding of the equipment, the current tag values and the historical trend.

Write fault mode descriptions the way an experienced maintenance technician would brief a new engineer. Include what to look for, what other symptoms typically accompany it and what the likely cause is. The richer the description, the more useful the Specialist.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `id` | string | yes | Unique identifier for this fault mode within the equipment type. |
| `name` | string | yes | Short name for this fault mode. e.g. Bearing Wear, Cavitation, Seal Failure. |
| `description` | string | yes | Natural language description of how this fault presents, what attributes are affected, typical progression, and likely causes. No length limit. |
| `severity` | string | yes | One of: advisory, warning, critical. Guides Deadband threshold and escalation behavior. |
| `affected_attributes` | list | yes | List of attribute IDs that are diagnostic indicators for this fault mode. |

#### `equipment_instances`

Equipment instances are the deployed equipment in the facility. Each instance references an equipment type and binds the type's attribute IDs to specific tag IDs on the protocol surface. This is where the abstract type model connects to the real plant.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `id` | string | yes | Unique identifier for this equipment instance. Referenced in operator queries and the audit trail. |
| `name` | string | yes | Human-readable instance name. e.g. Raw Water Pump 1. |
| `type_id` | string | yes | References an equipment type defined in equipment_types. |
| `process_area_id` | string | yes | References a process area defined in process_areas. Determines which Specialist is responsible. |
| `description` | string | no | Instance-specific notes. Use for information that differs from the type default, such as a different service history or known condition. |
| `tag_bindings` | map | yes | Maps attribute IDs from the equipment type to tag IDs on the protocol surface. Every attribute defined on the type must have a binding. |
| `commissioned` | string | no | ISO 8601 date the equipment was commissioned. Used by the Historian for long-term trend context. |
| `notes` | string | no | Free-form operational notes. Visible to Specialists. Use for known conditions, recent maintenance, or anything that context that affects diagnosis. |

```yaml
equipment_instances:
  - id: raw_water_pump_1
    name: Raw Water Pump 1
    type_id: centrifugal_pump
    process_area_id: intake
    commissioned: "2019-03-15"
    notes: Replaced impeller 2024-11-02 following cavitation damage.
      Running well since. Monitor suction conditions during high-demand periods.
    tag_bindings:
      discharge_pressure: Plant/WTP/Pump/RawWater_P01/DischargePressure
      motor_current:      Plant/WTP/Pump/RawWater_P01/MotorCurrent
      vibration:          Plant/WTP/Pump/RawWater_P01/Vibration
      bearing_temp:       Plant/WTP/Pump/RawWater_P01/BearingTemp
      run_status:         Plant/WTP/Pump/RawWater_P01/RunStatus
      speed_setpoint:     Plant/WTP/Pump/RawWater_P01/SpeedSetpoint

  - id: raw_water_pump_2
    name: Raw Water Pump 2
    type_id: centrifugal_pump
    process_area_id: intake
    commissioned: "2021-07-08"
    tag_bindings:
      discharge_pressure: Plant/WTP/Pump/RawWater_P02/DischargePressure
      motor_current:      Plant/WTP/Pump/RawWater_P02/MotorCurrent
      vibration:          Plant/WTP/Pump/RawWater_P02/Vibration
      bearing_temp:       Plant/WTP/Pump/RawWater_P02/BearingTemp
      run_status:         Plant/WTP/Pump/RawWater_P02/RunStatus
      speed_setpoint:     Plant/WTP/Pump/RawWater_P02/SpeedSetpoint
```

> Both pumps reference the centrifugal_pump type. The type is defined once. The instances differ only in their tag bindings, commissioned date, and notes. Adding a third pump requires only a new instance entry.

#### `historian`

The historian section configures the time dimension available to the Historian agent. It defines the default look-back window for trend queries and any historian-specific connection details if the time series source is separate from the real-time protocol surface.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| default_lookback_hours | integer | yes | Default time window for trend queries when no explicit window is specified. Recommended: 24. |
| max_lookback_days | integer | yes | Maximum historical window the Historian will query. Prevents unbounded history requests. |
| resolution_seconds | integer | no | Preferred data resolution for history queries in seconds. Default: adapter-native resolution. |
| source | string | no | If historical data comes from a dedicated historian rather than the real-time adapter, specify the aggregator server name here. Default: same adapter as real-time data. |

```yaml
historian:
  default_lookback_hours: 24
  max_lookback_days: 90
  resolution_seconds: 60
```

### aggregator.json

The aggregator configuration defines the protocol surface available to the agent layer. It is a JSON array of server definitions, where each entry represents one logical protocol server instance.

A logical server instance is not necessarily a separate physical server. The same protocol server can appear multiple times in the aggregator config, each time scoped differently. This is how a single MQTT broker serving an entire facility is divided into process-area-specific surfaces for the agent layer.

Server definition schema

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `name` | string | yes | Logical name for this server instance. Referenced in topology tag bindings and in agent tool calls. |
| `url` | string | yes | MCP server endpoint URL. SSE endpoint for streaming servers. |
| `include_tools` | list | no | List of tool names to expose from this server. Tools not listed are not available to agents. Omit to expose all tools. |
| `default_args` | object | no | Default parameter values applied to every tool call on this server. Used to scope servers to a section of the protocol surface without modifying the adapter. |
| `timeout_ms` | integer | no | Tool call timeout for this server in milliseconds. Default: 5000. |
| `description` | string | no | Human-readable description of what this logical server represents. Appears in get_server_info responses. |

```json
[
  {
    "name": "mqtt_intake",
    "url": "http://localhost:8001/sse",
    "include_tools": ["read_tag", "read_tag_history", "discover_tags"],
    "default_args": {
      "topic_filter": "Plant/WTP/Pump/RawWater_*"
    },
    "description": "Raw water intake pump data"
  },
  {
    "name": "mqtt_treatment",
    "url": "http://localhost:8001/sse",
    "include_tools": ["read_tag", "read_tag_history", "discover_tags"],
    "default_args": {
      "topic_filter": "Plant/WTP/Treatment/*"
    },
    "description": "Treatment process data"
  },
  {
    "name": "mqtt_distribution",
    "url": "http://localhost:8001/sse",
    "include_tools": ["read_tag", "read_tag_history", "discover_tags", "write_tag"],
    "default_args": {
      "topic_filter": "Plant/WTP/Pump/Treated_*"
    },
    "description": "Treated water distribution pumps. Write access enabled."
  }
]
```

> write_tag appears only in mqtt_distribution. Intake and treatment servers expose read and discovery tools only. The include_tools list is the primary write access control mechanism at the deployment layer. This is separate from topology writable flags, which define what is physically writable. Both must permit a write for it to succeed.

## The Topology Builder

Hand-authoring topology.yaml for a real facility is not a practical workflow. The smallest industrial plant has thousands of tags. A facility built over 20 years by multiple contractors may have tens of thousands. The FieldWorks topology builder is the onboarding tool that makes FieldWorks deployable against a real plant without hand-authoring anything.

The topology builder is an AI-assisted discovery tool that runs through the chat interface. It scans the configured protocol surfaces, infers equipment types and process areas from what it finds and builds the plant topology through a guided conversation with the deployer. The output is a review artifact, a draft topology.yaml, and a committed knowledge graph in LadybugDB.

It is a framework component. It is designed to be protocol-agnostic and plant-type-agnostic. The same tool that onboards a water treatment plant onboards a refinery, a brewery or a power station.

### How it works

The deployer starts the topology builder from the normal chat interface with a natural language instruction.

```text
Browse this broker and build my plant model
```

The interface shifts into topology builder mode. The diagnostic UI slides out. The topology builder expands to fill the screen. A chat panel on the left, a node visualization panel on the right. The plant materializes in the visualization as discovery progresses.

The builder works through four stages.

**Stage 1 — Template selection**

Before discovery begins, the builder presents a template library. Templates are pre-built plant type definitions that provide process area structure, expected equipment types, and fault mode libraries for known facility categories. Selecting a template gives the builder a scaffold to map discovered equipment into.

Templates are optional. The deployer can skip template selection and start discovery from scratch. In that case the builder infers process area structure from equipment type groupings and asks the deployer to confirm the process flow.

Official templates are maintained by the FieldWorks project. Community templates are contributed by SIs and operators who have deployed against specific plant types and want to share the starting point. Both are available in the template library.

> The template library is a community artifact. An SI who builds a high-quality water treatment template and contributes it back is giving every subsequent water treatment deployment a faster, better start. Over time the template library becomes a repository of industrial domain knowledge — plant structures, equipment types, and fault mode descriptions written by people who have actually maintained that equipment.
**Stage 2 — Discovery**

The builder connects to the configured protocol adapters through the aggregator and walks the available protocol surfaces. For MQTT it calls `get_full_topic_tree` to retrieve the full topic hierarchy. For OPC-UA it calls `get_node_tree` to traverse the address space. For multi-protocol deployments it scans all configured adapters and cross-references findings.

As topics and nodes are discovered, the builder infers equipment instances using naming pattern analysis. A cluster of topics under Plant/WTP/Pump/RawWater_01/ — Flow, Pressure, Running, Power — is recognized as a centrifugal pump instance named RawWater_01. The inference is probabilistic. Each inferred binding is assigned a confidence score.

During discovery, nodes appear in the visualization panel as they are found, organized into process area columns. The deployer watches the plant model materialize in real time. The confidence-based node sizing makes the uncertain inferences immediately visible. Fully confident nodes render at full size, inferred nodes smaller, suspect nodes smaller still.

```text
// Example discovery output — chat panel
MQTT scan complete. 38 topics discovered.
10 equipment instances found across 3 process areas.
All instances verified at 95% confidence.
Dual-sourced against OPC-UA for cross-validation.
```

**Stage 3 — Review and correction**

When discovery is complete the builder summarizes what it found and flags items that need deployer input. Flagged items appear as amber or red nodes in the visualization. The deployer resolves them through natural language in the chat panel.

```text
// Flagged item example
Plant/WTP/OldBroker/P-Legacy is publishing but doesn't match
any recognized equipment pattern. Is this active equipment
or a decommissioned tag?

// Deployer response
P-Legacy is decommissioned, ignore it

// Builder response
Got it. P-Legacy removed from the model.
```

The deployer can also correct classifications, add notes to specific instances, adjust process area assignments and enrich fault mode descriptions with facility-specific knowledge. The builder updates the model in real time and reflects changes immediately in the visualization.

The visualization panel supports filtering by process area. Clicking a column header isolates that area's nodes. At scale, with hundreds of equipment instances across many process areas, this makes the review manageable. The deployer works through one area at a time rather than trying to review the full plant simultaneously.

The status bar at the bottom of the visualization shows the current model state at all times. Instance count, verified count, inferred count, suspect count, flagged items. The deployer knows exactly where they stand before committing.

**Stage 4 — Review artifact and commit**

When the deployer is satisfied with the model, the builder generates a topology.yaml as a review artifact. The YAML appears in the chat panel as a complete, human-readable representation of the inferred topology. The deployer can inspect it, copy it for version control or request changes before committing.

Nothing is written to LadybugDB until the deployer explicitly commits. The commit is a deliberate action. A button in the visualization panel and a confirmation prompt in the chat. This is the same operator-in-the-loop principle that governs the action path in the diagnostic system. The AI proposes. The human decides.

On commit, the builder writes the full topology to LadybugDB using the schema defined in Part IV. The knowledge graph is seeded with the static layer. Facility, process areas, equipment types, instances, attributes, tag bindings and fault modes. The dynamic layer begins accumulating on the first diagnostic session.

The interface returns to the diagnostic UI. The fault status panel in the right sidebar is now populated from the committed topology. The specialist agents have plant context on their first query.

### Legacy mode

Real industrial plants are not clean. The waterworks-ai reference implementation includes a clean simulator that produces consistent, well-structured MQTT topics. Real plants built over 20 years by multiple contractors produce something very different.

Legacy mode is a simulator configuration that intentionally produces the kind of protocol surface the topology builder will encounter in real deployments. It is used to test and demonstrate the builder's inference capabilities under realistic conditions.

Inconsistent naming conventions across contractor eras. The same equipment type named three different ways in different sections of the plant.

Dead tags still publishing stale values from decommissioned equipment.

Duplicate signals from different integration projects publishing at different sample rates.

Engineering units in inconsistent conventions. PSI in one area, bar in another, kPa in a third.

Tags with no units at all.

Equipment that was renamed but the old tags were never removed.

A process area that no longer exists but still has active tags.

Quality signals set to good on everything regardless of actual sensor state.

The topology builder's handling of legacy mode is the honest test of whether it works against real plants. A builder that only works against clean, well-structured tag trees is a demo tool. A builder that produces a useful topology from a messy, inconsistent protocol surface is a deployment tool.

> Legacy mode is the honest test. Clean plants make the topology builder look easy. A plant with three naming conventions, decommissioned tags still publishing, and units in three different standards — that is what the builder has to handle in a real SI engagement.

### Framework separation

The topology builder is designed as a framework component from the start. It is not a waterworks-specific feature that will be extracted later. The separation is maintained through a clean interface boundary.

No plant-specific code in the builder. No hardcoded references to waterworks equipment types or topic structures.

Protocol agnostic. The builder communicates with the aggregator, not directly with MQTT or OPC-UA adapters. Swap the protocol, the builder does not change.

LadybugDB schema is the framework schema. The builder writes to the graph using the schema defined in Part IV. That schema belongs to the framework.

Templates are external files. Template definitions live in a `templates/` directory and conform to the template schema. Community templates are files that meet that schema. The builder loads them at startup.

The UI component is self-contained. The full UI shift, the visualization panel and the chat integration are a component that can be embedded in any FieldWorks deployment interface.

In the waterworks-ai reference implementation, the topology builder lives in a `fieldworks/topology_builder/` directory with a defined interface boundary. waterworks calls it. The framework owns it.

### What the builder enables

The topology builder changes the onboarding story for FieldWorks deployments. The deployment workflow becomes:

Connect the adapters to the protocol surface.

Select a template or start from scratch.

Type: browse this broker and build my plant model.

Review the discovered topology, correct the flags, commit.

Ask the first diagnostic question.

An SI familiar with the plant type and the FieldWorks framework can complete this workflow in an afternoon. An SI using a community template for a known plant type can complete it faster. The domain knowledge that would otherwise require weeks of manual topology authoring is contributed by the template and refined by the deployer's corrections.

That is the onboarding story that makes FieldWorks accessible at the scale of the SI channel. The topology builder is not a convenience feature. It is the mechanism that makes deployment practical.

## Validation

FieldWorks provides two validators. They serve different purposes and are run at different stages of deployment.

### Topology validator

The topology validator checks topology.yaml against the schema defined in this specification. It is a static validator that does not require a running protocol surface.

- All required fields are present at every level of the hierarchy.

- Equipment instance type_id references resolve to defined equipment types.

- Equipment instance process_area_id references resolve to defined process areas.

- Tag bindings in each instance cover all attributes defined on the referenced type.

- Normal range min is less than max for all attributes.

- Fault mode severity values are one of: advisory, warning, critical.

- Affected attributes in fault modes reference attribute IDs defined on the equipment type.

- Historian source, if specified, references a name defined in aggregator.json.

```shell
fieldworks validate topology.yaml
fieldworks validate topology.yaml --aggregator aggregator.json
```

> Pass --aggregator to also validate that all tag bindings reference tag IDs discoverable on the configured adapters. Requires running adapters. Omit for offline schema validation only.

### Adapter conformance suite

The adapter conformance suite validates that a protocol adapter meets the requirements of Part I. It is a behavioral test suite that runs against a live adapter instance.

- connect and disconnect complete without error.

- Every required tool declares the tool annotations Part I requires.

- discover_tags returns well-formed tag descriptors with all required fields.

- read_tag returns a valid VQT envelope for a known tag.

- read_tag returns a structured TAG_NOT_FOUND error for an unknown tag, or TIMEOUT when the protocol cannot determine that a tag does not exist (Part I, Error Handling).

- read_tag_history returns ordered VQT envelopes under `values`, or HISTORY_UNAVAILABLE when the protocol has no history.

- write_tag returns TAG_NOT_WRITABLE for a tag not in write permissions.

- write_tag returns INVALID_VALUE for a value outside the configured engineering range.

- get_server_info returns all required fields including a complete capabilities list.

- browse or scan returns a non-empty result for a configured protocol surface.

- get_topic_tree or get_node_tree returns a structured hierarchy.

```shell
fieldworks test-adapter --command "mqtt-mcp" --host localhost --port 1883
fieldworks test-adapter --command "opcua-mcp" --host 127.0.0.1 --port 4840
```

The suite starts the adapter binary as an MCP stdio subprocess. Without `--host`, it runs only the checks that need no live connection: tool discovery, tool annotations, and get_server_info.

> The conformance suite requires a running adapter with at least one readable tag. For write tests, at least one writable tag must be configured. The suite does not perform actual writes to the control layer; write tests validate error handling and permission enforcement only.

## Complete Worked Example

The following is the complete plant layer configuration for the waterworks-ai reference deployment. A municipal water treatment plant with three process areas, four equipment types, and twelve equipment instances.

This is the configuration that makes waterworks-ai buildable. With this topology.yaml, the aggregator.json above, and conformant MQTT and OPC-UA adapters, the full agent layer can be brought up and will have complete plant context from first query.

> The complete waterworks-ai topology.yaml is available in the FieldWorks GitHub organization. The version here is abbreviated to illustrate structure. The repository version is the authoritative reference.

```yaml
facility:
  name: Riverside Water Treatment Plant
  site_id: wtp-riverside-01
  description: Municipal water treatment, 45 MGD capacity
  timezone: America/Chicago
  units_system: metric

process_areas:
  - id: intake
    name: Raw Water Intake
    description: Raw water pumping from source to treatment.
  - id: treatment
    name: Treatment
    description: Coagulation, filtration, disinfection.
  - id: distribution
    name: Distribution
    description: Treated water pumping to network.

equipment_types:
  - id: centrifugal_pump
    name: Centrifugal Pump
    description: Water movement via impeller rotation.
    attributes:
      - id: discharge_pressure
        name: Discharge Pressure
        units: bar
        normal_range: { min: 2.8, max: 4.2 }
```

```yaml
      - id: motor_current
        name: Motor Current
        units: A
        normal_range: { min: 18.0, max: 32.0 }
      - id: vibration
        name: Vibration
        units: mm/s
        normal_range: { min: 0.0, max: 4.5 }
      - id: bearing_temp
        name: Bearing Temperature
        units: degC
        normal_range: { min: 20.0, max: 75.0 }
      - id: run_status
        name: Run Status
        units: ""
        normal_range: { min: 0, max: 1 }
      - id: speed_setpoint
        name: Speed Setpoint
        units: "%"
        normal_range: { min: 40.0, max: 100.0 }
        writable: true
    fault_modes:
      - id: bearing_wear
        name: Bearing Wear
        severity: warning
        affected_attributes: [vibration, bearing_temp, motor_current]
        description: Gradual vibration increase over hours to days, rising
          bearing temperature, slight motor current increase.
      - id: cavitation
        name: Cavitation
        severity: warning
        affected_attributes: [discharge_pressure, vibration, motor_current]
        description: Erratic discharge pressure, high-frequency vibration,
          unstable motor current. Causes rapid impeller damage if sustained.

  # ... uv_bank, chemical_dosing_pump, filter_bed types follow same pattern
```

```yaml
equipment_instances:
  - id: raw_water_pump_1
    name: Raw Water Pump 1
    type_id: centrifugal_pump
    process_area_id: intake
    commissioned: "2019-03-15"
    notes: Impeller replaced 2024-11-02 following cavitation damage.
    tag_bindings:
      discharge_pressure: Plant/WTP/Pump/RawWater_P01/DischargePressure
      motor_current:      Plant/WTP/Pump/RawWater_P01/MotorCurrent
      vibration:          Plant/WTP/Pump/RawWater_P01/Vibration
      bearing_temp:       Plant/WTP/Pump/RawWater_P01/BearingTemp
      run_status:         Plant/WTP/Pump/RawWater_P01/RunStatus
      speed_setpoint:     Plant/WTP/Pump/RawWater_P01/SpeedSetpoint

  # ... remaining instances follow same pattern

historian:
  default_lookback_hours: 24
  max_lookback_days: 90
  resolution_seconds: 60
```

## Modeling Imperfect Plants

Real industrial facilities are not clean. Decades of different contractors, different conventions, different commissioning standards and deferred maintenance produce protocol surfaces that don't match any idealized model. An MQTT broker serving a plant built in stages over 20 years may have three different naming conventions for the same equipment type, sensors that failed and were never removed, tags with no engineering units and quality signals that were never properly configured.

FieldWorks does not pretend this isn't true. The topology model provides four mechanisms for representing reality honestly. A topology that accurately describes a messy plant is more useful than one that pretends the plant is clean.

### Optional attribute bindings

Not every instance of an equipment type will have every attribute the type defines. A pump type may define a vibration attribute because most pumps in the facility have vibration sensors. Some don't. The instances without sensors should not be forced to fabricate a binding.

Tag bindings are optional at the instance level. An instance binds the attributes it actually has. The topology validator will warn on missing bindings but will not fail on them. The Specialist receives only the attributes that are bound and reasons with what is available. It notes what is missing rather than silently ignoring it.

```yaml
equipment_instances:
  - id: raw_water_pump_3
    name: Raw Water Pump 3
    type_id: centrifugal_pump
    process_area_id: intake
    tag_bindings:
      discharge_pressure: Plant/WTP/Pump/RawWater_P03/DischargePressure
      motor_current:      Plant/WTP/Pump/RawWater_P03/MotorCurrent
      run_status:         Plant/WTP/Pump/RawWater_P03/RunStatus
      # vibration, bearing_temp not instrumented on this unit
```

### Confidence on tag bindings

Tag bindings carry an optional confidence field that records how the binding was established. This flows directly into Specialist reasoning. A diagnosis built on verified bindings is more reliable than one built on inferred bindings, and the Specialist should say so.

| Key | Type | Required | Description |
|:---|:---|:---|:---|
| `confidence` | string | no | How this binding was established. One of: verified, inferred, suspect. Default: verified if omitted. |

```yaml
tag_bindings:
  discharge_pressure:
    tag_id: Plant/WTP/Pump/RawWater_P01/DischargePressure
    confidence: verified
  vibration:
    tag_id: Plant/WTP/Pump/RawWater_P01/Vibration
    confidence: inferred
  bearing_temp:
    tag_id: Plant/WTP/Pump/RawWater_P01/BearingTemp_OLD
    confidence: suspect
```

- **verified** — binding was confirmed against commissioning documentation or direct inspection. The tag ID is correct and the signal is reliable.

- **inferred** — binding was proposed by the topology builder based on naming convention analysis. Has not been manually confirmed. Treat with appropriate caution.

- **suspect** — binding is known to be unreliable. The tag exists and is readable but the signal has known quality issues. The Specialist should note this in any diagnosis that uses it.

> The expanded tag_bindings syntax with tag_id and confidence is fully compatible with the simple string syntax used in earlier examples. Simple string bindings are treated as confidence: verified. Use the expanded syntax only when confidence needs to be recorded.

### Notes on tag bindings

Individual tag bindings accept a notes field for known issues that cannot be expressed in structured fields. This is where institutional knowledge lives.

```yaml
tag_bindings:
  discharge_pressure:
    tag_id: Plant/WTP/Pump/RawWater_P01/DischargePressure
    confidence: verified
    notes: Transmitter replaced 2023-08, reading approximately 0.15 bar
      high until recalibration scheduled for Q3 2026.
  bearing_temp:
    tag_id: Plant/WTP/Pump/RawWater_P01/BearingTemp
    confidence: suspect
    notes: Sensor has been intermittently dropping to 0.0 since 2022.
      Quality signal is unreliable. Treat bad quality as sensor fault
      not equipment fault.
```

Notes on tag bindings are visible to Specialists. An experienced maintenance technician who knows that a pressure transmitter reads high can record that knowledge here. The Specialist incorporates it. Knowledge that would otherwise exist only in someone's head becomes part of the plant model.

### Explicit missing attribute handling

The Specialist agent design in Part III addresses directly what happens when a diagnosis encounters missing, inferred, or suspect data. The rules are simple:

- A Specialist that cannot read a bound tag due to quality bad or connection error reports the gap explicitly. It does not silently exclude the attribute from its reasoning.

- A Specialist reasoning against an inferred binding qualifies its conclusion. It may diagnose but it notes the confidence limitation.

- A Specialist reasoning against a suspect binding treats the signal as corroborating evidence only, not primary evidence. A diagnosis does not rest on a suspect signal alone.

- A Specialist asked to diagnose equipment with no vibration binding does not pretend vibration data is unavailable due to a fault. It states that this equipment is not instrumented for vibration and adjusts its diagnostic scope accordingly.

The goal is honest diagnosis. A Specialist that says "bearing wear is possible but I cannot confirm without vibration data, which is not instrumented on this unit" is more useful than one that either ignores the gap or fabricates a conclusion. Operators trust systems that know what they don't know.

## What Comes Next

Part II is complete when you have a validated topology.yaml and a working aggregator.json, and the adapter conformance suite passes against your protocol servers. At that point the plant layer is fully configured. The agent layer has everything it needs to reason about your facility.

Part III covers the agent layer: the fixed agent designs, how Cascade uses the topology to route queries, how Specialists consume equipment type context and fault modes, how Deadband validates before action, how Millwright executes with write access, the audit trail contract, and the trust mode configuration that governs how much autonomy the system operates with.
