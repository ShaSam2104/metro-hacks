import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../view_models/journey_card_view_model.dart';

class JourneyPlannerCard extends StatefulWidget {
  const JourneyPlannerCard({super.key, required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  State<JourneyPlannerCard> createState() => _JourneyPlannerCardState();
}

class _JourneyPlannerCardState extends State<JourneyPlannerCard> {
  var _originQuery = '';
  var _destinationQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final viewModel = widget.viewModel;
    return ShadCard(
      title: Text('Plan your journey', style: theme.textTheme.h4),
      description: const Text(
        'Choose where you start, where you are going, and what matters most.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start area', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>.withSearch(
            key: ValueKey('origin-${viewModel.originId}'),
            initialValue: viewModel.originId,
            minWidth: 280,
            maxHeight: 320,
            searchPlaceholder: const Text('Search area or station'),
            onSearchChanged: (value) => setState(() => _originQuery = value),
            selectedOptionBuilder: (_, value) => Text(viewModel.originName),
            onChanged: (value) {
              if (value != null) viewModel.selectOrigin(value);
            },
            options: _filtered(viewModel.journeyOrigins, _originQuery)
                .map(
                  (place) => ShadOption(
                    value: place.id,
                    child: Text(place.selectionLabel),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Text('First vehicle', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            key: ValueKey('boarding-${viewModel.boardingMode}'),
            initialValue: viewModel.boardingMode ?? 'Any enabled service',
            minWidth: 280,
            selectedOptionBuilder: (_, value) => Text(value),
            onChanged: (value) {
              if (value != null) viewModel.selectBoardingMode(value);
            },
            options: viewModel.boardingModes
                .map((mode) => ShadOption(value: mode, child: Text(mode)))
                .toList(),
          ),
          const SizedBox(height: 14),
          Text('Go to', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>.withSearch(
            key: ValueKey('destination-${viewModel.destinationId}'),
            initialValue: viewModel.destinationId,
            minWidth: 280,
            maxHeight: 320,
            searchPlaceholder: const Text('Search area or station'),
            onSearchChanged: (value) =>
                setState(() => _destinationQuery = value),
            selectedOptionBuilder: (_, value) =>
                Text(viewModel.destinationName),
            onChanged: (value) {
              if (value != null) viewModel.selectDestination(value);
            },
            options: _filtered(viewModel.journeyDestinations, _destinationQuery)
                .map(
                  (place) => ShadOption(
                    value: place.id,
                    child: Text(place.selectionLabel),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Text('Final stop', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            key: ValueKey('final-${viewModel.finalMode}'),
            initialValue: viewModel.finalMode ?? 'Any enabled service',
            minWidth: 280,
            selectedOptionBuilder: (_, value) => Text(value),
            onChanged: (value) {
              if (value != null) viewModel.selectFinalMode(value);
            },
            options: viewModel.finalModes
                .map((mode) => ShadOption(value: mode, child: Text(mode)))
                .toList(),
          ),
          const SizedBox(height: 14),
          Text('Leave at', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadInput(
            key: ValueKey('departure-${viewModel.departureTime}'),
            initialValue: viewModel.departureTime,
            placeholder: const Text('17:48'),
            keyboardType: TextInputType.datetime,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
            ],
            onSubmitted: viewModel.setDepartureTime,
          ),
          const SizedBox(height: 14),
          Text('Prioritize', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            key: ValueKey('preference-${viewModel.preference}'),
            initialValue: viewModel.preference,
            minWidth: 280,
            selectedOptionBuilder: (_, value) => Text(viewModel.preference),
            onChanged: (value) {
              if (value != null) viewModel.selectPreference(value);
            },
            options: JourneyCardViewModel.journeyPreferences
                .map((value) => ShadOption(value: value, child: Text(value)))
                .toList(),
          ),
          const SizedBox(height: 18),
          Text('Use these services', style: theme.textTheme.small),
          const SizedBox(height: 6),
          _ModeOption(
            label: 'Metro',
            color: const Color(0xff1976d2),
            enabled: viewModel.usesMode('Metro'),
            onChanged: (value) => viewModel.toggleMode('Metro', value),
          ),
          _ModeOption(
            label: 'AMTS buses',
            color: const Color(0xff00897b),
            enabled: viewModel.usesMode('AMTS'),
            onChanged: (value) => viewModel.toggleMode('AMTS', value),
          ),
          _ModeOption(
            label: 'BRTS buses',
            color: const Color(0xfff57c00),
            enabled: viewModel.usesMode('BRTS'),
            onChanged: (value) => viewModel.toggleMode('BRTS', value),
          ),
          const SizedBox(height: 14),
          Text(
            'The route can start, transfer, or finish on any selected service.',
            style: theme.textTheme.muted,
          ),
        ],
      ),
    );
  }

  List<dynamic> _filtered(List<dynamic> places, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return places;
    return places
        .where(
          (place) => place.selectionLabel.toLowerCase().contains(normalized),
        )
        .toList();
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ShadCheckbox(
    value: enabled,
    color: color,
    onChanged: onChanged,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}
