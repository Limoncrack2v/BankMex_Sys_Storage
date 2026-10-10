import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/models/quota_proposal.dart';

void main() {
  group('quotaOnSelect', () {
    test('la misma familia conserva lo escrito', () {
      for (final edited in [true, false]) {
        expect(
          quotaOnSelect(proposedFor: 'famA', selected: 'famA', edited: edited),
          QuotaOnSelect.keep,
        );
      }
    });

    test('familia distinta sin cambios propone la cuota', () {
      expect(
        quotaOnSelect(proposedFor: 'famA', selected: 'famB', edited: false),
        QuotaOnSelect.propose,
      );
    });

    test('familia distinta con cambios propone y avisa', () {
      expect(
        quotaOnSelect(proposedFor: 'famA', selected: 'famB', edited: true),
        QuotaOnSelect.proposeAndWarn,
      );
    });

    test('sin propuesta previa sin cambios propone la cuota', () {
      expect(
        quotaOnSelect(proposedFor: null, selected: 'famA', edited: false),
        QuotaOnSelect.propose,
      );
    });

    test('sin propuesta previa con cambios propone y avisa', () {
      expect(
        quotaOnSelect(proposedFor: null, selected: 'famA', edited: true),
        QuotaOnSelect.proposeAndWarn,
      );
    });
  });
}
