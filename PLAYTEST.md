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
