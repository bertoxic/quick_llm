import 'package:flutter/material.dart';

class QuickPromptsDialog extends StatefulWidget {
  final List<String> quickPrompts;
  final Function(List<String>) onPromptsChanged;

  const QuickPromptsDialog({
    super.key,
    required this.quickPrompts,
    required this.onPromptsChanged,
  });

  @override
  State<QuickPromptsDialog> createState() => _QuickPromptsDialogState();
}

class _QuickPromptsDialogState extends State<QuickPromptsDialog> {
  final TextEditingController _controller = TextEditingController();
  late List<String> _prompts;

  @override
  void initState() {
    super.initState();
    _prompts = List.from(widget.quickPrompts);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addPrompt() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        _prompts.add(_controller.text);
      });
      widget.onPromptsChanged(_prompts);
      _controller.clear();
    }
  }

  void _deletePrompt(int index) {
    setState(() {
      _prompts.removeAt(index);
    });
    widget.onPromptsChanged(_prompts);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick Prompts'),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Add new quick prompt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _addPrompt,
              child: const Text('Add'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _prompts.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_prompts[index]),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deletePrompt(index),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}