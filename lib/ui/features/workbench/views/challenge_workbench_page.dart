import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../domain/models/challenge_brief.dart';
import '../view_models/challenge_workbench_view_model.dart';

class ChallengeWorkbenchPage extends StatefulWidget {
  const ChallengeWorkbenchPage({super.key});

  @override
  State<ChallengeWorkbenchPage> createState() => _ChallengeWorkbenchPageState();
}

class _ChallengeWorkbenchPageState extends State<ChallengeWorkbenchPage> {
  final _viewModel = ChallengeWorkbenchViewModel();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final profile = _viewModel.selectedProfile;

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metro Hacks', style: theme.textTheme.h1),
                  const SizedBox(height: 8),
                  Text(
                    'A configurable offline-first workbench for the brief you receive on the train.',
                    style: theme.textTheme.muted,
                  ),
                  const SizedBox(height: 32),
                  Text('Select the brief track', style: theme.textTheme.h4),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: ChallengeTrack.values.map((track) {
                      final isSelected = track == _viewModel.selectedTrack;
                      final label = track == ChallengeTrack.metroOperations
                          ? 'Metro Operations'
                          : 'City Public Transport';
                      return ShadButton(
                        onPressed: () =>
                            setState(() => _viewModel.selectTrack(track)),
                        child: Text(isSelected ? '$label selected' : label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _ProfileCard(profile: profile)
                          .animate(key: ValueKey(profile.track))
                          .fadeIn(duration: 220.ms)
                          .slideY(begin: 0.04, end: 0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final TrackProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text(profile.label, style: theme.textTheme.h3),
      description: Text(profile.description),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reusable capabilities', style: theme.textTheme.large),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: profile.defaultCapabilities
                .map((capability) => _CapabilityChip(label: capability.label))
                .toList(),
          ),
          const SizedBox(height: 24),
          Text('Brief intake', style: theme.textTheme.large),
          const SizedBox(height: 8),
          Text(
            'When the organisers reveal a problem, add its actor, decision, signal, and expected outcome. The selected module then uses only the capabilities it needs.',
            style: theme.textTheme.muted,
          ),
        ],
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.small),
    );
  }
}

extension on Capability {
  String get label => switch (this) {
    Capability.offlineCapture => 'Offline capture',
    Capability.recommendation => 'Recommendation',
    Capability.advisory => 'Passenger advisory',
    Capability.evidence => 'Evidence log',
    Capability.sharedSync => 'Shared sync',
  };
}
