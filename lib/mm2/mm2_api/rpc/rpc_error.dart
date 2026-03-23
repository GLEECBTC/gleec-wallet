import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error_type.dart';

/// Legacy RPC exception class.
///
/// This class is deprecated. Use [MmRpcException] and its subclasses from
/// `package:komodo_defi_rpc_methods` instead. The [KdfErrorRegistry] provides
/// automatic parsing of error responses into typed exceptions.
///
/// Example migration:
/// ```dart
/// // Old code:
/// try {
///   await someRpcCall();
/// } on RpcException catch (e) {
///   print(e.error.errorType);
/// }
///
/// // New code:
/// try {
///   await someRpcCall();
/// } on MmRpcException catch (e) {
///   switch (e) {
///     case AccountRpcErrorNameTooLongException():
///       // Handle specific error
///     // ... other cases
///   }
/// }
/// ```
@Deprecated(
  'Use MmRpcException and its subclasses from package:komodo_defi_rpc_methods '
  'instead. See KdfErrorRegistry for automatic error parsing.',
)
class RpcException implements Exception {
  const RpcException(this.error);

  final RpcError error;

  @override
  String toString() {
    return 'RpcException: ${error.error}';
  }
}

/// Legacy RPC error data class.
///
/// This class is deprecated. Use [GeneralErrorResponse] from
/// `package:komodo_defi_rpc_methods` for error data, or catch typed
/// [MmRpcException] subclasses which contain the error data as fields.
@Deprecated(
  'Use GeneralErrorResponse or typed MmRpcException subclasses from '
  'package:komodo_defi_rpc_methods instead.',
)
class RpcError extends Equatable {
  const RpcError({
    this.mmrpc,
    this.error,
    this.errorPath,
    this.errorTrace,
    this.errorType,
    this.errorData,
    this.id,
  });

  factory RpcError.fromJson(Map<String, dynamic> json) {
    // Handle nested error format where RPC error is in 'message' field
    if (json.containsKey('message') && json['message'] is String) {
      try {
        final Map<String, dynamic> nestedError =
            jsonDecode(json['message'] as String) as Map<String, dynamic>;
        return RpcError._fromDirectJson(nestedError);
      } catch (_) {
        // If parsing fails, fall back to treating message as error string
        return RpcError(
          error: json['message'] as String?,
          errorData: json['error'] as String?,
        );
      }
    }

    return RpcError._fromDirectJson(json);
  }

  factory RpcError._fromDirectJson(Map<String, dynamic> json) => RpcError(
    mmrpc: json['mmrpc'] as String?,
    error: json['error'] as String?,
    errorPath: json['error_path'] as String?,
    errorTrace: json['error_trace'] as String?,
    errorType: json['error_type'] != null
        ? RpcErrorType.fromString(json['error_type'] as String)
        : null,
    errorData: json['error_data'] as String?,
    id: (json['id'] as num?)?.toInt(),
  );

  final String? mmrpc;
  final String? error;
  final String? errorPath;
  final String? errorTrace;
  final RpcErrorType? errorType;
  final String? errorData;
  final int? id;

  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'error': error,
    'error_path': errorPath,
    'error_trace': errorTrace,
    'error_type': errorType?.toString(),
    'error_data': errorData,
    'id': id,
  };

  RpcError copyWith({
    String? mmrpc,
    String? error,
    String? errorPath,
    String? errorTrace,
    RpcErrorType? errorType,
    String? errorData,
    int? id,
  }) {
    return RpcError(
      mmrpc: mmrpc ?? this.mmrpc,
      error: error ?? this.error,
      errorPath: errorPath ?? this.errorPath,
      errorTrace: errorTrace ?? this.errorTrace,
      errorType: errorType ?? this.errorType,
      errorData: errorData ?? this.errorData,
      id: id ?? this.id,
    );
  }

  @override
  String toString() {
    return '''
RpcError: {
  mmrpc: $mmrpc,
  error: $error,
  errorPath: $errorPath,
  errorTrace: $errorTrace,
  errorType: $errorType,
  errorData: $errorData,
  id: $id
}''';
  }

  @override
  List<Object?> get props {
    return [mmrpc, error, errorPath, errorTrace, errorType, errorData, id];
  }
}
