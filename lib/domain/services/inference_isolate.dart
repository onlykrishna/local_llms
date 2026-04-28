import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:llamadart/llamadart.dart';

class IsolateRequest {
  final String action;
  final dynamic data;
  final SendPort replyPort;

  IsolateRequest(this.action, this.data, this.replyPort);
}

class IsolateResponse {
  final dynamic data;
  final bool isError;
  final bool isDone;

  IsolateResponse(this.data, {this.isError = false, this.isDone = false});
}

void inferenceIsolateEntryPoint(SendPort mainSendPort) {
  final ReceivePort isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  LlamaBackend? backend;
  int? modelHandle;
  int? contextHandle;

  isolateReceivePort.listen((message) async {
    if (message is IsolateRequest) {
      try {
        switch (message.action) {
          case 'init':
            backend?.dispose();
            backend = LlamaBackend();
            final params = message.data['params'] as ModelParams;
            final path = message.data['path'] as String;
            
            modelHandle = await backend!.modelLoad(path, params);
            contextHandle = await backend!.contextCreate(modelHandle!, params);
            message.replyPort.send(IsolateResponse('ok'));
            break;

          case 'generate':
            if (backend == null || contextHandle == null) {
              message.replyPort.send(IsolateResponse('Not initialized', isError: true));
              break;
            }
            final prompt = message.data['prompt'] as String;
            final gParams = message.data['params'] as GenerationParams;
            
            await for (final chunk in backend!.generate(contextHandle!, prompt, gParams)) {
              if (chunk.isNotEmpty) {
                message.replyPort.send(IsolateResponse(utf8.decode(chunk)));
              }
            }
            message.replyPort.send(IsolateResponse(null, isDone: true));
            break;

          case 'cancel':
            backend?.cancelGeneration();
            break;

          case 'dispose':
            if (contextHandle != null) await backend?.contextFree(contextHandle!);
            if (modelHandle != null) await backend?.modelFree(modelHandle!);
            backend?.dispose();
            backend = null;
            modelHandle = null;
            contextHandle = null;
            break;
        }
      } catch (e) {
        message.replyPort.send(IsolateResponse(e.toString(), isError: true));
      }
    }
  });
}
