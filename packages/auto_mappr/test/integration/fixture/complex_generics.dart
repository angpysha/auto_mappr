import 'package:auto_mappr_annotation/auto_mappr_annotation.dart';
import 'package:equatable/equatable.dart';

import 'complex_generics.auto_mappr.dart';

@AutoMappr([
  // Deep nested generics (simulating GraphQL-like generated types)
  MapType<QueryGetUserInfoUserInfoItem, ApiResultSuccess>(),
  MapType<QueryGetUserInfoUserInfo, ApiResultSuccess>(),
  MapType<QueryGetUserInfo, ApiResultSuccess>(),
  // Generic with nullable type parameters
  MapType<Container<String?>, Container<String?>>(),
  MapType<Container<String>, Container<String>>(),
  MapType<Container<int?>, Container<int?>>(),
  MapType<Container<int>, Container<int>>(),
  // Multiple nested generics
  MapType<Wrapper<Inner<Data>>, Wrapper<Inner<Data>>>(),
  MapType<Wrapper<Inner<Data?>>, Wrapper<Inner<Data?>>>(),
  // Generic result types
  MapType<Result<String>, Result<String>>(),
  MapType<Result<String?>, Result<String?>>(),
  MapType<Result<int>, Result<int>>(),
])
class Mappr extends $Mappr {
  const Mappr();
}

// Simulating GraphQL-like generated types with deep nesting
class QueryGetUserInfo {
  final QueryGetUserInfoUserInfo? userInfo;

  const QueryGetUserInfo({this.userInfo});
}

class QueryGetUserInfoUserInfo {
  final List<QueryGetUserInfoUserInfoItem?>? items;

  const QueryGetUserInfoUserInfo({this.items});
}

class QueryGetUserInfoUserInfoItem {
  final String id;
  final String name;

  const QueryGetUserInfoUserInfoItem({required this.id, required this.name});
}

class ApiResultSuccess extends Equatable {
  final String? id;
  final String? name;

  @override
  List<Object?> get props => [id, name];

  const ApiResultSuccess({this.id, this.name});
}

// Generic container types
class Container<T> extends Equatable {
  final T? value;

  @override
  List<Object?> get props => [value];

  const Container(this.value);
}

// Nested generic types
class Wrapper<T> extends Equatable {
  final T inner;

  @override
  List<Object?> get props => [inner];

  const Wrapper(this.inner);
}

class Inner<T> extends Equatable {
  final T data;

  @override
  List<Object?> get props => [data];

  const Inner(this.data);
}

class Data extends Equatable {
  final String value;

  @override
  List<Object?> get props => [value];

  const Data(this.value);
}

// Generic result type
class Result<T> extends Equatable {
  final T? data;
  final bool success;

  @override
  List<Object?> get props => [data, success];

  const Result({this.data, required this.success});
}

