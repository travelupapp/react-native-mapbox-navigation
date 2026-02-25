"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = void 0;

// NativeComponentRegistry.get uses a static viewConfigProvider in RN Bridgeless mode,
// bypassing UIManager.getViewManagerConfig which fails for legacy Paper view managers.
var _NativeComponentRegistry = require("react-native/Libraries/NativeComponent/NativeComponentRegistry");
var _default = exports.default = (0, _NativeComponentRegistry.get)('MapboxNavigationView', () => ({
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
//# sourceMappingURL=MapboxNavigationViewNativeComponent.cjs.map