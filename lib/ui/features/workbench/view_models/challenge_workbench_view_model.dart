import '../../../../domain/models/challenge_brief.dart';
import '../../../../domain/use_cases/challenge_profiles.dart';

class ChallengeWorkbenchViewModel {
  ChallengeWorkbenchViewModel({
    ChallengeTrack initialTrack = ChallengeTrack.cityPublicTransport,
  }) : _selectedTrack = initialTrack;

  ChallengeTrack _selectedTrack;

  ChallengeTrack get selectedTrack => _selectedTrack;
  TrackProfile get selectedProfile => profileFor(_selectedTrack);

  void selectTrack(ChallengeTrack track) {
    _selectedTrack = track;
  }
}
