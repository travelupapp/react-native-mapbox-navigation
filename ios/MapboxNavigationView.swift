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

/// Container VC that hosts NavigationViewController as a child.
/// When the child calls dismiss(), UIKit walks up the responder chain and
/// dismisses this container (which is the one actually presented modally).
/// viewDidDisappear fires reliably, giving us a callback to React.
private class NavContainerViewController: UIViewController {
    var onDismiss: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onDismiss?()
            onDismiss = nil
        }
    }
}

public class MapboxNavigationView: UIView, NavigationViewControllerDelegate {
    public var navViewController: NavigationViewController?

    private var containerViewController: NavContainerViewController?
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
        }
    }

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        // Prevent the container's onDismiss from firing during React teardown
        containerViewController?.onDismiss = nil
        if let container = containerViewController {
            container.dismiss(animated: false)
        }
        containerViewController = nil
        navViewController = nil
        cancellables.removeAll()
        mapboxNavigationProvider = nil
        mapboxNavigation = nil
        embedded = false
        embedding = false
    }

    private func embed() {
        guard startOrigin.count == 2 && destination.count == 2 else {
            return
        }

        guard let originLat = startOrigin[1] as? CLLocationDegrees,
              let originLon = startOrigin[0] as? CLLocationDegrees,
              let destLat = destination[1] as? CLLocationDegrees,
              let destLon = destination[0] as? CLLocationDegrees else {
            onError?(["message": "Invalid coordinates"])
            return
        }

        embedding = true

        let originWaypoint = Waypoint(
            coordinate: CLLocationCoordinate2D(latitude: originLat, longitude: originLon)
        )
        var waypointsArray = [originWaypoint]
        waypointsArray.append(contentsOf: waypoints)

        let destinationWaypoint = Waypoint(
            coordinate: CLLocationCoordinate2D(latitude: destLat, longitude: destLon),
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

        let coreConfig = CoreConfig(
            locationSource: shouldSimulateRoute ? .simulation() : .live
        )
        let provider = MapboxNavigationProvider(coreConfig: coreConfig)
        self.mapboxNavigationProvider = provider
        let navigation = provider.mapboxNavigation
        self.mapboxNavigation = navigation

        // Configure mute
        if mute {
            provider.routeVoiceController.speechSynthesizer.muted = true
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
                self.navViewController = vc

                // Wrap NavigationVC in a container presented modally. This keeps it
                // outside React Native's Fabric view hierarchy (touch events work)
                // AND gives us a reliable dismiss callback via viewDidDisappear.
                // When NavigationVC's Exit button calls self.dismiss(), UIKit walks
                // up to the container (the presented VC) and dismisses it.
                let container = NavContainerViewController()
                container.modalPresentationStyle = .fullScreen
                container.view.backgroundColor = .black
                container.onDismiss = { [weak self] in
                    guard let self else { return }
                    self.navViewController = nil
                    self.containerViewController = nil
                    self.embedded = false
                    self.onCancelNavigation?(["message": "Navigation Cancel"])
                }

                container.addChild(vc)
                vc.view.frame = container.view.bounds
                vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.view.addSubview(vc.view)
                vc.didMove(toParent: container)

                self.containerViewController = container
                parentVC.present(container, animated: true)

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
        // Container's viewDidDisappear is the primary callback path.
        // If the delegate also fires, dismiss the container explicitly
        // and nil the callback to prevent double-fire.
        if canceled {
            containerViewController?.onDismiss = nil
            onCancelNavigation?(["message": "Navigation Cancel"])
        }
        containerViewController?.dismiss(animated: true) { [weak self] in
            self?.navViewController = nil
            self?.containerViewController = nil
            self?.embedded = false
        }
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
