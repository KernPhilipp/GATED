import 'package:package_info_plus/package_info_plus.dart';

class AppMetadataService {
  const AppMetadataService();

  Future<String> loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final buildNumber = packageInfo.buildNumber.trim();
    if (buildNumber.isEmpty) {
      return packageInfo.version;
    }

    return '${packageInfo.version}+$buildNumber';
  }
}
