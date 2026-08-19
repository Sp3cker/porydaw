	.equiv NUM_TRACKS_BGM, 16
	.equiv NUM_TRACKS_SE1, 3
	.equiv NUM_TRACKS_SE2, 3
	.equiv NUM_TRACKS_SE3, 3
	.equiv NUM_TRACKS_SE_1TRK, 1

	.align 2
gMPlayTable::
	music_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0
	music_player gMPlayInfo_SE1, gMPlayTrack_SE1, NUM_TRACKS_SE1, 0
	music_player gMPlayInfo_SE2, gMPlayTrack_SE2, NUM_TRACKS_SE2, 0
	music_player gMPlayInfo_SE3, gMPlayTrack_SE3, NUM_TRACKS_SE3, 0
	music_player gMPlayInfo_SE_1TRK, gMPlayTrack_SE_1TRK, NUM_TRACKS_SE_1TRK, 0
