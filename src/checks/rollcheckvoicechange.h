#pragma once

// Voice Change drawer-page coverage for the editor-drawer check. Runs the
// standalone VoiceChangeArea on its own synthesized document fixture and
// reports into the caller's failure count; it is never a registered harness.
void checkVoiceChangeAreaPage(int &failures);
