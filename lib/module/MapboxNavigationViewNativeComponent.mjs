import { get as getNativeComponent } from 'react-native/Libraries/NativeComponent/NativeComponentRegistry';

// NativeComponentRegistry.get uses a static viewConfigProvider in RN Bridgeless mode,
// bypassing UIManager.getViewManagerConfig which fails for legacy Paper view managers.
export default getNativeComponent('MapboxNavigationView', () => ({
  uiViewClassName: 'MapboxNavigationView',
  bubblingEventTypes: {},
  directEventTypes: {
    onLocationChange: { registrationName: 'onLocationChange' },
    onRouteProgressChange: { registrationName: 'onRouteProgressChange' },
    onError: { registrationName: 'onError' },
    onCancelNavigation: { registrationName: 'onCancelNavigation' },
    onArrive: { registrationName: 'onArrive' },
  },
  validAttributes: {
    startOrigin: true,
    waypoints: true,
    destination: true,
    destinationTitle: true,
    shouldSimulateRoute: true,
    showsEndOfRouteFeedback: true,
    showCancelButton: true,
    language: true,
    distanceUnit: true,
    mute: true,
    travelMode: true,
  },
}));
//# sourceMappingURL=MapboxNavigationViewNativeComponent.mjs.map