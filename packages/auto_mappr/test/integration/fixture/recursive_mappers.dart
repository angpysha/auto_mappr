import 'package:auto_mappr_annotation/auto_mappr_annotation.dart';
import 'package:equatable/equatable.dart';

import 'recursive_mappers.auto_mappr.dart';

@AutoMappr([
  // Single level recursion: ADto<T> -> A<T> contains BDto<T> -> B<T>
  MapType<ADto<int>, A<int>>(),
  MapType<BDto<int>, B<int>>(),
  
  // Two level recursion: ADto<T> -> A<T> contains BDto<T> -> B<T> contains CDto<T> -> C<T>
  MapType<ADto<String>, A<String>>(),
  MapType<BDto<String>, B<String>>(),
  MapType<CDto<String>, C<String>>(),
  
  // Three level recursion with different generic types
  MapType<ADto<num>, A<num>>(),
  MapType<BDto<num>, B<num>>(),
  MapType<CDto<num>, C<num>>(),
  MapType<DDto<num>, D<num>>(),
  
  // Multiple branches: ADto<T> -> A<T> contains both BDto<T> -> B<T> and EDto<T> -> E<T>
  MapType<ADto<bool>, A<bool>>(),
  MapType<BDto<bool>, B<bool>>(),
  MapType<EDto<bool>, E<bool>>(),
  
  // Deep recursion with nullable types
  MapType<ADto<String?>, A<String?>>(),
  MapType<BDto<String?>, B<String?>>(),
  MapType<CDto<String?>, C<String?>>(),
])
class Mappr extends $Mappr {
  const Mappr();
}

// Level 1: ADto<T> -> A<T>
class ADto<T> {
  final T value;
  final BDto<T>? child;

  const ADto({required this.value, this.child});
}

class A<T> extends Equatable {
  final T value;
  final B<T>? child;

  @override
  List<Object?> get props => [value, child];

  const A({required this.value, this.child});
}

// Level 2: BDto<T> -> B<T>
class BDto<T> {
  final T value;
  final CDto<T>? child;

  const BDto({required this.value, this.child});
}

class B<T> extends Equatable {
  final T value;
  final C<T>? child;

  @override
  List<Object?> get props => [value, child];

  const B({required this.value, this.child});
}

// Level 3: CDto<T> -> C<T>
class CDto<T> {
  final T value;
  final DDto<T>? child;

  const CDto({required this.value, this.child});
}

class C<T> extends Equatable {
  final T value;
  final D<T>? child;

  @override
  List<Object?> get props => [value, child];

  const C({required this.value, this.child});
}

// Level 4: DDto<T> -> D<T>
class DDto<T> {
  final T value;

  const DDto({required this.value});
}

class D<T> extends Equatable {
  final T value;

  @override
  List<Object?> get props => [value];

  const D({required this.value});
}

// Alternative branch: EDto<T> -> E<T>
class EDto<T> {
  final T value;

  const EDto({required this.value});
}

class E<T> extends Equatable {
  final T value;

  @override
  List<Object?> get props => [value];

  const E({required this.value});
}

