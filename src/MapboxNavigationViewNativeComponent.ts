import type { HostComponent, ViewProps } from 'react-native';
// NativeComponentRegistry.get uses a static viewConfigProvider in RN Bridgeless mode,
// bypassing UIManager.getViewManagerConfig which fails for legacy Paper view managers.
import { get as getNativeComponent } from 'react-native/Libraries/NativeComponent/NativeComponentRegistry';

import type { Double } from 'react-native/Libraries/Types/CodegenTypes';
import type { NativeEventsProps } from './types';

type NativeCoordinate = number[];
interface NativeProps extends ViewProps {
  mute?: boolean;
  separateLegs?: boolean;
  distanceUnit?: string;
  startOrigin: NativeCoordinate;
  waypoints?: {
    latitude: Double;
    longitude: Double;
    name?: string;
    separatesLegs?: boolean;
  }[];
  destinationTitle?: string;
  destination: NativeCoordinate;
  language?: string;
  showCancelButton?: boolean;
  shouldSimulateRoute?: boolean;
  showsEndOfRouteFeedback?: boolean;
  hideStatusView?: boolean;
  travelMode?: string;
}

export default getNativeComponent<NativeProps & NativeEventsProps>(
  'MapboxNavigationView',
  () => ({
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
  })
) as HostComponent<NativeProps & NativeEventsProps>;
