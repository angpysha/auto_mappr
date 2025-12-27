import 'package:test/test.dart';

import 'fixture/complex_generics.dart' as fixture;

void main() {
  late final fixture.Mappr mappr;

  setUpAll(() {
    mappr = const fixture.Mappr();
  });

  group('Deep nested GraphQL-like types', () {
    test('QueryGetUserInfoUserInfoItem -> ApiResultSuccess', () {
      const source = fixture.QueryGetUserInfoUserInfoItem(
        id: '123',
        name: 'Test User',
      );
      final converted = mappr.convert<
          fixture.QueryGetUserInfoUserInfoItem,
          fixture.ApiResultSuccess>(source);

      expect(converted.id, equals('123'));
      expect(converted.name, equals('Test User'));
    });

    test('QueryGetUserInfoUserInfo -> ApiResultSuccess', () {
      const source = fixture.QueryGetUserInfoUserInfo(
        items: [
          fixture.QueryGetUserInfoUserInfoItem(id: '1', name: 'User 1'),
          fixture.QueryGetUserInfoUserInfoItem(id: '2', name: 'User 2'),
        ],
      );
      final converted = mappr.convert<
          fixture.QueryGetUserInfoUserInfo,
          fixture.ApiResultSuccess>(source);

      // Note: This test verifies that the mapping doesn't crash
      // The actual mapping behavior depends on field mappings
      expect(converted, isA<fixture.ApiResultSuccess>());
    });

    test('QueryGetUserInfo -> ApiResultSuccess', () {
      const source = fixture.QueryGetUserInfo(
        userInfo: fixture.QueryGetUserInfoUserInfo(
          items: [
            fixture.QueryGetUserInfoUserInfoItem(id: '1', name: 'User 1'),
          ],
        ),
      );
      final converted = mappr.convert<
          fixture.QueryGetUserInfo,
          fixture.ApiResultSuccess>(source);

      expect(converted, isA<fixture.ApiResultSuccess>());
    });
  });

  group('Generic container types', () {
    test('Container<String> -> Container<String>', () {
      const source = fixture.Container<String>('test');
      final converted = mappr.convert<
          fixture.Container<String>,
          fixture.Container<String>>(source);

      expect(converted.value, equals('test'));
    });

    test('Container<String?> -> Container<String?>', () {
      const source = fixture.Container<String?>('nullable');
      final converted = mappr.convert<
          fixture.Container<String?>,
          fixture.Container<String?>>(source);

      expect(converted.value, equals('nullable'));
    });

    test('Container<int?> -> Container<int?>', () {
      const source = fixture.Container<int?>(42);
      final converted = mappr.convert<
          fixture.Container<int?>,
          fixture.Container<int?>>(source);

      expect(converted.value, equals(42));
    });
  });

  group('Nested generic types', () {
    test('Wrapper<Inner<Data>> -> Wrapper<Inner<Data>>', () {
      const source = fixture.Wrapper<fixture.Inner<fixture.Data>>(
        fixture.Inner<fixture.Data>(fixture.Data('test')),
      );
      final converted = mappr.convert<
          fixture.Wrapper<fixture.Inner<fixture.Data>>,
          fixture.Wrapper<fixture.Inner<fixture.Data>>>(source);

      expect(converted.inner.data.value, equals('test'));
    });

    test('Wrapper<Inner<Data?>> -> Wrapper<Inner<Data?>>', () {
      const source = fixture.Wrapper<fixture.Inner<fixture.Data?>>(
        fixture.Inner<fixture.Data?>(fixture.Data('nullable')),
      );
      final converted = mappr.convert<
          fixture.Wrapper<fixture.Inner<fixture.Data?>>,
          fixture.Wrapper<fixture.Inner<fixture.Data?>>>(source);

      expect(converted.inner.data?.value, equals('nullable'));
    });
  });

  group('Generic result types', () {
    test('Result<String> -> Result<String>', () {
      const source = fixture.Result<String>(data: 'success', success: true);
      final converted = mappr.convert<
          fixture.Result<String>,
          fixture.Result<String>>(source);

      expect(converted.data, equals('success'));
      expect(converted.success, isTrue);
    });

    test('Result<String?> -> Result<String?>', () {
      const source = fixture.Result<String?>(data: null, success: false);
      final converted = mappr.convert<
          fixture.Result<String?>,
          fixture.Result<String?>>(source);

      expect(converted.data, isNull);
      expect(converted.success, isFalse);
    });

    test('Result<int> -> Result<int>', () {
      const source = fixture.Result<int>(data: 42, success: true);
      final converted = mappr.convert<
          fixture.Result<int>,
          fixture.Result<int>>(source);

      expect(converted.data, equals(42));
      expect(converted.success, isTrue);
    });
  });
}

