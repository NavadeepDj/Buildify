package com.example.buildify_flutter

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.net.http.SslError
import android.os.Message
import android.view.View
import android.webkit.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** No provider key or Buildify action authority is exposed to the page. */
class VoiceCallViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val calls = mutableSetOf<VoiceCallView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // Only one microphone owner, even during a rapid route replacement.
        endAll()
        val url = (args as? Map<*, *>)?.get("url") as? String ?: ""
        return try {
            val uri = Uri.parse(url)
            require(validInvitation(uri)) { "Invalid call invitation" }
            VoiceCallView(activity, messenger, viewId, uri) { calls.remove(it) }
                .also { calls.add(it) }
        } catch (_: Exception) {
            UnavailableVoiceCallView(context, messenger, viewId)
        }
    }

    fun endAll() = calls.toList().forEach { it.end() }

    companion object {
        fun validInvitation(uri: Uri): Boolean = VoiceCallPolicy.validInvitation(uri.toString())
    }
}

private class UnavailableVoiceCallView(context: Context, messenger: BinaryMessenger, id: Int) : PlatformView {
    private val label = android.widget.TextView(context).apply { text = "The Android call screen is unavailable. Update Android System WebView and retry." }
    private val channel = MethodChannel(messenger, "buildify.ai/voice-call/$id")
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> result.success(mapOf("error" to "webview_unavailable"))
                "end" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
    override fun getView(): View = label
    override fun dispose() { channel.setMethodCallHandler(null) }
}

@SuppressLint("SetJavaScriptEnabled")
class VoiceCallView(
    private val activity: Activity,
    messenger: BinaryMessenger,
    id: Int,
    private val invitation: Uri,
    private val removed: (VoiceCallView) -> Unit,
) : PlatformView {
    private val web = WebView(activity)
    private val channel = MethodChannel(messenger, "buildify.ai/voice-call/$id")
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var ended = false
    private var destroyed = false
    private var ownsFocus = false
    private var previousMode = AudioManager.MODE_NORMAL
    private var pageReady = false
    private var lastError: String? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0) web.post { fail("audio_interrupted") }
    }

    private fun allowedDocument(uri: Uri): Boolean =
        VoiceCallPolicy.allowedDocument(invitation.toString(), uri.toString())

    init {
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setSupportMultipleWindows(false)
            javaScriptCanOpenWindowsAutomatically = false
            cacheMode = WebSettings.LOAD_NO_CACHE
        }
        web.setDownloadListener { _, _, _, _, _ -> fail("navigation_blocked") }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                if (!ended && VoiceCallPolicy.allowMicrophone(invitation.toString(),
                    request.origin.toString(), request.resources.toList(),
                    activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) &&
                    acquireAudio()) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else {
                    request.deny()
                    fail("microphone_unavailable")
                }
            }

            override fun onCreateWindow(view: WebView?, dialog: Boolean, gesture: Boolean, result: Message?): Boolean = false
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (ended) return true
                if (!request.isForMainFrame || !allowedDocument(request.url)) {
                    fail("navigation_blocked")
                    return true
                }
                return false
            }

            @Deprecated("Legacy WebView callback")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                if (ended) return true
                if (url == null || !allowedDocument(Uri.parse(url))) {
                    fail("navigation_blocked")
                    return true
                }
                return false
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                if (!ended && (url == null || !allowedDocument(Uri.parse(url)))) fail("navigation_blocked")
            }

            override fun onPageFinished(view: WebView, url: String?) {
                if (!ended && url != null && allowedDocument(Uri.parse(url))) {
                    // Existing helper pages expose a disabled stop button when no
                    // call remains. These events manage audio focus only; they
                    // cannot grant capture or invoke a Buildify operation.
                    web.evaluateJavascript("""
                        (() => {
                          const stop = document.getElementById('stop');
                          if (!stop || window.buildifyMediaObserver) return;
                          window.buildifyMediaObserver = new MutationObserver(() => {
                            if (stop.disabled) window.BuildifyVoiceMedia.finished();
                            else window.BuildifyVoiceMedia.connecting();
                          });
                          window.buildifyMediaObserver.observe(stop, {attributes:true, attributeFilter:['disabled']});
                        })();
                    """.trimIndent(), null)
                    channel.invokeMethod("ready", null)
                    pageReady = true
                }
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) fail("connection_failed")
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame) fail("connection_failed")
            }

            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler, error: SslError?) {
                handler.cancel()
                fail("connection_failed")
            }

            override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean {
                fail("webview_unavailable")
                (web.parent as? android.view.ViewGroup)?.removeView(web)
                dispose()
                return true
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "end" -> { end(); result.success(null) }
                "getState" -> result.success(mapOf("ready" to pageReady, "ended" to ended, "error" to lastError))
                else -> result.notImplemented()
            }
        }
        web.addJavascriptInterface(object {
            @JavascriptInterface
            fun connecting() {
                web.post {
                    if (!ended && web.url?.let { allowedDocument(Uri.parse(it)) } == true &&
                        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED &&
                        !acquireAudio()) fail("audio_interrupted")
                }
            }

            @JavascriptInterface
            fun finished() {
                web.post {
                    if (!ended && web.url?.let { allowedDocument(Uri.parse(it)) } == true) releaseAudio()
                }
            }
        }, "BuildifyVoiceMedia")
        web.loadUrl(invitation.toString())
    }

    @Suppress("DEPRECATION")
    private fun acquireAudio(): Boolean {
        if (ownsFocus) return true
        if (audio.requestAudioFocus(focusListener, AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return false
        ownsFocus = true
        previousMode = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        return true
    }

    private fun fail(code: String) {
        if (ended) return
        lastError = code
        channel.invokeMethod("error", code) // Fixed codes only; never URLs or credentials.
        end()
    }

    @Suppress("DEPRECATION")
    private fun releaseAudio() {
        if (ownsFocus) {
            audio.mode = previousMode
            audio.abandonAudioFocus(focusListener)
            ownsFocus = false
        }
    }

    fun end() {
        if (ended) return
        ended = true
        // The call page already cancels in-flight mints and stops its SDK on pagehide.
        try {
            web.evaluateJavascript("window.dispatchEvent(new Event('pagehide'));", null)
            web.stopLoading()
            web.loadUrl("about:blank")
            web.onPause()
        } catch (_: Exception) {
            // A crashed renderer is disposed by onRenderProcessGone.
        }
        releaseAudio()
        channel.invokeMethod("ended", null)
    }

    override fun getView(): View = web

    override fun dispose() {
        if (destroyed) return
        end()
        destroyed = true
        channel.setMethodCallHandler(null)
        web.removeJavascriptInterface("BuildifyVoiceMedia")
        web.removeAllViews()
        web.destroy()
        removed(this)
    }
}
