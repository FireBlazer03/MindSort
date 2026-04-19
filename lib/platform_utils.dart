import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PlatformUtils {
  static bool get isWeb => kIsWeb;

  static Future<String> getTempPath() async {
    if (isWeb) {
      return ''; // Web doesn't use file paths for recording
    } else {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
  }

  static String joinPath(String dir, String fileName) {
    if (isWeb) return fileName;
    return '$dir/$fileName';
  }
}
