package com.example.buildify_flutter

import java.net.URI

/** Pure policy so navigation and media grants can be tested without a WebView. */
internal object VoiceCallPolicy {
    private fun uri(value: String): URI? = try { URI(value) } catch (_: Exception) { null }

    fun validInvitation(value: String): Boolean {
        val u = uri(value) ?: return false
        return u.scheme == "https" && (u.port == -1 || u.port == 443) &&
            u.rawUserInfo == null && u.rawPath == "/" && u.rawQuery == null &&
            Regex("[a-z0-9-]+\\.trycloudflare\\.com").matches(u.host ?: "") &&
            Regex("invite=[A-Za-z0-9_-]{43}").matches(u.rawFragment ?: "")
    }

    fun trustedOrigin(invitation: String, candidate: String): Boolean {
        val base = uri(invitation) ?: return false
        val u = uri(candidate) ?: return false
        return validInvitation(invitation) && u.scheme == "https" &&
            u.host == base.host && (u.port == -1 || u.port == 443) && u.rawUserInfo == null
    }

    fun allowedDocument(invitation: String, candidate: String): Boolean {
        val u = uri(candidate) ?: return false
        val base = uri(invitation) ?: return false
        return trustedOrigin(invitation, candidate) && u.rawPath == "/" &&
            u.rawQuery == null && (u.rawFragment == null || u.rawFragment == base.rawFragment)
    }

    fun allowMicrophone(invitation: String, origin: String, resources: List<String>, permissionGranted: Boolean): Boolean =
        permissionGranted && trustedOrigin(invitation, origin) && resources.isNotEmpty() &&
            resources.all { it == "android.webkit.resource.AUDIO_CAPTURE" }
}
