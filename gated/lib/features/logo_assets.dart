import 'package:flutter/material.dart';

String getCompactLogoAsset(Brightness brightness) {
  return brightness == Brightness.dark
      ? 'assets/logo/logo-hell-quer.png'
      : 'assets/logo/logo-dunkel-quer.png';
}

String getFullLogoAsset(Brightness brightness) {
  return brightness == Brightness.dark
      ? 'assets/logo/logo-hell.png'
      : 'assets/logo/logo-dunkel.png';
}
