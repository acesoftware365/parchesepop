package com.liisgo.parchesepop

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var backgroundMusic: MediaPlayer? = null
    private var effectPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.liisgo.parchesepop/sounds"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setMusicEnabled" -> {
                    if (call.argument<Boolean>("enabled") == true) {
                        playBackgroundMusic()
                    } else {
                        backgroundMusic?.pause()
                    }
                    result.success(null)
                }
                "playEffect" -> {
                    call.argument<String>("asset")?.let(::playEffect)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openAsset(name: String) =
        assets.openFd("flutter_assets/assets/sounds/$name")

    private fun playBackgroundMusic() {
        if (backgroundMusic?.isPlaying == true) return
        try {
            backgroundMusic?.release()
            openAsset("background_music.wav").use { asset ->
                backgroundMusic = MediaPlayer().apply {
                    setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
                    isLooping = true
                    setVolume(.42f, .42f)
                    prepare()
                    start()
                }
            }
        } catch (_: Exception) {
            backgroundMusic = null
        }
    }

    private fun playEffect(name: String) {
        try {
            effectPlayer?.release()
            openAsset(name).use { asset ->
                effectPlayer = MediaPlayer().apply {
                    setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
                    setVolume(.82f, .82f)
                    setOnCompletionListener { it.release() }
                    prepare()
                    start()
                }
            }
        } catch (_: Exception) {
            effectPlayer = null
        }
    }

    override fun onDestroy() {
        backgroundMusic?.release()
        effectPlayer?.release()
        super.onDestroy()
    }
}
