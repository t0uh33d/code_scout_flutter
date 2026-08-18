import 'package:code_scout/code_scout.dart';
import 'package:flutter/material.dart';

import 'data_screen.dart';
import 'demo_stores.dart';
import 'logs_screen.dart';
import 'network_screen.dart';

/// Where to send logs, if anywhere.
///
/// Passed in rather than written down, so this example runs untouched and no
/// project secret ever reaches a repository:
///
/// ```
/// cp local.example.json local.json   # then fill it in; local.json is gitignored
/// flutter run --dart-define-from-file=local.json
/// ```
///
/// With none of them set the SDK stays on the device: the console printer and
/// the floating overlay still work, and nothing is uploaded. That is a real way
/// to use CodeScout rather than a degraded one, which is why it is the default
/// here.
const csURL = String.fromEnvironment('CS_URL');
const csProjectID = String.fromEnvironment('CS_PROJECT_ID');
const csProjectSecret = String.fromEnvironment('CS_PROJECT_SECRET');

bool get hasDashboard =>
    csURL.isNotEmpty && csProjectID.isNotEmpty && csProjectSecret.isNotEmpty;

ProjectCredentials? _credentials() {
  if (!hasDashboard) return null;
  return ProjectCredentials(
    link: csURL.endsWith('/') ? csURL : '$csURL/',
    projectID: csProjectID,
    projectSecret: csProjectSecret,
  );
}

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeScout',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF078DEE)),
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;
  DemoStores? _stores;

  @override
  void initState() {
    super.initState();

    // After the first frame, and with a context: the floating overlay needs a
    // widget tree to insert itself into, and freshContextFetcher is how it
    // finds the current one again later, once the app has navigated somewhere
    // else.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await CodeScout.instance.init(
        freshContextFetcher: () => context,
        configuration: CodeScoutConfiguration(
          logging: LoggingBehavior(
            // The example wants to show every level. An app would usually
            // leave this alone and keep debug noise out of the upload.
            minimumLevel: LogLevel.all,
          ),
          projectCredentials: _credentials(),
          sync: LogSyncBehavior(syncInterval: const Duration(seconds: 15)),
          // Off by default, because the token is sometimes the bug you are
          // chasing. recommended() covers the usual suspects; add your own with
          // RedactionBehavior.recommended(bodyKeys: {'order_signature'}).
          redaction: RedactionBehavior.recommended(),
        ),
      );

      // Offer everything this app stores locally, so a live session can browse
      // it from the dashboard. Nothing is browsable until this is called, and
      // nothing is editable without writable — a store exposed to look at has
      // not thereby been exposed to change.
      final stores = await DemoStores.openAndRegister();

      if (mounted) setState(() => _stores = stores);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeScout'),
        bottom: const _StatusBar(),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const LogsScreen(),
          const NetworkScreen(),
          DataScreen(stores: _stores),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notes), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.swap_vert), label: 'Network'),
          NavigationDestination(icon: Icon(Icons.table_rows), label: 'Data'),
        ],
      ),
    );
  }
}

/// Says where the logs are going. "Nothing appeared in my dashboard" is almost
/// always this.
class _StatusBar extends StatelessWidget implements PreferredSizeWidget {
  const _StatusBar();

  @override
  Size get preferredSize => const Size.fromHeight(30);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          hasDashboard
              ? 'Uploading to $csURL'
              : 'On device only. Tap the floating button to read your logs.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
