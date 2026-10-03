# Signs of Rain

A standalone Godot prototype. You choose an act. People decide what it means.

The approved scope is two villages, about 24 people, a bounded drought, limited rain and food, a definite ending, and replay with the same seed. No campaign, combat, creature training, or complex construction. No original BW2 assets or code. Preserve the existing BW2 repository, remote runtime, and Korri work.

## What must happen

Events reach people through sight or reports. Needs, past experience, and trust affect interpretation. Memory affects action. Generosity can lead to sharing, ritual belief to visits and rituals, favoritism to avoiding neighbors and hoarding. A report is not a direct observation. Uninformed people do not know a miracle occurred.

The player sees movement, sharing, rituals, stories, and distrust, then inspects the cause. Different dialogue with identical behavior does not pass.

The user explicitly requested simulation tests for information access, differing interpretation, belief-driven behavior, identical seeded replay, and contrasting runs including no intervention. These are the approved verification boundaries. The second boundary is the real shipped game on aka: input, rendering, audio, ending, and restart.

## Implementation scope

Godot 4.6.1, GDScript, an engine-independent-in-behavior RefCounted simulation, and a Node2D rendered valley. Fixed half-second simulation ticks. No external services. Rules limit expressive range but allow replay and causal inspection. Authored vector scenery and generated sound avoid conversion dependencies.

## Presentation plan

The memorable element is an inhabited, illustrated dry valley. The world gets most of the screen. A person opens a readable causal account, not a page of global scores.

Palette tokens: deep water `#123333`, slate `#416260`, dry grass `#aba578`, wheat `#ddd396`, rain `#89c6d0`, paper `#edf0da`. The two villages use blue-green and plum clothing. Serif titles and a humanist sans body separate story from controls. Avoid generic statistic cards. Buildings, paths, baskets, and people carry information directly.

The shape is a full-width valley under a compact header, with grouped miracle controls below. A person panel uses spare width or overlays the world when width is scarce. Lower-priority controls move together into a menu. Layout uses actual Control size, not a device label. No action disappears. The world remains a consistent 1000 by 640 coordinate plane.

The reference search returned adjacent map patterns, not games. [H&M](https://mobbin.com/screens/8c2cda9c-12dd-4cc2-8e9b-83acda6fb1cf) keeps the map beside a closeable selected-place panel. Adopt that spatial relationship. [GetYourGuide](https://mobbin.com/screens/4c6089bb-c5ed-4e53-8b37-307c502463ea) links a sequence of named stops with positions. Adopt the causal sequence, not the commercial sidebar. [Klaviyo](https://mobbin.com/screens/9e0750ed-89c5-4296-87cd-44844b5fa846) leaves a large map under a compact toolbar. Keep that world priority; reject its analytics navigation.

Review against the brief: a parchment management dashboard would obscure society. Use the live valley as the primary explanation, and use the panel only for a selected person. This prototype tests consequences, not a general-purpose belief dashboard.

## Delivery

Commit source. Deploy separately under the user's home on aka. Ship a launchable build, a short actual gameplay recording, controls, suggested experiments, verified evidence, and honest limitations. Cut content before testing.
