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
