import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _sakuraPink = Color(0xFFF48FB1);
  static const _sakuraDark = Color(0xFFEC407A);
  static const _lavender = Color(0xFFCE93D8);
  static const _softPurple = Color(0xFFB39DDB);
  static const _creamBg = Color(0xFFFFF8F0);
  static const _cardLight = Color(0xFFFFFDF5);
  static const _textDark = Color(0xFF3E2723);
  static const _textSoft = Color(0xFF8D6E63);
  static const _surfaceLight = Color(0xFFFFF0F5);

  static const _darkBg = Color(0xFF1A1A2E);
  static const _darkSurface = Color(0xFF16213E);
  static const _darkCard = Color(0xFF0F3460);
  static const _darkText = Color(0xFFE8E0E0);
  static const _darkTextSoft = Color(0xFF9E9E9E);

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: _sakuraDark,
          secondary: _lavender,
          tertiary: _softPurple,
          surface: _surfaceLight,
          surfaceTint: _sakuraPink.withAlpha(60),
          error: const Color(0xFFE57373),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: _textDark,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: _creamBg,
        cardColor: _cardLight,
        brightness: Brightness.light,
        textTheme: GoogleFonts.quicksandTextTheme().apply(
          bodyColor: _textDark,
          displayColor: _textDark,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: _textDark,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
          titleTextStyle: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textDark,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 3,
          shadowColor: Colors.black.withAlpha(40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          color: _cardLight.withAlpha(240),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withAlpha(230),
          indicatorColor: _sakuraPink.withAlpha(120),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _sakuraDark,
              );
            }
            return GoogleFonts.quicksand(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textSoft,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: _sakuraDark, size: 22);
            }
            return const IconThemeData(color: _textSoft, size: 22);
          }),
          elevation: 8,
          shadowColor: Colors.black.withAlpha(30),
          surfaceTintColor: Colors.transparent,
          height: 64,
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.white,
          indicatorColor: _sakuraPink.withAlpha(80),
          labelType: NavigationRailLabelType.all,
        ),
        iconTheme: const IconThemeData(color: _sakuraDark),
        dividerTheme: DividerThemeData(
          color: _sakuraPink.withAlpha(50),
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withAlpha(200),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _sakuraPink.withAlpha(100)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _sakuraDark, width: 2),
          ),
          hintStyle: const TextStyle(color: _textSoft),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _sakuraDark,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: _sakuraDark.withAlpha(80),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _lavender,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _sakuraDark,
            side: const BorderSide(color: _sakuraDark),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _sakuraPink.withAlpha(30),
          selectedColor: _sakuraPink.withAlpha(100),
          labelStyle: const TextStyle(color: _textDark, fontSize: 12),
          side: BorderSide(color: _sakuraPink.withAlpha(60)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _sakuraDark;
            }
            return const Color(0xFFBCAAA4);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _sakuraDark.withAlpha(128);
            }
            return const Color(0xFFD7CCC8);
          }),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: _sakuraDark,
          inactiveTrackColor: _sakuraPink.withAlpha(80),
          thumbColor: _sakuraDark,
          overlayColor: _sakuraDark.withAlpha(32),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _sakuraDark,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: Colors.white.withAlpha(240),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Colors.white.withAlpha(240),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: _sakuraPink,
          secondary: _lavender,
          tertiary: _softPurple,
          surface: _darkSurface,
          surfaceTint: _sakuraPink.withAlpha(40),
          error: const Color(0xFFEF9A9A),
          onPrimary: const Color(0xFF1A1A2E),
          onSecondary: const Color(0xFF1A1A2E),
          onSurface: _darkText,
          onError: const Color(0xFF1A1A2E),
        ),
        scaffoldBackgroundColor: _darkBg,
        cardColor: _darkCard,
        brightness: Brightness.dark,
        textTheme: GoogleFonts.quicksandTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: _darkText,
          displayColor: _darkText,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: _darkText,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
          titleTextStyle: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _darkText,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 3,
          shadowColor: Colors.black.withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          color: _darkCard.withAlpha(230),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _darkSurface.withAlpha(230),
          indicatorColor: _sakuraDark.withAlpha(120),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _sakuraPink,
              );
            }
            return GoogleFonts.quicksand(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _darkTextSoft,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: _sakuraPink, size: 22);
            }
            return const IconThemeData(color: _darkTextSoft, size: 22);
          }),
          elevation: 8,
          shadowColor: Colors.black.withAlpha(60),
          surfaceTintColor: Colors.transparent,
          height: 64,
        ),
        iconTheme: const IconThemeData(color: _sakuraPink),
        dividerTheme: DividerThemeData(
          color: _sakuraPink.withAlpha(50),
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _darkSurface.withAlpha(200),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _sakuraPink.withAlpha(100)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _sakuraPink, width: 2),
          ),
          hintStyle: const TextStyle(color: _darkTextSoft),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _sakuraDark,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: _sakuraDark.withAlpha(80),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _lavender,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _sakuraPink,
            side: const BorderSide(color: _sakuraPink),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _sakuraDark.withAlpha(50),
          selectedColor: _sakuraDark.withAlpha(150),
          labelStyle: const TextStyle(color: _darkText, fontSize: 12),
          side: BorderSide(color: _sakuraPink.withAlpha(60)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _sakuraPink;
            }
            return _darkTextSoft;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _sakuraPink.withAlpha(128);
            }
            return _darkTextSoft.withAlpha(80);
          }),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _sakuraDark,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: _darkSurface,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: _darkSurface.withAlpha(240),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: _darkSurface.withAlpha(240),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      );

  static ThemeData get pureBlackTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: _sakuraPink,
          secondary: _lavender,
          tertiary: _softPurple,
          surface: const Color(0xFF000000),
          surfaceTint: _sakuraPink.withAlpha(40),
          error: const Color(0xFFEF9A9A),
          onPrimary: const Color(0xFF000000),
          onSecondary: const Color(0xFF000000),
          onSurface: _darkText,
          onError: const Color(0xFF000000),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        cardColor: const Color(0xFF111111),
        brightness: Brightness.dark,
        textTheme:
            GoogleFonts.quicksandTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: _darkText,
          displayColor: _darkText,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: _darkText,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
          titleTextStyle: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _darkText,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 3,
          shadowColor: Colors.black.withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          color: const Color(0xFF111111).withAlpha(230),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF050505).withAlpha(230),
          indicatorColor: _sakuraDark.withAlpha(120),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _sakuraPink,
              );
            }
            return GoogleFonts.quicksand(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _darkTextSoft,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: _sakuraPink, size: 22);
            }
            return const IconThemeData(color: _darkTextSoft, size: 22);
          }),
          elevation: 8,
          shadowColor: Colors.black.withAlpha(60),
          surfaceTintColor: Colors.transparent,
          height: 64,
        ),
        iconTheme: const IconThemeData(color: _sakuraPink),
        dividerTheme: DividerThemeData(
          color: _sakuraPink.withAlpha(50),
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0A0A0A).withAlpha(200),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _sakuraPink.withAlpha(100)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _sakuraPink, width: 2),
          ),
          hintStyle: const TextStyle(color: _darkTextSoft),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _sakuraDark,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: _sakuraDark.withAlpha(80),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _lavender,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _sakuraPink,
            side: const BorderSide(color: _sakuraPink),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _sakuraDark.withAlpha(50),
          selectedColor: _sakuraDark.withAlpha(150),
          labelStyle: const TextStyle(color: _darkText, fontSize: 12),
          side: BorderSide(color: _sakuraPink.withAlpha(60)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _sakuraPink;
            }
            return _darkTextSoft;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _sakuraPink.withAlpha(128);
            }
            return _darkTextSoft.withAlpha(80);
          }),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _sakuraDark,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: const Color(0xFF111111),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: const Color(0xFF050505).withAlpha(240),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: const Color(0xFF0A0A0A).withAlpha(240),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      );
}
