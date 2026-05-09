import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_provider.dart';

// ── Webhook URL ───────────────────────────────────────────────────────────────
// Points to the n8n Roster Upload webhook.  Change the base URL in Settings to
// redirect to a different n8n instance.
const _kWebhookUrl = 'https://n8n.captainparth.com/webhook/roster-upload';

// ── State machine ─────────────────────────────────────────────────────────────
enum _UploadState { idle, previewing, uploading, conflictReview, confirming, success, error }

// ── Conflict model ────────────────────────────────────────────────────────────
class _ConflictEntry {
  final String engineerName;
  final String date;
  final String oldShift;
  final String newShift;

  const _ConflictEntry({
    required this.engineerName,
    required this.date,
    required this.oldShift,
    required this.newShift,
  });

  factory _ConflictEntry.fromJson(Map<dynamic, dynamic> j) => _ConflictEntry(
        engineerName: j['engineer_name']?.toString() ?? '',
        date: j['date']?.toString() ?? '',
        oldShift: j['old_shift_type']?.toString() ?? '',
        newShift: j['new_shift_type']?.toString() ?? '',
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────
class RosterUploadScreen extends ConsumerStatefulWidget {
  const RosterUploadScreen({super.key});

  @override
  ConsumerState<RosterUploadScreen> createState() => _RosterUploadScreenState();
}

class _RosterUploadScreenState extends ConsumerState<RosterUploadScreen> {
  // colours — matching the app's dark theme
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _accent = Color(0xFF4FC3F7);
  static const _accentDark = Color(0xFF0288D1);
  static const _textPri = Colors.white;
  static const _textSec = Color(0xFFB0BEC5);
  static const _conflictRed = Color(0xFFEF5350);
  static const _successGreen = Color(0xFF66BB6A);

  final _picker = ImagePicker();
  final _dio = Dio();
  final _uuid = const Uuid();

  _UploadState _state = _UploadState.idle;
  File? _imageFile;
  String _errorMessage = '';
  String _successMessage = '';
  String _statusMessage = '';
  String _sessionId = '';
  List<_ConflictEntry> _conflicts = [];
  int _newEntriesInserted = 0;
  int _existingUnchanged = 0;

  // ── Camera ──────────────────────────────────────────────────────────────────
  Future<void> _captureImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _state = _UploadState.previewing;
    });
  }

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _state = _UploadState.previewing;
    });
  }

  // ── Upload ──────────────────────────────────────────────────────────────────
  Future<void> _uploadImage() async {
    if (_imageFile == null) return;

    setState(() {
      _state = _UploadState.uploading;
      _statusMessage = 'Sending image to OCR…';
    });

    try {
      final token = _getToken();
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = _imageFile!.path.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      _sessionId = _uuid.v4();

      setState(() => _statusMessage = 'Reading roster table…');

      final response = await _dio.post(
        _kWebhookUrl,
        data: {
          'action': 'upload',
          'token': token,
          'sessionId': _sessionId,
          'imageBase64': base64Image,
          'mimeType': mimeType,
        },
        options: Options(
          contentType: 'application/json',
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 60),
          validateStatus: (s) => true,
        ),
      );

      _handleUploadResponse(response.data);
    } on DioException catch (e) {
      _setError('Network error: ${e.message}');
    } catch (e) {
      _setError('Unexpected error: $e');
    }
  }

  void _handleUploadResponse(dynamic data) {
    final Map<dynamic, dynamic> body = data is Map
        ? data
        : (data is String ? jsonDecode(data) as Map : {});
    final status = body['status']?.toString() ?? '';

    if (status == 'success') {
      setState(() {
        _state = _UploadState.success;
        _successMessage = body['message']?.toString() ??
            '✅ Roster updated successfully!';
      });
    } else if (status == 'conflict') {
      final rawConflicts = body['conflicts'] as List? ?? [];
      setState(() {
        _state = _UploadState.conflictReview;
        _sessionId = body['sessionId']?.toString() ?? _sessionId;
        _conflicts = rawConflicts
            .map((c) => _ConflictEntry.fromJson(c as Map))
            .toList();
        _newEntriesInserted =
            (body['newEntriesInserted'] as num?)?.toInt() ?? 0;
        _existingUnchanged =
            (body['existingUnchanged'] as num?)?.toInt() ?? 0;
      });
    } else {
      _setError(body['message']?.toString() ?? 'OCR failed. Please retake the photo.');
    }
  }

  // ── Confirm / Reject ────────────────────────────────────────────────────────
  Future<void> _sendDecision(String decision) async {
    setState(() {
      _state = _UploadState.confirming;
      _statusMessage =
          decision == 'yes' ? 'Applying changes…' : 'Discarding changes…';
    });

    try {
      final token = _getToken();
      final response = await _dio.post(
        _kWebhookUrl,
        data: {
          'action': 'confirm',
          'token': token,
          'sessionId': _sessionId,
          'decision': decision,
        },
        options: Options(
          contentType: 'application/json',
          validateStatus: (s) => true,
        ),
      );

      final body = response.data is Map
          ? response.data as Map
          : (response.data is String ? jsonDecode(response.data as String) as Map : {});
      final status = body['status']?.toString() ?? '';
      if (status == 'success') {
        setState(() {
          _state = _UploadState.success;
          _successMessage =
              body['message']?.toString() ?? '✅ Roster updated!';
        });
      } else if (status == 'rejected') {
        setState(() {
          _state = _UploadState.success;
          _successMessage =
              body['message']?.toString() ?? '❌ Changes rejected.';
        });
      } else {
        _setError(body['message']?.toString() ?? 'Something went wrong.');
      }
    } on DioException catch (e) {
      _setError('Network error: ${e.message}');
    } catch (e) {
      _setError('Unexpected error: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _getToken() {
    final auth = ref.read(authProvider);
    return auth is AuthStateAuthenticated ? auth.accessToken : '';
  }

  void _setError(String msg) =>
      setState(() { _state = _UploadState.error; _errorMessage = msg; });

  void _reset() => setState(() {
        _state = _UploadState.idle;
        _imageFile = null;
        _conflicts = [];
        _errorMessage = '';
        _successMessage = '';
        _sessionId = '';
      });

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Roster Upload', style: TextStyle(color: _textPri)),
        iconTheme: const IconThemeData(color: _textPri),
        elevation: 0,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _UploadState.idle:
        return _buildIdle();
      case _UploadState.previewing:
        return _buildPreviewing();
      case _UploadState.uploading:
      case _UploadState.confirming:
        return _buildLoading();
      case _UploadState.conflictReview:
        return _buildConflictReview();
      case _UploadState.success:
        return _buildSuccess();
      case _UploadState.error:
        return _buildError();
    }
  }

  // ── Idle ──────────────────────────────────────────────────────────────────
  Widget _buildIdle() {
    return Center(
      key: const ValueKey('idle'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.document_scanner_outlined,
                size: 80, color: _accent),
            const SizedBox(height: 24),
            const Text(
              'Upload Roster Photo',
              style: TextStyle(color: _textPri, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Take a clear photo of the printed roster sheet.\nThe system will OCR and update the DB automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSec, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 40),
            _primaryButton(
              icon: Icons.camera_alt,
              label: 'Take Photo',
              onPressed: _captureImage,
            ),
            const SizedBox(height: 12),
            _secondaryButton(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Gallery',
              onPressed: _pickFromGallery,
            ),
          ],
        ),
      ),
    );
  }

  // ── Previewing ───────────────────────────────────────────────────────────
  Widget _buildPreviewing() {
    return Column(
      key: const ValueKey('previewing'),
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_imageFile!, fit: BoxFit.contain),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            children: [
              _primaryButton(
                icon: Icons.upload_rounded,
                label: 'Upload & Process',
                onPressed: _uploadImage,
              ),
              const SizedBox(height: 10),
              _secondaryButton(
                icon: Icons.refresh,
                label: 'Retake',
                onPressed: _captureImage,
              ),
              const SizedBox(height: 10),
              _secondaryButton(
                icon: Icons.photo_library_outlined,
                label: 'Choose Different',
                onPressed: _pickFromGallery,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return Center(
      key: const ValueKey('loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _accent),
          const SizedBox(height: 20),
          Text(
            _statusMessage,
            style: const TextStyle(color: _textSec, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ── Conflict Review ──────────────────────────────────────────────────────
  Widget _buildConflictReview() {
    return Column(
      key: const ValueKey('conflict'),
      children: [
        // Summary banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF2D1F07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber),
                SizedBox(width: 8),
                Text('Conflicts Detected',
                    style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              _summaryRow('New entries already inserted', '$_newEntriesInserted'),
              _summaryRow('Unchanged existing entries', '$_existingUnchanged'),
              _summaryRow(
                  'Conflicts needing approval', '${_conflicts.length}',
                  color: Colors.amber),
            ],
          ),
        ),
        // Conflict list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _conflicts.length,
            separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A2A)),
            itemBuilder: (_, i) => _conflictTile(_conflicts[i]),
          ),
        ),
        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              const Text(
                'Approving will update the conflicting shifts in the DB.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textSec, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _successGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirm & Apply',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _sendDecision('yes'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _conflictRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _sendDecision('no'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conflictTile(_ConflictEntry c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.engineerName,
                style: const TextStyle(color: _textPri, fontWeight: FontWeight.w600)),
            Text(c.date, style: const TextStyle(color: _textSec, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6)),
          child: Text(c.oldShift,
              style: const TextStyle(color: _conflictRed, fontWeight: FontWeight.bold)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward, size: 16, color: _textSec),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF1A2A1A),
              borderRadius: BorderRadius.circular(6)),
          child: Text(c.newShift,
              style: const TextStyle(color: _successGreen, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _textSec, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color ?? _textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }

  // ── Success ──────────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final isRejected = _successMessage.startsWith('❌');
    return Center(
      key: const ValueKey('success'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRejected ? Icons.cancel_outlined : Icons.check_circle_outline,
              size: 72,
              color: isRejected ? _conflictRed : _successGreen,
            ),
            const SizedBox(height: 20),
            Text(
              _successMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textPri, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),
            _primaryButton(
              icon: Icons.upload_rounded,
              label: 'Upload Another',
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: _conflictRed),
            const SizedBox(height: 16),
            const Text('Something went wrong',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textSec, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            _primaryButton(
              icon: Icons.refresh,
              label: 'Try Again',
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared button styles ─────────────────────────────────────────────────
  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: _accent),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 14)),
        onPressed: onPressed,
      ),
    );
  }
}
