import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/failures.dart';
import '../data/services/backup_service.dart';

/// 文件出入口：备份导出/导入、恢复前自动快照、CSV 分享、工资条存相册。
///
/// 导出走系统文件选择器（SAF），不申请存储权限；
/// 自动快照写在 App 私有目录，用户看不到但可用于回退。
class FileService {
  /// 让用户选位置保存文本文件。返回保存位置（用户取消则 null）。
  Future<Uri?> exportText(
    String text,
    String fileName, {
    String mimeType = 'application/json',
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    return FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: '保存到手机',
    );
  }

  /// 选一个文本文件并读出内容。自动去掉 UTF-8 BOM。
  Future<String?> pickTextFile({List<String> extensions = const ['json']}) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      dialogTitle: '选择文件',
    );
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    return _decodeText(bytes);
  }

  String _decodeText(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return text;
  }

  /// 恢复前自动备份当前账本（App 私有目录，最多保留 5 份）。
  Future<String> persistSafetyBackup(String json) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'safety_backups'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final file = File(
      p.join(
        folder.path,
        BackupService.buildFileName(prefix: '恢复前自动备份'),
      ),
    );
    await file.writeAsString(json, flush: true);
    await _pruneSafetyBackups(folder);
    return file.path;
  }

  Future<void> _pruneSafetyBackups(Directory folder) async {
    final files = await folder
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.length <= 5) return;
    files.sort((a, b) => a.path.compareTo(b.path));
    for (var i = 0; i < files.length - 5; i++) {
      try {
        await files[i].delete();
      } catch (_) {
        // 清理失败不影响主流程
      }
    }
  }

  // ---------------- 分享 ----------------

  /// 把文本写成临时文件，返回路径。CSV/JSON 走系统分享时需要真实文件。
  Future<String> writeTempText(String text, String fileName) async {
    final folder = await _shareFolder();
    final file = File(p.join(folder.path, fileName));
    // CSV 必须带 BOM 才能在 Excel/微信预览里正确识别中文
    await file.writeAsBytes(utf8.encode(text), flush: true);
    return file.path;
  }

  /// 把图片字节写成临时文件，返回路径。
  Future<String> writeTempImage(Uint8List bytes, String fileName) async {
    final folder = await _shareFolder();
    final file = File(p.join(folder.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> _shareFolder() async {
    final dir = await getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'share'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// 系统分享面板（微信、QQ、邮件等）。
  Future<void> shareFiles(
    List<String> paths, {
    String? text,
    String? subject,
  }) async {
    if (paths.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final path in paths) XFile(path)],
        text: text,
        subject: subject,
      ),
    );
  }

  // ---------------- 相册 ----------------

  /// 保存图片到相册（申请权限失败时抛 [AppFailure]）。
  Future<void> saveImagesToGallery(
    List<Uint8List> images, {
    required String namePrefix,
  }) async {
    if (images.isEmpty) return;
    final granted = await Gal.hasPermission() || await Gal.requestPermission();
    if (!granted) {
      throw const FileFailure('没有相册权限，无法保存图片。请到系统设置里允许本应用访问相册');
    }
    for (var index = 0; index < images.length; index++) {
      final suffix = images.length == 1 ? '' : '-${index + 1}';
      await Gal.putImageBytes(
        images[index],
        name: '$namePrefix$suffix',
      );
    }
  }

  /// 清理分享临时目录里的旧图片，避免长期占用空间。
  Future<void> cleanTempShares({Duration olderThan = const Duration(days: 3)}) async {
    try {
      final folder = await _shareFolder();
      final cutoff = DateTime.now().subtract(olderThan);
      await for (final entity in folder.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 清理失败无所谓，系统会回收临时目录
    }
  }
}
