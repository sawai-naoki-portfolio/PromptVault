import 'package:flutter_test/flutter_test.dart';
import 'package:promptvault/services/placeholder_parser.dart';

void main() {
  group('基本の記法', () {
    test('本文中の変数を出現順に取り出す', () {
      const body = '以下の文章を{{ターゲット}}向けに{{文字数}}字で要約してください。';
      expect(
        PlaceholderParser.extractNames(body),
        <String>['ターゲット', '文字数'],
      );
    });

    test('同じ変数が複数回出てもフォームの入力欄は1つにまとめる', () {
      const body = '{{名前}}さん、{{名前}}さんへのメールです。{{目的}}';
      expect(PlaceholderParser.extractNames(body), <String>['名前', '目的']);
    });

    test('変数名の前後の空白は無視する', () {
      expect(PlaceholderParser.extractNames('{{  文字数  }}'), <String>['文字数']);
    });

    test('空の中括弧は変数として扱わない', () {
      expect(PlaceholderParser.extract('{{}} と {{  }}'), isEmpty);
    });

    test('中括弧が1つだけなら変数ではない', () {
      expect(PlaceholderParser.extract('{ターゲット} や {{未閉じ'), isEmpty);
    });

    test('改行をまたぐ記法は変数として拾わない', () {
      expect(PlaceholderParser.extract('{{ターゲット\n文字数}}'), isEmpty);
    });

    test('hasPlaceholders は変数の有無を返す', () {
      expect(PlaceholderParser.hasPlaceholders('{{a}}'), isTrue);
      expect(PlaceholderParser.hasPlaceholders('ただの文章'), isFalse);
    });
  });

  group('既定値つきの記法 {{名前=既定値}}', () {
    test('名前と既定値に分解する', () {
      final v = PlaceholderParser.extract('{{文字数=200}}').single;
      expect(v.name, '文字数');
      expect(v.defaultValue, '200');
      expect(v.hasChoices, isFalse);
    });

    test('前後の空白は落とす', () {
      final v = PlaceholderParser.extract('{{ 文字数 = 200 }}').single;
      expect(v.name, '文字数');
      expect(v.defaultValue, '200');
    });

    test('既定値が空でも変数として成立する', () {
      final v = PlaceholderParser.extract('{{文字数=}}').single;
      expect(v.name, '文字数');
      expect(v.defaultValue, isEmpty);
    });

    test('名前が空なら変数として扱わない', () {
      expect(PlaceholderParser.extract('{{=200}}'), isEmpty);
    });
  });

  group('選択肢つきの記法 {{名前:A|B}}', () {
    test('選択肢に分解し、先頭を既定値にする', () {
      final v = PlaceholderParser.extract('{{トーン:丁寧|カジュアル|硬め}}').single;
      expect(v.name, 'トーン');
      expect(v.choices, <String>['丁寧', 'カジュアル', '硬め']);
      // そのまま「置換してコピー」を押しても成立してほしいので先頭を既定にする。
      expect(v.defaultValue, '丁寧');
    });

    test('既定値を明示できる', () {
      final v = PlaceholderParser.extract('{{トーン:丁寧|カジュアル=カジュアル}}').single;
      expect(v.choices, <String>['丁寧', 'カジュアル']);
      expect(v.defaultValue, 'カジュアル');
    });

    test('選択肢の前後の空白は落とす', () {
      final v = PlaceholderParser.extract('{{トーン: 丁寧 | カジュアル }}').single;
      expect(v.choices, <String>['丁寧', 'カジュアル']);
    });

    test('空の選択肢は捨てる', () {
      final v = PlaceholderParser.extract('{{トーン:丁寧||カジュアル}}').single;
      expect(v.choices, <String>['丁寧', 'カジュアル']);
    });

    test('選択肢が実質空なら自由入力として扱う', () {
      final v = PlaceholderParser.extract('{{メモ:}}').single;
      expect(v.name, 'メモ');
      expect(v.hasChoices, isFalse);
    });

    test('選択肢が1つだけでも成立する', () {
      final v = PlaceholderParser.extract('{{言語:日本語}}').single;
      expect(v.choices, <String>['日本語']);
      expect(v.defaultValue, '日本語');
    });
  });

  group('重複と混在', () {
    test('同名なら最初の定義を優先する', () {
      final vars =
          PlaceholderParser.extract('{{トーン:丁寧|カジュアル}} と {{トーン}}');
      expect(vars.length, 1);
      expect(vars.single.choices, <String>['丁寧', 'カジュアル']);
    });

    test('複数種類の記法が混在しても順序を保つ', () {
      final vars = PlaceholderParser.extract(
        '{{入力}}を{{文字数=200}}字で{{トーン:丁寧|硬め}}に',
      );
      expect(
        vars.map((PromptVariable v) => v.name),
        <String>['入力', '文字数', 'トーン'],
      );
    });
  });

  group('initialValues', () {
    test('既定値をフォームの初期値にする', () {
      final vars = PlaceholderParser.extract('{{a}}{{b=2}}{{c:x|y}}');
      expect(
        PlaceholderParser.initialValues(vars),
        <String, String>{'a': '', 'b': '2', 'c': 'x'},
      );
    });
  });

  group('token（正規化表示）', () {
    test('素の変数はそのまま', () {
      expect(PlaceholderParser.extract('{{ 名前 }}').single.token, '{{名前}}');
    });

    test('既定値つきは既定値も表示する', () {
      expect(PlaceholderParser.extract('{{文字数=200}}').single.token,
          '{{文字数=200}}');
    });

    test('選択肢つきで既定値が先頭なら既定値は省く', () {
      expect(
        PlaceholderParser.extract('{{トーン:丁寧|硬め}}').single.token,
        '{{トーン:丁寧|硬め}}',
      );
    });

    test('選択肢つきで既定値が先頭以外なら明示する', () {
      expect(
        PlaceholderParser.extract('{{トーン:丁寧|硬め=硬め}}').single.token,
        '{{トーン:丁寧|硬め=硬め}}',
      );
    });
  });

  group('fill', () {
    test('渡された値で置換する', () {
      expect(
        PlaceholderParser.fill(
          '{{ターゲット}}向けに{{文字数}}字で要約',
          <String, String>{'ターゲット': '中学生', '文字数': '200'},
        ),
        '中学生向けに200字で要約',
      );
    });

    test('既定値つきの記法も変数名をキーに置換できる', () {
      expect(
        PlaceholderParser.fill(
          '{{文字数=200}}字で要約',
          <String, String>{'文字数': '300'},
        ),
        '300字で要約',
      );
    });

    test('選択肢つきの記法も変数名をキーに置換できる', () {
      expect(
        PlaceholderParser.fill(
          'トーンは{{トーン:丁寧|カジュアル}}で',
          <String, String>{'トーン': 'カジュアル'},
        ),
        'トーンはカジュアルで',
      );
    });

    test('同じ変数が複数箇所にあってもすべて置換する', () {
      expect(
        PlaceholderParser.fill(
          '{{名前}}さん、{{名前}}さんへ',
          <String, String>{'名前': '田中'},
        ),
        '田中さん、田中さんへ',
      );
    });

    test('値が未指定の変数は記法のまま残す', () {
      expect(
        PlaceholderParser.fill(
          '{{ターゲット}}向けに{{文字数=200}}字',
          <String, String>{'ターゲット': '新入社員'},
        ),
        '新入社員向けに{{文字数=200}}字',
      );
    });

    test('空文字が渡された変数も記法のまま残す', () {
      expect(
        PlaceholderParser.fill('{{文字数}}字', <String, String>{'文字数': ''}),
        '{{文字数}}字',
      );
    });

    test('置換後の値に変数記法が含まれても再置換しない', () {
      expect(
        PlaceholderParser.fill(
            '{{a}}', <String, String>{'a': '{{b}}', 'b': 'x'}),
        '{{b}}',
      );
    });
  });

  group('insert', () {
    test('指定位置に変数を挿入しカーソル位置を返す', () {
      final result = PlaceholderParser.insert('要約してください', 0, 'ターゲット');
      expect(result.text, '{{ターゲット}}要約してください');
      expect(result.caretOffset, '{{ターゲット}}'.length);
    });

    test('範囲外のオフセットは本文の長さに丸める', () {
      final result = PlaceholderParser.insert('abc', 999, 'x');
      expect(result.text, 'abc{{x}}');
      expect(result.caretOffset, 'abc{{x}}'.length);
    });

    test('負のオフセットは先頭に丸める', () {
      expect(PlaceholderParser.insert('abc', -5, 'x').text, '{{x}}abc');
    });
  });
}
