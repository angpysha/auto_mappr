import 'package:test/test.dart';

import 'fixture/recursive_mappers.dart' as fixture;

/// Tests for recursive mappers support.
///
/// These tests verify that mappings work correctly when:
/// - ADto<T> -> A<T> contains BDto<T> -> B<T>
/// - B<T> contains CDto<T> -> C<T>
/// - And so on, with multiple levels of nesting and branches
///
/// Note: Some tests may currently fail due to issues with finding nested
/// mappings for generic types. This is a known limitation that needs to be fixed.
void main() {
  late final fixture.Mappr mappr;

  setUpAll(() {
    mappr = const fixture.Mappr();
  });

  group('Single level recursion', () {
    test('ADto<int> -> A<int> with BDto<int> -> B<int>', () {
      const dto = fixture.ADto<int>(
        value: 42,
        child: fixture.BDto<int>(value: 100),
      );
      final converted = mappr.convert<fixture.ADto<int>, fixture.A<int>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<int>(
            value: 42,
            child: fixture.B<int>(value: 100),
          ),
        ),
      );
    });

    test('ADto<int> -> A<int> without child', () {
      const dto = fixture.ADto<int>(value: 42);
      final converted = mappr.convert<fixture.ADto<int>, fixture.A<int>>(dto);

      expect(
        converted,
        equals(const fixture.A<int>(value: 42)),
      );
    });
  });

  group('Two level recursion', () {
    test('ADto<String> -> A<String> with BDto<String> -> B<String> with CDto<String> -> C<String>', () {
      const dto = fixture.ADto<String>(
        value: 'level1',
        child: fixture.BDto<String>(
          value: 'level2',
          child: fixture.CDto<String>(value: 'level3'),
        ),
      );
      final converted = mappr.convert<fixture.ADto<String>, fixture.A<String>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<String>(
            value: 'level1',
            child: fixture.B<String>(
              value: 'level2',
              child: fixture.C<String>(value: 'level3'),
            ),
          ),
        ),
      );
    });
  });

  group('Three level recursion', () {
    test('ADto<num> -> A<num> with full chain to DDto<num> -> D<num>', () {
      const dto = fixture.ADto<num>(
        value: 1.0,
        child: fixture.BDto<num>(
          value: 2.0,
          child: fixture.CDto<num>(
            value: 3.0,
            child: fixture.DDto<num>(value: 4.0),
          ),
        ),
      );
      final converted = mappr.convert<fixture.ADto<num>, fixture.A<num>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<num>(
            value: 1.0,
            child: fixture.B<num>(
              value: 2.0,
              child: fixture.C<num>(
                value: 3.0,
                child: fixture.D<num>(value: 4.0),
              ),
            ),
          ),
        ),
      );
    });

    test('ADto<num> -> A<num> with partial chain (only B)', () {
      const dto = fixture.ADto<num>(
        value: 10.0,
        child: fixture.BDto<num>(value: 20.0),
      );
      final converted = mappr.convert<fixture.ADto<num>, fixture.A<num>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<num>(
            value: 10.0,
            child: fixture.B<num>(value: 20.0),
          ),
        ),
      );
    });
  });

  group('Multiple branches', () {
    test('ADto<bool> -> A<bool> can contain either BDto<bool> -> B<bool> or EDto<bool> -> E<bool>', () {
      const dtoWithB = fixture.ADto<bool>(
        value: true,
        child: fixture.BDto<bool>(value: false),
      );
      final convertedWithB = mappr.convert<fixture.ADto<bool>, fixture.A<bool>>(dtoWithB);

      expect(
        convertedWithB,
        equals(
          const fixture.A<bool>(
            value: true,
            child: fixture.B<bool>(value: false),
          ),
        ),
      );

      // Note: In this test structure, A doesn't have an E child field,
      // but we test that both B and E mappings work independently
      const eDto = fixture.EDto<bool>(value: true);
      final convertedE = mappr.convert<fixture.EDto<bool>, fixture.E<bool>>(eDto);

      expect(
        convertedE,
        equals(const fixture.E<bool>(value: true)),
      );
    });
  });

  group('Deep recursion with nullable types', () {
    test('ADto<String?> -> A<String?> with nullable chain', () {
      const dto = fixture.ADto<String?>(
        value: 'nullable',
        child: fixture.BDto<String?>(
          value: null,
          child: fixture.CDto<String?>(value: 'not null'),
        ),
      );
      final converted = mappr.convert<fixture.ADto<String?>, fixture.A<String?>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<String?>(
            value: 'nullable',
            child: fixture.B<String?>(
              value: null,
              child: fixture.C<String?>(value: 'not null'),
            ),
          ),
        ),
      );
    });
  });

  group('Edge cases', () {
    test('Empty chain (no children)', () {
      const dto = fixture.ADto<String>(value: 'root');
      final converted = mappr.convert<fixture.ADto<String>, fixture.A<String>>(dto);

      expect(
        converted,
        equals(const fixture.A<String>(value: 'root')),
      );
    });

    test('Full chain with different generic types', () {
      // Test that generic type T is properly propagated through the chain
      const dtoInt = fixture.ADto<int>(
        value: 1,
        child: fixture.BDto<int>(
          value: 2,
          child: fixture.CDto<int>(value: 3),
        ),
      );
      final convertedInt = mappr.convert<fixture.ADto<int>, fixture.A<int>>(dtoInt);
      expect(convertedInt.value, isA<int>());
      expect(convertedInt.child?.value, isA<int>());
      expect(convertedInt.child?.child?.value, isA<int>());

      const dtoString = fixture.ADto<String>(
        value: 'a',
        child: fixture.BDto<String>(
          value: 'b',
          child: fixture.CDto<String>(value: 'c'),
        ),
      );
      final convertedString = mappr.convert<fixture.ADto<String>, fixture.A<String>>(dtoString);
      expect(convertedString.value, isA<String>());
      expect(convertedString.child?.value, isA<String>());
      expect(convertedString.child?.child?.value, isA<String>());
    });
  });
}

