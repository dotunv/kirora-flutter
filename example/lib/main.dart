import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kirora_flutter/kirora_flutter.dart';

/// Optional build-time defaults, so a run can start pre-filled:
/// `flutter run --dart-define=KIRORA_KEY=kirora_pk_… --dart-define=KIRORA_API=https://…`
const _defaultKey = String.fromEnvironment('KIRORA_KEY');
const _defaultApi = String.fromEnvironment('KIRORA_API', defaultValue: 'https://api.kirora.io');
const _defaultToken = String.fromEnvironment('KIRORA_TOKEN');

/// Everything the SDK prints (it logs with `print`) is also kept here for the Log tab.
final ValueNotifier<List<String>> sdkLog = ValueNotifier(const []);

void _record(String line) {
  final t = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  final next = [...sdkLog.value, '$stamp  $line'];
  sdkLog.value = next.length > 300 ? next.sublist(next.length - 300) : next;
}

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const ExampleApp());
    },
    (error, stack) => _record('Uncaught: $error'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        _record(line);
      },
    ),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kirora example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      home: const Root(),
    );
  }
}

/// What the Setup screen collects; becomes [KiroraOptions].
class Config {
  Config({
    required this.clientKey,
    required this.apiUrl,
    this.requireTrackingConsent = false,
    this.trackSessions = true,
    this.trackAppLifecycle = true,
  });

  String clientKey;
  String apiUrl;
  bool requireTrackingConsent;
  bool trackSessions;
  bool trackAppLifecycle;
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  Kirora? kirora;
  StreamSubscription<NotificationData>? _clicks;

  /// The user token the app holds; `fetchUserToken` hands the SDK whatever is here.
  final tokenController = TextEditingController(text: _defaultToken);
  Config config = Config(clientKey: _defaultKey, apiUrl: _defaultApi);

  Future<void> _start(Config c) async {
    config = c;
    // A second instance replaces the first; its signed-in user carries over.
    final k = Kirora(KiroraOptions(
      push: const KiroraPushOptions(),
      clientKey: c.clientKey.trim(),
      apiUrl: c.apiUrl.trim(),
      requireTrackingConsent: c.requireTrackingConsent,
      trackSessions: c.trackSessions,
      trackAppLifecycle: c.trackAppLifecycle,
      logLevel: LogLevel.debug,
      fetchUserToken: () async {
        final t = tokenController.text.trim();
        return t.isEmpty ? null : t;
      },
    ));
    _clicks?.cancel();
    _clicks = k.onNotificationClicked.listen((data) => _record('Notification clicked: ${jsonEncode(data)}'));
    _record('Started SDK $sdkVersion against ${c.apiUrl.trim()}');
    setState(() => kirora = k);
  }

  @override
  void dispose() {
    _clicks?.cancel();
    tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = kirora;
    if (k == null) return SetupPage(initial: config, onStart: _start);
    return HomePage(
      kirora: k,
      tokenController: tokenController,
      onReconfigure: () => setState(() => kirora = null),
    );
  }
}

// ---------------------------------------------------------------- Setup

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.initial, required this.onStart});

  final Config initial;
  final void Function(Config) onStart;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late final key = TextEditingController(text: widget.initial.clientKey);
  late final api = TextEditingController(text: widget.initial.apiUrl);
  late bool consent = widget.initial.requireTrackingConsent;
  late bool sessions = widget.initial.trackSessions;
  late bool lifecycle = widget.initial.trackAppLifecycle;

  @override
  void dispose() {
    key.dispose();
    api.dispose();
    super.dispose();
  }

  bool get _valid => key.text.trim().isNotEmpty && api.text.trim().startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kirora setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Public client key and API URL of your workspace. The token secret never goes in the app.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: key,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Client key (kirora_pk_…)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: api,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'API URL (https only)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('requireTrackingConsent'),
            subtitle: const Text('Stores and sends nothing until consent is granted'),
            value: consent,
            onChanged: (v) => setState(() => consent = v),
          ),
          SwitchListTile(
            title: const Text('trackSessions'),
            value: sessions,
            onChanged: (v) => setState(() => sessions = v),
          ),
          SwitchListTile(
            title: const Text('trackAppLifecycle'),
            subtitle: const Text('Application Installed / Opened / Updated / Backgrounded'),
            value: lifecycle,
            onChanged: (v) => setState(() => lifecycle = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _valid
                ? () => widget.onStart(Config(
                      clientKey: key.text,
                      apiUrl: api.text,
                      requireTrackingConsent: consent,
                      trackSessions: sessions,
                      trackAppLifecycle: lifecycle,
                    ))
                : null,
            child: const Text('Start SDK'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Home

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.kirora, required this.tokenController, required this.onReconfigure});

  final Kirora kirora;
  final TextEditingController tokenController;
  final VoidCallback onReconfigure;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  KiroraState? state;
  Timer? _poll;

  Kirora get kirora => widget.kirora;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await kirora.getState();
    if (mounted) setState(() => state = s);
  }

  void _say(String message) {
    _record(message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs an SDK call, reports its outcome, and refreshes the state card.
  Future<void> _run(String label, Future<Object?> Function() call) async {
    try {
      final result = await call();
      _say(result == null ? '$label: done' : '$label: $result');
    } on UserTokenError catch (e) {
      _say('$label failed: ${e.message}');
    } catch (e) {
      _say('$label failed: $e');
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kirora example'),
          actions: [
            IconButton(
              tooltip: 'Change key / URL',
              icon: const Icon(Icons.settings),
              onPressed: widget.onReconfigure,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Identity'),
              Tab(text: 'Track'),
              Tab(text: 'Consent'),
              Tab(text: 'Log'),
            ],
          ),
        ),
        body: Column(
          children: [
            StateCard(state: state),
            Expanded(
              child: TabBarView(
                children: [
                  IdentityTab(kirora: kirora, tokenController: widget.tokenController, run: _run),
                  TrackTab(kirora: kirora, run: _run, say: _say, refresh: _refresh),
                  ConsentTab(kirora: kirora, state: state, run: _run, say: _say, refresh: _refresh),
                  const LogTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef RunFn = Future<void> Function(String label, Future<Object?> Function() call);

class StateCard extends StatelessWidget {
  const StateCard({super.key, required this.state});

  final KiroraState? state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget row(String k, String v, {bool copy = false}) => InkWell(
          onLongPress: copy && v != '—'
              ? () {
                  Clipboard.setData(ClipboardData(text: v));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $k')));
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 104, child: Text(k, style: style?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(child: Text(v, style: style)),
              ],
            ),
          ),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: s == null
            ? const Text('Reading state…')
            : Column(
                children: [
                  row('identified', '${s.isIdentified}'),
                  row('queued events', '${s.queuedEventCount}'),
                  row('device id', s.deviceId ?? '—', copy: true),
                  row('session id', s.sessionId ?? '—', copy: true),
                  row('tracking consent', '${s.trackingConsent}'),
                  row('push consent', '${s.pushConsent}'),
                  row('push token', s.pushToken == null ? '—' : 'set'),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Identity

class IdentityTab extends StatelessWidget {
  const IdentityTab({super.key, required this.kirora, required this.tokenController, required this.run});

  final Kirora kirora;
  final TextEditingController tokenController;
  final RunFn run;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Paste a user token: an HS256 JWT with a `sub` claim that your server signs with the token '
          'secret. identify() uses it, and the SDK asks for it again if Kirora refuses it as expired.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tokenController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'User token (JWT)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => run('identify', () async {
                  await kirora.identify();
                  return null;
                }),
                child: const Text('Identify'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => run('logout', () async {
                  await kirora.logout();
                  return null;
                }),
                child: const Text('Log out'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Track

class TrackTab extends StatefulWidget {
  const TrackTab({super.key, required this.kirora, required this.run, required this.say, required this.refresh});

  final Kirora kirora;
  final RunFn run;
  final void Function(String) say;
  final Future<void> Function() refresh;

  @override
  State<TrackTab> createState() => _TrackTabState();
}

class _TrackTabState extends State<TrackTab> {
  final name = TextEditingController(text: 'Button Pressed');
  final props = TextEditingController(text: '{"screen": "track_tab", "count": 1}');
  final screen = TextEditingController(text: 'Checkout');
  String? propsError;

  @override
  void dispose() {
    name.dispose();
    props.dispose();
    screen.dispose();
    super.dispose();
  }

  void _track() {
    Map<String, Object?>? parsed;
    final raw = props.text.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) throw const FormatException('must be a JSON object');
        parsed = decoded;
      } on FormatException catch (e) {
        setState(() => propsError = e.message);
        return;
      }
    }
    setState(() => propsError = null);
    widget.kirora.track(name.text.trim(), parsed);
    widget.say('Tracked "${name.text.trim()}"');
    widget.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Event name (past-tense Title Case)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: props,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Properties (JSON object, snake_case keys)',
            errorText: propsError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _track, child: const Text('Track event')),
        const Divider(height: 32),
        TextField(
          controller: screen,
          decoration: const InputDecoration(labelText: 'Screen name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            widget.kirora.trackScreenView(screen.text.trim());
            widget.say('Screen viewed: ${screen.text.trim()}');
            widget.refresh();
          },
          child: const Text('Track screen view'),
        ),
        const Divider(height: 32),
        OutlinedButton(
          onPressed: () => widget.run('flush', () async {
            await widget.kirora.flush();
            return null;
          }),
          child: const Text('Flush queue now'),
        ),
        const SizedBox(height: 8),
        Text(
          'Events wait on the device and go at 20 queued, every 30 s, and when the app goes to the '
          'background. Nothing is sent until a user is identified.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Consent & push

class ConsentTab extends StatelessWidget {
  const ConsentTab({
    super.key,
    required this.kirora,
    required this.state,
    required this.run,
    required this.say,
    required this.refresh,
  });

  final Kirora kirora;
  final KiroraState? state;
  final RunFn run;
  final void Function(String) say;
  final Future<void> Function() refresh;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Tracking consent'),
          subtitle: const Text('Withdrawing forgets events still waiting (when consent is required)'),
          value: s?.trackingConsent ?? false,
          onChanged: s == null
              ? null
              : (v) {
                  kirora.setTrackingConsent(v);
                  say('Tracking consent: $v');
                  refresh();
                },
        ),
        SwitchListTile(
          title: const Text('Push (marketing) consent'),
          subtitle: const Text('The user\'s own answer; separate from the OS permission'),
          value: s?.pushConsent ?? false,
          onChanged: s == null
              ? null
              : (v) {
                  kirora.setPushConsent(v);
                  say('Push consent: $v');
                  refresh();
                },
        ),
        const Divider(height: 32),
        FilledButton(
          onPressed: () => run('requestPushPermission', () async => (await kirora.requestPushPermission()).name),
          child: const Text('Request push permission'),
        ),
        const SizedBox(height: 8),
        Text(
          'Shows the Android notification prompt through FCM. When granted, the device registers '
          'for push once a user is identified (see the push token in the state card).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Log

class LogTab extends StatelessWidget {
  const LogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: sdkLog,
      builder: (context, lines, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text('${lines.length} lines'),
                  const Spacer(),
                  TextButton(
                    onPressed: lines.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: lines.join('\n')));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log copied')));
                          },
                    child: const Text('Copy'),
                  ),
                  TextButton(onPressed: () => sdkLog.value = const [], child: const Text('Clear')),
                ],
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? const Center(child: Text('Nothing logged yet'))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: lines.length,
                      itemBuilder: (context, i) => Text(
                        lines[lines.length - 1 - i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
