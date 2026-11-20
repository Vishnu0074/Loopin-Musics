import 'dart:convert';
import 'app_storage.dart';
import 'package:http/http.dart' as http;
import '../models/auth_user.dart';

class AuthException implements Exception { final String message; final int? statusCode; const AuthException(this.message, {this.statusCode}); @override String toString()=>message; }

class AuthService {
  static const baseUrl=String.fromEnvironment('LOOPIN_API_URL',defaultValue:'https://loopin-api-xuaf.onrender.com/api');
  static final _storage=AppStorage();
  static Future<void> Function()? onSessionExpired;
  static bool _expirationHandled = false;
  static const _access='loopin_access_token', _refresh='loopin_refresh_token', _user='loopin_auth_user';

  String? _firstError(Map<String,dynamic> data){for(final v in data.values){if(v is List&&v.isNotEmpty)return v.first.toString();if(v is Map&&v.isNotEmpty)return _firstError(v.cast<String,dynamic>());if(v is String)return v;}return null;}
  Map<String,dynamic> _decode(http.Response r){if(r.body.isEmpty)return {}; final d=jsonDecode(r.body);return d is Map<String,dynamic>?d:Map<String,dynamic>.from(d as Map);}

  Future<Map<String,dynamic>> _request(String method,String path,{Map<String,dynamic>? body,bool authenticated=true,bool retry=true}) async {
    var token=await accessToken();
    final headers=<String,String>{'Content-Type':'application/json'};
    if(authenticated&&token!=null)headers['Authorization']='Bearer $token';
    final uri=Uri.parse('$baseUrl$path');
    http.Response r;
    try {
      if(method=='GET') {
        r=await http.get(uri,headers:headers).timeout(const Duration(seconds:20));
      } else if(method=='DELETE') {
        r=await http.delete(uri,headers:headers).timeout(const Duration(seconds:20));
      } else if(method=='PATCH') {
        r=await http.patch(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:20));
      } else {
        r=await http.post(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:20));
      }
    } on Exception catch (_) {
      throw AuthException('Unable to reach Loopin right now. Please check your connection and try again.');
    }
    if (r.statusCode == 401 && authenticated) {
      if (retry) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          return _request(method, path, body: body, authenticated: true, retry: false);
        }
      }
      await _expireSession();
    }
    final data=_decode(r);
    if(r.statusCode<200||r.statusCode>=300)throw AuthException(data['detail']?.toString()??_firstError(data)??'Request failed (undefined).', statusCode: r.statusCode);
    return data;
  }

  Future<AuthUser> login(String email,String password) async {final d=await _request('POST','/auth/login/',body:{'email':email,'password':password},authenticated:false);await _save(d);return AuthUser.fromJson(d['user']);}
  Future<void> register({required String email,required String phone,required String password,required String passwordConfirm}) async {await _request('POST','/auth/register/',body:{'email':email,'phone_number':phone,'password':password,'password_confirm':passwordConfirm},authenticated:false);}
  Future<void> _save(Map<String,dynamic> d) async {_expirationHandled=false;await _storage.write(key:_access,value:d['access']?.toString());await _storage.write(key:_refresh,value:d['refresh']?.toString());if(d['user'] is Map)await _storage.write(key:_user,value:jsonEncode(d['user']));}
  Future<String?> accessToken()=>_storage.read(key:_access);
  Future<String?> _refreshToken()=>_storage.read(key:_refresh);
  Future<bool> refreshAccessToken() async {final refresh=await _refreshToken();if(refresh==null)return false;try{final r=await http.post(Uri.parse('$baseUrl/auth/token/refresh/'),headers:{'Content-Type':'application/json'},body:jsonEncode({'refresh':refresh})).timeout(const Duration(seconds:15));if(r.statusCode==200){final d=_decode(r);await _storage.write(key:_access,value:d['access']?.toString());if(d['refresh']!=null)await _storage.write(key:_refresh,value:d['refresh']?.toString());return true;}if(r.statusCode==400||r.statusCode==401){await _expireSession();return false;}return false;}catch(_){return false;}}
  Future<AuthUser?> restore() async {
    final token = await accessToken();
    final refresh = await _refreshToken();
    if (token == null && refresh == null) return null;

    // Restore the cached identity first. A cold API instance or slow mobile
    // connection must not hold the user on the splash screen for the 20s
    // request timeout. Authenticated API calls refresh expired tokens on 401.
    final cached = await _storage.read(key: _user);
    if (cached != null && cached.isNotEmpty) {
      try {
        return AuthUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {
        // Invalid cache: fall through to the authoritative profile request.
      }
    }

    try {
      final data = await _request('GET', '/auth/me/').timeout(
        const Duration(seconds: 5),
      );
      final user = AuthUser.fromJson(data);
      await _storage.write(key: _user, value: jsonEncode(data));
      return user;
    } catch (_) {
      return null;
    }
  }
  Future<Map<String,dynamic>> get(String path,{bool authenticated=true})=>_request('GET',path,authenticated:authenticated);
  Future<Map<String,dynamic>> patch(String path,Map<String,dynamic> body)=>_request('PATCH',path,body:body);
  Future<Map<String,dynamic>> post(String path,Map<String,dynamic> body,{bool authenticated=true})=>_request('POST',path,body:body,authenticated:authenticated);
  Future<void> delete(String path) async { await _request('DELETE',path); }
  Future<void> _expireSession() async {
    if (_expirationHandled) return;
    _expirationHandled = true;
    await logout();
    await onSessionExpired?.call();
  }

  Future<void> logout() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _user);
  }
}
