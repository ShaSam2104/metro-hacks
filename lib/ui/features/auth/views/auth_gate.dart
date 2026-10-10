import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/journey_sync_repository.dart';
import '../../../../data/repositories/ticket_repository.dart';
import '../../admin/views/admin_dashboard_page.dart';
import '../../journey_card/views/journey_card_page.dart';
import 'sign_in_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthRepository();
  var _isRestoring = true;
  var _offlineMode = false;
  var _showAdmin = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await _auth.restoreSession();
    if (mounted) {
      setState(() {
        _isRestoring = false;
        _showAdmin = _auth.session.value?.role == 'operator';
      });
    }
  }

  @override
  void dispose() {
    _auth.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoring) return const SizedBox.shrink();
    if (_offlineMode) return const JourneyCardPage();
    return ValueListenableBuilder<MetroSession?>(
      valueListenable: _auth.session,
      builder: (context, session, _) {
        if (session == null) {
          return SignInPage(
            authRepository: _auth,
            onContinueOffline: () => setState(() => _offlineMode = true),
            onAuthenticated: () => setState(
              () => _showAdmin = _auth.session.value?.role == 'operator',
            ),
          );
        }
        final syncRepository = JourneySyncRepository(authRepository: _auth);
        unawaited(syncRepository.flushPending());
        if (_showAdmin && session.role == 'operator') {
          return AdminDashboardPage(session: session, onLogout: _signOut);
        }
        return JourneyCardPage(
          userId: session.userId,
          syncRepository: syncRepository,
          ticketRepository: TicketRepository(authRepository: _auth),
          accountRole: session.role,
          onLogout: _signOut,
        );
      },
    );
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) setState(() => _showAdmin = false);
  }
}
