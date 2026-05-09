import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/tile_model.dart';
import '../../core/tsg_auth/tsg_auth_service.dart';

class TileForm extends ConsumerStatefulWidget {
  final TileModel? existing;
  final VoidCallback onSaved;

  const TileForm({super.key, this.existing, required this.onSaved});

  @override
  ConsumerState<TileForm> createState() => _TileFormState();
}

class _TileFormState extends ConsumerState<TileForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _slugCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _iconCtrl;
  late TextEditingController _descCtrl;
  String _quickPanel = 'none';  // 'none' | 'roster' | 'time' | 'date'
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nameCtrl = TextEditingController(text: t?.name ?? '');
    _slugCtrl = TextEditingController(text: t?.slug ?? '');
    _urlCtrl = TextEditingController(text: t?.launchUrl ?? '');
    _iconCtrl = TextEditingController(text: t?.iconUrl ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _quickPanel = t?.quickPanel ?? 'none';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _urlCtrl.dispose();
    _iconCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;

    try {
      if (widget.existing == null) {
        await TsgAuthService.createTile(
          accessToken: auth.accessToken,
          name: _nameCtrl.text.trim(),
          slug: _slugCtrl.text.trim(),
          launchUrl: _urlCtrl.text.trim(),
          iconUrl: _iconCtrl.text.trim().isEmpty ? null : _iconCtrl.text.trim(),
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          quickPanel: _quickPanel == 'none' ? null : _quickPanel,
        );
      } else {
        await TsgAuthService.updateTile(
          accessToken: auth.accessToken,
          slug: widget.existing!.slug,
          fields: {
            'name': _nameCtrl.text.trim(),
            'meta_launch_url': _urlCtrl.text.trim(),
            if (_iconCtrl.text.trim().isNotEmpty)
              'meta_icon': _iconCtrl.text.trim(),
            if (_descCtrl.text.trim().isNotEmpty)
              'meta_description': _descCtrl.text.trim(),
            'quick_panel': _quickPanel == 'none' ? null : _quickPanel,
          },
        );
      }
      widget.onSaved();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Tile' : 'New Tile'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            TextButton(
                onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Display Name *', border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            if (!isEditing) ...[
              TextFormField(
                controller: _slugCtrl,
                decoration: const InputDecoration(
                    labelText: 'Slug (URL key) *',
                    border: OutlineInputBorder(),
                    helperText: 'Lowercase, hyphens only. e.g. my-app'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v.trim())) {
                    return 'Lowercase letters, numbers, hyphens only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                  labelText: 'Launch URL *', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme) return 'Enter a valid URL';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _iconCtrl,
              decoration: const InputDecoration(
                  labelText: 'Icon URL (optional)',
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            // ── Quick Panel dropdown ─────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _quickPanel,
              decoration: const InputDecoration(
                labelText: 'Quick Panel',
                border: OutlineInputBorder(),
                helperText:
                    'Optional live data shown on the tile instead of the icon.',
              ),
              items: const [
                DropdownMenuItem(value: 'none',   child: Text('None (standard tile)')),
                DropdownMenuItem(value: 'roster', child: Text('Roster — today\'s shift schedule')),
                DropdownMenuItem(value: 'time',   child: Text('Time — live clock (hh:mm)')),
                DropdownMenuItem(value: 'date',   child: Text('Date — today\'s date (dd-mmm)')),
              ],
              onChanged: (v) => setState(() => _quickPanel = v ?? 'none'),
            ),
          ],
        ),
      ),
    );
  }
}
