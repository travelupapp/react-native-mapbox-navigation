declare module 'react-native/Libraries/NativeComponent/NativeComponentRegistry' {
  import type { HostComponent } from 'react-native';

  type ViewConfigGetter = () => {
    uiViewClassName: string;
    bubblingEventTypes?: Record<string, unknown>;
    directEventTypes?: Record<string, unknown>;
    validAttributes?: Record<string, unknown>;
  };

  export function get<T>(
    name: string,
    viewConfigProvider: ViewConfigGetter
  ): HostComponent<T>;
}
