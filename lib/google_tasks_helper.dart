import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/tasks/v1.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class GoogleTasksHelper {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      TasksApi.tasksScope,
    ],
  );

  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (error) {
      print('Google Sign-In Error: $error');
      return null;
    }
  }

  static Future<void> signOut() => _googleSignIn.signOut();

  static Future<bool> addTask(String title, {String? notes, String? priority}) async {
    try {
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) return false;

      final tasksApi = TasksApi(authClient);
      
      final task = Task(
        title: title,
        notes: '${notes ?? ""}\nPriority: ${priority ?? "Medium"}\nAdded via MindSort',
      );

      // Add to default task list (@default)
      await tasksApi.tasks.insert(task, '@default');
      return true;
    } catch (e) {
      print('Error adding task to Google: $e');
      return false;
    }
  }

  static Future<bool> isConnected() async {
    return await _googleSignIn.isSignedIn();
  }
}
