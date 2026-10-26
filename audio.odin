package main

import ma "vendor:miniaudio"

Sound_Id :: enum {
	Fire_Primary,
	Fire_Secondary,
	Ui_Mouse_Click,
	Ui_Click,
}

sound_files : [Sound_Id][]byte = {
	.Fire_Primary   = #load("assets/sounds/fire_primary.mp3"),
	.Fire_Secondary = #load("assets/sounds/fire_secondary.mp3"),
	.Ui_Mouse_Click = #load("assets/sounds/ui_mouse_click.ogg"),
	.Ui_Click       = #load("assets/sounds/ui_click.ogg"),
}

Music_Id :: enum {
	Main_Menu,
}

music_files : [Music_Id][]byte = {
    .Main_Menu = #load("assets/music/main.mp3"),
}

Audio :: struct{
	engine      : ma.engine,
	sound_group : ma.sound_group,
	music_group : ma.sound_group, 
	sound_map   : [Sound_Id]Sound,
	music_map   : [Music_Id]Music,
}

Audio_Data :: struct {
	ma_sound     : ma.sound,
	audio_buffer : ma.audio_buffer,
	pcm_data     : rawptr,
}

Sound :: struct {
	using audio_data : Audio_Data,
	pitch_range      : Maybe(struct {
        min : f32,
		max : f32,
	}),
    loop : bool,
}

Music :: struct {
	using audio_data : Audio_Data,
}

audio_init  :: proc(aud : ^Audio) {
	res := ma.engine_init(nil, &aud.engine)
	assert(res == .SUCCESS)

    for sound_bytes, id in sound_files {
        audio_make_sound(aud, id, sound_bytes)
    }

    for music_bytes, id in music_files {
        audio_make_music(aud, id, music_bytes)
    }
}

audio_make_audio_data  :: proc(
	aud        : ^Audio,
	audio_data : ^Audio_Data,
	file_data  : []byte,
    loop       : bool,
	group      : ^ma.sound_group,
) {
	frame_count: u64

	channels    := ma.engine_get_channels(&aud.engine)
	sample_rate := ma.engine_get_sample_rate(&aud.engine)

	decoder_cfg := ma.decoder_config_init(.f32, channels, sample_rate)

	res := ma.decode_memory(
		raw_data(file_data), 
		len(file_data), 
		&decoder_cfg, 
		&frame_count, 
		&audio_data.pcm_data
	)

	assert(res == .SUCCESS)

	aud_buf_cfg := ma.audio_buffer_config_init(
		.f32,
		channels, 
		frame_count, 
		audio_data.pcm_data,
		nil,
	)
	aud_buf_cfg.sampleRate = sample_rate
	
	ma.audio_buffer_init(&aud_buf_cfg, &audio_data.audio_buffer)

    ma_sound_flags : ma.sound_flags = {.NO_SPATIALIZATION}
    if loop {
        ma_sound_flags += {.LOOPING}
    }
    
	ma.sound_init_from_data_source(
		&aud.engine,
		cast(^ma.data_source)(&audio_data.audio_buffer),
		ma_sound_flags,
		group,
		&audio_data.ma_sound,
	)
}

audio_destroy_audio_data  :: proc(aud : ^Audio, audio_data : ^Audio_Data) {
	ma.sound_uninit(&audio_data.ma_sound)
	ma.audio_buffer_uninit(&audio_data.audio_buffer)
	ma.free(audio_data.pcm_data, nil)
}

audio_make_sound  :: proc(
	aud       : ^Audio,
	sound_id  : Sound_Id,
	file_data : []byte,
) {
	audio_make_audio_data(
        aud,
        &aud.sound_map[sound_id].audio_data,
        file_data,
        false,
		&aud.sound_group,
    )
}

audio_make_music  :: proc(
	aud       : ^Audio,
	music_id  : Music_Id,
	file_data : []byte,
) {
	audio_make_audio_data(
        aud,
        &aud.music_map[music_id].audio_data,
        file_data,
        true,
		&aud.music_group,
    )
}

audio_destroy_sound  :: proc(aud : ^Audio, sound_id : Sound_Id) {
	audio_destroy_audio_data(aud, &aud.sound_map[sound_id].audio_data)
	aud.sound_map[sound_id] = {}
}

audio_destroy_music  :: proc(aud : ^Audio, music_id : Music_Id) {
	audio_destroy_audio_data(aud, &aud.music_map[music_id].audio_data)
	aud.music_map[music_id] = {}
}

audio_update_listener  :: proc(
	aud               : ^Audio, 
	listener_position : [3]f32,
) {
	ma.engine_listener_set_position(
		&aud.engine,
		0,
		listener_position.x, listener_position.y, listener_position.z
	)
}

audio_destroy  :: proc(aud : ^Audio) {
	for _, id in aud.sound_map {
		audio_destroy_sound(aud, id)
	}
	
	for _, id in aud.music_map {
		audio_destroy_music(aud, id)
	}
	
	ma.engine_uninit(&aud.engine)
}

audio_play_sound :: proc(aud : ^Audio, sound_id : Sound_Id){
	ma_sound := &aud.sound_map[sound_id].ma_sound
	ma.sound_seek_to_pcm_frame(ma_sound, 0)
	ma.sound_start(ma_sound)
}

audio_play_music :: proc(aud : ^Audio, music_id : Music_Id){
	ma_sound := &aud.music_map[music_id].ma_sound
	ma.sound_seek_to_pcm_frame(ma_sound, 0)
	ma.sound_start(ma_sound)
}

audio_apply_master_volume :: proc(aud : ^Audio, linear_volume : f32) {
	ma.engine_set_volume(&aud.engine, linear_volume)
}

audio_apply_music_volume :: proc(aud : ^Audio, linear_volume : f32) {
	ma.sound_group_set_volume(&aud.music_group, linear_volume)
}

audio_apply_sound_volume :: proc(aud : ^Audio, linear_volume : f32) {
	ma.sound_group_set_volume(&aud.sound_group, linear_volume)
}