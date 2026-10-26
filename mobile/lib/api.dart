import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Json = Map<String, dynamic>;
final apiProvider = Provider((ref) => Api());
final sessionProvider = StateProvider<bool>((ref) => false);
final revisionProvider = StateProvider<int>((ref) => 0);
final themeProvider = StateProvider<String>((ref) => 'system');

class Api {
  static const base = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1/',
  );
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
    ),
  );
  final storage = const FlutterSecureStorage();
  String? access;
  Future<void>? _refreshing;
  Api() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (access != null) {
            options.headers['Authorization'] = 'Bearer $access';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              error.requestOptions.extra['retried'] != true &&
              !error.requestOptions.path.startsWith('auth/')) {
            try {
              _refreshing ??= refresh();
              await _refreshing;
              _refreshing = null;
              final options = error.requestOptions;
              options.extra['retried'] = true;
              options.headers['Authorization'] = 'Bearer $access';
              if (options.data is FormData) {
                options.data = (options.data as FormData).clone();
              }
              try {
                handler.resolve(await dio.fetch(options));
              } on DioException catch (retryError) {
                handler.next(retryError);
              }
              return;
            } catch (_) {
              _refreshing = null;
              access = null;
            }
          }
          handler.next(error);
        },
      ),
    );
  }
  Future<void> tokens(Json data) async {
    access = data['access'];
    await storage.write(key: 'refresh', value: data['refresh']);
  }

  Future<void> refresh() async {
    final token = await storage.read(key: 'refresh');
    if (token == null) throw StateError('Please sign in.');
    final response = await Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    ).post('auth/refresh/', data: {'refresh': token});
    await tokens(Map<String, dynamic>.from(response.data));
  }

  Future<bool> restore() async {
    try {
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> authenticate(
    String email,
    String password,
    bool register,
  ) async {
    final response = await dio.post(
      'auth/${register ? 'register' : 'login'}/',
      data: {
        'email': email.trim().toLowerCase(),
        'password': password,
        if (register) 'consent': true,
      },
    );
    await tokens(Map<String, dynamic>.from(response.data));
  }

  Future<void> logout() async {
    final token = await storage.read(key: 'refresh');
    try {
      if (token != null) {
        await dio.post('auth/logout/', data: {'refresh': token});
      }
    } on DioException {
      // Offline/expired sessions must still be removable from this device.
    } finally {
      access = null;
      await storage.delete(key: 'refresh');
    }
  }

  Future<dynamic> get(String path, {Json? query}) async =>
      (await dio.get(path, queryParameters: query)).data;
  Future<dynamic> post(String path, Json data) async =>
      (await dio.post(path, data: data)).data;
  Future<dynamic> patch(String path, Json data) async =>
      (await dio.patch(path, data: data)).data;
  Future<void> delete(String path, {Json? data}) async {
    await dio.delete(path, data: data);
  }

  Future<Json> upload(
    List<int> bytes,
    String name,
    void Function(double) progress,
  ) async {
    final response = await dio.post(
      'receipts/upload/',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: name),
      }),
      onSendProgress: (sent, total) {
        if (total > 0) progress(sent / total);
      },
    );
    return Map<String, dynamic>.from(response.data);
  }
}

String errorText(Object error) {
  if (error is DioException) {
    if (error.response != null) return jsonEncode(error.response!.data);
    return 'Could not reach BasketWise. Check your connection and try again.';
  }
  return error.toString().replaceFirst('Bad state: ', '');
}
