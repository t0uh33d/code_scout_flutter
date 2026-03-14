import 'dart:developer';
import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:flutter/material.dart';

class CSxInterfaceController extends ChangeNotifier {
  static final CSxInterfaceController i = CSxInterfaceController._i();

  factory CSxInterfaceController() => i;

  CSxInterfaceController._i();

  Socket? socket;
  String? connectedIP;
  int? connectedPort;

  bool connected = false;

  static const Duration _connectTimeout = Duration(seconds: 10);

  void init() {}

  Future<void> tryToConnect({
    required String ip,
    required String port,
    required String identifier,
    required ValueNotifier<bool>? notifier,
  }) async {
    notifier?.value = true;
    try {
      final port0 = int.tryParse(port);
      if (port0 == null || port0 < 1 || port0 > 65535) {
        log('CodeScout: Invalid port number: $port');
        return;
      }

      final socket0 =
          await Socket.connect(ip, port0, timeout: _connectTimeout);

      final connectionComms = CodeScoutComms(
        command: CodeScoutCommands.establishConnection,
        payloadType: CodeScoutPayloadType.identifier,
        data: {
          CodeScoutPayloadType.identifier: identifier,
        },
      );

      socket0.listen(
        (event) {
          CodeScoutComms codeScoutComms;
          try {
            String eventData = String.fromCharCodes(event);
            codeScoutComms = CodeScoutComms.fromJson(eventData);
          } catch (e) {
            log('CodeScout: Failed to parse socket event: $e');
            return;
          }

          if (codeScoutComms.command == CodeScoutCommands.connectionApproved) {
            socket = socket0;
            connected = true;
            connectedIP = ip;
            connectedPort = port0;
            notifyListeners();
            return;
          }

          log('CodeScout: Unexpected socket command: ${codeScoutComms.command}');
        },
        onError: (e) {
          log('CodeScout: Socket error: $e');
          resetConnection();
        },
        onDone: resetConnection,
        cancelOnError: true,
      );

      socket0.write(connectionComms);
    } catch (e) {
      log('CodeScout: Failed to connect: $e');
    } finally {
      notifier?.value = false;
    }
  }

  void resetConnection() {
    try {
      socket?.flush();
      socket?.close();
    } catch (e) {
      log('CodeScout: Error closing socket: $e');
    }

    socket = null;
    connected = false;
    connectedIP = null;
    connectedPort = null;
    notifyListeners();
  }

  @override
  void dispose() {
    resetConnection();
    super.dispose();
  }
}
