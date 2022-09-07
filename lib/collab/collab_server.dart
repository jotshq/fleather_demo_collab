import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quill_delta/quill_delta.dart';

class Op {
  final Delta delta;
  final int uid;
  final int rev;

  // local only
  bool sent = false;

  Op({required this.delta, required this.rev, required this.uid});
}

abstract class CollabServerSync {
  int get rev;

  bool pushOps(Iterable<Op> newOps);
  Stream<List<Op>> get changes;
}

// fake backend server for collab
class CollabServer extends ChangeNotifier implements CollabServerSync {
  final ops = <Op>[];
  int rejected = 0;
  final opsStreamController = StreamController<List<Op>>.broadcast();

  @override
  int get rev {
    return ops.isNotEmpty ? ops.last.rev : -1;
  }

  // returns the last accepted revision, -1 on error
  @override
  bool pushOps(Iterable<Op> newOps) {
    if (newOps.isEmpty) return true;

    int resultRev = rev;
    for (final newOp in newOps) {
      if (newOp.rev != resultRev + 1) {
        rejected = rejected + 1;
        notifyListeners();
        return false;
      }
      resultRev = newOp.rev;
    }

    ops.addAll(newOps);
    opsStreamController.add(newOps.toList());
    notifyListeners();
    return true;
  }

  @override
  Stream<List<Op>> get changes {
    return opsStreamController.stream;
  }
}

class CollabServerStatus extends StatelessWidget {
  final CollabServer server;
  const CollabServerStatus({required this.server, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: server,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(16),
        child: Text(
            'Server operations: ${server.ops.length} - Last rev: ${server.rev} - Rejected changes: ${server.rejected}'),
      ),
    );
  }
}
