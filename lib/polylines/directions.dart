import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Directions {
  final LatLngBounds bounds;
  final List<PointLatLng> polylinePoints;
  final String totalDistance;
  final String totalDuration;

  const Directions({
    required this.bounds,
    required this.polylinePoints,
    required this.totalDistance,
    required this.totalDuration,
  });

  factory Directions.fromMap(Map<String, dynamic> map) {
    // Check if the response has routes
    if (map['routes'] == null || (map['routes'] as List).isEmpty) {
      throw Exception('No routes found in the response. Status: ${map['status']}');
    }

    // Check the status of the response
    final status = map['status'];
    if (status != 'OK') {
      String errorMessage = 'Directions API Error: $status';
      if (map['error_message'] != null) {
        errorMessage += ' - ${map['error_message']}';
      }
      throw Exception(errorMessage);
    }

    final data = Map<String, dynamic>.from(map['routes'][0]);

    // Check if bounds exist
    if (data['bounds'] == null) {
      throw Exception('Route bounds not found in response');
    }

    final northeast = data['bounds']['northeast'];
    final southwest = data['bounds']['southwest'];
    final bounds = LatLngBounds(
        southwest: LatLng(southwest['lat'], southwest['lng']),
        northeast: LatLng(northeast['lat'], northeast['lng']));

    String distance = '';
    String duration = '';

    // Check if legs exist and are not empty
    if (data['legs'] != null && (data['legs'] as List).isNotEmpty) {
      final leg = data['legs'][0];
      distance = leg['distance']?['text'] ?? 'Unknown distance';
      duration = leg['duration']?['text'] ?? 'Unknown duration';
    }

    // Check if overview_polyline exists
    if (data['overview_polyline'] == null || data['overview_polyline']['points'] == null) {
      throw Exception('Polyline data not found in response');
    }

    List<PointLatLng> polylinePoints = [];
    try {
      polylinePoints = PolylinePoints().decodePolyline(data['overview_polyline']['points']);
    } catch (e) {
      throw Exception('Failed to decode polyline: $e');
    }

    return Directions(
        bounds: bounds,
        polylinePoints: polylinePoints,
        totalDistance: distance,
        totalDuration: duration);
  }
}