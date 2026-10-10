import 'package:flutter_test/flutter_test.dart';
import 'package:metro_hacks/domain/models/challenge_brief.dart';
import 'package:metro_hacks/domain/use_cases/challenge_profiles.dart';

void main() {
  test('city public transport supports passenger advisories', () {
    final profile = profileFor(ChallengeTrack.cityPublicTransport);

    expect(profile.defaultCapabilities, contains(Capability.advisory));
  });

  test('metro operations supports evidence logging', () {
    final profile = profileFor(ChallengeTrack.metroOperations);

    expect(profile.defaultCapabilities, contains(Capability.evidence));
  });
}
