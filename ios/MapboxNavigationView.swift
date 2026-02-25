import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit
import Combine

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder!.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}

public class MapboxNavigationView: UIView, NavigationViewControllerDelegate {
    public weak var navViewController: NavigationViewController?

    private var mapboxNavigationProvider: MapboxNavigationProvider?
    private var mapboxNavigation: MapboxNavigation?
    private var cancellables = Set<AnyCancellable>()

    var embedded: Bool
    var embedding: Bool

    @objc public var startOrigin: NSArray = [] {
        didSet { setNeedsLayout() }
    }

    var waypoints: [Waypoint] = [] {
        didSet { setNeedsLayout() }
    }

    func setWaypoints(waypoints: [MapboxWaypoint]) {
        self.waypoints = waypoints.enumerated().map { (index, waypointData) in
            let name = waypointData.name as? String ?? "\(index)"
            var waypoint = Waypoint(coordinate: waypointData.coordinate, name: name)
            waypoint.separatesLegs = waypointData.separatesLegs
            return waypoint
        }
    }

    @objc var destination: NSArray = [] {
        didSet { setNeedsLayout() }
    }

    @objc var shouldSimulateRoute: Bool = false
    @objc var showsEndOfRouteFeedback: Bool = false  // no-op in v3, kept for API compat
    @objc var showCancelButton: Bool = false
    @objc var hideStatusView: Bool = false  // no-op in v3, kept for API compat
    @objc var mute: Bool = false
    @objc var distanceUnit: NSString = "imperial"
    @objc var language: NSString = "us"
    @objc var destinationTitle: NSString = "Destination"
    @objc var travelMode: NSString = "driving-traffic"

    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onRouteProgressChange: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var onCancelNavigation: RCTDirectEventBlock?
    @objc var onArrive: RCTDirectEventBlock?

    override init(frame: CGRect) {
        self.embedded = false
        self.embedding = false
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if (navViewController == nil && !embedding && !embedded) {
            embed()
        } else {
            navViewController?.view.frame = bounds
        }
    }

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        navViewController?.removeFromParent()
        cancellables.removeAll()
        mapboxNavigationProvider = nil
        mapboxNavigation = nil
        embedded = false
        embedding = false
    }

    private func embed() {
        guard startOrigin.count == 2 && destination.count == 2 else { return }

        embedding = true

        let originWaypoint = Waypoint(
            coordinate: CLLocationCoordinate2D(
                latitude: startOrigin[1] as! CLLocationDegrees,
                longitude: startOrigin[0] as! CLLocationDegrees
            )
        )
        var waypointsArray = [originWaypoint]
        waypointsArray.append(contentsOf: waypoints)

        let destinationWaypoint = Waypoint(
            coordinate: CLLocationCoordinate2D(
                latitude: destination[1] as! CLLocationDegrees,
                longitude: destination[0] as! CLLocationDegrees
            ),
            name: destinationTitle as String
        )
        waypointsArray.append(destinationWaypoint)

        let profile: ProfileIdentifier
        switch travelMode {
        case "cycling":
            profile = .cycling
        case "walking":
            profile = .walking
        case "driving-traffic":
            profile = .automobileAvoidingTraffic
        default:
            profile = .automobile
        }

        let options = NavigationRouteOptions(waypoints: waypointsArray, profileIdentifier: profile)

        let locale = (self.language as String).replacingOccurrences(of: "-", with: "_")
        options.locale = Locale(identifier: locale)
        options.distanceMeasurementSystem = distanceUnit == "imperial" ? .imperial : .metric

        // Build the navigation provider - simulation and voice config live here
        let coreConfig = CoreConfig(
            simulationMode: shouldSimulateRoute ? .always : .never
        )
        let provider = MapboxNavigationProvider(coreConfig: coreConfig)
        self.mapboxNavigationProvider = provider
        let navigation = provider.mapboxNavigation
        self.mapboxNavigation = navigation

        // Configure mute
        if mute {
            provider.routeVoiceController.volume = 0
        }

        let request = navigation.routingProvider().calculateRoutes(options: options)

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let parentVC = self.parentViewController else {
                self.embedding = false
                return
            }

            switch await request.result {
            case .failure(let error):
                self.onError?(["message": error.localizedDescription])
                self.embedding = false
            case .success(let navigationRoutes):
                let navigationOptions = NavigationOptions(
                    mapboxNavigation: navigation,
                    voiceController: provider.routeVoiceController,
                    eventsManager: provider.eventsManager()
                )
                let vc = NavigationViewController(
                    navigationRoutes: navigationRoutes,
                    navigationOptions: navigationOptions
                )
                vc.delegate = self

                parentVC.addChild(vc)
                self.addSubview(vc.view)
                vc.view.frame = self.bounds
                vc.didMove(toParent: parentVC)
                self.navViewController = vc

                self.embedding = false
                self.embedded = true
            }
        }
    }

    public func navigationViewController(
        _ navigationViewController: NavigationViewController,
        didUpdate progress: RouteProgress,
        with location: CLLocation,
        rawLocation: CLLocation
    ) {
        onLocationChange?([
            "longitude": location.coordinate.longitude,
            "latitude": location.coordinate.latitude,
            "heading": 0,
            "accuracy": location.horizontalAccuracy.magnitude
        ])
        onRouteProgressChange?([
            "distanceTraveled": progress.distanceTraveled,
            "durationRemaining": progress.durationRemaining,
            "fractionTraveled": progress.fractionTraveled,
            "distanceRemaining": progress.distanceRemaining
        ])
    }

    public func navigationViewControllerDidDismiss(
        _ navigationViewController: NavigationViewController,
        byCanceling canceled: Bool
    ) {
        if (!canceled) { return }
        onCancelNavigation?(["message": "Navigation Cancel"])
    }

    public func navigationViewController(
        _ navigationViewController: NavigationViewController,
        didArriveAt waypoint: Waypoint
    ) -> Bool {
        onArrive?([
            "name": waypoint.name ?? waypoint.description,
            "longitude": waypoint.coordinate.longitude,
            "latitude": waypoint.coordinate.latitude,
        ])
        return true
    }
}
