import 'dart:async';
import 'package:flutter/material.dart';
import 'package:grad02/action_button/quick_action.dart';
import 'package:grad02/action_button/quick_action_menu.dart';
import 'package:grad02/station_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:grad02/polylines/location_manager.dart';
import '../common/glob.dart';
import '../common/service_call.dart';
import '../common/socket_manager.dart';
import 'package:grad02/polylines/directions_rep.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

const String google_API_Key = "AIzaSyA0j-zfLPSJ86hmBHHaHmBLbkZceI82U3U";

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  GoogleMapController? mapController;
  Set<Polyline> polylines = {};
  Set<Marker> markers = {};
  late DirectionsRep stationFinder;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(30.0076964, 31.2428155),
    zoom: 12,
  );

  late LatLng currentPosition;
  late PageController _pageController;
  final Map<String, Marker> usersCarArr = {};
  List<Marker> stationMarkers = [];
  late BitmapDescriptor iconCar, iconStation;

  void debugPolylineState() {
    print('=== POLYLINE STATE DEBUG ===');
    print('Polylines set length: ${polylines.length}');
    print('Polylines set contents: $polylines');

    if (polylines.isNotEmpty) {
      for (Polyline p in polylines) {
        print('Polyline ID: ${p.polylineId.value}');
        print('Points count: ${p.points.length}');
        print('Color: ${p.color}');
        print('Width: ${p.width}');
        if (p.points.isNotEmpty) {
          print('First point: ${p.points.first}');
          print('Last point: ${p.points.last}');
          // Print a few middle points to verify they're different
          if (p.points.length > 2) {
            print('Second point: ${p.points[1]}');
            print('Third point: ${p.points[2]}');
          }
        }
      }
    } else {
      print('NO POLYLINES IN SET!');
    }
    print('=== END DEBUG ===');
  }

  void addTestPolyline() {
    print('Adding test polyline manually...');
    setState(() {
      polylines.add(
        Polyline(
          polylineId: PolylineId('test_polyline'),
          points: [
            LatLng(30.0444, 31.2357), // Cairo
            LatLng(30.0626, 31.2497), // Another point in Cairo
          ],
          color: Colors.purple,
          width: 5,
        ),
      );
    });
    debugPolylineState();
  }

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addPostFrameCallback(
    //   (_) async => await fetchLocationUpdate(),
    // );

    stationFinder = DirectionsRep(
      onPolylinesUpdated: (Set<Polyline> newPolylines) {
        print(
          'onPolylinesUpdated called with ${newPolylines.length} polylines',
        );
        setState(() {
          polylines = newPolylines;
        });
        // Debug after setState
        debugPolylineState();
      },
    );

    getIcon();
    currentPosition = LatLng(
      LocationManager.shared.currentPos?.latitude ?? 0.0,
      LocationManager.shared.currentPos?.longitude ?? 0.0,
    );
    DefaultAssetBundle.of(
      context,
    ).loadString('assets/theme/dark_theme.json').then((thisValue) {
      _themeformap = thisValue;
    });
    SocketManager.shared.socket?.on(SVKey.nvCarJoin, (data) {
      if (data[KKey.status] == "1") {
        updateOtherCarLocation(data[KKey.payload] as Map? ?? {});
      } else {}
    });

    SocketManager.shared.socket?.on(SVKey.nvCarUpdateLocation, (data) {
      if (data[KKey.status] == "1") {
        updateOtherCarLocation(data[KKey.payload] as Map? ?? {});
      } else {}
    });
    apiCarJoin();
  }

  String _themeformap = '';

  void setMarkers() {
    for (var element in evStations) {
      stationMarkers.add(
        Marker(
          markerId: MarkerId(element.stationName),
          draggable: false,
          infoWindow: InfoWindow(
            title: element.stationName,
            snippet: element.address,
          ),
          position: element.locationCoords,
          icon: iconStation,
        ),
      );
      _pageController = PageController(initialPage: 1, viewportFraction: 0.8);
    }
  }

  void handleFindNearestStation() async {
    try {
      print('Wrapper function called');
      // Force a rebuild to ensure state is current
      if (mounted) {
        setState(() {});
      }
      await stationFinder.findNearestStationAndCreatePolyline();
      // Force another rebuild after completion
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error in wrapper function: $e');
    }
  }

  AnimatedBuilder _evStationList(int index) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (BuildContext context, Widget? widget) {
        double value = 1;
        if (_pageController.position.haveDimensions) {
          value = (_pageController.page! - index);
          value = (1 - (value.abs() * 0.3) + 0.06).clamp(0.0, 1.0);
        }
        return Center(
          child: SizedBox(
            height: Curves.easeInOut.transform(value) * 132.0,
            width: Curves.easeInOut.transform(value) * 350.0,
            child: widget,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          moveCamera();
        },
        child: Stack(
          children: [
            Center(
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 10.0, vertical: 20.0),
                height: 132.0,
                width: 275.0,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      offset: Offset(0.0, 4.0),
                      blurRadius: 10.0,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.0),
                    color: Colors.greenAccent.shade700,
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 90,
                        width: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            topLeft: Radius.circular(10),
                          ),
                          image: DecorationImage(
                            image: AssetImage(evStations[index].thumbNail),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              evStations[index].stationName,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              evStations[index].address,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('Building widget with ${polylines.length} polylines');
    setMarkers();
    final Set<Marker> allMarkers = {
      ...Set.from(stationMarkers),
      ...usersCarArr.values,
    };
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: Text('EV Charging Station Finder'),
        centerTitle: true,
        backgroundColor: Colors.greenAccent.shade700,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: GoogleMap(
              style: _themeformap,
              mapType: MapType.normal,
              initialCameraPosition: _kGooglePlex,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
              markers: allMarkers,
              polylines: polylines,
            ),
          ),
          QuickActionMenu(
            onTap: () {
              // This gets called every time the main FAB is tapped
              // You can leave this empty or add additional logic
              print('Main button tapped');
            },
            icon: Icons.menu,
            backgroundColor: Colors.greenAccent.shade700,
            actions: [
              QuickAction(
                icon: Icons.navigation,
                backgroundColor: Colors.greenAccent.shade700,
                onTap: () async {
                  print('GestureDetector with onTap');
                  await stationFinder.findNearestStationAndCreatePolyline();
                },
              ),
              QuickAction(
                icon: Icons.ev_station,
                backgroundColor: Colors.greenAccent.shade700,
                onTap: () async {
                  Positioned(
                    bottom: 20.0,
                    child: SizedBox(
                      height: 200,
                      width: MediaQuery.of(context).size.width,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: evStations.length,
                        itemBuilder: (BuildContext context, int index) {
                          return _evStationList(index);
                        },
                      ),
                    ),
                  );
                },
              ),
              QuickAction(
                icon: Icons.my_location,
                backgroundColor: Colors.greenAccent.shade700,
                onTap: () {
                  _cameraToPosition(
                    LatLng(
                      LocationManager.shared.currentPos?.latitude ?? 0.0,
                      LocationManager.shared.currentPos?.longitude ?? 0.0,
                    ),
                  );
                },
              ),
            ],
            child: Container(
              child: Center(child: Text('')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cameraToPosition(LatLng pos) async {
    final GoogleMapController controller = await _controller.future;
    CameraPosition newCameraPosition = CameraPosition(target: pos, zoom: 14);
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(newCameraPosition),
    );
    setState(() async {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(newCameraPosition),
      );
    });
  }

  void moveCamera() async {
    final GoogleMapController controller = await _controller.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: evStations[_pageController.page!.toInt()].locationCoords,
          zoom: 14,
        ),
      ),
    );
  }

  void getIcon() async {
    var iconCar = await BitmapDescriptor.asset(
      const ImageConfiguration(devicePixelRatio: 3.2),
      "assets/mapicons/car.png",
      width: 40,
      height: 40,
    );
    var iconStation = await BitmapDescriptor.asset(
      const ImageConfiguration(devicePixelRatio: 3.2),
      "assets/mapicons/charging-station.png",
      width: 40,
      height: 40,
    );
    setState(() {
      this.iconCar = iconCar;
      this.iconStation = iconStation;
    });
  }

  void updateOtherCarLocation(Map obj) {
    usersCarArr[obj["uuid"].toString()] = Marker(
      markerId: MarkerId(obj["uuid"].toString()),
      position: LatLng(
        double.tryParse(obj["lat"].toString()) ?? 0.0,
        double.tryParse(obj["long"].toString()) ?? 0.0,
      ),
      icon: iconCar,
      rotation: double.tryParse(obj["degree"].toString()) ?? 0.0,
      anchor: const Offset(0.5, 0.5),
    );

    if (mounted) {
      setState(() {});
    }
  }

  void apiCarJoin() {
    ServiceCall.post(
      {
        "uuid": ServiceCall.userUUID,
        "lat": currentPosition.latitude.toString(),
        "long": currentPosition.longitude.toString(),
        "degree": LocationManager.shared.carDegree.toString(),
        "socket_id": SocketManager.shared.socket?.id ?? "",
      },
      SVKey.svCarJoin,
      (responseObj) async {
        if (responseObj[KKey.status] == "1") {
          (responseObj[KKey.payload] as Map? ?? {}).forEach((key, value) {
            usersCarArr[key.toString()] = Marker(
              markerId: MarkerId(key.toString()),
              position: LatLng(
                double.tryParse(value["lat"].toString()) ?? 0.0,
                double.tryParse(value["long"].toString()) ?? 0.0,
              ),
              icon: iconCar,
              rotation: double.tryParse(value["degree"].toString()) ?? 0.0,
              anchor: const Offset(0.5, 0.5),
            );
          });

          if (mounted) {
            setState(() {});
          }
        } else {
          debugPrint(responseObj[KKey.message] as String? ?? MSG.fail);
        }
      },
      (error) async {
        debugPrint(error.toString());
      },
    );
  }
}
