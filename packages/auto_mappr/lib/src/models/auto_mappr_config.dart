import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:auto_mappr/src/extensions/dart_type_extension.dart';
import 'package:auto_mappr/src/helpers/emitter_helper.dart';
import 'package:auto_mappr/src/models/auto_mappr_options.dart';
import 'package:auto_mappr/src/models/type_mapping.dart';
import 'package:code_builder/code_builder.dart';
import 'package:collection/collection.dart';

class AutoMapprConfig {
  final List<TypeMapping> mappers;
  final String availableMappingsMacroId;
  final Expression? modulesCode;
  final List<DartObject> includesList;
  final List<DartObject> delegatesList;
  final AutoMapprOptions mapprOptions;

  String get availableMappingsDocComment {
    return [
      '/// {@macro $availableMappingsMacroId}',
      ..._delegatesDocComment(),
    ].join('\n');
  }

  const AutoMapprConfig({
    required this.mappers,
    required this.availableMappingsMacroId,
    required this.mapprOptions,
    this.modulesCode,
    this.includesList = const [],
    this.delegatesList = const [],
  });

  TypeMapping? findMapping({
    required DartType? source,
    required DartType? target,
  }) {
    if (source == null || target == null) return null;
    
    // First, try to find exact mapping (including nullability)
    var mapping = mappers.firstWhereOrNull(
      (mapper) => mapper.source.isSame(source, withNullability: true) && 
                  mapper.target.isSame(target, withNullability: true),
    );
    
    if (mapping != null) return mapping;
    
    // If not found, try to find mapping ignoring nullability
    // This handles cases where we have BDto<int>? -> B<int>? but mapping is BDto<int> -> B<int>
    mapping = mappers.firstWhereOrNull(
      (mapper) => mapper.source.isSame(source, withNullability: false) && 
                  mapper.target.isSame(target, withNullability: false),
    );
    
    if (mapping != null) return mapping;
    
    // If still not found and types are nullable, try to find mapping for non-nullable versions
    // This handles cases where field is nullable but mapping is defined for non-nullable types
    if (source.isNullable || target.isNullable) {
      final nonNullSource = source.isNullable && source.element?.library != null
          ? source.element!.library!.typeSystem.promoteToNonNull(source)
          : source;
      final nonNullTarget = target.isNullable && target.element?.library != null
          ? target.element!.library!.typeSystem.promoteToNonNull(target)
          : target;
      
      if (nonNullSource != source || nonNullTarget != target) {
        mapping = mappers.firstWhereOrNull(
          (mapper) => mapper.source.isSame(nonNullSource, withNullability: false) && 
                      mapper.target.isSame(nonNullTarget, withNullability: false),
        );
      }
    }
    
    return mapping;
  }

  Iterable<String> getAvailableMappingsDocComment() {
    return [
      '/// {@template $availableMappingsMacroId}',
      '/// Available mappings:',
      for (final mapper in mappers) _getTypeMappingDocs(mapper),
      '/// {@endtemplate}',
      ..._includesDocComment(),
      ..._delegatesDocComment(),
    ];
  }

  List<String> _includesDocComment() {
    return [
      if (includesList.isNotEmpty) ...[
        '///',
        "/// Used includes: ${includesList.map((e) {
          final emittedInclude = EmitterHelper.current.typeReferEmitted(type: e.type);

          return '[$emittedInclude]';
        }).join(', ')}",
      ],
    ];
  }

  List<String> _delegatesDocComment() {
    return [
      if (delegatesList.isNotEmpty) ...[
        '///',
        "/// Used delegates: ${delegatesList.map((e) {
          final emittedDelegate = EmitterHelper.current.typeReferEmitted(type: e.type);

          return '[$emittedDelegate]';
        }).join(', ')}",
      ],
    ];
  }

  String _getTypeMappingDocs(TypeMapping typeMapping) {
    final trailingPart = typeMapping.hasWhenNullDefault() ? ' -- With default value.' : '.';
    // Display without import aliases.
    final emittedSource = typeMapping.source.getDisplayString();
    final emittedTarget = typeMapping.target.getDisplayString();

    // ignore: avoid-non-ascii-symbols, it is ok
    return '/// - `$emittedSource` → `$emittedTarget`$trailingPart';
  }
}
