import 'package:flutter/material.dart';
import '../music.dart';
import 'theme.dart';

Future<void> addYouTubeLink(BuildContext context, FocusMusic music) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .5),
      builder: (_) => _YouTubeLinkDialog(music: music),
    );

class _YouTubeLinkDialog extends StatefulWidget {
  const _YouTubeLinkDialog({required this.music});
  final FocusMusic music;

  @override
  State<_YouTubeLinkDialog> createState() => _YouTubeLinkDialogState();
}

class _YouTubeLinkDialogState extends State<_YouTubeLinkDialog> {
  final form = GlobalKey<FormState>();
  final url = TextEditingController();
  final title = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    url.dispose();
    title.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    final saved = await widget.music.addYouTube(url.text, title: title.text);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.music.error ?? 'The link could not be saved. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      backgroundColor: StintColors.of(context).surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 404),
      title: const Text('Add a YouTube link'),
      content: SizedBox(
        width: 356,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A video or live stream. It plays in the menu bar timer panel and needs '
                  'an internet connection; Stint never downloads the audio.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('youtube-url'),
                  controller: url,
                  autofocus: true,
                  enabled: !saving,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Link',
                    hintText: 'https://www.youtube.com/watch?v=…',
                    errorMaxLines: 3,
                  ),
                  validator: (value) => (value?.trim() ?? '').isEmpty
                      ? 'Paste a YouTube link first.'
                      : youtubeVideoIdFromUrl(value!) == null
                      ? "That doesn't look like a YouTube video or live stream link."
                      : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('youtube-title'),
                  controller: title,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Shown in your sound list',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 120
                      ? 'Use 120 characters or fewer.'
                      : null,
                  onFieldSubmitted: (_) => save(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save link'),
        ),
      ],
    ),
  );
}
