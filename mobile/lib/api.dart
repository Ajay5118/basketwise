import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Json = Map<String, dynamic>;
final apiProvider = Provider((ref) => Api());
final sessionProvider = StateProvider<bool>((ref) => false);
final revisionProvider = StateProvider<int>((ref) => 0);
final themeProvider = StateProvider<String>((ref) => 'system');
final shellTabProvider = StateProvider<int>((ref) => 0);
final homeBannerProvider = StateProvider<String?>((ref) => null);

class Api {
  static const _configuredBase = String.fromEnvironment('API_URL');
  static String get base => _configuredBase.isNotEmpty
      ? _configuredBase
      : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000/api/v1/'
      : 'http://localhost:8000/api/v1/';
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
    final status = error.response?.statusCode;
    if (status == 401) {
      return error.requestOptions.path.contains('auth/login')
          ? 'The email or password is incorrect. Please try again.'
          : 'Your session has expired. Please sign in again.';
    }
    if (status == 413) {
      return 'This file is too large. Choose a receipt under 10 MB.';
    }
    if (status == 429) {
      return 'Too many attempts. Please wait a little before trying again.';
    }
    if (status != null && status >= 500) {
      return 'BasketWise is having trouble processing this request. Please try again shortly.';
    }
    final data = error.response?.data;
    if (data is Map) {
      final messages = <String>[];
      void collect(dynamic value, [String? field]) {
        if (value is Map) {
          for (final entry in value.entries) {
            collect(entry.value, entry.key.toString());
          }
        } else if (value is List) {
          for (final item in value) {
            collect(item, field);
          }
        } else if (value is String && value.trim().isNotEmpty) {
          final prefix =
              field == null ||
                  ['detail', 'error', 'non_field_errors'].contains(field)
              ? ''
              : '${field.replaceAll('_', ' ')}: ';
          messages.add('$prefix$value');
        }
      }

      collect(data);
      if (messages.isNotEmpty) return messages.join('\n');
    }
    if (status != null) {
      return 'We couldn’t complete that request. Please check the details and try again.';
    }
    if ([
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ].contains(error.type)) {
      return error.requestOptions.path.contains('receipts/')
          ? 'The connection is taking too long. Your receipt may still be processing. Refresh before uploading again.'
          : 'The connection is taking too long. Please try again.';
    }
    return 'Could not reach BasketWise. Check your connection and try again.';
  }
  return error.toString().replaceFirst('Bad state: ', '');
}
