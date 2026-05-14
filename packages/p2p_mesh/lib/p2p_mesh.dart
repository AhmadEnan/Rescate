library p2p_mesh;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mesh_network/flutter_mesh_network.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:security_crypto/security_crypto.dart';

class Peer {
  final String nodeId;
  final String displayName;
  final int lastSeen;
  final bool inRange;

  Peer({
    required this.nodeId,
    required this.displayName,
    required this.lastSeen,
    required this.inRange,
  });

  Map<String, dynamic> toMap() {
    return {
      'nodeId': nodeId,
      'displayName': displayName,
      'lastSeen': lastSeen,
      'inRange': inRange ? 1 : 0,
    };
  }

  factory Peer.fromMap(Map<String, dynamic> map) {
    return Peer(
      nodeId: map['nodeId'],
      displayName: map['displayName'],
      lastSeen: map['lastSeen'],
      inRange: map['inRange'] == 1,
    );
  }
}

class ChatMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String? recipientId;
  final bool isOutgoing;
  final String payloadText;
  final int timestamp;
  final String status;

  ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    this.recipientId,
    required this.isOutgoing,
    required this.payloadText,
    required this.timestamp,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'recipientId': recipientId,
      'isOutgoing': isOutgoing ? 1 : 0,
      'payloadText': payloadText,
      'timestamp': timestamp,
      'status': status,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      senderName: map['senderName'],
      recipientId: map['recipientId'],
      isOutgoing: map['isOutgoing'] == 1,
      payloadText: map['payloadText'],
      timestamp: map['timestamp'],
      status: map['status'],
    );
  }
}

class MeshProvider extends ChangeNotifier {
  static const String _serviceName = 'rescate-mesh';
  final _uuid = const Uuid();
  late MeshNetwork _mesh;
  late Database _db;
  
  String _myNodeId = '';
  String _myDisplayName = 'Anonymous';
  bool _isMeshEnabled = false;

  List<Peer> _peers = [];
  List<ChatMessage> _publicMessages = [];
  Map<String, List<ChatMessage>> _privateMessages = {};

  String get myNodeId => _myNodeId;
  String get myDisplayName => _myDisplayName;
  bool get isMeshEnabled => _isMeshEnabled;
  List<Peer> get peers => _peers;
  List<ChatMessage> get publicMessages => _publicMessages;

  Future<void> init() async {
    _myNodeId = _uuid.v4();
    
    if (kIsWeb) {
      debugPrint('Mesh networking and sqflite are not supported on Web. Running in mock UI mode.');
      return;
    }

    try {
      _db = await openDatabase(
        join(await getDatabasesPath(), 'mesh_chat.db'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE peers(nodeId TEXT PRIMARY KEY, displayName TEXT, lastSeen INTEGER, inRange INTEGER)',
          );
          await db.execute(
            'CREATE TABLE messages(messageId TEXT PRIMARY KEY, senderId TEXT, senderName TEXT, recipientId TEXT, isOutgoing INTEGER, payloadText TEXT, timestamp INTEGER, status TEXT)',
          );
        },
        version: 1,
      );
      await _loadFromDb();
    } catch (e) {
      debugPrint('Failed to initialize sqflite. Are you running on an unsupported desktop platform? Error: $e');
    }
  }

  Future<void> _loadFromDb() async {
    final peerMaps = await _db.query('peers');
    _peers = peerMaps.map((m) => Peer.fromMap(m)).toList();
    
    final msgMaps = await _db.query('messages', orderBy: 'timestamp ASC');
    final allMsgs = msgMaps.map((m) => ChatMessage.fromMap(m)).toList();
    
    _publicMessages = allMsgs.where((m) => m.recipientId == null).toList();
    _privateMessages.clear();
    for (var m in allMsgs) {
      if (m.recipientId != null) {
        final otherId = m.isOutgoing ? m.recipientId! : m.senderId;
        _privateMessages[otherId] = _privateMessages[otherId] ?? [];
        _privateMessages[otherId]!.add(m);
      }
    }
    notifyListeners();
  }

  Future<void> setDisplayName(String name) async {
    _myDisplayName = name;
    notifyListeners();
  }

  Future<void> toggleMesh(bool enable) async {
    if (enable == _isMeshEnabled) return;
    
    if (enable) {
      if (kIsWeb) {
        debugPrint('Mesh networking is mocked on Web.');
        _isMeshEnabled = true;
        notifyListeners();
        return;
      }
      _mesh = MeshNetwork(
        config: const MeshConfig(
          serviceName: _serviceName,
          maxHops: 10,
        ),
      );
      
      _mesh.onNodeChanged.listen((node) async {
        final idx = _peers.indexWhere((p) => p.nodeId == node.id);
        final isOnline = node.isOnline();
        if (idx >= 0) {
          _peers[idx] = Peer(nodeId: node.id, displayName: node.name, lastSeen: DateTime.now().millisecondsSinceEpoch, inRange: isOnline);
          try { await _db.update('peers', _peers[idx].toMap(), where: 'nodeId = ?', whereArgs: [node.id]); } catch (_) {}
        } else {
          final p = Peer(nodeId: node.id, displayName: node.name, lastSeen: DateTime.now().millisecondsSinceEpoch, inRange: isOnline);
          _peers.add(p);
          try { await _db.insert('peers', p.toMap()); } catch (_) {}
        }
        notifyListeners();
      });

      _mesh.onMessage.listen((msg) async {
        final chatMsg = ChatMessage(
          messageId: _uuid.v4(),
          senderId: msg.senderId,
          senderName: msg.senderName,
          recipientId: msg.targetId,
          isOutgoing: false,
          payloadText: msg.payload,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: 'delivered',
        );
        try { await _db.insert('messages', chatMsg.toMap()); } catch (_) {}
        await _loadFromDb();
      });

      await _mesh.start(userId: _myNodeId, userName: _myDisplayName);
      _isMeshEnabled = true;
    } else {
      if (!kIsWeb) {
        await _mesh.dispose();
      }
      _isMeshEnabled = false;
      // Mark all offline
      for (int i=0; i<_peers.length; i++) {
        _peers[i] = Peer(nodeId: _peers[i].nodeId, displayName: _peers[i].displayName, lastSeen: _peers[i].lastSeen, inRange: false);
      }
    }
    notifyListeners();
  }

  Future<void> sendPublicMessage(String text) async {
    final msg = ChatMessage(
      messageId: _uuid.v4(),
      senderId: _myNodeId,
      senderName: _myDisplayName,
      recipientId: null,
      isOutgoing: true,
      payloadText: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: _isMeshEnabled ? 'sent' : 'queued',
    );
    _publicMessages.add(msg);
    notifyListeners();
    
    if (kIsWeb) return;
    try { await _db.insert('messages', msg.toMap()); } catch (_) {}
    
    if (_isMeshEnabled) {
      await _mesh.sendText(text);
    }
    await _loadFromDb();
  }

  Future<void> sendPrivateMessage(String targetId, String text) async {
    final msg = ChatMessage(
      messageId: _uuid.v4(),
      senderId: _myNodeId,
      senderName: _myDisplayName,
      recipientId: targetId,
      isOutgoing: true,
      payloadText: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: _isMeshEnabled ? 'sent' : 'queued',
    );
    _privateMessages[targetId] = _privateMessages[targetId] ?? [];
    _privateMessages[targetId]!.add(msg);
    notifyListeners();
    
    if (kIsWeb) return;
    try { await _db.insert('messages', msg.toMap()); } catch (_) {}
    
    if (_isMeshEnabled) {
      await _mesh.sendText(text, targetId: targetId);
    }
    await _loadFromDb();
  }

  List<ChatMessage> getMessagesForPeer(String peerId) {
    return _privateMessages[peerId] ?? [];
  }
}

// ── InheritedWidget wrapper ─────────────────────────────────────────────────────
// Provides [MeshProvider] down the widget tree via MeshInheritedProvider.of(context).

class MeshInheritedProvider extends InheritedNotifier<MeshProvider> {
  const MeshInheritedProvider({
    super.key,
    required MeshProvider notifier,
    required super.child,
  }) : super(notifier: notifier);

  static MeshProvider of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MeshInheritedProvider>()!
        .notifier!;
  }
}
