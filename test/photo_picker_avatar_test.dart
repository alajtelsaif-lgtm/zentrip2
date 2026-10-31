import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zentrip/features/auth/presentation/widgets/photo_picker_avatar.dart';
import 'package:zentrip/l10n/app_localizations.dart';

void main() {
  testWidgets('removing a selected profile photo clears its preview and value',
      (tester) async {
    final photo = XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      name: 'avatar.png',
      mimeType: 'image/png',
    );
    XFile? selection = photo;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PhotoPickerAvatar(
          initialFile: photo,
          onChanged: (value) => selection = value,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byType(PhotoPickerAvatar));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(selection, isNull);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
