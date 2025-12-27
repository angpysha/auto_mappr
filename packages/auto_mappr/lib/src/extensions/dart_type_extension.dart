import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:auto_mappr/src/helpers/emitter_helper.dart';
import 'package:code_builder/code_builder.dart';
import 'package:collection/collection.dart';

extension DartTypeExtension on DartType {
  bool get isPrimitiveType =>
      isDartCoreNum ||
      isDartCoreInt ||
      isDartCoreDouble ||
      isDartCoreString ||
      isDartCoreBool ||
      isDartCoreEnum ||
      isDartCoreSymbol;

  bool get isNullable {
    return nullabilitySuffix == NullabilitySuffix.question;
  }

  bool get isNotNullable {
    return !isNullable;
  }

  bool get isDynamic {
    return this is DynamicType;
  }

  /// Is special variant of integer list.
  ///
  /// See `[Uint8List], [Uint16List], [Uint32List], [Uint64List]`.
  bool get isSpecializedIntListType {
    final thisType = this;
    if (thisType is! InterfaceType) return false;

    // ignore: deprecated_member_use, for now use this - w/o this it fails
    return thisType.allSupertypes.any((i) => i.getDisplayString(withNullability: false) == 'List<int>');
  }

  DartType get genericParameterTypeOrSelf => (this as ParameterizedType).typeArguments.firstOrNull ?? this;

  /// Checks name, generics, library
  /// and nullability if [withNullability] is not set.
  bool isSame(DartType? other, {bool withNullability = false}) {
    if (other == null) return false;

    // Not the same type of type.
    if ((this is InterfaceType) ^ (other is InterfaceType)) {
      return false;
    }

    // Name matches.
    // ignore: deprecated_member_use, for now use this - w/o this it fails
    final thisName = getDisplayString(withNullability: withNullability);
    // ignore: deprecated_member_use, for now use this - w/o this it fails
    final otherName = other.getDisplayString(withNullability: withNullability);
    final isSameName = thisName == otherName;

    // Library matches.
    final thisLibrary = element?.library?.uri.toString();
    final otherLibrary = other.element?.library?.uri.toString();
    final isSameLibrary = thisLibrary == otherLibrary;

    final isSameExceptNullability = isSameName && isSameLibrary;

    if (!withNullability) {
      return isSameExceptNullability;
    }

    // Nullability matches.
    final thisNullability = isNullable;
    final otherNullability = other.isNullable;
    final isSameNullability = thisNullability == otherNullability;

    return isSameExceptNullability && isSameNullability;
  }

  Expression defaultIterableExpression() {
    final itemType = genericParameterTypeOrSelf;

    return isDartCoreSet
        ? literalSet({}, EmitterHelper.current.typeRefer(type: itemType))
        : literalList([], EmitterHelper.current.typeRefer(type: itemType));
  }

  String toConvertMethodName({bool includeTopLevelNullability = true}) {
    // Generate method name that preserves nullability information within generic types
    // to avoid collisions like Container<int?> vs Container<int>
    final buffer = StringBuffer();
    _appendTypeNameForMethod(this, buffer, includeTopLevelNullability: includeTopLevelNullability);
    return buffer.toString();
  }

  static void _appendTypeNameForMethod(
    DartType type,
    StringBuffer buffer, {
    bool includeTopLevelNullability = true,
  }) {
    // Handle nullability suffix at the top level - we'll encode it differently
    final isTopLevelNullable = type.isNullable;
    
    // Get the base type name
    final elementName = type.element?.name;
    if (elementName != null) {
      buffer.write(elementName);
    } else {
      // Fallback for types without element (like generic parameters)
      final displayString = type.getDisplayString(withNullability: false);
      final baseName = displayString.split('<').first.split('?').first.trim();
      buffer.write(baseName.isNotEmpty ? baseName : 'dynamic');
    }
    
    // Handle generic type arguments
    if (type is ParameterizedType && type.typeArguments.isNotEmpty) {
      buffer.write(r'$');
      for (int i = 0; i < type.typeArguments.length; i++) {
        if (i > 0) buffer.write('_');
        final arg = type.typeArguments[i];
        // Recursively append type argument name (always include nullability for type arguments)
        _appendTypeNameForMethod(arg, buffer, includeTopLevelNullability: true);
        // Add nullability marker for nullable type arguments
        if (arg.isNullable) {
          buffer.write('Q'); // Q for Question mark (nullable)
        }
      }
      buffer.write(r'$');
    }
    
    // Add nullability marker for top-level nullable types (only if includeTopLevelNullability is true)
    if (includeTopLevelNullability && isTopLevelNullable) {
      buffer.write('Q');
    }
    
    // Replace special characters that might cause issues
    final result = buffer.toString()
        .replaceAll(' ', '')
        .replaceAll('.', r'$')
        .replaceAll(',', r'_$');
    
    buffer.clear();
    buffer.write(result);
  }
}
