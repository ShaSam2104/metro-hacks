import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/use_cases/multimodal_router.dart';
import 'auth_repository.dart';

class TicketOrder {
  const TicketOrder({
    required this.id,
    required this.riderName,
    required this.travelForSelf,
    required this.originName,
    required this.destinationName,
    required this.fareAmount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String riderName;
  final bool travelForSelf;
  final String originName;
  final String destinationName;
  final int fareAmount;
  final String status;
  final DateTime createdAt;

  factory TicketOrder.fromJson(Map<String, dynamic> json) => TicketOrder(
    id: json['id'] as String,
    riderName: json['rider_name'] as String,
    travelForSelf: json['travel_for_self'] as bool,
    originName: json['origin_name'] as String,
    destinationName: json['destination_name'] as String,
    fareAmount: json['fare_amount'] as int,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}

class TicketRepository {
  TicketRepository({required this.authRepository, http.Client? client})
    : _client = client ?? http.Client();

  final AuthRepository authRepository;
  final http.Client _client;

  Future<List<TicketOrder>> listOrders() async {
    final response = await _authorized(
      (session) => _client.get(
        Uri.parse('${AuthRepository.apiBaseUrl}/v1/ticket-orders'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ),
    );
    final body = _body(response);
    if (response.statusCode != 200 || body is! List) {
      throw ApiException(_detail(body, 'Could not load ticket history.'));
    }
    return body
        .whereType<Map>()
        .map((item) => TicketOrder.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<TicketOrder> issueDemoOrder({
    required String riderName,
    required bool travelForSelf,
    required String originName,
    required String destinationName,
    required RoutedJourney journey,
  }) async {
    final payload = {
      'rider_name': riderName.trim(),
      'travel_for_self': travelForSelf,
      'origin_name': originName,
      'destination_name': destinationName,
      'fare_amount': journey.estimatedFare,
      'itinerary': journey.legs
          .map(
            (leg) => {
              'mode': leg.mode,
              'route_name': leg.route?.shortName,
              'from_name': leg.from,
              'to_name': leg.to,
              'minutes': leg.minutes,
            },
          )
          .toList(),
    };
    final response = await _authorized(
      (session) => _client.post(
        Uri.parse('${AuthRepository.apiBaseUrl}/v1/ticket-orders'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );
    final body = _body(response);
    if (response.statusCode != 201 || body is! Map<String, dynamic>) {
      throw ApiException(_detail(body, 'Could not issue the journey pass.'));
    }
    return TicketOrder.fromJson(body);
  }

  Future<http.Response> _authorized(
    Future<http.Response> Function(MetroSession session) request,
  ) async {
    final session = authRepository.session.value;
    if (session == null || !authRepository.isConfigured) {
      throw const ApiException('Sign in to save and issue tickets.');
    }
    var response = await request(session);
    if (response.statusCode == 401 &&
        await authRepository.refreshAccessToken()) {
      response = await request(authRepository.session.value!);
    }
    return response;
  }
}

dynamic _body(http.Response response) =>
    response.body.isEmpty ? const {} : jsonDecode(response.body);

String _detail(dynamic body, String fallback) =>
    body is Map ? body['detail'] as String? ?? fallback : fallback;
