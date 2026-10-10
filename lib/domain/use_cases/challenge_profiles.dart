import '../models/challenge_brief.dart';

const trackProfiles = <TrackProfile>[
  TrackProfile(
    track: ChallengeTrack.metroOperations,
    label: 'Metro Operations',
    description: 'Support the people running stations, trains, and assets.',
    defaultCapabilities: {
      Capability.offlineCapture,
      Capability.recommendation,
      Capability.evidence,
      Capability.sharedSync,
    },
  ),
  TrackProfile(
    track: ChallengeTrack.cityPublicTransport,
    label: 'City Public Transport',
    description:
        'Connect Metro journeys with buses, roads, and the wider city.',
    defaultCapabilities: {
      Capability.offlineCapture,
      Capability.recommendation,
      Capability.advisory,
      Capability.sharedSync,
    },
  ),
];

TrackProfile profileFor(ChallengeTrack track) {
  return trackProfiles.firstWhere((profile) => profile.track == track);
}
