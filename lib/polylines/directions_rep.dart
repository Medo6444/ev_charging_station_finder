import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:grad02/station_model.dart';
import 'directions.dart';
import 'location_manager.dart';

const String google_API_Key = "AIzaSyA0j-zfLPSJ86hmBHHaHmBLbkZceI82U3U";

class DirectionsRep {
  // Create Dio instance internally instead of requiring it as parameter
  final Dio _dio = Dio();
  Set<Polyline> polylines = {};
  Function(Set<Polyline>)? onPolylinesUpdated;

  DirectionsRep({this.onPolylinesUpdated});

  // Your base URL and API key (make sure these are defined)
  static const String _baseURL =
      'https://maps.googleapis.com/maps/api/directions/json';

  // Remove the constructor parameter requirement
  Future<Directions?> getDirections({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      // Validate coordinates
      if (origin.latitude == 0.0 && origin.longitude == 0.0) {
        print('Invalid origin coordinates');
        return null;
      }

      if (destination.latitude == 0.0 && destination.longitude == 0.0) {
        print('Invalid destination coordinates');
        return null;
      }

      // Debug: Print the exact URL being called
      final String requestUrl =
          '$_baseURL?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$google_API_Key&mode=driving&units=metric';
      print('Full Request URL: $requestUrl');

      print(
        'Getting directions from ${origin.latitude},${origin.longitude} to ${destination.latitude},${destination.longitude}',
      );

      final response = await _dio.get(
        _baseURL,
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'key': google_API_Key,
          'mode': 'driving',
          'units': 'metric',
        },
      );

      print('API Response Status: ${response.statusCode}');
      print('API Response Data: ${response.data}');

      if (response.statusCode == 200) {
        try {
          return Directions.fromMap(response.data);
        } catch (e) {
          print('Error parsing directions response: $e');
          return null;
        }
      } else {
        print('API request failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Network error getting directions: $e');
      return null;
    }
  }

  double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double lat1Rad = point1.latitude * (pi / 180);
    double lat2Rad = point2.latitude * (pi / 180);
    double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    double deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);

    double a =
        sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) *
            cos(lat2Rad) *
            sin(deltaLngRad / 2) *
            sin(deltaLngRad / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // Distance in kilometers
  }

  Station? findNearestStation(LatLng currentLocation, List<Station> stations) {
    if (stations.isEmpty) return null;

    Station nearestStation = stations.first;
    double minDistance = calculateDistance(
      currentLocation,
      stations.first.locationCoords,
    );

    for (Station station in stations) {
      double distance = calculateDistance(
        currentLocation,
        station.locationCoords,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestStation = station;
      }
    }

    return nearestStation;
  }

  Future<void> adjustCameraToShowRoute(
    Directions directions,
    GoogleMapController? mapController,
  ) async {
    if (mapController == null) return;

    try {
      // Use the bounds from the directions to fit the camera
      await mapController.animateCamera(
        CameraUpdate.newLatLngBounds(
          directions.bounds,
          100.0, // padding
        ),
      );
      print('Camera adjusted to show full route');
    } catch (e) {
      print('Error adjusting camera: $e');
    }
  }

  Future<void> findNearestStationAndCreatePolyline() async {
    try {
      print('=== STARTING findNearestStationAndCreatePolyline ===');

      // Get current location
      LatLng currentLocation = LatLng(
        LocationManager.shared.currentPos?.latitude ?? 0.0,
        LocationManager.shared.currentPos?.longitude ?? 0.0,
      );

      print('Current location: $currentLocation');

      if (currentLocation.latitude == 0.0 && currentLocation.longitude == 0.0) {
        print('Current location not available');
        return;
      }

      // Find nearest station
      Station? nearestStation = findNearestStation(currentLocation, evStations);

      if (nearestStation == null) {
        print('No stations available');
        return;
      }

      print('Nearest station found: ${nearestStation.stationName}');
      print('Station location: ${nearestStation.locationCoords}');

      // Get directions
      Directions? directions = await getDirections(
        origin: currentLocation,
        destination: nearestStation.locationCoords,
      );

      if (directions != null) {
        print('Directions received, creating polyline...');
        print('Polyline points count: ${directions.polylinePoints.length}');

        // Create the polyline
        Polyline? routePolyline = await getPolylineData(directions, nearestStation);

        if (routePolyline != null) {
          print('Polyline created successfully');
          print('Polyline ID: ${routePolyline.polylineId.value}');
          print('Polyline points: ${routePolyline.points.length}');
          print('Polyline color: ${routePolyline.color}');

          // Clear and add polyline
          polylines.clear();
          polylines.add(routePolyline);

          print('Polyline added to set. Set size: ${polylines.length}');

          // Call the callback
          if (onPolylinesUpdated != null) {
            print('Calling onPolylinesUpdated callback...');
            onPolylinesUpdated!(polylines);
            print('Callback called successfully');
          } else {
            print('ERROR: onPolylinesUpdated callback is NULL!');
          }

          print('Total distance: ${directions.totalDistance}');
          print('Total duration: ${directions.totalDuration}');
        } else {
          print('ERROR: Failed to create polyline');
        }
      } else {
        print('ERROR: Could not get directions to nearest station');
      }

    } catch (e) {
      print('ERROR in findNearestStationAndCreatePolyline: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  Future<Polyline?> getPolylineData(Directions directions, Station nearestStation) async {
    try {
      if (directions.polylinePoints.isEmpty) {
        print('No polyline points available');
        return null;
      }

      List<LatLng> polylineCoordinates = directions.polylinePoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      print('Creating polyline with ${polylineCoordinates.length} points');
      print('First coordinate: ${polylineCoordinates.first}');
      print('Last coordinate: ${polylineCoordinates.last}');

      return Polyline(
        polylineId: const PolylineId('route_to_nearest_station'),
        points: polylineCoordinates,
        color: Colors.purple, // Very visible color
        width: 5, // Very thick
        geodesic: true,
      );
    } catch (e) {
      print('Error creating polyline: $e');
      return null;
    }
  }

  void clearPolylines() {
    polylines.clear();
    onPolylinesUpdated?.call(polylines);
  }

  Future<Station?> getNearestStation() async {
    LatLng currentLocation = LatLng(
      LocationManager.shared.currentPos?.latitude ?? 0.0,
      LocationManager.shared.currentPos?.longitude ?? 0.0,
    );
    if (currentLocation.latitude == 0.0 && currentLocation.longitude == 0.0) {
      return null;
    }
    return findNearestStation(currentLocation, evStations);
  }

}
