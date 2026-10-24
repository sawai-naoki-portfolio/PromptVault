import 'package:flutter/foundation.dart';

/// 1タップで自分のプロンプト集に取り込めるテンプレート。
@immutable
class StarterPrompt {
  const StarterPrompt({
    required this.title,
    required this.body,
    required this.tags,
  });

  final String title;
  final String body;
  final List<String> tags;
}

/// 初回起動時に自動投入するテンプレート集。
///
/// 以前は「発見」タブとして独立した画面に置いていたが、
/// 常設タブを1つ使うほど繰り返し訪れる場所ではなかったため、
/// オンボーディング（初回投入）と空状態の導線に畳んだ。
///
/// `{{変数}}` の使い方をいきなり体験してもらう役割も兼ねている。
class StarterPrompts {
  const StarterPrompts._();

  /// 初回起動時に自動で入れる数。
  /// 全部入れると「自分で作った感」が薄れるので、代表的なものだけ。
  static const int autoSeedCount = 3;

  static const List<StarterPrompt> all = <StarterPrompt>[
    StarterPrompt(
      title: '文章の要約',
      body: '以下の文章を{{ターゲット}}向けに{{文字数=200}}字で要約してください。\n'
          'トーンは{{トーン:丁寧|カジュアル|硬め}}で、結論を最初に書いてください。\n\n'
          '---\n{{入力テキスト}}',
      tags: <String>['要約', 'ライティング'],
    ),
    StarterPrompt(
      title: 'メールの下書き',
      body: '{{相手}}宛に、{{目的}}を伝えるビジネスメールを書いてください。\n'
          'トーンは{{トーン:丁寧|カジュアル}}、長さは{{文字数=200}}字程度。\n'
          '件名も提案してください。',
      tags: <String>['メール', 'ビジネス'],
    ),
    StarterPrompt(
      title: 'コードレビュー',
      body: '以下の{{言語}}のコードをレビューしてください。\n'
          '観点: バグ・可読性・パフォーマンス・命名。\n'
          '指摘は重要度順に、修正案のコードも添えてください。\n\n'
          '```\n{{入力テキスト}}\n```',
      tags: <String>['レビュー', '開発'],
    ),
    StarterPrompt(
      title: 'アイデア出し（ブレスト）',
      body: '{{テーマ}}について、アイデアを{{個数=10}}個出してください。\n'
          'それぞれに「狙い」と「想定される反論」を1行ずつ添えてください。\n'
          '常識的なものと、あえて外したものを半分ずつ混ぜてください。',
      tags: <String>['ブレスト', '企画'],
    ),
    StarterPrompt(
      title: '英文の添削',
      body: '以下の英文を、{{目的}}にふさわしい自然な英語に添削してください。\n'
          '修正箇所と理由を日本語で簡潔に説明してください。\n\n'
          '---\n{{入力テキスト}}',
      tags: <String>['英語', '添削'],
    ),
    StarterPrompt(
      title: '議事録の整形',
      body: '以下のメモを議事録の形式に整えてください。\n'
          '「決定事項」「ToDo（担当者つき）」「保留」に分けて記載してください。\n\n'
          '---\n{{入力テキスト}}',
      tags: <String>['議事録', 'ビジネス'],
    ),
  ];
}
