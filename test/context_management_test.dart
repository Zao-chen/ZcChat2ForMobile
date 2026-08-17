import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/models/app_models.dart';
import 'package:zcchat2_for_mobile/src/services/context_history_compressor.dart';
import 'package:zcchat2_for_mobile/src/services/context_token_estimator.dart';
import 'package:zcchat2_for_mobile/src/services/model_context_catalog.dart';

void main() {
  test('ModelProviderConfig normalizes duplicate model ids', () {
    final ModelProviderConfig fromJson = ModelProviderConfig.fromJson(
      <String, dynamic>{
        'ModelList': <String>['gpt-5.1', ' gpt-5.1 ', '', 'gpt-5.2'],
      },
    );
    expect(fromJson.models, <String>['gpt-5.1', 'gpt-5.2']);

    final ModelProviderConfig copied = fromJson.copyWith(
      models: <String>['gpt-5.1', 'gpt-5.1', ' gpt-5.2 '],
    );
    expect(copied.models, <String>['gpt-5.1', 'gpt-5.2']);
  });

  group('ContextTokenEstimator', () {
    test('estimates text and request overhead', () {
      expect(ContextTokenEstimator.estimateTextTokens(''), 0);
      expect(ContextTokenEstimator.estimateTextTokens('abcdefghijklmnop'), 4);
      expect(ContextTokenEstimator.estimateTextTokens('你好世界'), 4);
      expect(ContextTokenEstimator.estimateTextTokens('😀'), 2);

      final int textTokens =
          ContextTokenEstimator.estimateTextTokens('你是桌宠 AI') +
          ContextTokenEstimator.estimateTextTokens('你好');
      expect(
        ContextTokenEstimator.estimateChatRequestTokens(
          systemPrompt: '你是桌宠 AI',
          userMessage: '你好',
        ),
        greaterThan(textTokens),
      );
    });

    test('validates limits and formats progress', () {
      expect(ContextTokenEstimator.validatedTokenLimit(128000), 128000);
      expect(
        ContextTokenEstimator.validatedTokenLimit(0),
        ContextTokenEstimator.defaultContextTokenLimit,
      );
      expect(ContextTokenEstimator.remainingTokens(100, 120), 0);
      expect(
        ContextTokenEstimator.formatContextProgress(
          tokenLimit: 100,
          estimatedUsedTokens: 120,
          source: '手动设置',
        ),
        allOf(contains('本地估算剩余：0 Token'), contains('已超出：20 Token')),
      );
    });
  });

  group('ModelContextCatalog', () {
    final Map<String, dynamic> catalog = <String, dynamic>{
      'openai/gpt-4o': <String, dynamic>{
        'limit': <String, dynamic>{'context': 128000},
      },
      'deepseek/deepseek-chat': <String, dynamic>{
        'limit': <String, dynamic>{'context': 1000000},
      },
      'anthropic/claude-sonnet': <String, dynamic>{
        'limit': <String, dynamic>{'context': 200000},
      },
      'vendor/shared-model': <String, dynamic>{
        'limit': <String, dynamic>{'context': 32000},
      },
      'other/shared-model': <String, dynamic>{
        'limit': <String, dynamic>{'context': 64000},
      },
    };

    test('matches saved selection and built-in providers', () {
      expect(
        ModelContextCatalog.selectionMatches(
          storedProvider: 'openai',
          storedModel: 'gpt-4o',
          currentProvider: 'OpenAI',
          currentModel: 'gpt-4o',
        ),
        isTrue,
      );
      expect(
        ModelContextCatalog.findContextWindow(
          catalog: catalog,
          provider: LlmProviderType.openAI,
          modelId: 'gpt-4o',
        ).contextTokenLimit,
        128000,
      );
      expect(
        ModelContextCatalog.findContextWindow(
          catalog: catalog,
          provider: LlmProviderType.deepSeek,
          modelId: 'deepseek-chat',
        ).contextTokenLimit,
        1000000,
      );
    });

    test('supports variants but rejects ambiguous bare IDs', () {
      expect(
        ModelContextCatalog.findContextWindow(
          catalog: catalog,
          provider: LlmProviderType.custom,
          modelId: 'anthropic/claude-sonnet:free',
        ).canonicalModelId,
        'anthropic/claude-sonnet',
      );
      expect(
        ModelContextCatalog.findContextWindow(
          catalog: catalog,
          provider: LlmProviderType.custom,
          modelId: 'shared-model',
        ).isValid,
        isFalse,
      );
      expect(
        ModelContextCatalog.findContextWindow(
          catalog: catalog,
          provider: LlmProviderType.openAI,
          modelId: 'anthropic/claude-sonnet',
        ).isValid,
        isFalse,
      );
    });
  });

  group('ContextHistoryCompressor', () {
    const List<String> history = <String>[
      '用户：第一问',
      '角色：第一答',
      '用户：第二问',
      '角色：第二答',
      '用户：第三问',
      '角色：第三答',
    ];

    test('triggers at threshold and validates percentages', () {
      expect(
        ContextHistoryCompressor.shouldCompress(
          estimatedTokens: 799,
          contextTokenLimit: 1000,
          triggerPercent: 80,
        ),
        isFalse,
      );
      expect(
        ContextHistoryCompressor.shouldCompress(
          estimatedTokens: 800,
          contextTokenLimit: 1000,
          triggerPercent: 80,
        ),
        isTrue,
      );
      expect(ContextHistoryCompressor.validatedTriggerPercent(49), 80);
    });

    test('builds active and fast history without mutating full history', () {
      expect(
        ContextHistoryCompressor.activeHistory(
          fullHistory: history,
          summary: '已经讨论过第一问',
          compactedHistoryCount: 2,
        ),
        <String>['较早对话摘要：已经讨论过第一问', '用户：第二问', '角色：第二答', '用户：第三问', '角色：第三答'],
      );
      expect(
        ContextHistoryCompressor.fastActiveHistory(
          fullHistory: history,
          summary: '第一轮摘要',
          compactedHistoryCount: 2,
          compactUntil: 4,
        ),
        <String>['较早对话摘要：第一轮摘要', '用户：第三问', '角色：第三答'],
      );
      expect(history.length, 6);
    });

    test('plans on a turn boundary and rejects unhelpful summaries', () {
      final ContextCompactionPlan plan = ContextHistoryCompressor.createPlan(
        fullHistory: history,
        summary: '',
        compactedHistoryCount: 0,
      );
      expect(plan.isValid, isTrue);
      expect(plan.compactUntil, 2);
      expect(plan.contextToReplace, '用户：第一问\n角色：第一答');
      expect(
        ContextHistoryCompressor.isUsefulSummary(
          summary: '第一轮问答',
          contextToReplace: plan.contextToReplace,
        ),
        isTrue,
      );
      expect(
        ContextHistoryCompressor.isUsefulSummary(
          summary: '${plan.contextToReplace}${plan.contextToReplace}',
          contextToReplace: plan.contextToReplace,
        ),
        isFalse,
      );
    });
  });
}
