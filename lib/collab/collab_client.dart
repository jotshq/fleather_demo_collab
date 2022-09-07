import 'dart:async';
import 'dart:math';

import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:quill_delta/quill_delta.dart';
import './collab_server.dart';

class CollabClient extends ChangeNotifier {
  final FleatherController controller;
  final CollabServerSync serverSync;
  bool paused = false;
  final int uid;

  // the server history of the document
  final committed = <Op>[];

  // the queue of local uncommitted changes
  final queue = <Op>[];

  // if we pause the server changes actually comes here
  final serverSyncQueue = <Op>[];

  late StreamSubscription<ParchmentChange> docSub;
  late StreamSubscription<List<Op>> serverSyncSub;

  CollabClient(
      {required this.uid,
      required this.serverSync,
      required ParchmentDocument doc})
      : controller = FleatherController(doc) {
    docSub = controller.document.changes.listen(recvLocalChange);
    serverSyncSub = serverSync.changes.listen(recvServerChanges);
  }

  @override
  void dispose() {
    docSub.cancel();
    serverSyncSub.cancel();
    super.dispose();
  }

  // receiving local changes from the text editor
  void recvLocalChange(ParchmentChange change) {
    if (change.source == ChangeSource.remote) return;
    queue.add(Op(uid: uid, rev: nextRev, delta: change.change));
    notifyListeners();
    sync();
  }

  // receiving remote changes from other editors
  void recvServerChanges(List<Op> ops) {
    if (paused) {
      serverSyncQueue.addAll(ops);
      return;
    }

    if (ops.isEmpty) return;

    committed.addAll(ops);

    // filter out all operations that were not created by us
    var otherOps = ops.skipWhile((op) => op.uid == uid);

    // count the number of operations that are coming from our client
    var validatedCount = ops.length - otherOps.length;

    // cleanup our queue with what have been committed
    // NOTE: We do not check is sent is true or not because some changes
    // may have been accepted by the server, without being marked sent locally
    queue.removeRange(0, validatedCount);

    if (otherOps.isEmpty) {
      notifyListeners();
      return;
    }

    // compose together all the new changes the editor never saw
    final remoteDelta =
        otherOps.map((e) => e.delta).reduce((a, b) => a.compose(b));

    // rebase them on top of the local uncommitted changes
    final newDelta = queue.fold<Delta>(
        remoteDelta, (res, op) => op.delta.transform(res, true));
    // apply them on the editor
    controller.compose(newDelta);

    // rebase our queue of uncommitted changes
    rebase(remoteDelta, committed.last.rev);
    sync();
    notifyListeners();
  }

  // OT convergence highly inspired by the wonderfully written CodeMirror collab plugin
  // https://github.com/codemirror/collab/blob/main/src/collab.ts
  void rebase(Delta otherDelta, int remoteRev) {
    var stackedChanges = otherDelta;

    // for each operation in the uncommitted queue of changes
    for (var opIndex = 0; opIndex < queue.length; opIndex += 1) {
      final op = queue[opIndex];

      // rebase the current queue operation on top of stackedChanges
      // stackedChanges = otherDelta + queue[0..op.rev-1]
      final updatedDelta = stackedChanges.transform(op.delta, false);

      // update stackedChanges to include the current delta
      stackedChanges = updatedDelta.transform(stackedChanges, true);

      queue[opIndex] =
          Op(delta: updatedDelta, uid: op.uid, rev: remoteRev + opIndex + 1);
    }
  }

  int get nextRev {
    var queueRev = 0, committedRev = 0;
    if (queue.isNotEmpty) queueRev = queue.last.rev + 1;
    if (committed.isNotEmpty) committedRev = committed.last.rev + 1;
    return max(queueRev, committedRev);
  }

  void togglePause() {
    paused = !paused;
    if (paused == false && serverSyncQueue.isNotEmpty) {
      final queuedChanges = [...serverSyncQueue];
      serverSyncQueue.clear();
      recvServerChanges(queuedChanges);
    }
    notifyListeners();
    sync();
  }

  void sync() {
    if (paused == true) return;

    final toPush = queue.skipWhile((op) => op.sent);
    final synced = serverSync.pushOps(toPush);
    if (synced) {
      for (final op in toPush) {
        op.sent = true;
      }
    }
    notifyListeners();
  }
}

class CollabOperationsList extends StatelessWidget {
  final CollabClient client;
  const CollabOperationsList({required this.client, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: client,
        builder: (context, _) {
          return SizedBox(
              height: 128,
              child: ListView.builder(
                  controller: ScrollController(),
                  itemCount: client.queue.length,
                  itemBuilder: ((context, index) {
                    final op = client.queue[index];
                    return ListTile(
                        title: Text(op.delta.toString()),
                        subtitle: Text('${op.rev} - sent: ${op.sent}'));
                  })));
        });
  }
}

class CollabClientStatus extends StatelessWidget {
  final CollabClient client;
  const CollabClientStatus({required this.client, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: client,
        builder: (context, _) {
          final sent = client.queue.fold(0, (i, op) => i + (op.sent ? 1 : 0));

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                        'Committed: ${client.committed.length} Queued: $sent / ${client.queue.length} - nextRev: ${client.nextRev}'),
                    IconButton(
                        onPressed: () => client.togglePause(),
                        icon: client.paused
                            ? const Icon(Icons.play_arrow)
                            : const Icon(Icons.pause))
                  ],
                ),
                CollabOperationsList(client: client),
              ],
            ),
          );
        });
  }
}
