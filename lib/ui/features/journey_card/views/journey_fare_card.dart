import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../data/repositories/ticket_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/services/ticket_pdf_service.dart';
import '../view_models/journey_card_view_model.dart';

class JourneyFareCard extends StatefulWidget {
  const JourneyFareCard({
    super.key,
    required this.viewModel,
    required this.ticketRepository,
  });

  final JourneyCardViewModel viewModel;
  final TicketRepository? ticketRepository;

  @override
  State<JourneyFareCard> createState() => _JourneyFareCardState();
}

class _JourneyFareCardState extends State<JourneyFareCard> {
  final _riderController = TextEditingController();
  List<TicketOrder> _orders = const [];
  var _forSomeoneElse = false;
  var _isIssuing = false;
  var _isLoadingHistory = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _riderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final viewModel = widget.viewModel;
    return ShadCard(
      title: Text('Ticket-ready journey card', style: theme.textTheme.h4),
      description: const Text('Offline fare estimate for the selected route.'),
      child: Column(
        children: [
          ...viewModel.fareLegs.expand(
            (leg) => [
              _FareRow(
                label: '${leg.mode} ${leg.route?.shortName ?? 'leg'}',
                amount: leg.fare,
              ),
              const SizedBox(height: 10),
            ],
          ),
          const Divider(height: 24),
          _FareRow(
            label: 'One passenger total',
            amount: viewModel.totalFareEstimate,
            emphasized: true,
          ),
          const SizedBox(height: 12),
          Text(
            '${viewModel.estimatedTotalMinutes} min total · ${viewModel.totalWalkingMinutes} min walking · ${viewModel.routeTransfers} interchange${viewModel.routeTransfers == 1 ? '' : 's'}',
            style: theme.textTheme.small,
          ),
          const SizedBox(height: 6),
          Text(
            'Metro Blue Line uses the bundled GMRC token OD matrix. AMTS/BRTS fallback: Rs 2/km, Rs 5 minimum, Rs 30 cap.',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 6),
          ShadCheckbox(
            value: _forSomeoneElse,
            onChanged: (value) => setState(() => _forSomeoneElse = value),
            label: const Text('Issue this ticket for someone else'),
          ),
          if (_forSomeoneElse) ...[
            const SizedBox(height: 10),
            ShadInput(
              controller: _riderController,
              placeholder: const Text('Rider full name'),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              onPressed: _isIssuing ? null : _issueOrder,
              child: _isIssuing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Issue journey pass'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, style: theme.textTheme.small),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('Ticket wallet', style: theme.textTheme.large),
              ),
              IconButton(
                tooltip: 'Refresh ticket wallet',
                onPressed: _isLoadingHistory ? null : _loadHistory,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_isLoadingHistory)
            const LinearProgressIndicator()
          else if (_orders.isEmpty)
            Text('No issued journey passes yet.', style: theme.textTheme.muted)
          else
            ..._orders
                .take(3)
                .map(
                  (order) => _TicketOrderRow(
                    order,
                    onDownload: () => _downloadPass(order),
                  ),
                ),
          const SizedBox(height: 10),
          Text(
            'This creates an account-owned demo pass with a route snapshot. It does not charge a card or issue a live operator QR ticket.',
            style: theme.textTheme.muted,
          ),
        ],
      ),
    );
  }

  Future<void> _loadHistory() async {
    final repository = widget.ticketRepository;
    if (repository == null) return;
    setState(() => _isLoadingHistory = true);
    try {
      final orders = await repository.listOrders();
      if (mounted) setState(() => _orders = orders);
    } catch (_) {
      // The issue action provides a direct error if an account is unavailable.
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _issueOrder() async {
    final repository = widget.ticketRepository;
    final journey = widget.viewModel.routedJourney;
    if (repository == null || journey == null) {
      setState(
        () => _message = 'Sign in and calculate a route before issuing a pass.',
      );
      return;
    }
    final session = repository.authRepository.session.value;
    final rider = _forSomeoneElse
        ? _riderController.text.trim()
        : session?.username ?? '';
    if (rider.length < 2) {
      setState(() => _message = 'Enter the rider name for this journey pass.');
      return;
    }
    setState(() {
      _isIssuing = true;
      _message = null;
    });
    try {
      final order = await repository.issueDemoOrder(
        riderName: rider,
        travelForSelf: !_forSomeoneElse,
        originName: widget.viewModel.originName,
        destinationName: widget.viewModel.destinationName,
        journey: journey,
      );
      if (mounted) {
        setState(() {
          _orders = [order, ..._orders];
          _message = 'Journey pass issued to $rider.';
          _riderController.clear();
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not issue the journey pass.');
      }
    } finally {
      if (mounted) setState(() => _isIssuing = false);
    }
  }

  Future<void> _downloadPass(TicketOrder order) async {
    try {
      await const TicketPdfService().download(order);
      if (mounted) setState(() => _message = 'PDF journey pass prepared.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not create the PDF pass.');
    }
  }
}

class _TicketOrderRow extends StatelessWidget {
  const _TicketOrderRow(this.order, {required this.onDownload});
  final TicketOrder order;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_outlined, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.riderName, style: theme.textTheme.small),
                Text(
                  '${order.originName} to ${order.destinationName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.muted,
                ),
              ],
            ),
          ),
          Text('Rs ${order.fareAmount}', style: theme.textTheme.small),
          IconButton(
            tooltip: 'Download PDF pass',
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final int amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final style = emphasized ? theme.textTheme.large : theme.textTheme.small;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text('Rs $amount', style: style),
      ],
    );
  }
}
