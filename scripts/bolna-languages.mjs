// Keep the complete Buildify tool/approval policy in every language prompt.
export const buildifyLanguages = ['en', 'te', 'hi'];

export function buildifyMultilingualConfig(systemPrompt, englishSpeech) {
  return {
    enabled: true,
    active_language: 'en',
    language_switch_trigger: 'requested_or_auto_detected',
    languages: {
      en: {
        ...structuredClone(englishSpeech),
        system_prompt: systemPrompt,
        agent_name: 'Buildify',
        handoff_message: 'Sure, we can speak in English.',
      },
      hi: {
        transcriber: {
          provider: 'sarvam', model: 'saaras:v4', language: 'hi',
          stream: true, encoding: 'linear16', sampling_rate: 16000, endpointing: 500,
        },
        synthesizer: {
          provider: 'sarvam',
          provider_config: { voice: 'Priya', voice_id: 'priya', model: 'bulbul:v3', language: 'hi-IN' },
          stream: true, buffer_size: 250, audio_format: 'wav',
        },
        system_prompt: systemPrompt + '\n\nआप Buildify सहायक हैं। सहज हिंदी में एक या दो छोटे वाक्यों में जवाब दें। उपयोगकर्ता के English तकनीकी शब्द इस्तेमाल कर सकते हैं। मॉडल के नाम, tool के नाम और IDs न बदलें। ऊपर दिए सभी tool, सुरक्षा, अनुमति और ईमेल नियम हिंदी में भी लागू हैं। प्लान तैयार होने के बाद उसका विवरण हिंदी में बताकर स्पष्ट अनुमति माँगें। उपयोगकर्ता उस प्लान के लिए “शुरू करें” या “मैं मंज़ूरी देता हूँ” कहे तो उसे Go जैसी स्पष्ट अनुमति मानें। Tool का परिणाम मिलने से पहले काम पूरा होने या ईमेल भेजे जाने का दावा न करें।',
        agent_name: 'Buildify',
        handoff_message: 'ठीक है, हिंदी में बात करते हैं।',
        welcome_message: 'नमस्ते! मैं Buildify सहायक हूँ। मॉडल शुरू करने, रोकने या उसकी स्थिति जानने में आपकी मदद कर सकता हूँ।',
      },
      te: {
        transcriber: {
          provider: 'sarvam', model: 'saaras:v4', language: 'te',
          stream: true, encoding: 'linear16', sampling_rate: 16000, endpointing: 500,
        },
        synthesizer: {
          provider: 'sarvam',
          provider_config: { voice: 'Priya', voice_id: 'priya', model: 'bulbul:v3', language: 'te-IN' },
          stream: true, buffer_size: 250, audio_format: 'wav',
        },
        system_prompt: systemPrompt + '\n\nమీరు Buildify సహాయకులు. సహజమైన తెలుగులో ఒకటి లేదా రెండు చిన్న వాక్యాలతో మాట్లాడండి. వినియోగదారు వాడే English సాంకేతిక పదాలను అలాగే వాడవచ్చు. మోడల్ పేర్లు, tool పేర్లు, IDs మార్చవద్దు. పైన ఉన్న అన్ని tool, భద్రత, ఆమోదం, ఇమెయిల్ నియమాలు తెలుగులోనూ వర్తిస్తాయి. ప్లాన్ సిద్ధమైన తర్వాత వివరాలు తెలుగులో చెప్పి స్పష్టమైన ఆమోదం అడగండి. వినియోగదారు “ప్రారంభించండి” లేదా “ఆమోదిస్తున్నాను” అని ఆ ప్లాన్‌కు స్పష్టంగా అనుమతి ఇస్తే అది Go అన్నట్టే పరిగణించండి. Tool ఫలితం రాకముందు పని పూర్తయిందని లేదా ఇమెయిల్ పంపామని చెప్పవద్దు.',
        agent_name: 'Buildify',
        handoff_message: 'సరే, తెలుగులో మాట్లాడుకుందాం.',
        welcome_message: 'నమస్కారం! నేను Buildify సహాయకుడిని. మోడల్ ప్రారంభించడం, ఆపడం లేదా స్థితి తెలుసుకోవడంలో సహాయం చేయగలను.',
      },
    },
  };
}
