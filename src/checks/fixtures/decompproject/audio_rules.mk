SOUND_BIN_DIR := $(OBJ_DIR)/sound

$(SOUND_BIN_DIR)/%.bin: sound/%.wav 
	$(WAV2AGB) -b $< $@
