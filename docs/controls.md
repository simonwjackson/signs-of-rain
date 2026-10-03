# Playing Signs of Rain

You have eight power. Rain costs two. Food costs one. Power does not refill.

The drought ends after seven days, about 4 minutes 40 seconds at normal speed. You can pause, act while paused, or watch without intervening. At the ending, close the account to inspect people.

| Control | Action |
| --- | --- |
| Wheel | Zoom continuously between face, village, and landscape scale. |
| Middle drag | Orbit and tilt the 3D camera. |
| Right drag, or WASD | Pan across the terrain. |
| Q / E | Orbit with the keyboard. |
| C | Focus a close view on the selected person. |
| V | Return to the whole valley. |
| 1, or Look | Select a person by clicking them. |
| 2, then click | Bring rain. Put a village well inside the preview circle to restore its water and crops. |
| 3, then click | Place a food cache. People must find it, collect it, and carry the food. |
| Space | Pause or resume time. |
| Tab | Inspect the next person. The People menu also lists everyone. |
| F | Cycle normal, double, and quadruple speed. |
| R | Restart with the same seed and starting conditions. The new attempt starts paused. |
| P | Replay the current or previous attempt with its recorded input times. |
| M | Mute or restore sound. |
| H | Open the guide. |
| Escape | Close a panel or cancel miracle targeting. |
| Right click | Cancel miracle targeting. |
| Menu | Access replay, save replay, reduced motion, and Quit. |

The guide and People list do not pause time automatically. Use Space before opening them if you want time to stop. The first guide starts paused.

The inspector separates direct observation from reports. It shows the person who passed a story, its route, the interpretation, and subsequent choices. When following a person closely, selecting another person also moves the camera to them. A new sign can take until the next simulation tick to change an action.

World activity has meaning. People carry food baskets and water vessels only when they hold supplies. Skeletal gestures show work, conversation, sharing, and ritual. Withdrawal changes their destinations. Inspect a person to identify their village and reasons. Crop height and color follow the remaining crop; the common well's water level follows its supply.

## Suggested experiments

1. Give rain to Alder, then inspect Ada, Bram, and Cora with Tab. They have different histories. Let time run and follow their destinations.
2. Wait for people to travel near the shrine, then give food there. Compare a direct witness with a person who only hears a report. An unwitnessed cache can still feed people without creating a supernatural story.
3. Spend all your rain on Alder. Restart and alternate between the villages. Compare the number of exhausted people, the thirst in each village, and the stories remembered.
4. Do nothing at quadruple speed. The drought still reaches an ending. Compare it with your intervened attempt.
5. Use Replay after an attempt. It repeats accepted interventions at their original simulation ticks. Restart returns agency to you. Save replay writes `last-replay.json` in the game's user-data directory; it overwrites that one file. The menu replay uses the current session, not this saved file.

## Known limits

The valley contains 24 rule-driven people and four starting history patterns. Trust and history stay fixed. Reports carry attributed facts without inventing new details. There are no buildings to construct, obstacles to navigate, deaths, campaign, or creature. Travel is direct, so characters can cross scenery.

Resources and beliefs interact, but this is not a calibrated survival model or a theory of religion. A kind gift can also cause travel and offerings that reduce harvesting. There is no single moral score or guaranteed best strategy.

Desktop mouse and keyboard are the supported controls. Small windows keep the controls but make the world harder to read; use the People menu there, then close the inspector to see the focused person. Camera clearance prevents terrain penetration, but does not prevent passing through architecture. Controller, touch, and screen-reader play are not verified. Seeded results are verified on the supplied Godot 4.6.1 runtime, not across engine versions or CPU architectures.
