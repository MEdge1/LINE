# Milestone 1 Playtest

**Platform:** Android physical device
**Status:** Complete pending final payout-feedback verification

## What Worked

- Generator → Processor → Output production loop works correctly.
- Resources visibly travel through the production line.
- Processor correctly increases resource value.
- Output correctly converts processed resources into currency.
- Touch selection of the Generator works.
- Generator upgrades work correctly.
- Upgrading from Level 1 to Level 2 changes production from 1.00/sec to 1.25/sec.
- Android APK builds, installs, and runs successfully.

## Playtest Finding: Currency Feedback

The first physical-device playtest revealed that currency gain was not visually obvious enough. The money total was increasing correctly, but the player had to read the instructions before recognizing that resources reaching the Output were generating money.

## Improvement

Payout feedback was added:

- A `+$N` indicator appears above the Output when a resource generates currency.
- The payout indicator rises and fades.
- The displayed amount comes directly from the actual simulation payout.
- The HUD money total briefly scales and highlights when money is received.
- Multiple closely timed payouts are handled without overlapping excessively.
- Authoritative currency calculations remain in the simulation layer.

## Design Lesson

> Important game events should be understandable by watching the network, not by reading instructions.

This principle should guide future LINE systems. Processing, payouts, upgrades, boosts, queues, bottlenecks, and other important state changes should communicate themselves visually whenever practical.

## Milestone 1 Result

Milestone 1 validated the basic gameplay loop:

```
Generate → Process → Output → Earn → Upgrade → Produce Faster
```

The next milestone expands LINE from watching a predetermined production line to building and connecting a production network.

---

# Milestone 2 Playtest: Player-Built Networks

**Platform:** Android physical device
**Status:** Complete
**Commit:** `6ea9956` — Milestone 2: implement player-built production networks

## What Milestone 2 Added

Milestone 2 transformed LINE from a predetermined production line into a player-built network game.

Players can now:

- Place Generator, Processor, and Output on a grid.
- Create directional connections between nodes.
- Drag from a source node's output handle to create a connection.
- Use the CONNECT action as an alternative connection method.
- Disconnect and reconnect individual connections without deleting nodes.
- Move existing nodes.
- Delete nodes safely.
- Upgrade Generators up to Level 15.
- Pan and zoom the production workspace.
- See resources move through the network.
- Receive clear payout feedback when resources reach an Output.

## Architecture

Milestone 2 separates network topology, layout, simulation, presentation, and interaction.

- **NetworkGraph:** logical nodes, connections, and connection rules.
- **WorkspaceLayout:** grid positions and occupancy.
- **ProductionSimulation:** aggregated resource batches, processing, payouts, and the conservation ledger.
- **NetworkView:** representative visual flow, grid, nodes, labels, and feedback.
- **WorkspaceController:** touch and mouse gestures, interaction modes, and drag-to-connect.
- **Hud, NodePanel, BuildToolbar:** player controls and inspection.

The simulation remains authoritative. Visual particles represent production flow; they are not the production itself.

## Playtest Finding: Individual Resources Did Not Scale

Early Milestone 2 builds represented every resource as an individual object.

With 5,427 held resources:

- 5,427 individual resource objects were maintained.
- `manager.step` took about 3.5 ms per call.
- Large disconnected backlogs created excessive visual artifacts and degraded performance.

The simulation was then changed to aggregate resources into batches. With the same 5,427 held resources:

- The simulation maintained 54 batches.
- `manager.step` fell to about 0.08 ms per call.
- The authoritative resource quantity was unchanged, while the visual artifact count dropped sharply.

## Resource Conservation

The simulation enforces a conservation ledger:

```
produced = paid + held + lost
```

Stress test (107 nodes, 16,000 steps):

- 17,600 units produced
- 17,483 units paid
- 117 units still held
- 0 unaccounted units

Disconnecting an edge returns its in-flight quantity to the source node's waiting queue rather than discarding it.

## Playtest Finding: Visual Flow Needed to Feel Alive

Batching solved the scalability problem, but the first flow visuals felt too sparse and less satisfying than the earlier per-unit look.

LINE now separates authoritative quantity from representative visual flow. Each batch shows a bounded number of particles from a nonlinear density mapping (1 particle for 1 unit, rising to 8 for very large batches). Connections glow with flow, and particles have faint trails.

Current visual limits:

- 12 representative particles per connection
- 200 representative particles globally
- 6 simultaneous payout indicators

The goal is for high-production networks to look busy without creating one visual object per resource.

## Playtest Finding: Connection Editing Needed to Be Easier

The original workflow was tap-to-select, then tap-to-connect. Reconfiguring a network meant deleting and rebuilding nodes.

Milestone 2 iterations added:

- Drag-to-connect from an output handle, with a live preview.
- Inspector-based DISCONNECT for each connection.
- A CONNECT action as a fallback.
- Explanatory feedback for invalid connections.

Physical testing confirmed that reconnecting and disconnecting work without accidental conflicts with panning, zooming, or selection.

## Playtest Finding: Large Number Safety

Long Processor chains double value repeatedly, so values grow very quickly.

- The Processor multiplier remains ×2.
- A large-number representation prevents silent integer overflow.
- Displayed values use compact formatting, such as 1,250, 18.4K, 2.71M, 8.35B, 1.26T, and 1.00e15.
- Formatting is display-only. Authoritative values stay exact.

## Generator Prototype Cap

Generators have a temporary maximum level of 15.

At Level 15:

- The UPGRADE button is disabled.
- No currency is spent on repeated attempts.
- The inspector displays MAX LEVEL.

This is a prototype balance safeguard, not the final Generator progression design.

## Strategy Finding

Playtesting suggested that the strongest current strategy is to fill available space with connected Processors. Because each Processor doubles value, long chains produce highly satisfying payout growth.

This is currently a feature to preserve rather than suppress with diminishing returns. Milestone 3 should add throughput, queues, buffers, bottlenecks, Splitters, Mergers, Boosters, and spatial tradeoffs so that Processor-heavy layouts become one strategy among several.

## Design Lessons

> Visual quantity and visual density should remain independent.

> Important game events should be understandable by watching the network.

> Reconfiguring the machine should be easy. Experimentation is part of the game.

> Exponential growth is currently satisfying. Balance should be judged after Milestone 3 introduces competing systems.

## Milestone 2 Result

Milestone 2 validated the core player loop:

```
Place → Connect → Produce → Observe → Upgrade → Reconfigure
```

Players can now build and rearrange their own machine, and the flow of production is readable on a phone.

The primary question for Milestone 3: can throughput, routing, capacity, and bottlenecks turn Processor-heavy chains into one strategy among several?

## Milestone 3 Playtest: Routing, Throughput, and Network Optimization

**Platform:** Android physical device  
**Status:** Complete

### What Milestone 3 Added

Milestone 3 transformed LINE from a network-building game into an optimization game.

The production simulation now includes:

- Formal node throughput.
- Bounded resource buffers.
- Backpressure.
- Queue visualization.
- Bottleneck detection.
- Splitters.
- Mergers.
- Spatial Boosters.
- Network and node telemetry.
- Product Complexity.
- Complexity-aware processing speed.
- Complexity-based resource visuals.
- Large-number-safe deep processing.
- Improved camera behavior for the mobile inspector.

The Processor's core behavior remains:

`Value ×2`

The multiplier was intentionally preserved because exponential processing continues to be one of LINE's most satisfying mechanics.

---

### Playtest Finding: Bottlenecks Are Satisfying to Solve

Physical-device testing confirmed that the queue and backpressure systems create a useful optimization loop.

A constrained network visibly begins backing up:

`Production → Queue Growth → Bottleneck → Player Diagnosis → Network Change → Queue Clears`

Identifying a bottleneck and correcting the network is satisfying.

This validates an important LINE design principle:

> The player should be able to see that the machine has a problem, understand why, and redesign the network to improve it.

Bottlenecks now distinguish between:

- **BUSY:** high utilization while keeping up.
- **BOTTLENECK:** high utilization with sustained queued work.
- **BLOCKED:** waiting because downstream capacity is unavailable.

---

### Splitters and Mergers

Physical testing confirmed that both routing components work naturally.

**Splitter**

A Splitter accepts one production stream and distributes resources between two branches using deterministic routing.

`Input → Splitter → Branch A / Branch B`

The split is performed mathematically on resource batches rather than by creating individual simulation objects.

**Merger**

A Merger accepts two production streams and combines them into a single downstream route.

`Branch A + Branch B → Merger → Output`

Compatible batches may merge while resources with different authoritative properties remain distinct.

Both systems create layouts that are meaningfully different from a simple sequential Processor chain.

---

### Booster

Boosters provide a spatial processing-capacity bonus to orthogonally adjacent Processors.

Current prototype behavior:

`+25% Processor capacity`

Physical testing confirmed that the Booster effect is noticeable and useful when processing capacity becomes constrained.

Early testing also showed that Boosters have limited value when the network is not experiencing genuine processing pressure.

This is currently considered desirable.

> A Booster should solve a processing problem rather than automatically belong in every network.

Product Complexity makes Boosters increasingly relevant as deeper processing creates additional throughput pressure.

---

### Buffers and Backpressure

Each production node now has a bounded resource buffer.

When downstream capacity becomes unavailable:

1. Downstream queues fill.
2. Upstream flow slows or pauses.
3. Production remains accounted for.
4. Resources are not silently destroyed.
5. Flow resumes when capacity becomes available.

The authoritative simulation continues to enforce:

`Produced = Paid + Held + Lost`

Normal backpressure does not count as lost production.

---

### Resource Batching Remains Fundamental

Milestone 2 introduced aggregated `ResourceBatch` simulation to prevent individual resources from causing runaway simulation and rendering costs.

Milestone 3 preserves this architecture.

Authoritative resource quantity remains independent from visual particle quantity.

Large production volumes therefore do not require an equally large number of simulation or rendering objects.

Representative particles remain bounded by the visual-cap system.

---

### Product Complexity

Physical playtesting identified a central design direction for deeper processing.

Instead of weakening the Processor's `×2` multiplier, every processing step now also increases **Product Complexity**.

A resource therefore evolves as:

`Complexity 0 / Value 1`

`↓ Processor`

`Complexity 1 / Value 2`

`↓ Processor`

`Complexity 2 / Value 4`

`↓ Processor`

`Complexity 3 / Value 8`

Each Processor still doubles value exactly once.

Complexity is stored explicitly as authoritative resource state rather than inferred from value.

---

### Complexity and Processing Speed

Higher-complexity resources are increasingly difficult to process.

The current prototype processing modifier is:

`processing_modifier(c) = 1 / (1 + 0.10 × c)`

Processor effective capacity therefore depends on:

`Base Capacity × Booster Modifier × Complexity Modifier`

This creates a new tradeoff:

`PROCESSING DEPTH ↔ VALUE ↔ THROUGHPUT`

Deep processing produces extremely valuable resources but moves fewer completed units through the network.

Shallower processing produces less valuable resources at higher throughput.

The Processor multiplier itself remains unchanged.

---

### Complexity Visual Identity

Product Complexity is also communicated visually.

As resources move through deeper Processor chains, their appearance evolves through a deterministic progression including:

- Color.
- Glow.
- Particle size.
- Trail intensity.

The current visual progression moves through colors approximately resembling:

`Cyan → Blue → Violet → Magenta → Orange → Gold`

Higher-complexity resources therefore look increasingly valuable and energetic.

This creates a visible transformation across long processing chains rather than representing every processing stage with the same artifact.

The goal is for the player to watch a simple resource become increasingly sophisticated before finally reaching the Output.

---

### High-Complexity Payouts

Output payout feedback now also reflects Product Complexity.

The payout amount remains entirely determined by authoritative resource value.

Complexity only affects presentation.

Higher-complexity payouts may receive:

- Stronger payout color.
- Slightly larger payout text.
- Stronger glow.
- More noticeable HUD pulse.
- Complexity-tier presentation.

This reinforces the relationship:

`Long Processing → High Complexity → Difficult Production → Large Payoff`

---

### Large Numbers

Long Processor chains produce extremely large values.

LINE continues using its large-number representation to preserve exact economic values without silent integer overflow.

Product Complexity does not replace or modify the authoritative value.

For example, a 43-stage Processor chain still produces:

`Value = 2^43 = 8,796,093,022,208 per completed unit`

Complexity changes how quickly that resource can continue through processing, not what the resource is worth.

---

### Strategy Finding

Milestone 3 compared several production architectures.

The major finding is that **deep sequential processing remains the strongest strategy when optimizing purely for revenue**.

After Product Complexity was introduced, a 43-Processor chain produced approximately:

`$6.74 trillion / second`

while completing roughly:

`0.767 units / second`

By comparison, medium-depth and parallel layouts completed substantially more units per second but produced lower total revenue.

This is accepted as a Milestone 3 design result rather than treated as a defect.

> Exponential value growth still exceeds the current hyperbolic processing penalty as Processor depth increases.

LINE does not currently require one universally optimal network.

Future objectives can reward different characteristics such as:

- Maximum revenue.
- High unit throughput.
- Low queue size.
- Limited space usage.
- Low bottleneck count.
- Target Product Complexity.
- Stable production.
- Efficient routing.

Different goals can therefore make different network architectures desirable without weakening the Processor's satisfying `×2` behavior.

---

### Camera Playtest Finding

The original Milestone 3 implementation automatically centered every selected node above the inspector.

Physical testing found this frustrating because repeated node selections caused the camera to override the player's chosen view.

The behavior was changed.

The camera now moves only when the selected node would actually be obscured by the UI.

When correction is required:

- Only the minimum necessary movement is applied.
- The transition is animated.
- Visible nodes cause no camera movement.
- Manual pan, touch, and pinch input immediately take priority.

This preserves spatial orientation while still preventing the inspector from hiding the selected node.

---

### Disconnect Resource Handling

Disconnecting an active connection must preserve resources without violating buffer capacity.

Returned in-flight batches now enter a dedicated holding state at the source.

Resources are moved back into the normal queue as buffer space becomes available.

This preserves:

- Quantity.
- Value.
- Complexity.
- Processing state.
- Buffer capacity.
- Resource conservation.

Disconnecting and rearranging the machine therefore remains safe and forgiving.

---

### Performance

Milestone 3 preserves the performance architecture established during Milestone 2.

Stress testing included:

- Deep processing chains.
- High Product Complexity.
- Large values.
- Queues.
- Backpressure.
- Splitters.
- Mergers.
- Boosters.
- Representative particle rendering.

Physical Android stress testing remained responsive.

Simulation quantity and visible particle quantity remain independent.

---

### Physical-Device Results

Android testing confirmed:

- Network construction remains smooth.
- Splitters work as intended.
- Mergers work as intended.
- Booster effects are visible.
- Queues and backpressure work.
- Fixing bottlenecks is satisfying.
- Large networks remain responsive.
- Deep Processor chains remain satisfying.
- Product Complexity provides a stronger identity to deeply processed resources.
- Complexity-induced processing constraints create useful bottleneck pressure.
- Mobile network editing remains practical.
- The revised camera behavior preserves player navigation better than automatic centering.

---

### Milestone 3 Design Lessons

> A machine should visibly communicate why it is struggling.

> Fixing a bottleneck should produce an observable reward.

> Exponential processing is a source of satisfaction and should not be weakened without a strong reason.

> Make deeper processing increasingly difficult rather than making it less valuable.

> The product itself should visually evolve as processing depth increases.

> Simulation quantity and visual artifact quantity must remain independent.

> Different network objectives can make different architectures valuable without requiring one universally optimal design.

> Camera automation should assist the player without taking navigation control away from the player.

---

### Milestone 3 Result

Milestone 3 validated the third major gameplay question:

**Is diagnosing and improving the machine satisfying?**

Yes.

LINE now supports the gameplay loop:

`Build → Observe → Diagnose → Reconfigure → Improve → Process Deeper → Earn More`

The network is no longer simply a chain of multipliers.

The player must reason about:

`VALUE`

`THROUGHPUT`

`COMPLEXITY`

`QUEUES`

`BOTTLENECKS`

`ROUTING`

`SPACE`

`BOOSTER PLACEMENT`

The next major development question becomes:

**Why should the player continue improving the machine over a longer play session?**

That question belongs to Milestone 4: progression, objectives, unlocking, expansion, and persistence.

