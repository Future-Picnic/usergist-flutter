import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/theme.dart';
import 'package:usergist_feedback/src/ui/theme_resolver.dart';

void main() {
  testWidgets(
    'per-prompt theme wins while global theme fills missing fields',
    (tester) async {
      late ResolvedPromptTheme resolved;
      const global = PromptTheme(
        colors: PromptThemeColors(
          primary: Color(0xFF111111),
          background: Colors.white,
          text: Color(0xFF222222),
          subtext: Color(0xFF333333),
          border: Color(0xFF444444),
        ),
        radius: 16,
        fontFamily: 'Global Font',
      );
      const prompt = PromptTheme(
        colors: PromptThemeColors(
          primary: Color(0xFF6548E8),
          background: Color(0xFFF7F5FF),
          text: Color(0xFF1D1933),
        ),
        radius: 24,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = ResolvedPromptTheme.of(
                context,
                serverTheme: prompt,
                overrides: global,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.primary, const Color(0xFF6548E8));
      expect(resolved.background, const Color(0xFFF7F5FF));
      expect(resolved.text, const Color(0xFF1D1933));
      expect(resolved.subtext, const Color(0xFF333333));
      expect(resolved.border, const Color(0xFF444444));
      expect(resolved.radius, 24);
      expect(resolved.fontFamily, 'Global Font');
    },
  );
}
