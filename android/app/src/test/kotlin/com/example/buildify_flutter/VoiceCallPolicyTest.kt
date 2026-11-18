package com.example.buildify_flutter

import org.junit.Assert.*
import org.junit.Test

class VoiceCallPolicyTest {
    private val origin = "https://paired-host.trycloudflare.com"
    private val invitation = "$origin/#invite=${"a".repeat(43)}"
    private val audio = "android.webkit.resource.AUDIO_CAPTURE"

    @Test fun invitationsAreStrict() {
        assertTrue(VoiceCallPolicy.validInvitation(invitation))
        for (url in listOf("http://paired-host.trycloudflare.com/#invite=${"a".repeat(43)}",
            "$origin/", "$origin/other#invite=${"a".repeat(43)}",
            invitation.replace("https://", "https://user@"),
            invitation.replace(".com/", ".com:444/"), invitation.replace("/#", "/?extra=1#"))) {
            assertFalse(url, VoiceCallPolicy.validInvitation(url))
        }
    }

    @Test fun navigationCannotChangeOriginOrInvitation() {
        assertTrue(VoiceCallPolicy.allowedDocument(invitation, invitation))
        assertTrue(VoiceCallPolicy.allowedDocument(invitation, "$origin/"))
        for (url in listOf("https://other.trycloudflare.com/", "$origin.evil.test/",
            "$origin/session", "$origin/?redirect=1", "$origin/#invite=${"b".repeat(43)}",
            "javascript:alert(1)", "intent://call", "file:///data/local/tmp/page")) {
            assertFalse(url, VoiceCallPolicy.allowedDocument(invitation, url))
        }
    }

    @Test fun microphoneNeedsExactOriginRuntimePermissionAndAudioOnly() {
        assertTrue(VoiceCallPolicy.allowMicrophone(invitation, origin, listOf(audio), true))
        assertFalse(VoiceCallPolicy.allowMicrophone(invitation, origin, listOf(audio), false))
        assertFalse(VoiceCallPolicy.allowMicrophone(invitation, "https://other.trycloudflare.com", listOf(audio), true))
        assertFalse(VoiceCallPolicy.allowMicrophone(invitation, origin, emptyList(), true))
        assertFalse(VoiceCallPolicy.allowMicrophone(invitation, origin, listOf(audio, "android.webkit.resource.VIDEO_CAPTURE"), true))
        assertFalse(VoiceCallPolicy.allowMicrophone(invitation, origin, listOf("new-resource"), true))
    }
}
