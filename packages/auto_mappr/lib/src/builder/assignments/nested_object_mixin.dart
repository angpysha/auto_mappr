import 'package:analyzer/dart/element/type.dart';
import 'package:auto_mappr/src/builder/assignments/assignments.dart';
import 'package:auto_mappr/src/builder/methods/method_builder_base.dart';
import 'package:auto_mappr/src/extensions/dart_type_extension.dart';
import 'package:auto_mappr/src/helpers/emitter_helper.dart';
import 'package:auto_mappr/src/models/models.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';

/// Separate logic as a mixin so we do not soil [AssignmentBuilderBase].
mixin NestedObjectMixin on AssignmentBuilderBase {
  /// Assigns nested object as either:
  /// - default value
  /// - call to already generated mapping between two types
  ///
  /// If [convertMethodArgument] is null, uses a tear off call instead.
  Expression assignNestedObject({
    required DartType source,
    required DartType target,
    required SourceAssignment assignment,
    Expression? convertMethodArgument,
    bool includeGenericTypes = false,
  }) {
    final sourceOnModel = AssignmentBuilderBase.modelReference.property(assignment.sourceField!.displayName);
    final fieldMapping = mapping.tryGetFieldMapping(assignment.targetName);
    // Source and target is the same.

    if (source.isSame(target) || source.isDynamic || target.isDynamic) {
      final shouldIgnoreNull =
          fieldMapping?.ignoreNull ??
          mapping.ignoreFieldNull ??
          mapperConfig.mapprOptions.ignoreNullableSourceField ??
          false;

      // Use convertMethodArgument if provided (e.g., from iterable mapping), otherwise use sourceOnModel
      final expressionToUse = convertMethodArgument ?? sourceOnModel;

      // if SOURCE nullable and TARGET not AND ignoreNull is used - use it.
      if ((source.isNullable && target.isNotNullable) && shouldIgnoreNull) {
        return expressionToUse.nullChecked;
      }

      return expressionToUse;
    }

    final nestedMapping = mapperConfig.findMapping(source: source, target: target);

    // Type converters.
    final typeConvertersBuilder = TypeConverterBuilder(
      assignment: assignment,
      mapperConfig: mapperConfig,
      mapping: mapping,
      onUsedNullableMethodCallback: null,
      convertMethodArgument: convertMethodArgument,
      source: source,
      target: target,
    );
    if (typeConvertersBuilder.canAssign()) {
      return typeConvertersBuilder.buildAssignment();
    }

    // Unknown mapping.
    if (nestedMapping == null) {
      final sourceParentClass = assignment.sourceField?.enclosingElement.name;
      final targetParentClass = assignment.targetField?.enclosingElement.name;
      final enclosingMappingMessage = "Parent mapping holding this is '$sourceParentClass' -> '$targetParentClass'";

      // If target is a generic type parameter (TypeParameterType), we can use the source directly
      // The generic parameter will be resolved at runtime when the actual type is known
      final isTargetGenericParameter = target is TypeParameterType;
      
      // Also check if target is a ParameterizedType where all type arguments are TypeParameterType
      // For example, With<T, T> where T is a generic parameter
      final isTargetGenericParameterizedType = target is ParameterizedType &&
          target.typeArguments.isNotEmpty &&
          target.typeArguments.every((arg) => arg is TypeParameterType);
      
      // Check if source and target have the same base type (same class name)
      // This handles cases like With<num, num> -> With<T, T>
      // But we can only use source directly if there are no nested type differences
      bool hasSameBaseType = false;
      bool canUseSourceDirectly = false;
      
      if (source is InterfaceType && target is InterfaceType) {
        final sourceInterface = source;
        final targetInterface = target;
        hasSameBaseType = sourceInterface.element.name == targetInterface.element.name &&
            sourceInterface.element.library.uri == targetInterface.element.library.uri;
        
        // Only use source directly if:
        // 1. Target has all generic parameters (TypeParameterType) - simple case like With<T, T>
        // 2. OR source and target are exactly the same (including type arguments)
        if (hasSameBaseType) {
          if (isTargetGenericParameterizedType) {
            // Target has all generic params - can use source directly
            canUseSourceDirectly = true;
          } else {
            // Check if both are parameterized types and have matching type arguments
            // Try to access typeArguments - if types are not ParameterizedType, this will be empty
            // ignore: unnecessary_type_check, linter incorrectly thinks this is always true
            final sourceArgs = (source is ParameterizedType) ? source.typeArguments : <DartType>[];
            // ignore: unnecessary_type_check, linter incorrectly thinks this is always true
            final targetArgs = (target is ParameterizedType) ? target.typeArguments : <DartType>[];
            
            if (sourceArgs.isNotEmpty || targetArgs.isNotEmpty) {
              if (sourceArgs.length == targetArgs.length) {
                // Check if all type arguments match exactly (including nullability)
                canUseSourceDirectly = true;
                for (int i = 0; i < sourceArgs.length; i++) {
                  final sourceArg = sourceArgs[i];
                  final targetArg = targetArgs[i];
                  
                  // If target arg is a generic parameter, we need to be careful
                  // If source arg is nullable and target generic param might be non-nullable,
                  // we can't use source directly as it will cause type errors
                  if (targetArg is TypeParameterType) {
                    // Check if source arg is a ParameterizedType with nullable inner types
                    // If so, we can't use source directly as it might not match the generic constraint
                    if (sourceArg is ParameterizedType) {
                      // Check if any nested type arguments are nullable
                      final hasNullableNested = sourceArg.typeArguments.any((arg) => arg.isNullable);
                      if (hasNullableNested) {
                        // Source has nullable nested types, can't use directly
                        // The generic parameter might be constrained to non-nullable
                        canUseSourceDirectly = false;
                        break;
                      }
                    } else if (sourceArg.isNullable) {
                      // Source arg itself is nullable, but target generic might be non-nullable
                      // Can't use source directly to avoid type errors
                      canUseSourceDirectly = false;
                      break;
                    }
                    // Otherwise, generic parameter can accept the source type
                    continue;
                  }
                  
                  // For concrete types, they must match exactly (including nullability)
                  // This prevents issues like Wrapper<Inner<Data?>> -> Wrapper<Inner<Data>>
                  if (!sourceArg.isSame(targetArg, withNullability: true)) {
                    canUseSourceDirectly = false;
                    break;
                  }
                }
              }
            } else {
              // Same base type but not parameterized - can use source directly
              canUseSourceDirectly = true;
            }
          }
        }
      }
      
      if (isTargetGenericParameter || (isTargetGenericParameterizedType && canUseSourceDirectly)) {
        // For generic parameters or parameterized types with generic parameters,
        // we can use the source value directly
        // However, if convertMethodArgument is provided (e.g., from iterable mapping),
        // we should use that instead of sourceOnModel
        final expressionToUse = convertMethodArgument ?? sourceOnModel;
        
        // Handle nullability appropriately
        final shouldIgnoreNull =
            fieldMapping?.ignoreNull ??
            mapping.ignoreFieldNull ??
            mapperConfig.mapprOptions.ignoreNullableSourceField ??
            false;

        // if SOURCE nullable and TARGET not AND ignoreNull is used - use it.
        if ((source.isNullable && target.isNotNullable) && shouldIgnoreNull) {
          return expressionToUse.nullChecked;
        }

        // Otherwise, use source directly (generic parameter will accept it)
        return expressionToUse;
      }
      
      if (target.isNullable) {
        log.warning(
          "Can't find nested mapping '$assignment' but target is nullable. Setting null. ($enclosingMappingMessage).",
        );

        return literalNull;
      }

      throw InvalidGenerationSourceError(
        "Mapping nested object '$assignment' but no mapping is configured. ($enclosingMappingMessage).",
      );
    }

    final convertCallExpression = mappingCall(
      nestedMapping: nestedMapping,
      source: source,
      target: target,
      convertMethodArgument: convertMethodArgument,
      includeGenericTypes: includeGenericTypes,
    );

    // If source == null and target not nullable -> use whenNullDefault if possible
    if (source.isNullable && (fieldMapping?.whenNullExpression != null)) {
      // Generates code like:
      //
      // model.name == null
      //     ? const Nested(
      //         id: 123,
      //         name: 'test',
      //       )
      //     : _map_NestedDto_To_Nested(model.name),
      return sourceOnModel.equalTo(literalNull).conditional(fieldMapping!.whenNullExpression!, convertCallExpression);
    }

    // Generates code like:
    //
    // `_map_NestedDto_To_Nested(model.name)`
    return convertCallExpression;
  }

  /// Generates a mapping call `_mapAlphaDto_to_Alpha(convertMethodArgument)`.
  /// When [convertMethodArgument] is null, then a tear off `_mapAlphaDto_to_Alpha` is generated.
  ///
  /// This function also marks nullable mapping to be generated
  /// using the [onUsedNullableMethodCallback] callback.
  Expression mappingCall({
    required DartType source,
    required DartType target,
    required TypeMapping nestedMapping,
    Expression? convertMethodArgument,
    bool includeGenericTypes = false,
  }) {
    final isTargetNullable = target.isNullable;

    final useNullableMethod = isTargetNullable && !mapping.hasWhenNullDefault();

    // When target is nullable, use nullable convert method.
    // But use non-nullable when the mapping has default value.
    //
    // Otherwise use non-nullable.
    final convertMethod = refer(
      useNullableMethod
          ? MethodBuilderBase.constructNullableConvertMethodName(source: source, target: target)
          : MethodBuilderBase.constructConvertMethodName(source: source, target: target),
    );

    if (useNullableMethod) {
      onUsedNullableMethodCallback?.call(nestedMapping);
    }

    return convertMethodArgument == null
        ? convertMethod
        : convertMethod.call(
            [convertMethodArgument],
            {},
            includeGenericTypes
                ? [EmitterHelper.current.typeRefer(type: source), EmitterHelper.current.typeRefer(type: target)]
                : [],
          );
  }
}
