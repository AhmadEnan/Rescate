// Tool schemas declared to Gemma 4 in the system turn.

import 'package:ai_inference/ai_inference.dart';

const ToolSchema getBiometricSchema = ToolSchema(
  name: 'get_biometric',
  description:
      "Take a live measurement of a vital using the phone's sensors. Asks the user for consent first.",
  args: <ToolArg>[
    ToolArg(
      name: 'metric',
      type: ToolArgType.string,
      description: 'Which vital to measure',
      enumValues: <String>[
        'heart_rate',
        'respiration',
        'spo2',
        'temperature',
        'pupillometry',
      ],
    ),
  ],
);

const ToolSchema requestHelpNearbySchema = ToolSchema(
  name: 'request_help_nearby',
  description:
      "Broadcast a short help-request over the local Bluetooth mesh to nearby phones.",
  args: <ToolArg>[
    ToolArg(
      name: 'case_summary',
      type: ToolArgType.string,
      description: 'Very short situation description (max 70 chars)',
    ),
    ToolArg(
      name: 'urgency',
      type: ToolArgType.string,
      description: 'How urgent',
      enumValues: <String>['critical', 'urgent', 'routine'],
    ),
  ],
);

const ToolSchema showCprTutorialSchema = ToolSchema(
  name: 'show_cpr_tutorial',
  description: "Show an 'Open CPR Tutorial' button below your reply.",
  args: <ToolArg>[],
);

const List<ToolSchema> kRescateTools = <ToolSchema>[
  getBiometricSchema,
  requestHelpNearbySchema,
  showCprTutorialSchema,
];

/// Tool declarations add prompt tokens and should only be sent when the user
/// is asking for an action the app can perform. Ordinary medical questions use
/// the plain generation path so the model can start evaluating sooner.
bool shouldUseRescateTools(String question) {
  final text = question.toLowerCase();
  const directToolRequests = <String>[
    'cpr tutorial',
    'show cpr',
    'open cpr',
    'nearby help',
    'send help',
    'request help',
    'إنعاش',
    'مساعدة قريبة',
    'ارسل مساعدة',
    'اطلب مساعدة',
  ];
  if (directToolRequests.any(text.contains)) return true;

  const measurementActions = <String>[
    'measure',
    'check my',
    'take my',
    'scan my',
    'read my',
    'قياس',
    'قس ',
    'افحص',
  ];
  const measurableVitals = <String>[
    'heart rate',
    'blood oxygen',
    'spo2',
    'pulse',
    'temperature',
    'respiration',
    'breathing rate',
    'vitals',
    'معدل النبض',
    'نبضي',
    'الأكسجين',
    'الاكسجين',
    'حرارتي',
    'تنفسي',
  ];
  return measurementActions.any(text.contains) &&
      measurableVitals.any(text.contains);
}
