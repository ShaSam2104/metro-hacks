enum ChallengeTrack { metroOperations, cityPublicTransport }

enum Capability {
  offlineCapture,
  recommendation,
  advisory,
  evidence,
  sharedSync,
}

class ChallengeBrief {
  const ChallengeBrief({
    required this.id,
    required this.title,
    required this.track,
    required this.problem,
    required this.requiredCapabilities,
  });

  final String id;
  final String title;
  final ChallengeTrack track;
  final String problem;
  final Set<Capability> requiredCapabilities;
}

class TrackProfile {
  const TrackProfile({
    required this.track,
    required this.label,
    required this.description,
    required this.defaultCapabilities,
  });

  final ChallengeTrack track;
  final String label;
  final String description;
  final Set<Capability> defaultCapabilities;
}
