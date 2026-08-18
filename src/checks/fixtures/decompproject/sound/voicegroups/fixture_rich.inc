	.align 2
voice_group fixture_rich
	voice_directsound 60, 0, DirectSoundWaveData_fixture_loop, 255, 180, 200, 72
	voice_directsound 60, 0, DirectSoundWaveData_fixture_pluck, 240, 140, 176, 64
	voice_directsound_no_resample 60, 0, DirectSoundWaveData_fixture_bass, 224, 128, 192, 80
	voice_directsound_alt 60, 0, DirectSoundWaveData_fixture_drum, 255, 96, 160, 48
	voice_square_1 60, 0, 2, 2, 2, 3, 12, 4
	voice_square_2 60, 0, 1, 3, 2, 11, 4
	voice_programmable_wave 60, 0, ProgrammableWaveData_fixture_pulse, 2, 3, 12, 4
	voice_noise 60, 0, 1, 2, 2, 10, 3
	voice_keysplit fixture_keys, keysplit_fixture
	voice_keysplit fixture_bass, keysplit_fixture_bass
	voice_keysplit_all fixture_drums_a
	voice_keysplit_all fixture_drums_b
