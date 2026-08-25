// Forwarding Talker's logs to CodeScout.
//
// Nothing about your logging changes. Talker keeps printing, TalkerScreen keeps
// working, every talker_* logger keeps working. The observer only adds a second
// reader, so the same logs also reach a dashboard you can search across every
// device rather than only the one in your hand.
import 'package:code_scout/code_scout.dart';
import 'package:code_scout_talker/code_scout_talker.dart';
import 'package:flutter/material.dart';
import 'package:talker/talker.dart';

// Not const: the observer announces itself when it is built, so the panel can
// tell "no logs yet" apart from "you forgot to wire this up".
final talker = Talker(observer: CodeScoutTalkerObserver(tags: {'example'}));

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: Home());
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // No credentials here, so this stays entirely on the device: the console
      // and the floating panel work with no server at all.
      await CodeScout.instance.init(freshContextFetcher: () => context);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('code_scout_talker')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => talker.info('Something worth noting'),
                child: const Text('Log info'),
              ),
              ElevatedButton(
                onPressed: () => talker.handle(
                  StateError('the cart was empty'),
                  StackTrace.current,
                  'Checkout failed',
                ),
                child: const Text('Log an error'),
              ),
            ],
          ),
        ),
      );
}
