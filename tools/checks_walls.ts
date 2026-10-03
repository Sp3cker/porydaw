// Measured walls (2026-09-28, 18 cores, pools 6 and 8) for LPT: heaviest first.
// Only rows ≥ ~0.8 s (checks) / ~2.5 s (shell) are listed; lighter ones at the 0.3 default fill gaps.
export const WALL_ESTIMATE: Record<string, number> = {
  // checks (porydaw_checks)
  "swiftcore-projectsession": 9.51,
  "swiftcore-playback": 8.13,
  "swiftcore-bankhistory": 2.1,
  "exportcheck-tail": 0.99,
  "exportcheck-loop": 0.86,
  // checks:shell (shell_qml_tests)
  "shell-tabs": 23.82,
  "shell-drawer-parity-voice-velocity": 23.74,
  "shell-text-contrast-song-vanilla": 11.61,
  "shell-text-contrast-song-dark-neutral-high": 11.56,
  "shell-text-contrast-song-immaterial": 11.53,
  "shell-songs": 9.78,
  "shell-transport": 8.48,
  "shell-tabs-open-select": 6.21,
  "shell-voicegroup-editing": 6.1,
  "shell-drawer-parity": 5.95,
  "shell-tabs-reload": 5.88,
  "shell-settings": 5.25,
  "shell-transport-session": 5.14,
  "shell-tabs-close": 4.18,
  "shell-polyphony": 4.14,
  "shellwindow-velocity": 3.68,
  "shell-pitch-bend-retarget": 3.67,
  "shell-event-list-menus": 3.29,
  "shellwindow-prompts": 3.2,
  "shell-tabs-drawer": 2.89,
  "shell-tabs-bank-lifetime": 2.88,
  "shell-grid-menu-ruler-lifecycle": 2.86,
  "shell-note-visuals": 2.65,
  "shell-event-list-presentation": 2.63,
  shellwindow: 2.53,
  "shell-voicegroup-save": 2.51,
};

export function wallEstimate(name: string): number {
  return WALL_ESTIMATE[name] ?? 0.3;
}
