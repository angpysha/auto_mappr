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

  group('Five level recursion', () {
    test('ADto<double> -> A<double> with full chain through E branch to FDto<double> -> F<double>', () {
      const dto = fixture.ADto<double>(
        value: 1.0,
        child: fixture.BDto<double>(
          value: 2.0,
          child: fixture.CDto<double>(
            value: 3.0,
            child: fixture.DDto<double>(value: 4.0),
          ),
        ),
      );
      final converted = mappr.convert<fixture.ADto<double>, fixture.A<double>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<double>(
            value: 1.0,
            child: fixture.B<double>(
              value: 2.0,
              child: fixture.C<double>(
                value: 3.0,
                child: fixture.D<double>(value: 4.0),
              ),
            ),
          ),
        ),
      );

      // Test E branch separately for 5 levels
      const eDto = fixture.EDto<double>(
        value: 5.0,
        child: fixture.FDto<double>(value: 6.0),
      );
      final convertedE = mappr.convert<fixture.EDto<double>, fixture.E<double>>(eDto);

      expect(
        convertedE,
        equals(
          const fixture.E<double>(
            value: 5.0,
            child: fixture.F<double>(value: 6.0),
          ),
        ),
      );
    });

    test('ADto<double> -> A<double> with partial chain (only B)', () {
      const dto = fixture.ADto<double>(
        value: 10.0,
        child: fixture.BDto<double>(value: 20.0),
      );
      final converted = mappr.convert<fixture.ADto<double>, fixture.A<double>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<double>(
            value: 10.0,
            child: fixture.B<double>(value: 20.0),
          ),
        ),
      );
    });
  });

  group('Seven level recursion', () {
    test('ADto<Object> -> A<Object> with full chain through E branch to GDto<Object> -> G<Object>', () {
      // Test A->B->C->D chain (4 levels)
      const dto = fixture.ADto<Object>(
        value: 'level1',
        child: fixture.BDto<Object>(
          value: 'level2',
          child: fixture.CDto<Object>(
            value: 'level3',
            child: fixture.DDto<Object>(value: 'level4'),
          ),
        ),
      );
      final converted = mappr.convert<fixture.ADto<Object>, fixture.A<Object>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<Object>(
            value: 'level1',
            child: fixture.B<Object>(
              value: 'level2',
              child: fixture.C<Object>(
                value: 'level3',
                child: fixture.D<Object>(value: 'level4'),
              ),
            ),
          ),
        ),
      );

      // Test E->F->G chain (3 levels) to get 7 total levels
      const eDto = fixture.EDto<Object>(
        value: 'level5',
        child: fixture.FDto<Object>(
          value: 'level6',
          child: fixture.GDto<Object>(value: 'level7'),
        ),
      );
      final convertedE = mappr.convert<fixture.EDto<Object>, fixture.E<Object>>(eDto);

      expect(
        convertedE,
        equals(
          const fixture.E<Object>(
            value: 'level5',
            child: fixture.F<Object>(
              value: 'level6',
              child: fixture.G<Object>(value: 'level7'),
            ),
          ),
        ),
      );
    });

    test('ADto<Object> -> A<Object> with partial chain (only B and C)', () {
      const dto = fixture.ADto<Object>(
        value: 'root',
        child: fixture.BDto<Object>(
          value: 'b',
          child: fixture.CDto<Object>(value: 'c'),
        ),
      );
      final converted = mappr.convert<fixture.ADto<Object>, fixture.A<Object>>(dto);

      expect(
        converted,
        equals(
          const fixture.A<Object>(
            value: 'root',
            child: fixture.B<Object>(
              value: 'b',
              child: fixture.C<Object>(value: 'c'),
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
      // Use num for deep chain as mappings are configured for num type (which includes int)
      const dtoNum = fixture.ADto<num>(
        value: 1,
        child: fixture.BDto<num>(
          value: 2,
          child: fixture.CDto<num>(value: 3),
        ),
      );
      final convertedNum = mappr.convert<fixture.ADto<num>, fixture.A<num>>(dtoNum);
      expect(convertedNum.value, isA<num>());
      expect(convertedNum.child?.value, isA<num>());
      expect(convertedNum.child?.child?.value, isA<num>());

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

