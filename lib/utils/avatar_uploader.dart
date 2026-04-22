import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AvatarUploader {
  static Future<String?> pickAndUploadAvatar({
    required String workerId, // это workers.id (НЕ auth_user_id)
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return null;

    final supabase = Supabase.instance.client;
    final Uint8List bytes = await picked.readAsBytes();

    final fileName = '${const Uuid().v4()}.jpg';
    final path = '$workerId/$fileName';

    await supabase.storage.from('avatars').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      ),
    );

    final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);
    return publicUrl;
  }
}
