import 'package:analyzer/dart/element/nullability_suffix.dart';
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

    var nestedMapping = mapperConfig.findMapping(source: source, target: target);
    var resolvedTarget = target;

    // If mapping not found and target has generic parameters, try to resolve them from source
    // This handles cases like CDto<num>? -> C<T>? where T is a generic parameter from parent type
    // We recursively resolve generic parameters at any depth (up to 7 levels)
    if (nestedMapping == null && target is ParameterizedType && source is ParameterizedType) {
      final resolved = _resolveGenericMapping(mapperConfig: mapperConfig, source: source, target: target, maxDepth: 7);
      if (resolved != null) {
        nestedMapping = resolved.mapping;
        resolvedTarget = resolved.resolvedTarget;
      }
    }

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
      final isTargetGenericParameterizedType =
          target is ParameterizedType &&
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
        hasSameBaseType =
            sourceInterface.element.name == targetInterface.element.name &&
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

    // If we found a mapping with resolved target, we need to create a new target type
    // that preserves nullability from source type arguments
    // For example: BDto<String?>? -> B<T>? should use B<String?> for method name generation
    DartType? targetForMethodName;
    if (resolvedTarget != target &&
        resolvedTarget is ParameterizedType &&
        target is ParameterizedType &&
        source is ParameterizedType) {
      // Create a hybrid type: use base type and structure from resolvedTarget,
      // but preserve nullability from source type arguments
      // This ensures we generate correct method names like B$StringQQ instead of B$String or B$T
      targetForMethodName = resolvedTarget;
    } else {
      targetForMethodName = null;
    }

    final convertCallExpression = mappingCall(
      nestedMapping: nestedMapping,
      source: source,
      target: target,
      resolvedTargetForMethodName: targetForMethodName,
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
    DartType? resolvedTargetForMethodName,
  }) {
    // Use resolvedTargetForMethodName for method name generation if provided
    // Even if nullability doesn't match, we should use it for type arguments
    // The nullability for top-level is handled separately via useNullableMethod
    // This handles cases where target is B<T>? but resolvedTarget is B<String?>
    final targetForMethodName = resolvedTargetForMethodName ?? target;
    final isTargetNullable = target.isNullable;

    final useNullableMethod = isTargetNullable && !mapping.hasWhenNullDefault();

    // When target is nullable, use nullable convert method.
    // But use non-nullable when the mapping has default value.
    //
    // Otherwise use non-nullable.
    final convertMethod = refer(
      useNullableMethod
          ? MethodBuilderBase.constructNullableConvertMethodName(source: source, target: targetForMethodName)
          : MethodBuilderBase.constructConvertMethodName(source: source, target: targetForMethodName),
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

  /// Recursively resolves generic type parameters to find a mapping.
  /// This handles cases like CDto<num>? -> C<T>? where T is a generic parameter from parent type.
  /// Supports up to [maxDepth] levels of nesting.
  _ResolvedMapping? _resolveGenericMapping({
    required AutoMapprConfig mapperConfig,
    required DartType source,
    required DartType target,
    int maxDepth = 7,
    int currentDepth = 0,
  }) {
    if (currentDepth >= maxDepth) return null;

    if (target is! ParameterizedType || source is! ParameterizedType) {
      return null;
    }

    final targetParam = target;
    final sourceParam = source;

    // Check if target has generic parameters (TypeParameterType) and source has concrete types
    final targetHasGenericParams = targetParam.typeArguments.any((arg) => arg is TypeParameterType);
    final sourceHasConcreteTypes = sourceParam.typeArguments.every((arg) => !(arg is TypeParameterType));

    if (!targetHasGenericParams ||
        !sourceHasConcreteTypes ||
        targetParam.typeArguments.length != sourceParam.typeArguments.length ||
        targetParam.element == null ||
        sourceParam.element == null) {
      return null;
    }

    // Try to find mapping by iterating through all mappers and checking if
    // source matches and target base type matches with resolved type arguments
    for (final mapper in mapperConfig.mappers) {
      // Check if mapper source matches our source (ignoring nullability)
      if (mapper.source.isSame(source, withNullability: false)) {
        // Check if mapper target has the same base type as our target
        if (mapper.target is ParameterizedType) {
          final mapperTarget = mapper.target;
          if (mapperTarget.element == targetParam.element &&
              mapperTarget.typeArguments.length == sourceParam.typeArguments.length) {
            // Check if mapper target type arguments match source type arguments
            // This needs to be recursive for nested generic types
            bool typeArgsMatch = true;
            for (int i = 0; i < mapperTarget.typeArguments.length; i++) {
              final mapperArg = mapperTarget.typeArguments[i];
              final sourceArg = sourceParam.typeArguments[i];

              // If mapper arg is a generic parameter, we can't match it directly
              // But if source arg matches, that's fine
              if (mapperArg is TypeParameterType) {
                // This shouldn't happen in configured mappings, but handle it
                continue;
              }

              // Recursively check nested generic types
              if (mapperArg is ParameterizedType) {
                if (sourceArg is ParameterizedType) {
                  // Check if nested types match (recursively)
                  if (!_typesMatchRecursively(
                    mapperArg,
                    sourceArg,
                    maxDepth: maxDepth,
                    currentDepth: currentDepth + 1,
                  )) {
                    typeArgsMatch = false;
                    break;
                  }
                } else {
                  typeArgsMatch = false;
                  break;
                }
              } else if (!mapperArg.isSame(sourceArg, withNullability: false)) {
                typeArgsMatch = false;
                break;
              }
            }

            if (typeArgsMatch) {
              // IMPORTANT: Check if source has nullable type arguments
              // If so, mapper.target might have non-nullable type arguments
              // We can still use the mapping, but we should NOT use resolvedTarget
              // for method name generation because nullability doesn't match

              // Check if we need to adjust nullability
              bool hasNullableTypeArgs = false;
              if (sourceParam.typeArguments.isNotEmpty) {
                for (int i = 0; i < sourceParam.typeArguments.length; i++) {
                  final sourceArg = sourceParam.typeArguments[i];
                  // If source arg is nullable, we need to use a different approach
                  if (sourceArg.isNullable) {
                    hasNullableTypeArgs = true;
                    break;
                  }
                }
              }

              if (hasNullableTypeArgs) {
                // Don't return resolved mapping for nullable type arguments
                // The system will use findMapping which will handle nullable types correctly
                continue;
              }

              // Use mapper's target type (which has concrete type arguments)
              // This ensures we use concrete types instead of generic parameters for method name generation
              // Important: preserve the nullability of the original target if it's nullable
              // This handles cases where target is B<T>? but mapper.target is B<String>
              final resolvedTargetType = mapper.target;
              return _ResolvedMapping(mapping: mapper, resolvedTarget: resolvedTargetType);
            }
          }
        }
      }
    }

    return null;
  }

  /// Recursively checks if two types match, handling nested generic types.
  bool _typesMatchRecursively(DartType type1, DartType type2, {int maxDepth = 7, int currentDepth = 0}) {
    if (currentDepth >= maxDepth) return false;

    // If both are ParameterizedType, check recursively
    if (type1 is ParameterizedType && type2 is ParameterizedType) {
      if (type1.element != type2.element || type1.typeArguments.length != type2.typeArguments.length) {
        return false;
      }

      for (int i = 0; i < type1.typeArguments.length; i++) {
        if (!_typesMatchRecursively(
          type1.typeArguments[i],
          type2.typeArguments[i],
          maxDepth: maxDepth,
          currentDepth: currentDepth + 1,
        )) {
          return false;
        }
      }
      return true;
    }

    // Otherwise, check if they're the same (ignoring nullability)
    return type1.isSame(type2, withNullability: false);
  }
}

/// Helper class to hold resolved mapping information.
class _ResolvedMapping {
  final TypeMapping mapping;
  final DartType resolvedTarget;

  const _ResolvedMapping({required this.mapping, required this.resolvedTarget});
}
