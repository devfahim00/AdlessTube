package com.devfahim00.tube

import android.content.res.Configuration
import com.ryanheise.audioservice.AudioServiceActivity
import com.thesparks.android_pip.PipCallbackHelper
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private val pipCallbackHelper = PipCallbackHelper()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipCallbackHelper.configureFlutterEngine(flutterEngine)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipCallbackHelper.onPictureInPictureModeChanged(
            isInPictureInPictureMode,
            this
        )
    }
}
