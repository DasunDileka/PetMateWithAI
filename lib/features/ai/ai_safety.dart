/// Client-side safety guardrails for the PetMate assistant.
///
/// PetMate is a record-keeping and pattern-spotting tool, not a veterinarian.
/// Two layers enforce that:
///
///  1. **This file** — a deterministic pre-check. Requests that unambiguously
///     ask for a diagnosis, a prescription, or a dosage change are answered
///     locally with a fixed, safe response and never reach the model at all.
///     Being deterministic matters: a system prompt is a strong instruction but
///     not a guarantee, whereas a request that is never sent cannot produce an
///     unsafe answer. It is also cheaper and instant.
///
///  2. **The system prompt** (`ai_prompts.dart`) — governs everything that does
///     reach the model.
///
/// The filter is intentionally narrow. Over-blocking would make the assistant
/// useless for ordinary questions like "how often should I brush his coat?",
/// so only high-confidence clinical requests are intercepted.
library;

enum SafetyVerdict {
  /// Send to the model under the standard system prompt.
  allow,

  /// Send, but prepend an explicit reminder that a clinical question is in
  /// play and the answer must stay general and refer to a vet.
  cautious,

  /// Do not send. Answer locally with [AiSafety.clinicalRefusal].
  blocked,
}

class SafetyAssessment {
  const SafetyAssessment(this.verdict, {this.matched});

  final SafetyVerdict verdict;

  /// The phrase that triggered the classification, kept for the testing matrix
  /// so results are explainable rather than opaque.
  final String? matched;

  bool get isBlocked => verdict == SafetyVerdict.blocked;
}

class AiSafety {
  const AiSafety._();

  /// Direct requests for a diagnosis, a drug, or a dose change.
  static const List<String> _blockedPatterns = <String>[
    'what disease',
    'which disease',
    'what illness',
    'what is wrong with',
    "what's wrong with",
    'whats wrong with',
    'diagnose',
    'diagnosis',
    'does he have',
    'does she have',
    'does my pet have',
    'is it cancer',
    'is it parvo',
    'is it rabies',
    'what medicine should i give',
    'what medication should i give',
    'which medicine should i give',
    'what drug should i give',
    'how much medicine should i give',
    // Dosage requests phrased around a *named* drug slipped through the list
    // above, which only matched the generic words. "What dose of ibuprofen
    // should I give him" reached the model, and the deterministic layer is
    // meant to be what stops that rather than the model's own judgement.
    'what dose',
    "what's the dose",
    'whats the dose',
    'what dosage',
    'which dose',
    'how much should i give',
    'how many mg',
    'how much mg',
    'how many ml',
    'how many tablets',
    'how much can i give',
    'safe dose',
    'correct dose',
    'right dose',
    'human medicine',
    'ibuprofen',
    'paracetamol',
    'acetaminophen',
    'aspirin',
    'naproxen',
    'can i give him',
    'can i give her',
    'can i give my',
    'should i increase the dose',
    'should i decrease the dose',
    'increase the dosage',
    'decrease the dosage',
    'change the dose',
    'change the dosage',
    'double the dose',
    'stop the medication',
    'stop his medicine',
    'stop her medicine',
    'prescribe',
    'is this fatal',
    'will he die',
    'will she die',
    'is he dying',
    'is she dying',
  ];

  /// Symptom language: allowed, but the model is reminded to stay general and
  /// point at a vet.
  static const List<String> _cautiousPatterns = <String>[
    'vomit',
    'throwing up',
    'threw up',
    'diarrhea',
    'diarrhoea',
    'blood',
    'bleeding',
    'limp',
    'seizure',
    'fever',
    'not eating',
    "won't eat",
    'wont eat',
    'refusing food',
    'lethargic',
    'lethargy',
    'coughing',
    'sneezing',
    'swollen',
    'swelling',
    'rash',
    'itching',
    'scratching a lot',
    'breathing',
    'panting',
    'pain',
    'hurt',
    'injured',
    'wound',
    'poison',
    'ate something',
    'swallowed',
    'tick',
    'fleas',
    'worms',
    'unconscious',
    'collapsed',
  ];

  /// Emergencies: still blocked from model diagnosis, but answered with an
  /// urgent-care message rather than the standard refusal.
  static const List<String> _emergencyPatterns = <String>[
    'unconscious',
    'collapsed',
    'not breathing',
    "can't breathe",
    'cant breathe',
    'seizure',
    'poison',
    'antifreeze',
    'chocolate',
    'xylitol',
    'hit by a car',
    'bleeding heavily',
    'severe bleeding',
  ];

  static SafetyAssessment assess(String question) {
    final String q = question.toLowerCase().trim();
    if (q.isEmpty) return const SafetyAssessment(SafetyVerdict.allow);

    for (final String pattern in _emergencyPatterns) {
      if (q.contains(pattern)) {
        return SafetyAssessment(SafetyVerdict.blocked, matched: pattern);
      }
    }

    for (final String pattern in _blockedPatterns) {
      if (q.contains(pattern)) {
        return SafetyAssessment(SafetyVerdict.blocked, matched: pattern);
      }
    }

    for (final String pattern in _cautiousPatterns) {
      if (q.contains(pattern)) {
        return SafetyAssessment(SafetyVerdict.cautious, matched: pattern);
      }
    }

    return const SafetyAssessment(SafetyVerdict.allow);
  }

  static bool isEmergency(String question) {
    final String q = question.toLowerCase();
    return _emergencyPatterns.any(q.contains);
  }

  /// The fixed response returned for a blocked clinical request.
  static String clinicalRefusal(String petName) =>
      'I can share general pet-care information and tell you what your records '
      'show, but I cannot diagnose $petName, identify a condition, or advise on '
      'medication or dosages.\n\n'
      'If you are concerned about $petName, please contact a qualified '
      'veterinarian — they can examine $petName properly.\n\n'
      'I can still help you with things like what care is due today, what the '
      'records show over the past week, or preparing a summary of '
      '$petName\'s recent history to take to the appointment.';

  /// The response returned when the request looks like an emergency.
  static String emergencyResponse(String petName) =>
      '⚠️ This sounds like it could be urgent.\n\n'
      'Please contact a veterinarian or an emergency animal hospital about '
      '$petName straight away. I am not able to assess or treat a medical '
      'situation.\n\n'
      'If it helps while you arrange care, I can pull together a summary of '
      '$petName\'s recent records — recent feeding, activity, medication and '
      'vaccinations — for you to pass to the vet.';

  /// Extra instruction appended to the system prompt for cautious requests.
  static const String cautiousInstruction =
      'The user has mentioned a possible symptom. Do not speculate about causes '
      'or name any condition. Acknowledge the concern briefly, state plainly '
      'that you cannot assess it, recommend contacting a veterinarian, and then '
      'offer only what the recorded data shows and practical monitoring or '
      'record-keeping help.';
}
