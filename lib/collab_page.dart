import 'package:flutter/material.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:fleather/fleather.dart';

import './collab/collab_client.dart';
import './collab/collab_server.dart';

class CollabEditor extends StatefulWidget {
  final CollabServer server;
  final CollabClient client;
  final focusNode = FocusNode();

  CollabEditor({required int uid, required this.server, Key? key})
      : client = CollabClient(
            uid: uid, serverSync: server, doc: ParchmentDocument()),
        super(key: key);

  @override
  State<CollabEditor> createState() => _CollabEditorState();
}

class _CollabEditorState extends State<CollabEditor> {
  @override
  Widget build(BuildContext context) {
    return Container(
        child: Column(
      children: [
        CollabClientStatus(client: widget.client),
        Container(
            margin: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border.all(color: Colors.black)),
            child: FleatherEditor(
              controller: widget.client.controller,
              // expands: true,
              focusNode: widget.focusNode,
            )),
      ],
    ));
  }
}

class CollaborativeEditionDemo extends StatefulWidget {
  final CollabServer _server = CollabServer();

  CollaborativeEditionDemo({Key? key}) : super(key: key);

  @override
  CollaborativeEditionDemoState createState() =>
      CollaborativeEditionDemoState();
}

class CollaborativeEditionDemoState extends State<CollaborativeEditionDemo> {
  @override
  void initState() {
    super.initState();

    // setState(() {
    //   _controller = FleatherController(ParchmentDocument());
    // });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor page'),
      ),
      body: Column(children: <Widget>[
        CollabServerStatus(server: widget._server),
        const SizedBox(
          height: 16,
        ),
        CollabEditor(uid: 1, server: widget._server),
        const SizedBox(
          height: 16,
        ),
        CollabEditor(uid: 2, server: widget._server),
      ]),
    );
  }
}
