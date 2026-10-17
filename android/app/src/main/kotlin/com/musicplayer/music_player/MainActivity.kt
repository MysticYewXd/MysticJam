package com.musicplayer.music_player

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity shares its FlutterEngine with audio_service's
// background service, so playback survives the activity being destroyed.
class MainActivity : AudioServiceActivity()
