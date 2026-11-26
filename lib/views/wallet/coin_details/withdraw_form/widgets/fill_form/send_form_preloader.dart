import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class FillFormPreloader extends StatelessWidget {
  const FillFormPreloader([this.message]);

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const UiSpinner(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
