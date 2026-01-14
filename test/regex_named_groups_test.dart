import 'package:import_rules/src/import_rule.dart';
import 'package:test/test.dart';

void main() {
  group('Regex Named Groups', () {
    test('TargetPattern detects regex patterns correctly', () {
      final regexPattern = TargetPattern(
        pattern: r'lib/features/business/(?<feature>[^/]+)/**',
      );
      final globPattern = TargetPattern(pattern: 'lib/features/business/**');

      expect(regexPattern.isRegex, isTrue);
      expect(globPattern.isRegex, isFalse);
    });

    test('TargetPattern extracts named capture groups', () {
      final pattern = TargetPattern(
        pattern: r'lib/features/(?<group>[^/]+)/(?<feature>[^/]+)/**',
      );

      final file =
          'lib/features/business/wallet/presentation/providers/wallet_notifier.dart';
      final groups = pattern.extractGroups(file);

      expect(groups['group'], equals('business'));
      expect(groups['feature'], equals('wallet'));
    });

    test('TargetPattern matches files with regex patterns', () {
      final pattern = TargetPattern(
        pattern: r'lib/features/business/(?<feature>[^/]+)/**',
      );

      expect(
        pattern.matches(
          'lib/features/business/wallet/domain/entities/wallet.dart',
        ),
        isTrue,
      );
      expect(
        pattern.matches(
          'lib/features/business/profile/presentation/profile_page.dart',
        ),
        isTrue,
      );
      expect(pattern.matches('lib/core/utils/logger.dart'), isFalse);
    });

    test('DisallowPattern substitutes captured group variables', () {
      final pattern = DisallowPattern(
        pattern: r'lib/features/business/$feature/**',
      );

      final capturedGroups = {'feature': 'wallet'};

      // Should match wallet feature
      expect(
        pattern.matches(
          'lib/features/business/wallet/domain/entities/wallet.dart',
          'lib/features/business/wallet/presentation/providers',
          capturedGroups: capturedGroups,
        ),
        isTrue,
      );

      // Should not match profile feature
      expect(
        pattern.matches(
          'lib/features/business/profile/domain/user.dart',
          'lib/features/business/wallet/presentation/providers',
          capturedGroups: capturedGroups,
        ),
        isFalse,
      );
    });

    test('ImportRule uses captured groups for feature isolation', () {
      final rule = ImportRule(
        reason: 'Features should be isolated using regex groups',
        targetPatterns: [
          TargetPattern(pattern: r'lib/features/business/(?<feature>[^/]+)/**'),
        ],
        disallowPatterns: [
          DisallowPattern(pattern: 'lib/features/business/**'),
        ],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/features/business/$feature/**'),
        ],
      );

      // Test case 1: wallet feature can import from its own files
      final walletFile =
          'lib/features/business/wallet/presentation/providers/wallet_notifier.dart';
      final walletDomainImport = Import(
        uri: 'lib/features/business/wallet/domain/entities/wallet.dart',
      );

      expect(
        rule.canImport(walletFile, walletDomainImport),
        isTrue,
        reason:
            'Wallet feature should be able to import from its own domain layer',
      );

      // Test case 2: wallet feature cannot import from profile feature
      final profileImport = Import(
        uri: 'lib/features/business/profile/domain/user.dart',
      );

      expect(
        rule.canImport(walletFile, profileImport),
        isFalse,
        reason:
            'Wallet feature should not be able to import from profile feature',
      );

      // Test case 3: profile feature can import from its own files
      final profileFile =
          'lib/features/business/profile/presentation/profile_page.dart';
      final profileDomainImport = Import(
        uri: 'lib/features/business/profile/domain/user.dart',
      );

      expect(
        rule.canImport(profileFile, profileDomainImport),
        isTrue,
        reason:
            'Profile feature should be able to import from its own domain layer',
      );

      // Test case 4: profile feature cannot import from wallet feature
      expect(
        rule.canImport(profileFile, walletDomainImport),
        isFalse,
        reason:
            'Profile feature should not be able to import from wallet feature',
      );
    });

    test('ImportRule supports multiple capture groups', () {
      final rule = ImportRule(
        reason: 'Support multiple capture groups',
        targetPatterns: [
          TargetPattern(
            pattern: r'lib/features/(?<group>[^/]+)/(?<feature>[^/]+)/**',
          ),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/features/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/features/$group/$feature/**'),
        ],
      );

      final walletFile =
          'lib/features/business/wallet/presentation/providers/wallet_notifier.dart';
      final walletImport = Import(
        uri: 'lib/features/business/wallet/domain/entities/wallet.dart',
      );
      final profileImport = Import(
        uri: 'lib/features/business/profile/domain/user.dart',
      );

      expect(rule.canImport(walletFile, walletImport), isTrue);
      expect(rule.canImport(walletFile, profileImport), isFalse);
    });

    test('ImportRule works with deeply nested feature structures', () {
      final rule = ImportRule(
        reason: 'Deep nesting with regex groups',
        targetPatterns: [
          TargetPattern(pattern: r'lib/features/business/(?<feature>[^/]+)/**'),
        ],
        disallowPatterns: [
          DisallowPattern(pattern: 'lib/features/business/**'),
        ],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/features/business/$feature/**'),
        ],
      );

      final deepFile =
          'lib/features/business/wallet/presentation/pages/home/widgets/balance_card.dart';
      final deepImport = Import(
        uri: 'lib/features/business/wallet/domain/entities/transaction.dart',
      );

      expect(
        rule.canImport(deepFile, deepImport),
        isTrue,
        reason: 'Deeply nested files should still recognize feature root',
      );
    });

    test('ImportRule handles edge cases with special characters', () {
      final rule = ImportRule(
        reason: 'Handle special characters in feature names',
        targetPatterns: [
          TargetPattern(pattern: r'lib/features/(?<feature>[\w-]+)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/features/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/features/$feature/**'),
        ],
      );

      final file = 'lib/features/my-feature/src/utils.dart';
      final sameFeatureImport = Import(
        uri: 'lib/features/my-feature/domain/entity.dart',
      );
      final differentFeatureImport = Import(
        uri: 'lib/features/other-feature/domain/entity.dart',
      );

      expect(rule.canImport(file, sameFeatureImport), isTrue);
      expect(rule.canImport(file, differentFeatureImport), isFalse);
    });

    test('ImportRule combines regex groups with \$TARGET_DIR', () {
      final rule = ImportRule(
        reason: 'Combine regex groups with TARGET_DIR',
        targetPatterns: [
          TargetPattern(pattern: r'lib/features/business/(?<feature>[^/]+)/**'),
        ],
        disallowPatterns: [
          DisallowPattern(pattern: 'lib/features/business/**'),
        ],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'$TARGET_DIR/**'), // Same directory
          DisallowPattern(
            pattern: r'lib/features/business/$feature/**',
          ), // Captured group
        ],
      );

      final walletFile =
          'lib/features/business/wallet/presentation/providers/wallet_notifier.dart';

      // Can import from same directory
      final sameDir = Import(
        uri:
            'lib/features/business/wallet/presentation/providers/wallet_state.dart',
      );
      expect(rule.canImport(walletFile, sameDir), isTrue);

      // Can import from different directory in same feature
      final differentDir = Import(
        uri: 'lib/features/business/wallet/domain/entities/wallet.dart',
      );
      expect(rule.canImport(walletFile, differentDir), isTrue);

      // Cannot import from different feature
      final differentFeature = Import(
        uri: 'lib/features/business/profile/domain/user.dart',
      );
      expect(rule.canImport(walletFile, differentFeature), isFalse);
    });

    // ========== 通用场景测试 ==========

    test('Generic: Module isolation with named groups', () {
      // 场景：不同模块之间隔离，但允许模块内部引用
      final rule = ImportRule(
        reason: 'Modules should be isolated from each other',
        targetPatterns: [
          TargetPattern(pattern: r'lib/modules/(?<module>[^/]+)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/modules/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/modules/$module/**'),
        ],
      );

      final authFile = 'lib/modules/auth/services/auth_service.dart';
      final authImport = Import(uri: 'lib/modules/auth/models/user.dart');
      final paymentImport = Import(
        uri: 'lib/modules/payment/models/order.dart',
      );

      expect(rule.canImport(authFile, authImport), isTrue);
      expect(rule.canImport(authFile, paymentImport), isFalse);
    });

    test('Generic: Layered architecture enforcement', () {
      // 场景：强制分层架构，presentation 层不能直接访问 data 层
      final rule = ImportRule(
        reason: 'Presentation layer cannot access data layer directly',
        targetPatterns: [
          TargetPattern(pattern: r'lib/(?<module>[^/]+)/presentation/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: r'lib/$module/data/**')],
      );

      final presentationFile = 'lib/user/presentation/pages/profile_page.dart';
      final dataImport = Import(
        uri: 'lib/user/data/repositories/user_repo.dart',
      );
      final domainImport = Import(uri: 'lib/user/domain/entities/user.dart');

      expect(rule.canImport(presentationFile, dataImport), isFalse);
      expect(rule.canImport(presentationFile, domainImport), isTrue);
    });

    test('Generic: Version-specific imports', () {
      // scene：different API versions should not cross-reference
      final rule = ImportRule(
        reason: 'API versions should not cross-reference',
        targetPatterns: [
          TargetPattern(pattern: r'lib/api/(?<version>v\d+)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: r'lib/api/v*/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/api/$version/**'),
          DisallowPattern(pattern: 'lib/api/common/**'),
        ],
      );

      final v1File = 'lib/api/v1/controllers/user_controller.dart';
      final v1Import = Import(uri: 'lib/api/v1/models/user.dart');
      final v2Import = Import(uri: 'lib/api/v2/models/user.dart');
      final commonImport = Import(uri: 'lib/api/common/response.dart');

      expect(rule.canImport(v1File, v1Import), isTrue);
      expect(rule.canImport(v1File, v2Import), isFalse);
      expect(rule.canImport(v1File, commonImport), isTrue);
    });

    test('Generic: Platform-specific code isolation', () {
      // scene：platform-specific code should not cross-reference
      final rule = ImportRule(
        reason: 'Platform-specific code should not cross-reference',
        targetPatterns: [
          TargetPattern(
            pattern: r'lib/platforms/(?<platform>android|ios|web)/**',
          ),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/platforms/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/platforms/$platform/**'),
          DisallowPattern(pattern: 'lib/platforms/common/**'),
        ],
      );

      final androidFile = 'lib/platforms/android/native_bridge.dart';
      final androidImport = Import(uri: 'lib/platforms/android/utils.dart');
      final iosImport = Import(uri: 'lib/platforms/ios/native_bridge.dart');
      final commonImport = Import(uri: 'lib/platforms/common/interface.dart');

      expect(rule.canImport(androidFile, androidImport), isTrue);
      expect(rule.canImport(androidFile, iosImport), isFalse);
      expect(rule.canImport(androidFile, commonImport), isTrue);
    });

    test('Generic: Tenant isolation in multi-tenant app', () {
      // scene：tenant-specific code should be isolated
      final rule = ImportRule(
        reason: 'Tenant-specific code should be isolated',
        targetPatterns: [
          TargetPattern(pattern: r'lib/tenants/(?<tenant>[^/]+)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/tenants/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/tenants/$tenant/**'),
          DisallowPattern(pattern: 'lib/tenants/shared/**'),
        ],
      );

      final tenantAFile = 'lib/tenants/company_a/config.dart';
      final tenantAImport = Import(uri: 'lib/tenants/company_a/theme.dart');
      final tenantBImport = Import(uri: 'lib/tenants/company_b/theme.dart');
      final sharedImport = Import(uri: 'lib/tenants/shared/base_config.dart');

      expect(rule.canImport(tenantAFile, tenantAImport), isTrue);
      expect(rule.canImport(tenantAFile, tenantBImport), isFalse);
      expect(rule.canImport(tenantAFile, sharedImport), isTrue);
    });

    test('Generic: Environment-specific configurations', () {
      // scene：environment-specific configs should not cross-reference
      final rule = ImportRule(
        reason: 'Environment configs should not cross-reference',
        targetPatterns: [
          TargetPattern(pattern: r'lib/config/(?<env>dev|staging|prod)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/config/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/config/$env/**'),
          DisallowPattern(pattern: 'lib/config/base/**'),
        ],
      );

      final devFile = 'lib/config/dev/api_config.dart';
      final devImport = Import(uri: 'lib/config/dev/database_config.dart');
      final prodImport = Import(uri: 'lib/config/prod/api_config.dart');
      final baseImport = Import(uri: 'lib/config/base/config_interface.dart');

      expect(rule.canImport(devFile, devImport), isTrue);
      expect(rule.canImport(devFile, prodImport), isFalse);
      expect(rule.canImport(devFile, baseImport), isTrue);
    });

    test('Generic: Three-level hierarchy with multiple groups', () {
      // scene：three-level hierarchy with multiple groups
      final rule = ImportRule(
        reason: 'Enforce three-level module hierarchy',
        targetPatterns: [
          TargetPattern(
            pattern:
                r'lib/(?<category>[^/]+)/(?<module>[^/]+)/(?<layer>[^/]+)/**',
          ),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/$category/$module/$layer/**'),
          DisallowPattern(pattern: r'lib/$category/$module/shared/**'),
          DisallowPattern(pattern: 'lib/core/**'),
        ],
      );

      final file = 'lib/business/payment/presentation/pages/checkout.dart';
      final sameLayerImport = Import(
        uri: 'lib/business/payment/presentation/widgets/card.dart',
      );
      final sharedImport = Import(
        uri: 'lib/business/payment/shared/constants.dart',
      );
      final differentLayerImport = Import(
        uri: 'lib/business/payment/data/repositories/payment_repo.dart',
      );
      final coreImport = Import(uri: 'lib/core/utils/logger.dart');

      expect(rule.canImport(file, sameLayerImport), isTrue);
      expect(rule.canImport(file, sharedImport), isTrue);
      expect(rule.canImport(file, differentLayerImport), isFalse);
      expect(rule.canImport(file, coreImport), isTrue);
    });

    test('Generic: Package namespace isolation', () {
      // scene：package namespace isolation
      final rule = ImportRule(
        reason: 'Package namespaces should be isolated',
        targetPatterns: [
          TargetPattern(pattern: r'lib/packages/(?<package>[\w_]+)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/packages/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/packages/$package/**'),
        ],
      );

      final packageAFile = 'lib/packages/ui_kit/buttons/primary_button.dart';
      final packageAImport = Import(
        uri: 'lib/packages/ui_kit/theme/colors.dart',
      );
      final packageBImport = Import(uri: 'lib/packages/analytics/tracker.dart');

      expect(rule.canImport(packageAFile, packageAImport), isTrue);
      expect(rule.canImport(packageAFile, packageBImport), isFalse);
    });

    test('Generic: Complex regex pattern with optional segments', () {
      // scene：complex regex pattern with optional segments
      final rule = ImportRule(
        reason: 'Complex pattern matching',
        targetPatterns: [
          TargetPattern(
            pattern:
                r'lib/(?<domain>\w+)/(?<subdomain>\w+)?/?(?<module>[^/]+)/**',
          ),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/**')],
        excludeDisallowPatterns: [DisallowPattern(pattern: r'lib/$domain/**')],
      );

      final file = 'lib/ecommerce/catalog/products/product_list.dart';
      final sameDomainImport = Import(
        uri: 'lib/ecommerce/cart/cart_service.dart',
      );
      final differentDomainImport = Import(uri: 'lib/analytics/tracker.dart');

      expect(rule.canImport(file, sameDomainImport), isTrue);
      expect(rule.canImport(file, differentDomainImport), isFalse);
    });

    test('Generic: Capture group with numeric patterns', () {
      // scene：capture numeric version
      final rule = ImportRule(
        reason: 'Numeric version isolation',
        targetPatterns: [
          TargetPattern(pattern: r'lib/schemas/(?<version>\d+\.\d+)/**'),
        ],
        disallowPatterns: [DisallowPattern(pattern: r'lib/schemas/*/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/schemas/$version/**'),
        ],
      );

      final v1File = 'lib/schemas/1.0/user_schema.dart';
      final v1Import = Import(uri: 'lib/schemas/1.0/base_schema.dart');
      final v2Import = Import(uri: 'lib/schemas/2.0/user_schema.dart');

      expect(rule.canImport(v1File, v1Import), isTrue);
      expect(rule.canImport(v1File, v2Import), isFalse);
    });

    test('Generic: Multiple independent capture groups', () {
      // scene：multiple independent capture groups for different purposes
      final rule = ImportRule(
        reason: 'Multiple independent groups',
        targetPatterns: [
          TargetPattern(
            pattern: r'lib/(?<team>team_\w+)/(?<project>project_\w+)/**',
          ),
        ],
        disallowPatterns: [DisallowPattern(pattern: 'lib/**')],
        excludeDisallowPatterns: [
          DisallowPattern(pattern: r'lib/$team/$project/**'),
          DisallowPattern(pattern: r'lib/$team/shared/**'),
        ],
      );

      final file = 'lib/team_alpha/project_x/src/main.dart';
      final sameProjectImport = Import(
        uri: 'lib/team_alpha/project_x/utils/helper.dart',
      );
      final teamSharedImport = Import(
        uri: 'lib/team_alpha/shared/constants.dart',
      );
      final differentProjectImport = Import(
        uri: 'lib/team_alpha/project_y/utils/helper.dart',
      );
      final differentTeamImport = Import(
        uri: 'lib/team_beta/project_x/utils/helper.dart',
      );

      expect(rule.canImport(file, sameProjectImport), isTrue);
      expect(rule.canImport(file, teamSharedImport), isTrue);
      expect(rule.canImport(file, differentProjectImport), isFalse);
      expect(rule.canImport(file, differentTeamImport), isFalse);
    });
  });
}
