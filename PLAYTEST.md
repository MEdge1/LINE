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
