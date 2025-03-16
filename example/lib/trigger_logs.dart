import 'package:code_scout/code_scout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class TriggerLogs extends StatefulWidget {
  const TriggerLogs({super.key});

  @override
  State<TriggerLogs> createState() => _TriggerLogsState();
}

class _TriggerLogsState extends State<TriggerLogs> {
  @override
  void initState() {
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      CodeScout.instance.init(
        context: context,
        freshContextFetcher: () => context,
        configuration: CodeScoutConfiguration(),
      );
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trigger Logs')),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Trigger Logs'),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                // CodeScout.instance.logAnalytics(
                //   'Analytics Triggered',
                //   dateTime: DateTime.now(),
                // );
              },
              child: const Text('Analytics Logs'),
            ),
            SizedBox(height: 12),
            // ElevatedButton(
            //   onPressed: () {
            //     CodeScout.logAnalytics(
            //       'Analytics Triggered',
            //       dateTime: DateTime.now(),
            //     );
            //   },
            //   child: const Text('Analytics Logs'),
            // ),
            ElevatedButton(
              onPressed: () {
                CodeScout.instance.toggleIcon();
              },
              child: const Text('Toggle icon'),
            ),
          ],
        ),
      ),
    );
  }
}
