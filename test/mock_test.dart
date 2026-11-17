import 'package:flutter_test/flutter_test.dart';
import 'package:kirora_flutter/testing.dart';

void main() {
  test('KiroraMock records calls, answers what it is told and stands in for Kirora', () async {
    final mock = KiroraMock()..pushStatus = PushStatus.disabled;
    final Kirora kirora = mock; // usable wherever the app takes a Kirora

    await kirora.identify('t');
    kirora.track('Order Completed', {'id': 1});
    kirora.trackScreenView('Home');
    kirora.setTrackingConsent(false);
    kirora.track('Not Tracked');

    expect(mock.tracked.map((e) => e.name), ['Order Completed', 'Screen Viewed']);
    expect(await kirora.getPushStatus(), PushStatus.disabled);
    expect((await kirora.getState()).isIdentified, isTrue);
    expect(mock.calls.first.method, 'identify');

    final taps = <NotificationData>[];
    kirora.onNotificationClicked.listen(taps.add);
    mock.simulateNotificationClick({'kirora': 'true'});
    await pumpEventQueue();
    expect(taps, [{'kirora': 'true'}]);

    mock.identifyError = UserTokenError('no token');
    await expectLater(kirora.identify(), throwsA(isA<UserTokenError>()));
  });

  test('KiroraMock keeps events as the SDK would: copied at capture, after beforeSend', () async {
    final mock = KiroraMock(KiroraOptions(
      clientKey: 'kirora_pk_mock',
      beforeSend: (e) => e.name == 'Secret'
          ? null
          : BeforeSendEvent(name: e.name, properties: {...e.properties}..remove('email'), context: e.context),
    ));
    final props = <String, Object?>{'email': 'a@b.c', 'plan': 'pro'};
    mock.track('Signed Up', props);
    props['plan'] = 'changed later';
    mock.track('Secret');
    mock.track('NaN', {'x': double.nan});

    expect(mock.tracked.map((e) => e.name), ['Signed Up']);
    expect(mock.tracked.single.properties, {'plan': 'pro'});
  });

  test('KiroraMock follows requireTrackingConsent, and redacts screen views as the SDK does', () async {
    final mock = KiroraMock(KiroraOptions(
      clientKey: 'kirora_pk_mock',
      requireTrackingConsent: true,
      beforeSend: (e) => e.properties['name'] == 'Secret'
          ? BeforeSendEvent(name: e.name, properties: {'name': 'hidden'}, context: e.context)
          : e,
    ));
    mock.track('Before Consent');
    expect(mock.tracked, isEmpty);

    mock.setTrackingConsent(true);
    mock.trackScreenView('Home');
    mock.trackScreenView('Secret');
    expect(mock.tracked.map((e) => e.properties), [
      {'name': 'Home'},
      {'name': 'hidden'},
    ]);
  });
}
