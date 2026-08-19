MID_SUBDIR := sound/songs/midi
MID := $(MID2AGB)
STD_REVERB = 50
AQUA_VOICEGROUP = _fixture_aqua
AQUA_VOLUME = 080

$(MID_SUBDIR)/mus_aqua_magma_hideout.s: %.s: %.mid
	$(MID) $< $@ -E -R45 -G$(AQUA_VOICEGROUP) -V$(AQUA_VOLUME)

$(MID_SUBDIR)/mus_mkcheck_compare.s: %.s: %.mid
	$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_compare -V090
