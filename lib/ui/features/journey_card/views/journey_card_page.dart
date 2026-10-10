import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../../../domain/models/journey_data.dart';
import '../../../../domain/use_cases/connection_advisor.dart';
import '../../../../data/repositories/journey_sync_repository.dart';
import '../../../../data/repositories/ticket_repository.dart';
import '../view_models/journey_card_view_model.dart';
import 'journey_fare_card.dart';
import 'journey_planner_card.dart';
import 'journey_route_card.dart';

class JourneyCardPage extends StatefulWidget {
  const JourneyCardPage({
    super.key,
    this.userId,
    this.syncRepository,
    this.ticketRepository,
    this.accountRole = 'offline',
    this.onOpenAdmin,
    this.onLogout,
  });

  final String? userId;
  final JourneySyncRepository? syncRepository;
  final TicketRepository? ticketRepository;
  final String accountRole;
  final VoidCallback? onOpenAdmin;
  final VoidCallback? onLogout;

  @override
  State<JourneyCardPage> createState() => _JourneyCardPageState();
}

class _JourneyCardPageState extends State<JourneyCardPage> {
  late final JourneyCardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = JourneyCardViewModel(
      userId: widget.userId,
      syncRepository: widget.syncRepository,
    )..load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        if (_viewModel.isLoading) return const _LoadingView();
        if (_viewModel.error != null && _viewModel.seed == null) {
          return _ErrorView(message: _viewModel.error!);
        }
        return _JourneyContent(
          viewModel: _viewModel,
          ticketRepository: widget.ticketRepository,
          accountRole: widget.accountRole,
          onOpenAdmin: widget.onOpenAdmin,
          onLogout: widget.onLogout,
        );
      },
    );
  }
}

class _JourneyContent extends StatelessWidget {
  const _JourneyContent({
    required this.viewModel,
    required this.accountRole,
    required this.ticketRepository,
    this.onOpenAdmin,
    this.onLogout,
  });

  final JourneyCardViewModel viewModel;
  final String accountRole;
  final TicketRepository? ticketRepository;
  final VoidCallback? onOpenAdmin;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final padding = desktop ? 24.0 : 14.0;
        final railWidth = desktop ? 340.0 : double.infinity;
        return ColoredBox(
          color: theme.colorScheme.background,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        accountRole: accountRole,
                        onOpenAdmin: onOpenAdmin,
                        onLogout: onLogout,
                      ),
                      const SizedBox(height: 20),
                      if (desktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: JourneyRouteCard(
                                viewModel: viewModel,
                                expandedMap: true,
                              ),
                            ),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: railWidth,
                              child: _JourneyRail(
                                viewModel: viewModel,
                                ticketRepository: ticketRepository,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        JourneyPlannerCard(viewModel: viewModel),
                        const SizedBox(height: 14),
                        JourneyRouteCard(viewModel: viewModel),
                        const SizedBox(height: 14),
                        JourneyFareCard(
                          viewModel: viewModel,
                          ticketRepository: ticketRepository,
                        ),
                        const SizedBox(height: 14),
                        _DataNote(viewModel: viewModel),
                      ],
                      if (viewModel.error != null) ...[
                        const SizedBox(height: 14),
                        _InlineError(message: viewModel.error!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JourneyRail extends StatelessWidget {
  const _JourneyRail({required this.viewModel, required this.ticketRepository});
  final JourneyCardViewModel viewModel;
  final TicketRepository? ticketRepository;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      JourneyPlannerCard(viewModel: viewModel),
      const SizedBox(height: 14),
      JourneyFareCard(viewModel: viewModel, ticketRepository: ticketRepository),
      const SizedBox(height: 14),
      _DataNote(viewModel: viewModel),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.accountRole, this.onOpenAdmin, this.onLogout});
  final String accountRole;
  final VoidCallback? onOpenAdmin;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.train_rounded,
            color: theme.colorScheme.primaryForeground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MetroLink', style: theme.textTheme.h3),
              const SizedBox(height: 2),
              Text('One City, One Journey', style: theme.textTheme.muted),
            ],
          ),
        ),
        if (accountRole != 'offline') _AccountPill(role: accountRole),
        if (onOpenAdmin != null) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Open network control',
            onPressed: onOpenAdmin,
            icon: const Icon(Icons.admin_panel_settings_outlined, size: 21),
          ),
        ],
        if (onLogout != null)
          IconButton(
            tooltip: 'Log out',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, size: 21),
          ),
        if (accountRole == 'offline')
          const Icon(Icons.cloud_off_outlined, size: 20),
      ],
    );
  }
}

class _AccountPill extends StatelessWidget {
  const _AccountPill({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isOperator = role == 'operator';
    final color = isOperator
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: .55)),
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isOperator ? 'OPERATOR' : 'PASSENGER',
        style: theme.textTheme.small.copyWith(color: color),
      ),
    );
  }
}

// ignore: unused_element
class _InputCard extends StatelessWidget {
  const _InputCard({required this.viewModel, required this.hub});

  final JourneyCardViewModel viewModel;
  final JourneyHub hub;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Transfer details', style: theme.textTheme.h4),
      description: const Text('Adjust the planned interchange when needed.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Metro station', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            key: ValueKey('hub-${hub.id}'),
            initialValue: hub.id,
            minWidth: double.infinity,
            selectedOptionBuilder: (_, value) => Text(value),
            onChanged: (value) {
              if (value != null) viewModel.selectHub(value);
            },
            options: viewModel.seed!.hubs
                .map(
                  (item) => ShadOption(value: item.id, child: Text(item.name)),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          if (!hub.supportsScheduledTransfer)
            _UnavailableTransfer(hub: hub, link: viewModel.accessLink)
          else ...[
            _StopPicker(viewModel: viewModel),
            const SizedBox(height: 18),
            _TimePicker(viewModel: viewModel),
            const SizedBox(height: 18),
            _TransferAllowance(viewModel: viewModel),
            const SizedBox(height: 18),
            _RoutePicker(viewModel: viewModel),
          ],
        ],
      ),
    );
  }
}

class _StopPicker extends StatelessWidget {
  const _StopPicker({required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final stop = viewModel.selectedStop!;
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Boarding stop', style: theme.textTheme.small),
        const SizedBox(height: 6),
        ShadSelect<String>(
          key: ValueKey('stop-${stop.id}'),
          initialValue: stop.id,
          minWidth: double.infinity,
          selectedOptionBuilder: (_, value) => Text(value),
          onChanged: (value) {
            if (value != null) viewModel.selectStop(value);
          },
          options: viewModel.selectedHub!.candidateStops
              .map(
                (item) => ShadOption(
                  value: item.id,
                  child: Text(
                    '${item.name}  ·  ${item.directDistanceMeters} m',
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _TimePicker extends StatelessWidget {
  const _TimePicker({required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reach street level at', style: theme.textTheme.small),
        const SizedBox(height: 6),
        ShadInput(
          key: ValueKey('arrival-${viewModel.arrivalTime}'),
          initialValue: viewModel.arrivalTime,
          placeholder: const Text('17:48'),
          keyboardType: TextInputType.datetime,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
          ],
          onSubmitted: viewModel.setArrivalTime,
          onEditingComplete: () {},
        ),
      ],
    );
  }
}

class _TransferAllowance extends StatelessWidget {
  const _TransferAllowance({required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Transfer allowance', style: theme.textTheme.small),
            const Spacer(),
            Text(
              '${viewModel.transferMinutes} min',
              style: theme.textTheme.small,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ShadSlider(
          key: ValueKey('transfer-${viewModel.transferMinutes}'),
          initialValue: viewModel.transferMinutes.toDouble(),
          min: 3,
          max: 20,
          divisions: 17,
          onChanged: viewModel.setTransferMinutes,
        ),
        const SizedBox(height: 6),
        Text(
          'Adjust for crowds, exits, or luggage.',
          style: theme.textTheme.muted,
        ),
      ],
    );
  }
}

class _RoutePicker extends StatelessWidget {
  const _RoutePicker({required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final route = viewModel.selectedRoute!;
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bus direction', style: theme.textTheme.small),
        const SizedBox(height: 6),
        ShadSelect<String>(
          key: ValueKey('route-${route.id}'),
          initialValue: route.id,
          minWidth: double.infinity,
          maxHeight: 300,
          selectedOptionBuilder: (_, value) => Text(_routeLabel(route)),
          onChanged: (value) {
            if (value != null) viewModel.selectRoute(value);
          },
          options: viewModel.routeOptions
              .map(
                (item) =>
                    ShadOption(value: item.id, child: Text(_routeLabel(item))),
              )
              .toList(),
        ),
      ],
    );
  }
}

String _routeLabel(BusRoute route) =>
    '${route.shortName} · ${route.longName.isEmpty ? route.agency : route.longName}';

// ignore: unused_element
class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.viewModel, required this.hub});

  final JourneyCardViewModel viewModel;
  final JourneyHub hub;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (!hub.supportsScheduledTransfer) {
      return ShadCard(
        title: Text('Connection status', style: theme.textTheme.h4),
        child: _UnavailableTransfer(hub: hub, link: viewModel.accessLink),
      );
    }
    final decision = viewModel.decision!;
    final route = viewModel.selectedRoute!;
    final trip = decision.firstCatchable;
    final isMiss = decision.missesNext;
    return ShadCard(
      title: Text('Connection check', style: theme.textTheme.h4),
      description: const Text('Cached schedule. Not live vehicle tracking.'),
      child: trip == null
          ? Text(
              'No later scheduled trip for this direction is present in the offline reference.',
              style: theme.textTheme.muted,
            )
          : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        (isMiss
                                ? theme.colorScheme.destructive
                                : theme.colorScheme.primary)
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMiss
                          ? theme.colorScheme.destructive
                          : theme.colorScheme.primary,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isMiss
                            ? Icons.schedule_rounded
                            : Icons.check_circle_outline_rounded,
                        color: isMiss
                            ? theme.colorScheme.destructive
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isMiss ? 'Take the fallback' : 'You can make this bus',
                        style: theme.textTheme.large,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${route.shortName} toward ${trip.headsign}',
                        style: theme.textTheme.muted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        formatClockMinutes(clockMinutes(trip.time)),
                        style: theme.textTheme.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reach the stop by ${formatClockMinutes(decision.readyAtMinutes)}',
                        style: theme.textTheme.small,
                      ),
                      if (isMiss) ...[
                        const SizedBox(height: 12),
                        Text(
                          'The ${formatClockMinutes(clockMinutes(decision.nextScheduled!.time))} scheduled trip leaves before your transfer allowance ends.',
                          style: theme.textTheme.small,
                        ),
                      ],
                    ],
                  ),
                )
                .animate(key: ValueKey('${trip.tripId}-$isMiss'))
                .fadeIn(duration: 220.ms)
                .slideY(begin: 0.03),
    );
  }
}

class _UnavailableTransfer extends StatelessWidget {
  const _UnavailableTransfer({required this.hub, required this.link});

  final JourneyHub hub;
  final AccessLink? link;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accessLink = link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          color: theme.colorScheme.mutedForeground,
        ),
        const SizedBox(height: 10),
        Text(hub.availability, style: theme.textTheme.muted),
        if (accessLink != null) ...[
          const SizedBox(height: 16),
          Text('Verified onward link', style: theme.textTheme.large),
          const SizedBox(height: 6),
          Text(
            '${accessLink.destination} · ${accessLink.distanceMeters} m',
            style: theme.textTheme.small,
          ),
          const SizedBox(height: 4),
          Text(accessLink.description, style: theme.textTheme.muted),
        ],
      ],
    );
  }
}

// ignore: unused_element
class _DepartureChart extends StatelessWidget {
  const _DepartureChart({required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Scheduled departures nearby', style: theme.textTheme.h4),
      description: Text(
        'All cached departures at ${viewModel.selectedStop!.name}.',
      ),
      child: SizedBox(
        height: 180,
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          primaryXAxis: CategoryAxis(
            majorGridLines: const MajorGridLines(width: 0),
            labelStyle: theme.textTheme.small,
          ),
          primaryYAxis: NumericAxis(
            isVisible: false,
            majorGridLines: const MajorGridLines(width: 0),
          ),
          series: <CartesianSeries<DepartureBucket, String>>[
            ColumnSeries<DepartureBucket, String>(
              dataSource: viewModel.departureBuckets,
              xValueMapper: (item, _) => item.label,
              yValueMapper: (item, _) => item.count,
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              dataLabelSettings: const DataLabelSettings(isVisible: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataNote extends StatelessWidget {
  const _DataNote({required this.viewModel});

  final JourneyCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final busSource = viewModel.seed!.sources['busSchedule']!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.offline_bolt_outlined,
          size: 18,
          color: theme.colorScheme.mutedForeground,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$busSource. Works without a connection.',
            style: theme.textTheme.muted,
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(message)));
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Text(message);
}
