// Tool schemas declared to Gemma 4 in the system turn.

import 'package:ai_inference/ai_inference.dart';

const ToolSchema getBiometricSchema = ToolSchema(
  name: 'get_biometric',
  description:
      "Ask the user (with a yes/no popup) to take a live measurement of the "
      "specified biometric using the phone's built-in sensors. Use this only "
      "when the metric would meaningfully change your next step. If the user "
      "declines, returns {declined:true}. If the device cannot measure it, "
      "returns {available:false}.",
  args: <ToolArg>[
    ToolArg(
      name: 'metric',
      type: ToolArgType.string,
      description: 'Which biometric to measure',
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
      "Broadcast a short help-request to every phone currently connected "
      "over the local Bluetooth mesh. Use when the user is in a real "
      "emergency and could benefit from a bystander. Returns "
      "{peers_messaged:N}; if N=0, no peers are connected.",
  args: <ToolArg>[
    ToolArg(
      name: 'case_summary',
      type: ToolArgType.string,
      description:
          'Very short description of the situation (will be truncated to 70 characters)',
    ),
    ToolArg(
      name: 'urgency',
      type: ToolArgType.string,
      description: 'How urgent the situation is',
      enumValues: <String>['critical', 'urgent', 'routine'],
    ),
  ],
);

const ToolSchema showCprTutorialSchema = ToolSchema(
  name: 'show_cpr_tutorial',
  description:
      "Surface an 'Open CPR Tutorial' button below your reply that, when "
      "tapped, opens the step-by-step CPR lesson. Use only when CPR is the "
      "indicated intervention right now. Returns {acknowledged:true} "
      "immediately so you can continue the answer.",
  args: <ToolArg>[],
);

const List<ToolSchema> kRescateTools = <ToolSchema>[
  getBiometricSchema,
  requestHelpNearbySchema,
  showCprTutorialSchema,
];
