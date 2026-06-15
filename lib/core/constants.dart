class Constants {
  // ICE Servers for WebRTC
  // STUN servers are free and sufficient for same-network calls.
  // For cross-network calls (WiFi to 4G), add TURN server credentials.
  // Get free TURN credentials at https://www.metered.ca/stun-turn
  static List<Map<String, dynamic>> get iceServers => [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun.metered.ca:80'},
    // Uncomment and fill in your metered.ca credentials for TURN support:
    // {
    //   'urls': 'turn:standard.relay.metered.ca:80',
    //   'username': 'YOUR_METERED_USERNAME',
    //   'credential': 'YOUR_METERED_CREDENTIAL',
    // },
    // {
    //   'urls': 'turn:standard.relay.metered.ca:443',
    //   'username': 'YOUR_METERED_USERNAME',
    //   'credential': 'YOUR_METERED_CREDENTIAL',
    // },
  ];
}
