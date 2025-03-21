import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_crdt/flutter_crdt.dart';
import 'package:get/get.dart';
import 'package:isar/isar.dart';
import 'package:wenznote/editor/crdt/YsText.dart';
import 'package:wenznote/editor/crdt/doc_utils.dart';
import 'package:wenznote/model/note/po/doc_state_po.dart';
import 'package:wenznote/service/service_manager.dart';

/// 读取数据 = 读取全量数据(离线)+读取合并数据(用户)+增量数据(用户)
/// 写入数据 = 写入全量数据+写入增量数据
/// 每500个增量合并一次
class DocEditService {
  ServiceManager serviceManager;

  DocEditService(this.serviceManager);

  final _fileCache = <String, Uint8List>{};
  final _docCache = <String, Doc>{};
  final _updateCache = <String, Uint8List>{};

  Future<String> getNoteDir() async {
    return serviceManager.fileManager.getDocDir();
  }

  Future<String> getNoteFilePath(String docId) async {
    var noteDir = await getNoteDir();
    if (!await Directory(noteDir).exists()) {
      await Directory(noteDir).create(recursive: true);
    }
    return "$noteDir/$docId.wnote";
  }

  Future<Uint8List?> readDocFile(String? docId) async {
    if (docId == null || docId.isEmpty) {
      return null;
    }
    var item = _fileCache[docId];
    if (item != null) {
      return item;
    }
    var noteFile = File(await getNoteFilePath(docId));
    if (noteFile.existsSync()) {
      var result = await noteFile.readAsBytes();
      _fileCache[docId] = result;
      return result;
    }
    return null;
  }

  Future<void> writeDocFile(String? docId, Uint8List data) async {
    if (docId == null || docId.isEmpty) {
      return;
    }
    var noteFile = File(await getNoteFilePath(docId));
    await noteFile.writeAsBytes(data);
    _fileCache[docId] = data;
  }

  Future<Doc?> readDoc(String? docId) async {
    if (docId == null) {
      return null;
    }
    var doc = _docCache[docId];
    if (doc != null) {
      return doc;
    }
    // 如何将读取耗时控制在一定范围内？
    var bytes = await readDocFile(docId);
    if (bytes == null) {
      return null;
    }
    try {
      Doc result = Doc()..clientID = serviceManager.userService.clientId;
      try {
        applyUpdateV2(result, bytes, null);
      } catch (e) {
        applyUpdate(result, bytes, null);
      }
      _docCache[docId] = result;
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<void> writeDoc(
    String? docId,
    Doc doc, {
    bool needUpload = true,
  }) async {
    if (docId == null) {
      return;
    }
    useV2Encoding();
    var bytes = encodeStateAsUpdate(doc, null);
    _docCache[docId] = doc;
    await writeDocFile(docId, bytes);
    // 更新doc state
    var isar = serviceManager.isarService.documentIsar;
    var clientId = serviceManager.userService.clientId;
    var state = await isar.docStatePOs
        .filter()
        .docIdEqualTo(docId)
        .clientIdEqualTo(clientId)
        .findFirst();
    state ??= DocStatePO(docId: docId, clientId: clientId);
    state.updateTime = DateTime.now().millisecondsSinceEpoch;
    await isar.writeTxn(() => isar.docStatePOs.put(state!));
    // 增加上传快照任务
    if (needUpload) {
      serviceManager.uploadTaskService.uploadDoc(docId);
    }
  }

  Future<void> deleteDocFile(String docId) async {
    _docCache.remove(docId);
    _fileCache.remove(docId);
    var path = await getNoteFilePath(docId);
    try {
      File(path).deleteSync();
    } catch (e) {
      e.printError();
    }
  }

  Future<bool> updateDoc(
    String docId,
    Uint8List delta, {
    bool needUpload = true,
  }) async {
    _updateCache[docId] = delta;
    var doc = await readDoc(docId);
    doc ??= Doc()..clientID = serviceManager.userService.clientId;
    var startSnap = encodeSnapshotV2(snapshot(doc), null);
    applyUpdateV2(doc, delta, null);
    writeDoc(docId, doc, needUpload: needUpload);
    var endSnap = encodeSnapshotV2(snapshot(doc), null);
    return !_equalsSnapShot(startSnap, endSnap);
  }

  String readDocToJson(Uint8List data) {
    var doc = Doc();
    applyUpdateV2(doc, data, null);
    return jsonEncode(doc.toJSON());
  }

  bool isInUpdateCache(String docId, Uint8List delta) {
    var cache = _updateCache[docId];
    if (cache == null) {
      return false;
    }
    if (cache.length != delta.length) {
      return false;
    }
    for (var i = 0; i < cache.length; i++) {
      if (cache[i] != delta[i]) {
        return false;
      }
    }
    return true;
  }

  bool _equalsSnapShot(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> saveDocStringFile(String? uuid, String? content) async {
    if (uuid == null) {
      return;
    }
    var doc = await jsonToYDoc(serviceManager.userService.clientId, content);
    await writeDoc(uuid, doc);
  }

  Doc createDoc() {
    var doc = Doc();
    doc.clientID = serviceManager.userService.clientId;
    doc.getArray("blocks").insert(0, [createEmptyTextYMap()]);
    return doc;
  }

  Future<Uint8List?> queryDocDelta(String dataId, List<int> content) async {
    var doc = await readDoc(dataId);
    if (doc == null) {
      return null;
    }
    return encodeStateAsUpdateV2(doc, Uint8List.fromList(content));
  }

  Future<Uint8List?> queryDocSnap(String docId) async {
    var doc = await readDoc(docId);
    if (doc == null) {
      return null;
    }
    return encodeStateVectorV2(doc);
  }
}
