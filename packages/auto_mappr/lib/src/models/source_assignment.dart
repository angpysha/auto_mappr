// ignore_for_file: prefer-match-file-name, prefer-single-declaration-per-file

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:auto_mappr/src/extensions/dart_type_extension.dart';
import 'package:auto_mappr/src/helpers/emitter_helper.dart';
import 'package:auto_mappr/src/models/models.dart';
import 'package:auto_mappr/src/models/type_converter.dart';
import 'package:code_builder/code_builder.dart' show Expression, literalList, literalMap, literalNull, literalSet;

class ConstructorAssignment {
  final FormalParameterElement param;
  final int? position;

  bool get isNamed => param.isNamed;

  const ConstructorAssignment({required this.param, this.position});
}

class SourceAssignment {
  final PropertyAccessorElement? sourceField;

  final ConstructorAssignment? targetConstructorParam;
  final PropertyAccessorElement? targetField;

  final List<TypeConverter> typeConverters;

  /// Field mapping.
  ///
  /// Like filed 'name' from 'userName' etc.
  final FieldMapping? fieldMapping;

  /// The instantiated target type (e.g., ApiSubscriptionResult<CategoryProjection>)
  /// Used to resolve generic parameters in field types
  final InterfaceType? instantiatedTargetType;

  /// The type system used for type substitution
  final TypeSystem? typeSystem;

  DartType? get sourceType => sourceField?.returnType;

  String? get sourceName => sourceField?.displayName;

  DartType get targetType {
    final baseType = targetConstructorParam?.param.type ?? targetField!.returnType;
    
    // If we have an instantiated target type, try to substitute generic parameters
    if (instantiatedTargetType != null) {
      return _substituteTypeParameters(baseType, instantiatedTargetType!);
    }
    
    return baseType;
  }

  /// Recursively substitute generic type parameters in a type
  DartType _substituteTypeParameters(DartType type, InterfaceType context) {
    if (type is TypeParameterType) {
      // Find the matching type argument in the instantiated type
      final typeParam = type.element;
      final contextClass = context.element;
      
      // Find the index of this type parameter
      final typeParamIndex = contextClass.typeParameters.indexWhere((p) => p == typeParam);
      
      if (typeParamIndex >= 0 && typeParamIndex < context.typeArguments.length) {
        // Return the concrete type argument
        return context.typeArguments[typeParamIndex];
      }
      
      return type; // Not found, return as is
    } else if (type is InterfaceType && type.typeArguments.isNotEmpty) {
      // If type is parameterized (e.g., RangeSyncResult<T>), substitute its type arguments
      final needsSubstitution = type.typeArguments.any((arg) => arg is TypeParameterType);
      
      if (!needsSubstitution) {
        return type; // No type parameters to substitute
      }
      
      // Substitute each type argument
      final newTypeArguments = type.typeArguments.map((arg) {
        return _substituteTypeParameters(arg, context);
      }).toList();
      
      // Create new InterfaceType with substituted type arguments
      // Preserve nullability
      return type.element.instantiate(
        typeArguments: newTypeArguments,
        nullabilitySuffix: type.nullabilitySuffix,
      );
    }
    
    return type; // Return as is for other types
  }

  String get targetName => targetConstructorParam?.param.displayName ?? targetField!.displayName;

  const SourceAssignment({
    required this.sourceField,
    required this.targetField,
    this.targetConstructorParam,
    this.typeConverters = const [],
    this.fieldMapping,
    this.instantiatedTargetType,
    this.typeSystem,
  });

  bool canAssignIterable() {
    final isCoreIterable = _isCoreIterable(targetType);
    final isSpecializedIntList = targetType.isSpecializedIntListType;
    final isMappableIterable = _isMappableIterable(sourceType!);

    // The source can be mapped to the target, if the source is mappable object and the target is an iterable.
    return (isCoreIterable || isSpecializedIntList) && isMappableIterable;
  }

  bool canAssignMap() {
    // The source can be mapped to the target, if the source is mappable object and the target is map.
    return targetType.isDartCoreMap && _isMappableMap(sourceType!);
  }

  bool canAssignRecord() {
    final isSourceRecord = sourceType is RecordType;
    final isTargetRecord = targetType is RecordType;

    return isSourceRecord && isTargetRecord;
  }

  @override
  String toString() {
    final emittedSource = EmitterHelper.current.typeReferEmitted(type: sourceType);
    final emittedTarget = EmitterHelper.current.typeReferEmitted(type: targetType);

    return '$emittedSource $sourceName -> $emittedTarget $targetName';
  }

  Expression getDefaultValue() {
    if (targetType.isDartCoreList) return literalList([]);
    if (targetType.isDartCoreSet) return literalSet({});
    if (targetType.isDartCoreMap) return literalMap({});

    return literalNull;
  }

  bool _isCoreIterable(DartType type) {
    return type.isDartCoreList || type.isDartCoreSet || type.isDartCoreIterable;
  }

  bool _isMappableIterable(DartType type) {
    if (_isCoreIterable(type)) {
      return true;
    }

    if (type is! InterfaceType) {
      return false;
    }

    return type.allSupertypes.any(_isCoreIterable);
  }

  bool _isMappableMap(DartType type) {
    if (type.isDartCoreMap) {
      return true;
    }

    if (type is! InterfaceType) {
      return false;
    }

    return type.allSupertypes.any((superType) => superType.isDartCoreMap);
  }
}
