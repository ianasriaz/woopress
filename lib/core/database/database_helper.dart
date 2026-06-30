import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  // In-memory fallbacks for Web
  List<Map<String, dynamic>> _webCache = [];
  List<Map<String, dynamic>> _webSyncQueue = [];

  DatabaseHelper._init();

  Future<Database?> get database async {
    if (kIsWeb) return null; // sqflite is not supported on web
    if (_database != null) return _database!;
    _database = await _initDB('wooexpress.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE cached_orders (
  id INTEGER PRIMARY KEY,
  status TEXT NOT NULL,
  search_term TEXT,
  payload TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL,
  action_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');
  }

  // --- Orders Cache Methods ---
  
  Future<void> cacheOrders(List<dynamic> ordersJson) async {
    if (kIsWeb) {
      _webCache.clear();
      for (var order in ordersJson) {
        _webCache.add({
          'id': order['id'],
          'status': order['status'] ?? '',
          'search_term': '${order['number']} ${order['billing']?['first_name']} ${order['billing']?['last_name']} ${order['billing']?['phone']} ${order['billing']?['email']}'.toLowerCase(),
          'payload': jsonEncode(order),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return;
    }

    final db = await instance.database;
    if (db == null) return;
    Batch batch = db.batch();
    
    // Clear old cache before replacing to avoid huge size
    batch.delete('cached_orders');
    
    for (var order in ordersJson) {
      batch.insert('cached_orders', {
        'id': order['id'],
        'status': order['status'] ?? '',
        'search_term': '${order['number']} ${order['billing']?['first_name']} ${order['billing']?['last_name']} ${order['billing']?['phone']} ${order['billing']?['email']}'.toLowerCase(),
        'payload': jsonEncode(order),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
  
  Future<List<Map<String, dynamic>>> getCachedOrders({String? status, String? search}) async {
    if (kIsWeb) {
      var results = _webCache;
      if (status != null && status != 'all') {
        results = results.where((o) => o['status'] == status).toList();
      }
      if (search != null && search.isNotEmpty) {
        final st = search.toLowerCase();
        results = results.where((o) => (o['search_term'] as String).contains(st)).toList();
      }
      return results.map((row) => jsonDecode(row['payload'] as String) as Map<String, dynamic>).toList();
    }

    final db = await instance.database;
    if (db == null) return [];
    
    String where = '';
    List<dynamic> whereArgs = [];
    
    if (status != null && status != 'all') {
      where += 'status = ?';
      whereArgs.add(status);
    }
    
    if (search != null && search.isNotEmpty) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'search_term LIKE ?';
      whereArgs.add('%${search.toLowerCase()}%');
    }
    
    final result = await db.query(
      'cached_orders',
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'id DESC', // Highest ID first
    );
    
    return result.map((row) => jsonDecode(row['payload'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> updateCachedOrder(int orderId, Map<String, dynamic> updatedOrderJson) async {
    if (kIsWeb) {
      final index = _webCache.indexWhere((o) => o['id'] == orderId);
      if (index != -1) {
        _webCache[index]['status'] = updatedOrderJson['status'] ?? '';
        _webCache[index]['payload'] = jsonEncode(updatedOrderJson);
      }
      return;
    }

    final db = await instance.database;
    if (db == null) return;
    await db.update(
      'cached_orders',
      {
        'status': updatedOrderJson['status'] ?? '',
        'payload': jsonEncode(updatedOrderJson),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }
  
  Future<Map<String, dynamic>?> getCachedOrder(int orderId) async {
    if (kIsWeb) {
      final order = _webCache.where((o) => o['id'] == orderId).firstOrNull;
      if (order != null) return jsonDecode(order['payload'] as String);
      return null;
    }

    final db = await instance.database;
    if (db == null) return null;
    final result = await db.query('cached_orders', where: 'id = ?', whereArgs: [orderId]);
    if (result.isNotEmpty) {
      return jsonDecode(result.first['payload'] as String);
    }
    return null;
  }

  // --- Sync Queue Methods ---

  Future<void> enqueueSyncAction(int orderId, String actionType, Map<String, dynamic> payload) async {
    if (kIsWeb) {
      _webSyncQueue.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'order_id': orderId,
        'action_type': actionType,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }

    final db = await instance.database;
    if (db == null) return;
    await db.insert('sync_queue', {
      'order_id': orderId,
      'action_type': actionType,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncActions() async {
    if (kIsWeb) return List.from(_webSyncQueue);
    
    final db = await instance.database;
    if (db == null) return [];
    return await db.query('sync_queue', orderBy: 'created_at ASC');
  }

  Future<void> removeSyncAction(int id) async {
    if (kIsWeb) {
      _webSyncQueue.removeWhere((q) => q['id'] == id);
      return;
    }
    final db = await instance.database;
    if (db == null) return;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<int> getPendingSyncCount() async {
    if (kIsWeb) return _webSyncQueue.length;
    
    final db = await instance.database;
    if (db == null) return 0;
    final result = await db.rawQuery('SELECT COUNT(*) FROM sync_queue');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
