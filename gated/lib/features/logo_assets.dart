import 'package:flutter/material.dart';

String getCompactLogoAsset(Brightness brightness) {
  return brightness == Brightness.dark
      ? 'assets/logo/logo-hell-quer.svg'
      : 'assets/logo/logo-dunkel-quer.svg';
}

String getFullLogoAsset(Brightness brightness) {
  return brightness == Brightness.dark
      ? 'assets/logo/logo-hell.svg'
      : 'assets/logo/logo-dunkel.svg';
}
