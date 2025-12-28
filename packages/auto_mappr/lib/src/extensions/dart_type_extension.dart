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

    // For nullable types, compare their non-nullable versions
    // This ensures that BDto<int>? matches BDto<int> when withNullability is false
    final thisType = this;
    final otherType = other;
    
    // Get non-nullable versions for comparison if needed
    final thisForComparison = (thisType is InterfaceType && thisType.isNullable && thisType.element?.library != null)
        ? thisType.element!.library!.typeSystem.promoteToNonNull(thisType)
        : thisType;
    final otherForComparison = (otherType is InterfaceType && otherType.isNullable && otherType.element?.library != null)
        ? otherType.element!.library!.typeSystem.promoteToNonNull(otherType)
        : otherType;

    // Not the same type of type.
    if ((thisForComparison is InterfaceType) ^ (otherForComparison is InterfaceType)) {
      return false;
    }

    // Check element name and library first
    final thisElementName = thisForComparison.element?.name;
    final otherElementName = otherForComparison.element?.name;
    if (thisElementName != otherElementName) {
      return false;
    }

    // Library matches.
    final thisLibrary = thisForComparison.element?.library?.uri.toString();
    final otherLibrary = otherForComparison.element?.library?.uri.toString();
    if (thisLibrary != otherLibrary) {
      return false;
    }

    // Check type arguments (including their nullability)
    // This is important: we ALWAYS check type arguments' nullability, even when withNullability: false
    // withNullability: false only means "ignore top-level nullability", not "ignore type arguments' nullability"
    if (thisForComparison is ParameterizedType && otherForComparison is ParameterizedType) {
      final thisParams = thisForComparison as ParameterizedType;
      final otherParams = otherForComparison as ParameterizedType;
      
      if (thisParams.typeArguments.length != otherParams.typeArguments.length) {
        return false;
      }
      
      for (int i = 0; i < thisParams.typeArguments.length; i++) {
        final thisArg = thisParams.typeArguments[i];
        final otherArg = otherParams.typeArguments[i];
        // Recursively compare type arguments with nullability
        // This ensures BDto<String?> does NOT match BDto<String>
        if (!thisArg.isSame(otherArg, withNullability: true)) {
          return false;
        }
      }
    }

    final isSameExceptNullability = true;

    if (!withNullability) {
      return isSameExceptNullability;
    }

    // Nullability matches.
    final thisNullability = thisType.isNullable;
    final otherNullability = otherType.isNullable;
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
        // This ensures that nullable type arguments are properly encoded
        // Use a temporary buffer to check if 'Q' was added by _appendTypeNameForMethod
        final tempBuffer = StringBuffer();
        _appendTypeNameForMethod(arg, tempBuffer, includeTopLevelNullability: true);
        final argName = tempBuffer.toString();
        buffer.write(argName);
        
        // Add nullability marker for nullable type arguments
        // This is crucial: even if _appendTypeNameForMethod already added a 'Q' for top-level nullability,
        // we need to add another 'Q' to encode that the type argument itself is nullable
        // This handles cases like B<String?> where String? is a nullable type argument
        // We check if the arg name ends with 'Q' (from _appendTypeNameForMethod) or if arg is nullable
        // If it ends with 'Q', we add another 'Q' to encode the type argument's nullability
        final isArgNullable = arg.isNullable || 
            arg.nullabilitySuffix == NullabilitySuffix.question ||
            argName.endsWith('Q');
        if (isArgNullable) {
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
