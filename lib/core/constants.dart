class Constants {
  /// STUN-only fallback ICE servers.
  ///
  /// The real config (including the TURN relay) is fetched per-call from the
  /// `turn-credentials` Firebase edge function, which proxies Cloudflare's
  /// Realtime TURN service and returns short-lived credentials so no TURN
  /// secret ever ships inside the APK. This list is only used if that fetch
  /// fails — it still covers same-network / simple-NAT calls, but cross-network
  /// calls need the TURN relay.
  static List<Map<String, dynamic>> get iceServers => [
    {'urls': 'stun:stun.cloudflare.com:3478'},
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];
}
